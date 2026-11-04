module dc_realtime_mul_backend (
    input logic clk, rst, operand_ce, product_ce,
    input logic [15:0] req_a_low, req_b_low,
    input logic signed [16:0] req_a_high, req_b_high,
    output logic [31:0] pp_ll_q,
    output logic signed [33:0] pp_lh_q, pp_hl_q, pp_hh_q
);
    timeunit 1ns;
    timeprecision 1ps;
    logic [24:0] dsp_a [0:3];
    logic [17:0] dsp_b [0:3];
    wire [47:0] dsp_product [0:3];
    // Capture partial products directly in DSP P registers on request.
    // This trades the input-to-DSP setup path for one low-MUL pipeline cycle.
    always_comb begin
        dsp_a[0] = {9'd0, req_a_low};
        dsp_b[0] = {2'd0, req_b_low};
        dsp_a[1] = {9'd0, req_a_low};
        dsp_b[1] = {req_b_high[16], req_b_high};
        dsp_a[2] = {{8{req_a_high[16]}}, req_a_high};
        dsp_b[2] = {2'd0, req_b_low};
        dsp_a[3] = {{8{req_a_high[16]}}, req_a_high};
        dsp_b[3] = {req_b_high[16], req_b_high};
    end

    for (genvar partial_index = 0; partial_index < 4; partial_index++) begin : dsp_partial_gen
        DSP48E1 #(
            .ACASCREG(0), .AREG(0), .BCASCREG(0), .BREG(0),
            .ADREG(0), .ALUMODEREG(0), .CARRYINREG(0),
            .CARRYINSELREG(0), .CREG(0), .DREG(0), .INMODEREG(0),
            .MREG(0), .OPMODEREG(0), .PREG(1),
            .USE_DPORT("FALSE"), .USE_MULT("MULTIPLY"), .USE_SIMD("ONE48")
        ) pp_dsp (
            .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
            .MULTSIGNOUT(), .OVERFLOW(), .P(dsp_product[partial_index]),
            .PATTERNBDETECT(), .PATTERNDETECT(), .PCOUT(), .UNDERFLOW(),
            .A({5'd0, dsp_a[partial_index]}), .ACIN(30'd0),
            .ALUMODE(4'd0), .B(dsp_b[partial_index]), .BCIN(18'd0),
            .C(48'd0), .CARRYCASCIN(1'b0), .CARRYIN(1'b0),
            .CARRYINSEL(3'd0), .CEA1(1'b0), .CEA2(1'b0),
            .CEAD(1'b0), .CEALUMODE(1'b0), .CEB1(1'b0),
            .CEB2(1'b0), .CEC(1'b0), .CECARRYIN(1'b0),
            .CECTRL(1'b0), .CED(1'b0), .CEINMODE(1'b0),
            .CEM(1'b0), .CEP(product_ce), .CLK(clk), .D(25'd0),
            .INMODE(5'd0), .MULTSIGNIN(1'b0), .OPMODE(7'b0000101),
            .PCIN(48'd0), .RSTA(rst), .RSTALLCARRYIN(rst),
            .RSTALUMODE(rst), .RSTB(rst), .RSTC(rst), .RSTCTRL(rst),
            .RSTD(rst), .RSTINMODE(rst), .RSTM(rst), .RSTP(rst)
        );
    end

    assign pp_ll_q = dsp_product[0][31:0];
    assign pp_lh_q = dsp_product[1][33:0];
    assign pp_hl_q = dsp_product[2][33:0];
    assign pp_hh_q = dsp_product[3][33:0];

endmodule
