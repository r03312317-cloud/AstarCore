`timescale 1ns/1ps
// Direct FPGA TMDS output. There is no MS7210 in this board output path.
// RGB888 and all timing signals must already be aligned in pixel_clk.
// No ready/backpressure port: the display reader must keep the raster running.
// HDMI 发送路径将 RGB 和同步控制编码为三个 TMDS 通道并驱动差分引脚。
// 像素时钟负责并行编码，5 倍时钟配合双沿输出形成 10 位串行字符。
// 复位释放需要时钟锁定及各域同步，不能在串行时钟未稳定时启动输出。
// 此接口承载图像扫描，没有在 FPGA 上实现完整桌面或键盘输入子系统。
module soc_mini_hdmi_tx (
    input  wire pixel_clk,
    input  wire serial_clk,
    input  wire reset_n,
    input  wire serial_reset_n,
    input  wire [23:0] rgb888,
    input  wire de,
    input  wire hsync,
    input  wire vsync,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n,
    output wire tmds_clk_p,
    output wire tmds_clk_n
);
    soc_rgb2tmds_reset_split u_tx (
        .pixelclk(pixel_clk), .serialclk(serial_clk), .rstn(reset_n),
        .serial_rstn(serial_reset_n),
        .vid_pdata(rgb888), .vid_pvde(de),
        .vid_phsync(hsync), .vid_pvsync(vsync),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n)
    );
endmodule

// Project serializer: related 5:1 clocks, one encoded word per pixel toggle.
// Both DDR inputs are updated on the serial rising edge. Each lane emits
// bit 0, bit 1, ... bit 9 (LSB first). Original TMDS encoder is unchanged.
// Runtime reset clears fabric data/phase state; the I/O ODDR local RS is 0.
// GRS handles configuration startup. No runtime reset recovery is hidden:
// there is physically no runtime reset net connected to the fast I/O latch.
module soc_rgb2tmds_reset_split(
    input wire pixelclk,serialclk,rstn,serial_rstn,
    input wire [23:0] vid_pdata,input wire vid_pvde,vid_phsync,vid_pvsync,
    output wire [2:0] tmds_data_p,tmds_data_n,
    output wire tmds_clk_p,tmds_clk_n
);
    wire [9:0] pdataoutraw[2:0];
    reg pixel_toggle;
    always @(posedge pixelclk or negedge rstn)
        if(!rstn)pixel_toggle<=0;else pixel_toggle<=!pixel_toggle;
    // Only one serial FF loads the pixel-domain toggle. The serial register
    // drives the wide load mux locally; no 30-load pixel->serial control net.
    reg sampled_toggle,seen_toggle;
    // load_word 由比较式 sampled_toggle!=seen_toggle 产生；该结果是条件判断，不是被比较的数据。
    wire load_word=sampled_toggle!=seen_toggle;
    always @(posedge serialclk)
        if(!serial_rstn)begin sampled_toggle<=0;seen_toggle<=0;end
        else begin sampled_toggle<=pixel_toggle;seen_toggle<=sampled_toggle;end
    for(genvar i=0;i<3;i++)begin:encoder
        tmds_encoder dataencoder(.pix_clk(pixelclk),.rstn,
            .din(vid_pdata[i*8+:8]),.de(vid_pvde),
            .c0(i==0?vid_phsync:1'b0),.c1(i==0?vid_pvsync:1'b0),
            .dout(pdataoutraw[i]));
    end
    for(genvar lane=0;lane<4;lane++)begin:serializer
        wire [9:0] encoded_word;
        if(lane==3)assign encoded_word=10'b1111100000;
        else assign encoded_word=pdataoutraw[lane];
        reg [7:0] remaining;
        reg bit_even,bit_odd;
        always @(posedge serialclk)
            if(!serial_rstn)begin
                remaining<=0;bit_even<=0;bit_odd<=0;
            end else if(load_word)begin
                // 本时钟边界的 bit_even 读取 encoded_word[0] 所选位域；位索引按声明中的高低位顺序解释。
                bit_even<=encoded_word[0];bit_odd<=encoded_word[1];
                // 本时钟边界的 remaining 读取 encoded_word[9:2] 所选位域；位索引按声明中的高低位顺序解释。
                remaining<=encoded_word[9:2];
            end else begin
                // 本时钟边界的 bit_even 读取 remaining[0] 所选位域；位索引按声明中的高低位顺序解释。
                bit_even<=remaining[0];bit_odd<=remaining[1];
                // 本时钟边界的 remaining 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
                // 拼接源为 {2'b00,remaining[7:2]}；复制大括号表示重复位域，不是独立队列元素。
                remaining<={2'b00,remaining[7:2]};
            end
        wire serial_bit;
        GTP_ODDR_E1 #(.ODDR_MODE("SAME_EDGE"),.GRS_EN("TRUE"),.RS_TYPE("ASYNC_RESET")) u_oddr(
            .Q(serial_bit),.D0(bit_even),.D1(bit_odd),
            .CE(1'b1),.CLK(serialclk),.RS(1'b0));
        if(lane==3)begin
            GTP_OUTBUFDS #(.IOSTANDARD("TMDS")) u_buf(.O(tmds_clk_p),.OB(tmds_clk_n),.I(serial_bit));
        end else begin
            GTP_OUTBUFDS #(.IOSTANDARD("TMDS")) u_buf(.O(tmds_data_p[lane]),.OB(tmds_data_n[lane]),.I(serial_bit));
        end
    end
endmodule
