// Request and response use separate asynchronous FIFOs. The entire transaction
// tuple crosses together; no independent per-bit synchronization of payload.
// IDs are preserved. There is no speculative/early response to a store.
// 原生 DDR 请求与响应各用一条异步 FIFO 跨时钟域，形成完整往返通道。
// 地址 写数据 strobe 标签在请求侧打包，读数据 写应答标记及错误在响应侧打包。
// 两侧背压独立传播，源端接收请求不表示目标端已完成访问。
// 响应身份必须跟随原事务，不能在跨域后重新从当前请求寄存器推导。
module soc_native_cdc #(
    parameter integer ADDR_W=32, DATA_W=128, TAG_W=4, FIFO_ADDR_BITS=4
)(
    input logic s_clk,s_rst,
    // s_req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    input logic s_req_valid,output logic s_req_ready,input logic s_req_write,
    // s_req_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    input logic [ADDR_W-1:0] s_req_addr,input logic [DATA_W-1:0] s_req_wdata,
    // s_req_wstrb 保存逐字节写使能，未使能的字节保持原值。
    input logic [DATA_W/8-1:0] s_req_wstrb,input logic [TAG_W-1:0] s_req_tag,
    // s_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output logic s_rsp_valid,input logic s_rsp_ready,output logic s_rsp_write,
    // s_rsp_rdata 保存读响应 payload，须在响应有效时才能使用。
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
    // 子模块 soc_async_fifo 的职责：异步 FIFO 在写域和读域分别保存二进制指针，并同步 Gray 码指针跨域。
    // 下列命名端口把本层信号连接到该模块，参数覆盖以实例中的原代码为准。
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
