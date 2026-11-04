// 架构导读：npu_postprocess。
// 处理累加结果的输出格式和写回字段，保留任务有效状态。
module npu_postprocess #(
  // 静态配置：parameter int ACC_W=48。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int ACC_W=48
) (
  // 接口声明：input logic clk。
  // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
  input  logic                    clk,
  // 接口声明：input logic rst。
  // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
  input  logic                    rst,
  // 接口声明：input logic in_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  input  logic                    in_valid,
  // 接口声明：output logic in_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  output logic                    in_ready,
  // 接口声明：input logic signed [ACC_W-1:0] in_value。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic signed [ACC_W-1:0] in_value,
  // 接口声明：input logic [1:0] output_fmt。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic [1:0]              output_fmt,
  // 接口声明：input logic [1:0] activation。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic [1:0]              activation,
  // 接口声明：input logic rounding。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic                    rounding,
  // 接口声明：input logic [5:0] shift。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic [5:0]              shift,
  // 接口声明：input logic signed [31:0] clamp_min。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic signed [31:0]      clamp_min,
  // 接口声明：input logic signed [31:0] clamp_max。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic signed [31:0]      clamp_max,
  // 接口声明：output logic out_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  output logic                    out_valid,
  // 接口声明：input logic out_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  input  logic                    out_ready,
  // 接口声明：output logic signed [31:0] out_value。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic signed [31:0]      out_value,
  // 接口声明：output logic [2:0] out_bytes。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic [2:0]              out_bytes
);
  // 静态配置：localparam logic signed [ACC_W-1:0] INT8_MIN = {{(ACC_W-8){1'b1}}, 8'h80}。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic signed [ACC_W-1:0] INT8_MIN  = {{(ACC_W-8){1'b1}}, 8'h80};
  // 静态配置：localparam logic signed [ACC_W-1:0] INT8_MAX = {{(ACC_W-8){1'b0}}, 8'h7f}。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic signed [ACC_W-1:0] INT8_MAX  = {{(ACC_W-8){1'b0}}, 8'h7f};
  // 静态配置：localparam logic signed [ACC_W-1:0] INT16_MIN = {{(ACC_W-16){1'b1}}, 16'h8000}。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic signed [ACC_W-1:0] INT16_MIN = {{(ACC_W-16){1'b1}}, 16'h8000};
  // 静态配置：localparam logic signed [ACC_W-1:0] INT16_MAX = {{(ACC_W-16){1'b0}}, 16'h7fff}。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic signed [ACC_W-1:0] INT16_MAX = {{(ACC_W-16){1'b0}}, 16'h7fff};
  // 静态配置：localparam logic signed [ACC_W-1:0] INT32_MIN = {{(ACC_W-32){1'b1}}, 32'h8000_0000}。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic signed [ACC_W-1:0] INT32_MIN = {{(ACC_W-32){1'b1}}, 32'h8000_0000};
  // 静态配置：localparam logic signed [ACC_W-1:0] INT32_MAX = {{(ACC_W-32){1'b0}}, 32'h7fff_ffff}。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
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
        // 按 value[bit_index] 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
        case (value[bit_index])
          1'b0, 1'b1: ;
          default: known_word32 = 1'b0;
        endcase
      end
    end
  endfunction

  // 局部运算/辅助过程：function automatic logic signed [ACC_W-1:0] round_shift(。
  // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
  function automatic logic signed [ACC_W-1:0] round_shift(
    // 接口声明：input logic signed [ACC_W-1:0] value。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic signed [ACC_W-1:0] value,
    // 接口声明：input logic round_en。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic round_en,
    // 接口声明：input logic [5:0] shift_amount。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
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

  // 局部运算/辅助过程：function automatic logic signed [ACC_W-1:0] apply_activation(。
  // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
  function automatic logic signed [ACC_W-1:0] apply_activation(
    // 接口声明：input logic signed [ACC_W-1:0] value。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic signed [ACC_W-1:0] value,
    // 接口声明：input logic [1:0] activation_mode。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [1:0] activation_mode,
    // 接口声明：input logic signed [31:0] min_value。
    input logic signed [31:0] min_value,
    input logic signed [31:0] max_value
  );
    logic signed [ACC_W-1:0] min_ext;
    logic signed [ACC_W-1:0] max_ext;
    begin
      min_ext = {{(ACC_W-32){min_value[31]}}, min_value};
      max_ext = {{(ACC_W-32){max_value[31]}}, max_value};
      // 按 activation_mode 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
      case (activation_mode)
        2'd1: apply_activation = (value < 0) ? '0 : value;
        2'd2: apply_activation = (value < min_ext) ? min_ext :
                                  ((value > max_ext) ? max_ext : value);
        default: apply_activation = value;
      endcase
    end
  endfunction

  // 局部运算/辅助过程：function automatic logic signed [31:0] saturate_value(。
  // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
  function automatic logic signed [31:0] saturate_value(
    input logic signed [ACC_W-1:0] value,
    input logic [1:0] format
  );
    begin
      // 按 format 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
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

  // 局部运算/辅助过程：function automatic logic [2:0] format_bytes(input logic [1:0] format);。
  // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
  function automatic logic [2:0] format_bytes(input logic [1:0] format);
    begin
      // 按 format 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
      case (format)
        2'd0: format_bytes = 3'd1;
        2'd1: format_bytes = 3'd2;
        2'd2: format_bytes = 3'd4;
        default: format_bytes = 3'd0;
      endcase
    end
  endfunction

  // 过程边界：always @* begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always @* begin
    output_fmt_valid = 1'b0;
    activation_valid = 1'b0;
    rounding_valid = 1'b0;
    shift_valid = 1'b0;
    // 按 output_fmt 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
    case (output_fmt)
      2'd0, 2'd1, 2'd2: output_fmt_valid = 1'b1;
      default: output_fmt_valid = 1'b0;
    endcase
    // 按 activation 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
    case (activation)
      2'd0, 2'd1, 2'd2: activation_valid = 1'b1;
      default: activation_valid = 1'b0;
    endcase
    // 按 rounding 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
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
    // 按 activation 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
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

  // 过程边界：always_ff @(posedge clk) begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) begin
    // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
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
