// Optional board peripheral window. One owner is held until its response is
// consumed. All signals are synchronous to cpu_clk; CDC belongs downstream.
module soc_board_mmio_router #(
 parameter logic [31:0] BOARD_BASE=32'h60001000
)(
 input logic clk,rst,
 input logic req_valid,output logic req_ready,
 input logic [31:0] req_addr,req_wdata,
 input logic req_write,req_is_fetch,input logic [3:0] req_wstrb,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_rdata,output logic rsp_error,
 output logic [1:0] m_req_valid,input logic [1:0] m_req_ready,
 output logic [31:0] m_req_addr,m_req_wdata,
 output logic m_req_write,m_req_is_fetch,output logic [3:0] m_req_wstrb,
 input logic [1:0] m_rsp_valid,output logic [1:0] m_rsp_ready,
 input logic [1:0][31:0] m_rsp_rdata,input logic [1:0] m_rsp_error
);
 logic busy,owner;
 wire select_board=req_addr[31:12]==BOARD_BASE[31:12];
 assign m_req_addr=req_addr;
 assign m_req_wdata=req_wdata;
 assign m_req_write=req_write;
 assign m_req_is_fetch=req_is_fetch;
 assign m_req_wstrb=req_wstrb;
 assign m_req_valid=(!rst&&!busy&&req_valid)?(select_board?2'b10:2'b01):2'b00;
 assign req_ready=!rst&&!busy&&m_req_ready[select_board];
 assign rsp_valid=!rst&&busy&&m_rsp_valid[owner];
 assign rsp_rdata=m_rsp_rdata[owner];
 assign rsp_error=m_rsp_error[owner];
 assign m_rsp_ready=(!rst&&busy&&rsp_ready)?(owner?2'b10:2'b01):2'b00;
 always_ff @(posedge clk) begin
  if(rst)begin busy<=0;owner<=0;end
  else begin
   if(req_valid&&req_ready)begin busy<=1;owner<=select_board;end
   if(rsp_valid&&rsp_ready)busy<=0;
  end
 end
endmodule
