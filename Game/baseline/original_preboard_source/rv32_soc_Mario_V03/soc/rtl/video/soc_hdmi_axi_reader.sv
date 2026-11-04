`timescale 1ns/1ps
// Full-size replay from the reserved low-DDR video region. The entire 16-beat
// AXI burst is captured before pixel emission. This guarantees RREADY until
// RLAST even when the downstream writer must obtain the same shared AXI port.
// A caller must treat pixels as uncommitted until frame_valid.
module soc_hdmi_axi_reader #(
    parameter logic [31:0] VIDEO_BASE=32'h8100_0000,
    parameter logic [31:0] VIDEO_BYTES=32'h0200_0000,
    parameter int MAX_PIXELS=2592*1944,
    parameter bit ENABLE_ABORT=0,
    parameter int WAIT_LIMIT=0
)(
    input logic clk,rst,
    input logic start,abort,
    input logic [31:0] frame_base,frame_pixels,
    output logic ready,busy,done_pulse,frame_valid,
    output logic [7:0] error_sticky,
    output logic [31:0] pixels_emitted,
    output logic [31:0] max_wait_cycles,
    output logic pixel_valid,
    input logic pixel_ready,
    output logic [15:0] pixel_data,
    output logic pixel_last,
    output logic [3:0] m_arid,
    output logic [31:0] m_araddr,
    output logic [7:0] m_arlen,
    output logic [2:0] m_arsize,
    output logic [1:0] m_arburst,
    output logic m_arvalid,
    input logic m_arready,
    input logic [3:0] m_rid,
    input logic [127:0] m_rdata,
    input logic [1:0] m_rresp,
    input logic m_rlast,m_rvalid,
    output logic m_rready
);
    typedef enum logic [2:0] {IDLE,ADDR,READ,EMIT,DRAIN} state_t;
    state_t state;
    logic [31:0] base_q,target_q;
    (* ram_style="distributed" *) logic [127:0] burst_data[0:15];
    logic [4:0] burst_beats_q,beat_index_q,emit_index_q;
    logic [3:0] lane_q,beat_pixels_q;
    logic [33:0] frame_end;
    logic valid_config;
    logic [31:0] remaining;
    logic [4:0] next_burst_beats;
    logic cancelled;
    logic [31:0] wait_cycles;
    wire do_abort=ENABLE_ABORT&&abort;
    assign frame_end={2'b0,frame_base}+{1'b0,frame_pixels,1'b0};
    assign valid_config=frame_base[7:0]==0 && frame_pixels!=0 &&
        frame_pixels<=32'(MAX_PIXELS) && frame_base>=VIDEO_BASE &&
        frame_end<={2'b0,VIDEO_BASE}+{2'b0,VIDEO_BYTES};
    assign remaining=target_q-pixels_emitted;
    assign next_burst_beats=remaining>=32'd128 ? 5'd16 : 5'((remaining+7)>>3);
    assign ready=state==IDLE && !rst;
    assign busy=state!=IDLE;
    assign m_arid=4'hd;
    assign m_araddr=base_q+(pixels_emitted<<1);
    assign m_arlen=8'(next_burst_beats-1'b1);
    assign m_arsize=3'd4;
    assign m_arburst=2'b01;
    assign m_arvalid=state==ADDR;
    assign m_rready=state==READ || state==DRAIN;
    assign pixel_valid=state==EMIT;
    assign pixel_data=burst_data[emit_index_q[3:0]][16*lane_q[2:0] +:16];
    assign pixel_last=pixel_valid && pixels_emitted+1==target_q;
    always_ff @(posedge clk) begin
        done_pulse<=0;
        if(rst) begin
            state<=IDLE;base_q<=0;target_q<=0;
            burst_beats_q<=0;beat_index_q<=0;emit_index_q<=0;lane_q<=0;
            beat_pixels_q<=0;
            pixels_emitted<=0;error_sticky<=0;frame_valid<=0;
            cancelled<=0;wait_cycles<=0;max_wait_cycles<=0;
        end else begin
            if(state!=IDLE&&do_abort)cancelled<=1;
            if((state==ADDR&&!m_arready)||((state==READ||state==DRAIN)&&!m_rvalid))begin
                if(wait_cycles!=32'hffffffff)wait_cycles<=wait_cycles+1'b1;
                if(wait_cycles>=max_wait_cycles)max_wait_cycles<=wait_cycles+1'b1;
                if(WAIT_LIMIT>0&&wait_cycles>=WAIT_LIMIT-1)error_sticky[3]<=1;
            end else wait_cycles<=0;
            case(state)
                IDLE: if(start) begin
                    base_q<=frame_base;target_q<=frame_pixels;
                    pixels_emitted<=0;error_sticky<=0;frame_valid<=0;
                    beat_index_q<=0;emit_index_q<=0;lane_q<=0;
                    cancelled<=0;
                    if(valid_config)state<=ADDR;
                    else begin error_sticky[0]<=1;done_pulse<=1;end
                end
                ADDR: if(m_arready) begin
                    burst_beats_q<=next_burst_beats;
                    beat_index_q<=0;
                    state<=(cancelled||do_abort)?DRAIN:READ;
                end
                READ: if(m_rvalid) begin
                    if(cancelled||do_abort)begin
                        if(m_rlast)begin done_pulse<=1;state<=IDLE;end
                        else state<=DRAIN;
                    end else if(m_rid!=4'hd || m_rresp!=2'b00 ||
                       m_rlast!=(beat_index_q+1==burst_beats_q)) begin
                        error_sticky[1]<=m_rid!=4'hd || m_rresp!=2'b00;
                        error_sticky[2]<=m_rlast!=(beat_index_q+1==burst_beats_q);
                        if(m_rlast)begin done_pulse<=1;state<=IDLE;end
                        else state<=DRAIN;
                    end else begin
                        burst_data[beat_index_q[3:0]]<=m_rdata;
                        if(beat_index_q+1==burst_beats_q) begin
                            emit_index_q<=0;lane_q<=0;
                            beat_pixels_q<=remaining>=32'd8 ? 4'd8 : 4'(remaining);
                            state<=EMIT;
                        end else beat_index_q<=beat_index_q+1;
                    end
                end
                EMIT: if(cancelled||do_abort)begin done_pulse<=1;state<=IDLE;end
                else if(pixel_ready) begin
                    pixels_emitted<=pixels_emitted+1;
                    if(lane_q+1==beat_pixels_q) begin
                        if(pixels_emitted+1==target_q) begin
                            frame_valid<=1;done_pulse<=1;state<=IDLE;
                        end else if(emit_index_q+1==burst_beats_q) state<=ADDR;
                        else begin
                            emit_index_q<=emit_index_q+1;lane_q<=0;
                            beat_pixels_q<=remaining>32'd9 ? 4'd8 :
                                           4'(remaining-1'b1);
                        end
                    end else lane_q<=lane_q+1;
                end
                DRAIN: if(m_rvalid && m_rlast) begin
                    done_pulse<=1;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
    initial if(VIDEO_BASE[7:0]!=0 || VIDEO_BYTES<256 || MAX_PIXELS<1)
        $fatal(1,"VIDEO_REPLAY_PARAMETER");
endmodule
