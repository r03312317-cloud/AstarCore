// 架构导读：npu_resident_fill_owner。
// 跟踪驻留操作数填充所有权，限制生产和使用同一存储区域的交叠。
`timescale 1ns/1ps
// Bounded fill phase of the existing Scheduler, NOT a secondScheduler/DMA.
// Acquires an exact-generation operandbank, reuses it or feeds ONE existing
// DMA plus packer, then commits only after genuine R/B retirement. Current
// readjob drains on cancellation; no response is synthesized or discarded
// before the existing DMA's classification. INT16 remains the legacy path.
module npu_resident_fill_owner #(
 // 静态配置：parameter logic [31:0] DRAM_BASE=32'h80000000。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter logic [31:0] DRAM_BASE=32'h80000000,
 // 静态配置：parameter logic [32:0] DRAM_BYTES=33'h004000000。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter logic [32:0] DRAM_BYTES=33'h004000000,
 // 静态配置：parameter int B_PAIR_WORDS=8192。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter int B_PAIR_WORDS=8192
)(
 // 接口声明：input logic clk,rst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic clk,rst,
 // 接口声明：input logic start_valid,output logic start_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic start_valid,output logic start_ready,
 // 接口声明：input logic start_is_b,start_a_slot。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic start_is_b,start_a_slot,
 // 接口声明：input logic [31:0] start_base,start_model_epoch,start_frame_epoch,start_tensor,start_generation。
 // 区分任务或数据代次，用于拒绝旧上下文的完成/释放。
 input logic [31:0] start_base,start_model_epoch,start_frame_epoch,start_tensor,start_generation,
 // 接口声明：input logic [5:0] start_A_rows,input logic [8:0] start_B_columns,input logic [10:0] start_K。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [5:0] start_A_rows,input logic [8:0] start_B_columns,input logic [10:0] start_K,
 // 接口声明：input logic cancel。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic cancel,
 // Grant is an exclusive phase in the enclosing ONE-DMA arbiter. Hold it
 // until completion or coordinated reset. No other client may issue a job.
 input logic DMA_exclusive_grant,
 // 接口声明：output logic dma_job_valid,input logic dma_job_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 output logic dma_job_valid,input logic dma_job_ready,
 // 接口声明：output npu_defs_pkg::npu_dma_job_t dma_job。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output npu_defs_pkg::npu_dma_job_t dma_job,
 // 接口声明：input logic dma_job_done,dma_job_error,input npu_defs_pkg::npu_error_e dma_error_code。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 input logic dma_job_done,dma_job_error,input npu_defs_pkg::npu_error_e dma_error_code,
 input logic [4:0] dma_outstanding,
 input logic response_order_idle,response_order_poison,
 output logic pack_start,input logic pack_start_ready,
 output logic pack_is_b,output logic [5:0] pack_A_rows,
 output logic [8:0] pack_B_columns,output logic [10:0] pack_K,
 output logic pack_abort_request,pack_abort_retire,pack_real_retired,
 input logic pack_active,pack_done,pack_aborted,pack_poison,
 output logic bank_a_begin,bank_b_begin,bank_a_slot,
 output logic [255:0] bank_identity,
 output logic [5:0] bank_A_rows,output logic [8:0] bank_B_columns,output logic [10:0] bank_K,
 input logic bank_a_begin_ready,bank_b_begin_ready,bank_a_reuse_hit,bank_b_reuse_hit,
 output logic bank_a_commit,bank_b_commit,bank_real_retired,bank_a_abort,bank_b_abort,
 input logic bank_poison,
 output logic busy,done,reused,cancelled,protocol_poison,
 output npu_defs_pkg::npu_error_e error_code
);
 import npu_defs_pkg::*;
 typedef enum logic [3:0] {IDLE,ACQUIRE,CHECK_HIT,START_WORK,WAIT_WORK,
  DRAIN_ABORT,ABORT_BANK,COMMIT_BANK,CHECK_BANK,COMPLETE,QUARANTINE} state_t;
 state_t state;
 logic is_b,slot,cancel_q,dma_seen,pack_seen,pack_abort_seen,work_started;
 logic [31:0] base;
 logic [5:0] nr;logic [8:0] nc;logic [10:0] kl;
 logic [18:0] B_bytes;
 wire [18:0] start_payload=start_is_b?19'(start_B_columns)*19'(start_K):19'(start_A_rows)*19'(start_K);
 wire [32:0] start_end=({1'b0,start_base}+33'(start_payload)+33'd15)&~33'd15;
 wire [16:0] start_B_pairwords=17'(({1'b0,start_B_columns}+10'd7)>>3)*17'(({1'b0,start_K}+12'd1)>>1);
 wire start_shape=start_K!=0&&start_K<=1152&&
  (start_is_b?(start_B_columns!=0&&start_B_columns<=256&&start_B_pairwords<=B_PAIR_WORDS):
              (start_A_rows!=0&&start_A_rows<=16));
 wire start_address={1'b0,start_base}>={1'b0,DRAM_BASE}&&start_end<={1'b0,DRAM_BASE}+DRAM_BYTES&&
  start_end>={1'b0,start_base}&&(!start_is_b||start_base[3:0]==0);
 wire bank_ready=is_b?bank_b_begin_ready:bank_a_begin_ready;
 wire bank_hit=is_b?bank_b_reuse_hit:bank_a_reuse_hit;
 wire real_retired=dma_seen&&dma_job_ready&&dma_outstanding==0&&response_order_idle;
 wire aborting=cancel_q||cancel||error_code!=ERR_NONE;
 assign busy=state!=IDLE;
 assign start_ready=!rst&&state==IDLE&&!protocol_poison&&DMA_exclusive_grant&&dma_job_ready&&response_order_idle;
 assign bank_a_slot=slot;
 assign bank_A_rows=nr;assign bank_B_columns=nc;assign bank_K=kl;
 // Bank begin/commit ports are command strobes, not heldvalid inputs.
 // Wait without asserting a command while another compute owns that bank.
 assign bank_a_begin=state==ACQUIRE&&!is_b&&!cancel_q&&!cancel&&bank_a_begin_ready;
 assign bank_b_begin=state==ACQUIRE&&is_b&&!cancel_q&&!cancel&&bank_b_begin_ready;
 assign pack_is_b=is_b;assign pack_A_rows=nr;assign pack_B_columns=nc;assign pack_K=kl;
 // Atomic ready/valid start, independent ready signals from fixed clients.
 assign pack_start=state==START_WORK&&!aborting&&DMA_exclusive_grant&&dma_job_ready;
 assign dma_job_valid=state==START_WORK&&!aborting&&DMA_exclusive_grant&&pack_start_ready;
 // 过程边界：always_comb begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_comb begin
  dma_job='0;dma_job.kind=DMA_LOAD_A;dma_job.base=base;dma_job.elem_bytes=1;dma_job.bank=slot;
  if(is_b)begin dma_job.rows=16'((B_bytes+19'd15)>>4);dma_job.cols=16;dma_job.row_stride=16;end
  else begin dma_job.rows=16'(nr);dma_job.cols=16'(kl);dma_job.row_stride=32'(kl);end
 end
 assign pack_abort_request=state==DRAIN_ABORT||state==QUARANTINE;
 assign pack_real_retired=real_retired;
 assign pack_abort_retire=state==DRAIN_ABORT&&real_retired&&pack_active&&!pack_abort_seen;
 assign bank_real_retired=real_retired;
 assign bank_a_commit=state==COMMIT_BANK&&!is_b;
 assign bank_b_commit=state==COMMIT_BANK&&is_b;
 assign bank_a_abort=state==ABORT_BANK&&!is_b;
 assign bank_b_abort=state==ABORT_BANK&&is_b;
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  done<=0;
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin
   state<=IDLE;is_b<=0;slot<=0;cancel_q<=0;dma_seen<=0;pack_seen<=0;pack_abort_seen<=0;work_started<=0;
   base<=0;nr<=0;nc<=0;kl<=0;B_bytes<=0;bank_identity<=0;
   reused<=0;cancelled<=0;protocol_poison<=0;error_code<=ERR_NONE;
  end else begin
   if(busy&&cancel)cancel_q<=1;
   // Legacy DMA has mutually exclusive terminal done(success)/error(failure) pulses.
   if((dma_job_done||dma_job_error)&&work_started)begin
    dma_seen<=1;
    if(dma_job_error)error_code<=dma_error_code==ERR_NONE?ERR_INTERNAL_PROTOCOL:dma_error_code;
   end
   if(pack_done&&work_started)pack_seen<=1;
   if(pack_aborted&&work_started)pack_abort_seen<=1;
   if(busy&&(!DMA_exclusive_grant||response_order_poison||pack_poison||bank_poison))begin
    state<=QUARANTINE;protocol_poison<=1;error_code<=ERR_INTERNAL_PROTOCOL;
   end else case(state)
    // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
    IDLE:if(start_valid&&start_ready)begin
     is_b<=start_is_b;slot<=start_a_slot;base<=start_base;nr<=start_is_b?0:start_A_rows;nc<=start_is_b?start_B_columns:0;kl<=start_K;
     B_bytes<=19'(start_B_columns)*19'(start_K);
     bank_identity<={start_model_epoch,start_frame_epoch,start_tensor,start_generation,start_base,
                      32'(start_K),32'(start_is_b?start_B_columns:9'd0),32'(start_is_b?6'd0:start_A_rows)};
     cancel_q<=cancel;cancelled<=0;reused<=0;error_code<=ERR_NONE;
     dma_seen<=0;pack_seen<=0;pack_abort_seen<=0;work_started<=0;
     if(!start_shape||start_model_epoch==0||start_generation==0)begin error_code<=ERR_INVALID_DIM;state<=COMPLETE;end
     else if(!start_address)begin error_code<=start_is_b&&start_base[3:0]!=0?ERR_MISALIGNED:ERR_ADDRESS_RANGE;state<=COMPLETE;end
     else if(cancel)begin cancelled<=1;state<=COMPLETE;end
     else state<=ACQUIRE;
    end
    // 状态/选择分支 ACQUIRE：本分支规定该编码下的寄存器更新和下一步动作。
    ACQUIRE:if(cancel_q||cancel)begin cancelled<=1;state<=COMPLETE;end
      else if(bank_ready)state<=CHECK_HIT;
    // 状态/选择分支 CHECK_HIT：本分支规定该编码下的寄存器更新和下一步动作。
    CHECK_HIT:if(bank_hit)begin reused<=1;cancelled<=cancel_q||cancel;state<=COMPLETE;end
      else if(cancel_q||cancel)begin cancelled<=1;state<=ABORT_BANK;end
      else state<=START_WORK;
    // 状态/选择分支 START_WORK：本分支规定该编码下的寄存器更新和下一步动作。
    START_WORK:if(cancel_q||cancel)begin cancelled<=1;state<=ABORT_BANK;end
      else if(dma_job_ready&&pack_start_ready&&DMA_exclusive_grant)begin state<=WAIT_WORK;work_started<=1;end
    // 状态/选择分支 WAIT_WORK：本分支规定该编码下的寄存器更新和下一步动作。
    WAIT_WORK:begin
     if(aborting||dma_job_error)begin cancelled<=cancel_q||cancel;state<=DRAIN_ABORT;end
     else if(real_retired&&pack_seen&&!pack_active)state<=COMMIT_BANK;
    end
    // 状态/选择分支 DRAIN_ABORT：本分支规定该编码下的寄存器更新和下一步动作。
    DRAIN_ABORT:if(real_retired&&(pack_abort_seen||!pack_active))state<=ABORT_BANK;
    // 状态/选择分支 ABORT_BANK：本分支规定该编码下的寄存器更新和下一步动作。
    ABORT_BANK:state<=CHECK_BANK;
    // 状态/选择分支 COMMIT_BANK：本分支规定该编码下的寄存器更新和下一步动作。
    COMMIT_BANK:state<=CHECK_BANK;
    // 状态/选择分支 CHECK_BANK：本分支规定该编码下的寄存器更新和下一步动作。
    CHECK_BANK:state<=COMPLETE;
    // 状态/选择分支 COMPLETE：本分支规定该编码下的寄存器更新和下一步动作。
    COMPLETE:begin done<=1;cancelled<=cancelled||cancel_q||cancel;state<=IDLE;work_started<=0;end
    // 状态/选择分支 QUARANTINE：本分支规定该编码下的寄存器更新和下一步动作。
    QUARANTINE:begin end
    default:begin state<=QUARANTINE;protocol_poison<=1;error_code<=ERR_INTERNAL_PROTOCOL;end
   endcase
  end
 end
endmodule
