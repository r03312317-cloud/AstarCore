`timescale 1ns/1ps
// Unmerged model-oriented operand store, not a DMA or a second Scheduler.
// INT8 only. INT16 must continue through the original validated hardware path.
// A16/B128 candidate: two16-row slots and bounded K/N-page B residency.
// Default physical allocation64KiB A +128KiB B. A32/B256 remains parameterized.
// B uses a linear packed address, not a wasteful maxN-by-maxK rectangle.
// Each physical lane has one synchronous read and one wholeword write port.
// K64 pages use the low6bits of k; highbits select resident pages. Payload
// reset is forbidden: only complete, exact-identity generations may be read.
module npu_resident_ab #(parameter int A_ROWS_PER_SLOT=16,B_PAIR_ADDR_W=13)(
 input logic clk,rst,
 input logic a_begin,a_slot,
 input logic [255:0] a_identity,
 input logic [5:0] a_rows,
 input logic [10:0] a_k_length,
 output logic a_begin_ready,a_reuse_hit,
 input logic a_write_valid,
 input logic [4:0] a_write_row,
 input logic [10:0] a_write_k,
 input logic [127:0] a_write_word,
 output logic a_write_ready,
 input logic a_commit,a_real_responses_retired,a_abort,
 input logic b_begin,
 input logic [255:0] b_identity,
 input logic [8:0] b_columns,
 input logic [10:0] b_k_length,
 output logic b_begin_ready,b_reuse_hit,
 input logic b_write_valid,
 input logic [4:0] b_write_group,
 input logic [10:0] b_write_k,
 input logic [127:0] b_write_pair,
 output logic b_write_ready,
 input logic b_commit,b_real_responses_retired,b_abort,
 input logic invalidate_a,invalidate_a_slot,invalidate_b,
 input logic claim,
 input logic claim_a_slot,claim_m16,
 input logic [4:0] claim_n8,
 input logic [255:0] expected_a_identity,expected_b_identity,
 output logic claim_ready,
 input logic release_compute,
 input logic read_valid,
 input logic [10:0] read_k,
 output logic read_ready,vector_valid,
 output logic [255:0] a_vector,
 output logic [127:0] b_vector,
 output logic compute_active,protocol_poison,
 output logic [3:0] a_owners,
 output logic [1:0] b_owner,
 output logic [31:0] a_words_written,b_words_written,
 output logic [31:0] a_reuse_count,b_reuse_count
);
 localparam logic [1:0] EMPTY=0,FILLING=1,READY=2,COMPUTE=3;
 localparam int A_ADDR_W=A_ROWS_PER_SLOT==32?9:8;
 initial begin
  if((A_ROWS_PER_SLOT!=16&&A_ROWS_PER_SLOT!=32)||(B_PAIR_ADDR_W!=13&&B_PAIR_ADDR_W!=14))
   $fatal(1,"RESIDENT_FIXED_BANK_CAPACITY_UNSUPPORTED");
 end
 logic [1:0] ast[0:1],bst;
 logic [255:0] ak[0:1],bk;
 logic [5:0] ar[0:1];
 logic [10:0] alen[0:1],blen;
 logic [8:0] bc;
 logic [4:0] next_arow[0:1];
 logic [10:0] next_ak[0:1],next_bk;
 logic [4:0] next_bg;
 logic [B_PAIR_ADDR_W-1:0] b_linear_q,active_b_base;
 logic [B_PAIR_ADDR_W-1:0] b_group_base[0:31];
 wire [16:0] b_required_words=17'(({1'b0,b_columns}+10'd7)>>3)*
                                   17'(({1'b0,b_k_length}+12'd1)>>1);
 logic afull[0:1],bfull;
 logic active_slot,active_m16;
 logic [4:0] active_rows;
 logic [3:0] active_cols;
 logic [10:0] active_k;
 logic [3:0] a_sub_q;
 logic b_sub_q;
 wire a_shape_ok=a_rows!=0&&a_rows<=A_ROWS_PER_SLOT&&a_k_length!=0&&a_k_length<=1152;
 wire b_shape_ok=b_columns!=0&&b_columns<=256&&b_k_length!=0&&b_k_length<=1152&&b_required_words<=(17'(1)<<B_PAIR_ADDR_W);
 wire a_hit=ast[a_slot]==READY&&ak[a_slot]==a_identity&&ar[a_slot]==a_rows&&alen[a_slot]==a_k_length;
 wire b_hit=bst==READY&&bk==b_identity&&bc==b_columns&&blen==b_k_length;
 assign a_begin_ready=!rst&&!protocol_poison&&ast[a_slot]!=COMPUTE&&ast[a_slot]!=FILLING;
 assign b_begin_ready=!rst&&!protocol_poison&&bst!=COMPUTE&&bst!=FILLING;
 // Writes are in a deterministic order. Holes/duplicates cannot be hidden
 // by a final valid bit; the last accepted wholeword proves full coverage.
 assign a_write_ready=!rst&&!protocol_poison&&ast[a_slot]==FILLING&&!afull[a_slot]&&
   a_write_row==next_arow[a_slot]&&a_write_k==next_ak[a_slot]&&a_write_k[3:0]==0;
 assign b_write_ready=!rst&&!protocol_poison&&bst==FILLING&&!bfull&&
   b_write_group==next_bg&&b_write_k==next_bk&&b_write_k[0]==0;
 wire aw=a_write_valid&&a_write_ready;
 wire bw=b_write_valid&&b_write_ready;
 wire [8:0] claim_col_first={claim_n8,3'b000};
 wire [5:0] claim_row_first=claim_m16?6'd16:6'd0;
 assign compute_active=bst==COMPUTE;
 assign claim_ready=!rst&&!protocol_poison&&!compute_active&&ast[claim_a_slot]==READY&&bst==READY&&
  ak[claim_a_slot]==expected_a_identity&&bk==expected_b_identity&&alen[claim_a_slot]==blen&&
  ar[claim_a_slot]>claim_row_first&&bc>claim_col_first&&(A_ROWS_PER_SLOT==32||!claim_m16);
 assign read_ready=!rst&&!protocol_poison&&compute_active&&read_k<active_k;
 wire rf=read_valid&&read_ready;
 wire [A_ADDR_W-1:0] a_wa,a_ra;
 if(A_ROWS_PER_SLOT==32)begin:g_a32_address
  assign a_wa={a_slot,a_write_row[4],a_write_k[10:4]};
  assign a_ra={active_slot,active_m16,read_k[10:4]};
 end else begin:g_a16_address
  assign a_wa={a_slot,a_write_k[10:4]};
  assign a_ra={active_slot,read_k[10:4]};
 end
 wire [B_PAIR_ADDR_W-1:0] b_wa=b_linear_q;
 wire [B_PAIR_ADDR_W-1:0] b_ra=active_b_base+B_PAIR_ADDR_W'(read_k[10:1]);
 assign a_owners={ast[1],ast[0]};assign b_owner=bst;
 for(genvar row=0;row<16;row++)begin:g_a
  wire [127:0] word_q;
  npu_resident_word_ram #(.WIDTH(128),.ADDR_W(A_ADDR_W)) ram(
   .clk,.wr_en(aw&&a_write_row[3:0]==4'(row)),.wr_addr(a_wa),.wr_data(a_write_word),
   .rd_en(rf),.rd_addr(a_ra),.rd_data(word_q));
  wire [7:0] byte_q=word_q[8*a_sub_q+:8];
  assign a_vector[row*16+:16]=vector_valid&&active_rows>row ? {{8{byte_q[7]}},byte_q}:16'd0;
 end
 for(genvar col=0;col<8;col++)begin:g_b
  wire [15:0] pair_q;
  npu_resident_word_ram #(.WIDTH(16),.ADDR_W(B_PAIR_ADDR_W)) ram(
   .clk,.wr_en(bw),.wr_addr(b_wa),.wr_data({b_write_pair[64+col*8+:8],b_write_pair[col*8+:8]}),
   .rd_en(rf),.rd_addr(b_ra),.rd_data(pair_q));
  wire [7:0] byte_q=b_sub_q?pair_q[15:8]:pair_q[7:0];
  assign b_vector[col*16+:16]=vector_valid&&active_cols>col ? {{8{byte_q[7]}},byte_q}:16'd0;
 end
 always_ff @(posedge clk)begin
  a_reuse_hit<=0;b_reuse_hit<=0;vector_valid<=0;
  if(rst)begin
   for(integer s=0;s<2;s++)begin ast[s]<=EMPTY;ak[s]<=0;ar[s]<=0;alen[s]<=0;next_arow[s]<=0;next_ak[s]<=0;afull[s]<=0;end
   bst<=EMPTY;bk<=0;bc<=0;blen<=0;next_bg<=0;next_bk<=0;bfull<=0;
   active_slot<=0;active_m16<=0;active_b_base<=0;b_linear_q<=0;active_rows<=0;active_cols<=0;active_k<=0;
   a_sub_q<=0;b_sub_q<=0;protocol_poison<=0;a_words_written<=0;b_words_written<=0;a_reuse_count<=0;b_reuse_count<=0;
  end else if(!protocol_poison)begin
   if(a_begin)begin
    if(!a_begin_ready||!a_shape_ok)protocol_poison<=1;
    else if(a_hit)begin a_reuse_hit<=1;a_reuse_count<=a_reuse_count+1'b1;end
    else begin
     ast[a_slot]<=FILLING;ak[a_slot]<=a_identity;ar[a_slot]<=a_rows;alen[a_slot]<=a_k_length;
     next_arow[a_slot]<=0;next_ak[a_slot]<=0;afull[a_slot]<=0;
    end
   end
   if(b_begin)begin
    if(!b_begin_ready||!b_shape_ok)protocol_poison<=1;
    else if(b_hit)begin b_reuse_hit<=1;b_reuse_count<=b_reuse_count+1'b1;end
    else begin bst<=FILLING;bk<=b_identity;bc<=b_columns;blen<=b_k_length;next_bg<=0;next_bk<=0;bfull<=0;b_linear_q<=0;end
   end
   if(a_write_valid)begin
    if(!a_write_ready)protocol_poison<=1;
    else begin
     a_words_written<=a_words_written+1'b1;
     if({1'b0,next_ak[a_slot]}+12'd16>= {1'b0,alen[a_slot]})begin
      next_ak[a_slot]<=0;
      if({1'b0,next_arow[a_slot]}+6'd1>=ar[a_slot])afull[a_slot]<=1;
      else next_arow[a_slot]<=next_arow[a_slot]+1'b1;
     end else next_ak[a_slot]<=next_ak[a_slot]+11'd16;
    end
   end
   if(b_write_valid)begin
    if(!b_write_ready)protocol_poison<=1;
    else begin
     b_words_written<=b_words_written+1'b1;b_linear_q<=b_linear_q+1'b1;
     if(next_bk==0)b_group_base[next_bg]<=b_linear_q;
     if({1'b0,next_bk}+12'd2>={1'b0,blen})begin
      next_bk<=0;
      if({1'b0,next_bg,3'b000}+9'd8>=bc)bfull<=1;
      else next_bg<=next_bg+1'b1;
     end else next_bk<=next_bk+11'd2;
    end
   end
   if(a_commit)begin
    if(ast[a_slot]!=FILLING||!afull[a_slot]||!a_real_responses_retired||aw||a_abort)protocol_poison<=1;
    else ast[a_slot]<=READY;
   end
   if(b_commit)begin
    if(bst!=FILLING||!bfull||!b_real_responses_retired||bw||b_abort)protocol_poison<=1;
    else bst<=READY;
   end
   if(a_abort)begin
    if(ast[a_slot]!=FILLING||a_write_valid||a_begin)protocol_poison<=1;
    else begin ast[a_slot]<=EMPTY;afull[a_slot]<=0;end
   end
   if(b_abort)begin
    if(bst!=FILLING||b_write_valid||b_begin)protocol_poison<=1;
    else begin bst<=EMPTY;bfull<=0;end
   end
   if(claim)begin
    if(!claim_ready||release_compute||a_begin&&a_slot==claim_a_slot||b_begin)protocol_poison<=1;
    else begin
     active_slot<=claim_a_slot;active_m16<=claim_m16;active_b_base<=b_group_base[claim_n8];
     active_rows<=ar[claim_a_slot]-claim_row_first>16 ? 5'd16:5'(ar[claim_a_slot]-claim_row_first);
     active_cols<=bc-claim_col_first>8 ? 4'd8:4'(bc-claim_col_first);active_k<=blen;
     ast[claim_a_slot]<=COMPUTE;bst<=COMPUTE;
    end
   end
   if(rf)begin vector_valid<=1;a_sub_q<=read_k[3:0];b_sub_q<=read_k[0];end
   if(read_valid&&!read_ready)protocol_poison<=1;
   if(release_compute)begin
    if(!compute_active||read_valid||vector_valid)protocol_poison<=1;
    else begin ast[active_slot]<=READY;bst<=READY;end
   end
   if(invalidate_a)begin
    if(ast[invalidate_a_slot]==COMPUTE||ast[invalidate_a_slot]==FILLING||a_begin||a_commit||aw||claim)protocol_poison<=1;
    else begin ast[invalidate_a_slot]<=EMPTY;afull[invalidate_a_slot]<=0;end
   end
   if(invalidate_b)begin
    if(bst==COMPUTE||bst==FILLING||b_begin||b_commit||bw||claim)protocol_poison<=1;
    else begin bst<=EMPTY;bfull<=0;end
   end
  end
 end
endmodule

// Wholeword writes avoid a multiported or per-byte replicated payload array.
// Caller guarantees no consumption of padding bytes beyond the committed K.
// This is a read-first, one-cycle synchronous1R1W RAM; payload has no reset.
module npu_resident_word_ram #(parameter int WIDTH=128,ADDR_W=9)(
 input logic clk,wr_en,input logic [ADDR_W-1:0] wr_addr,
 input logic [WIDTH-1:0] wr_data,input logic rd_en,
 input logic [ADDR_W-1:0] rd_addr,output logic [WIDTH-1:0] rd_data
);
 (* ram_style="block",syn_ramstyle="block_ram" *) logic [WIDTH-1:0] mem[0:(1<<ADDR_W)-1];
 always_ff @(posedge clk)begin
  if(wr_en)mem[wr_addr]<=wr_data;
  if(rd_en)rd_data<=mem[rd_addr];
 end
endmodule
