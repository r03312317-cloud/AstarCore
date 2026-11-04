// 架构导读：npu_row_result_capture。
// 在阵列结果有效时捕获整行数据，隔离累加器读出和后续存储。
`timescale 1ns/1ps
// Replacement candidate for serial accumulator reads. Does not own a DMA,
// array, command queue or Scheduler. Captures one ACC48 row per clock once
// the existing array reports its genuine final-K completion.
module npu_row_result_capture(
 // 接口声明：input logic clk,rst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic clk,rst,
 input logic start_valid,output logic start_ready,
 input logic [4:0] tile_rows,row_base,channel_group,
 input logic cancel,
 output logic array_read_enable,output logic [3:0] array_read_row,
 input logic [383:0] array_row_ACC48,
 output logic write_valid,input logic write_ready,
 output logic [4:0] write_row,write_group,
 output logic [383:0] write_ACC48,
 output logic busy,done_pulse,cancelled,bad_start,
 output logic [31:0] rows_captured
);
 logic active,pending,cancel_q;
 logic [4:0] nr,base,group_q,issued,pending_row;
 assign start_ready=!rst&&!active&&!pending;
 assign busy=active||pending;
 assign array_read_enable=!rst&&active&&!cancel_q&&!cancel&&issued<nr&&(!pending||write_ready);
 assign array_read_row=issued[3:0];
 assign write_valid=!rst&&pending;
 assign write_row=pending_row;assign write_group=group_q;assign write_ACC48=array_row_ACC48;
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  done_pulse<=0;bad_start<=0;
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin active<=0;pending<=0;cancel_q<=0;cancelled<=0;nr<=0;base<=0;group_q<=0;issued<=0;pending_row<=0;rows_captured<=0;end
  else begin
   // 握手/背压判断：write_valid&&write_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(write_valid&&write_ready)begin pending<=0;rows_captured<=rows_captured+1'b1;end
   if(array_read_enable)begin pending<=1;pending_row<=base+issued;issued<=issued+1'b1;end
   // 握手/背压判断：start_valid&&start_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(start_valid&&start_ready)begin
    if(tile_rows==0||tile_rows>16||{1'b0,row_base}+{1'b0,tile_rows}>32||(row_base!=0&&row_base!=16))bad_start<=1;
    else begin active<=1;nr<=tile_rows;base<=row_base;group_q<=channel_group;issued<=0;cancel_q<=cancel;cancelled<=0;end
   end
   if(active&&cancel)cancel_q<=1;
   // A committed output token is held even after cancellation. Retire it,
   // then tell the enclosing owner to abort the incomplete result bank.
   if(active&&(cancel_q||issued==nr)&&(!pending||(write_valid&&write_ready))&&!array_read_enable)begin
    active<=0;done_pulse<=1;cancelled<=cancel_q;
   end
  end
 end
endmodule
