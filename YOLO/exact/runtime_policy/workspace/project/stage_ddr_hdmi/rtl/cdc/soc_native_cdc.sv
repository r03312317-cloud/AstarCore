// Request and response use separate asynchronous FIFOs. The entire transaction
// tuple crosses together; no independent per-bit synchronization of payload.
// IDs are preserved. There is no speculative/early response to a store.
module soc_native_cdc #(
    parameter integer ADDR_W=32, DATA_W=128, TAG_W=4, FIFO_ADDR_BITS=4
)(
    input logic s_clk,s_rst,
    input logic s_req_valid,output logic s_req_ready,input logic s_req_write,
    input logic [ADDR_W-1:0] s_req_addr,input logic [DATA_W-1:0] s_req_wdata,
    input logic [DATA_W/8-1:0] s_req_wstrb,input logic [TAG_W-1:0] s_req_tag,
    output logic s_rsp_valid,input logic s_rsp_ready,output logic s_rsp_write,
    output logic [DATA_W-1:0] s_rsp_rdata,output logic [TAG_W-1:0] s_rsp_tag,output logic s_rsp_error,
    input logic m_clk,m_rst,
    output logic m_req_valid,input logic m_req_ready,output logic m_req_write,
    output logic [ADDR_W-1:0] m_req_addr,output logic [DATA_W-1:0] m_req_wdata,
    output logic [DATA_W/8-1:0] m_req_wstrb,output logic [TAG_W-1:0] m_req_tag,
    input logic m_rsp_valid,output logic m_rsp_ready,input logic m_rsp_write,
    input logic [DATA_W-1:0] m_rsp_rdata,input logic [TAG_W-1:0] m_rsp_tag,input logic m_rsp_error
);
    localparam integer QW=1+ADDR_W+DATA_W+DATA_W/8+TAG_W;
    localparam integer SW=1+DATA_W+TAG_W+1;
    soc_async_fifo #(.WIDTH(QW),.ADDR_BITS(FIFO_ADDR_BITS)) request_fifo(
        .w_clk(s_clk),.w_rst(s_rst),.w_valid(s_req_valid),.w_ready(s_req_ready),
        .w_data({s_req_write,s_req_addr,s_req_wdata,s_req_wstrb,s_req_tag}),
        .r_clk(m_clk),.r_rst(m_rst),.r_valid(m_req_valid),.r_ready(m_req_ready),
        .r_data({m_req_write,m_req_addr,m_req_wdata,m_req_wstrb,m_req_tag}));
    soc_async_fifo #(.WIDTH(SW),.ADDR_BITS(FIFO_ADDR_BITS)) response_fifo(
        .w_clk(m_clk),.w_rst(m_rst),.w_valid(m_rsp_valid),.w_ready(m_rsp_ready),
        .w_data({m_rsp_write,m_rsp_rdata,m_rsp_tag,m_rsp_error}),
        .r_clk(s_clk),.r_rst(s_rst),.r_valid(s_rsp_valid),.r_ready(s_rsp_ready),
        .r_data({s_rsp_write,s_rsp_rdata,s_rsp_tag,s_rsp_error}));
endmodule
