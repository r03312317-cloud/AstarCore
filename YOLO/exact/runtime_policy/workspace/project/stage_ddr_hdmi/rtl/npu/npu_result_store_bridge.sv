`timescale 1ns/1ps
// Existing RV32 result-bank to native DMA stream path.
// Serializes a captured M16xN-page INT32 result into ONE existing native DMA.
// MAX_COLUMNS=8 is the small-tile control; 256 permits full channel-page
// row-major Store, giving the existing DDR bridge contiguous requests.
// It contains no memory requester, PE, second DMA or completion queue.
// The result bank remains owned until the actual DMA and R/B order queue
// report genuine retirement. Cancellation drains the accepted Store with
// its original captured values; a completed B error can discard unread bank
// payload only after every accepted physical response has retired.
// Base/stride/range authorization belongs to the original Scheduler. This
// shape-only internal bridge MUST NOT be exposed as an unchecked MMIO client.
module npu_result_store_bridge #(parameter int MAX_COLUMNS=256,parameter bit VECTOR4_ENABLE=1'b0)(
 input logic clk,rst,
 input logic start_valid,output logic start_ready,
 input logic start_slot,input logic [255:0] start_identity,
 input logic [4:0] start_rows,input logic [8:0] start_columns,
 input logic [31:0] start_base,start_stride,
 input logic cancel,DMA_exclusive_grant,
 output logic bank_claim,bank_slot,output logic [255:0] bank_identity,
 input logic bank_claim_ready,
 output logic bank_read_valid,output logic [4:0] bank_read_row,bank_read_group,
 input logic bank_read_ready,bank_output_valid,
 output logic bank_output_ready,
 input logic [255:0] bank_output_INT32,input logic [31:0] bank_output_strobe,
 output logic bank_release,bank_real_B_retired,bank_store_failed,
 input logic bank_poison,
 output logic dma_job_valid,input logic dma_job_ready,
 output npu_defs_pkg::npu_dma_job_t dma_job,
 input logic dma_job_done,dma_job_error,
 input npu_defs_pkg::npu_error_e dma_error_code,
 input logic [4:0] dma_outstanding,input logic response_order_idle,response_order_poison,
 output logic store_elem_vector4,output logic [127:0] store_elem_vector_data,
 output logic store_elem_valid,input logic store_elem_ready,
 output logic signed [31:0] store_elem_data,
 output logic [2:0] store_elem_bytes,
 output logic [15:0] store_elem_row,store_elem_col,
 output logic busy,done,cancelled,protocol_poison,
 output npu_defs_pkg::npu_error_e error_code,
 output logic [31:0] streamed_elements,stream_stall_cycles,real_retire_wait_cycles
);
 import npu_defs_pkg::*;
 typedef enum logic [2:0] {IDLE,CLAIM,STREAM,DRAIN,RELEASE,CHECK,COMPLETE,POISON} state_t;
 state_t state;
 localparam int COLUMN_W=MAX_COLUMNS<=8?4:9;
 logic [4:0] rows_q,next_read,row_q,next_group,group_q;
 logic [COLUMN_W-1:0] columns_q;
 logic [2:0] col_q;
 logic vector4_q;
 wire [3:0] stream_step=vector4_q?4'd4:4'd1;
 assign store_elem_vector4=vector4_q;
 assign store_elem_vector_data=bank_output_INT32[col_q[2]*128+:128];
 logic [31:0] base_q,stride_q;
 logic pending_row,all_requested,cancel_q,terminal_seen,terminal_failed;
 wire terminal=dma_job_done||dma_job_error;
 wire lease=state==CLAIM||state==STREAM||state==DRAIN||state==RELEASE;
 wire retired=terminal_seen&&dma_job_ready&&dma_outstanding==0&&response_order_idle;
 // An unaccepted start owns nothing. Once accepted, even cancellation
 // before the DMA grant drains this bounded captured tile with true writes.
 assign start_ready=!rst&&!cancel&&DMA_exclusive_grant&&!protocol_poison&&state==IDLE;
 assign busy=state!=IDLE;
 assign dma_job_valid=!rst&&state==CLAIM&&bank_claim_ready&&DMA_exclusive_grant;
 assign bank_claim=!rst&&state==CLAIM&&dma_job_ready&&DMA_exclusive_grant;
 always_comb begin
  dma_job='0;dma_job.kind=DMA_STORE_C;dma_job.base=base_q;
  dma_job.row_stride=stride_q;dma_job.rows=16'(rows_q);dma_job.cols=16'(columns_q);
  // Original two-bit job ABI: INT32 is 0 here; STORE takes the authoritative
  // literal four-byte width from store_elem_bytes on its element stream.
  dma_job.elem_bytes=2'd0;dma_job.bank=bank_slot;
 end
 // The existing synchronous bank accepts a replacement read on the edge
 // that its last lane is consumed. Reuse its one output register, retaining
 // ready/valid backpressure; no speculative read or extra result bank.
 assign bank_read_valid=!rst&&state==STREAM&&!terminal_failed&&!terminal&&
                        (!pending_row||row_done)&&!all_requested;
 assign bank_read_row=next_read;assign bank_read_group=next_group;
 assign store_elem_valid=!rst&&state==STREAM&&pending_row&&bank_output_valid&&!terminal_failed&&!terminal;
 assign store_elem_data=$signed(bank_output_INT32[32*col_q+:32]);
 assign store_elem_bytes=3'd4;
 assign store_elem_row=16'(row_q);assign store_elem_col=16'({group_q,3'd0})+16'(col_q);
 wire sf=store_elem_valid&&store_elem_ready;
 wire [8:0] remaining_columns=9'(columns_q)-{group_q,3'd0};
 wire [3:0] vector_columns=remaining_columns>8?4'd8:4'(remaining_columns);
 wire row_done=sf&&({1'b0,col_q}+stream_step>=vector_columns);
 // Once the old DMA reports a terminal error, no new physical write can be
 // supplied. Drop only its unconsumed local output token, not a DDR response.
 assign bank_output_ready=(state==STREAM&&row_done)||(state==DRAIN&&terminal_failed);
 assign bank_release=!rst&&state==RELEASE;
 assign bank_real_B_retired=retired;
 assign bank_store_failed=terminal_failed;
 always_ff @(posedge clk)begin
  done<=0;
  if(rst)begin
   state<=IDLE;vector4_q<=0;rows_q<=0;columns_q<=0;next_read<=0;row_q<=0;col_q<=0;next_group<=0;group_q<=0;
   base_q<=0;stride_q<=0;bank_slot<=0;bank_identity<=0;
   pending_row<=0;all_requested<=0;cancel_q<=0;terminal_seen<=0;terminal_failed<=0;
   cancelled<=0;protocol_poison<=0;error_code<=ERR_NONE;
   streamed_elements<=0;stream_stall_cycles<=0;real_retire_wait_cycles<=0;
  end else if(!protocol_poison)begin
   if(busy&&cancel)cancel_q<=1;
   if(store_elem_valid&&!store_elem_ready)stream_stall_cycles<=stream_stall_cycles+1'b1;
   if(state==DRAIN&&!retired)real_retire_wait_cycles<=real_retire_wait_cycles+1'b1;
   if(lease&&(!DMA_exclusive_grant||response_order_poison||bank_poison))begin
    protocol_poison<=1;error_code<=ERR_INTERNAL_PROTOCOL;state<=POISON;
   end else if(terminal&&state!=STREAM&&state!=DRAIN)begin
    protocol_poison<=1;error_code<=ERR_INTERNAL_PROTOCOL;state<=POISON;
   end else if(dma_job_done&&dma_job_error)begin
    protocol_poison<=1;error_code<=ERR_INTERNAL_PROTOCOL;state<=POISON;
   end else begin
    if(terminal)begin
     terminal_seen<=1;
     if(dma_job_error)begin
      terminal_failed<=1;error_code<=dma_error_code==ERR_NONE?ERR_INTERNAL_PROTOCOL:dma_error_code;
     end
    end
    case(state)
     IDLE:if(start_valid&&start_ready)begin
      vector4_q<=VECTOR4_ENABLE&&start_columns[1:0]==0&&start_base[3:0]==0&&start_stride[3:0]==0;
      rows_q<=start_rows;columns_q<=COLUMN_W'(start_columns);base_q<=start_base;stride_q<=start_stride;
      bank_slot<=start_slot;bank_identity<=start_identity;
      next_read<=0;row_q<=0;col_q<=0;next_group<=0;group_q<=0;pending_row<=0;all_requested<=0;
      terminal_seen<=0;terminal_failed<=0;cancel_q<=cancel;cancelled<=0;error_code<=ERR_NONE;
      if(start_rows==0||start_rows>16||start_columns==0||start_columns>MAX_COLUMNS)begin
       error_code<=ERR_INVALID_DIM;state<=COMPLETE;
      end else if(cancel)begin cancelled<=1;state<=COMPLETE;end
      else state<=CLAIM;
     end
     CLAIM:if(dma_job_valid&&dma_job_ready&&bank_claim&&bank_claim_ready)state<=STREAM;
     STREAM:begin
      if(bank_read_valid&&bank_read_ready)begin
       pending_row<=1;row_q<=next_read;group_q<=next_group;col_q<=0;
       if(MAX_COLUMNS==8||{1'b0,next_group,3'd0}+9'd8>=9'(columns_q))begin
        next_group<=0;
        if(next_read+5'd1>=rows_q)all_requested<=1;
        else next_read<=next_read+1'b1;
       end else next_group<=next_group+1'b1;
      end
      if(sf)begin
       streamed_elements<=streamed_elements+32'(stream_step);
       if(vector4_q?bank_output_strobe[16*col_q[2]+:16]!=16'hffff:bank_output_strobe[4*col_q+:4]!=4'hf)begin
        protocol_poison<=1;error_code<=ERR_INTERNAL_PROTOCOL;state<=POISON;
       end
       if(row_done)begin pending_row<=bank_read_valid&&bank_read_ready;col_q<=0;end
       else col_q<=col_q+3'(stream_step);
      end
      if(terminal)begin
       if(dma_job_done&&(!all_requested||pending_row))begin
        protocol_poison<=1;error_code<=ERR_INTERNAL_PROTOCOL;state<=POISON;
       end else state<=DRAIN;
      end
     end
     DRAIN:begin
      if(terminal_failed&&bank_output_valid)pending_row<=0;
      if(retired&&!bank_output_valid)state<=RELEASE;
     end
     RELEASE:if(retired&&!bank_output_valid&&!bank_read_valid)state<=CHECK;
      else begin protocol_poison<=1;error_code<=ERR_INTERNAL_PROTOCOL;state<=POISON;end
     CHECK:state<=COMPLETE;
     COMPLETE:begin done<=1;cancelled<=cancel_q||cancel;state<=IDLE;end
     POISON:begin end
     default:begin protocol_poison<=1;error_code<=ERR_INTERNAL_PROTOCOL;state<=POISON;end
    endcase
   end
  end
 end
 initial if(MAX_COLUMNS!=8&&MAX_COLUMNS!=256)$fatal(1,"RESULT_STORE_FIXED_PAGE_CAPACITY_RED");
endmodule
