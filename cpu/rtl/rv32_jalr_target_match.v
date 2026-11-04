// Original RV32 combinational JALR prediction check.
// A predicted sum bit implies carry-in A^B^P. The preceding bit implies
// carry-out (A&B)|((A|B)&~P). Check all adjacent-bit agreements in parallel.
// JALR clears sum bit 0; its carry into bit 1 is A[0]&B[0]. The top carry
// wraps modulo 2^32. There is no pipeline stage or change to the real target.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 不经过完整目标加法链，精确判断给定JALR预测地址是否等于base加offset并清最低位
// 。
// 由相邻位推出进位一致性，各位比较并行，归约后得到match_ok。
// bit1使用base[0]与offset[0]产生的真实最低位进位；最高位按32位自然回绕。
// expected最低位必须为0，符合JALR目标最低位清零的语义。
// 本模块只判等，不替代实际跳转地址的计算和未对齐异常检查。
// 纯组合辅助模块，没有改变跳转结果或添加流水级。
module rv32_jalr_target_match(
    // 接口字段：input [31:0] base,offset,expected。
    // 不经过完整目标加法链，精确判断给定JALR预测地址是否等于base加offset并清最
    // 低位。
    input [31:0] base,offset,expected,
    // 接口字段：output match_ok。
    // 不经过完整目标加法链，精确判断给定JALR预测地址是否等于base加offset并清最
    // 低位。
    output match_ok
);
    wire [31:1] agreements;
    assign agreements[1]=(base[1]^offset[1]^expected[1])==(base[0]&offset[0]);
    genvar bit_position;
    generate for(bit_position=2;bit_position<32;bit_position=bit_position+1)begin:local_carry_check
        assign agreements[bit_position]=(base[bit_position]^offset[bit_position]^expected[bit_position])==
            ((base[bit_position-1]&offset[bit_position-1])|
             ((base[bit_position-1]|offset[bit_position-1])&!expected[bit_position-1]));
    end endgenerate
    assign match_ok=!expected[0]&&(&agreements);
endmodule
