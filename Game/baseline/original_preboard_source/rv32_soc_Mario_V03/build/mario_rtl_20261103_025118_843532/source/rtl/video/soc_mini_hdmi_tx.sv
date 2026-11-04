`timescale 1ns/1ps
// Direct FPGA TMDS output. There is no MS7210 in this board output path.
// RGB888 and all timing signals must already be aligned in pixel_clk.
// No ready/backpressure port: the display reader must keep the raster running.
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
                bit_even<=encoded_word[0];bit_odd<=encoded_word[1];
                remaining<=encoded_word[9:2];
            end else begin
                bit_even<=remaining[0];bit_odd<=remaining[1];
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
