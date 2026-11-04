module dc_realtime_core_regfile (
    input  logic        clk,
    input  logic        rst,
    input  logic        read_fast_context,
    input  logic [4:0]  read_rs1,
    input  logic [4:0]  read_rs2,
    output logic [31:0] read_rs1_value,
    output logic [31:0] read_rs2_value,
    input  logic        write_valid,
    input  logic        write_fast_context,
    input  logic [4:0]  write_rd,
    input  logic [31:0] write_value
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [5:0] read_address_rs1;
    logic [5:0] read_address_rs2;
    logic [5:0] write_address;
    logic [63:0] register_valid_q;

    (* ram_style = "distributed" *) logic [31:0] registers [0:63] /* synthesis syn_ramstyle = "lut_ram" */;
    (* ram_style = "distributed" *) logic [31:0] registers_rs2 [0:63] /* synthesis syn_ramstyle = "lut_ram" */;

    assign read_address_rs1 = {read_fast_context, read_rs1};
    assign read_address_rs2 = {read_fast_context, read_rs2};
    assign write_address = {write_fast_context, write_rd};

    assign read_rs1_value = (read_rs1 == 5'd0 ||
                             !register_valid_q[read_address_rs1]) ?
                            32'd0 : registers[read_address_rs1];
    assign read_rs2_value = (read_rs2 == 5'd0 ||
                             !register_valid_q[read_address_rs2]) ?
                            32'd0 : registers_rs2[read_address_rs2];

    always_ff @(posedge clk) begin
        if (rst) begin
            register_valid_q <= 64'd0;
        end else begin
            if (write_valid && write_rd != 5'd0) begin
                registers[write_address] <= write_value;
                registers_rs2[write_address] <= write_value;
                register_valid_q[write_address] <= 1'b1;
            end
        end
    end
endmodule
