// Preserve the original initialized ITCM and convert its 32-bit responses
// into the eight 64-bit beats consumed by the complete RV32 instruction cache.
module rv32_d1_ifill #(
 parameter integer ITCM_ADDR_WIDTH=14,
 parameter ITCM_INIT_FILE="",
 parameter logic [31:0] DDR_BASE=32'h80000000,
 parameter logic [32:0] DDR_BYTES=33'h010000000
)(
 input logic clk,rst,input logic req,output logic gnt,input logic [31:0] addr,
 output logic rvalid,input logic rready,output logic [63:0] rdata,output logic error,
 output logic fault,
 output logic mem_req_valid,input logic mem_req_ready,output logic mem_req_write,
 output logic [31:0] mem_req_addr,output logic [127:0] mem_req_wdata,
 output logic [15:0] mem_req_wstrb,output logic [3:0] mem_req_tag,
 input logic mem_rsp_valid,output logic mem_rsp_ready,input logic mem_rsp_write,
 input logic [127:0] mem_rsp_rdata,input logic [3:0] mem_rsp_tag,input logic mem_rsp_error
);
 typedef enum logic[2:0]{IDLE,TCM_REQ,TCM_WAIT,TCM_OUT,DDR} state_t;
 state_t state;
 logic [31:0] base_q,lower_q;
 logic [3:0] word_q;
 logic error_q;
 logic [63:0] pair_q;
 wire select_tcm=addr>=32'h10000000&&{1'b0,addr}+33'd64<=33'h010000000+33'(4<<ITCM_ADDR_WIDTH);
 logic tv,tr,sv,sr,se;
 logic [31:0] td;
 logic dg,dv,de,unused_rid;
 logic [63:0] dd;
 assign gnt=!rst&&state==IDLE&&(select_tcm||dg);
 assign rvalid=state==TCM_OUT||((state==DDR)&&dv);
 assign rdata=state==TCM_OUT?pair_q:dd;
 assign error=state==TCM_OUT?error_q:de;
 assign tv=!rst&&state==TCM_REQ;
 assign sr=!rst&&state==TCM_WAIT;
 dc_realtime_core_itcm_channel #(.ADDR_WIDTH(ITCM_ADDR_WIDTH),.INIT_FILE(ITCM_INIT_FILE)) itcm(
  .clk,.rst,.req_valid(tv),.req_ready(tr),.req_addr(base_q+{26'd0,word_q,2'b00}),
  .rsp_valid(sv),.rsp_ready(sr),.rsp_rdata(td),.rsp_error(se));
 rv32_line128_adapter #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) ddr(
  .clk,.rst,.rd_req(req&&state==IDLE&&!select_tcm),.rd_gnt(dg),.rd_addr(addr),.rd_id(1'b0),
  .rd_valid(dv),.rd_ready(rready&&state==DDR),.rd_data(dd),.rd_error(de),.rd_rid(unused_rid),
  .wr_req(1'b0),.wr_gnt(),.wr_addr(32'd0),.wr_data(64'd0),.wr_last(1'b0),.wr_id(1'b0),
  .b_valid(),.b_error(),.b_id(),.fault,
  .mem_req_valid,.mem_req_ready,.mem_req_write,.mem_req_addr,.mem_req_wdata,.mem_req_wstrb,.mem_req_tag,
  .mem_rsp_valid,.mem_rsp_ready,.mem_rsp_write,.mem_rsp_rdata,.mem_rsp_tag,.mem_rsp_error);
 logic [2:0] ddr_beat;
 always_ff @(posedge clk)begin
  if(rst)begin state<=IDLE;base_q<=0;lower_q<=0;word_q<=0;pair_q<=0;error_q<=0;ddr_beat<=0;end
  else case(state)
   IDLE:if(req&&gnt)begin
    base_q<=addr;word_q<=0;error_q<=addr[5:0]!=0;ddr_beat<=0;
    state<=select_tcm?TCM_REQ:DDR;
   end
   TCM_REQ:if(tv&&tr)state<=TCM_WAIT;
   TCM_WAIT:if(sv&&sr)begin
    error_q<=error_q|se;
    if(word_q[0])begin pair_q<={td,lower_q};state<=TCM_OUT;end
    else begin lower_q<=td;word_q<=word_q+1'b1;state<=TCM_REQ;end
   end
   TCM_OUT:if(rvalid&&rready)begin
    if(word_q==15)state<=IDLE;
    else begin word_q<=word_q+1'b1;state<=TCM_REQ;end
   end
   DDR:if(dv&&rready)begin if(ddr_beat==7)state<=IDLE;else ddr_beat<=ddr_beat+1'b1;end
   default:state<=IDLE;
  endcase
 end
endmodule
