// ---------------------------------------------------------------------------
// DSP48E1 behavioural model for Verilator simulation only.
//
// The production build uses rtl/vendor/dsp48e1_pango_compat.sv, which maps the
// same module name onto a Pango Logos2 GTP_APM_E2 hard block.  Verilator has no
// access to the vendor primitive library, so simulation compiles this file
// instead.  Both files are mutually exclusive in the file lists.
//
// Only the configuration used by dc_realtime_mul_backend.sv is modelled:
//   USE_MULT="MULTIPLY", USE_DPORT="FALSE", USE_SIMD="ONE48",
//   OPMODE=7'b0000101 (P = M), AREG/BREG/MREG/PREG as instantiated,
//   C/D/post-adder unused.
//
// Timing contract: one product register, no accumulation.  That is what the
// CPU multiply unit expects from the production back end as well.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
module DSP48E1 #(
    parameter integer ACASCREG = 1,
    parameter integer AREG = 1,
    parameter integer BCASCREG = 1,
    parameter integer BREG = 1,
    parameter integer ADREG = 1,
    parameter integer ALUMODEREG = 1,
    parameter integer CARRYINREG = 1,
    parameter integer CARRYINSELREG = 1,
    parameter integer CREG = 1,
    parameter integer DREG = 1,
    parameter integer INMODEREG = 1,
    parameter integer MREG = 1,
    parameter integer OPMODEREG = 1,
    parameter integer PREG = 1,
    parameter string  USE_DPORT = "FALSE",
    parameter string  USE_MULT = "MULTIPLY",
    parameter string  USE_SIMD = "ONE48"
) (
    output logic [29:0] ACOUT,
    output logic [17:0] BCOUT,
    output logic        CARRYCASCOUT,
    output logic [3:0]  CARRYOUT,
    output logic        MULTSIGNOUT,
    output logic        OVERFLOW,
    output logic [47:0] P,
    output logic        PATTERNBDETECT,
    output logic        PATTERNDETECT,
    output logic [47:0] PCOUT,
    output logic        UNDERFLOW,
    input  logic [29:0] A,
    input  logic [29:0] ACIN,
    input  logic [3:0]  ALUMODE,
    input  logic [17:0] B,
    input  logic [17:0] BCIN,
    input  logic [47:0] C,
    input  logic        CARRYCASCIN,
    input  logic        CARRYIN,
    input  logic [2:0]  CARRYINSEL,
    input  logic        CEA1,
    input  logic        CEA2,
    input  logic        CEAD,
    input  logic        CEALUMODE,
    input  logic        CEB1,
    input  logic        CEB2,
    input  logic        CEC,
    input  logic        CECARRYIN,
    input  logic        CECTRL,
    input  logic        CED,
    input  logic        CEINMODE,
    input  logic        CEM,
    input  logic        CEP,
    input  logic        CLK,
    input  logic [24:0] D,
    input  logic [4:0]  INMODE,
    input  logic        MULTSIGNIN,
    input  logic [6:0]  OPMODE,
    input  logic [47:0] PCIN,
    input  logic        RSTA,
    input  logic        RSTALLCARRYIN,
    input  logic        RSTALUMODE,
    input  logic        RSTB,
    input  logic        RSTC,
    input  logic        RSTCTRL,
    input  logic        RSTD,
    input  logic        RSTINMODE,
    input  logic        RSTM,
    input  logic        RSTP
);
    timeunit 1ns;
    timeprecision 1ps;

    logic signed [24:0] a_q;
    logic signed [17:0] b_q;
    logic signed [47:0] m_q;
    logic signed [47:0] p_q;

    wire signed [24:0] a_mux = INMODE[0] ? $signed(D) : $signed(A[24:0]);
    wire signed [17:0] b_mux = B;
    wire signed [47:0] product = a_mux * b_mux;

    always_ff @(posedge CLK) begin
        if (RSTA) a_q <= '0;
        else if (AREG == 0 || CEA2) a_q <= a_mux;
        if (RSTB) b_q <= '0;
        else if (BREG == 0 || CEB2) b_q <= b_mux;
        if (RSTM) m_q <= '0;
        else if (MREG == 0 || CEM) m_q <= a_q * b_q;
        if (RSTP) p_q <= '0;
        else if (PREG == 0 || CEP) p_q <= (OPMODE[3:0] == 4'b0101) ? product : m_q;
    end

    assign P = p_q;
    assign ACOUT = '0;
    assign BCOUT = '0;
    assign CARRYCASCOUT = 1'b0;
    assign CARRYOUT = '0;
    assign MULTSIGNOUT = 1'b0;
    assign OVERFLOW = 1'b0;
    assign PATTERNBDETECT = 1'b0;
    assign PATTERNDETECT = 1'b0;
    assign PCOUT = '0;
    assign UNDERFLOW = 1'b0;
endmodule
