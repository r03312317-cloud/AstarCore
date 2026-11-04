// Original RV32 R47 low-word multiplier; S6 ancestry retained.
// See verification/MUL_EARLY_RESPONSE_CONTRACT.md. No external CPU input.
// One accepted request registers three16x16 partial products. Its low word
// is then available from those registers without another mandatory edge.
// A separate result buffer preserves two credits and a stable held response.
`default_nettype none
// 独立低位乘法流水通过请求和响应握手处理 MUL 的低 32 位结果。
// 运算 payload 与身份 metadata 同行推进，使积能回到正确 ROB 所有者。
// 背压时保留未消费结果，occupancy 反映实际占有的流水位置。
// 本模块只覆盖低位乘法，其他乘高位及除余操作由 arithmetic 单元处理。
// 流水被占用不等于对应指令已提交，恢复时仍由外层检查所有者存活。
module rv32_mul_stream #(
 parameter TOKEN_WIDTH=4,
 // Set only when the producer already disallows full-queue turnover.
 // The RV32 core gates requests with registered occupancy != 2.
 parameter REGISTERED_INPUT_CREDIT=0
)(
 // request_valid 属于请求提议，保存有效资格，标识该项是否属于当前仍可使用的事务。
 // 接收事件由对应 valid 与 ready 同时成立决定。
 input wire clk,reset,cancel,request_valid,
 // request_ready 属于请求提议，保存接收或操作数就绪资格，须结合对应的有效位使用。
 output wire request_ready,
 // left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
 input wire [31:0] left,right,
 input wire [TOKEN_WIDTH-1:0] request_token,
 output wire response_valid,response_present,
 input wire response_ready,
 output wire [31:0] result,
 output wire [TOKEN_WIDTH-1:0] response_token,
 output wire [1:0] occupancy
);
 // partial_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 reg partial_valid,buffer_valid;
 reg [31:0] low_product,buffer_result;
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
