`timescale 1ns/1ps
// Opt-in candidate: blocking, two-way, synchronous 128-bit data RAM.
// D$: write-through/no-write-allocate. I$: cache-region only, no stores.
// CPU/data/CSR source files are NOT altered or selected by this module.
// Candidate RAM mapping refactor; see lab/docs and evidence for measured scope.
module pg_cache2way #(
 parameter integer CAPACITY_BYTES=16384,
 parameter integer LINE_BYTES=64,
 parameter bit READ_ONLY=1'b0,
 parameter logic [31:0] DDR_BASE=32'h80000000,
 parameter logic [32:0] DDR_BYTES=33'h010000000,
 parameter logic [31:0] CACHE_BASE=32'h84000000,
 parameter logic [32:0] CACHE_BYTES=33'h004000000
)(
 input logic clk,rst,
 input logic req_valid,req_write,req_fetch,
 input logic [31:0] req_addr,req_wdata,
 input logic [3:0] req_wstrb,
 output logic req_ready,
 output logic rsp_valid,rsp_error,
 output logic [31:0] rsp_rdata,
 input logic rsp_ready,
 input logic invalidate_valid,
 output logic invalidate_ready,invalidate_done,initialized,protocol_fault,
 output logic [31:0] hit_count,miss_count,bypass_count,
 output logic mem_req_valid,mem_req_write,
 output logic [31:0] mem_req_addr,
 output logic [127:0] mem_req_wdata,
 output logic [15:0] mem_req_wstrb,
 output logic [3:0] mem_req_tag,
 input logic mem_req_ready,mem_rsp_valid,mem_rsp_write,mem_rsp_error,
 input logic [127:0] mem_rsp_rdata,
 input logic [3:0] mem_rsp_tag,
 output logic mem_rsp_ready
);
 localparam integer SETS=CAPACITY_BYTES/(2*LINE_BYTES),BEATS=LINE_BYTES/16;
 localparam integer SB=$clog2(SETS),LB=$clog2(LINE_BYTES),BB=$clog2(BEATS),TB=32-LB-SB;
 typedef enum logic[3:0]{SWEEP,IDLE,LOOKUP,EVALUATE,FILL,SEND_ONE,WAIT_ONE,RETURN_RSP,FAULT} state_t;
 state_t state;
 // RAM write mux is outside storage: exactly one address and byte mask per way.
 localparam integer RAM_ADDR_W = SB + BB;
 logic [RAM_ADDR_W-1:0] ram_read_addr, ram_write_addr;
 logic [127:0] ram_write_data;
 logic [15:0] ram_write_mask, ram_we0, ram_we1;
 logic fill_write, store_write, ram_write_way;
 logic [TB-1:0] tag0[0:SETS-1],tag1[0:SETS-1];
 logic valid0[0:SETS-1],valid1[0:SETS-1],lru[0:SETS-1];
 logic [SB-1:0] sweep,qs;
 logic [TB-1:0] qt;
 logic [31:2] qa;
 logic [31:0] qd,word_saved;
 logic [3:0] qmask;
 logic lookup_hit0_q,lookup_hit1_q;
 logic qw,hit0,hit1,write_hit,write_way,victim,fill_error;
 logic [127:0] read0,read1;
 logic [BEATS-1:0] seen;
 integer unsigned sent,received;
 wire [BB-1:0] qbeat=qa[LB-1:4];
 wire [31:0] linebase={qa[31:LB],{LB{1'b0}}};
 wire [32:0] addr33={1'b0,req_addr};
 wire inside_ddr=addr33>={1'b0,DDR_BASE} && addr33<({1'b0,DDR_BASE}+DDR_BYTES);
 wire inside_cache=addr33>={1'b0,CACHE_BASE} && addr33<({1'b0,CACHE_BASE}+CACHE_BYTES);
 initial begin
  if(SETS<2||(SETS&(SETS-1))!=0||BEATS<2||BEATS>16||(BEATS&(BEATS-1))!=0||CAPACITY_BYTES!=SETS*2*LINE_BYTES)$fatal(1,"CACHE_PARAMETER");
  if((CACHE_BASE%LINE_BYTES)!=0||(CACHE_BYTES%33'(LINE_BYTES))!=0||CACHE_BASE<DDR_BASE||{1'b0,CACHE_BASE}+CACHE_BYTES>{1'b0,DDR_BASE}+DDR_BYTES||{1'b0,DDR_BASE}+DDR_BYTES>33'h100000000)$fatal(1,"CACHE_RANGE");
 end
 always_comb begin
  req_ready=(state==IDLE)&&!invalidate_valid&&!rst;
  rsp_valid=state==RETURN_RSP&&!rst;
  invalidate_ready=(state==IDLE)&&!rst;
  hit0=lookup_hit0_q;hit1=lookup_hit1_q;
  mem_req_valid=1'b0;mem_req_write=1'b0;mem_req_addr=0;mem_req_wdata=0;mem_req_wstrb=0;mem_req_tag=0;
  mem_rsp_ready=!rst&&(state==FILL||state==WAIT_ONE||state==FAULT);
  if(state==FILL&&sent<BEATS&&!rst)begin
   mem_req_valid=1;mem_req_addr=linebase+32'(sent*16);mem_req_tag=4'(sent);
  end
  if(state==SEND_ONE&&!rst)begin
   mem_req_valid=1;mem_req_write=qw;mem_req_addr={qa[31:4],4'b0};
   mem_req_wdata=128'(qd)<<(32*qa[3:2]);mem_req_wstrb=16'(qmask)<<(4*qa[3:2]);
  end
 end
 // Keep the original LOOKUP read edge and the exact write qualification.
 // Full-width tag validity is checked before narrowing to a RAM address.
 assign ram_read_addr = {qs,qbeat};
 assign fill_write = !rst && state==FILL && mem_rsp_valid && mem_rsp_ready
                   && !mem_rsp_write && integer'(mem_rsp_tag)<sent
                   && !seen[BB'(mem_rsp_tag)] && !mem_rsp_error;
 if (READ_ONLY) begin : g_no_store_port
  assign store_write = 1'b0;
 end else begin : g_store_port
  assign store_write = !rst && state==WAIT_ONE && mem_rsp_valid && mem_rsp_ready
                    && mem_rsp_tag==0 && mem_rsp_write==qw && !mem_rsp_error
                    && qw && write_hit;
 end
 always_comb begin
  ram_write_addr = ram_read_addr;
  ram_write_data = 128'b0;
  ram_write_mask = 16'b0;
  ram_write_way = write_way;
  if (fill_write) begin
   ram_write_addr = {qs,BB'(mem_rsp_tag)};
   ram_write_data = mem_rsp_rdata;
   ram_write_mask = 16'hffff;
   ram_write_way = victim;
  end else if (store_write) begin
   // Broadcast qd; only the selected 32-bit bank has enabled bytes.
   // The physical storage process contains no dynamic write part-select.
   for (integer word_lane=0; word_lane<4; word_lane=word_lane+1) begin
    ram_write_data[word_lane*32 +: 32] = qd;
    ram_write_mask[word_lane*4 +: 4] = (qa[3:2]==2'(word_lane)) ? qmask : 4'b0;
   end
  end
  ram_we0 = ram_write_way ? 16'b0 : ram_write_mask;
  ram_we1 = ram_write_way ? ram_write_mask : 16'b0;
 end
 pg_cache_data_ram #(.ADDR_WIDTH(RAM_ADDR_W)) u_data_way0 (
  .clk(clk), .rd_en(state==LOOKUP), .rd_addr(ram_read_addr), .rd_data(read0),
  .wr_addr(ram_write_addr), .wr_data(ram_write_data), .wr_byte_en(ram_we0)
 );
 pg_cache_data_ram #(.ADDR_WIDTH(RAM_ADDR_W)) u_data_way1 (
  .clk(clk), .rd_en(state==LOOKUP), .rd_addr(ram_read_addr), .rd_data(read1),
  .wr_addr(ram_write_addr), .wr_data(ram_write_data), .wr_byte_en(ram_we1)
 );
 always_ff @(posedge clk)begin
  if(rst)begin
   lookup_hit0_q<=0;lookup_hit1_q<=0;
   state<=SWEEP;sweep<='0;initialized<=0;invalidate_done<=0;protocol_fault<=0;
   hit_count<=0;miss_count<=0;bypass_count<=0;rsp_error<=0;rsp_rdata<=0;
   qs<=0;qt<=0;qa<=0;qd<=0;qmask<=0;qw<=0;write_hit<=0;write_way<=0;victim<=0;seen<=0;sent<=0;received<=0;fill_error<=0;word_saved<=0;
  end else begin
   invalidate_done<=0;
   case(state)
    SWEEP:begin valid0[sweep]<=0;valid1[sweep]<=0;lru[sweep]<=0;
     if(integer'(sweep)==SETS-1)begin initialized<=1;invalidate_done<=1;state<=IDLE;end else sweep<=sweep+1'b1;end
    IDLE:begin
     if(invalidate_valid)begin sweep<=0;initialized<=0;state<=SWEEP;end
     else if(req_valid&&req_ready)begin
      qa<=req_addr[31:2];qd<=req_wdata;qmask<=req_wstrb;qw<=req_write;
      qs<=req_addr[LB+:SB];qt<=req_addr[31:LB+SB];rsp_error<=0;rsp_rdata<=0;write_hit<=0;
      if(!inside_ddr||(READ_ONLY&&(req_write||!req_fetch||!inside_cache||req_addr[1:0]!=0))||(!READ_ONLY&&req_fetch))begin rsp_error<=1;state<=RETURN_RSP;end
      else if(req_write&&req_wstrb==0)state<=RETURN_RSP;
      else if(!inside_cache)begin bypass_count<=bypass_count+1'b1;state<=SEND_ONE;end
      else state<=LOOKUP;
     end
    end
    // Tag compare runs in parallel with synchronous data RAM read, not after
    // it. Blocking FSM prevents metadata changes between this edge and EVALUATE.
    LOOKUP:begin
     lookup_hit0_q<=valid0[qs]&&tag0[qs]==qt;
     lookup_hit1_q<=valid1[qs]&&tag1[qs]==qt;
     state<=EVALUATE;
    end
    EVALUATE:begin
     if(hit0&&hit1)begin protocol_fault<=1;state<=FAULT;end
     else if(hit0||hit1)begin
      hit_count<=hit_count+1'b1;lru[qs]<=hit0;write_hit<=qw;write_way<=hit1;
      if(qw)state<=SEND_ONE;
      else begin rsp_rdata<=hit1?read1[qa[3:2]*32+:32]:read0[qa[3:2]*32+:32];state<=RETURN_RSP;end
     end else begin
      miss_count<=miss_count+1'b1;
      if(qw)state<=SEND_ONE;
      else begin victim<=!valid0[qs]?1'b0:(!valid1[qs]?1'b1:lru[qs]);
       if(!valid0[qs])valid0[qs]<=0;else if(!valid1[qs])valid1[qs]<=0;else if(lru[qs])valid1[qs]<=0;else valid0[qs]<=0;
       sent<=0;received<=0;seen<=0;fill_error<=0;word_saved<=0;state<=FILL;
      end
     end
    end
    FILL:begin
     if(mem_req_valid&&mem_req_ready)sent<=sent+1;
     if(mem_rsp_valid&&mem_rsp_ready)begin
      if(mem_rsp_write||integer'(mem_rsp_tag)>=sent||seen[BB'(mem_rsp_tag)])begin protocol_fault<=1;state<=FAULT;end
      else begin
       seen[BB'(mem_rsp_tag)]<=1;received<=received+1;fill_error<=fill_error||mem_rsp_error;
       if(integer'(mem_rsp_tag)==integer'(qbeat))word_saved<=mem_rsp_rdata[qa[3:2]*32+:32];
       if(received==BEATS-1)begin
        rsp_error<=fill_error||mem_rsp_error;
        rsp_rdata<=(fill_error||mem_rsp_error)?32'b0:((integer'(mem_rsp_tag)==integer'(qbeat))?mem_rsp_rdata[qa[3:2]*32+:32]:word_saved);
        if(!fill_error&&!mem_rsp_error)begin
         if(victim)begin tag1[qs]<=qt;valid1[qs]<=1;end else begin tag0[qs]<=qt;valid0[qs]<=1;end
         lru[qs]<=!victim;
        end
        state<=RETURN_RSP;
       end
      end
     end
    end
    SEND_ONE:if(mem_req_valid&&mem_req_ready)state<=WAIT_ONE;
    WAIT_ONE:if(mem_rsp_valid&&mem_rsp_ready)begin
     if(mem_rsp_tag!=0||mem_rsp_write!=qw)begin protocol_fault<=1;state<=FAULT;end
     else begin
      rsp_error<=mem_rsp_error;rsp_rdata<=mem_rsp_error||qw?32'b0:mem_rsp_rdata[qa[3:2]*32+:32];
      if(qw&&write_hit&&mem_rsp_error)begin if(write_way)valid1[qs]<=0;else valid0[qs]<=0;end
      state<=RETURN_RSP;
     end
    end
    RETURN_RSP:if(rsp_ready)state<=IDLE;
    FAULT:begin end
    default:begin protocol_fault<=1;state<=FAULT;end
   endcase
  end
 end
endmodule
