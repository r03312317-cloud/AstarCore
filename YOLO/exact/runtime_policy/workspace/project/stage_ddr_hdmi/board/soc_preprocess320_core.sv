// Hardware pre-processing engine: 1280x720 RGB565 -> 320x320x3 INT8.
//
// Byte-exact reproduction of soc_preprocess_rgb565_320_i8(). That C function
// is the contract; read its comment before changing anything here.
//
// Per active output pixel (x in [0,320), y' = y - 70, col = 4x + 1):
//   a0,a1 = source[(4y'+1)*1280 + col], [+1]
//   b0,b1 = source[(4y'+2)*1280 + col], [+1]
//   R8(p) = {v, v[4:2]} with v = p[15:11]      (v<<3)|(v>>2)
//   G8(p) = {v, v[5:4]} with v = p[10:5]       (v<<2)|(v>>4)
//   B8(p) = {v, v[4:2]} with v = p[4:0]        (v<<3)|(v>>2)
//   r = (R8(a0)+R8(a1)+R8(b0)+R8(b1)+2) >> 2   (same for g and b)
//   emit lut[r], lut[g], lut[b]
// That is OpenCV INTER_LINEAR sampled at exact 4:1, i.e. source coordinates
// (4x+1.5, 4y'+1.5); the +2 is its integer rounding.
// Output rows 0..69 and 250..319 are letterbox, every byte = lut[114].
//
// Upper-row horizontal sums use a 160x60-bit memory. Lower-row samples
// combine with those sums, index the programmable LUT, and emit RGB bytes.
// This integration uses one outstanding request and exact READY gating. The
// AXI adapter supplies 256-byte prefetches and absorbs complete read bursts.
// Performance and correctness evidence live in sim/image and sim/preprocess;
// cycle counts must be converted with the actual fabric frequency (93.75 MHz).
module soc_preprocess320_core #(
    parameter bit WIDE_OUTPUT_PACK = 1'b1, // PIPEOPT2: six-byte RGB packing + full letterbox beats
    parameter int SRC_STRIDE_B = 2560,                     // 1280 px * 2 B
    parameter int OUT_STRIDE_B = 960,                      // 320 px * 3 B
    parameter int OUT_H        = 320,
    parameter int TOP          = 70,
    parameter int ACT_H        = 180,
    parameter int BEATS_PER_SRC_ROW = SRC_STRIDE_B / 16    // 160
)(
    input  logic         clk,
    input  logic         rst,

    input  logic         start,
    input  logic [29:0]  src_base,
    input  logic [29:0]  dst_base,
    output logic         busy,
    output logic         done,

    // 256-entry input LUT, written before start
    input  logic         lut_we,
    input  logic [7:0]   lut_idx,
    input  logic [7:0]   lut_dat,

    // Beat-level read channel
    output logic         rd_valid,
    input  logic         rd_ready,
    output logic [29:0]  rd_addr,
    input  logic         rsp_valid,
    output logic         rsp_ready,
    input  logic [127:0] rsp_data,

    // Beat-level write channel, 16 B full strobe
    output logic         wr_valid,
    input  logic         wr_ready,
    output logic [29:0]  wr_addr,
    output logic [127:0] wr_data,

    output logic [31:0]  stat_rd_beats,
    output logic [31:0]  stat_wr_beats
);
    timeunit 1ns; timeprecision 1ps;
    // One request is outstanding. The burst adapter prefetches sixteen beats,
    // so even a one-request client benefits without a request/response deadlock.
    // READY is combinational from actual storage availability; no response can
    // handshake on the cycle after the staging register becomes occupied.
    typedef enum logic [3:0] {IDLE,ROW,LBOX,AREQ,ARSP,BREQ,BRSP,
        STAGE,ROW_END,FINISH,REARM} state_t;
    state_t state;
    logic [7:0] lut_q[0:255];
    logic [59:0] psum_q[0:BEATS_PER_SRC_ROW-1];
    logic [29:0] source_q,dest_q,rowa_q,rowb_q,outrow_q;
    logic [8:0] y_q,k_q;
    logic [10:0] row_bytes;
    logic [127:0] pack_q,pack_next;
    logic [3:0] pack_count;
    logic [47:0] stage_q;
    logic [2:0] stage_count;
    localparam bit FAST_PACK = WIDE_OUTPUT_PACK && (OUT_STRIDE_B % 16 == 0);
    wire can_push=!wr_valid||wr_ready;
    // pack_q contains only the live residual bytes in fast mode. One six-byte
    // stage may cross at most one 16-byte output boundary. Output remains
    // registered and stable under write backpressure.
    wire [175:0] wide_pack = {48'd0,pack_q} |
                            ({128'd0,stage_q} << (8*pack_count));
    wire [4:0] wide_count = {1'b0,pack_count}+{2'b0,stage_count};
    wire push=(state==LBOX&&row_bytes<11'(OUT_STRIDE_B)) ||
              (state==STAGE&&stage_count!=0);
    wire [7:0] push_byte=state==LBOX?lut_q[114]:stage_q[7:0];
    function automatic [7:0] red8(input logic [15:0] p);
        red8={p[15:11],p[15:13]};
    endfunction
    function automatic [7:0] grn8(input logic [15:0] p);
        grn8={p[10:5],p[10:9]};
    endfunction
    function automatic [7:0] blu8(input logic [15:0] p);
        blu8={p[4:0],p[4:2]};
    endfunction
    function automatic [29:0] pair_sum(input logic [127:0] b,input int lo);
        logic [15:0] a,c;
        logic [9:0] r,g,bl;
        a=b[lo*16+:16];c=b[(lo+1)*16+:16];
        r=10'(red8(a))+10'(red8(c));
        g=10'(grn8(a))+10'(grn8(c));
        bl=10'(blu8(a))+10'(blu8(c));
        pair_sum={r,g,bl};
    endfunction
    wire [59:0] upper=psum_q[k_q[7:0]];
    wire [29:0] lo=pair_sum(rsp_data,1),hi=pair_sum(rsp_data,5);
    wire [7:0] r0=8'((11'(upper[29:20])+11'(lo[29:20])+11'd2)>>2);
    wire [7:0] g0=8'((11'(upper[19:10])+11'(lo[19:10])+11'd2)>>2);
    wire [7:0] b0=8'((11'(upper[9:0])+11'(lo[9:0])+11'd2)>>2);
    wire [7:0] r1=8'((11'(upper[59:50])+11'(hi[29:20])+11'd2)>>2);
    wire [7:0] g1=8'((11'(upper[49:40])+11'(hi[19:10])+11'd2)>>2);
    wire [7:0] b1=8'((11'(upper[39:30])+11'(hi[9:0])+11'd2)>>2);
    always_comb begin
        pack_next=pack_q;
        pack_next[pack_count*8+:8]=push_byte;
    end
    assign rd_valid=(state==AREQ||state==BREQ)&&!rst;
    assign rd_addr=(state==AREQ?rowa_q:rowb_q)+{17'd0,k_q,4'd0};
    assign rsp_ready=(state==ARSP||state==BRSP)&&!rst;
    always_ff @(posedge clk)begin
        if(lut_we)lut_q[lut_idx]<=lut_dat;
        done<=0;
        if(rst)begin
            state<=IDLE;busy<=0;done<=0;source_q<=0;dest_q<=0;
            rowa_q<=0;rowb_q<=0;outrow_q<=0;y_q<=0;k_q<=0;
            row_bytes<=0;pack_q<=0;pack_count<=0;stage_q<=0;stage_count<=0;
            wr_valid<=0;wr_addr<=0;wr_data<=0;
            stat_rd_beats<=0;stat_wr_beats<=0;
        end else begin
            if(wr_valid&&wr_ready)begin
                wr_valid<=0;stat_wr_beats<=stat_wr_beats+1'b1;
            end
            if(!FAST_PACK&&push&&can_push)begin
                pack_q<=pack_next;pack_count<=pack_count+1'b1;
                row_bytes<=row_bytes+1'b1;
                if(pack_count==15)begin
                    wr_valid<=1;wr_data<=pack_next;
                    wr_addr<=outrow_q+30'(row_bytes)-30'd15;
                end
                if(state==STAGE)begin
                    stage_q<=stage_q>>8;stage_count<=stage_count-1'b1;
                end
            end
            case(state)
                IDLE:if(start)begin
                    source_q<=src_base;dest_q<=dst_base;outrow_q<=dst_base;
                    y_q<=0;k_q<=0;row_bytes<=0;pack_count<=0;
                    stat_rd_beats<=0;stat_wr_beats<=0;
                    busy<=1;state<=ROW;
                end
                ROW:begin
                    row_bytes<=0;k_q<=0;
                    if(FAST_PACK)begin pack_q<=0;pack_count<=0;end
                    if(y_q>=9'(OUT_H))state<=FINISH;
                    else if(y_q<9'(TOP)||y_q>=9'(TOP+ACT_H))state<=LBOX;
                    else begin
                        rowa_q<=source_q+30'((4*(int'(y_q)-TOP)+1)*SRC_STRIDE_B);
                        rowb_q<=source_q+30'((4*(int'(y_q)-TOP)+2)*SRC_STRIDE_B);
                        state<=AREQ;
                    end
                end
                LBOX:begin
                    if(row_bytes==11'(OUT_STRIDE_B))state<=ROW_END;
                    else if(FAST_PACK&&can_push)begin
                        wr_valid<=1;wr_data<={16{lut_q[114]}};
                        wr_addr<=outrow_q+30'(row_bytes);
                        row_bytes<=row_bytes+11'd16;
                    end
                end
                AREQ:if(rd_ready)state<=ARSP;
                ARSP:if(rsp_valid)begin
                    psum_q[k_q[7:0]]<={pair_sum(rsp_data,5),pair_sum(rsp_data,1)};
                    stat_rd_beats<=stat_rd_beats+1'b1;
                    if(k_q==9'(BEATS_PER_SRC_ROW-1))begin k_q<=0;state<=BREQ;end
                    else begin k_q<=k_q+1'b1;state<=AREQ;end
                end
                BREQ:if(rd_ready)state<=BRSP;
                BRSP:if(rsp_valid)begin
                    stat_rd_beats<=stat_rd_beats+1'b1;
                    stage_q<={lut_q[b1],lut_q[g1],lut_q[r1],lut_q[b0],lut_q[g0],lut_q[r0]};
                    stage_count<=6;state<=STAGE;
                end
                STAGE:begin
                    if(FAST_PACK&&stage_count!=0&&can_push)begin
                        row_bytes<=row_bytes+11'(stage_count);
                        stage_count<=0;
                        if(wide_count>=5'd16)begin
                            wr_valid<=1;wr_data<=wide_pack[127:0];
                            wr_addr<=outrow_q+30'(row_bytes)-30'(pack_count);
                            pack_q<={80'd0,wide_pack[175:128]};
                            pack_count<=4'(wide_count-5'd16);
                        end else begin
                            pack_q<=wide_pack[127:0];pack_count<=wide_count[3:0];
                        end
                        if(k_q==9'(BEATS_PER_SRC_ROW-1))state<=ROW_END;
                        else begin k_q<=k_q+1'b1;state<=BREQ;end
                    end else if(stage_count==0)begin
                        if(k_q==9'(BEATS_PER_SRC_ROW-1))state<=ROW_END;
                        else begin k_q<=k_q+1'b1;state<=BREQ;end
                    end
                end
                ROW_END:if(!wr_valid)begin
                    y_q<=y_q+1'b1;outrow_q<=outrow_q+30'(OUT_STRIDE_B);state<=ROW;
                end
                FINISH:if(!wr_valid)begin busy<=0;done<=1;state<=REARM;end
                REARM:if(!start)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
