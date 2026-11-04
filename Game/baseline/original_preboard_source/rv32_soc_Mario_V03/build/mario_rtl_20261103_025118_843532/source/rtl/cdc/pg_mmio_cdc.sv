// Full single-owner MMIO request/response CDC. Doorbells, W1C and reads with
// side effects cross exactly once. The existing legacy bridge stays entirely
// in dst_clk; its fixed ISSUE/WAIT states and write pulse never cross a clock.
module pg_mmio_cdc (
 input logic src_clk,dst_clk,arst,
 input logic s_req_valid,output logic s_req_ready,input logic[15:0] s_req_addr,
 input logic s_req_write,input logic[31:0] s_req_wdata,input logic[3:0] s_req_wstrb,
 output logic s_rsp_valid,input logic s_rsp_ready,output logic[31:0] s_rsp_rdata,
 output logic s_rsp_error,
 output logic m_req_valid,input logic m_req_ready,output logic[15:0] m_req_addr,
 output logic m_req_write,output logic[31:0] m_req_wdata,output logic[3:0] m_req_wstrb,
 input logic m_rsp_valid,output logic m_rsp_ready,input logic[31:0] m_rsp_rdata,
 input logic m_rsp_error
);
 timeunit 1ns;timeprecision 1ps;
 logic src_rst,busy_q,req_ready_local,rsp_valid_local;
 logic rsp_hold_valid_q,rsp_hold_error_q;
 logic [31:0] rsp_hold_rdata_q,rsp_rdata_local;
 logic rsp_error_local;
 pg_reset_sync release_src(.clk(src_clk),.arst,.rst(src_rst));
 assign s_req_ready=!src_rst&&!busy_q&&req_ready_local;
 // Register the returned response in the source domain before it reaches the
 // SoC response router and CPU control. This is a one-owner, one-entry stage:
 // the FIFO cannot pop again until the previous response is consumed.
 assign s_rsp_valid=rsp_hold_valid_q;
 assign s_rsp_rdata=rsp_hold_rdata_q;
 assign s_rsp_error=rsp_hold_error_q;
 always_ff @(posedge src_clk or posedge src_rst)
  if(src_rst)begin
   busy_q<=0;
   rsp_hold_valid_q<=0;
   rsp_hold_rdata_q<=0;
   rsp_hold_error_q<=0;
  end
  else begin
   if(s_req_valid&&s_req_ready)busy_q<=1;
   if(s_rsp_valid&&s_rsp_ready)busy_q<=0;
   if(rsp_valid_local&&!rsp_hold_valid_q&&busy_q)begin
    rsp_hold_valid_q<=1;
    rsp_hold_rdata_q<=rsp_rdata_local;
    rsp_hold_error_q<=rsp_error_local;
   end
   else if(s_rsp_valid&&s_rsp_ready)rsp_hold_valid_q<=0;
  end
 pg_async_fifo_dc #(.WIDTH(53),.DEPTH(2)) req_fifo(
  .wr_clk(src_clk),.rd_clk(dst_clk),.arst,
  .in_valid(s_req_valid&&!busy_q&&!src_rst),.in_ready(req_ready_local),
  .in_data({s_req_addr,s_req_write,s_req_wdata,s_req_wstrb}),
  .out_valid(m_req_valid),.out_ready(m_req_ready),
  .out_data({m_req_addr,m_req_write,m_req_wdata,m_req_wstrb}));
 pg_async_fifo_dc #(.WIDTH(33),.DEPTH(2)) rsp_fifo(
  .wr_clk(dst_clk),.rd_clk(src_clk),.arst,
  .in_valid(m_rsp_valid),.in_ready(m_rsp_ready),
  .in_data({m_rsp_error,m_rsp_rdata}),
  .out_valid(rsp_valid_local),.out_ready(!rsp_hold_valid_q&&busy_q&&!src_rst),
  .out_data({rsp_error_local,rsp_rdata_local}));
 // synthesis translate_off
 always @(posedge src_clk)if(!src_rst&&rsp_valid_local&&!busy_q)
  $fatal(1,"CP6_MMIO_UNOWNED_RESPONSE_RED");
 // synthesis translate_on
endmodule
