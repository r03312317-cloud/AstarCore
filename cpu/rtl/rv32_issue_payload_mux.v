// Original RV32 combinational payload factoring, Soc02 round 2.
// Ownership, issue masks, order, and cycle boundaries are unchanged.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 把独热候选对应的宽数据从整数和复杂银行读出，供两个 EX 槽位采样。
// 先分别归并第一整数、第二整数与复杂数据，再做晚到操作类型选择。
// payload 宽度由 WIDTH 参数指定，内容由调用者打包，不能把它固定解释为一条指令。
// 当 EX0 因乘法背压保持时，EX1 可使用第一整数候选。
// 无内部所有权状态，one-hot 选择契约由调度器保证。
// 原文件的综合保留属性保护局部归并边界，属于综合语义，整理时必须完整保留。
// 接口契约与阅读示例
// 若lane0选择复杂项，则lane1使用最老整数项，不能再跳过它取第二整数。
// 若lane0选择第一整数，则lane1才使用第二整数项。
// 若EX0保持，则输出0被屏蔽，lane1仍可使用第一整数候选。
// 复位或关闭配对会屏蔽相应输出，但本模块没有写入RF的副作用。
// 独热按位或归并依赖掩码合法性，多选会按位混合，因此调用者必须保证one-hot。
// 宽payload中的字段必须来自同一行，不能分别选PC和操作数再以不同标签合并。
module rv32_issue_payload_mux #(
    // 参数 WIDTH：打包的独热选择数据位宽，由调用者定义字段，
    // 不隐含固定指令格式。
    parameter WIDTH=91,
    // 参数 ENABLE_PAIRING：允许最大两条分配/发射/提交；
    // 资源及依赖不满足时仍可仅推进一条。
    parameter ENABLE_PAIRING=1
)(
    // 接口字段：input reset,ex_hold。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input reset,ex_hold,
    // 接口字段：input [7:0] first_integer,second_integer。
    // 把独热候选对应的宽数据从整数和复杂银行读出，供两个 EX 槽位采样。
    input [7:0] first_integer,second_integer,
    // 接口字段：input [3:0] first_complex。
    // 把独热候选对应的宽数据从整数和复杂银行读出，供两个 EX 槽位采样。
    input [3:0] first_complex,
    // 接口字段：input choose_complex。
    // 把独热候选对应的宽数据从整数和复杂银行读出，供两个 EX 槽位采样。
    input choose_complex,
    // 接口字段：input [12*WIDTH-1:0] payload。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
    input [12*WIDTH-1:0] payload,
    // 接口字段：output [WIDTH-1:0] value0,value1。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
    output [WIDTH-1:0] value0,value1
);
    // Retain the completed bank reads before the late bank selector.
    reg [WIDTH-1:0] first_data /* synthesis syn_keep = 1 */;
    reg [WIDTH-1:0] second_data /* synthesis syn_keep = 1 */;
    reg [WIDTH-1:0] complex_data /* synthesis syn_keep = 1 */;
    integer k;
    always @*begin
        first_data=0;second_data=0;complex_data=0;
        for(k=0;k<8;k=k+1)begin
            first_data=first_data|({WIDTH{first_integer[k]}}&payload[k*WIDTH+:WIDTH]);
            second_data=second_data|({WIDTH{second_integer[k]}}&payload[k*WIDTH+:WIDTH]);
        end
        for(k=0;k<4;k=k+1)
            complex_data=complex_data|({WIDTH{first_complex[k]}}&payload[(8+k)*WIDTH+:WIDTH]);
    end
    assign value0=reset||ex_hold?{WIDTH{1'b0}}:(choose_complex?complex_data:first_data);
    assign value1=reset||!ENABLE_PAIRING?{WIDTH{1'b0}}:
        (ex_hold||choose_complex?first_data:second_data);
endmodule
