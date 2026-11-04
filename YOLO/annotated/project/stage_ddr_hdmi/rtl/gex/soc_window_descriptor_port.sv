// 架构导读：soc_window_descriptor_port。
// Window 描述符接口，提交采样参数并检查对应任务的完成状态。
`timescale 1ns/1ps
// Serial client of the original Window MMIO contract, not a second gather
// engine or DMA. Connect its MMIO channel through the proven pg_mmio_cdc.
// Accepted requests and their responses are held until actual retirement.
module soc_window_descriptor_port(
 // 接口声明：input logic clk,rst,clear_counters。
 // 记录数量或剩余进度，位宽限定可表达范围。
 input logic clk,rst,clear_counters,
 // 接口声明：input logic job_valid,output logic job_ready,input logic [351:0] job_data。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 input logic job_valid,output logic job_ready,input logic [351:0] job_data,
 // 接口声明：input logic [31:0] job_cookie,input logic [15:0] expected_K。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [31:0] job_cookie,input logic [15:0] expected_K,
 // 接口声明：output logic done_valid,input logic done_ready,output logic [31:0] done_cookie。
 // 把返回信息关联到对应的已接受请求。
 output logic done_valid,input logic done_ready,output logic [31:0] done_cookie,
 // 接口声明：output logic [7:0] done_error,output logic done_partial。
 // 表达本地完成/结束条件，系统退休还需满足上层接口契约。
 output logic [7:0] done_error,output logic done_partial,
 // 接口声明：output logic req_valid,input logic req_ready,output logic [15:0] req_addr。
 // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
 output logic req_valid,input logic req_ready,output logic [15:0] req_addr,
 // 接口声明：output logic req_write,output logic [31:0] req_wdata,output logic [3:0] req_wstrb。
 // 按字节选择本次写入生效的 lane。
 output logic req_write,output logic [31:0] req_wdata,output logic [3:0] req_wstrb,
 // 接口声明：input logic rsp_valid,output logic rsp_ready,input logic [31:0] rsp_rdata,input logic rsp_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 input logic rsp_valid,output logic rsp_ready,input logic [31:0] rsp_rdata,input logic rsp_error,
 // 接口声明：output logic busy,protocol_poison。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 output logic busy,protocol_poison,
 // 接口声明：output logic [31:0] total_read_bytes,total_write_bytes,total_active_UI,total_stall_UI,total_hits,total_miss...。
 output logic [31:0] total_read_bytes,total_write_bytes,total_active_UI,total_stall_UI,total_hits,total_misses,total_command_ticks
);
 typedef enum logic [2:0] {IDLE,SEND,WAIT_RESPONSE,HOLD_DONE,POISON} state_t;
 state_t state;
 logic [351:0] words_q;
 logic [31:0] cookie_q,expected_bytes_q,status_q;
 logic [4:0] operation_q;
 logic [7:0] error_q;
 logic partial_q,started_q;
 logic [31:0] job_ticks;
 // Operation0 prechecks readiness;1..11 configure;12 starts;13 polls
 // realcompletion;14..19 collect existing byte/cache/UI counters.
 assign job_ready=!rst&&state==IDLE&&!protocol_poison;
 assign done_valid=!rst&&state==HOLD_DONE&&!protocol_poison;
 assign done_cookie=cookie_q;assign done_error=error_q;assign done_partial=partial_q;
 assign busy=state!=IDLE;
 assign req_valid=!rst&&state==SEND&&!protocol_poison;
 assign rsp_ready=!rst&&state==WAIT_RESPONSE&&!protocol_poison;
 assign req_wstrb=4'hf;
 // 过程边界：always_comb begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_comb begin
  req_addr=16'h0330;req_write=0;req_wdata=0;
  if(operation_q>=1&&operation_q<=11)begin
   req_addr=16'h0300+{9'd0,operation_q,2'd0};req_write=1;
   req_wdata=words_q[32*(operation_q[3:0]-4'd1)+:32];
  end
  if(operation_q==12)begin req_addr=16'h0300;req_write=1;req_wdata=1;end
  if(operation_q>=14)req_addr=16'h0334+{9'd0,(operation_q-5'd14),2'd0};
 end
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin
   state<=IDLE;words_q<=0;cookie_q<=0;expected_bytes_q<=0;status_q<=0;operation_q<=0;
   error_q<=0;partial_q<=0;started_q<=0;protocol_poison<=0;
   total_read_bytes<=0;total_write_bytes<=0;total_active_UI<=0;total_stall_UI<=0;total_hits<=0;total_misses<=0;total_command_ticks<=0;job_ticks<=0;
  end else begin
   if(state!=IDLE&&state!=HOLD_DONE&&state!=POISON)job_ticks<=job_ticks+1'b1;
   // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case(state)
   // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
   IDLE:if(job_valid&&job_ready)begin
    words_q<=job_data;cookie_q<=job_cookie;expected_bytes_q<=32'(job_data[6*32+16+:16])*32'(expected_K);
    error_q<=0;partial_q<=0;started_q<=0;job_ticks<=0;operation_q<=0;state<=SEND;
   end
   // 状态/选择分支 SEND：本分支规定该编码下的寄存器更新和下一步动作。
   SEND:if(req_ready)state<=WAIT_RESPONSE;
   // 状态/选择分支 WAIT_RESPONSE：本分支规定该编码下的寄存器更新和下一步动作。
   WAIT_RESPONSE:if(rsp_valid)begin
    if(rsp_error)begin
     // A write-side transport fault after START has ambiguous ownership.
     // Do not invent a completed gather; common reset is required.
     if(started_q)begin protocol_poison<=1;state<=POISON;end
     else begin error_q<=8'he8;state<=HOLD_DONE;end
    end else if(operation_q==0)begin
     if(rsp_rdata[16]||!rsp_rdata[15])begin error_q<=8'he9;state<=HOLD_DONE;end
     else if(!rsp_rdata[17])state<=SEND;
     else begin operation_q<=1;state<=SEND;end
    end else if(operation_q<=11)begin operation_q<=operation_q+1'b1;state<=SEND;end
    else if(operation_q==12)begin started_q<=1;operation_q<=13;state<=SEND;end
    else if(operation_q==13)begin
     if(!rsp_rdata[1])state<=SEND;
     else begin
      status_q<=rsp_rdata;partial_q<=rsp_rdata[13];
      if(rsp_rdata[12:5]!=0)error_q<=rsp_rdata[12:5];
      else if(rsp_rdata[14]||rsp_rdata[16]||!rsp_rdata[13]||rsp_rdata[0])error_q<=8'hea;
      operation_q<=14;state<=SEND;
     end
    end else begin
     // 按 operation_q 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
     case(operation_q)
      14:begin total_read_bytes<=total_read_bytes+rsp_rdata;if(rsp_rdata[3:0]!=0&&error_q==0)error_q<=8'heb;end
      15:begin total_write_bytes<=total_write_bytes+rsp_rdata;if(rsp_rdata!=expected_bytes_q&&error_q==0)error_q<=8'hec;end
      16:total_hits<=total_hits+rsp_rdata;
      17:total_misses<=total_misses+rsp_rdata;
      18:total_active_UI<=total_active_UI+rsp_rdata;
      19:total_stall_UI<=total_stall_UI+rsp_rdata;
      default:;
     endcase
     if(operation_q==19)state<=HOLD_DONE;else begin operation_q<=operation_q+1'b1;state<=SEND;end
    end
   end
   // 状态/选择分支 HOLD_DONE：本分支规定该编码下的寄存器更新和下一步动作。
   HOLD_DONE:if(done_ready)begin state<=IDLE;started_q<=0;total_command_ticks<=total_command_ticks+job_ticks;end
   POISON:;
   default:begin protocol_poison<=1;state<=POISON;end
   endcase
   if(clear_counters)begin
    if(state!=IDLE)begin protocol_poison<=1;state<=POISON;end
    else begin total_read_bytes<=0;total_write_bytes<=0;total_active_UI<=0;total_stall_UI<=0;total_hits<=0;total_misses<=0;total_command_ticks<=0;job_ticks<=0;end
   end
  end
 end
endmodule
