module npu_elastic_fifo #(
  parameter int WIDTH = 8,
  parameter int DEPTH = 4,
  parameter int COUNT_W = (DEPTH >= 1) ? $clog2(DEPTH + 1) : 1
) (
  input  logic               clk,
  input  logic               rst,
  input  logic               in_valid,
  output logic               in_ready,
  input  logic [WIDTH-1:0]   in_data,
  output logic               out_valid,
  input  logic               out_ready,
  output logic [WIDTH-1:0]   out_data,
  output logic [COUNT_W-1:0] occupancy
);
  localparam int BACKING_DEPTH = (DEPTH > 1) ? DEPTH - 1 : 1;
  localparam int PTR_W = (DEPTH > 2) ? $clog2(DEPTH - 1) : 1;

  logic [WIDTH-1:0] backing [0:BACKING_DEPTH-1];
  logic [PTR_W-1:0] head_q, tail_q;
  logic [WIDTH-1:0] out_data_q;
  logic out_valid_q;
  logic [COUNT_W-1:0] occupancy_q;
  logic push, pop;

  function automatic logic [PTR_W-1:0] next_backing_ptr(
    input logic [PTR_W-1:0] ptr
  );
    if (DEPTH <= 2)
      next_backing_ptr = '0;
    else if (ptr == PTR_W'(DEPTH - 2))
      next_backing_ptr = '0;
    else
      next_backing_ptr = ptr + PTR_W'(1);
  endfunction

  assign in_ready = !rst && (occupancy_q < COUNT_W'(DEPTH));
  assign out_valid = out_valid_q;
  assign out_data = out_data_q;
  assign occupancy = occupancy_q;
  assign push = (in_valid === 1'b1) && in_ready;
  assign pop = out_valid_q && (out_ready === 1'b1);

  always_ff @(posedge clk) begin
    if (rst) begin
      head_q <= '0;
      tail_q <= '0;
      out_data_q <= '0;
      out_valid_q <= 1'b0;
      occupancy_q <= '0;
    end else begin
      case ({push, pop})
        2'b10: begin
          if (!out_valid_q) begin
            out_data_q <= in_data;
            out_valid_q <= 1'b1;
          end else begin
            backing[tail_q] <= in_data;
            tail_q <= next_backing_ptr(tail_q);
          end
          occupancy_q <= occupancy_q + COUNT_W'(1);
        end
        2'b01: begin
          if (occupancy_q > COUNT_W'(1)) begin
            out_data_q <= backing[head_q];
            head_q <= next_backing_ptr(head_q);
            occupancy_q <= occupancy_q - COUNT_W'(1);
          end else begin
            out_valid_q <= 1'b0;
            occupancy_q <= '0;
          end
        end
        2'b11: begin
          if (occupancy_q == COUNT_W'(1)) begin
            out_data_q <= in_data;
          end else begin
            out_data_q <= backing[head_q];
            head_q <= next_backing_ptr(head_q);
            backing[tail_q] <= in_data;
            tail_q <= next_backing_ptr(tail_q);
          end
        end
        default: begin end
      endcase
    end
  end

  generate
    if (WIDTH < 1) begin : g_bad_width
      initial $fatal(1, "npu_elastic_fifo: WIDTH must be at least 1");
    end
    if (DEPTH < 1) begin : g_bad_depth
      initial $fatal(1, "npu_elastic_fifo: DEPTH must be at least 1");
    end
  endgenerate
endmodule
