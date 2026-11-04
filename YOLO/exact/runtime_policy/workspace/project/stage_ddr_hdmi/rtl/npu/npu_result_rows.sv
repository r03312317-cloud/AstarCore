`timescale 1ns/1ps
// Unmerged fixed-lane result store: two32x256xINT32 banks, not a DMA.
// Capture one complete8-column ACC48 row, preserving the original INT32
// saturation. Stream complete channel groups in DDR row-major order.
// Ownership cannot retire before every realB response has retired.
module npu_result_rows #(
 parameter int BANK_ROWS=32,BANK_COLUMNS=256
)( 
 input logic clk,rst,
 input logic write_begin,write_slot,input logic [255:0] write_identity,
 input logic [5:0] rows,input logic [8:0] columns,
 output logic write_begin_ready,
 input logic write_valid,input logic [4:0] write_row,write_group,
 input logic [383:0] write_ACC48,output logic write_ready,
 input logic write_commit,write_abort,
 input logic store_claim,store_slot,input logic [255:0] expected_identity,
 output logic store_claim_ready,
 input logic read_valid,input logic [4:0] read_row,read_group,
 output logic read_ready,output_valid,input logic output_ready,
 output logic [255:0] output_INT32,output logic [31:0] output_strobe,
 input logic store_release,real_B_retired,store_failed,
 // Discard only an unclaimed READY generation. No DDR Store owns it yet.
 // Reuse the existing store_slot/expected_identity comparison and require
 // a quiescent local interface; an active Store still needs real B release.
 input logic discard_ready,
 output logic [3:0] owners,output logic protocol_poison,
 output logic [31:0] captured_rows,consumed_groups
);
 localparam int ROW_ADDR_W=BANK_ROWS==16?4:5;
 localparam int RESULT_ADDR_W=1+ROW_ADDR_W+(BANK_COLUMNS==8?0:5);
 initial begin
  if((BANK_ROWS!=16&&BANK_ROWS!=32)||(BANK_COLUMNS!=8&&BANK_COLUMNS!=256))
   $fatal(1,"RESULT_FIXED_BANK_CAPACITY_UNSUPPORTED");
 end
 localparam logic [1:0] EMPTY=0,FILL=1,READY=2,STORE=3;
 logic [1:0] owner[0:1];logic [255:0] identity[0:1];
 logic [5:0] nr[0:1];logic [8:0] nc[0:1];
 logic [4:0] last_group[0:1],next_row[0:1],next_group[0:1];
 logic half[0:1],complete[0:1];
 logic active_slot,read_complete;
 logic [4:0] expected_read_row,expected_read_group;
 logic [3:0] response_columns;
 // Preserve all256 identity bits and same-cycle claim/discard semantics.
 // Eight32bit comparisons expose a parallel equality reduction topology.
 wire [255:0] selected_identity=identity[store_slot];
 wire [7:0] identity_equal32;
 for(genvar keypart=0;keypart<8;keypart++)begin:g_identity_equal32
  assign identity_equal32[keypart]=selected_identity[keypart*32+:32]==expected_identity[keypart*32+:32];
 end
 wire identity_match=&identity_equal32;
 wire shape_ok=rows>0&&rows<=BANK_ROWS&&columns>0&&columns<=BANK_COLUMNS;
 assign owners={owner[1],owner[0]};
 assign write_begin_ready=!rst&&!protocol_poison&&owner[write_slot]==EMPTY;
 assign write_ready=!rst&&!protocol_poison&&owner[write_slot]==FILL&&!complete[write_slot]&&
  write_row==next_row[write_slot]&&write_group==next_group[write_slot];
 wire wf=write_valid&&write_ready;
 assign store_claim_ready=!rst&&!protocol_poison&&owner[store_slot]==READY&&
  identity_match&&owner[!store_slot]!=STORE&&!output_valid;
 assign read_ready=!rst&&!protocol_poison&&owner[active_slot]==STORE&&!read_complete&&
  (!output_valid||output_ready)&&read_row==expected_read_row&&read_group==expected_read_group;
 wire rf=read_valid&&read_ready;
 wire [RESULT_ADDR_W-1:0] write_address,read_address;
 if(BANK_COLUMNS==8)begin:g_one_group
  assign write_address={write_slot,write_row[ROW_ADDR_W-1:0]};
  assign read_address={active_slot,read_row[ROW_ADDR_W-1:0]};
 end else begin:g_channel_page
  assign write_address={write_slot,write_row[ROW_ADDR_W-1:0],write_group};
  assign read_address={active_slot,read_row[ROW_ADDR_W-1:0],read_group};
 end
 function automatic logic [31:0] original_INT32(input logic signed [47:0] value);
  if(value[47:32]=={16{value[31]}})return value[31:0];
  return value[47]?32'h80000000:32'h7fffffff;
 endfunction
 for(genvar lane=0;lane<8;lane++)begin:g_lane
  wire [31:0] ram_data;
  wire [8:0] absolute_column={write_group,3'd0}+9'(lane);
  wire [31:0] value=absolute_column<nc[write_slot]?original_INT32($signed(write_ACC48[lane*48+:48])):32'd0;
  npu_result_word_ram #(.WIDTH(32),.ADDR_W(RESULT_ADDR_W)) ram(
   .clk,.wr_en(wf),.wr_addr(write_address),.wr_data(value),
   .rd_en(rf),.rd_addr(read_address),.rd_data(ram_data));
  assign output_INT32[lane*32+:32]=ram_data;
  assign output_strobe[lane*4+:4]=output_valid&&lane<response_columns?4'hf:4'h0;
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   for(integer s=0;s<2;s++)begin owner[s]<=EMPTY;identity[s]<=0;nr[s]<=0;nc[s]<=0;last_group[s]<=0;next_row[s]<=0;next_group[s]<=0;half[s]<=0;complete[s]<=0;end
   active_slot<=0;read_complete<=0;expected_read_row<=0;expected_read_group<=0;
   response_columns<=0;output_valid<=0;protocol_poison<=0;captured_rows<=0;consumed_groups<=0;
  end else if(!protocol_poison)begin
   if(output_valid&&output_ready)begin output_valid<=0;consumed_groups<=consumed_groups+1'b1;end
   if(write_begin)begin
    if(!write_begin_ready||!shape_ok||write_valid||write_commit||write_abort)protocol_poison<=1;
    else begin owner[write_slot]<=FILL;identity[write_slot]<=write_identity;nr[write_slot]<=rows;nc[write_slot]<=columns;
     last_group[write_slot]<=BANK_COLUMNS==8?5'd0:5'((columns-1'b1)>>3);next_row[write_slot]<=0;next_group[write_slot]<=0;half[write_slot]<=0;complete[write_slot]<=0;end
   end
   if(write_valid)begin
    if(!write_ready)protocol_poison<=1;
    else begin
     captured_rows<=captured_rows+1'b1;
     if({1'b0,write_row}+6'd1>=nr[write_slot]||write_row[3:0]==15)begin
      if(write_group==last_group[write_slot])begin
       if({1'b0,write_row}+6'd1>=nr[write_slot])complete[write_slot]<=1;
       else begin half[write_slot]<=1;next_row[write_slot]<=16;next_group[write_slot]<=0;end
      end else begin next_group[write_slot]<=write_group+1'b1;next_row[write_slot]<=half[write_slot]?5'd16:5'd0;end
     end else next_row[write_slot]<=write_row+1'b1;
    end
   end
   if(write_commit)begin
    if(owner[write_slot]!=FILL||!complete[write_slot]||write_valid||write_abort)protocol_poison<=1;
    else owner[write_slot]<=READY;
   end
   if(write_abort)begin
    if(owner[write_slot]!=FILL||write_valid||write_commit||write_begin)protocol_poison<=1;
    else begin owner[write_slot]<=EMPTY;complete[write_slot]<=0;end
   end
   if(store_claim)begin
    if(!store_claim_ready||store_release)protocol_poison<=1;
    else begin owner[store_slot]<=STORE;active_slot<=store_slot;read_complete<=0;expected_read_row<=0;expected_read_group<=0;end
   end
   if(read_valid)begin
    if(owner[active_slot]!=STORE||read_complete||read_row!=expected_read_row||read_group!=expected_read_group)protocol_poison<=1;
    else if(rf)begin
     output_valid<=1;
     response_columns<=nc[active_slot]-{read_group,3'd0}>8?4'd8:4'(nc[active_slot]-{read_group,3'd0});
     if(read_group==last_group[active_slot])begin
      expected_read_group<=0;
      if({1'b0,read_row}+6'd1>=nr[active_slot])read_complete<=1;
      else expected_read_row<=read_row+1'b1;
     end else expected_read_group<=read_group+1'b1;
    end
   end
   if(store_release)begin
    if(owner[active_slot]!=STORE||!real_B_retired||output_valid||read_valid||(!read_complete&&!store_failed))protocol_poison<=1;
    else owner[active_slot]<=EMPTY;
   end
   if(discard_ready)begin
    if(owner[store_slot]!=READY||!identity_match||
       store_claim||store_release||write_begin||write_valid||write_commit||write_abort||read_valid||output_valid)
     protocol_poison<=1;
    else owner[store_slot]<=EMPTY;
   end
  end
 end
endmodule

// One synchronous read and one wholeword write port. Payload has no reset.
module npu_result_word_ram #(parameter int WIDTH=32,ADDR_W=11)(
 input logic clk,wr_en,input logic [ADDR_W-1:0] wr_addr,input logic [WIDTH-1:0] wr_data,
 input logic rd_en,input logic [ADDR_W-1:0] rd_addr,output logic [WIDTH-1:0] rd_data
);
 (* ram_style="block",syn_ramstyle="block_ram" *) logic [WIDTH-1:0] memory[0:(1<<ADDR_W)-1];
 always_ff @(posedge clk)begin
  if(wr_en)memory[wr_addr]<=wr_data;
  if(rd_en)rd_data<=memory[rd_addr];
 end
endmodule
