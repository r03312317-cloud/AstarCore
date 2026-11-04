package dc_realtime_core_pkg;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int unsigned DC_RT_PLATFORM_IRQ_WIDTH = 8;
    localparam int unsigned DC_RT_IRQ_SOURCE_COUNT = 7;
    localparam int unsigned DC_RT_IRQ_VECTOR_COUNT = 14;
    localparam int unsigned DC_RT_IRQ_SLOT_NMI_FAULT = 0;
    localparam int unsigned DC_RT_IRQ_SLOT_FAST_ADC = 1;
    localparam int unsigned DC_RT_IRQ_SLOT_FAST_PWM = 2;
    localparam int unsigned DC_RT_IRQ_SLOT_QEI = 3;
    localparam int unsigned DC_RT_IRQ_SLOT_TIMER = 4;
    localparam int unsigned DC_RT_IRQ_SLOT_IPC = 5;
    localparam int unsigned DC_RT_IRQ_SLOT_PLATFORM0 = 6;
    typedef enum logic [2:0] {
        DC_RT_IRQ_NMI_FAULT = 3'd0,
        DC_RT_IRQ_FAST_ADC  = 3'd1,
        DC_RT_IRQ_FAST_PWM  = 3'd2,
        DC_RT_IRQ_QEI       = 3'd3,
        DC_RT_IRQ_TIMER     = 3'd4,
        DC_RT_IRQ_IPC       = 3'd5,
        DC_RT_IRQ_PLATFORM  = 3'd6
    } dc_rt_irq_source_e;

    typedef enum logic [3:0] {
        DC_RT_ALU_ADD  = 4'd0,
        DC_RT_ALU_SUB  = 4'd1,
        DC_RT_ALU_SLL  = 4'd2,
        DC_RT_ALU_SLT  = 4'd3,
        DC_RT_ALU_SLTU = 4'd4,
        DC_RT_ALU_XOR  = 4'd5,
        DC_RT_ALU_SRL  = 4'd6,
        DC_RT_ALU_SRA  = 4'd7,
        DC_RT_ALU_OR   = 4'd8,
        DC_RT_ALU_AND  = 4'd9
    } dc_rt_alu_op_e;

    typedef enum logic [2:0] {
        DC_RT_M_MUL    = 3'b000,
        DC_RT_M_MULH   = 3'b001,
        DC_RT_M_MULHSU = 3'b010,
        DC_RT_M_MULHU  = 3'b011,
        DC_RT_M_DIV    = 3'b100,
        DC_RT_M_DIVU   = 3'b101,
        DC_RT_M_REM    = 3'b110,
        DC_RT_M_REMU   = 3'b111
    } dc_rt_m_op_e;

    typedef enum logic [1:0] {
        DC_RT_OPERAND_A_RS1  = 2'd0,
        DC_RT_OPERAND_A_PC   = 2'd1,
        DC_RT_OPERAND_A_ZERO = 2'd2
    } dc_rt_operand_a_e;

    typedef enum logic [1:0] {
        DC_RT_CONTROL_NONE   = 2'd0,
        DC_RT_CONTROL_BRANCH = 2'd1,
        DC_RT_CONTROL_JAL    = 2'd2,
        DC_RT_CONTROL_JALR   = 2'd3
    } dc_rt_control_e;

    typedef enum logic [2:0] {
        DC_RT_BRANCH_EQ  = 3'd0,
        DC_RT_BRANCH_NE  = 3'd1,
        DC_RT_BRANCH_LT  = 3'd2,
        DC_RT_BRANCH_GE  = 3'd3,
        DC_RT_BRANCH_LTU = 3'd4,
        DC_RT_BRANCH_GEU = 3'd5
    } dc_rt_branch_condition_e;

    typedef enum logic [1:0] {
        DC_RT_MEMORY_NONE  = 2'd0,
        DC_RT_MEMORY_LOAD  = 2'd1,
        DC_RT_MEMORY_STORE = 2'd2
    } dc_rt_memory_e;

    typedef enum logic [1:0] {
        DC_RT_MEMORY_BYTE = 2'd0,
        DC_RT_MEMORY_HALF = 2'd1,
        DC_RT_MEMORY_WORD = 2'd2
    } dc_rt_memory_size_e;

    typedef enum logic [1:0] {
        DC_RT_TVAL_ZERO        = 2'd0,
        DC_RT_TVAL_PC          = 2'd1,
        DC_RT_TVAL_INSTRUCTION = 2'd2,
        DC_RT_TVAL_ADDRESS     = 2'd3
    } dc_rt_tval_source_e;

    typedef enum logic [1:0] {
        DC_RT_CSR_RW = 2'd0,
        DC_RT_CSR_RS = 2'd1,
        DC_RT_CSR_RC = 2'd2
    } dc_rt_csr_op_e;

    typedef enum logic [2:0] {
        DC_RT_SYSTEM_NONE   = 3'd0,
        DC_RT_SYSTEM_CSR    = 3'd1,
        DC_RT_SYSTEM_ECALL  = 3'd2,
        DC_RT_SYSTEM_EBREAK = 3'd3,
        DC_RT_SYSTEM_MRET   = 3'd4,
        DC_RT_SYSTEM_WFI    = 3'd5
    } dc_rt_system_e;

    typedef enum logic [1:0] {
        DC_RT_BTB_CONDITIONAL = 2'd0,
        DC_RT_BTB_JAL_CALL    = 2'd1,
        DC_RT_BTB_JALR        = 2'd2,
        DC_RT_BTB_RETURN      = 2'd3
    } dc_rt_btb_type_e;

    typedef enum logic [2:0] {
        DC_RT_PRED_SEQUENTIAL = 3'd0,
        DC_RT_PRED_BHT        = 3'd1,
        DC_RT_PRED_LOOP       = 3'd2,
        DC_RT_PRED_BTB        = 3'd3,
        DC_RT_PRED_RAS        = 3'd4,
        DC_RT_PRED_DIRECT_JAL = 3'd5
    } dc_rt_pred_source_e;
endpackage
