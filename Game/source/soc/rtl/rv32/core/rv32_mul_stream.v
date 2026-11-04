// [ARCH] 低位乘法流保存操作数与原始 tag、sequence、PC。
// [ARCH] 结果必须连同原始身份返回，不能用响应时的新指令补填身份。
// [ARCH] 输入和输出背压分别约束占用，尚未消费的结果不能被覆盖。
// [ARCH] 重定向后的无效结果不能误交给复用相同环形 tag 的新指令。
// [ARCH] DSP 数据载荷本身不构成指令有效凭据。
// Original RV32 R47 low-word multiplier; S6 ancestry retained.
// See verification/MUL_EARLY_RESPONSE_CONTRACT.md. No external CPU input.
// One accepted request registers three16x16 partial products. Its low word
// is then available from those registers without another mandatory edge.
// A separate result buffer preserves two credits and a stable held response.
`default_nettype none
module rv32_mul_stream #(
 parameter TOKEN_WIDTH=4,
 // Set only when the producer already disallows full-queue turnover.
 // The RV32 core gates requests with registered occupancy != 2.
 parameter REGISTERED_INPUT_CREDIT=0
)(
 // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
 input wire clk,reset,cancel,request_valid,
 // [ARCH] request_ready（请求所有权）：标记操作数或下游接纳条件已满足；还需检查相应有效身份。
 output wire request_ready,
 // [ARCH] left：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 low_product, cross_left_low, cross_right_low 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input wire [31:0] left,right,
 // [ARCH] request_token：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 partial_token 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input wire [TOKEN_WIDTH-1:0] request_token,
 // [ARCH] response_valid（响应所有权）：标记本槽/载荷是否属于一个有效所有者；数据 RAM 的残留值本身不能代替有效位。
 output wire response_valid,response_present,
 // [ARCH] response_ready（响应所有权）：标记操作数或下游接纳条件已满足；还需检查相应有效身份。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 buffer_space, move_to_buffer 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input wire response_ready,
 output wire [31:0] result,
 output wire [TOKEN_WIDTH-1:0] response_token,
 output wire [1:0] occupancy
);
 // [ARCH] partial_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 partial_space, registered_space, move_to_buffer, response_present 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 reg partial_valid,buffer_valid;
 reg [31:0] low_product,buffer_result;
 // [ARCH] cross_left_low：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 middle_column 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 reg [15:0] cross_left_low,cross_right_low;
 reg [TOKEN_WIDTH-1:0] partial_token,buffer_token;
 wire active=!reset&&!cancel;
 wire buffer_space=!buffer_valid||response_ready;
 wire partial_space=!partial_valid||buffer_space;
 // The generic interface retains full + consume + accept turnover. In the
 // core mode, admission uses only registered local occupancy and never
 // depends on response_ready, decode, reset, cancel or recovery.
 wire registered_space=!partial_valid||!buffer_valid;
 wire input_space=REGISTERED_INPUT_CREDIT?registered_space:partial_space;
 // [ARCH] input_accept：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 partial_valid, partial_token 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire input_accept=request_valid&&input_space;
 wire [15:0] middle_column=low_product[31:16]+cross_left_low+cross_right_low;
 wire [31:0] partial_result={middle_column,low_product[15:0]};
 // If the buffer is empty and the consumer is ready, it consumes the
 // partial-stage result directly. Otherwise save that same tuple in the
 // buffer before replacing the partial slot. Buffer contents always precede
 // partial contents; response selection depends only on registered validity.
 wire move_to_buffer=partial_valid&&(buffer_valid||!response_ready);
 assign request_ready=active&&input_space;
 assign response_present=buffer_valid||partial_valid;
 assign response_valid=active&&response_present;
 assign result=buffer_valid?buffer_result:partial_result;
 assign response_token=buffer_valid?buffer_token:partial_token;
 assign occupancy={1'b0,partial_valid}+{1'b0,buffer_valid};
 // Sample payload independently of ownership. When an unbuffered partial
 // must move to the buffer, its old products are copied before this edge's
 // new products become visible. When both slots are held, sampling stops.
 // Data reset is unnecessary: validity still resets/cancels synchronously.
 always @(posedge clk)begin
  if(input_space)begin
   low_product<=left[15:0]*right[15:0];
   cross_left_low<=left[31:16]*right[15:0];
   cross_right_low<=left[15:0]*right[31:16];
  end
 end
 always @(posedge clk)begin
  if(reset)begin
   partial_valid<=0;buffer_valid<=0;partial_token<=0;
   buffer_result<=0;buffer_token<=0;
  end else if(cancel)begin partial_valid<=0;buffer_valid<=0;end
  else begin
   if(buffer_space)begin
    buffer_valid<=move_to_buffer;
    if(move_to_buffer)begin buffer_result<=partial_result;buffer_token<=partial_token;end
   end
   if(partial_space)begin
    partial_valid<=input_accept;
    if(input_accept)partial_token<=request_token;
   end
  end
 end
endmodule
`default_nettype wire
