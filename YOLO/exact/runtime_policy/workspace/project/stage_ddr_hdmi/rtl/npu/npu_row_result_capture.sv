`timescale 1ns/1ps
// Replacement candidate for serial accumulator reads. Does not own a DMA,
// array, command queue or Scheduler. Captures one ACC48 row per clock once
// the existing array reports its genuine final-K completion.
module npu_row_result_capture(
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
 always_ff @(posedge clk)begin
  done_pulse<=0;bad_start<=0;
  if(rst)begin active<=0;pending<=0;cancel_q<=0;cancelled<=0;nr<=0;base<=0;group_q<=0;issued<=0;pending_row<=0;rows_captured<=0;end
  else begin
   if(write_valid&&write_ready)begin pending<=0;rows_captured<=rows_captured+1'b1;end
   if(array_read_enable)begin pending<=1;pending_row<=base+issued;issued<=issued+1'b1;end
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
