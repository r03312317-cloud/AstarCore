module dc_realtime_core_csr #(
    parameter logic [31:0] HART_ID = 32'd0
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [11:0] read_address,
    output logic        read_valid,
    output logic        read_only,
    output logic [31:0] read_data,
    input  logic [11:0] probe_address,
    output logic        probe_valid,
    output logic        probe_read_only,
    output logic [1:0]  probe_data_low,
    input  logic        write_valid,
    input  logic [11:0] write_address,
    input  logic [31:0] write_data,
    output logic [31:0] write_effective_data,
    input  logic        trap_valid,
    input  logic [31:0] trap_pc,
    input  logic [31:0] trap_cause,
    input  logic [31:0] trap_tval,
    input  logic        mret_valid,
    input  logic [31:0] mip,
    output logic [31:0] mtvec,
    output logic [31:0] mepc,
    output logic [13:1] mie,
    output logic        mstatus_mie
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam logic [11:0] CSR_MSTATUS  = 12'h300;
    localparam logic [11:0] CSR_MISA     = 12'h301;
    localparam logic [11:0] CSR_MIE      = 12'h304;
    localparam logic [11:0] CSR_MTVEC    = 12'h305;
    localparam logic [11:0] CSR_MSCRATCH = 12'h340;
    localparam logic [11:0] CSR_MEPC     = 12'h341;
    localparam logic [11:0] CSR_MCAUSE   = 12'h342;
    localparam logic [11:0] CSR_MTVAL    = 12'h343;
    localparam logic [11:0] CSR_MIP      = 12'h344;
    localparam logic [11:0] CSR_MHARTID  = 12'hf14;
    localparam logic [31:0] MSTATUS_MPP  = 32'h0000_1800;
    localparam logic [31:0] MSTATUS_MASK = 32'h0000_0088;
    localparam logic [31:0] MIE_MASK     = 32'h0000_3ffe;

    logic [31:0] mstatus_q;
    logic [31:0] mtvec_q;
    logic [31:0] mie_q;
    logic [31:0] mscratch_q;
    logic [31:0] mepc_q;
    logic [31:0] mcause_q;
    logic [31:0] mtval_q;
    logic [33:0] read_decode;

    function automatic logic [33:0] decode_read(input logic [11:0] address);
        begin
            case (address)
                CSR_MSTATUS:  decode_read = {1'b1, 1'b0, mstatus_q};
                CSR_MISA:     decode_read = {1'b1, 1'b1, 32'h4000_1100};
                CSR_MIE:      decode_read = {1'b1, 1'b0, mie_q};
                CSR_MTVEC:    decode_read = {1'b1, 1'b0, mtvec_q};
                CSR_MSCRATCH: decode_read = {1'b1, 1'b0, mscratch_q};
                CSR_MEPC:     decode_read = {1'b1, 1'b0, mepc_q};
                CSR_MCAUSE:   decode_read = {1'b1, 1'b0, mcause_q};
                CSR_MTVAL:    decode_read = {1'b1, 1'b0, mtval_q};
                CSR_MIP:      decode_read = {1'b1, 1'b1, mip};
                CSR_MHARTID:  decode_read = {1'b1, 1'b1, HART_ID};
                default:      decode_read = {1'b0, 1'b0, 32'd0};
            endcase
        end
    endfunction

    function automatic logic [3:0] decode_probe(input logic [11:0] address);
        begin
            case (address)
                CSR_MSTATUS:  decode_probe = {1'b1, 1'b0, mstatus_q[1:0]};
                CSR_MISA:     decode_probe = {1'b1, 1'b1, 2'b00};
                CSR_MIE:      decode_probe = {1'b1, 1'b0, mie_q[1:0]};
                CSR_MTVEC:    decode_probe = {1'b1, 1'b0, mtvec_q[1:0]};
                CSR_MSCRATCH: decode_probe = {1'b1, 1'b0, mscratch_q[1:0]};
                CSR_MEPC:     decode_probe = {1'b1, 1'b0, mepc_q[1:0]};
                CSR_MCAUSE:   decode_probe = {1'b1, 1'b0, mcause_q[1:0]};
                CSR_MTVAL:    decode_probe = {1'b1, 1'b0, mtval_q[1:0]};
                CSR_MIP:      decode_probe = {1'b1, 1'b1, mip[1:0]};
                CSR_MHARTID:  decode_probe = {1'b1, 1'b1, HART_ID[1:0]};
                default:      decode_probe = {1'b0, 1'b0, 2'b00};
            endcase
        end
    endfunction

    always_comb begin
        read_decode = decode_read(read_address);
        {read_valid, read_only, read_data} = read_decode;
        {probe_valid, probe_read_only, probe_data_low} = decode_probe(probe_address);
        case (write_address)
            CSR_MSTATUS: write_effective_data = (write_data & MSTATUS_MASK) | MSTATUS_MPP;
            CSR_MIE:     write_effective_data = write_data & MIE_MASK;
            CSR_MTVEC:   write_effective_data = {write_data[31:2], 2'b00};
            default:     write_effective_data = write_data;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mstatus_q  <= MSTATUS_MPP;
            mtvec_q    <= 32'd0;
            mie_q      <= 32'd0;
            mscratch_q <= 32'd0;
            mepc_q     <= 32'd0;
            mcause_q   <= 32'd0;
            mtval_q    <= 32'd0;
        end else if (trap_valid) begin
            mstatus_q[3]     <= 1'b0;
            mstatus_q[7]     <= mstatus_q[3];
            mstatus_q[12:11] <= 2'b11;
            mepc_q            <= trap_pc;
            mcause_q          <= trap_cause;
            mtval_q           <= trap_tval;
        end else begin
            if (write_valid) begin
                case (write_address)
                    CSR_MSTATUS:  mstatus_q <= (write_data & MSTATUS_MASK) | MSTATUS_MPP;
                    CSR_MIE:      mie_q <= write_data & MIE_MASK;
                    CSR_MTVEC:    mtvec_q <= {write_data[31:2], 2'b00};
                    CSR_MSCRATCH: mscratch_q <= write_data;
                    CSR_MEPC:     mepc_q <= write_data;
                    CSR_MCAUSE:   mcause_q <= write_data;
                    CSR_MTVAL:    mtval_q <= write_data;
                    default: begin end
                endcase
            end
            if (mret_valid) begin
                mstatus_q[3]     <= mstatus_q[7];
                mstatus_q[7]     <= 1'b1;
                mstatus_q[12:11] <= 2'b11;
            end
        end
    end

    assign mtvec = mtvec_q;
    assign mepc = mepc_q;
    assign mie = mie_q[13:1];
    assign mstatus_mie = mstatus_q[3];
endmodule
