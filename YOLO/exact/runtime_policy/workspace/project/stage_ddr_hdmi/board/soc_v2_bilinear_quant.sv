`timescale 1ns/1ps
// Fully elastic V2 pixel interpolation. The five registered steps isolate
// phase weights, products, sum, exact /400, and model LUT access. Every step
// obeys valid/ready, so arbitrary DDR and output stalls preserve raster order.
module soc_v2_bilinear_quant (
    input logic clk,rst,
    input logic lut_write,
    input logic [7:0] lut_addr,lut_data,
    output logic lut_ready,lut_complete,
    input logic in_valid,
    output logic in_ready,
    input logic pad,
    input logic [15:0] c00,c01,c10,c11,
    input logic [4:0] phase_x,phase_y,
    output logic out_valid,
    input logic out_ready,
    output logic [23:0] out_rgb_i8
);
    (* ram_style="distributed" *) logic [7:0] lut[0:255];
    logic [255:0] written;
    logic locked;
    logic [4:0] valid_q;
    logic [3:0] pad_q;
    logic [8:0] weight_q[0:3];
    logic [7:0] sample_q[0:11];
    logic [16:0] product_q[0:11];
    logic [18:0] sum_q[0:2];
    logic [7:0] rgb_q[0:2];
    logic ready_0,ready_1,ready_2,ready_3,ready_4;

    function automatic logic [7:0] expand(input logic [15:0] word,
                                           input int channel);
        logic [4:0] five;
        logic [5:0] six;
        case(channel)
            0: begin five=word[15:11];return {five,five[4:2]}; end
            1: begin six=word[10:5];return {six,six[5:4]}; end
            default: begin five=word[4:0];return {five,five[4:2]}; end
        endcase
    endfunction

    assign lut_ready=!rst && !locked;
    assign lut_complete=&written;
    assign ready_4=!valid_q[4] || out_ready;
    assign ready_3=!valid_q[3] || ready_4;
    assign ready_2=!valid_q[2] || ready_3;
    assign ready_1=!valid_q[1] || ready_2;
    assign ready_0=!valid_q[0] || ready_1;
    assign in_ready=!rst && lut_complete && ready_0;
    assign out_valid=valid_q[4];

    always_ff @(posedge clk) begin
        if(rst) begin
            written<='0;locked<=0;valid_q<='0;pad_q<='0;
            out_rgb_i8<=0;
        end else begin
            if(lut_write && lut_ready) begin
                lut[lut_addr]<=lut_data;
                written[lut_addr]<=1;
            end
            if(ready_4) begin
                valid_q[4]<=valid_q[3];
                if(valid_q[3])
                    out_rgb_i8<={lut[rgb_q[2]],lut[rgb_q[1]],lut[rgb_q[0]]};
            end
            if(ready_3) begin
                valid_q[3]<=valid_q[2];
                if(valid_q[2]) begin
                    pad_q[3]<=pad_q[2];
                    for(int ch=0;ch<3;ch++)
                        rgb_q[ch]<=pad_q[2] ? 8'd114 :
                                   8'((sum_q[ch]+19'd200)/19'd400);
                end
            end
            if(ready_2) begin
                valid_q[2]<=valid_q[1];
                if(valid_q[1]) begin
                    pad_q[2]<=pad_q[1];
                    for(int ch=0;ch<3;ch++)
                        sum_q[ch]<=19'(product_q[ch*4+0])+
                                   19'(product_q[ch*4+1])+
                                   19'(product_q[ch*4+2])+
                                   19'(product_q[ch*4+3]);
                end
            end
            if(ready_1) begin
                valid_q[1]<=valid_q[0];
                if(valid_q[0]) begin
                    pad_q[1]<=pad_q[0];
                    for(int ch=0;ch<3;ch++)
                        for(int tap=0;tap<4;tap++)
                            product_q[ch*4+tap]<=17'(weight_q[tap])*
                                                 17'(sample_q[ch*4+tap]);
                end
            end
            if(ready_0) begin
                valid_q[0]<=in_valid && lut_complete;
                if(in_valid && lut_complete) begin
                    locked<=1;pad_q[0]<=pad;
                    weight_q[0]<=9'(20-phase_x)*9'(20-phase_y);
                    weight_q[1]<=9'(phase_x)*9'(20-phase_y);
                    weight_q[2]<=9'(20-phase_x)*9'(phase_y);
                    weight_q[3]<=9'(phase_x)*9'(phase_y);
                    for(int ch=0;ch<3;ch++) begin
                        sample_q[ch*4+0]<=expand(c00,ch);
                        sample_q[ch*4+1]<=expand(c01,ch);
                        sample_q[ch*4+2]<=expand(c10,ch);
                        sample_q[ch*4+3]<=expand(c11,ch);
                    end
                end
            end
        end
    end
    initial if(20*20*255>19'h7ffff) $fatal(1,"V2_WEIGHT_WIDTH");
endmodule
