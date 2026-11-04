// One-frame RGB565 writer. Pixel input is already in the HMIC user clock
// domain, normally after soc_camera_async_fifo. A 256-byte staging bank
// decouples the DVP byte clock from one AXI INCR burst at a time. The caller
// owns the destination until done_pulse and must not arm another frame first.
// An invalid/short frame may leave partial data in DDR; frame_valid stays low.
module soc_camera_axi_writer #(
    parameter logic [31:0] DDR_BASE = 32'h8000_0000,
    parameter logic [31:0] DDR_BYTES = 32'h0400_0000,
    parameter int MAX_PIXELS = 1280*720
)(
    input logic clk, rst,
    input logic start,
    input logic [31:0] frame_base, frame_pixels,
    input logic sensor_done, sensor_bad,
    input logic pixel_valid,
    output logic pixel_ready,
    input logic [15:0] pixel_data,
    output logic busy, done_pulse, frame_valid,
    output logic [7:0] error_sticky,
    output logic [31:0] pixels_written,
    output logic [3:0] m_awid,
    output logic [31:0] m_awaddr,
    output logic [7:0] m_awlen,
    output logic [2:0] m_awsize,
    output logic [1:0] m_awburst,
    output logic m_awvalid,
    input logic m_awready,
    output logic [127:0] m_wdata,
    output logic [15:0] m_wstrb,
    output logic m_wlast, m_wvalid,
    input logic m_wready,
    input logic [3:0] m_bid,
    input logic [1:0] m_bresp,
    input logic m_bvalid,
    output logic m_bready
);
    timeunit 1ns; timeprecision 1ps;
    typedef enum logic [2:0] {IDLE, FILL, ADDR, DATA, RESP} state_t;
    state_t state;
    logic [127:0] stage [0:15];
    logic [31:0] base_q, target_q, accepted_q, write_addr_q;
    logic [7:0] fill_pixels_q, chunk_pixels_q;
    logic [4:0] beats_q;
    logic [4:0] beat_index_q;
    logic [15:0] last_strb_q;
    logic [7:0] faults_q;
    logic [33:0] frame_end;
    logic valid_config;
    logic [7:0] filled_beats;
    logic [2:0] tail_pixels;

    assign frame_end={2'b0,frame_base}+{1'b0,frame_pixels,1'b0};
    assign valid_config=(frame_base[7:0]==0) && frame_pixels!=0 &&
        frame_pixels<=32'(MAX_PIXELS) && frame_base>=DDR_BASE &&
        frame_end<={2'b0,DDR_BASE}+{2'b0,DDR_BYTES};
    assign busy=(state!=IDLE);
    assign pixel_ready=(state==FILL) && accepted_q<target_q &&
        fill_pixels_q<8'd128;
    assign m_awid=4'hc;
    assign m_awaddr=write_addr_q;
    assign m_awlen=8'(beats_q-1'b1);
    assign m_awsize=3'd4;
    assign m_awburst=2'b01;
    assign m_awvalid=(state==ADDR);
    assign m_wdata=stage[beat_index_q[3:0]];
    assign m_wstrb=(beat_index_q==beats_q-1'b1) ? last_strb_q : 16'hffff;
    assign m_wlast=(beat_index_q==beats_q-1'b1);
    assign m_wvalid=(state==DATA);
    assign m_bready=(state==RESP);
    assign error_sticky=faults_q;
    assign filled_beats=(fill_pixels_q+8'd7)>>3;
    assign tail_pixels=fill_pixels_q[2:0];

    always_ff @(posedge clk) begin
        done_pulse<=0;
        if(rst) begin
            state<=IDLE; base_q<=0; target_q<=0; accepted_q<=0;
            write_addr_q<=0; fill_pixels_q<=0; chunk_pixels_q<=0;
            beats_q<=0; beat_index_q<=0; last_strb_q<=0;
            faults_q<=0; pixels_written<=0; frame_valid<=0;
        end else begin
            case(state)
                IDLE: if(start) begin
                    base_q<=frame_base; target_q<=frame_pixels;
                    accepted_q<=0; pixels_written<=0;
                    write_addr_q<=frame_base; fill_pixels_q<=0;
                    chunk_pixels_q<=0; beats_q<=0; beat_index_q<=0;
                    faults_q<=0; frame_valid<=0;
                    if(valid_config) state<=FILL;
                    else begin faults_q[2]<=1; done_pulse<=1; end
                end
                FILL: begin
                    if(pixel_valid && pixel_ready) begin
                        stage[fill_pixels_q[6:3]][16*fill_pixels_q[2:0]+:16]<=pixel_data;
                        fill_pixels_q<=fill_pixels_q+1'b1;
                        accepted_q<=accepted_q+1'b1;
                    end else if(fill_pixels_q==8'd128 ||
                               (fill_pixels_q!=0 && (accepted_q==target_q ||
                                                     (sensor_done && !pixel_valid)))) begin
                        chunk_pixels_q<=fill_pixels_q;
                        beats_q<=5'(filled_beats);
                        last_strb_q<=tail_pixels==0 ? 16'hffff :
                            ((16'h0001 << (2*tail_pixels))-16'h0001);
                        beat_index_q<=0;
                        state<=ADDR;
                    end else if(sensor_done && (accepted_q==target_q || !pixel_valid)) begin
                        if(accepted_q!=target_q) faults_q[0]<=1;
                        if(pixel_valid) faults_q[3]<=1;
                        if(sensor_bad) faults_q[4]<=1;
                        frame_valid<=(accepted_q==target_q) && !pixel_valid &&
                                     !sensor_bad && faults_q==0;
                        done_pulse<=1;
                        state<=IDLE;
                    end
                end
                ADDR: if(m_awready) state<=DATA;
                DATA: if(m_wready) begin
                    if(m_wlast) state<=RESP;
                    else beat_index_q<=beat_index_q+1'b1;
                end
                RESP: if(m_bvalid) begin
                    if(m_bid!=4'hc || m_bresp!=2'b00) faults_q[1]<=1;
                    pixels_written<=pixels_written+32'(chunk_pixels_q);
                    write_addr_q<=write_addr_q+{23'b0,beats_q,4'b0};
                    fill_pixels_q<=0;
                    state<=FILL;
                end
                default: state<=IDLE;
            endcase
        end
    end
    initial begin
        if(MAX_PIXELS<1 || DDR_BYTES<256 || DDR_BASE[7:0]!=0)
            $fatal(1,"CAMERA_AXI_WRITER_PARAMETER");
    end
endmodule
