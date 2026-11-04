`timescale 1ns/1ps
// Functional RGB INT8 HWC writer. Single-beat AXI writes keep every request
// inside a 4 KiB page. A frame is committed only after producer completion
// and all 19,200 write responses have succeeded.
module soc_v2_axi_writer (
    input logic clk,rst,start,
    input logic [31:0] destination,
    input logic producer_done,producer_valid,
    input logic pixel_valid,pixel_last,
    output logic pixel_ready,
    input logic [23:0] pixel_rgb_i8,
    output logic busy,done_pulse,frame_valid,
    output logic [7:0] error_sticky,
    output logic [31:0] pixels_accepted,bytes_written,
    output logic [3:0] m_awid,
    output logic [31:0] m_awaddr,
    output logic [7:0] m_awlen,
    output logic [2:0] m_awsize,
    output logic [1:0] m_awburst,
    output logic m_awvalid,
    input logic m_awready,
    output logic [127:0] m_wdata,
    output logic [15:0] m_wstrb,
    output logic m_wlast,m_wvalid,
    input logic m_wready,
    input logic [3:0] m_bid,
    input logic [1:0] m_bresp,
    input logic m_bvalid,
    output logic m_bready
);
    localparam logic [31:0] BASE=32'h8000_0000,END_ADDR=32'h8400_0000;
    localparam int PIXELS=320*320,BYTES=PIXELS*3;
    typedef enum logic [2:0] {IDLE,FILL,ADDR,DATA,RESP} state_t;
    state_t state;
    logic [127:0] stage_data;
    logic [15:0] carry_data;
    logic [1:0] carry_count;
    logic [4:0] fill_bytes;
    logic [31:0] write_addr;
    logic producer_done_seen,producer_good_seen;
    logic [31:0] byte_position;
    assign busy=state!=IDLE;
    assign pixel_ready=state==FILL && pixels_accepted<PIXELS &&
                       !producer_done_seen;
    assign m_awid=4'he;
    assign m_awaddr=write_addr;
    assign m_awlen=0;
    assign m_awsize=3'd4;
    assign m_awburst=2'b01;
    assign m_awvalid=state==ADDR;
    assign m_wdata=stage_data;
    assign m_wstrb=16'hffff;
    assign m_wlast=1'b1;
    assign m_wvalid=state==DATA;
    assign m_bready=state==RESP;
    always_ff @(posedge clk) begin
        done_pulse<=0;
        if(rst) begin
            state<=IDLE;stage_data<=0;carry_data<=0;carry_count<=0;
            fill_bytes<=0;write_addr<=0;pixels_accepted<=0;bytes_written<=0;
            producer_done_seen<=0;producer_good_seen<=0;
            frame_valid<=0;error_sticky<=0;
        end else begin
            if(start && state!=IDLE)error_sticky[4]<=1;
            if(state!=IDLE && producer_done)begin
                producer_done_seen<=1;
                producer_good_seen<=producer_valid;
                if(!producer_valid)error_sticky[2]<=1;
            end
            case(state)
                IDLE: if(start) begin
                    stage_data<=0;carry_data<=0;carry_count<=0;
                    fill_bytes<=0;write_addr<=destination;
                    pixels_accepted<=0;bytes_written<=0;
                    producer_done_seen<=0;producer_good_seen<=0;
                    frame_valid<=0;error_sticky<=0;
                    if(destination[3:0]!=0 || destination<BASE ||
                       destination>END_ADDR-BYTES)begin
                        error_sticky[0]<=1;done_pulse<=1;
                    end else state<=FILL;
                end
                FILL:begin
                    if(pixel_valid && pixel_ready)begin
                        for(int b=0;b<3;b++)begin
                            if(fill_bytes+5'(b)<16)
                                stage_data[8*(fill_bytes+5'(b))+:8]<=pixel_rgb_i8[8*b+:8];
                            else carry_data[8*(fill_bytes+5'(b)-5'd16)+:8]<=pixel_rgb_i8[8*b+:8];
                        end
                        pixels_accepted<=pixels_accepted+1;
                        if(pixel_last!=(pixels_accepted==PIXELS-1))
                            error_sticky[1]<=1;
                        if(fill_bytes+5'd3>=16)begin
                            carry_count<=2'(fill_bytes+5'd3-5'd16);
                            state<=ADDR;
                        end else fill_bytes<=fill_bytes+5'd3;
                    end else if(producer_done_seen)begin
                        if(pixels_accepted!=PIXELS || fill_bytes!=0 ||
                           bytes_written!=BYTES || !producer_good_seen ||
                           error_sticky!=0) begin
                            error_sticky[3]<=pixels_accepted!=PIXELS ||
                                             fill_bytes!=0 || bytes_written!=BYTES;
                            frame_valid<=0;
                        end else frame_valid<=1;
                        done_pulse<=1;state<=IDLE;
                    end
                end
                ADDR:if(m_awready)state<=DATA;
                DATA:if(m_wready)state<=RESP;
                RESP:if(m_bvalid)begin
                    if(m_bid!=4'he || m_bresp!=2'b00)error_sticky[5]<=1;
                    bytes_written<=bytes_written+16;
                    write_addr<=write_addr+16;
                    stage_data<=128'(carry_data);
                    fill_bytes<=5'(carry_count);
                    carry_data<=0;carry_count<=0;
                    state<=FILL;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
