`timescale 1ns/1ps
module tb_s3_axi;
  logic clk=0,rst=1,ddr_ready=1;
  always #5 clk=~clk;
  logic req_valid=0,req_ready,req_write=0;
  logic [31:0] req_addr=0;
  logic [127:0] req_wdata=0;
  logic [15:0] req_wstrb=0;
  logic [3:0] req_id=0;
  logic rsp_valid,rsp_ready=0,rsp_write,rsp_error,poisoned;
  logic [3:0] rsp_id;
  logic [127:0] rsp_rdata;
  logic [3:0] m_awid,m_bid=0,m_arid,m_rid=0;
  logic [31:0] m_awaddr,m_araddr;
  logic [7:0] m_awlen,m_arlen;
  logic [2:0] m_awsize,m_arsize;
  logic [1:0] m_awburst,m_arburst,m_bresp=0,m_rresp=0;
  logic m_awvalid,m_awready=0,m_wlast,m_wvalid,m_wready=0;
  logic m_bvalid=0,m_bready,m_arvalid,m_arready=0;
  logic m_rlast=1,m_rvalid=0,m_rready;
  logic [127:0] m_wdata,m_rdata=0;
  logic [15:0] m_wstrb;
  soc_rq_to_axi #(.TIMEOUT_CYCLES(12)) dut(.*);
  task automatic begin_req(input bit wr,input logic [31:0] addr,
                           input logic [3:0] id);
    @(negedge clk);req_write=wr;req_addr=addr;req_id=id;
    req_wstrb=wr?16'h00ff:0;req_wdata=128'h12345678;req_valid=1;
    do @(posedge clk); while(!req_ready);
    @(negedge clk);req_valid=0;
  endtask
  task automatic consume_rsp;
    @(negedge clk);rsp_ready=1;
    @(posedge clk);@(negedge clk);rsp_ready=0;
  endtask
  initial begin
    repeat(3) @(posedge clk);@(negedge clk);rst=0;
    begin_req(0,32'h80001000,4'h5);
    if(!m_arvalid || m_araddr!=32'h80001000 || m_arid!=5 ||
       m_arlen!=0 || m_arsize!=4 || m_arburst!=1) $fatal(1,"AR payload");
    repeat(2) @(posedge clk);
    @(negedge clk);m_arready=1;
    @(posedge clk);@(negedge clk);m_arready=0;
    m_rid=5;m_rdata=128'habcddcba;m_rvalid=1;
    @(posedge clk);@(negedge clk);m_rvalid=0;
    if(!rsp_valid || rsp_error || rsp_write || rsp_id!=5 ||
       rsp_rdata!=128'habcddcba) $fatal(1,"read response");
    consume_rsp();
    begin_req(1,32'h80001010,4'h3);
    if(!m_awvalid || m_awaddr!=32'h80001010 || m_awid!=3)
       $fatal(1,"AW payload");
    @(negedge clk);m_awready=1;
    @(posedge clk);@(negedge clk);m_awready=0;
    if(!m_wvalid || !m_wlast || m_wstrb!=16'h00ff ||
       m_wdata!=128'h12345678) $fatal(1,"W payload");
    @(negedge clk);m_wready=1;
    @(posedge clk);@(negedge clk);m_wready=0;
    m_bid=3;m_bvalid=1;
    @(posedge clk);@(negedge clk);m_bvalid=0;
    if(!rsp_valid || rsp_error || !rsp_write || rsp_id!=3)
       $fatal(1,"write response");
    consume_rsp();
    begin_req(0,32'h80001020,4'h0);
    @(negedge clk);m_arready=1;
    @(posedge clk);@(negedge clk);m_arready=0;
    m_rid=1;m_rvalid=1;
    @(posedge clk);@(negedge clk);m_rvalid=0;
    if(!rsp_valid || !rsp_error || !poisoned) $fatal(1,"tag fault");
    consume_rsp();
    if(req_ready || !poisoned) $fatal(1,"late response quarantine");
    @(negedge clk);rst=1;@(posedge clk);@(negedge clk);rst=0;
    begin_req(0,32'h80002000,4'h0);
    repeat(14) @(posedge clk);
    if(!rsp_valid || !rsp_error || !poisoned) $fatal(1,"timeout");
    consume_rsp();
    $display("PASS tb_s3_axi read/write/tag/timeout");
    $finish;
  end
endmodule
