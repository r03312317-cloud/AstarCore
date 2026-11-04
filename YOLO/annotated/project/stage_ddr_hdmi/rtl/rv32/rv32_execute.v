// Original RV32 project file; see SOURCE_PROVENANCE.md.
// RV32 instruction semantics. Written from scratch for this project.
// Pure combinational RV32IM_Zba_Zbb_Zbs/Zicsr/Zifencei execution decoder.
// 架构导读：rv32_execute。
// 执行整数运算和控制转移，向核心提交结果以及重定向信息。
module rv32_execute(
    // 接口声明：input [31:0] instruction, pc, left, right, csr_value。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input [31:0] instruction, pc, left, right, csr_value,
    // 接口声明：output [4:0] source1, source2, destination。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output [4:0] source1, source2, destination,
    // 接口声明：output reg uses_source1, uses_source2, writes_destination。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output reg uses_source1, uses_source2, writes_destination,
    // 接口声明：output reg [31:0] value, address, store_value, next_pc。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output reg [31:0] value, address, store_value, next_pc,
    // 接口声明：output reg memory, memory_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output reg memory, memory_write,
    // 接口声明：output reg [1:0] memory_size。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output reg [1:0] memory_size,
    // 接口声明：output reg memory_unsigned。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output reg memory_unsigned,
    // 接口声明：output reg arithmetic。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output reg arithmetic,
    // 接口声明：output [2:0] arithmetic_operation。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output [2:0] arithmetic_operation,
    // 接口声明：output reg control, conditional, taken。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output reg control, conditional, taken,
    // 接口声明：output reg csr, csr_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output reg csr, csr_write,
    // 接口声明：output reg [31:0] csr_new_value。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output reg [31:0] csr_new_value,
    // 接口声明：output [11:0] csr_number。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output [11:0] csr_number,
    // 接口声明：output reg [2:0] system_operation。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output reg [2:0] system_operation,
    // 接口声明：output reg illegal。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output reg illegal
);
    // 局部字段 wire [6:0] opcode = instruction[6:0]。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    wire [6:0] opcode = instruction[6:0];
    // 局部字段 wire [2:0] sub = instruction[14:12]。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    wire [2:0] sub = instruction[14:12];
    // 局部字段 wire [6:0] extension = instruction[31:25]。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    wire [6:0] extension = instruction[31:25];
    // 局部字段 wire [31:0] immediate_i = {{20{instruction[31]}},instruction[31:20]}。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    wire [31:0] immediate_i = {{20{instruction[31]}},instruction[31:20]};
    // 局部字段 wire [31:0] immediate_s = {{20{instruction[31]}},instruction[31:25],instruction[11:7]}。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    wire [31:0] immediate_s = {{20{instruction[31]}},instruction[31:25],instruction[11:7]};
    // 局部字段 wire [31:0] immediate_b = {{19{instruction[31]}},instruction[31],instruction[7],instruction[30:25],ins...。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    wire [31:0] immediate_b = {{19{instruction[31]}},instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0};
    // 局部字段 wire [31:0] immediate_j = {{11{instruction[31]}},instruction[31],instruction[19:12],instruction[20],in...。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    wire [31:0] immediate_j = {{11{instruction[31]}},instruction[31],instruction[19:12],instruction[20],instruction[30:21],1'b0};
    // 局部字段 wire [4:0] shift = right[4:0]。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    wire [4:0] shift = right[4:0];
    // 局部字段 wire [4:0] immediate_shift = instruction[24:20]。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    wire [4:0] immediate_shift = instruction[24:20];
    // 局部字段 wire [31:0] csr_source = sub[2] ? {27'b0,instruction[19:15]} : left。
    // 记录数量或剩余进度，位宽限定可表达范围。
    wire [31:0] csr_source = sub[2] ? {27'b0,instruction[19:15]} : left;
    // R50: one barrel network serves register/immediate shifts and rotates.
    // Reversing both ends converts a right barrel into a left barrel.
    // A rotation supplies the input as its upper half; SRA supplies sign.
    wire [4:0] shared_shift_amount=opcode[5]?shift:immediate_shift;
    // 局部字段 wire shared_shift_left=sub==1。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    wire shared_shift_left=sub==1;
    wire shared_rotate=extension==7'b0110000&&
        ((opcode==7'b0110011&&(sub==1||sub==5))||
         (opcode==7'b0010011&&sub==5));
    // 局部字段 wire shared_arithmetic=extension==7'b0100000&&sub==5。
    wire shared_arithmetic=extension==7'b0100000&&sub==5;
    wire [31:0] reversed_left,barrel_input,barrel_fill,shared_shift_value;
    wire [63:0] barrel_shifted={barrel_fill,barrel_input}>>shared_shift_amount;
    wire unused_barrel_upper=|barrel_shifted[63:32];
    genvar shift_bit;
    generate for(shift_bit=0;shift_bit<32;shift_bit=shift_bit+1)begin:shared_barrel
        // 组合连接 reversed_left[shift_bit]：记录数量或剩余进度，位宽限定可表达范围。
        assign reversed_left[shift_bit]=left[31-shift_bit];
        // 组合连接 shared_shift_value[shift_bit]：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
        assign shared_shift_value[shift_bit]=shared_shift_left?
            barrel_shifted[31-shift_bit]:barrel_shifted[shift_bit];
    end endgenerate
    // 组合连接 barrel_input：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign barrel_input=shared_shift_left?reversed_left:left;
    // 组合连接 barrel_fill：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign barrel_fill=shared_rotate?barrel_input:{32{shared_arithmetic&&left[31]}};
    wire [31:0] shared_bit_mask=32'b1<<shared_shift_amount;
    wire [31:0] compare_right=opcode==7'b0010011 ?immediate_i:right;
    wire shared_unsigned_less=left<compare_right;
    wire shared_signed_less=left[31]!=compare_right[31]?left[31]:shared_unsigned_less;
    wire [31:0] shared_add_right=opcode==7'b0100011 ?immediate_s:
        opcode==7'b0110011 ?right:immediate_i;
    wire [31:0] shared_add_left=(opcode==7'b0110011&&extension==7'b0010000)?
        (sub==2?{left[30:0],1'b0}:sub==4?{left[29:0],2'b0}:{left[28:0],3'b0}):left;
    wire shared_subtract=opcode==7'b0110011&&extension==7'b0100000&&sub==0;
    wire [31:0] shared_sum=shared_add_left+(shared_subtract?~shared_add_right:shared_add_right)+{31'b0,shared_subtract};
    wire [31:0] shared_pc_offset=opcode==7'b0010111 ?{instruction[31:12],12'b0}:
        opcode==7'b1101111 ?immediate_j:immediate_b;
    wire [31:0] shared_pc_target=pc+shared_pc_offset;
    // Balanced count trees avoid a 32-deep chain in FPGA LUT fabric.
`ifdef VERILATOR
    // 局部运算/辅助过程：function [5:0] leading_zeroes_reference;。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function [5:0] leading_zeroes_reference;
        // 接口声明：input [31:0] word。
        // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
        input [31:0] word;
        reg [31:0] shifted;
        reg [5:0] amount;
        begin
            shifted=word;amount=0;
            // 条件分支：检查 shifted[31:16]==0。
            if(shifted[31:16]==0)begin amount=amount+16;shifted=shifted<<16;end
            // 条件分支：检查 shifted[31:24]==0。
            if(shifted[31:24]==0)begin amount=amount+8;shifted=shifted<<8;end
            // 条件分支：检查 shifted[31:28]==0。
            if(shifted[31:28]==0)begin amount=amount+4;shifted=shifted<<4;end
            // 条件分支：检查 shifted[31:30]==0。
            if(shifted[31:30]==0)begin amount=amount+2;shifted=shifted<<2;end
            // 条件分支：检查 shifted[31]==0。
            if(shifted[31]==0)amount=amount+1;
            leading_zeroes_reference=(word==0)?6'd32:amount;
        end
    endfunction
`endif
    // A balanced priority tree carries only valid/index information.
    // Its highest occupied leaf is the most significant set bit; inverting
    // that5-bit index gives CLZ. CTZ still uses the original bit reversal.
    function [5:0] leading_zeroes;
        // 接口声明：input [31:0] word。
        // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
        input [31:0] word;
        reg [63:1] subtree_valid;
        reg [4:0] position[1:63];
        integer k;
        begin
            // 按 k=0;k<32;k=k+1 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
            for(k=0;k<32;k=k+1)begin subtree_valid[32+k]=word[k];position[32+k]=k[4:0];end
            // 按 k=31;k>0;k=k-1 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
            for(k=31;k>0;k=k-1)begin
                subtree_valid[k]=subtree_valid[2*k]||subtree_valid[2*k+1];
                position[k]=subtree_valid[2*k+1]?position[2*k+1]:position[2*k];
            end
            leading_zeroes=subtree_valid[1]?{1'b0,~position[1]}:6'd32;
`ifdef VERILATOR
            // 条件分支：检查 leading_zeroes!=leading_zeroes_reference(word)。
            if(leading_zeroes!=leading_zeroes_reference(word))
                $fatal(1,"R39 priority encoder differs from original zero-count function");
`endif
        end
    endfunction
    // 局部运算/辅助过程：function [5:0] trailing_zeroes;。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function [5:0] trailing_zeroes;
        // 接口声明：input [31:0] word。
        // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
        input [31:0] word;
        reg [31:0] reversed;
        integer k;
        begin
            // 按 k=0;k<32;k=k+1 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
            for(k=0;k<32;k=k+1)reversed[k]=word[31-k];
            trailing_zeroes=leading_zeroes(reversed);
        end
    endfunction
    // 局部运算/辅助过程：function [5:0] population;。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function [5:0] population;
        // 接口声明：input [31:0] word。
        // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
        input [31:0] word;
        reg [1:0] pairs[0:15];
        reg [2:0] quads[0:7];
        reg [3:0] octets[0:3];
        reg [4:0] halves[0:1];
        integer k;
        begin
            // 按 k=0;k<16;k=k+1 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
            for(k=0;k<16;k=k+1)pairs[k]={1'b0,word[2*k]}+{1'b0,word[2*k+1]};
            // 按 k=0;k<8;k=k+1 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
            for(k=0;k<8;k=k+1)quads[k]={1'b0,pairs[2*k]}+{1'b0,pairs[2*k+1]};
            // 按 k=0;k<4;k=k+1 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
            for(k=0;k<4;k=k+1)octets[k]={1'b0,quads[2*k]}+{1'b0,quads[2*k+1]};
            // 按 k=0;k<2;k=k+1 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
            for(k=0;k<2;k=k+1)halves[k]={1'b0,octets[2*k]}+{1'b0,octets[2*k+1]};
            population={1'b0,halves[0]}+{1'b0,halves[1]};
        end
    endfunction
    // 组合连接 source1：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign source1 = instruction[19:15];
    // 组合连接 source2：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign source2 = instruction[24:20];
    // 组合连接 destination：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign destination = instruction[11:7];
    // 组合连接 arithmetic_operation：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign arithmetic_operation = sub;
    // 组合连接 csr_number：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign csr_number = instruction[31:20];
    // 过程边界：always @* begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always @* begin
        uses_source1=0; uses_source2=0; writes_destination=0;
        value=0; address=0; store_value=right; next_pc=pc+32'd4;
        memory=0; memory_write=0; memory_size=0; memory_unsigned=0;
        arithmetic=0; control=0; conditional=0; taken=0;
        csr=0; csr_write=0; csr_new_value=csr_value; system_operation=0;
        illegal=0;
        // 按 opcode 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
        case (opcode)
            7'b0110111: begin writes_destination=1; value={instruction[31:12],12'b0}; end
            7'b0010111: begin writes_destination=1; value=shared_pc_target; end
            7'b1101111: begin
                writes_destination=1; value=pc+32'd4; next_pc=shared_pc_target;
                control=1; taken=1;
            end
            7'b1100111: begin
                uses_source1=1; writes_destination=1; value=pc+32'd4;
                next_pc=(shared_sum)&32'hfffffffe; control=1; taken=1;
                // 条件分支：检查 sub!=0。
                if(sub!=0) illegal=1;
            end
            7'b1100011: begin
                uses_source1=1; uses_source2=1; control=1; conditional=1;
                // 按 sub 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                case(sub)
                    0: taken=(left==right);
                    1: taken=(left!=right);
                    4: taken=shared_signed_less;
                    5: taken=!shared_signed_less;
                    6: taken=shared_unsigned_less;
                    7: taken=!shared_unsigned_less;
                    default: illegal=1;
                endcase
                // 条件分支：检查 taken。
                if(taken) next_pc=shared_pc_target;
            end
            7'b0000011: begin
                uses_source1=1; writes_destination=1; memory=1;
                address=shared_sum; memory_size=sub[1:0]; memory_unsigned=sub[2];
                // 条件分支：检查 sub==3 || sub==6 || sub==7。
                if(sub==3 || sub==6 || sub==7) illegal=1;
            end
            7'b0100011: begin
                uses_source1=1; uses_source2=1; memory=1; memory_write=1;
                address=shared_sum; memory_size=sub[1:0];
                // 条件分支：检查 sub>2。
                if(sub>2) illegal=1;
            end
            7'b0010011: begin
                uses_source1=1; writes_destination=1;
                // 按 sub 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                case(sub)
                    0: value=shared_sum;
                    2: value={31'b0,shared_signed_less};
                    3: value={31'b0,shared_unsigned_less};
                    4: value=left^immediate_i;
                    6: value=left|immediate_i;
                    7: value=left&immediate_i;
                    1: begin
                        // 按 extension 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                        case(extension)
                            7'b0000000: value=shared_shift_value;
                            7'b0010100: value=left|shared_bit_mask;
                            7'b0100100: value=left&~shared_bit_mask;
                            7'b0110100: value=left^shared_bit_mask;
                            7'b0110000: begin
                                // 按 immediate_shift 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                                case(immediate_shift)
                                    0: value={26'b0,leading_zeroes(left)};
                                    1: value={26'b0,trailing_zeroes(left)};
                                    2: value={26'b0,population(left)};
                                    4: value={{24{left[7]}},left[7:0]};
                                    5: value={{16{left[15]}},left[15:0]};
                                    default: illegal=1;
                                endcase
                            end
                            default: illegal=1;
                        endcase
                    end
                    5: begin
                        // 按 extension 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                        case(extension)
                            7'b0000000: value=shared_shift_value;
                            7'b0100000: value=shared_shift_value;
                            7'b0110000: value=shared_shift_value;
                            7'b0100100: value={31'b0,shared_shift_value[0]};
                            7'b0010100: begin
                                // 条件分支：检查 immediate_shift!=7。
                                if(immediate_shift!=7) illegal=1;
                                value={{8{|left[31:24]}},{8{|left[23:16]}},{8{|left[15:8]}},{8{|left[7:0]}}};
                            end
                            7'b0110100: begin
                                // 条件分支：检查 immediate_shift!=24。
                                if(immediate_shift!=24) illegal=1;
                                value={left[7:0],left[15:8],left[23:16],left[31:24]};
                            end
                            default: illegal=1;
                        endcase
                    end
                    default: illegal=1;
                endcase
            end
            7'b0110011: begin
                uses_source1=1; uses_source2=1; writes_destination=1;
                // 按 extension 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                case(extension)
                    7'b0000001: arithmetic=1;
                    7'b0000000: begin
                        // 按 sub 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                        case(sub)
                            0:value=shared_sum;
                            1:value=shared_shift_value;
                            2:value={31'b0,shared_signed_less};
                            3:value={31'b0,shared_unsigned_less};
                            4:value=left^right;
                            5:value=shared_shift_value;
                            6:value=left|right;
                            7:value=left&right;
                        endcase
                    end
                    7'b0100000: begin
                        // 按 sub 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                        case(sub)
                            0:value=shared_sum;
                            4:value=~(left^right);
                            5:value=shared_shift_value;
                            6:value=left|~right;
                            7:value=left&~right;
                            default:illegal=1;
                        endcase
                    end
                    7'b0110000: begin
                        // 按 sub 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                        case(sub)
                            1:value=shared_shift_value;
                            5:value=shared_shift_value;
                            default:illegal=1;
                        endcase
                    end
                    7'b0000101: begin
                        // 按 sub 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                        case(sub)
                            4:value=shared_signed_less?left:right;
                            5:value=shared_unsigned_less?left:right;
                            6:value=!shared_signed_less?left:right;
                            7:value=!shared_unsigned_less?left:right;
                            default:illegal=1;
                        endcase
                    end
                    7'b0010000: begin
                        // 按 sub 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                        case(sub)
                            2:value=shared_sum;
                            4:value=shared_sum;
                            6:value=shared_sum;
                            default:illegal=1;
                        endcase
                    end
                    7'b0000100: begin
                        // 条件分支：检查 sub==4 && source2==0。
                        if(sub==4 && source2==0) begin value={16'b0,left[15:0]}; uses_source2=0; end
                        else illegal=1;
                    end
                    7'b0010100: if(sub==1) value=left|shared_bit_mask; else illegal=1;
                    7'b0100100: begin
                        // 条件分支：检查 sub==1。
                        if(sub==1) value=left&~shared_bit_mask;
                        // 条件分支：检查 sub==5。
                        else if(sub==5) value={31'b0,shared_shift_value[0]};
                        else illegal=1;
                    end
                    7'b0110100: if(sub==1) value=left^shared_bit_mask; else illegal=1;
                    default:illegal=1;
                endcase
            end
            7'b0001111: begin
                // 条件分支：检查 instruction==32'h0000500f。
                if(instruction==32'h0000500f) system_operation=6;
                // 条件分支：检查 sub==1。
                else if(sub==1) system_operation=1;
                // 条件分支：检查 sub==0。
                else if(sub==0) system_operation=6;
                else illegal=1;
            end
            7'b1110011: begin
                // 条件分支：检查 sub==0。
                if(sub==0) begin
                    // 按 instruction 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                    case(instruction)
                        32'h00000073:system_operation=3;
                        32'h00100073:system_operation=4;
                        32'h30200073:system_operation=2;
                        32'h10500073:system_operation=5;
                        default:begin
                            // 条件分支：检查 (instruction&32'hfe007fff)==32'h12000073。
                            if((instruction&32'hfe007fff)==32'h12000073) system_operation=1;
                            else illegal=1;
                        end
                    endcase
                end else begin
                    csr=1; writes_destination=1; uses_source1=!sub[2]; value=csr_value;
                    // 按 sub[1:0] 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                    case(sub[1:0])
                        1: begin csr_write=1; csr_new_value=csr_source; end
                        2: begin csr_write=(source1!=0); csr_new_value=csr_value|csr_source; end
                        3: begin csr_write=(source1!=0); csr_new_value=csr_value&~csr_source; end
                        default:illegal=1;
                    endcase
                end
            end
            default:illegal=1;
        endcase
    end
endmodule
