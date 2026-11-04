// Original RV32 R47 low-word multiplier; S6 ancestry retained.
// See verification/MUL_EARLY_RESPONSE_CONTRACT.md. No external CPU input.
// One accepted request registers three16x16 partial products. Its low word
// is then available from those registers without another mandatory edge.
// A separate result buffer preserves two credits and a stable held response.
`default_nettype none
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 低 32 位 MUL 的两信用计算通路，供 CoreMark 中常见整数乘法使用。
// 接收边界保存三个 16 乘 16 部分积，仅保留低字需要的交叉项。
// 部分积寄存后，低字可组合形成并直接交给消费者，无强制再等一拍的结果寄存。
// 另有一个结果缓冲，已有缓冲结果先于新部分积结果响应，保证顺序。
// request_token 随请求携带 ROB 所有者信息，不参与数值乘法。
// 本板使用 REGISTERED_INPUT_CREDIT，接收只看本地寄存占用，不沿 response_ready
// 反传长路径。
// 输入满且消费的同边界接收能力取决于参数，不能假定两种模式接口行为完全相同。
// reset/cancel 丢弃有效所有权，未消费结果在无取消时必须保持稳定。
// 接口契约与阅读示例
// 部分积槽和结果缓冲各占一个信用，occupancy只由两个有效位相加。
// 缓冲非空时必须先响应旧缓冲，不允许新部分积结果越过它。
// 缓冲空且消费者ready时，可直接消费部分积计算结果，避免无条件再寄存一拍。
// 缓冲空但消费者不ready时，把当前部分积与token一起移动到缓冲。
// 移动旧部分积和采样新部分积发生于同边界时，
// 非阻塞赋值保证复制的是旧所有者结果。
// request_token与数值结果必须一起移动，不能仅保存乘积而丢掉ROB目标。
// 本板注册信用模式占满两个槽时不靠当拍response_ready来开放输入，减少长反馈。
// 即使该模式某拍拒绝新请求，也不能覆盖尚未消费的部分积所有者。
// reset或cancel清除两个valid；没有valid的数据位不要求全部清零。
// CoreMark矩阵的低位MUL可以受益于本模块，但双发射仍受访存及依赖限制。
module rv32_mul_stream #(
    // 参数 TOKEN_WIDTH：随运算请求传递的所有者标签宽度；token不参与数值计算。
 parameter TOKEN_WIDTH=4,
 // Set only when the producer already disallows full-queue turnover.
 // The RV32 core gates requests with registered occupancy != 2.
    // 参数 REGISTERED_INPUT_CREDIT：MUL接收空间只取自寄存占用，
    // 切断response_ready到请求许可的长反馈。
 parameter REGISTERED_INPUT_CREDIT=0
)(
    // 接口字段：input wire clk,reset,cancel,request_valid。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
 input wire clk,reset,cancel,request_valid,
    // 接口字段：output wire request_ready。
    // 事务握手。valid与对应ready同边界才接收；背压期间有主状态的载荷必须保持。
 output wire request_ready,
    // 接口字段：input wire [31:0] left,right。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
 input wire [31:0] left,right,
    // 接口字段：input wire [TOKEN_WIDTH-1:0] request_token。
    // 生产者或事务标签。只关联所有者，不代表算术值，也不能单凭标签判断已完成。
 input wire [TOKEN_WIDTH-1:0] request_token,
    // 接口字段：output wire response_valid,response_present。
    // 事务握手。valid与对应ready同边界才接收；背压期间有主状态的载荷必须保持。
 output wire response_valid,response_present,
    // 接口字段：input wire response_ready。
    // 事务握手。valid与对应ready同边界才接收；背压期间有主状态的载荷必须保持。
 input wire response_ready,
    // 接口字段：output wire [31:0] result。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
 output wire [31:0] result,
    // 接口字段：output wire [TOKEN_WIDTH-1:0] response_token。
    // 生产者或事务标签。只关联所有者，不代表算术值，也不能单凭标签判断已完成。
 output wire [TOKEN_WIDTH-1:0] response_token,
    // 接口字段：output wire [1:0] occupancy。
    // 有效数量或消费数量。索引编码只有对应有效/计数许可时才表示存活所有者。
 output wire [1:0] occupancy
);
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
