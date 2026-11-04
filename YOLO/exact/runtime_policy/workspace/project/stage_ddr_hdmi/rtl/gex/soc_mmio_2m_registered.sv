// One accepted transaction owns its response through arbitrary backpressure.
// Register both ingress and response; no new long CPU->MMIO combinational path.
module soc_mmio_2m_registered(
 input logic clk,rst,
 input logic [1:0] s_req_valid, output logic [1:0] s_req_ready,
 input logic [1:0][31:0] s_req_addr,s_req_wdata,
 input logic [1:0] s_req_write,s_req_fetch,input logic [1:0][3:0] s_req_wstrb,
 output logic [1:0] s_rsp_valid,input logic [1:0] s_rsp_ready,
 output logic [1:0][31:0] s_rsp_rdata,output logic [1:0] s_rsp_error,
 output logic m_req_valid,input logic m_req_ready,
 output logic [31:0] m_req_addr,m_req_wdata,
 output logic m_req_write,m_req_fetch,output logic [3:0] m_req_wstrb,
 input logic m_rsp_valid,output logic m_rsp_ready,
 input logic [31:0] m_rsp_rdata,input logic m_rsp_error
);
 localparam [1:0] IDLE=0,ISSUE=1,WAIT_RSP=2,RETURN_RSP=3;
 logic [1:0] state;logic owner,prefer,selected;
 logic [31:0] response;logic response_error;
 always_comb begin
  selected=s_req_valid[prefer]?prefer:~prefer;
  s_req_ready=0;s_rsp_valid=0;s_rsp_error=0;
  s_rsp_rdata[0]=response;s_rsp_rdata[1]=response;
  m_req_valid=!rst&&state==ISSUE;m_rsp_ready=!rst&&state==WAIT_RSP;
  if(!rst&&state==IDLE)s_req_ready[selected]=1;
  if(!rst&&state==RETURN_RSP)begin s_rsp_valid[owner]=1;s_rsp_error[owner]=response_error;end
 end
 always_ff @(posedge clk) begin
  if(rst)begin
   state<=IDLE;owner<=0;prefer<=0;response<=0;response_error<=0;
   m_req_addr<=0;m_req_wdata<=0;m_req_write<=0;m_req_fetch<=0;m_req_wstrb<=0;
  end else case(state)
   IDLE:if(s_req_valid[selected])begin
    owner<=selected;prefer<=~selected;m_req_addr<=s_req_addr[selected];
    m_req_wdata<=s_req_wdata[selected];m_req_write<=s_req_write[selected];
    m_req_fetch<=s_req_fetch[selected];m_req_wstrb<=s_req_wstrb[selected];state<=ISSUE;
   end
   ISSUE:if(m_req_ready)state<=WAIT_RSP;
   WAIT_RSP:if(m_rsp_valid)begin response<=m_rsp_rdata;response_error<=m_rsp_error;state<=RETURN_RSP;end
   RETURN_RSP:if(s_rsp_ready[owner])state<=IDLE;
  endcase
 end
endmodule
