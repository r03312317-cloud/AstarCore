// Exact S6 effective-address region classification, independent of full32-bit sum.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 有效地址的精确外设区域预分类，输入为32位基址与有符号12位偏移。
// 原外设范围可按高6位连续区间判断，低位加法只需确定是否跨越64MiB边界。
// 正负偏移最多跨越一次边界，因此只对四个边界高位组合纠正区域归属。
// 输出与完整32位地址加法后的原区域判断相同，并非近似预测。
// 该结果用于LSU副作用和非对齐资格，真正访存地址仍由地址加法器产生。
// 纯组合模块，不拥有请求、Cache行或提交状态。
module rv32_address_classify(input [31:0] base,input [11:0] offset,output peripheral);
    wire [5:0] high=base[31:26];
    wire [12:0] low_sum={1'b0,base[11:0]}+{1'b0,offset};
    wire positive_cross=!offset[11]&&(&base[25:12])&&low_sum[12];
    wire negative_cross=offset[11]&&!(|base[25:12])&&!low_sum[12];
    // Original two contiguous ranges are exactly high6 in[12,32]. A signed
    //12-bit offset can cross at most one64-MiB boundary. Only four boundary
    // high values can change region membership; all comparisons are parallel.
    wire base_inside=high>=6'd12&&high<=6'd32;
    wire change=(positive_cross&&(high==6'd11||high==6'd32))||
                (negative_cross&&(high==6'd12||high==6'd33));
    assign peripheral=base_inside^change;
endmodule
