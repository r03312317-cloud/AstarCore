module npu_free_slot_allocator #(
  parameter int SLOT_COUNT = 4
) (
  input  logic clk,
  input  logic rst,
  input  logic allocate_take,
  output logic allocate_valid,
  output logic [((SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 1)-1:0]
               allocate_slot,
  input  logic release_valid,
  input  logic [((SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 1)-1:0]
               release_slot,
  output logic [((SLOT_COUNT >= 1) ? $clog2(SLOT_COUNT + 1) : 1)-1:0]
               free_count,
  output logic protocol_error
);
  localparam int SLOT_W = (SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 1;
  localparam int COUNT_W = (SLOT_COUNT >= 1) ? $clog2(SLOT_COUNT + 1) : 1;
  localparam int TREE_LEVELS = (SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 0;
  localparam int TREE_LEAVES = 1 << TREE_LEVELS;
  localparam logic [SLOT_W:0] SLOT_COUNT_EXT = (SLOT_W + 1)'(SLOT_COUNT);

  logic [SLOT_COUNT-1:0] free_bitmap_q;
  logic [TREE_LEAVES-1:0] tree_valid [0:TREE_LEVELS]
    /* verilator split_var */;
  logic [SLOT_W-1:0] tree_slot [0:TREE_LEVELS][0:TREE_LEAVES-1]
    /* verilator split_var */;
  logic allocate_fire;
  logic release_accept;
  logic release_error;
  logic [COUNT_W-1:0] free_count_q;

  generate
    for (genvar leaf = 0; leaf < TREE_LEAVES; leaf++) begin : g_tree_leaf
      if (leaf < SLOT_COUNT) begin : g_physical_slot
        assign tree_valid[0][leaf] = free_bitmap_q[leaf];
      end else begin : g_padded_slot
        assign tree_valid[0][leaf] = 1'b0;
      end
      assign tree_slot[0][leaf] = SLOT_W'(leaf);
    end

    for (genvar level = 1; level <= TREE_LEVELS; level++) begin : g_tree_level
      for (genvar node = 0; node < TREE_LEAVES; node++) begin : g_tree_node
        if (node < (TREE_LEAVES >> level)) begin : g_parent
          assign tree_valid[level][node] =
            tree_valid[level-1][2*node] | tree_valid[level-1][2*node+1];
          assign tree_slot[level][node] = tree_valid[level-1][2*node]
            ? tree_slot[level-1][2*node]
            : tree_slot[level-1][2*node+1];
        end else begin : g_unused
          assign tree_valid[level][node] = 1'b0;
          assign tree_slot[level][node] = '0;
        end
      end
    end
  endgenerate

  assign allocate_valid = (rst === 1'b0) && tree_valid[TREE_LEVELS][0];
  assign allocate_slot = tree_slot[TREE_LEVELS][0];
  assign allocate_fire = (allocate_take === 1'b1) && allocate_valid;
  assign free_count = free_count_q;

  always_comb begin
    release_accept = 1'b0;
    release_error = 1'b0;
    if (release_valid === 1'b1) begin
      if ((^release_slot) === 1'bx) begin
        release_error = 1'b1;
      end else if ({1'b0, release_slot} >= SLOT_COUNT_EXT) begin
        release_error = 1'b1;
      end else if (free_bitmap_q[release_slot] !== 1'b0) begin
        release_error = 1'b1;
      end else begin
        release_accept = 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      free_bitmap_q <= {SLOT_COUNT{1'b1}};
      free_count_q <= COUNT_W'(SLOT_COUNT);
      protocol_error <= 1'b0;
    end else begin
      if (allocate_fire)
        free_bitmap_q[allocate_slot] <= 1'b0;
      if (release_accept)
        free_bitmap_q[release_slot] <= 1'b1;

      case ({allocate_fire, release_accept})
        2'b10: free_count_q <= free_count_q - COUNT_W'(1);
        2'b01: free_count_q <= free_count_q + COUNT_W'(1);
        2'b11: free_count_q <= free_count_q;
        default: free_count_q <= free_count_q;
      endcase
      protocol_error <= release_error;
    end
  end

  generate
    if (SLOT_COUNT < 1) begin : g_bad_slot_count
      initial $fatal(1, "npu_free_slot_allocator: SLOT_COUNT must be at least 1");
    end
  endgenerate
endmodule
