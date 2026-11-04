// Ping/pong scratchpad boundary.  Owner packing is bank 0 at [1:0] and bank 1
// at [3:2] for each target.  Vector lane i occupies [i*MAX_ELEM_W +: MAX_ELEM_W].
module npu_scratchpad #(
  parameter int ARRAY_ROWS = 4,
  parameter int ARRAY_COLS = 4,
  parameter int K_TILE = 32,
  parameter int MAX_ELEM_W = 16,
  parameter int DMA_VECTOR_ELEMS = 1,
  parameter bit A_PACKED_INT8_16 = 1'b0
) (
  input  logic clk,
  input  logic rst,
  input  logic owner_req_valid,
  input  logic owner_req_is_b,
  input  logic owner_req_bank,
  input  logic [1:0] owner_req_state,
  input  logic dma_write_valid,
  input  logic dma_is_b,
  input  logic dma_bank,
  input  logic [((ARRAY_ROWS > ARRAY_COLS) ? ((ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1) : ((ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1))-1:0] dma_lane,
  input  logic [((K_TILE > 1) ? $clog2(K_TILE) : 1)-1:0] dma_k,
  input  logic dma_input_int16,
  input  logic signed [DMA_VECTOR_ELEMS*16-1:0] dma_data,
  input  logic [((DMA_VECTOR_ELEMS>1)?$clog2(DMA_VECTOR_ELEMS+1):1)-1:0] dma_count,
  input  logic compute_read_valid,
  input  logic compute_bank,
  input  logic [((K_TILE > 1) ? $clog2(K_TILE) : 1)-1:0] compute_k,
  output logic [ARRAY_ROWS*MAX_ELEM_W-1:0] a_vector,
  output logic [ARRAY_COLS*MAX_ELEM_W-1:0] b_vector,
  output logic compute_read_data_valid,
  output logic [3:0] a_owner,
  output logic [3:0] b_owner,
  output logic protocol_error
);
  generate if(A_PACKED_INT8_16)begin:g_int8packed16
    npu_scratchpad_int8packed16 #(.ARRAY_ROWS(ARRAY_ROWS),.ARRAY_COLS(ARRAY_COLS),
      .K_TILE(K_TILE),.MAX_ELEM_W(MAX_ELEM_W),.DMA_VECTOR_ELEMS(DMA_VECTOR_ELEMS)) impl(.*);
  end else begin:g_legacy
    npu_scratchpad_legacy #(.ARRAY_ROWS(ARRAY_ROWS),.ARRAY_COLS(ARRAY_COLS),
      .K_TILE(K_TILE),.MAX_ELEM_W(MAX_ELEM_W),.DMA_VECTOR_ELEMS(DMA_VECTOR_ELEMS)) impl(.*);
  end endgenerate
endmodule

// Ping/pong scratchpad boundary.  Owner packing is bank 0 at [1:0] and bank 1
// at [3:2] for each target.  Vector lane i occupies [i*MAX_ELEM_W +: MAX_ELEM_W].
module npu_scratchpad_legacy #(
  parameter int ARRAY_ROWS = 4,
  parameter int ARRAY_COLS = 4,
  parameter int K_TILE = 32,
  parameter int MAX_ELEM_W = 16,
  parameter int DMA_VECTOR_ELEMS = 1
) (
  input  logic clk,
  input  logic rst,
  input  logic owner_req_valid,
  input  logic owner_req_is_b,
  input  logic owner_req_bank,
  input  logic [1:0] owner_req_state,
  input  logic dma_write_valid,
  input  logic dma_is_b,
  input  logic dma_bank,
  input  logic [((ARRAY_ROWS > ARRAY_COLS) ? ((ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1) : ((ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1))-1:0] dma_lane,
  input  logic [((K_TILE > 1) ? $clog2(K_TILE) : 1)-1:0] dma_k,
  input  logic dma_input_int16,
  input  logic signed [DMA_VECTOR_ELEMS*16-1:0] dma_data,
  input  logic [((DMA_VECTOR_ELEMS>1)?$clog2(DMA_VECTOR_ELEMS+1):1)-1:0] dma_count,
  input  logic compute_read_valid,
  input  logic compute_bank,
  input  logic [((K_TILE > 1) ? $clog2(K_TILE) : 1)-1:0] compute_k,
  output logic [ARRAY_ROWS*MAX_ELEM_W-1:0] a_vector,
  output logic [ARRAY_COLS*MAX_ELEM_W-1:0] b_vector,
  output logic compute_read_data_valid,
  output logic [3:0] a_owner,
  output logic [3:0] b_owner,
  output logic protocol_error
);
  localparam logic [1:0] OWNER_EMPTY   = 2'd0;
  localparam logic [1:0] OWNER_FILLING = 2'd1;
  localparam logic [1:0] OWNER_READY   = 2'd2;
  localparam logic [1:0] OWNER_COMPUTE = 2'd3;
  localparam int LANE_W = (ARRAY_ROWS > ARRAY_COLS) ?
                          ((ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1) :
                          ((ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1);
  localparam int K_W = (K_TILE > 1) ? $clog2(K_TILE) : 1;
  localparam int B_DATA_W = ARRAY_COLS*16;
  localparam logic [LANE_W:0] ARRAY_ROWS_COUNT = (LANE_W+1)'(ARRAY_ROWS);
  localparam logic [LANE_W:0] ARRAY_COLS_COUNT = (LANE_W+1)'(ARRAY_COLS);
  localparam logic [K_W:0] K_TILE_COUNT = (K_W+1)'(K_TILE);

  // TC4: physical lane banking; {ping/pong, k} is the local RAM address.
  // Writes, owner changes and compute reads remain independent actions using
  // pre-edge ownership. The controller owns reset/invalid-read zeroing; the
  // data RAM has no reset and keeps a canonical synchronous 1R/1W template.
  logic dma_legal, compute_legal, dma_fire, compute_fire, vector_zero_q;
  localparam int VLOG=(DMA_VECTOR_ELEMS>1)?$clog2(DMA_VECTOR_ELEMS):0;
  localparam int SUB_W=(VLOG>0)?VLOG:1;
  localparam int PACK_ADDR_W=K_W+1-VLOG;
  logic [DMA_VECTOR_ELEMS*16-1:0] normalized_dma_vector,a_write_data;
  logic [DMA_VECTOR_ELEMS-1:0] a_write_mask, count_mask;
  logic [ARRAY_COLS-1:0] b_write_mask;
  logic [ARRAY_COLS*16-1:0] b_write_data;
  logic [SUB_W-1:0] write_sub,read_sub_q;
  logic [PACK_ADDR_W-1:0] packed_write_address,packed_read_address;
  logic [K_W:0] write_address, read_address;
  always_comb begin
    dma_legal = !(((dma_is_b !== 1'b0) && (dma_is_b !== 1'b1)) ||
                  ((dma_bank !== 1'b0) && (dma_bank !== 1'b1)) ||
                  ((dma_input_int16 !== 1'b0) && (dma_input_int16 !== 1'b1)) ||
                  ((^dma_lane) === 1'bx) || ((^dma_k) === 1'bx) ||
                  ((^dma_count) === 1'bx) || dma_count=='0 || int'(dma_count)>DMA_VECTOR_ELEMS ||
                  ((!dma_is_b) && (int'(dma_k)+int'(dma_count)>K_TILE ||
                    int'(write_sub)+int'(dma_count)>DMA_VECTOR_ELEMS)) ||
                  ((dma_is_b) && int'(dma_lane)+int'(dma_count)>ARRAY_COLS) ||
                  ({1'b0,dma_k} >= K_TILE_COUNT) ||
                  ((dma_is_b === 1'b1) && ({1'b0,dma_lane} >= ARRAY_COLS_COUNT)) ||
                  ((dma_is_b === 1'b0) && ({1'b0,dma_lane} >= ARRAY_ROWS_COUNT)) ||
                  ((dma_is_b === 1'b1) && (b_owner[dma_bank*2 +: 2] !== OWNER_FILLING)) ||
                  ((dma_is_b === 1'b0) && (a_owner[dma_bank*2 +: 2] !== OWNER_FILLING)));
    compute_legal = !(((compute_bank !== 1'b0) && (compute_bank !== 1'b1)) ||
                      ((^compute_k) === 1'bx) ||
                      ({1'b0,compute_k} >= K_TILE_COUNT) ||
                      (a_owner[compute_bank*2 +: 2] !== OWNER_COMPUTE) ||
                      (b_owner[compute_bank*2 +: 2] !== OWNER_COMPUTE));
  end
  assign dma_fire = !rst && (dma_write_valid === 1'b1) && dma_legal;
  assign compute_fire = !rst && (compute_read_valid === 1'b1) && compute_legal;
  assign write_address = {dma_bank,dma_k};
  assign read_address = {compute_bank,compute_k};
  assign packed_write_address=PACK_ADDR_W'(write_address>>VLOG);
  assign packed_read_address=PACK_ADDR_W'(read_address>>VLOG);
  assign write_sub=SUB_W'(int'(dma_k)&(DMA_VECTOR_ELEMS-1));
  always_ff @(posedge clk)begin
    if(rst)read_sub_q<='0;
    else if(compute_fire)read_sub_q<=SUB_W'(int'(compute_k)&(DMA_VECTOR_ELEMS-1));
  end
  for(genvar e=0;e<DMA_VECTOR_ELEMS;e++)begin:g_norm
    assign normalized_dma_vector[e*16+:16]=dma_input_int16 ? dma_data[e*16+:16] :
      {{8{dma_data[e*16+7]}},dma_data[e*16+:8]};
    assign count_mask[e] = (dma_count > $bits(dma_count)'(e));
  end
  assign a_write_mask = (count_mask << write_sub) &
                        {DMA_VECTOR_ELEMS{dma_fire && !dma_is_b}};
  assign b_write_mask = (ARRAY_COLS'(count_mask) << dma_lane) &
                        {ARRAY_COLS{dma_fire && dma_is_b}};
  // One shared element-alignment network outside RAM; all RAM writes use
  // static element slices and one address, never a read-modify-write loop.
  assign a_write_data=normalized_dma_vector << (int'(write_sub)*16);
  assign b_write_data=B_DATA_W'(normalized_dma_vector) << {dma_lane,4'b0000};
  for(genvar r=0;r<ARRAY_ROWS;r++)begin:g_a_lane
    wire [DMA_VECTOR_ELEMS*16-1:0] packed_data;
    wire [DMA_VECTOR_ELEMS-1:0] lane_mask=a_write_mask & {DMA_VECTOR_ELEMS{dma_lane==LANE_W'(r)}};
    npu_spad_packed_ram #(.ADDR_W(PACK_ADDR_W),.PACK_ELEMS(DMA_VECTOR_ELEMS)) mem (
      .clk,.wr_mask(lane_mask),.wr_addr(packed_write_address),.wr_data(a_write_data),
      .rd_en(compute_fire),.rd_addr(packed_read_address),.rd_data(packed_data));
    assign a_vector[r*MAX_ELEM_W+:MAX_ELEM_W]=vector_zero_q ? '0 :
      packed_data[int'(read_sub_q)*16+:16];
  end
  for(genvar c=0;c<ARRAY_COLS;c++)begin:g_b_lane
    wire [15:0] data;
    npu_spad_lane_ram #(.ADDR_W(K_W+1)) mem (
      .clk,.wr_en(b_write_mask[c]),.wr_addr(write_address),.wr_data(b_write_data[c*16+:16]),
      .rd_en(compute_fire),.rd_addr(read_address),.rd_data(data));
    assign b_vector[c*MAX_ELEM_W+:MAX_ELEM_W]=vector_zero_q ? '0 : data;
  end

  // Keep all guards in elaborated generate blocks: SYNTHESIS sees the same
  // invalid configuration boundary as simulation rather than a test-only one.
  generate
    if(DMA_VECTOR_ELEMS<1 || DMA_VECTOR_ELEMS>8 ||
       ((DMA_VECTOR_ELEMS&(DMA_VECTOR_ELEMS-1))!=0) || DMA_VECTOR_ELEMS>K_TILE)begin:g_bad_dma_vector
      initial $fatal(1,"CP5_SPAD_VECTOR_PARAM_RED");
    end
    if (ARRAY_ROWS < 2 || ARRAY_ROWS > 16 ||
        ((ARRAY_ROWS & (ARRAY_ROWS - 1)) != 0)) begin : g_bad_array_rows
      initial $fatal(1, "npu_scratchpad: ARRAY_ROWS must be a power of two from 2 to 16");
    end
    if (ARRAY_COLS < 2 || ARRAY_COLS > 16 ||
        ((ARRAY_COLS & (ARRAY_COLS - 1)) != 0)) begin : g_bad_array_cols
      initial $fatal(1, "npu_scratchpad: ARRAY_COLS must be a power of two from 2 to 16");
    end
    if (K_TILE < 8 || K_TILE > 256 || ((K_TILE & (K_TILE - 1)) != 0)) begin : g_bad_k_tile
      initial $fatal(1, "npu_scratchpad: K_TILE must be a power of two from 8 to 256");
    end
    if (MAX_ELEM_W != 16) begin : g_bad_element_width
      initial $fatal(1, "npu_scratchpad: MAX_ELEM_W must be 16");
    end
  endgenerate

  function automatic logic legal_transition(
    input logic [1:0] current_state,
    input logic [1:0] requested_state
  );
    begin
      legal_transition = ((current_state === OWNER_EMPTY) && (requested_state === OWNER_FILLING)) ||
                         ((current_state === OWNER_FILLING) && (requested_state === OWNER_READY)) ||
                         ((current_state === OWNER_READY) && (requested_state === OWNER_COMPUTE)) ||
                         ((current_state === OWNER_COMPUTE) && (requested_state === OWNER_EMPTY));
    end
  endfunction

  // Owner, DMA, and compute requests are independent action classes.  All
  // authorizations inspect pre-edge owners; nonblocking owner updates preserve
  // that rule.  Malformed actions aggregate to one error pulse but never
  // suppress independent legal actions.
  always_ff @(posedge clk) begin
    if (rst) begin
      a_owner <= '0;
      b_owner <= '0;
      vector_zero_q <= 1'b1;
      compute_read_data_valid <= 1'b0;
      protocol_error <= 1'b0;
    end else begin
      protocol_error <= 1'b0;
      compute_read_data_valid <= 1'b0;

      if (owner_req_valid === 1'b1) begin
        if (((owner_req_is_b !== 1'b0) && (owner_req_is_b !== 1'b1)) ||
            ((owner_req_bank !== 1'b0) && (owner_req_bank !== 1'b1)) ||
            !((owner_req_state === OWNER_EMPTY) || (owner_req_state === OWNER_FILLING) ||
              (owner_req_state === OWNER_READY) || (owner_req_state === OWNER_COMPUTE))) begin
          protocol_error <= 1'b1;
        end else if (owner_req_is_b === 1'b1) begin
          if (legal_transition(b_owner[owner_req_bank*2 +: 2], owner_req_state))
            b_owner[owner_req_bank*2 +: 2] <= owner_req_state;
          else
            protocol_error <= 1'b1;
        end else begin
          if (legal_transition(a_owner[owner_req_bank*2 +: 2], owner_req_state))
            a_owner[owner_req_bank*2 +: 2] <= owner_req_state;
          else
            protocol_error <= 1'b1;
        end
      end

      // The RAM leaf acts on these same pre-edge authorizations. A malformed
      // action must not cancel an independent legal action in the same edge.
      if ((dma_write_valid === 1'b1) && !dma_legal)
        protocol_error <= 1'b1;
      if (compute_read_valid === 1'b1) begin
        if (!compute_legal) begin
          protocol_error <= 1'b1;
          vector_zero_q <= 1'b1;
        end else begin
          vector_zero_q <= 1'b0;
          compute_read_data_valid <= 1'b1;
        end
      end
    end
  end
endmodule
