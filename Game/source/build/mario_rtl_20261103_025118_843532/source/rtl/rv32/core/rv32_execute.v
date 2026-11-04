// Original RV32 project file; see SOURCE_PROVENANCE.md.
// RV32 instruction semantics. Written from scratch for this project.
// Pure combinational RV32IM_Zba_Zbb_Zbs/Zicsr/Zifencei execution decoder.
module rv32_execute(
    input [31:0] instruction, pc, left, right, csr_value,
    output [4:0] source1, source2, destination,
    output reg uses_source1, uses_source2, writes_destination,
    output reg [31:0] value, address, store_value, next_pc,
    // TOPT5: expose targets already used by the control datapath, so
    // prediction matching can compare in parallel with direction.
    output [31:0] sequential_target,branch_jump_target,indirect_jump_target,
    output reg memory, memory_write,
    output reg [1:0] memory_size,
    output reg memory_unsigned,
    output reg arithmetic,
    output [2:0] arithmetic_operation,
    output reg control, conditional, taken,
    output reg csr, csr_write,
    output reg [31:0] csr_new_value,
    output [11:0] csr_number,
    output reg [2:0] system_operation,
    output reg illegal
);
    wire [6:0] opcode = instruction[6:0];
    wire [2:0] sub = instruction[14:12];
    wire [6:0] extension = instruction[31:25];
    wire [31:0] immediate_i = {{20{instruction[31]}},instruction[31:20]};
    wire [31:0] immediate_s = {{20{instruction[31]}},instruction[31:25],instruction[11:7]};
    wire [31:0] immediate_b = {{19{instruction[31]}},instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0};
    wire [31:0] immediate_j = {{11{instruction[31]}},instruction[31],instruction[19:12],instruction[20],instruction[30:21],1'b0};
    wire [4:0] shift = right[4:0];
    wire [4:0] immediate_shift = instruction[24:20];
    wire [31:0] csr_source = sub[2] ? {27'b0,instruction[19:15]} : left;
    // R50: one barrel network serves register/immediate shifts and rotates.
    // Reversing both ends converts a right barrel into a left barrel.
    // A rotation supplies the input as its upper half; SRA supplies sign.
    wire [4:0] shared_shift_amount=opcode[5]?shift:immediate_shift;
    wire shared_shift_left=sub==1;
    wire shared_rotate=extension==7'b0110000&&
        ((opcode==7'b0110011&&(sub==1||sub==5))||
         (opcode==7'b0010011&&sub==5));
    wire shared_arithmetic=extension==7'b0100000&&sub==5;
    wire [31:0] reversed_left,barrel_input,barrel_fill,shared_shift_value;
    wire [63:0] barrel_shifted={barrel_fill,barrel_input}>>shared_shift_amount;
    wire unused_barrel_upper=|barrel_shifted[63:32];
    genvar shift_bit;
    generate for(shift_bit=0;shift_bit<32;shift_bit=shift_bit+1)begin:shared_barrel
        assign reversed_left[shift_bit]=left[31-shift_bit];
        assign shared_shift_value[shift_bit]=shared_shift_left?
            barrel_shifted[31-shift_bit]:barrel_shifted[shift_bit];
    end endgenerate
    assign barrel_input=shared_shift_left?reversed_left:left;
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
    // TOPT5: control and memory operations never consume the general ALU's
    // register/immediate selector, Zba left shift or add/subtract selection.
    // Keep the original ALU network for its value output and diagnostic mode.
    // With the core's predecoded ALU enabled, that unused value cone is pruned.
    wire branch_unsigned_less=left<right;
    wire branch_signed_less=left[31]!=right[31]?left[31]:branch_unsigned_less;
    wire [31:0] control_address_rhs=opcode==7'b0100011 ? immediate_s:immediate_i;
    wire [31:0] control_address_sum=left+control_address_rhs;
    wire [31:0] control_pc_offset=opcode==7'b1101111 ? immediate_j:immediate_b;
    assign sequential_target=pc+32'd4;
    assign branch_jump_target=pc+control_pc_offset;
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
            shifted=word;amount=0;
            if(shifted[31:16]==0)begin amount=amount+16;shifted=shifted<<16;end
            if(shifted[31:24]==0)begin amount=amount+8;shifted=shifted<<8;end
            if(shifted[31:28]==0)begin amount=amount+4;shifted=shifted<<4;end
            if(shifted[31:30]==0)begin amount=amount+2;shifted=shifted<<2;end
            if(shifted[31]==0)amount=amount+1;
            leading_zeroes_reference=(word==0)?6'd32:amount;
        end
    endfunction
`endif
    // A balanced priority tree carries only valid/index information.
    // Its highest occupied leaf is the most significant set bit; inverting
    // that5-bit index gives CLZ. CTZ still uses the original bit reversal.
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
            population={1'b0,halves[0]}+{1'b0,halves[1]};
        end
    endfunction
    assign source1 = instruction[19:15];
    assign source2 = instruction[24:20];
    assign destination = instruction[11:7];
    assign arithmetic_operation = sub;
    assign csr_number = instruction[31:20];
    always @* begin
        uses_source1=0; uses_source2=0; writes_destination=0;
        value=0; address=0; store_value=right; next_pc=sequential_target;
        memory=0; memory_write=0; memory_size=0; memory_unsigned=0;
        arithmetic=0; control=0; conditional=0; taken=0;
        csr=0; csr_write=0; csr_new_value=csr_value; system_operation=0;
        illegal=0;
        case (opcode)
            7'b0110111: begin writes_destination=1; value={instruction[31:12],12'b0}; end
            7'b0010111: begin writes_destination=1; value=shared_pc_target; end
            7'b1101111: begin
                writes_destination=1; value=sequential_target; next_pc=branch_jump_target;
                control=1; taken=1;
            end
            7'b1100111: begin
                uses_source1=1; writes_destination=1; value=sequential_target;
                next_pc=indirect_jump_target; control=1; taken=1;
                if(sub!=0) illegal=1;
            end
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
            7'b0000011: begin
                uses_source1=1; writes_destination=1; memory=1;
                address=control_address_sum; memory_size=sub[1:0]; memory_unsigned=sub[2];
                if(sub==3 || sub==6 || sub==7) illegal=1;
            end
            7'b0100011: begin
                uses_source1=1; uses_source2=1; memory=1; memory_write=1;
                address=control_address_sum; memory_size=sub[1:0];
                if(sub>2) illegal=1;
            end
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
            7'b0001111: begin
                if(instruction==32'h0000500f) system_operation=6;
                else if(sub==1) system_operation=1;
                else if(sub==0) system_operation=6;
                else illegal=1;
            end
            7'b1110011: begin
                if(sub==0) begin
                    case(instruction)
                        32'h00000073:system_operation=3;
                        32'h00100073:system_operation=4;
                        32'h30200073:system_operation=2;
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
    wire [31:0] rhs=control[21]?immediate_i:right;
    wire [4:0] shift_amount=control[21]?immediate_shift:right[4:0];
    wire [31:0] bit_mask=32'b1<<shift_amount;
    // Resolve small control choices before applying them to wide operands.
    wire logic_use_register=!control[22]&&!control[21];
    wire logic_use_immediate=!control[22]&&control[21];
    wire logic_use_mask=control[22];
    wire [31:0] logic_rhs_source=({32{logic_use_register}}&right)|
        ({32{logic_use_immediate}}&immediate_i)|({32{logic_use_mask}}&bit_mask);
    wire [31:0] logic_rhs=logic_rhs_source^{32{control[23]}};
    wire [3:0] add_left_select={control[31:30]==3,control[31:30]==2,
        control[31:30]==1,control[31:30]==0};
    wire [31:0] add_left=({32{add_left_select[0]}}&left)|
        ({32{add_left_select[1]}}&{left[30:0],1'b0})|
        ({32{add_left_select[2]}}&{left[29:0],2'b0})|
        ({32{add_left_select[3]}}&{left[28:0],3'b0});
    wire [31:0] sum=add_left+(rhs^{32{control[25]}})+{31'b0,control[25]};
    wire unsigned_less=left<rhs;
    wire signed_less=left[31]!=rhs[31]?left[31]:unsigned_less;
    wire less=control[26]?unsigned_less:signed_less;
    wire [31:0] minmax_value=(less^control[27])?left:right;
    wire [31:0] reverse_left;
    // Selected shift terms enter the final result OR directly. The fixed
    // cyclic networks do not depend on rotate, arithmetic-fill or family bits.
    wire [31:0] shift_right_result,shift_left_result;
    wire bit_extract;
    genvar bit_index;
    generate for(bit_index=0;bit_index<32;bit_index=bit_index+1)begin:input_reverse
        assign reverse_left[bit_index]=left[31-bit_index];
    end
    if(DUAL_BARREL)begin:fixed_direction_barrels
        // TOPT6: rotate first using only data/shift amount. Truncation and
        // arithmetic fill are output masks, so control[28] never precedes
        // the five variable-shift stages. Fold the family bit into each
        // mask rather than placing a second data gate after the shift result.
        wire [63:0] right_rotated={left,left}>>shift_amount;
        wire [63:0] reversed_rotated={reverse_left,reverse_left}>>shift_amount;
        for(bit_index=0;bit_index<32;bit_index=bit_index+1)begin:output_masks
            localparam [4:0] RIGHT_LIMIT=31-bit_index;
            localparam [4:0] LEFT_LIMIT=bit_index;
            wire right_in_range=(shift_amount<=RIGHT_LIMIT);
            wire left_in_range=(shift_amount<=LEFT_LIMIT);
            wire right_data_enable=control[8]&&(control[28]||right_in_range);
            wire right_sign_enable=control[8]&&!control[28]&&control[29]&&!right_in_range;
            wire left_data_enable=control[9]&&(control[28]||left_in_range);
            assign shift_right_result[bit_index]=
                (right_rotated[bit_index]&&right_data_enable)||
                (left[31]&&right_sign_enable);
            assign shift_left_result[bit_index]=
                reversed_rotated[31-bit_index]&&left_data_enable;
        end
        // With a five-bit amount, bit zero always reads left[shift_amount];
        // it never crosses into a fill bit, even for arbitrary control words.
        assign bit_extract=right_rotated[0];
    end else begin:shared_direction_barrel
        // Preserve the diagnostic shared-direction network's exact behavior,
        // including arbitrary/multiple family bits rather than only ISA use.
        wire [31:0] barrel_input=control[9]?reverse_left:left;
        wire [31:0] barrel_fill=control[28]?barrel_input:{32{control[29]&&left[31]}};
        wire [63:0] shifted={barrel_fill,barrel_input}>>shift_amount;
        wire [31:0] shared_value;
        for(bit_index=0;bit_index<32;bit_index=bit_index+1)begin:output_direction
            assign shared_value[bit_index]=control[9]?shifted[31-bit_index]:shifted[bit_index];
        end
        assign shift_right_result={32{control[8]}}&shared_value;
        assign shift_left_result={32{control[9]}}&shared_value;
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
    wire [31:0] orcb={{8{|left[31:24]}},{8{|left[23:16]}},{8{|left[15:8]}},{8{|left[7:0]}}};
    wire [31:0] reverse_bytes={left[7:0],left[15:8],left[23:16],left[31:24]};
    // A complete parallel one-hot result reduction; no priority case over
    // opcode/funct fields remains after the EX control register.
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
