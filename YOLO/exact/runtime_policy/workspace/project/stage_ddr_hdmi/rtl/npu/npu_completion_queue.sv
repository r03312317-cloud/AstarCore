function automatic integer npu_completion_count_width(input integer depth);
  begin
    if (depth < 2)
      npu_completion_count_width = 1;
    else
      npu_completion_count_width = $clog2(depth + 1);
  end
endfunction

module npu_completion_queue #(parameter int DEPTH=4) (
  input logic clk, rst,
  input logic reserve_valid,
  output logic reserve_ready,
  input logic release_reservation,
  input logic enqueue_valid,
  output logic enqueue_ready,
  input npu_defs_pkg::npu_completion_t enqueue_data,
  output logic head_valid,
  output npu_defs_pkg::npu_completion_t head_data,
  input logic pop,
  output logic [npu_completion_count_width(DEPTH)-1:0] level,
  output logic [npu_completion_count_width(DEPTH)-1:0] reserved
);
  localparam int COUNT_W = npu_completion_count_width(DEPTH);
  localparam logic [COUNT_W-1:0] DEPTH_COUNT = COUNT_W'(DEPTH);
  localparam logic [COUNT_W:0] DEPTH_CAPACITY = (COUNT_W+1)'(DEPTH);

  generate
    if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0) begin : g_invalid_depth
      initial $fatal(1, "npu_completion_queue: DEPTH must be a power of two and at least 2");

      assign reserve_ready = 1'b0;
      assign enqueue_ready = 1'b0;
      assign head_valid = 1'b0;
      assign head_data = '0;
      assign level = '0;
      assign reserved = '0;
    end else begin : g_valid_depth
      localparam int PTR_W = $clog2(DEPTH);

      npu_defs_pkg::npu_completion_t mem [0:DEPTH-1];
      logic [PTR_W-1:0] rd_ptr, wr_ptr;
      logic reserve_fire, enqueue_fire, release_fire, pop_fire;
      logic [COUNT_W:0] capacity_used;

      assign capacity_used = {1'b0, level} + {1'b0, reserved};
      assign head_valid = (level != '0);
      assign head_data = mem[rd_ptr];
      assign pop_fire = head_valid && pop;
      assign reserve_ready = capacity_used < DEPTH_CAPACITY;
      assign reserve_fire = reserve_valid && reserve_ready;
      assign enqueue_ready = (reserved != '0) && ((level != DEPTH_COUNT) || pop_fire);
      assign enqueue_fire = enqueue_valid && enqueue_ready;
      assign release_fire = release_reservation && (reserved != '0) && !enqueue_fire;

`ifndef SYNTHESIS
      always @(posedge clk) begin
        if (!rst) begin
          assert (!(enqueue_valid && release_reservation))
            else $error("npu_completion_queue: enqueue and release cannot occur together");
          assert (!(enqueue_fire && (reserved == '0)))
            else $fatal(1, "npu_completion_queue: enqueue consumed no reservation");
          assert (!(release_fire && (reserved == '0)))
            else $fatal(1, "npu_completion_queue: release consumed no reservation");
          assert (capacity_used <= DEPTH_CAPACITY)
            else $fatal(1, "npu_completion_queue: capacity invariant violated");
        end
      end
`endif

      always_ff @(posedge clk) begin
        if (rst) begin
          rd_ptr <= '0;
          wr_ptr <= '0;
          level <= '0;
          reserved <= '0;
        end else begin
          if (enqueue_fire) begin
            mem[wr_ptr] <= enqueue_data;
            wr_ptr <= wr_ptr + 1'b1;
          end
          if (pop_fire)
            rd_ptr <= rd_ptr + 1'b1;

          case ({enqueue_fire, pop_fire})
            2'b10: level <= level + 1'b1;
            2'b01: level <= level - 1'b1;
            default: level <= level;
          endcase
          case ({reserve_fire, (enqueue_fire || release_fire)})
            2'b10: reserved <= reserved + 1'b1;
            2'b01: reserved <= reserved - 1'b1;
            default: reserved <= reserved;
          endcase
        end
      end
    end
  endgenerate
endmodule
