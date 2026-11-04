// Experimental A payload layout only. Each A lane keeps the legacy physical
// 128-bit word and ping/pong bank boundary. INT8 packs 16 bytes per word;
// INT16 packs 8 halfwords. B retains the original 16-bit lane organization.
// Data is written only by real DMA response retirement; no payload clear/init.
module npu_scratchpad_int8packed16 #(
  parameter int ARRAY_ROWS=16, ARRAY_COLS=8, K_TILE=64,
  parameter int MAX_ELEM_W=16, DMA_VECTOR_ELEMS=16
)(
  input logic clk,rst,
  input logic owner_req_valid,owner_req_is_b,owner_req_bank,
  input logic [1:0] owner_req_state,
  input logic dma_write_valid,dma_is_b,dma_bank,
  input logic [((ARRAY_ROWS>ARRAY_COLS)?((ARRAY_ROWS>1)?$clog2(ARRAY_ROWS):1):((ARRAY_COLS>1)?$clog2(ARRAY_COLS):1))-1:0] dma_lane,
  input logic [((K_TILE>1)?$clog2(K_TILE):1)-1:0] dma_k,
  input logic dma_input_int16,
  input logic signed [DMA_VECTOR_ELEMS*16-1:0] dma_data,
  input logic [((DMA_VECTOR_ELEMS>1)?$clog2(DMA_VECTOR_ELEMS+1):1)-1:0] dma_count,
  input logic compute_read_valid,compute_bank,
  input logic [((K_TILE>1)?$clog2(K_TILE):1)-1:0] compute_k,
  output logic [ARRAY_ROWS*MAX_ELEM_W-1:0] a_vector,
  output logic [ARRAY_COLS*MAX_ELEM_W-1:0] b_vector,
  output logic compute_read_data_valid,
  output logic [3:0] a_owner,b_owner,
  output logic protocol_error
);
  localparam logic [1:0] OWNER_EMPTY=0, OWNER_FILLING=1,
      OWNER_READY=2, OWNER_COMPUTE=3;
  localparam int LANE_W=$clog2((ARRAY_ROWS>ARRAY_COLS)?ARRAY_ROWS:ARRAY_COLS);
  localparam int K_W=$clog2(K_TILE);
  localparam int A_ADDR_W=K_W-2; // same depth as legacy V8, never mode dependent
  localparam int A_BANK_WORD_W=K_W-3;
  logic [1:0] a_mode_valid,b_mode_valid,a_mode_int16,b_mode_int16;
  logic dma_legal,compute_legal,dma_fire,compute_fire,owner_legal;
  logic vector_zero_q,read_mode_q;
  logic [3:0] write_byte_offset,read_byte_offset,read_byte_offset_q;
  logic [4:0] a_byte_count;
  logic [15:0] a_count_mask,a_write_mask;
  logic [127:0] a_unshifted_bytes,a_write_data;
  logic [A_BANK_WORD_W-1:0] a_write_word,a_read_word;
  logic [A_ADDR_W-1:0] a_write_address,a_read_address;
  logic [ARRAY_COLS-1:0] b_count_mask,b_write_mask;
  logic [ARRAY_COLS*16-1:0] b_unshifted_data,b_write_data;
  logic [K_W:0] b_write_address,b_read_address;

  function automatic logic legal_transition(input logic [1:0] current_state,
                                              input logic [1:0] requested_state);
    legal_transition=((current_state===OWNER_EMPTY)&&(requested_state===OWNER_FILLING)) ||
      ((current_state===OWNER_FILLING)&&(requested_state===OWNER_READY)) ||
      ((current_state===OWNER_READY)&&(requested_state===OWNER_COMPUTE)) ||
      ((current_state===OWNER_COMPUTE)&&(requested_state===OWNER_EMPTY));
  endfunction

  assign write_byte_offset=dma_input_int16 ? {dma_k[2:0],1'b0} : dma_k[3:0];
  assign a_byte_count=dma_input_int16 ? (5'(dma_count)<<1) : 5'(dma_count);
  // Reserve K_TILE/8 physical words for each bank even in INT8 mode. This
  // keeps simultaneous INT8 and INT16 banks disjoint and supports mode reuse.
  assign a_write_word=A_BANK_WORD_W'(dma_k >> (dma_input_int16 ? 3 : 4));
  assign a_read_word=A_BANK_WORD_W'(compute_k >> (a_mode_int16[compute_bank] ? 3 : 4));
  assign a_write_address={dma_bank,a_write_word};
  assign a_read_address={compute_bank,a_read_word};
  assign read_byte_offset=a_mode_int16[compute_bank] ? {compute_k[2:0],1'b0} : compute_k[3:0];
  assign b_write_address={dma_bank,dma_k};
  assign b_read_address={compute_bank,compute_k};

  always_comb begin
    owner_legal=!(((owner_req_is_b!==1'b0)&&(owner_req_is_b!==1'b1)) ||
      ((owner_req_bank!==1'b0)&&(owner_req_bank!==1'b1))) &&
      legal_transition(owner_req_is_b ? b_owner[owner_req_bank*2+:2] :
                                         a_owner[owner_req_bank*2+:2],owner_req_state);
    dma_legal=!(((dma_is_b!==1'b0)&&(dma_is_b!==1'b1)) ||
      ((dma_bank!==1'b0)&&(dma_bank!==1'b1)) ||
      ((dma_input_int16!==1'b0)&&(dma_input_int16!==1'b1)) ||
      ((^dma_lane)===1'bx) || ((^dma_k)===1'bx) || ((^dma_count)===1'bx) ||
      (dma_count==0) || (int'(dma_count)>16) || (int'(dma_k)>=K_TILE) ||
      (!dma_is_b && ((int'(dma_lane)>=ARRAY_ROWS) ||
        (int'(dma_k)+int'(dma_count)>K_TILE) ||
        (dma_input_int16 && (int'(dma_count)>8)) ||
        (int'(write_byte_offset)+int'(a_byte_count)>16) ||
        (a_owner[dma_bank*2+:2]!==OWNER_FILLING) ||
        (a_mode_valid[dma_bank] && (a_mode_int16[dma_bank]!==dma_input_int16)))) ||
      (dma_is_b && ((int'(dma_lane)>=ARRAY_COLS) ||
        (int'(dma_lane)+int'(dma_count)>ARRAY_COLS) ||
        (b_owner[dma_bank*2+:2]!==OWNER_FILLING) ||
        (b_mode_valid[dma_bank] && (b_mode_int16[dma_bank]!==dma_input_int16)))));
    compute_legal=!(((compute_bank!==1'b0)&&(compute_bank!==1'b1)) ||
      ((^compute_k)===1'bx) || (int'(compute_k)>=K_TILE) ||
      (a_owner[compute_bank*2+:2]!==OWNER_COMPUTE) ||
      (b_owner[compute_bank*2+:2]!==OWNER_COMPUTE) ||
      (a_mode_valid[compute_bank]!==1'b1) ||
      (b_mode_valid[compute_bank]!==1'b1) ||
      (a_mode_int16[compute_bank]!==b_mode_int16[compute_bank]));
  end
  assign dma_fire=!rst && (dma_write_valid===1'b1) && dma_legal;
  assign compute_fire=!rst && (compute_read_valid===1'b1) && compute_legal;

  for(genvar e=0;e<16;e=e+1)begin:g_a_bytes
    assign a_unshifted_bytes[e*8+:8]=dma_input_int16 ?
      dma_data[(e/2)*16+(e%2)*8+:8] : dma_data[e*16+:8];
    assign a_count_mask[e]=(a_byte_count>5'(e));
  end
  assign a_write_data=a_unshifted_bytes << {write_byte_offset,3'b000};
  assign a_write_mask=(a_count_mask << write_byte_offset) & {16{dma_fire&&!dma_is_b}};
  for(genvar e=0;e<ARRAY_COLS;e=e+1)begin:g_b_normalize
    assign b_unshifted_data[e*16+:16]=dma_input_int16 ? dma_data[e*16+:16] :
      {{8{dma_data[e*16+7]}},dma_data[e*16+:8]};
    assign b_count_mask[e]=(dma_count>$bits(dma_count)'(e));
  end
  assign b_write_data=b_unshifted_data << {dma_lane,4'b0000};
  assign b_write_mask=(b_count_mask << dma_lane) & {ARRAY_COLS{dma_fire&&dma_is_b}};

  // Bound each A read-enable branch to at most four lanes (64 payload CE
  // pins), with four combinational drivers at 16 rows. No clock or cycle
  // changes; only these measured control buffers are preserved.
  localparam int A_READ_GROUPS=(ARRAY_ROWS+3)/4;
  (* syn_keep=1 *) wire [A_READ_GROUPS-1:0] group_read_enable;
  for(genvar g=0;g<A_READ_GROUPS;g=g+1)begin:g_a_read_group
    (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
      local_read_driver(.I0(compute_fire),.Z(group_read_enable[g]));
  end
  for(genvar r=0;r<ARRAY_ROWS;r=r+1)begin:g_a_lane
    wire [15:0] held_data;
    wire [15:0] lane_mask=a_write_mask & {16{dma_lane==LANE_W'(r)}};
    npu_spad_byte_read16_ram #(.ADDR_W(A_ADDR_W)) mem(
      .clk,.wr_mask(lane_mask),.wr_addr(a_write_address),.wr_data(a_write_data),
      .rd_en(group_read_enable[r/4]),.rd_addr(a_read_address),
      .rd_byte_offset(read_byte_offset),.rd_int16(a_mode_int16[compute_bank]),
      .rd_data(held_data));
    assign a_vector[r*16+:16]=vector_zero_q ? 16'd0 : held_data;
  end
  for(genvar c=0;c<ARRAY_COLS;c=c+1)begin:g_b_lane
    wire [15:0] data;
    npu_spad_lane_ram #(.ADDR_W(K_W+1)) mem(
      .clk,.wr_en(b_write_mask[c]),.wr_addr(b_write_address),.wr_data(b_write_data[c*16+:16]),
      .rd_en(compute_fire),.rd_addr(b_read_address),.rd_data(data));
    assign b_vector[c*16+:16]=vector_zero_q ? 16'd0 : data;
  end

  always_ff @(posedge clk)begin
    if(rst)begin
      a_owner<='0;b_owner<='0;
      a_mode_valid<='0;b_mode_valid<='0;a_mode_int16<='0;b_mode_int16<='0;
      vector_zero_q<=1'b1;read_mode_q<=1'b0;read_byte_offset_q<='0;
      compute_read_data_valid<=1'b0;protocol_error<=1'b0;
    end else begin
      compute_read_data_valid<=1'b0;protocol_error<=1'b0;
      // All action classes authorize against pre-edge owners. A legal write
      // may coincide with FILLING->READY; an EMPTY->FILLING edge cannot write.
      if(owner_req_valid===1'b1)begin
        if(!owner_legal)protocol_error<=1'b1;
        else if(owner_req_is_b)begin
          b_owner[owner_req_bank*2+:2]<=owner_req_state;
          if((owner_req_state==OWNER_EMPTY)||(owner_req_state==OWNER_FILLING))
            b_mode_valid[owner_req_bank]<=1'b0;
        end else begin
          a_owner[owner_req_bank*2+:2]<=owner_req_state;
          if((owner_req_state==OWNER_EMPTY)||(owner_req_state==OWNER_FILLING))
            a_mode_valid[owner_req_bank]<=1'b0;
        end
      end
      if(dma_write_valid===1'b1)begin
        if(!dma_legal)protocol_error<=1'b1;
        else if(dma_is_b)begin
          b_mode_valid[dma_bank]<=1'b1;b_mode_int16[dma_bank]<=dma_input_int16;
        end else begin
          a_mode_valid[dma_bank]<=1'b1;a_mode_int16[dma_bank]<=dma_input_int16;
        end
      end
      if(compute_read_valid===1'b1)begin
        if(!compute_legal)begin protocol_error<=1'b1;vector_zero_q<=1'b1;end
        else begin
          vector_zero_q<=1'b0;compute_read_data_valid<=1'b1;
          read_mode_q<=a_mode_int16[compute_bank];read_byte_offset_q<=read_byte_offset;
        end
      end
    end
  end
  initial begin
    if(DMA_VECTOR_ELEMS!=16 || MAX_ELEM_W!=16 || K_TILE<16 || K_TILE>256 ||
       (K_TILE&(K_TILE-1))!=0 || ARRAY_ROWS<2 || ARRAY_ROWS>16 ||
       (ARRAY_ROWS&(ARRAY_ROWS-1))!=0 || ARRAY_COLS<2 || ARRAY_COLS>16 ||
       (ARRAY_COLS&(ARRAY_COLS-1))!=0)
      $fatal(1,"A_INT8PACKED16_CONFIGURATION_RED");
  end
endmodule
