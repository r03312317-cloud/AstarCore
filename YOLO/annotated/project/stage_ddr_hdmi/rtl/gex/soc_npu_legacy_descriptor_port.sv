// 架构导读：soc_npu_legacy_descriptor_port。
// 将卷积服务的描述符转换为既有 NPU 控制接口事务。
`timescale 1ns/1ps
// A bounded hardware client of the existing NPU register ABI. There is one
// unchanged NPU/Scheduler/DMA behind this port. Completion is read only from
// that NPU's real completion queue after its realR/B retirement contract.
// The enclosing owner mux must exclude CPU writes for the whole Conv job.
module soc_npu_legacy_descriptor_port(
 // 接口声明：input logic clk,rst,enable,clear_counters。
 // 记录数量或剩余进度，位宽限定可表达范围。
 input logic clk,rst,enable,clear_counters,
 // 接口声明：input logic cmd_valid,output logic cmd_ready,input npu_defs_pkg::npu_cmd_t cmd。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic cmd_valid,output logic cmd_ready,input npu_defs_pkg::npu_cmd_t cmd,
 // 接口声明：output logic comp_valid,input logic comp_ready,output npu_defs_pkg::npu_completion_t comp。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic comp_valid,input logic comp_ready,output npu_defs_pkg::npu_completion_t comp,
 // 接口声明：output logic [31:0] legacy_addr,legacy_wdata。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 output logic [31:0] legacy_addr,legacy_wdata,
 // 接口声明：output logic legacy_wen,output logic [1:0] legacy_mask,input logic [31:0] legacy_rdata。
 output logic legacy_wen,output logic [1:0] legacy_mask,input logic [31:0] legacy_rdata,
 output logic busy,protocol_poison,output logic [31:0] completed_service_cycles,total_command_ticks
);
 import npu_defs_pkg::*;
 typedef enum logic [3:0] {IDLE,CHECK_WAIT1,CHECK_WAIT2,CHECK_READ,SETUP,
  POLL_WAIT1,POLL_WAIT2,POLL_READ,RESULT_WAIT1,RESULT_WAIT2,RESULT_READ,
  POP_HEAD,CLEAR_IRQ,HOLD_RESULT,POISON} state_t;
 state_t state;
 npu_cmd_t cmd_q;npu_completion_t comp_q;
 logic [4:0] word_q;
 logic [2:0] result_q;
 logic [31:0] error_status_q;
 logic [31:0] job_ticks;
 // 静态配置：localparam logic [31:0] BASE=32'h80200200。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam logic [31:0] BASE=32'h80200200;
 assign cmd_ready=!rst&&enable&&state==IDLE&&!protocol_poison;
 assign comp_valid=!rst&&state==HOLD_RESULT&&!protocol_poison;
 assign comp=comp_q;assign busy=state!=IDLE;
 assign legacy_mask=2;
 // 过程边界：always_comb begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_comb begin
  legacy_addr=BASE+32'h0c;legacy_wdata=0;legacy_wen=0;
  if(state==SETUP)begin
   legacy_wen=1;
   // 按 word_q 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case(word_q)
    0:begin legacy_addr=BASE+32'h14;legacy_wdata=3;end
    1:begin legacy_addr=BASE+32'h78;legacy_wdata=32'hfff;end
    2:begin legacy_addr=BASE+32'h10;legacy_wdata=3;end
    3:begin legacy_addr=BASE+32'h20;legacy_wdata=cmd_q.a_base;end
    4:begin legacy_addr=BASE+32'h24;legacy_wdata=cmd_q.b_base;end
    5:begin legacy_addr=BASE+32'h28;legacy_wdata=cmd_q.c_base;end
    6:begin legacy_addr=BASE+32'h2c;legacy_wdata={cmd_q.n,cmd_q.m};end
    7:begin legacy_addr=BASE+32'h30;legacy_wdata={15'd0,cmd_q.input_int16,cmd_q.k};end
    8:begin legacy_addr=BASE+32'h34;legacy_wdata=cmd_q.a_stride;end
    9:begin legacy_addr=BASE+32'h38;legacy_wdata=cmd_q.b_stride;end
    10:begin legacy_addr=BASE+32'h3c;legacy_wdata=cmd_q.c_stride;end
    11:begin legacy_addr=BASE+32'h40;legacy_wdata={21'd0,cmd_q.shift,cmd_q.rounding,cmd_q.activation,cmd_q.output_fmt};end
    12:begin legacy_addr=BASE+32'h44;legacy_wdata=cmd_q.clamp_min;end
    13:begin legacy_addr=BASE+32'h48;legacy_wdata=cmd_q.clamp_max;end
    14:begin legacy_addr=BASE+32'h4c;legacy_wdata=cmd_q.user_tag;end
    15:begin legacy_addr=BASE+32'h50;legacy_wdata=1;end
    default:legacy_wen=0;
   endcase
  end
  if(state==RESULT_WAIT1||state==RESULT_WAIT2||state==RESULT_READ)
   legacy_addr=result_q==5?BASE+32'h78:BASE+32'h60+{27'd0,result_q,2'd0};
  if(state==POP_HEAD)begin legacy_addr=BASE+32'h74;legacy_wdata=1;legacy_wen=1;end
  if(state==CLEAR_IRQ)begin legacy_addr=BASE+32'h14;legacy_wdata=3;legacy_wen=1;end
  // 复位相关判断：!enable||rst||protocol_poison；分支方向由信号极性与取反表达式决定。
  if(!enable||rst||protocol_poison)legacy_wen=0;
 end
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin state<=IDLE;cmd_q<='0;comp_q<='0;word_q<=0;result_q<=0;error_status_q<=0;protocol_poison<=0;completed_service_cycles<=0;total_command_ticks<=0;job_ticks<=0;end
  else begin
   if(state!=IDLE&&state!=HOLD_RESULT&&state!=POISON)job_ticks<=job_ticks+1'b1;
   if(!enable&&state!=IDLE)begin protocol_poison<=1;state<=POISON;end
   else case(state)
    // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
    IDLE:if(cmd_valid&&cmd_ready)begin cmd_q<=cmd;comp_q<='0;error_status_q<=0;job_ticks<=0;state<=CHECK_WAIT1;end
    // 状态/选择分支 CHECK_WAIT1：本分支规定该编码下的寄存器更新和下一步动作。
    CHECK_WAIT1:state<=CHECK_WAIT2;
    // 状态/选择分支 CHECK_WAIT2：本分支规定该编码下的寄存器更新和下一步动作。
    CHECK_WAIT2:state<=CHECK_READ;
    // 状态/选择分支 CHECK_READ：本分支规定该编码下的寄存器更新和下一步动作。
    CHECK_READ:if((legacy_rdata&32'h47)!=5)begin protocol_poison<=1;state<=POISON;end
     else begin word_q<=0;state<=SETUP;end
    // 状态/选择分支 SETUP：本分支规定该编码下的寄存器更新和下一步动作。
    SETUP:if(word_q==15)state<=POLL_WAIT1;else word_q<=word_q+1'b1;
    // 状态/选择分支 POLL_WAIT1：本分支规定该编码下的寄存器更新和下一步动作。
    POLL_WAIT1:state<=POLL_WAIT2;
    // 状态/选择分支 POLL_WAIT2：本分支规定该编码下的寄存器更新和下一步动作。
    POLL_WAIT2:state<=POLL_READ;
    // 状态/选择分支 POLL_READ：本分支规定该编码下的寄存器更新和下一步动作。
    POLL_READ:if(legacy_rdata[6])begin result_q<=0;state<=RESULT_WAIT1;end else state<=POLL_WAIT1;
    // 状态/选择分支 RESULT_WAIT1：本分支规定该编码下的寄存器更新和下一步动作。
    RESULT_WAIT1:state<=RESULT_WAIT2;
    // 状态/选择分支 RESULT_WAIT2：本分支规定该编码下的寄存器更新和下一步动作。
    RESULT_WAIT2:state<=RESULT_READ;
    // 状态/选择分支 RESULT_READ：本分支规定该编码下的寄存器更新和下一步动作。
    RESULT_READ:begin
     // 按 result_q 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
     case(result_q)
      0:comp_q.user_tag<=legacy_rdata;
      1:begin
       comp_q.error<=npu_error_e'(legacy_rdata[7:0]);comp_q.partial_output<=legacy_rdata[8];
       // Preserve the old CPUdriver's fail-closed fullstatusword check:
       // partial-without-error or nonzero reservedbits cannot mean success.
       if((legacy_rdata[8]&&legacy_rdata[7:0]==0)||legacy_rdata[31:9]!=0)comp_q.error<=ERR_INTERNAL_PROTOCOL;
      end
      2:comp_q.cycles<=legacy_rdata;
      3:comp_q.macs[31:0]<=legacy_rdata;
      4:comp_q.macs[63:32]<=legacy_rdata;
      5:begin error_status_q<=legacy_rdata;if(legacy_rdata!=0&&comp_q.error==ERR_NONE)comp_q.error<=ERR_INTERNAL_PROTOCOL;end
      default:begin protocol_poison<=1;state<=POISON;end
     endcase
     if(result_q==5)state<=POP_HEAD;else begin result_q<=result_q+1'b1;state<=RESULT_WAIT1;end
    end
    // 状态/选择分支 POP_HEAD：本分支规定该编码下的寄存器更新和下一步动作。
    POP_HEAD:state<=CLEAR_IRQ;
    // 状态/选择分支 CLEAR_IRQ：本分支规定该编码下的寄存器更新和下一步动作。
    CLEAR_IRQ:begin completed_service_cycles<=completed_service_cycles+comp_q.cycles;state<=HOLD_RESULT;end
    // 状态/选择分支 HOLD_RESULT：本分支规定该编码下的寄存器更新和下一步动作。
    HOLD_RESULT:if(comp_ready)begin state<=IDLE;total_command_ticks<=total_command_ticks+job_ticks;end
    POISON:;
    default:begin protocol_poison<=1;state<=POISON;end
   endcase
   if(clear_counters)begin
    if(state!=IDLE)begin protocol_poison<=1;state<=POISON;end
    else begin completed_service_cycles<=0;total_command_ticks<=0;job_ticks<=0;end
   end
  end
 end
 // synthesis translate_off
 always_ff @(posedge clk)if(!rst&&comp_valid&&error_status_q!=0&&comp_q.error==ERR_NONE)
  $fatal(1,"GEX_LEGACY_ERROR_WAS_IGNORED_RED");
 // synthesis translate_on
endmodule
