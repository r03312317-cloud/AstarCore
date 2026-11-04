// S6-derived instruction legality optimization; original decoder is the reference.
// No operand, privilege-state or CSR-existence decisions are moved here.
module rv32_instruction_flags(input [31:0] instruction,output illegal);
    wire [6:0] op=instruction[6:0],ext=instruction[31:25];
    wire [2:0] sub=instruction[14:12];
    wire [4:0] rs2=instruction[24:20];
    wire imm_left=(ext==7'd0||ext==7'd20||ext==7'd36||ext==7'd52||
        (ext==7'd48&&(rs2==0||rs2==1||rs2==2||rs2==4||rs2==5)));
    wire imm_right=(ext==7'd0||ext==7'd32||ext==7'd48||ext==7'd36||
        (ext==7'd20&&rs2==7)||(ext==7'd52&&rs2==24));
    wire imm_legal=(sub!=1&&sub!=5)||(sub==1&&imm_left)||(sub==5&&imm_right);
    wire reg_legal=(ext==0)||(ext==1)||
        (ext==32&&(sub==0||sub>=4))||(ext==48&&(sub==1||sub==5))||
        (ext==5&&sub!=0)||(ext==16&&(sub==2||sub==4||sub==6))||
        (ext==4&&sub==4&&rs2==0)||(ext==20&&sub==1)||
        (ext==36&&(sub==1||sub==5))||(ext==52&&sub==1);
    wire privileged_legal=instruction==32'h00000073||instruction==32'h00100073||
        instruction==32'h30200073||instruction==32'h10500073||
        (instruction&32'hfe007fff)==32'h12000073;
    // Parallel accepted-encoding predicates, avoiding a general ALU result
    // decoder's nested priority and output-sharing cones on the BRAM path.
    wire legal=(op==7'd55)||(op==7'd23)||(op==7'd111)||
        (op==7'd103&&sub==0)||(op==7'd99&&sub!=2&&sub!=3)||
        (op==7'd3&&sub!=3&&sub<6)||(op==7'd35&&sub<3)||
        (op==7'd19&&imm_legal)||(op==7'd51&&reg_legal)||
        (op==7'd15&&(sub==0||sub==1||instruction==32'h0000500f))||
        (op==7'd115&&(sub[1:0]!=0||privileged_legal));
    assign illegal=!legal;
endmodule
