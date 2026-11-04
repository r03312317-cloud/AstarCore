module dc_realtime_core_decode (
    input  logic [31:0] instruction,
    output logic        legal,
    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [4:0]  rd,
    output logic        rd_write,
    output dc_realtime_core_pkg::dc_rt_alu_op_e alu_op,
    output logic        m_valid,
    output dc_realtime_core_pkg::dc_rt_m_op_e m_op,
    output dc_realtime_core_pkg::dc_rt_operand_a_e operand_a_select,
    output logic        operand_b_immediate,
    output logic [31:0] immediate,
    output dc_realtime_core_pkg::dc_rt_control_e control,
    output dc_realtime_core_pkg::dc_rt_branch_condition_e branch_condition,
    output logic [31:0] control_immediate,
    output dc_realtime_core_pkg::dc_rt_memory_e memory,
    output dc_realtime_core_pkg::dc_rt_memory_size_e memory_size,
    output logic        load_unsigned,
    output dc_realtime_core_pkg::dc_rt_system_e system,
    output dc_realtime_core_pkg::dc_rt_csr_op_e csr_op,
    output logic        csr_immediate,
    output logic [11:0] csr_address,
    output logic        csr_source_zero
);
    timeunit 1ns;
    timeprecision 1ps;

    import dc_realtime_core_pkg::*;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic       writes_rd;

    always_comb begin
        opcode = instruction[6:0];
        funct3 = instruction[14:12];
        funct7 = instruction[31:25];
        rs1 = instruction[19:15];
        rs2 = instruction[24:20];
        rd = instruction[11:7];

        legal = 1'b0;
        writes_rd = 1'b0;
        alu_op = DC_RT_ALU_ADD;
        m_valid = 1'b0;
        m_op = DC_RT_M_MUL;
        operand_a_select = DC_RT_OPERAND_A_RS1;
        operand_b_immediate = 1'b0;
        immediate = {{20{instruction[31]}}, instruction[31:20]};
        control = DC_RT_CONTROL_NONE;
        branch_condition = DC_RT_BRANCH_EQ;
        control_immediate = 32'd0;
        memory = DC_RT_MEMORY_NONE;
        memory_size = DC_RT_MEMORY_BYTE;
        load_unsigned = 1'b0;
        system = DC_RT_SYSTEM_NONE;
        csr_op = DC_RT_CSR_RW;
        csr_immediate = 1'b0;
        csr_address = instruction[31:20];
        csr_source_zero = instruction[19:15] == 5'd0;

        case (opcode)
            7'b0110111: begin
                legal = 1'b1;
                writes_rd = 1'b1;
                operand_a_select = DC_RT_OPERAND_A_ZERO;
                operand_b_immediate = 1'b1;
                immediate = {instruction[31:12], 12'd0};
            end
            7'b0010111: begin
                legal = 1'b1;
                writes_rd = 1'b1;
                operand_a_select = DC_RT_OPERAND_A_PC;
                operand_b_immediate = 1'b1;
                immediate = {instruction[31:12], 12'd0};
            end
            7'b0010011: begin
                operand_b_immediate = 1'b1;
                case (funct3)
                    3'b000: begin legal = 1'b1; alu_op = DC_RT_ALU_ADD;  end
                    3'b010: begin legal = 1'b1; alu_op = DC_RT_ALU_SLT;  end
                    3'b011: begin legal = 1'b1; alu_op = DC_RT_ALU_SLTU; end
                    3'b100: begin legal = 1'b1; alu_op = DC_RT_ALU_XOR;  end
                    3'b110: begin legal = 1'b1; alu_op = DC_RT_ALU_OR;   end
                    3'b111: begin legal = 1'b1; alu_op = DC_RT_ALU_AND;  end
                    3'b001: begin
                        if (funct7 == 7'b0000000) begin
                            legal = 1'b1;
                            alu_op = DC_RT_ALU_SLL;
                            immediate = {27'd0, instruction[24:20]};
                        end
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            legal = 1'b1;
                            alu_op = DC_RT_ALU_SRL;
                            immediate = {27'd0, instruction[24:20]};
                        end else if (funct7 == 7'b0100000) begin
                            legal = 1'b1;
                            alu_op = DC_RT_ALU_SRA;
                            immediate = {27'd0, instruction[24:20]};
                        end
                    end
                    default: begin end
                endcase
                writes_rd = legal;
            end
            7'b0110011: begin
                if (funct7 == 7'b0000001) begin
                    legal = 1'b1;
                    m_valid = 1'b1;
                    m_op = dc_rt_m_op_e'(funct3);
                end else begin
                    case (funct3)
                        3'b000: begin
                            if (funct7 == 7'b0000000) begin legal = 1'b1; alu_op = DC_RT_ALU_ADD; end
                            else if (funct7 == 7'b0100000) begin legal = 1'b1; alu_op = DC_RT_ALU_SUB; end
                        end
                        3'b001: if (funct7 == 7'b0000000) begin legal = 1'b1; alu_op = DC_RT_ALU_SLL;  end
                        3'b010: if (funct7 == 7'b0000000) begin legal = 1'b1; alu_op = DC_RT_ALU_SLT;  end
                        3'b011: if (funct7 == 7'b0000000) begin legal = 1'b1; alu_op = DC_RT_ALU_SLTU; end
                        3'b100: if (funct7 == 7'b0000000) begin legal = 1'b1; alu_op = DC_RT_ALU_XOR;  end
                        3'b101: begin
                            if (funct7 == 7'b0000000) begin legal = 1'b1; alu_op = DC_RT_ALU_SRL; end
                            else if (funct7 == 7'b0100000) begin legal = 1'b1; alu_op = DC_RT_ALU_SRA; end
                        end
                        3'b110: if (funct7 == 7'b0000000) begin legal = 1'b1; alu_op = DC_RT_ALU_OR;  end
                        3'b111: if (funct7 == 7'b0000000) begin legal = 1'b1; alu_op = DC_RT_ALU_AND; end
                        default: begin end
                    endcase
                end
                writes_rd = legal;
            end
            7'b0000011: begin
                operand_b_immediate = 1'b1;
                memory = DC_RT_MEMORY_LOAD;
                case (funct3)
                    3'b000: begin legal = 1'b1; memory_size = DC_RT_MEMORY_BYTE; end
                    3'b001: begin legal = 1'b1; memory_size = DC_RT_MEMORY_HALF; end
                    3'b010: begin legal = 1'b1; memory_size = DC_RT_MEMORY_WORD; end
                    3'b100: begin
                        legal = 1'b1;
                        memory_size = DC_RT_MEMORY_BYTE;
                        load_unsigned = 1'b1;
                    end
                    3'b101: begin
                        legal = 1'b1;
                        memory_size = DC_RT_MEMORY_HALF;
                        load_unsigned = 1'b1;
                    end
                    default: begin end
                endcase
                writes_rd = legal;
            end
            7'b0100011: begin
                memory = DC_RT_MEMORY_STORE;
                operand_b_immediate = 1'b1;
                immediate = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
                case (funct3)
                    3'b000: begin legal = 1'b1; memory_size = DC_RT_MEMORY_BYTE; end
                    3'b001: begin legal = 1'b1; memory_size = DC_RT_MEMORY_HALF; end
                    3'b010: begin legal = 1'b1; memory_size = DC_RT_MEMORY_WORD; end
                    default: begin end
                endcase
            end
            7'b0001111: begin
                // FENCE is an ordering point.  The current LSU is blocking and
                // single-outstanding, so accepting it as a side-effect-free
                // instruction preserves all preceding/following bus order.
                // FENCE.I (funct3=001) remains unsupported in this milestone.
                if (funct3 == 3'b000) begin
                    legal = 1'b1;
                    operand_a_select = DC_RT_OPERAND_A_ZERO;
                    operand_b_immediate = 1'b1;
                    immediate = 32'd0;
                end
            end
            7'b1100011: begin
                control = DC_RT_CONTROL_BRANCH;
                control_immediate = {{19{instruction[31]}}, instruction[31],
                                     instruction[7], instruction[30:25],
                                     instruction[11:8], 1'b0};
                case (funct3)
                    3'b000: begin legal = 1'b1; branch_condition = DC_RT_BRANCH_EQ;  end
                    3'b001: begin legal = 1'b1; branch_condition = DC_RT_BRANCH_NE;  end
                    3'b100: begin legal = 1'b1; branch_condition = DC_RT_BRANCH_LT;  end
                    3'b101: begin legal = 1'b1; branch_condition = DC_RT_BRANCH_GE;  end
                    3'b110: begin legal = 1'b1; branch_condition = DC_RT_BRANCH_LTU; end
                    3'b111: begin legal = 1'b1; branch_condition = DC_RT_BRANCH_GEU; end
                    default: begin end
                endcase
            end
            7'b1101111: begin
                legal = 1'b1;
                writes_rd = 1'b1;
                control = DC_RT_CONTROL_JAL;
                control_immediate = {{11{instruction[31]}}, instruction[31],
                                     instruction[19:12], instruction[20],
                                     instruction[30:21], 1'b0};
            end
            7'b1100111: begin
                if (funct3 == 3'b000) begin
                    legal = 1'b1;
                    writes_rd = 1'b1;
                    control = DC_RT_CONTROL_JALR;
                    control_immediate = {{20{instruction[31]}}, instruction[31:20]};
                end
            end
            7'b1110011: begin
                case (funct3)
                    3'b000: begin
                        case (instruction)
                            32'h0000_0073: begin legal = 1'b1; system = DC_RT_SYSTEM_ECALL; end
                            32'h0010_0073: begin legal = 1'b1; system = DC_RT_SYSTEM_EBREAK; end
                            32'h3020_0073: begin legal = 1'b1; system = DC_RT_SYSTEM_MRET; end
                            32'h1050_0073: begin legal = 1'b1; system = DC_RT_SYSTEM_WFI; end
                            default: begin end
                        endcase
                    end
                    3'b001, 3'b010, 3'b011,
                    3'b101, 3'b110, 3'b111: begin
                        legal = 1'b1;
                        writes_rd = 1'b1;
                        system = DC_RT_SYSTEM_CSR;
                        csr_immediate = funct3[2];
                        case (funct3[1:0])
                            2'b01: csr_op = DC_RT_CSR_RW;
                            2'b10: csr_op = DC_RT_CSR_RS;
                            2'b11: csr_op = DC_RT_CSR_RC;
                            default: begin end
                        endcase
                    end
                    default: begin end
                endcase
            end
            default: begin end
        endcase

        rd_write = legal && writes_rd && (rd != 5'd0);
    end
endmodule
