module pg_gpio #(
    parameter int WIDTH = 32
) (
    input logic clk, rst,
    input logic [WIDTH-1:0] pins_in,
    input logic [WIDTH-1:0] value_out,
    output logic [WIDTH-1:0] pins_out,
    output logic [WIDTH-1:0] sampled_in
);
    logic [WIDTH-1:0] meta_q;
    assign pins_out = value_out;
    always_ff @(posedge clk) begin
        if (rst) begin meta_q <= '0; sampled_in <= '0; end
        else begin meta_q <= pins_in; sampled_in <= meta_q; end
    end
endmodule
