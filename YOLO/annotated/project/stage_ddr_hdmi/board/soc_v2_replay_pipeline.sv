// 架构导读：soc_v2_replay_pipeline。
// 可综合数据/控制组件；接口含义和更新条件以下面的局部注释及原始表达式为准。
`timescale 1ns/1ps
// CPU-controlled 5MP DDR replay -> V2 spatial/LUT -> model input DDR.
// Reader and writer are independent AXI channels of one arbitration client.
module soc_v2_replay_pipeline (
    // 接口声明：input logic clk,rst,ddr_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic clk,rst,ddr_ready,
    // 接口声明：input logic req_valid,output logic req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic req_valid,output logic req_ready,
    // 接口声明：input logic [15:0] req_addr,input logic req_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [15:0] req_addr,input logic req_write,
    // 接口声明：input logic [31:0] req_wdata,input logic [3:0] req_wstrb。
    // 按字节选择本次写入生效的 lane。
    input logic [31:0] req_wdata,input logic [3:0] req_wstrb,
    // 接口声明：output logic rsp_valid,input logic rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic rsp_valid,input logic rsp_ready,
    // 接口声明：output logic [31:0] rsp_rdata,output logic rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [31:0] rsp_rdata,output logic rsp_error,
    // 接口声明：output logic [3:0] m_awid。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [3:0] m_awid,
    // 接口声明：output logic [31:0] m_awaddr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] m_awaddr,
    // 接口声明：output logic [7:0] m_awlen。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [7:0] m_awlen,
    // 接口声明：output logic [2:0] m_awsize。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [2:0] m_awsize,
    // 接口声明：output logic [1:0] m_awburst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    output logic [1:0] m_awburst,
    // 接口声明：output logic m_awvalid,input logic m_awready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic m_awvalid,input logic m_awready,
    // 接口声明：output logic [127:0] m_wdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [127:0] m_wdata,
    // 接口声明：output logic [15:0] m_wstrb。
    // 按字节选择本次写入生效的 lane。
    output logic [15:0] m_wstrb,
    // 接口声明：output logic m_wlast,m_wvalid,input logic m_wready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic m_wlast,m_wvalid,input logic m_wready,
    // 接口声明：input logic [3:0] m_bid。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [3:0] m_bid,
    input logic [1:0] m_bresp,
    input logic m_bvalid,output logic m_bready,
    output logic [3:0] m_arid,
    output logic [31:0] m_araddr,
    output logic [7:0] m_arlen,
    output logic [2:0] m_arsize,
    output logic [1:0] m_arburst,
    output logic m_arvalid,input logic m_arready,
    input logic [3:0] m_rid,
    input logic [127:0] m_rdata,
    input logic [1:0] m_rresp,
    input logic m_rlast,m_rvalid,output logic m_rready
);
    logic start;
    logic [31:0] source_addr,destination_addr;
    logic lut_write,lut_ready,lut_complete;
    logic [7:0] lut_addr,lut_data;
    logic reader_ready,reader_busy,reader_done,reader_valid;
    logic [7:0] reader_errors;
    logic [31:0] reader_pixels;
    logic raw_valid,raw_ready,raw_last;
    logic [15:0] raw_pixel;
    logic stream_ready,stream_busy,stream_done,stream_valid;
    logic [7:0] stream_errors;
    logic [31:0] source_pixels,active_pixels,output_pixels;
    logic tensor_valid,tensor_ready,tensor_last;
    logic [23:0] tensor_pixel;
    logic writer_busy,writer_done,writer_valid;
    logic [7:0] writer_errors;
    logic [31:0] writer_pixels,bytes_written;

    soc_v2_replay_mmio controller(
        .clk,.rst,.ddr_ready,.req_valid,.req_ready,.req_addr,.req_write,
        .req_wdata,.req_wstrb,.rsp_valid,.rsp_ready,.rsp_rdata,.rsp_error,
        .start,.source_addr,.destination_addr,.lut_write,.lut_addr,.lut_data,
        .lut_ready,.lut_complete,.reader_ready,.reader_done,.reader_valid,
        .reader_errors,.stream_ready,.stream_done,.stream_valid,
        .stream_errors,.writer_busy,.writer_done,.writer_valid,
        .writer_errors,.source_pixels,.active_pixels,.output_pixels,
        .bytes_written);
    soc_video_axi_reader reader(
        .clk,.rst,.start,.frame_base(source_addr),.frame_pixels(32'd5038848),
        .ready(reader_ready),.busy(reader_busy),.done_pulse(reader_done),
        .frame_valid(reader_valid),.error_sticky(reader_errors),
        .pixels_emitted(reader_pixels),.pixel_valid(raw_valid),
        .pixel_ready(raw_ready),.pixel_data(raw_pixel),.pixel_last(raw_last),
        .m_arid,.m_araddr,.m_arlen,.m_arsize,.m_arburst,.m_arvalid,
        .m_arready,.m_rid,.m_rdata,.m_rresp,.m_rlast,.m_rvalid,.m_rready);
    soc_v2_stream_5mp stream(
        .clk,.rst,.start,.abort(reader_done && !reader_valid),
        .ready(stream_ready),.busy(stream_busy),.done_pulse(stream_done),
        .frame_valid(stream_valid),.error_sticky(stream_errors),
        .lut_write,.lut_addr,.lut_data,.lut_ready,.lut_complete,
        .in_valid(raw_valid),.in_last(raw_last),.in_ready(raw_ready),
        .in_rgb565(raw_pixel),.out_valid(tensor_valid),
        .out_last(tensor_last),.out_ready(tensor_ready),
        .out_rgb_i8(tensor_pixel),.source_pixels,.active_pixels,
        .output_pixels);
    soc_v2_axi_writer writer(
        .clk,.rst,.start,.destination(destination_addr),
        .producer_done(stream_done),.producer_valid(stream_valid),
        .pixel_valid(tensor_valid),.pixel_last(tensor_last),
        .pixel_ready(tensor_ready),.pixel_rgb_i8(tensor_pixel),
        .busy(writer_busy),.done_pulse(writer_done),.frame_valid(writer_valid),
        .error_sticky(writer_errors),.pixels_accepted(writer_pixels),
        .bytes_written,.m_awid,.m_awaddr,.m_awlen,.m_awsize,.m_awburst,
        .m_awvalid,.m_awready,.m_wdata,.m_wstrb,.m_wlast,.m_wvalid,
        .m_wready,.m_bid,.m_bresp,.m_bvalid,.m_bready);
endmodule
