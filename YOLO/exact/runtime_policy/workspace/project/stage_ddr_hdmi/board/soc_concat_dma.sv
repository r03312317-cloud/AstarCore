`timescale 1ns/1ps
// One replacement for the existing Concat engine, with shared exact INT8
// Add/Pool/Upsample modes. Native16byte port and one actual response owner.
// Initial Pool/Upsample shapes cover the unchanged production model only.
module soc_concat_dma #(
 parameter logic [31:0] DDR_BASE=32'h80000000,DDR_BYTES=32'h04000000,
 parameter bit PIPELINED_POOL=1'b1,
 parameter bit PARALLEL_POOL=1'b1,
 parameter bit PAIR_CAT16=1'b1,
 parameter bit PAIR_CAT_WIDE=1'b1,
 parameter bit UP_WRITE_BURST=1'b1,
 parameter bit OUTPUT_PIPELINE=1'b1,
 parameter bit UP_EARLY_READ=1'b1,
 parameter bit READ_BURST_ENABLE=1'b0,
 parameter bit WRITE_BURST_ENABLE=1'b0
)(
 input logic clk,rst,start,cancel,
 input logic [1:0] operation, // 0Concat,1Add,2nearest2x,3maxPool5x5
 input logic [15:0] image_h,image_w,
 input logic [31:0] input_base,aux_base,output_base,pixels,
 input logic [15:0] input_channels,aux_channels,
 output logic ready,busy,done_pulse,partial_output,protocol_poison,
 output logic [7:0] error_sticky,
 output logic [31:0] read_bytes,write_bytes,active_cycles,stall_cycles,
 output logic dma_req_valid,input logic dma_req_ready,
 output logic dma_req_write,output logic [31:0] dma_req_addr,
 output logic [127:0] dma_req_wdata,output logic [15:0] dma_req_wstrb,
 output logic [3:0] dma_req_id,output logic [3:0] dma_req_len,
 input logic dma_rsp_last,
 input logic dma_rsp_valid,output logic dma_rsp_ready,
 input logic dma_rsp_write,input logic [3:0] dma_rsp_id,
 input logic [127:0] dma_rsp_rdata,input logic dma_rsp_error
);
 localparam logic [1:0] CAT=0,ADD=1,UP=2,POOL=3;
 localparam logic [63:0] DDR_LIMIT={32'd0,DDR_BASE}+{32'd0,DDR_BYTES};
 localparam logic [7:0] BAD_SHAPE=1,BAD_RANGE=2,READ_ERROR=3,
   WRITE_ERROR=4,BAD_RESPONSE=5,CANCELLED=6,BAD_OWNER=7;
 typedef enum logic [4:0] {IDLE,PRODUCTS,LENGTHS,ENDS,CHECK,PREP,
   READ_REQ,READ_WAIT,WRITE_REQ,WRITE_WAIT,POOL_INIT,POOL_SCAN,POOL_REDUCE,
   UP_READ,UP_LATCH,FINISH,POOL_STREAM,BATCH_BEGIN,BATCH_READ,BATCH_LATCH,BATCH_ADD,WRITE_STEP,
   POOL_PARALLEL,POOL_STAGE,POOL_SEND_BEGIN,UP_PACKET_BEGIN,
   STREAM_INIT,STREAM_WRITE} state_t;
 typedef enum logic [2:0] {RK_CAT,RK_A,RK_B,RK_CACHE,RK_BLOCK_A,RK_BLOCK_B} read_kind_t;
 state_t state;
 read_kind_t read_kind;
 logic [1:0] mode_q;
 // CAT/Add batches reuse otherwise idle row RAM (words 0..31). No second
 // tensor buffer or new AXI master. Native replies remain owned to LAST.
 logic [4:0] batch_words,batch_fill,batch_output;
 logic batch_write_live;
 // Elastic copy pipeline. The original word_payload is the output register;
 // the synchronous row-RAM read register is its lookahead slot. No payload
 // register bank or additional memory port is introduced.
 logic stream_head_valid,stream_ram_valid;
 logic [4:0] stream_issued;
 logic [8:0] stream_base,stream_up_position,stream_up_row;
 logic [8:0] stream_read_address;
 wire stream_fire=state==STREAM_WRITE&&stream_head_valid&&dma_req_ready;
 wire stream_live=!abort_now||batch_write_live||stream_head_valid;
 wire stream_move=state==STREAM_WRITE&&stream_live&&stream_ram_valid&&(!stream_head_valid||stream_fire);
 wire stream_read=state==STREAM_WRITE&&stream_live&&stream_issued<batch_words&&(!stream_ram_valid||stream_move);
 wire stream_nonlast=stream_fire&&batch_output+1'b1<batch_words;
 // Pair complete pixels of equal-width 16/32/64/128-channel CAT. Each
 // original A/B row-RAM region holds at most eight words. Segment-aligned
 // inputs and whole-pixel-aligned output prevent partial pixels at 4 KiB.
 // Other alignments/shapes retain the original segment batching path.
 wire paired_cat=READ_BURST_ENABLE&&WRITE_BURST_ENABLE&&mode_q==CAT&&in_c_q==aux_c_q&&
     ((PAIR_CAT16&&in_c_q==16&&out_q[4:0]==0)||
      (PAIR_CAT_WIDE&&((in_c_q==32&&((in_q[4:0]|aux_q[4:0])==0)&&out_q[5:0]==0)||
                      (in_c_q==64&&((in_q[5:0]|aux_q[5:0])==0)&&out_q[6:0]==0)||
                      (in_c_q==128&&((in_q[6:0]|aux_q[6:0])==0)&&out_q[7:0]==0))));
 wire [1:0] cat_pair_shift=in_c_q==32?2'd1:in_c_q==64?2'd2:in_c_q==128?2'd3:2'd0;
 logic [8:0] cat_pair_address;
 wire parallel_pool=PARALLEL_POOL&&READ_BURST_ENABLE&&WRITE_BURST_ENABLE&&mode_q==POOL;
 wire burst_up=UP_WRITE_BURST&&READ_BURST_ENABLE&&WRITE_BURST_ENABLE&&mode_q==UP;
 wire tensor_batch_mode=READ_BURST_ENABLE&&(mode_q==ADD||
     (mode_q==CAT&&(!(in_c_q==16&&aux_c_q==16)||paired_cat)));
 wire batch_write_mode=WRITE_BURST_ENABLE&&(tensor_batch_mode||parallel_pool||burst_up);
 logic [8:0] batch_limit,request_words,boundary_a,boundary_b,pair_pixels;
 wire response_last=!READ_BURST_ENABLE||dma_rsp_last;
 wire batch_a=read_kind==RK_BLOCK_A;
 wire batch_b=read_kind==RK_BLOCK_B;
 always_comb begin
  boundary_a=9'd256-{1'b0,((mode_q==CAT&&aux_segment)?aux_cursor[11:4]:in_cursor[11:4])};
  boundary_b=9'd256-{1'b0,aux_cursor[11:4]};
  batch_limit=9'd16;
  if(mode_q==CAT)begin
   if((segment_left>>4)<16)batch_limit=9'(segment_left>>4);
  end else if((bytes_left>>4)<16)batch_limit=9'(bytes_left>>4);
  if(batch_limit>boundary_a)batch_limit=boundary_a;
  if(mode_q==ADD&&batch_limit>boundary_b)batch_limit=boundary_b;
  if(WRITE_BURST_ENABLE&&batch_limit>(9'd256-{1'b0,out_cursor[11:4]}))
   batch_limit=9'd256-{1'b0,out_cursor[11:4]};
  pair_pixels=9'd8>>cat_pair_shift;
  if(pixels_left<32'(pair_pixels))pair_pixels=9'(pixels_left);
  if(pair_pixels>(boundary_a>>cat_pair_shift))pair_pixels=boundary_a>>cat_pair_shift;
  if(pair_pixels>(boundary_b>>cat_pair_shift))pair_pixels=boundary_b>>cat_pair_shift;
  if(pair_pixels>((9'd256-{1'b0,out_cursor[11:4]})>>({1'b0,cat_pair_shift}+3'd1)))
   pair_pixels=(9'd256-{1'b0,out_cursor[11:4]})>>({1'b0,cat_pair_shift}+3'd1);
  if(paired_cat)batch_limit=pair_pixels<<({1'b0,cat_pair_shift}+3'd1);
  case(cat_pair_shift)
   0:cat_pair_address={4'd0,batch_output[0],4'd0}+{6'd0,batch_output[3:1]};
   1:cat_pair_address={4'd0,batch_output[1],4'd0}+{6'd0,batch_output[3:2],batch_output[0]};
   2:cat_pair_address={4'd0,batch_output[2],4'd0}+{6'd0,batch_output[3],batch_output[1:0]};
   3:cat_pair_address={4'd0,batch_output[3],4'd0}+{6'd0,batch_output[2:0]};
  endcase
  request_words=1;
  if(READ_BURST_ENABLE&&state==READ_REQ)begin
   if(batch_a||batch_b)request_words=paired_cat?(9'(batch_words)>>1):9'(batch_words);
   else if(read_kind==RK_CACHE)begin
    request_words=9'd80-9'(cache_word);
    if(request_words>16)request_words=16;
    if(request_words>9'd256-{1'b0,in_cursor[11:4]})
     request_words=9'd256-{1'b0,in_cursor[11:4]};
   end
  end
  dma_req_len=((state==WRITE_REQ||state==STREAM_WRITE)&&batch_write_mode&&batch_output==0)?
    4'(batch_words-1'b1):4'(request_words-1'b1);
 end

 logic cancel_q;
 wire abort_now=cancel_q||cancel;
 logic [31:0] in_q,aux_q,out_q,pixels_q,pixels_left,bytes_left;
 logic [15:0] in_c_q,aux_c_q,segment_left,h_q,w_q;
 logic aux_segment;
 logic [47:0] in_length,aux_length;
 logic [48:0] out_length;
 logic [63:0] in_end,aux_end,out_end;
 logic [31:0] in_cursor,aux_cursor,out_cursor;
 // Reset-visible zero is retained by narrow first-write validity. The
 // controller and every fault/ownership/cancel state retain their resets.
 wire [127:0] word_q,best_q;
 logic [127:0] word_payload,best_payload,lane_result;
 logic word_initialized,best_initialized;
 assign word_q=word_initialized?word_payload:128'd0;
 assign best_q=best_initialized?best_payload:128'd0;
 logic [4:0] load_y;
 logic [2:0] fill_bank;
 logic [6:0] cache_word,up_read_index;
 logic [4:0] row_valid;
 logic [4:0] row_tag[0:4];
 // Five adjacent output windows share one scan of their nine-column union.
 // Only five 128-bit maxima and narrow pipeline tokens are added. Completed
 // values use words 400..439 of the existing 512-word RAM, disjoint from the
 // unchanged five raw rows in words 0..399. No additional payload RAM or DMA.
 logic [127:0] pool_maxima[0:4];
 logic [3:0] pool_scan_x;
 logic [2:0] pool_stage_index;
 logic [5:0] pool_emit_word;
 logic [4:0] pool_lane_mask;
 logic [8:0] pool_packet_words;
 logic [8:0] up_row_words_left,up_packet_words;
 function automatic logic [127:0] max_i8x16(input logic [127:0] a,b);
  for(integer lane=0;lane<16;lane=lane+1)
   max_i8x16[lane*8+:8]=$signed(a[lane*8+:8])>$signed(b[lane*8+:8])?a[lane*8+:8]:b[lane*8+:8];
 endfunction
 logic [3:0] pool_oy,pool_ox;
 logic [2:0] pool_cw,pool_ky,pool_kx;
 logic signed [5:0] pool_iy,pool_ix;
 logic pool_in_bounds,pool_bank_found;
 logic [2:0] pool_bank;
 logic [4:0] up_x;
 logic [2:0] up_cw;
 logic up_hrep,up_vrep;
 // One synchronous RAM response token; padding advances position without a
 // RAM read. Never consume a word from a different (ky,kx,cw) iteration.
 logic pool_pending,pool_pending_last,pool_scan_done;
 wire [127:0] pool_stream_value=pool_pending?lane_result:best_q;
 logic [6:0] up_next_index;
 wire up_next_row=({1'b0,up_cw}==channel_words-1'b1)&&up_hrep&&
                   ({11'd0,up_x}==w_q-1'b1)&&up_vrep;
 wire up_lookahead=UP_EARLY_READ&&!burst_up&&state==WRITE_WAIT&&mode_q==UP&&
     dma_rsp_valid&&dma_rsp_write&&dma_rsp_id==1&&!dma_rsp_error&&
     !abort_now&&!up_next_row&&row_valid[0]&&row_tag[0]==(load_y-1'b1);
 always_comb begin
  up_next_index=up_read_index+1'b1;
  if({1'b0,up_cw}==channel_words-1'b1)begin
   if(!up_hrep)up_next_index=up_read_index-(7'(channel_words)-7'd1);
   else if({11'd0,up_x}==w_q-1'b1)up_next_index=0;
  end
 end
 wire [3:0] channel_words=in_c_q==128?4'd8:4'd4;
 logic ram_wr,ram_rd;
 logic [8:0] ram_waddr,ram_raddr;
 logic [127:0] ram_rdata,ram_wdata;
 wire read_response_ok=state==READ_WAIT&&dma_rsp_valid&&!dma_rsp_write&&
   dma_rsp_id==0&&!dma_rsp_error&&!abort_now;
 function automatic logic overlaps(input logic [31:0] a,b,
                                    input logic [63:0] ae,be);
  return {32'd0,a}<be&&{32'd0,b}<ae;
 endfunction
 task automatic advance_pool(input logic [127:0] value);
  if(pool_ky==4&&pool_kx==4)begin word_payload<=value;word_initialized<=1'b1;state<=WRITE_REQ;end
  else begin
   if(pool_kx==4)begin pool_kx<=0;pool_ky<=pool_ky+1'b1;end
   else pool_kx<=pool_kx+1'b1;
   state<=POOL_SCAN;
  end
 endtask
 assign ready=state==IDLE&&!rst&&!protocol_poison;
 assign busy=state!=IDLE;
 assign dma_req_valid=!rst&&(state==READ_REQ||state==WRITE_REQ||(state==STREAM_WRITE&&stream_head_valid));
 assign dma_req_write=state==WRITE_REQ||state==STREAM_WRITE;
 assign dma_req_addr=(state==WRITE_REQ||state==STREAM_WRITE)?out_cursor:
   (read_kind==RK_B||batch_b)?aux_cursor:
   (read_kind==RK_CAT||(batch_a&&mode_q==CAT))&&aux_segment?aux_cursor:in_cursor;
 assign dma_req_wdata=word_q;
 assign dma_req_wstrb=16'hffff;
 assign dma_req_id=(state==WRITE_REQ||state==STREAM_WRITE)?4'd1:4'd0;
 assign dma_rsp_ready=!rst&&(state==READ_WAIT||state==WRITE_WAIT);
 soc_tensor_lane_alu lanes(.add_mode(mode_q==ADD),.a(mode_q==ADD?word_q:best_q),
   .b(mode_q==ADD&&!READ_BURST_ENABLE?dma_rsp_rdata:ram_rdata),.result(lane_result));
 soc_tensor_row_ram row_ram(.clk,.wr_en(ram_wr),.rd_en(ram_rd),
   .wr_addr(ram_waddr),.rd_addr(ram_raddr),.wr_data(ram_wdata),.rd_data(ram_rdata));
 always_comb begin
  pool_iy=$signed({2'b0,pool_oy})+$signed({3'b0,pool_ky})-6'sd2;
  pool_ix=$signed({2'b0,pool_ox})+(parallel_pool?$signed({2'b0,pool_scan_x}):$signed({3'b0,pool_kx}))-6'sd2;
  pool_in_bounds=pool_iy>=0&&pool_iy<10&&pool_ix>=0&&pool_ix<10;
  pool_bank=0;pool_bank_found=0;
  for(integer b=0;b<5;b++)if(row_valid[b]&&row_tag[b]==5'(pool_iy))begin
   pool_bank=3'(b);pool_bank_found=1;
  end
  ram_wr=(read_response_ok&&(read_kind==RK_CACHE||batch_a||batch_b))||
          (state==POOL_STAGE&&!rst&&!abort_now);
  ram_wdata=state==POOL_STAGE?pool_maxima[pool_stage_index]:dma_rsp_rdata;
  ram_waddr=state==POOL_STAGE?9'd400+(9'(pool_stage_index)<<3)+9'(pool_cw):
     (batch_a||batch_b)?((batch_b?9'd16:9'd0)+9'(batch_fill)):
      (mode_q==POOL?9'(fill_bank)*9'd80+9'(cache_word):9'(cache_word));
  stream_up_position=stream_base+9'(stream_issued);
  stream_up_row=stream_up_position>=160?stream_up_position-9'd160:stream_up_position;
  stream_read_address=9'(stream_issued);
  if(parallel_pool)stream_read_address=stream_base+9'(stream_issued);
  else if(burst_up)stream_read_address=in_c_q==128?{2'd0,stream_up_row[7:4],stream_up_row[2:0]}:
                                                              {2'd0,stream_up_row[7:3],stream_up_row[1:0]};
  else if(paired_cat)case(cat_pair_shift)
   0:stream_read_address={4'd0,stream_issued[0],4'd0}+{6'd0,stream_issued[3:1]};
   1:stream_read_address={4'd0,stream_issued[1],4'd0}+{6'd0,stream_issued[3:2],stream_issued[0]};
   2:stream_read_address={4'd0,stream_issued[2],4'd0}+{6'd0,stream_issued[3],stream_issued[1:0]};
   3:stream_read_address={4'd0,stream_issued[3],4'd0}+{6'd0,stream_issued[2:0]};
  endcase
  ram_rd=(!rst&&stream_read)||(!rst&&(!abort_now||batch_write_live)&&(state==BATCH_READ||(state==BATCH_LATCH&&mode_q==ADD)||((state==POOL_SCAN||
    ((state==POOL_STREAM||state==POOL_PARALLEL)&&!pool_scan_done))&&pool_in_bounds&&pool_bank_found)||
    ((state==UP_READ||up_lookahead)&&row_valid[0]&&row_tag[0]==(load_y-1'b1))));
  ram_raddr=state==STREAM_WRITE?stream_read_address:(state==BATCH_READ||state==BATCH_LATCH)?
      (burst_up?{2'd0,up_read_index}:parallel_pool?9'd400+9'(pool_emit_word):
       paired_cat?cat_pair_address:
       (9'(batch_output)+(state==BATCH_LATCH?9'd16:9'd0))):
      (mode_q==POOL?9'(pool_bank)*9'd80+9'(pool_ix)*9'd8+9'(pool_cw):
      (up_lookahead?{2'd0,up_next_index}:{2'd0,up_read_index}));
  pool_packet_words=9'd40-9'(pool_emit_word);
  if(pool_packet_words>16)pool_packet_words=16;
  if(pool_packet_words>9'd256-{1'b0,out_cursor[11:4]})
   pool_packet_words=9'd256-{1'b0,out_cursor[11:4]};
  up_packet_words=up_row_words_left;
  if(up_packet_words>16)up_packet_words=16;
  if(up_packet_words>9'd256-{1'b0,out_cursor[11:4]})
   up_packet_words=9'd256-{1'b0,out_cursor[11:4]};
 end
 always_ff @(posedge clk)begin
  done_pulse<=0;
  if(rst)begin
   state<=IDLE;read_kind<=RK_CAT;batch_words<=0;batch_fill<=0;batch_output<=0;batch_write_live<=0;mode_q<=CAT;cancel_q<=0;protocol_poison<=0;
   partial_output<=0;error_sticky<=0;read_bytes<=0;write_bytes<=0;
   active_cycles<=0;stall_cycles<=0;in_q<=0;aux_q<=0;out_q<=0;
   pixels_q<=0;pixels_left<=0;bytes_left<=0;in_c_q<=0;aux_c_q<=0;segment_left<=0;
   h_q<=0;w_q<=0;aux_segment<=0;in_length<=0;aux_length<=0;out_length<=0;
   in_end<=0;aux_end<=0;out_end<=0;in_cursor<=0;aux_cursor<=0;out_cursor<=0;
   word_initialized<=1'b0;best_initialized<=1'b0;load_y<=0;fill_bank<=0;cache_word<=0;up_read_index<=0;
   row_valid<=0;pool_oy<=0;pool_ox<=0;pool_cw<=0;pool_ky<=0;pool_kx<=0;
   up_x<=0;up_cw<=0;up_hrep<=0;up_vrep<=0;
   pool_pending<=0;pool_pending_last<=0;pool_scan_done<=0;
   pool_scan_x<=0;pool_stage_index<=0;pool_emit_word<=0;pool_lane_mask<=0;
   up_row_words_left<=0;
   stream_head_valid<=0;stream_ram_valid<=0;stream_issued<=0;stream_base<=0;
   for(integer b=0;b<5;b++)row_tag[b]<=0;
  end else begin
   if(state==STREAM_WRITE)begin
    if(stream_fire)begin stream_head_valid<=0;batch_write_live<=1;partial_output<=1;end
    if(stream_move)begin word_payload<=ram_rdata;word_initialized<=1;stream_head_valid<=1;stream_ram_valid<=0;end
    if(stream_read)begin stream_ram_valid<=1;stream_issued<=stream_issued+1'b1;end
   end
   if(state!=POOL_STREAM&&state!=POOL_PARALLEL)begin pool_pending<=0;pool_pending_last<=0;end
   if(busy)active_cycles<=active_cycles+1'b1;
   if(dma_req_valid&&!dma_req_ready||dma_rsp_ready&&!dma_rsp_valid)
    stall_cycles<=stall_cycles+1'b1;
   if(cancel&&busy)cancel_q<=1;
   case(state)
    IDLE:if(start&&!protocol_poison)begin
     in_q<=input_base;aux_q<=aux_base;out_q<=output_base;
     pixels_q<=pixels;in_c_q<=input_channels;aux_c_q<=aux_channels;
     mode_q<=operation;h_q<=image_h;w_q<=image_w;cancel_q<=0;
     partial_output<=0;error_sticky<=0;read_bytes<=0;write_bytes<=0;
     active_cycles<=0;stall_cycles<=0;row_valid<=0;state<=PRODUCTS;
    end
    PRODUCTS:begin
     in_length<=48'(pixels_q)*48'(in_c_q);
     aux_length<=48'(pixels_q)*48'(aux_c_q);state<=LENGTHS;
    end
    LENGTHS:begin
     case(mode_q)
      CAT:out_length<={1'b0,in_length}+{1'b0,aux_length};
      ADD:begin out_length<={1'b0,in_length};aux_length<=in_length;end
      UP:begin out_length<={1'b0,in_length}<<2;aux_length<=0;end
      POOL:begin out_length<={1'b0,in_length};aux_length<=0;end
     endcase
     state<=ENDS;
    end
    ENDS:begin
     in_end<={32'd0,in_q}+{16'd0,in_length};
     aux_end<={32'd0,aux_q}+{16'd0,aux_length};
     out_end<={32'd0,out_q}+{15'd0,out_length};state<=CHECK;
    end
    CHECK:begin
     if(pixels_q==0||in_c_q==0|| |in_c_q[3:0]||
       |in_q[3:0]|| |out_q[3:0]||
       (mode_q==CAT&&(aux_c_q==0|| |aux_c_q[3:0]|| |aux_q[3:0]||
        ({1'b0,in_c_q}+{1'b0,aux_c_q})>17'd65535))||
       (mode_q==ADD&&(aux_c_q!=0|| |aux_q[3:0]))||
       ((mode_q==UP||mode_q==POOL)&&(aux_q!=0||aux_c_q!=0))||
       (mode_q==POOL&&!(h_q==10&&w_q==10&&in_c_q==128&&pixels_q==100))||
       (mode_q==UP&&!((h_q==10&&w_q==10&&in_c_q==128&&pixels_q==100)||
                       (h_q==20&&w_q==20&&in_c_q==64&&pixels_q==400))))begin
      error_sticky<=BAD_SHAPE;state<=FINISH;
     end else if(in_q<DDR_BASE||out_q<DDR_BASE||in_end>DDR_LIMIT||out_end>DDR_LIMIT||
       in_length>{16'd0,DDR_BYTES}||out_length>{17'd0,DDR_BYTES}||
       overlaps(in_q,out_q,in_end,out_end)||
       (aux_length!=0&&(aux_q<DDR_BASE||aux_end>DDR_LIMIT||
        aux_length>{16'd0,DDR_BYTES}||overlaps(in_q,aux_q,in_end,aux_end)||
        overlaps(aux_q,out_q,aux_end,out_end))))begin
      error_sticky<=BAD_RANGE;state<=FINISH;
     end else if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else begin
      in_cursor<=in_q;aux_cursor<=aux_q;out_cursor<=out_q;bytes_left<=32'(in_length);
      pixels_left<=pixels_q;segment_left<=in_c_q;aux_segment<=0;
      pool_oy<=0;pool_ox<=0;pool_cw<=0;load_y<=0;fill_bank<=0;cache_word<=0;
      if(tensor_batch_mode)state<=BATCH_BEGIN;
      else if(mode_q==CAT)begin read_kind<=RK_CAT;state<=READ_REQ;end
      else if(mode_q==ADD)begin read_kind<=RK_A;state<=READ_REQ;end
      else state<=PREP;
     end
    end
    PREP:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else if(mode_q==UP||(load_y<10&&load_y<=({1'b0,pool_oy}+5'd2)))begin
      row_valid[mode_q==UP?0:fill_bank]<=0;cache_word<=0;
      read_kind<=RK_CACHE;state<=READ_REQ;
     end else state<=POOL_INIT;
    // A presented request is never withdrawn by cancel. It remains stable,
    // then the real response is drained before any terminal completion.
    READ_REQ:if(dma_req_ready)state<=READ_WAIT;
    READ_WAIT:if(dma_rsp_valid)begin
     if(dma_rsp_write||dma_rsp_id!=0)begin
      error_sticky<=BAD_RESPONSE;protocol_poison<=1;state<=FINISH;
     end else if(dma_rsp_error)begin error_sticky<=READ_ERROR;state<=FINISH;end
     else if(abort_now)begin
      // Drain every native response of an accepted read burst on cancellation.
      if(response_last)begin error_sticky<=CANCELLED;state<=FINISH;end
     end
     else begin
      read_bytes<=read_bytes+32'd16;
      case(read_kind)
       RK_CAT:begin word_payload<=dma_rsp_rdata;word_initialized<=1'b1;state<=WRITE_REQ;end
       RK_A:begin word_payload<=dma_rsp_rdata;word_initialized<=1'b1;read_kind<=RK_B;state<=READ_REQ;end
       RK_B:begin word_payload<=lane_result;word_initialized<=1'b1;state<=WRITE_REQ;end
       RK_BLOCK_A,RK_BLOCK_B:begin
        if(response_last)begin
         batch_fill<=0;
         if(batch_a&&(mode_q==ADD||paired_cat))begin read_kind<=RK_BLOCK_B;state<=READ_REQ;end
         else begin batch_output<=0;state<=OUTPUT_PIPELINE&&mode_q!=ADD?STREAM_INIT:BATCH_READ;end
        end else batch_fill<=batch_fill+1'b1;
       end
       RK_CACHE:begin
        in_cursor<=in_cursor+32'd16;
        if(cache_word==79)begin
         row_valid[mode_q==UP?0:fill_bank]<=1;
         row_tag[mode_q==UP?0:fill_bank]<=load_y;
         load_y<=load_y+1'b1;cache_word<=0;
         if(mode_q==POOL)begin fill_bank<=fill_bank==4?0:fill_bank+1'b1;state<=PREP;end
         else begin
          up_x<=0;up_cw<=0;up_hrep<=0;up_vrep<=0;up_read_index<=0;
          up_row_words_left<=9'd320;state<=burst_up?UP_PACKET_BEGIN:UP_READ;
         end
        end else begin cache_word<=cache_word+1'b1;state<=response_last?READ_REQ:READ_WAIT;end
       end
      endcase
     end
    end
    BATCH_BEGIN:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else begin batch_words<=5'(batch_limit);batch_fill<=0;read_kind<=RK_BLOCK_A;state<=READ_REQ;end
    BATCH_READ:if(abort_now&&!batch_write_live)begin error_sticky<=CANCELLED;state<=FINISH;end
     else state<=BATCH_LATCH;
    BATCH_LATCH:if(abort_now&&!batch_write_live)begin error_sticky<=CANCELLED;state<=FINISH;end
     else begin word_payload<=ram_rdata;word_initialized<=1'b1;state<=mode_q==ADD?BATCH_ADD:WRITE_REQ;end
    BATCH_ADD:if(abort_now&&!batch_write_live)begin error_sticky<=CANCELLED;state<=FINISH;end
     else begin word_payload<=lane_result;word_initialized<=1'b1;state<=WRITE_REQ;end
    STREAM_INIT:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else begin
      stream_head_valid<=0;stream_ram_valid<=0;stream_issued<=0;
      stream_base<=burst_up?9'd320-up_row_words_left:9'd400+9'(pool_emit_word);
      state<=STREAM_WRITE;
     end
    POOL_INIT:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else begin
      best_payload<={16{8'h80}};best_initialized<=1'b1;pool_ky<=0;pool_kx<=0;
      pool_scan_done<=0;pool_pending<=0;pool_pending_last<=0;
      pool_scan_x<=0;pool_stage_index<=0;pool_lane_mask<=0;
      // Payload is initialized on entry, never reset into a large control net.
      for(integer g=0;g<5;g=g+1)pool_maxima[g]<={16{8'h80}};
      state<=parallel_pool?POOL_PARALLEL:(PIPELINED_POOL?POOL_STREAM:POOL_SCAN);
     end
    POOL_PARALLEL:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else if(!pool_scan_done&&pool_in_bounds&&!pool_bank_found)begin
      error_sticky<=BAD_OWNER;state<=FINISH;
     end else begin
      if(pool_pending)for(integer g=0;g<5;g=g+1)if(pool_lane_mask[g])
       pool_maxima[g]<=max_i8x16(pool_maxima[g],ram_rdata);
      if(pool_pending_last)begin pool_pending<=0;state<=POOL_STAGE;end
      else begin
       pool_pending<=!pool_scan_done&&pool_in_bounds&&pool_bank_found;
       for(integer g=0;g<5;g=g+1)pool_lane_mask[g]<=pool_scan_x>=4'(g)&&pool_scan_x<4'(g+5);
       pool_pending_last<=!pool_scan_done&&pool_ky==4&&pool_scan_x==8;
       if(!pool_scan_done)begin
        if(pool_ky==4&&pool_scan_x==8)pool_scan_done<=1;
        else if(pool_scan_x==8)begin pool_scan_x<=0;pool_ky<=pool_ky+1'b1;end
        else pool_scan_x<=pool_scan_x+1'b1;
       end
      end
     end
    POOL_STAGE:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else if(pool_stage_index==4)begin
      pool_stage_index<=0;
      if(pool_cw==7)begin pool_cw<=0;pool_emit_word<=0;state<=POOL_SEND_BEGIN;end
      else begin pool_cw<=pool_cw+1'b1;state<=POOL_INIT;end
     end else pool_stage_index<=pool_stage_index+1'b1;
    POOL_SEND_BEGIN:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else begin batch_words<=5'(pool_packet_words);batch_output<=0;state<=OUTPUT_PIPELINE?STREAM_INIT:BATCH_READ;end
    // Reuse the same cached input row for all four nearest-neighbour copies.
    // Only the current native packet is live; retire its genuine B before
    // starting another packet or replacing the row. No second payload RAM.
    UP_PACKET_BEGIN:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else if(!row_valid[0]||row_tag[0]!=(load_y-1'b1))begin error_sticky<=BAD_OWNER;state<=FINISH;end
     else begin batch_words<=5'(up_packet_words);batch_output<=0;state<=OUTPUT_PIPELINE?STREAM_INIT:BATCH_READ;end
    POOL_STREAM:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else if(pool_pending_last)begin
      word_payload<=pool_stream_value;word_initialized<=1'b1;state<=WRITE_REQ;
      pool_pending<=0;pool_pending_last<=0;
     end else if(!pool_scan_done&&pool_in_bounds&&!pool_bank_found)begin
      error_sticky<=BAD_OWNER;state<=FINISH;
     end else begin
      if(pool_pending)begin best_payload<=lane_result;best_initialized<=1'b1;end
      pool_pending<=!pool_scan_done&&pool_in_bounds&&pool_bank_found;
      pool_pending_last<=!pool_scan_done&&pool_ky==4&&pool_kx==4;
      if(!pool_scan_done)begin
       if(pool_ky==4&&pool_kx==4)pool_scan_done<=1;
       else if(pool_kx==4)begin pool_kx<=0;pool_ky<=pool_ky+1'b1;end
       else pool_kx<=pool_kx+1'b1;
      end
     end
    POOL_SCAN:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else if(!pool_in_bounds)advance_pool(best_q);
     else if(!pool_bank_found)begin error_sticky<=BAD_OWNER;state<=FINISH;end
     else state<=POOL_REDUCE;
    POOL_REDUCE:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else begin best_payload<=lane_result;best_initialized<=1'b1;advance_pool(lane_result);end
    UP_READ:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else if(!row_valid[0]||row_tag[0]!=(load_y-1'b1))begin error_sticky<=BAD_OWNER;state<=FINISH;end
     else state<=UP_LATCH;
    UP_LATCH:if(abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else begin word_payload<=ram_rdata;word_initialized<=1'b1;state<=WRITE_REQ;end
    WRITE_REQ:if(dma_req_ready)begin
     partial_output<=1;
     if(batch_write_mode)batch_write_live<=1;
     state<=batch_write_mode&&batch_output+1'b1<batch_words?WRITE_STEP:WRITE_WAIT;
    end
    STREAM_WRITE,WRITE_WAIT,WRITE_STEP:begin
     if(state==STREAM_WRITE&&abort_now&&!batch_write_live&&!stream_head_valid)begin error_sticky<=CANCELLED;state<=FINISH;end
     else if(state==STREAM_WRITE&&stream_fire&&!stream_nonlast)state<=WRITE_WAIT;
     if(state==WRITE_STEP||stream_nonlast||(state==WRITE_WAIT&&dma_rsp_valid))begin
     if(state==WRITE_WAIT)batch_write_live<=0;
     if(state==WRITE_WAIT&&(!dma_rsp_write||dma_rsp_id!=1))begin
      error_sticky<=BAD_RESPONSE;protocol_poison<=1;state<=FINISH;
     end else if(state==WRITE_WAIT&&dma_rsp_error)begin error_sticky<=WRITE_ERROR;state<=FINISH;end
     else if(state==WRITE_WAIT&&abort_now)begin error_sticky<=CANCELLED;state<=FINISH;end
     else begin
      if(state==WRITE_WAIT)write_bytes<=write_bytes+(batch_write_mode?(32'(batch_words)<<4):32'd16);
      out_cursor<=out_cursor+32'd16;
      case(mode_q)
       CAT:begin
        if(aux_segment)aux_cursor<=aux_cursor+32'd16;else in_cursor<=in_cursor+32'd16;
        if(segment_left==16)begin
         if(!aux_segment)begin aux_segment<=1;segment_left<=aux_c_q;state<=READ_REQ;end
         else if(pixels_left==1)begin partial_output<=0;state<=FINISH;end
         else begin aux_segment<=0;segment_left<=in_c_q;pixels_left<=pixels_left-1'b1;state<=READ_REQ;end
        end else begin segment_left<=segment_left-16'd16;state<=READ_REQ;end
        if(tensor_batch_mode&&!(aux_segment&&segment_left==16&&pixels_left==1))begin
         if(batch_output+1'b1<batch_words)begin batch_output<=batch_output+1'b1;state<=BATCH_READ;end
         else state<=BATCH_BEGIN;
        end
       end
       ADD:if(bytes_left==16)begin partial_output<=0;state<=FINISH;end
        else begin
         bytes_left<=bytes_left-32'd16;in_cursor<=in_cursor+32'd16;aux_cursor<=aux_cursor+32'd16;
         read_kind<=RK_A;state<=READ_REQ;
         if(READ_BURST_ENABLE)begin
          if(batch_output+1'b1<batch_words)begin batch_output<=batch_output+1'b1;state<=BATCH_READ;end
          else state<=BATCH_BEGIN;
         end
        end
       POOL:if(parallel_pool)begin
        if(pool_emit_word==39)begin
         pool_emit_word<=0;pool_cw<=0;
         if(pool_ox==0)begin pool_ox<=5;state<=POOL_INIT;end
         else begin
          pool_ox<=0;
          if(pool_oy==9)begin partial_output<=0;state<=FINISH;end
          else begin pool_oy<=pool_oy+1'b1;state<=PREP;end
         end
        end else begin
         pool_emit_word<=pool_emit_word+1'b1;
         if(batch_output+1'b1<batch_words)begin batch_output<=batch_output+1'b1;state<=BATCH_READ;end
         else state<=POOL_SEND_BEGIN;
        end
       end else begin
        state<=POOL_INIT;
        if(pool_cw==7)begin
         pool_cw<=0;
         if(pool_ox==9)begin
          pool_ox<=0;
          if(pool_oy==9)begin partial_output<=0;state<=FINISH;end
          else begin pool_oy<=pool_oy+1'b1;state<=PREP;end
         end else pool_ox<=pool_ox+1'b1;
        end else pool_cw<=pool_cw+1'b1;
       end
       UP:begin
        state<=up_lookahead?UP_LATCH:UP_READ;
        if(burst_up)begin
         up_row_words_left<=up_row_words_left-1'b1;
         if(batch_output+1'b1<batch_words)begin batch_output<=batch_output+1'b1;state<=BATCH_READ;end
         else state<=UP_PACKET_BEGIN;
        end
        if({1'b0,up_cw}==channel_words-1'b1)begin
         up_cw<=0;
         if(!up_hrep)begin up_hrep<=1;up_read_index<=up_read_index-(7'(channel_words)-7'd1);end
         else begin
          up_hrep<=0;
          if({11'd0,up_x}==w_q-1'b1)begin
           up_x<=0;up_read_index<=0;
           if(!up_vrep)up_vrep<=1;
           else begin
            up_vrep<=0;
            if({11'd0,load_y}==h_q)begin partial_output<=0;state<=FINISH;end
            else state<=PREP;
           end
          end else begin up_x<=up_x+1'b1;up_read_index<=up_read_index+1'b1;end
         end
        end else begin up_cw<=up_cw+1'b1;up_read_index<=up_read_index+1'b1;end
       end
      endcase
      if(state==STREAM_WRITE)begin batch_output<=batch_output+1'b1;state<=STREAM_WRITE;end
     end
    end
    end
    FINISH:begin done_pulse<=1;state<=IDLE;end
    default:begin error_sticky<=BAD_RESPONSE;protocol_poison<=1;state<=FINISH;end
   endcase
  end
 end
 // synthesis translate_off
 always_ff @(posedge clk)if(!rst)begin
  if(ram_wr&&ram_rd)$fatal(1,"SHARED_TENSOR_UNPROVED_RAM_COLLISION_RED");
  if(ram_wr&&ram_waddr>=(parallel_pool?440:400))$fatal(1,"SHARED_TENSOR_PAYLOAD_WRITE_BOUNDS_RED");
  if(ram_rd&&ram_raddr>=(parallel_pool?440:400))$fatal(1,"SHARED_TENSOR_PAYLOAD_READ_BOUNDS_RED");
  if(paired_cat&&state==BATCH_BEGIN&&(pair_pixels==0||aux_segment))$fatal(1,"PAIRED_CAT_GEOMETRY_RED");
  if(parallel_pool&&state==POOL_STAGE&&pool_stage_index>=5)$fatal(1,"PARALLEL_POOL_STAGE_RED");
  if(burst_up&&state==UP_PACKET_BEGIN&&up_packet_words==0)$fatal(1,"UP_BURST_GEOMETRY_RED");
  if(burst_up&&state==BATCH_READ&&(!row_valid[0]||row_tag[0]!=(load_y-1'b1)))$fatal(1,"UP_BURST_ROW_OWNER_RED");
  if(state==STREAM_WRITE&&(mode_q==ADD||!batch_write_mode||stream_issued>batch_words))$fatal(1,"TENSOR_STREAM_GEOMETRY_RED");
  if(state==STREAM_WRITE&&stream_fire&&batch_output+1'b1==batch_words&&(stream_issued!=batch_words||stream_ram_valid||stream_read))$fatal(1,"TENSOR_STREAM_TERMINAL_TOKEN_RED");
 end
 // synthesis translate_on
endmodule
