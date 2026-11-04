// 架构导读：soc_v2_bilinear_quant。
// 可综合数据/控制组件；接口含义和更新条件以下面的局部注释及原始表达式为准。
`timescale 1ns/1ps
// Fully elastic V2 pixel interpolation. The five registered steps isolate
// phase weights, products, sum, exact /400, and model LUT access. Every step
// obeys valid/ready, so arbitrary DDR and output stalls preserve raster order.
module soc_v2_bilinear_quant (
    // 接口声明：input logic clk,rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic clk,rst,
    // 接口声明：input logic lut_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic lut_write,
    // 接口声明：input logic [7:0] lut_addr,lut_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [7:0] lut_addr,lut_data,
    // 接口声明：output logic lut_ready,lut_complete。
    // 表达本地完成/结束条件，系统退休还需满足上层接口契约。
    output logic lut_ready,lut_complete,
    // 接口声明：input logic in_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input logic in_valid,
    // 接口声明：output logic in_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic in_ready,
    // 接口声明：input logic pad。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic pad,
    // 接口声明：input logic [15:0] c00,c01,c10,c11。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [15:0] c00,c01,c10,c11,
    // 接口声明：input logic [4:0] phase_x,phase_y。
    // 选择控制阶段，各编码的行为由状态分支定义。
    input logic [4:0] phase_x,phase_y,
    // 接口声明：output logic out_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic out_valid,
    // 接口声明：input logic out_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic out_ready,
    // 接口声明：output logic [23:0] out_rgb_i8。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [23:0] out_rgb_i8
);
    (* ram_style="distributed" *) logic [7:0] lut[0:255];
    logic [255:0] written;
    logic locked;
    logic [4:0] valid_q;
    logic [3:0] pad_q;
    logic [8:0] weight_q[0:3];
    logic [7:0] sample_q[0:11];
    logic [16:0] product_q[0:11];
    logic [18:0] sum_q[0:2];
    logic [7:0] rgb_q[0:2];
    logic ready_0,ready_1,ready_2,ready_3,ready_4;

    // 局部运算/辅助过程：function automatic logic [7:0] expand(input logic [15:0] word,。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function automatic logic [7:0] expand(input logic [15:0] word,
                                           // 接口声明：input int channel)。
                                           // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
                                           input int channel);
        logic [4:0] five;
        logic [5:0] six;
        // 按 channel 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
        case(channel)
            0: begin five=word[15:11];return {five,five[4:2]}; end
            1: begin six=word[10:5];return {six,six[5:4]}; end
            default: begin five=word[4:0];return {five,five[4:2]}; end
        endcase
    endfunction

    assign lut_ready=!rst && !locked;
    assign lut_complete=&written;
    assign ready_4=!valid_q[4] || out_ready;
    assign ready_3=!valid_q[3] || ready_4;
    assign ready_2=!valid_q[2] || ready_3;
    assign ready_1=!valid_q[1] || ready_2;
    assign ready_0=!valid_q[0] || ready_1;
    assign in_ready=!rst && lut_complete && ready_0;
    assign out_valid=valid_q[4];

    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst) begin
            written<='0;locked<=0;valid_q<='0;pad_q<='0;
            out_rgb_i8<=0;
        end else begin
            // 条件分支：检查 lut_write && lut_ready。
            if(lut_write && lut_ready) begin
                lut[lut_addr]<=lut_data;
                written[lut_addr]<=1;
            end
            // 条件分支：检查 ready_4。
            if(ready_4) begin
                valid_q[4]<=valid_q[3];
                // 条件分支：检查 valid_q[3]。
                if(valid_q[3])
                    out_rgb_i8<={lut[rgb_q[2]],lut[rgb_q[1]],lut[rgb_q[0]]};
            end
            // 条件分支：检查 ready_3。
            if(ready_3) begin
                valid_q[3]<=valid_q[2];
                // 条件分支：检查 valid_q[2]。
                if(valid_q[2]) begin
                    pad_q[3]<=pad_q[2];
                    for(int ch=0;ch<3;ch++)
                        rgb_q[ch]<=pad_q[2] ? 8'd114 :
                                   8'((sum_q[ch]+19'd200)/19'd400);
                end
            end
            // 条件分支：检查 ready_2。
            if(ready_2) begin
                valid_q[2]<=valid_q[1];
                // 条件分支：检查 valid_q[1]。
                if(valid_q[1]) begin
                    pad_q[2]<=pad_q[1];
                    for(int ch=0;ch<3;ch++)
                        sum_q[ch]<=19'(product_q[ch*4+0])+
                                   19'(product_q[ch*4+1])+
                                   19'(product_q[ch*4+2])+
                                   19'(product_q[ch*4+3]);
                end
            end
            // 条件分支：检查 ready_1。
            if(ready_1) begin
                valid_q[1]<=valid_q[0];
                // 条件分支：检查 valid_q[0]。
                if(valid_q[0]) begin
                    pad_q[1]<=pad_q[0];
                    for(int ch=0;ch<3;ch++)
                        for(int tap=0;tap<4;tap++)
                            product_q[ch*4+tap]<=17'(weight_q[tap])*
                                                 17'(sample_q[ch*4+tap]);
                end
            end
            if(ready_0) begin
                valid_q[0]<=in_valid && lut_complete;
                if(in_valid && lut_complete) begin
                    locked<=1;pad_q[0]<=pad;
                    weight_q[0]<=9'(20-phase_x)*9'(20-phase_y);
                    weight_q[1]<=9'(phase_x)*9'(20-phase_y);
                    weight_q[2]<=9'(20-phase_x)*9'(phase_y);
                    weight_q[3]<=9'(phase_x)*9'(phase_y);
                    for(int ch=0;ch<3;ch++) begin
                        sample_q[ch*4+0]<=expand(c00,ch);
                        sample_q[ch*4+1]<=expand(c01,ch);
                        sample_q[ch*4+2]<=expand(c10,ch);
                        sample_q[ch*4+3]<=expand(c11,ch);
                    end
                end
            end
        end
    end
    initial if(20*20*255>19'h7ffff) $fatal(1,"V2_WEIGHT_WIDTH");
endmodule
