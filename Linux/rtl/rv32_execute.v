// Original RV32 project file; see SOURCE_PROVENANCE.md.
// RV32 instruction semantics. Written from scratch for this project.
// Pure combinational RV32IM_Zba_Zbb_Zbs/Zicsr/Zifencei execution decoder.
// 执行译码从指令 PC 和捕获的操作数形成 ALU 访存 分支及系统操作结果。
// 组合结果只是候选，是否能产生架构副作用由外层 ROB 提交与异常控制决定。
// 立即数拼接和符号扩展按指令格式分别完成，不应将移位和加减共用错误的符号位。
// JALR 清除目标最低位，未启用压缩指令时还需检查指令地址对齐。
// CSR 操作同时输出编号 新值及写资格，读改写不是普通整数寄存器写回。
// 预译码 ALU 控制与原始指令译码并存，功能选择受顶层参数控制。
module rv32_execute(
    // instruction 保存原始指令编码，和该条指令的 PC 及身份同行保存。
    input [31:0] instruction, pc, left, right, csr_value,
    // destination 保存目的架构寄存器编号，必须和结果所有者同时核对。
    output [4:0] source1, source2, destination,
    // writes_destination 保存目的架构寄存器编号，必须和结果所有者同时核对。
    output reg uses_source1, uses_source2, writes_destination,
    // address 保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
    output reg [31:0] value, address, store_value, next_pc,
    // TOPT5: expose targets already used by the control datapath, so
    // prediction matching can compare in parallel with direction.
    output [31:0] sequential_target,branch_jump_target,indirect_jump_target,
    // memory 保存访存类别资格，供访存顺序与执行资源选择使用。
    output reg memory, memory_write,
    // memory_size 属于访存顺序控制，保存访问尺寸编码，决定对齐和字节选择的处理方式。
    // 顺序许可与容量许可分别约束，存储及 MMIO 副作用不能重复。
    output reg [1:0] memory_size,
    output reg memory_unsigned,
    // arithmetic 保存复杂算术类别或结果，和普通整数路径分别仲裁。
    output reg arithmetic,
    output [2:0] arithmetic_operation,
    // control 保存控制流类别或控制位，供目标选择和分支结果处理使用。
    output reg control, conditional, taken,
    output reg csr, csr_write,
    output reg [31:0] csr_new_value,
    output [11:0] csr_number,
    output reg [2:0] system_operation,
    output reg illegal
);
    // opcode 读取 instruction[6:0] 所选位域；位索引按声明中的高低位顺序解释。
    wire [6:0] opcode = instruction[6:0];
    // sub 读取 instruction[14:12] 所选位域；位索引按声明中的高低位顺序解释。
    wire [2:0] sub = instruction[14:12];
    // extension 读取 instruction[31:25] 所选位域；位索引按声明中的高低位顺序解释。
    wire [6:0] extension = instruction[31:25];
    // immediate_i 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {{20{instruction[31]}},instruction[31:20]}；复制大括号表示重复位域，不是独立队列元素。
    wire [31:0] immediate_i = {{20{instruction[31]}},instruction[31:20]};
    // immediate_s 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {{20{instruction[31]}},instruction[31:25],instruction[11:7]}；复制大括号表示重复位域，不是独立队列元素。
    wire [31:0] immediate_s = {{20{instruction[31]}},instruction[31:25],instruction[11:7]};
    // immediate_b 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {{19{instruction[31]}},instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0}；复制大括号表示重复位域，不是独立队列元素。
    wire [31:0] immediate_b = {{19{instruction[31]}},instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0};
    // immediate_j 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {{11{instruction[31]}},instruction[31],instruction[19:12],instruction[20],instruction[30:21],1'b0}；复制大括号表示重复位域，不是独立队列元素。
    wire [31:0] immediate_j = {{11{instruction[31]}},instruction[31],instruction[19:12],instruction[20],instruction[30:21],1'b0};
    // shift 读取 right[4:0] 所选位域；位索引按声明中的高低位顺序解释。
    wire [4:0] shift = right[4:0];
    // immediate_shift 读取 instruction[24:20] 所选位域；位索引按声明中的高低位顺序解释。
    wire [4:0] immediate_shift = instruction[24:20];
    // csr_source 按 sub[2] 进行来源选择。
    // 真分支取 {27'b0,instruction[19:15]}；其余情况取 left。
    wire [31:0] csr_source = sub[2] ? {27'b0,instruction[19:15]} : left;
    // R50: one barrel network serves register/immediate shifts and rotates.
    // Reversing both ends converts a right barrel into a left barrel.
    // A rotation supplies the input as its upper half; SRA supplies sign.
    // shared_shift_amount 按 opcode[5] 进行来源选择。
    // 真分支取 shift；其余情况取 immediate_shift。
    wire [4:0] shared_shift_amount=opcode[5]?shift:immediate_shift;
    // shared_shift_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    // shared_shift_left 由比较式 sub==1 产生；该结果是条件判断，不是被比较的数据。
    wire shared_shift_left=sub==1;
    // shared_rotate 的资格组合为 extension==7'b0110000&& ((opcode==7'b0110011&&(sub==1||sub==5))|| (opcode==7'b0010011&&sub==5))。
    // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
    wire shared_rotate=extension==7'b0110000&&
        ((opcode==7'b0110011&&(sub==1||sub==5))||
         (opcode==7'b0010011&&sub==5));
    // shared_arithmetic 保存复杂算术类别或结果，和普通整数路径分别仲裁。
    // shared_arithmetic 的资格组合为 extension==7'b0100000&&sub==5。
    wire shared_arithmetic=extension==7'b0100000&&sub==5;
    // reversed_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    wire [31:0] reversed_left,barrel_input,barrel_fill,shared_shift_value;
    // barrel_shifted 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {barrel_fill,barrel_input}>>shared_shift_amount；复制大括号表示重复位域，不是独立队列元素。
    wire [63:0] barrel_shifted={barrel_fill,barrel_input}>>shared_shift_amount;
    // unused_barrel_upper 对 |barrel_shifted[63:32] 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire unused_barrel_upper=|barrel_shifted[63:32];
    genvar shift_bit;
    generate for(shift_bit=0;shift_bit<32;shift_bit=shift_bit+1)begin:shared_barrel
        // reversed_left[shift_bit] 读取 left[31-shift_bit] 所选位域；位索引按声明中的高低位顺序解释。
        assign reversed_left[shift_bit]=left[31-shift_bit];
        assign shared_shift_value[shift_bit]=shared_shift_left?
            barrel_shifted[31-shift_bit]:barrel_shifted[shift_bit];
    end endgenerate
    // barrel_input 按 shared_shift_left 进行来源选择。
    // 真分支取 reversed_left；其余情况取 left。
    assign barrel_input=shared_shift_left?reversed_left:left;
    // barrel_fill 按 shared_rotate 进行来源选择。
    // 真分支取 barrel_input；其余情况取 {32{shared_arithmetic&&left[31]}}。
    assign barrel_fill=shared_rotate?barrel_input:{32{shared_arithmetic&&left[31]}};
    // shared_bit_mask 按 32'b1<<shared_shift_amount 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [31:0] shared_bit_mask=32'b1<<shared_shift_amount;
    // compare_right 保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    // compare_right 按 opcode==7'b0010011 进行来源选择。
    // 真分支取 immediate_i；其余情况取 right。
    wire [31:0] compare_right=opcode==7'b0010011 ?immediate_i:right;
    wire shared_unsigned_less=left<compare_right;
    // shared_signed_less 按 left[31]!=compare_right[31] 进行来源选择。
    // 真分支取 left[31]；其余情况取 shared_unsigned_less。
    wire shared_signed_less=left[31]!=compare_right[31]?left[31]:shared_unsigned_less;
    // shared_add_right 保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    // shared_add_right 按 opcode==7'b0100011 进行来源选择。
    // 真分支取 immediate_s；其余情况取 opcode==7'b0110011 ?right:immediate_i。
    wire [31:0] shared_add_right=opcode==7'b0100011 ?immediate_s:
        // opcode 按 =7'b0110011 进行来源选择。
        // 真分支取 right；其余情况取 immediate_i。
        opcode==7'b0110011 ?right:immediate_i;
    // shared_add_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    // shared_add_left 按 (opcode==7'b0110011&&extension==7'b0010000) 进行来源选择。
    // 真分支取 (sub==2?{left[30:0],1'b0}:sub==4?{left[29:0],2'b0}:{left[28:0],3'b0})；其余情况取 left。
    wire [31:0] shared_add_left=(opcode==7'b0110011&&extension==7'b0010000)?
        (sub==2?{left[30:0],1'b0}:sub==4?{left[29:0],2'b0}:{left[28:0],3'b0}):left;
    // shared_subtract 的资格组合为 opcode==7'b0110011&&extension==7'b0100000&&sub==0。
    wire shared_subtract=opcode==7'b0110011&&extension==7'b0100000&&sub==0;
    // shared_sum 按 shared_add_left+(shared_subtract?~shared_add_right:shared_add_right)+{31'b0,shared_subtract} 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [31:0] shared_sum=shared_add_left+(shared_subtract?~shared_add_right:shared_add_right)+{31'b0,shared_subtract};
    // shared_pc_offset 按 opcode==7'b0010111 进行来源选择。
    // 真分支取 {instruction[31:12],12'b0}；其余情况取 opcode==7'b1101111 ?immediate_j:immediate_b。
    wire [31:0] shared_pc_offset=opcode==7'b0010111 ?{instruction[31:12],12'b0}:
        // opcode 按 =7'b1101111 进行来源选择。
        opcode==7'b1101111 ?immediate_j:immediate_b;
    // shared_pc_target 按 pc+shared_pc_offset 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [31:0] shared_pc_target=pc+shared_pc_offset;
    // TOPT5: control and memory operations never consume the general ALU's
    // register/immediate selector, Zba left shift or add/subtract selection.
    // Keep the original ALU network for its value output and diagnostic mode.
    // With the core's predecoded ALU enabled, that unused value cone is pruned.
    wire branch_unsigned_less=left<right;
    // branch_signed_less 按 left[31]!=right[31] 进行来源选择。
    // 真分支取 left[31]；其余情况取 branch_unsigned_less。
    wire branch_signed_less=left[31]!=right[31]?left[31]:branch_unsigned_less;
    // control_address_rhs 按 opcode==7'b0100011 进行来源选择。
    // 真分支取 immediate_s；其余情况取 immediate_i。
    wire [31:0] control_address_rhs=opcode==7'b0100011 ? immediate_s:immediate_i;
    // control_address_sum 按 left+control_address_rhs 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [31:0] control_address_sum=left+control_address_rhs;
    // control_pc_offset 按 opcode==7'b1101111 进行来源选择。
    // 真分支取 immediate_j；其余情况取 immediate_b。
    wire [31:0] control_pc_offset=opcode==7'b1101111 ? immediate_j:immediate_b;
    // sequential_target 按 pc+32'd4 计算，运算位宽与有无符号以原声明和显式扩展为准。
    assign sequential_target=pc+32'd4;
    // branch_jump_target 按 pc+control_pc_offset 计算，运算位宽与有无符号以原声明和显式扩展为准。
    assign branch_jump_target=pc+control_pc_offset;
    // indirect_jump_target 对 control_address_sum&32'hfffffffe 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    assign indirect_jump_target=control_address_sum&32'hfffffffe;
`ifdef VERILATOR
    always @*begin
        if(opcode==7'b1100011&&
            (branch_unsigned_less!=shared_unsigned_less||branch_signed_less!=shared_signed_less))
            $fatal(1,"TOPT5 dedicated branch comparison differs from original shared comparison");
        if((opcode==7'b0000011||opcode==7'b0100011||opcode==7'b1100111)&&
            control_address_sum!=shared_sum)
            $fatal(1,"TOPT5 dedicated address addition differs from original shared addition");
        if((opcode==7'b1100011||opcode==7'b1101111)&&branch_jump_target!=shared_pc_target)
            $fatal(1,"TOPT5 dedicated control target differs from original shared PC target");
    end
`endif
    // Balanced count trees avoid a 32-deep chain in FPGA LUT fabric.
`ifdef VERILATOR
    function [5:0] leading_zeroes_reference;
        input [31:0] word;
        reg [31:0] shifted;
        reg [5:0] amount;
        begin
            // shifted 连接到 word，两者在此路径上保持字段对应。
            shifted=word;amount=0;
            if(shifted[31:16]==0)begin amount=amount+16;shifted=shifted<<16;end
            if(shifted[31:24]==0)begin amount=amount+8;shifted=shifted<<8;end
            if(shifted[31:28]==0)begin amount=amount+4;shifted=shifted<<4;end
            if(shifted[31:30]==0)begin amount=amount+2;shifted=shifted<<2;end
            if(shifted[31]==0)amount=amount+1;
            // leading_zeroes_reference 按 (word==0) 进行来源选择。
            // 真分支取 6'd32；其余情况取 amount。
            leading_zeroes_reference=(word==0)?6'd32:amount;
        end
    endfunction
`endif
    // A balanced priority tree carries only valid/index information.
    // Its highest occupied leaf is the most significant set bit; inverting
    // that5-bit index gives CLZ. CTZ still uses the original bit reversal.
    function [5:0] leading_zeroes;
        input [31:0] word;
        // subtree_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
        reg [63:1] subtree_valid;
        reg [4:0] position[1:63];
        integer k;
        begin
            for(k=0;k<32;k=k+1)begin subtree_valid[32+k]=word[k];position[32+k]=k[4:0];end
            for(k=31;k>0;k=k-1)begin
                // subtree_valid[k] 的资格组合为 subtree_valid[2*k]||subtree_valid[2*k+1]。
                subtree_valid[k]=subtree_valid[2*k]||subtree_valid[2*k+1];
                // position[k] 按 subtree_valid[2*k+1] 进行来源选择。
                // 真分支取 position[2*k+1]；其余情况取 position[2*k]。
                position[k]=subtree_valid[2*k+1]?position[2*k+1]:position[2*k];
            end
            // leading_zeroes 按 subtree_valid[1] 进行来源选择。
            // 真分支取 {1'b0,~position[1]}；其余情况取 6'd32。
            leading_zeroes=subtree_valid[1]?{1'b0,~position[1]}:6'd32;
`ifdef VERILATOR
            if(leading_zeroes!=leading_zeroes_reference(word))
                $fatal(1,"R39 priority encoder differs from original zero-count function");
`endif
        end
    endfunction
    function [5:0] trailing_zeroes;
        input [31:0] word;
        reg [31:0] reversed;
        integer k;
        begin
            for(k=0;k<32;k=k+1)reversed[k]=word[31-k];
            trailing_zeroes=leading_zeroes(reversed);
        end
    endfunction
    function [5:0] population;
        input [31:0] word;
        reg [1:0] pairs[0:15];
        reg [2:0] quads[0:7];
        reg [3:0] octets[0:3];
        reg [4:0] halves[0:1];
        integer k;
        begin
            for(k=0;k<16;k=k+1)pairs[k]={1'b0,word[2*k]}+{1'b0,word[2*k+1]};
            for(k=0;k<8;k=k+1)quads[k]={1'b0,pairs[2*k]}+{1'b0,pairs[2*k+1]};
            for(k=0;k<4;k=k+1)octets[k]={1'b0,quads[2*k]}+{1'b0,quads[2*k+1]};
            for(k=0;k<2;k=k+1)halves[k]={1'b0,octets[2*k]}+{1'b0,octets[2*k+1]};
            // population 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
            // 拼接源为 {1'b0,halves[0]}+{1'b0,halves[1]}；复制大括号表示重复位域，不是独立队列元素。
            population={1'b0,halves[0]}+{1'b0,halves[1]};
        end
    endfunction
    // source1 读取 instruction[19:15] 所选位域；位索引按声明中的高低位顺序解释。
    assign source1 = instruction[19:15];
    // source2 读取 instruction[24:20] 所选位域；位索引按声明中的高低位顺序解释。
    assign source2 = instruction[24:20];
    // destination 读取 instruction[11:7] 所选位域；位索引按声明中的高低位顺序解释。
    assign destination = instruction[11:7];
    // arithmetic_operation 连接到 sub，两者在此路径上保持字段对应。
    assign arithmetic_operation = sub;
    // csr_number 读取 instruction[31:20] 所选位域；位索引按声明中的高低位顺序解释。
    assign csr_number = instruction[31:20];
    always @* begin
        uses_source1=0; uses_source2=0; writes_destination=0;
        value=0; address=0; store_value=right; next_pc=sequential_target;
        memory=0; memory_write=0; memory_size=0; memory_unsigned=0;
        arithmetic=0; control=0; conditional=0; taken=0;
        csr=0; csr_write=0; csr_new_value=csr_value; system_operation=0;
        illegal=0;
        case (opcode)
            // 此 opcode 分支处理 LUI 高位立即数。
            // funct 子字段继续区分具体操作，未支持编码仍需进入非法指令处理。
            7'b0110111: begin writes_destination=1; value={instruction[31:12],12'b0}; end
            // 此 opcode 分支处理 AUIPC PC 相对加法。
            7'b0010111: begin writes_destination=1; value=shared_pc_target; end
            // 此 opcode 分支处理 JAL 直接跳转。
            7'b1101111: begin
                writes_destination=1; value=sequential_target; next_pc=branch_jump_target;
                control=1; taken=1;
            end
            // 此 opcode 分支处理 JALR 间接跳转。
            7'b1100111: begin
                uses_source1=1; writes_destination=1; value=sequential_target;
                // next_pc 连接到 indirect_jump_target，两者在此路径上保持字段对应。
                next_pc=indirect_jump_target; control=1; taken=1;
                if(sub!=0) illegal=1;
            end
            // 此 opcode 分支处理 条件分支。
            7'b1100011: begin
                uses_source1=1; uses_source2=1; control=1; conditional=1;
                case(sub)
                    0: taken=(left==right);
                    1: taken=(left!=right);
                    4: taken=branch_signed_less;
                    5: taken=!branch_signed_less;
                    6: taken=branch_unsigned_less;
                    7: taken=!branch_unsigned_less;
                    default: illegal=1;
                endcase
                if(taken) next_pc=branch_jump_target;
            end
            // 此 opcode 分支处理 load 访存读取。
            7'b0000011: begin
                uses_source1=1; writes_destination=1; memory=1;
                // address 连接到 control_address_sum，两者在此路径上保持字段对应。
                address=control_address_sum; memory_size=sub[1:0]; memory_unsigned=sub[2];
                if(sub==3 || sub==6 || sub==7) illegal=1;
            end
            // 此 opcode 分支处理 原子访存。
            7'b0101111: begin
                // RV32A requests are serialized by the core and completed by
                // the post-translation atomic adapter, including LR/SC status.
                uses_source1=1;uses_source2=instruction[31:27]!=5'b00010;
                writes_destination=1;memory=1;memory_size=2;address=left;
                // memory_write 由比较式 instruction[31:27]!=5'b00010 产生；该结果是条件判断，不是被比较的数据。
                memory_write=instruction[31:27]!=5'b00010;
                if(sub!=2)illegal=1;
                case(instruction[31:27])
                    5'b00010:if(source2!=0)illegal=1;
                    5'b00011,5'b00001,5'b00000,5'b00100,5'b01100,5'b01000,
                    5'b10000,5'b10100,5'b11000,5'b11100:begin end
                    default:illegal=1;
                endcase
            end
            // 此 opcode 分支处理 store 访存写入。
            7'b0100011: begin
                uses_source1=1; uses_source2=1; memory=1; memory_write=1;
                address=control_address_sum; memory_size=sub[1:0];
                if(sub>2) illegal=1;
            end
            // 此 opcode 分支处理 整数立即数运算。
            7'b0010011: begin
                uses_source1=1; writes_destination=1;
                case(sub)
                    0: value=shared_sum;
                    2: value={31'b0,shared_signed_less};
                    3: value={31'b0,shared_unsigned_less};
                    4: value=left^immediate_i;
                    6: value=left|immediate_i;
                    7: value=left&immediate_i;
                    1: begin
                        case(extension)
                            7'b0000000: value=shared_shift_value;
                            7'b0010100: value=left|shared_bit_mask;
                            7'b0100100: value=left&~shared_bit_mask;
                            7'b0110100: value=left^shared_bit_mask;
                            7'b0110000: begin
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
                        case(extension)
                            7'b0000000: value=shared_shift_value;
                            7'b0100000: value=shared_shift_value;
                            7'b0110000: value=shared_shift_value;
                            7'b0100100: value={31'b0,shared_shift_value[0]};
                            7'b0010100: begin
                                if(immediate_shift!=7) illegal=1;
                                // value 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
                                value={{8{|left[31:24]}},{8{|left[23:16]}},{8{|left[15:8]}},{8{|left[7:0]}}};
                            end
                            7'b0110100: begin
                                if(immediate_shift!=24) illegal=1;
                                value={left[7:0],left[15:8],left[23:16],left[31:24]};
                            end
                            default: illegal=1;
                        endcase
                    end
                    default: illegal=1;
                endcase
            end
            // 此 opcode 分支处理 整数寄存器运算及扩展算术。
            7'b0110011: begin
                uses_source1=1; uses_source2=1; writes_destination=1;
                case(extension)
                    7'b0000001: arithmetic=1;
                    7'b0000000: begin
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
                        case(sub)
                            1:value=shared_shift_value;
                            5:value=shared_shift_value;
                            default:illegal=1;
                        endcase
                    end
                    7'b0000101: begin
                        case(sub)
                            4:value=shared_signed_less?left:right;
                            5:value=shared_unsigned_less?left:right;
                            6:value=!shared_signed_less?left:right;
                            7:value=!shared_unsigned_less?left:right;
                            default:illegal=1;
                        endcase
                    end
                    7'b0010000: begin
                        case(sub)
                            2:value=shared_sum;
                            4:value=shared_sum;
                            6:value=shared_sum;
                            default:illegal=1;
                        endcase
                    end
                    7'b0000100: begin
                        if(sub==4 && source2==0) begin value={16'b0,left[15:0]}; uses_source2=0; end
                        else illegal=1;
                    end
                    7'b0010100: if(sub==1) value=left|shared_bit_mask; else illegal=1;
                    7'b0100100: begin
                        if(sub==1) value=left&~shared_bit_mask;
                        else if(sub==5) value={31'b0,shared_shift_value[0]};
                        else illegal=1;
                    end
                    7'b0110100: if(sub==1) value=left^shared_bit_mask; else illegal=1;
                    default:illegal=1;
                endcase
            end
            // 此 opcode 分支处理 FENCE 与指令流维护。
            7'b0001111: begin
                if(instruction==32'h0000500f) system_operation=6;
                else if(sub==1) system_operation=1;
                else if(sub==0) system_operation=6;
                else illegal=1;
            end
            // 此 opcode 分支处理 CSR 与特权系统指令。
            7'b1110011: begin
                if(sub==0) begin
                    case(instruction)
                        32'h00000073:system_operation=3;
                        32'h00100073:system_operation=4;
                        32'h30200073:system_operation=2;
                        32'h10200073:system_operation=7;
                        32'h10500073:system_operation=5;
                        default:begin
                            if((instruction&32'hfe007fff)==32'h12000073) system_operation=1;
                            else illegal=1;
                        end
                    endcase
                end else begin
                    csr=1; writes_destination=1; uses_source1=!sub[2]; value=csr_value;
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

// TOPT3: instruction-only value controls are generated before the existing
// queue/EX boundaries. The original decoder above remains the architectural
// reference for every other result and for illegal-instruction semantics.
//
// [20:0] one-hot-or-zero result family:
//  0 sum       1 PC+U      2 PC+4      3 U          4 less
//  5 AND       6 OR        7 XOR       8 shift-R    9 shift-L
// 10 bit-extract          11 CLZ      12 CTZ       13 CPOP
// 14 sign-byte 15 sign-half          16 zero-half
// 17 ORC.B     18 REV8     19 min/max  20 CSR
// [21] immediate RHS     [22] bit-mask logic RHS
// [23] invert logic RHS  [24] invert XOR result  [25] subtract
// [26] unsigned compare  [27] maximum           [28] rotate
// [29] arithmetic right shift                  [31:30] Zba add-left shift
module rv32_alu_predecode(
    input [31:0] instruction,
    output reg [31:0] control
);
    wire [6:0] opcode=instruction[6:0];
    wire [2:0] sub=instruction[14:12];
    wire [6:0] extension=instruction[31:25];
    wire [4:0] immediate_shift=instruction[24:20];
    always @*begin
        control=32'b0;
        case(opcode)
            7'b0110111:control[3]=1;
            7'b0010111:control[1]=1;
            // Invalid JALR funct3 still produces PC+4 in the reference.
            7'b1101111,7'b1100111:control[2]=1;
            7'b0010011:begin
                control[21]=1;
                case(sub)
                    0:control[0]=1;
                    2:control[4]=1;
                    3:begin control[4]=1;control[26]=1;end
                    4:control[7]=1;
                    6:control[6]=1;
                    7:control[5]=1;
                    1:begin
                        case(extension)
                            7'b0000000:control[9]=1;
                            7'b0010100:begin control[6]=1;control[22]=1;end
                            7'b0100100:begin control[5]=1;control[22]=1;control[23]=1;end
                            7'b0110100:begin control[7]=1;control[22]=1;end
                            7'b0110000:begin
                                case(immediate_shift)
                                    0:control[11]=1;
                                    1:control[12]=1;
                                    2:control[13]=1;
                                    4:control[14]=1;
                                    5:control[15]=1;
                                    default:begin end
                                endcase
                            end
                            default:begin end
                        endcase
                    end
                    5:begin
                        case(extension)
                            7'b0000000:control[8]=1;
                            7'b0100000:begin control[8]=1;control[29]=1;end
                            7'b0110000:begin control[8]=1;control[28]=1;end
                            7'b0100100:control[10]=1;
                            // The reference assigns these values even when
                            // the immediate subencoding also raises illegal.
                            7'b0010100:control[17]=1;
                            7'b0110100:control[18]=1;
                            default:begin end
                        endcase
                    end
                    default:begin end
                endcase
            end
            7'b0110011:begin
                case(extension)
                    // RV32M's value is zero here; the separate MDU owns its
                    // actual result. No arithmetic admission/latency changes.
                    7'b0000001:begin end
                    7'b0000000:begin
                        case(sub)
                            0:control[0]=1;
                            1:control[9]=1;
                            2:control[4]=1;
                            3:begin control[4]=1;control[26]=1;end
                            4:control[7]=1;
                            5:control[8]=1;
                            6:control[6]=1;
                            7:control[5]=1;
                        endcase
                    end
                    7'b0100000:begin
                        case(sub)
                            0:begin control[0]=1;control[25]=1;end
                            4:begin control[7]=1;control[24]=1;end
                            5:begin control[8]=1;control[29]=1;end
                            6:begin control[6]=1;control[23]=1;end
                            7:begin control[5]=1;control[23]=1;end
                            default:begin end
                        endcase
                    end
                    7'b0110000:begin
                        case(sub)
                            1:begin control[9]=1;control[28]=1;end
                            5:begin control[8]=1;control[28]=1;end
                            default:begin end
                        endcase
                    end
                    7'b0000101:begin
                        case(sub)
                            4,5,6,7:begin
                                control[19]=1;
                                // control[26] 读取 sub[0] 所选位域；位索引按声明中的高低位顺序解释。
                                control[26]=sub[0];control[27]=sub[1];
                            end
                            default:begin end
                        endcase
                    end
                    7'b0010000:begin
                        case(sub)
                            2:begin control[0]=1;control[31:30]=1;end
                            4:begin control[0]=1;control[31:30]=2;end
                            6:begin control[0]=1;control[31:30]=3;end
                            default:begin end
                        endcase
                    end
                    7'b0000100:if(sub==4&&immediate_shift==0)control[16]=1;
                    7'b0010100:if(sub==1)begin control[6]=1;control[22]=1;end
                    7'b0100100:begin
                        if(sub==1)begin control[5]=1;control[22]=1;control[23]=1;end
                        else if(sub==5)control[10]=1;
                    end
                    7'b0110100:if(sub==1)begin control[7]=1;control[22]=1;end
                    default:begin end
                endcase
            end
            // Preserve funct3=100's CSR read value even though it is illegal.
            7'b1110011:if(sub!=0)control[20]=1;
            default:begin end
        endcase
    end
endmodule

// Only decoded controls and immediate DATA enter this result datapath.
// In the core, control travels through the same existing EX boundary as the
// instruction and operands. Do not combinationally decode the late issue
// instruction at this interface: that would move the old bottleneck upstream.
module rv32_alu_value #(
    parameter DUAL_BARREL=1
)(
    input [31:0] control,pc,left,right,csr_value,immediate_i,immediate_u,
    input [4:0] immediate_shift,
    output [31:0] value
);
    // rhs 按 control[21] 进行来源选择。
    wire [31:0] rhs=control[21]?immediate_i:right;
    // shift_amount 按 control[21] 进行来源选择。
    // 真分支取 immediate_shift；其余情况取 right[4:0]。
    wire [4:0] shift_amount=control[21]?immediate_shift:right[4:0];
    // bit_mask 按 32'b1<<shift_amount 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [31:0] bit_mask=32'b1<<shift_amount;
    // Resolve small control choices before applying them to wide operands.
    // logic_use_register 的资格组合为 !control[22]&&!control[21]。
    wire logic_use_register=!control[22]&&!control[21];
    // logic_use_immediate 的资格组合为 !control[22]&&control[21]。
    wire logic_use_immediate=!control[22]&&control[21];
    // logic_use_mask 读取 control[22] 所选位域；位索引按声明中的高低位顺序解释。
    wire logic_use_mask=control[22];
    // logic_rhs_source 对 ({32{logic_use_register}}&right)| ({32{logic_use_immediate}}&immediate_i)|({32{logic_use_mask}}&bit_mask) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [31:0] logic_rhs_source=({32{logic_use_register}}&right)|
        ({32{logic_use_immediate}}&immediate_i)|({32{logic_use_mask}}&bit_mask);
    // logic_rhs 对 logic_rhs_source^{32{control[23]}} 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [31:0] logic_rhs=logic_rhs_source^{32{control[23]}};
    // add_left_select 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {control[31:30]==3,control[31:30]==2,；复制大括号表示重复位域，不是独立队列元素。
    wire [3:0] add_left_select={control[31:30]==3,control[31:30]==2,
        // control[31:30] 由比较式 =1,control[31:30]==0} 产生；该结果是条件判断，不是被比较的数据。
        control[31:30]==1,control[31:30]==0};
    // add_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    wire [31:0] add_left=({32{add_left_select[0]}}&left)|
        ({32{add_left_select[1]}}&{left[30:0],1'b0})|
        ({32{add_left_select[2]}}&{left[29:0],2'b0})|
        ({32{add_left_select[3]}}&{left[28:0],3'b0});
    // sum 按 add_left+(rhs^{32{control[25]}})+{31'b0,control[25]} 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [31:0] sum=add_left+(rhs^{32{control[25]}})+{31'b0,control[25]};
    wire unsigned_less=left<rhs;
    // signed_less 按 left[31]!=rhs[31] 进行来源选择。
    // 真分支取 left[31]；其余情况取 unsigned_less。
    wire signed_less=left[31]!=rhs[31]?left[31]:unsigned_less;
    // less 按 control[26] 进行来源选择。
    // 真分支取 unsigned_less；其余情况取 signed_less。
    wire less=control[26]?unsigned_less:signed_less;
    // minmax_value 按 (less^control[27]) 进行来源选择。
    // 真分支取 left；其余情况取 right。
    wire [31:0] minmax_value=(less^control[27])?left:right;
    // reverse_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    wire [31:0] reverse_left;
    // Selected shift terms enter the final result OR directly. The fixed
    // cyclic networks do not depend on rotate, arithmetic-fill or family bits.
    wire [31:0] shift_right_result,shift_left_result;
    wire bit_extract;
    genvar bit_index;
    generate for(bit_index=0;bit_index<32;bit_index=bit_index+1)begin:input_reverse
        // reverse_left[bit_index] 读取 left[31-bit_index] 所选位域；位索引按声明中的高低位顺序解释。
        assign reverse_left[bit_index]=left[31-bit_index];
    end
    if(DUAL_BARREL)begin:fixed_direction_barrels
        // TOPT6: rotate first using only data/shift amount. Truncation and
        // arithmetic fill are output masks, so control[28] never precedes
        // the five variable-shift stages. Fold the family bit into each
        // mask rather than placing a second data gate after the shift result.
        // right_rotated 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
        // 拼接源为 {left,left}>>shift_amount；复制大括号表示重复位域，不是独立队列元素。
        wire [63:0] right_rotated={left,left}>>shift_amount;
        // reversed_rotated 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
        // 拼接源为 {reverse_left,reverse_left}>>shift_amount；复制大括号表示重复位域，不是独立队列元素。
        wire [63:0] reversed_rotated={reverse_left,reverse_left}>>shift_amount;
        for(bit_index=0;bit_index<32;bit_index=bit_index+1)begin:output_masks
            localparam [4:0] RIGHT_LIMIT=31-bit_index;
            // LEFT_LIMIT 连接到 bit_index，两者在此路径上保持字段对应。
            localparam [4:0] LEFT_LIMIT=bit_index;
            // right_in_range 由比较式 (shift_amount<=RIGHT_LIMIT) 产生；该结果是条件判断，不是被比较的数据。
            wire right_in_range=(shift_amount<=RIGHT_LIMIT);
            // left_in_range 由比较式 (shift_amount<=LEFT_LIMIT) 产生；该结果是条件判断，不是被比较的数据。
            wire left_in_range=(shift_amount<=LEFT_LIMIT);
            // right_data_enable 保存功能或输出使能，控制资格而非实际吞吐测量值。
            // right_data_enable 的资格组合为 control[8]&&(control[28]||right_in_range)。
            wire right_data_enable=control[8]&&(control[28]||right_in_range);
            // right_sign_enable 保存功能或输出使能，控制资格而非实际吞吐测量值。
            // right_sign_enable 的资格组合为 control[8]&&!control[28]&&control[29]&&!right_in_range。
            wire right_sign_enable=control[8]&&!control[28]&&control[29]&&!right_in_range;
            // left_data_enable 保存功能或输出使能，控制资格而非实际吞吐测量值。
            // left_data_enable 的资格组合为 control[9]&&(control[28]||left_in_range)。
            wire left_data_enable=control[9]&&(control[28]||left_in_range);
            assign shift_right_result[bit_index]=
                (right_rotated[bit_index]&&right_data_enable)||
                (left[31]&&right_sign_enable);
            assign shift_left_result[bit_index]=
                reversed_rotated[31-bit_index]&&left_data_enable;
        end
        // With a five-bit amount, bit zero always reads left[shift_amount];
        // it never crosses into a fill bit, even for arbitrary control words.
        // bit_extract 读取 right_rotated[0] 所选位域；位索引按声明中的高低位顺序解释。
        assign bit_extract=right_rotated[0];
    end else begin:shared_direction_barrel
        // Preserve the diagnostic shared-direction network's exact behavior,
        // including arbitrary/multiple family bits rather than only ISA use.
        // barrel_input 按 control[9] 进行来源选择。
        // 真分支取 reverse_left；其余情况取 left。
        wire [31:0] barrel_input=control[9]?reverse_left:left;
        // barrel_fill 按 control[28] 进行来源选择。
        // 真分支取 barrel_input；其余情况取 {32{control[29]&&left[31]}}。
        wire [31:0] barrel_fill=control[28]?barrel_input:{32{control[29]&&left[31]}};
        // shifted 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
        // 拼接源为 {barrel_fill,barrel_input}>>shift_amount；复制大括号表示重复位域，不是独立队列元素。
        wire [63:0] shifted={barrel_fill,barrel_input}>>shift_amount;
        wire [31:0] shared_value;
        for(bit_index=0;bit_index<32;bit_index=bit_index+1)begin:output_direction
            // shared_value[bit_index] 按 control[9] 进行来源选择。
            // 真分支取 shifted[31-bit_index]；其余情况取 shifted[bit_index]。
            assign shared_value[bit_index]=control[9]?shifted[31-bit_index]:shifted[bit_index];
        end
        // shift_right_result 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
        // 拼接源为 {32{control[8]}}&shared_value；复制大括号表示重复位域，不是独立队列元素。
        assign shift_right_result={32{control[8]}}&shared_value;
        // shift_left_result 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
        // 拼接源为 {32{control[9]}}&shared_value；复制大括号表示重复位域，不是独立队列元素。
        assign shift_left_result={32{control[9]}}&shared_value;
        // bit_extract 读取 shared_value[0] 所选位域；位索引按声明中的高低位顺序解释。
        assign bit_extract=shared_value[0];
    end endgenerate

    // Retain the reference's balanced count implementations. The changed
    // part is their predecoded selection, not their arithmetic semantics.
    function [5:0] leading_zeroes;
        input [31:0] word;
        reg [63:1] subtree_valid;
        reg [4:0] position[1:63];
        integer k;
        begin
            for(k=0;k<32;k=k+1)begin subtree_valid[32+k]=word[k];position[32+k]=k[4:0];end
            for(k=31;k>0;k=k-1)begin
                subtree_valid[k]=subtree_valid[2*k]||subtree_valid[2*k+1];
                position[k]=subtree_valid[2*k+1]?position[2*k+1]:position[2*k];
            end
            leading_zeroes=subtree_valid[1]?{1'b0,~position[1]}:6'd32;
        end
    endfunction
    function [5:0] trailing_zeroes;
        input [31:0] word;
        reg [31:0] reversed;
        integer k;
        begin
            for(k=0;k<32;k=k+1)reversed[k]=word[31-k];
            trailing_zeroes=leading_zeroes(reversed);
        end
    endfunction
    function [5:0] population;
        input [31:0] word;
        reg [1:0] pairs[0:15];
        reg [2:0] quads[0:7];
        reg [3:0] octets[0:3];
        reg [4:0] halves[0:1];
        integer k;
        begin
            for(k=0;k<16;k=k+1)pairs[k]={1'b0,word[2*k]}+{1'b0,word[2*k+1]};
            for(k=0;k<8;k=k+1)quads[k]={1'b0,pairs[2*k]}+{1'b0,pairs[2*k+1]};
            for(k=0;k<4;k=k+1)octets[k]={1'b0,quads[2*k]}+{1'b0,quads[2*k+1]};
            for(k=0;k<2;k=k+1)halves[k]={1'b0,octets[2*k]}+{1'b0,octets[2*k+1]};
            population={1'b0,halves[0]}+{1'b0,halves[1]};
        end
    endfunction
    // orcb 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {{8{|left[31:24]}},{8{|left[23:16]}},{8{|left[15:8]}},{8{|left[7:0]}}}；复制大括号表示重复位域，不是独立队列元素。
    wire [31:0] orcb={{8{|left[31:24]}},{8{|left[23:16]}},{8{|left[15:8]}},{8{|left[7:0]}}};
    // reverse_bytes 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {left[7:0],left[15:8],left[23:16],left[31:24]}；复制大括号表示重复位域，不是独立队列元素。
    wire [31:0] reverse_bytes={left[7:0],left[15:8],left[23:16],left[31:24]};
    // A complete parallel one-hot result reduction; no priority case over
    // opcode/funct fields remains after the EX control register.
    // value 对 ({32{control[0]}}&sum)| 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    assign value=({32{control[0]}}&sum)|
        ({32{control[1]}}&(pc+immediate_u))|
        ({32{control[2]}}&(pc+32'd4))|
        ({32{control[3]}}&immediate_u)|
        ({32{control[4]}}&{31'b0,less})|
        ({32{control[5]}}&(left&logic_rhs))|
        ({32{control[6]}}&(left|logic_rhs))|
        ({32{control[7]}}&((left^logic_rhs)^{32{control[24]}}))|
        shift_right_result|
        shift_left_result|
        ({32{control[10]}}&{31'b0,bit_extract})|
        ({32{control[11]}}&{26'b0,leading_zeroes(left)})|
        ({32{control[12]}}&{26'b0,trailing_zeroes(left)})|
        ({32{control[13]}}&{26'b0,population(left)})|
        ({32{control[14]}}&{{24{left[7]}},left[7:0]})|
        ({32{control[15]}}&{{16{left[15]}},left[15:0]})|
        ({32{control[16]}}&{16'b0,left[15:0]})|
        ({32{control[17]}}&orcb)|
        ({32{control[18]}}&reverse_bytes)|
        ({32{control[19]}}&minmax_value)|
        ({32{control[20]}}&csr_value);
endmodule
