module npu_cmd_queue #(parameter int DEPTH=4) (
  input logic clk, rst,
  input logic push_valid, output logic push_ready,
  input npu_defs_pkg::npu_cmd_t push_data,
  output logic pop_valid, input logic pop_ready,
  output npu_defs_pkg::npu_cmd_t pop_data,
  output logic [$clog2(DEPTH+1)-1:0] level,
  output logic full, empty
);
  localparam int PTR_W = (DEPTH >= 2) ? $clog2(DEPTH) : 1;
  localparam int LEVEL_W = $clog2(DEPTH + 1);
  localparam logic [LEVEL_W-1:0] DEPTH_COUNT = LEVEL_W'(DEPTH);

  generate
    if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0) begin : g_invalid_depth
      initial $fatal(1, "npu_cmd_queue: DEPTH must be a power of two and at least 2");
    end
  endgenerate

  npu_defs_pkg::npu_cmd_t mem [0:DEPTH-1];
  logic [PTR_W-1:0] rd_ptr, wr_ptr;
  logic push_fire, pop_fire;

  assign empty = (level == '0);
  assign full = (level == DEPTH_COUNT);
  assign pop_valid = !empty;
  assign pop_data = mem[rd_ptr];
  assign push_ready = !full || (pop_valid && pop_ready);
  assign push_fire = push_valid && push_ready;
  assign pop_fire = pop_valid && pop_ready;

  always_ff @(posedge clk) begin
    if (rst) begin
      rd_ptr <= '0;
      wr_ptr <= '0;
      level <= '0;
    end else begin
      if (push_fire) begin
        mem[wr_ptr] <= push_data;
        wr_ptr <= wr_ptr + 1'b1;
      end
      if (pop_fire)
        rd_ptr <= rd_ptr + 1'b1;
      case ({push_fire, pop_fire})
        2'b10: level <= level + 1'b1;
        2'b01: level <= level - 1'b1;
        default: level <= level;
      endcase
    end
  end
endmodule
