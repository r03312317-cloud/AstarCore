// S6-derived instruction legality optimization; original decoder is the reference.
// No operand, privilege-state or CSR-existence decisions are moved here.
// 此模块提取指令的源寄存器使用及类别标志，给前端与调度提供早期信息。
// flags 属于译码提示，最终非法指令判断与异常提交仍由执行和核心控制完成。
// AMO 与普通 load store 的源操作数需求不同，必须保留其地址与写数据依赖。
// 不使用的源寄存器不能制造虚假的生产者等待，x0 也不能变为可写目的寄存器。
module rv32_instruction_flags(input [31:0] instruction,output illegal);
    wire [6:0] op=instruction[6:0],ext=instruction[31:25];
    // sub 读取 instruction[14:12] 所选位域；位索引按声明中的高低位顺序解释。
    wire [2:0] sub=instruction[14:12];
    // rs2 读取 instruction[24:20] 所选位域；位索引按声明中的高低位顺序解释。
    wire [4:0] rs2=instruction[24:20];
    // imm_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    // imm_left 的资格组合为 (ext==7'd0||ext==7'd20||ext==7'd36||ext==7'd52|| (ext==7'd48&&(rs2==0||rs2==1||rs2==2||rs2==4||rs2==5)))。
    // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
    wire imm_left=(ext==7'd0||ext==7'd20||ext==7'd36||ext==7'd52||
        (ext==7'd48&&(rs2==0||rs2==1||rs2==2||rs2==4||rs2==5)));
    // imm_right 保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    wire imm_right=(ext==7'd0||ext==7'd32||ext==7'd48||ext==7'd36||
        (ext==7'd20&&rs2==7)||(ext==7'd52&&rs2==24));
    wire imm_legal=(sub!=1&&sub!=5)||(sub==1&&imm_left)||(sub==5&&imm_right);
    wire reg_legal=(ext==0)||(ext==1)||
        (ext==32&&(sub==0||sub>=4))||(ext==48&&(sub==1||sub==5))||
        (ext==5&&sub>=4)||(ext==16&&(sub==2||sub==4||sub==6))||
        (ext==4&&sub==4&&rs2==0)||(ext==20&&sub==1)||
        (ext==36&&(sub==1||sub==5))||(ext==52&&sub==1);
    wire privileged_legal=instruction==32'h00000073||instruction==32'h00100073||
        instruction==32'h30200073||instruction==32'h10200073||instruction==32'h10500073||
        (instruction&32'hfe007fff)==32'h12000073;
    // Parallel accepted-encoding predicates, avoiding a general ALU result
    // decoder's nested priority and output-sharing cones on the BRAM path.
    wire atomic_legal=sub==2 && ((instruction[31:27]==2&&rs2==0)||
        instruction[31:27]==3||instruction[31:27]==1||instruction[31:27]==0||
        instruction[31:27]==4||instruction[31:27]==12||instruction[31:27]==8||
        instruction[31:27]==16||instruction[31:27]==20||instruction[31:27]==24||instruction[31:27]==28);
    wire legal=(op==7'd47&&atomic_legal)||(op==7'd55)||(op==7'd23)||(op==7'd111)||
        (op==7'd103&&sub==0)||(op==7'd99&&sub!=2&&sub!=3)||
        (op==7'd3&&sub!=3&&sub<6)||(op==7'd35&&sub<3)||
        (op==7'd19&&imm_legal)||(op==7'd51&&reg_legal)||
        (op==7'd15&&(sub==0||sub==1||instruction==32'h0000500f))||
        (op==7'd115&&(sub[1:0]!=0||privileged_legal));
    assign illegal=!legal;
endmodule
