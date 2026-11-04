module npu_postprocess #(
  parameter int ACC_W=48
) (
  input  logic                    clk,
  input  logic                    rst,
  input  logic                    in_valid,
  output logic                    in_ready,
  input  logic signed [ACC_W-1:0] in_value,
  input  logic [1:0]              output_fmt,
  input  logic [1:0]              activation,
  input  logic                    rounding,
  input  logic [5:0]              shift,
  input  logic signed [31:0]      clamp_min,
  input  logic signed [31:0]      clamp_max,
  output logic                    out_valid,
  input  logic                    out_ready,
  output logic signed [31:0]      out_value,
  output logic [2:0]              out_bytes
);
  localparam logic signed [ACC_W-1:0] INT8_MIN  = {{(ACC_W-8){1'b1}}, 8'h80};
  localparam logic signed [ACC_W-1:0] INT8_MAX  = {{(ACC_W-8){1'b0}}, 8'h7f};
  localparam logic signed [ACC_W-1:0] INT16_MIN = {{(ACC_W-16){1'b1}}, 16'h8000};
  localparam logic signed [ACC_W-1:0] INT16_MAX = {{(ACC_W-16){1'b0}}, 16'h7fff};
  localparam logic signed [ACC_W-1:0] INT32_MIN = {{(ACC_W-32){1'b1}}, 32'h8000_0000};
  localparam logic signed [ACC_W-1:0] INT32_MAX = {{(ACC_W-32){1'b0}}, 32'h7fff_ffff};

  logic s1_valid, s2_valid, s3_valid;
  logic s1_ready, s2_ready, s3_ready;
  logic signed [ACC_W-1:0] s1_value, s2_value;
  logic [1:0] s1_output_fmt, s1_activation, s2_output_fmt;
  logic signed [31:0] s1_clamp_min, s1_clamp_max;
  logic signed [31:0] s3_value;
  logic [2:0] s3_bytes;
  logic output_fmt_valid, activation_valid, rounding_valid, shift_valid, clamp_valid, config_valid;

  // This exact-bit decode is synthesizable (hardware inputs are 0/1) and
  // deliberately fail-closed in four-state simulation at the stream boundary.
  function automatic logic known_word32(input logic [31:0] value);
    begin
      known_word32 = 1'b1;
      for (int unsigned bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
        case (value[bit_index])
          1'b0, 1'b1: ;
          default: known_word32 = 1'b0;
        endcase
      end
    end
  endfunction

  function automatic logic signed [ACC_W-1:0] round_shift(
    input logic signed [ACC_W-1:0] value,
    input logic round_en,
    input logic [5:0] shift_amount
  );
    logic signed [ACC_W:0] value_ext;
    logic signed [ACC_W:0] bias;
    logic signed [ACC_W:0] unit_value;
    begin
      value_ext = {value[ACC_W-1], value};
      bias = '0;
      unit_value = {{ACC_W{1'b0}}, 1'b1};
      if (round_en && (shift_amount != 6'd0)) begin
        bias = unit_value <<< (shift_amount - 6'd1);
        if (value < 0)
          bias = bias - unit_value;
      end
      round_shift = ACC_W'((value_ext + bias) >>> shift_amount);
    end
  endfunction

  function automatic logic signed [ACC_W-1:0] apply_activation(
    input logic signed [ACC_W-1:0] value,
    input logic [1:0] activation_mode,
    input logic signed [31:0] min_value,
    input logic signed [31:0] max_value
  );
    logic signed [ACC_W-1:0] min_ext;
    logic signed [ACC_W-1:0] max_ext;
    begin
      min_ext = {{(ACC_W-32){min_value[31]}}, min_value};
      max_ext = {{(ACC_W-32){max_value[31]}}, max_value};
      case (activation_mode)
        2'd1: apply_activation = (value < 0) ? '0 : value;
        2'd2: apply_activation = (value < min_ext) ? min_ext :
                                  ((value > max_ext) ? max_ext : value);
        default: apply_activation = value;
      endcase
    end
  endfunction

  function automatic logic signed [31:0] saturate_value(
    input logic signed [ACC_W-1:0] value,
    input logic [1:0] format
  );
    begin
      case (format)
        2'd0: begin
          if (value > INT8_MAX) saturate_value = 32'sd127;
          else if (value < INT8_MIN) saturate_value = -32'sd128;
          else saturate_value = {{24{value[7]}}, value[7:0]};
        end
        2'd1: begin
          if (value > INT16_MAX) saturate_value = 32'sd32767;
          else if (value < INT16_MIN) saturate_value = -32'sd32768;
          else saturate_value = {{16{value[15]}}, value[15:0]};
        end
        2'd2: begin
          if (value > INT32_MAX) saturate_value = 32'sh7fff_ffff;
          else if (value < INT32_MIN) saturate_value = -32'sh8000_0000;
          else saturate_value = value[31:0];
        end
        default: saturate_value = '0;
      endcase
    end
  endfunction

  function automatic logic [2:0] format_bytes(input logic [1:0] format);
    begin
      case (format)
        2'd0: format_bytes = 3'd1;
        2'd1: format_bytes = 3'd2;
        2'd2: format_bytes = 3'd4;
        default: format_bytes = 3'd0;
      endcase
    end
  endfunction

  always @* begin
    output_fmt_valid = 1'b0;
    activation_valid = 1'b0;
    rounding_valid = 1'b0;
    shift_valid = 1'b0;
    case (output_fmt)
      2'd0, 2'd1, 2'd2: output_fmt_valid = 1'b1;
      default: output_fmt_valid = 1'b0;
    endcase
    case (activation)
      2'd0, 2'd1, 2'd2: activation_valid = 1'b1;
      default: activation_valid = 1'b0;
    endcase
    case (rounding)
      1'b0, 1'b1: rounding_valid = 1'b1;
      default: rounding_valid = 1'b0;
    endcase
    // This is equivalent to the old per-value case-equality loop for every
    // supported ACC_W (32..64), including X/Z fail-closed simulation.  A
    // range comparator avoids a wide OR of 48 equality terms on the 200 MHz
    // shift/config-valid path.
    shift_valid = ((^shift) !== 1'bx) && ({1'b0, shift} < 7'(ACC_W));
    clamp_valid = 1'b1;
    case (activation)
      2'd2: begin
        if (!known_word32(clamp_min) || !known_word32(clamp_max))
          clamp_valid = 1'b0;
        else if ($signed(clamp_min) > $signed(clamp_max))
          clamp_valid = 1'b0;
      end
      default: clamp_valid = 1'b1;
    endcase
    config_valid = output_fmt_valid && activation_valid && rounding_valid && shift_valid && clamp_valid;
  end

  assign s3_ready = !s3_valid || out_ready;
  assign s2_ready = !s2_valid || s3_ready;
  assign s1_ready = !s1_valid || s2_ready;
  // Invalid command encodings are rejected by the scheduler; this leaf also
  // fail-closes them so an invalid descriptor cannot be silently transformed.
  assign in_ready = !rst && config_valid && s1_ready;
  assign out_valid = s3_valid;
  assign out_value = s3_value;
  assign out_bytes = s3_bytes;

  initial begin
    if (ACC_W < 32 || ACC_W > 64)
      $fatal(1, "npu_postprocess: ACC_W must be in [32,64]");
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      s1_valid <= 1'b0;
      s2_valid <= 1'b0;
      s3_valid <= 1'b0;
      s1_value <= '0;
      s2_value <= '0;
      s1_output_fmt <= '0;
      s2_output_fmt <= '0;
      s1_activation <= '0;
      s1_clamp_min <= '0;
      s1_clamp_max <= '0;
      s3_value <= '0;
      s3_bytes <= '0;
    end else begin
      if (s3_ready) begin
        s3_valid <= s2_valid;
        if (s2_valid) begin
          s3_value <= saturate_value(s2_value, s2_output_fmt);
          s3_bytes <= format_bytes(s2_output_fmt);
        end
      end
      if (s2_ready) begin
        s2_valid <= s1_valid;
        if (s1_valid) begin
          s2_value <= apply_activation(s1_value, s1_activation, s1_clamp_min, s1_clamp_max);
          s2_output_fmt <= s1_output_fmt;
        end
      end
      if (s1_ready) begin
        s1_valid <= in_valid && config_valid;
        if (in_valid && config_valid) begin
          s1_value <= round_shift(in_value, rounding, shift);
          s1_output_fmt <= output_fmt;
          s1_activation <= activation;
          s1_clamp_min <= clamp_min;
          s1_clamp_max <= clamp_max;
        end
      end
    end
  end
endmodule
