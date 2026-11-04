// 架构导读：soc_video_event_mmio。
// 锁存显示路径事件及对应帧/运行标识，用于软件确认。
`timescale 1ns/1ps
// UI register window. A run's event snapshots are captured once and remain
// immutable until an explicit ARM for the next run. CPU polling is not a
// timestamp source: event ticks originate at the actual pixel-domain event.
module soc_video_event_mmio (
 // 接口声明：input logic clk,rst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic clk,rst,
 // 接口声明：input logic req_valid,output logic req_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic req_valid,output logic req_ready,
 // 接口声明：input logic [15:0] req_addr,input logic req_write。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [15:0] req_addr,input logic req_write,
 // 接口声明：input logic [31:0] req_wdata,input logic [3:0] req_wstrb。
 // 按字节选择本次写入生效的 lane。
 input logic [31:0] req_wdata,input logic [3:0] req_wstrb,
 // 接口声明：output logic rsp_valid,input logic rsp_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 output logic rsp_valid,input logic rsp_ready,
 // 接口声明：output logic [31:0] rsp_rdata,output logic rsp_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 output logic [31:0] rsp_rdata,output logic rsp_error,
 // 接口声明：output logic [1:0] test_pattern。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [1:0] test_pattern,
 // 接口声明：input logic event_tc,event_th,event_te,te_good。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic event_tc,event_th,event_te,te_good,
 // 接口声明：input logic [63:0] tc_ticks,th_ticks,te_ticks。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [63:0] tc_ticks,th_ticks,te_ticks,
 // 接口声明：input logic [31:0] tc_frame,tc_run,th_frame,th_run,te_frame,te_run。
 input logic [31:0] tc_frame,tc_run,th_frame,th_run,te_frame,te_run,
 input logic [31:0] stat_underflow,stat_mismatch,stat_presented,
 input logic [31:0] stat_max_ddr_wait,stat_fifo_high,stat_fifo_low,
 input logic [7:0] video_fault
);
 logic armed,seen_tc,seen_th,seen_te,frame_good;
 logic [31:0] expected_frame,expected_run,underflow_before;
 logic [63:0] captured_tc,captured_th,captured_te;
 wire [7:0] off={req_addr[7:2],2'b0};
 assign req_ready=!rsp_valid||rsp_ready;
 // 过程边界：always_ff @(posedge clk) begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk) begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst) begin
   rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;test_pattern<=1;
   armed<=0;seen_tc<=0;seen_th<=0;seen_te<=0;frame_good<=0;
   expected_frame<=0;expected_run<=0;underflow_before<=0;
   captured_tc<=0;captured_th<=0;captured_te<=0;
  end else begin
   // 握手/背压判断：rsp_valid&&rsp_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(rsp_valid&&rsp_ready)rsp_valid<=0;
   if(armed) begin
    if(event_tc&&!seen_tc&&tc_frame==expected_frame&&tc_run==expected_run)
      begin seen_tc<=1;captured_tc<=tc_ticks;end
    if(event_th&&!seen_th&&th_frame==expected_frame&&th_run==expected_run)
      begin seen_th<=1;captured_th<=th_ticks;end
    if(event_te&&!seen_te&&te_frame==expected_frame&&te_run==expected_run)
      begin seen_te<=1;captured_te<=te_ticks;frame_good<=te_good;end
   end
   // 握手/背压判断：req_valid&&req_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(req_valid&&req_ready) begin
    rsp_valid<=1;rsp_error<=0;rsp_rdata<=0;
    if(req_addr[11:8]!=4'h6||req_addr[1:0]!=0||(req_write&&req_wstrb!=4'hf))rsp_error<=1;
    else if(req_write)case(off)
     8'h00:if(req_wdata==1)begin
       armed<=1;seen_tc<=0;seen_th<=0;seen_te<=0;frame_good<=0;
       captured_tc<=0;captured_th<=0;captured_te<=0;underflow_before<=stat_underflow;
      end else if(req_wdata==0)armed<=0;else rsp_error<=1;
     8'h08:if(armed)rsp_error<=1;else expected_run<=req_wdata;
     8'h0c:if(armed)rsp_error<=1;else expected_frame<=req_wdata;
     8'h10:if(req_wdata>2)rsp_error<=1;else test_pattern<=req_wdata[1:0];
     default:rsp_error<=1;
    endcase
    else case(off)
     8'h00:rsp_rdata<=32'h32544956; // VIT2, CPU-reference event snapshots
     8'h04:rsp_rdata<={24'b0,3'b0,frame_good,seen_te,seen_th,seen_tc,armed};
     8'h08:rsp_rdata<=expected_run;
     8'h0c:rsp_rdata<=expected_frame;
     8'h10:rsp_rdata<={30'b0,test_pattern};
     8'h14:rsp_rdata<=stat_underflow;
     8'h18:rsp_rdata<=stat_mismatch;
     8'h1c:rsp_rdata<=stat_presented;
     8'h20:rsp_rdata<=stat_max_ddr_wait;
     8'h24:rsp_rdata<=stat_fifo_high;
     8'h28:rsp_rdata<=stat_fifo_low;
     8'h2c:rsp_rdata<={24'b0,video_fault};
     8'h30:rsp_rdata<=captured_tc[31:0];
     8'h34:rsp_rdata<=captured_tc[63:32];
     8'h38:rsp_rdata<=captured_th[31:0];
     8'h3c:rsp_rdata<=captured_th[63:32];
     8'h40:rsp_rdata<=captured_te[31:0];
     8'h44:rsp_rdata<=captured_te[63:32];
     8'h48:rsp_rdata<=underflow_before;
     // Conservative delay bound in CPU cycles for registered source, two
     // receiving synchronizers, decode/edge capture at CPU150/pixel74.25.
     8'h4c:rsp_rdata<=32'd12;
     default:rsp_error<=1;
    endcase
   end
  end
 end
endmodule
