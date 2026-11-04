module dc_realtime_core_fast_irq (
    input  logic        clk,
    input  logic        rst,
    input  logic        irq_nmi_fault,
    input  logic        irq_fast_adc,
    input  logic        irq_fast_pwm,
    input  logic        irq_qei,
    input  logic        irq_timer,
    input  logic        irq_ipc,
    input  logic [7:0]  irq_platform,
    input  logic [13:1] mie,
    input  logic        mstatus_mie,
    input  logic        handler_active,
    input  logic        accept_enable,
    output logic [31:0] mip,
    output logic        accept,
    output logic [3:0]  accepted_slot,
    output logic        fault_seen
);
    timeunit 1ns;
    timeprecision 1ps;

    import dc_realtime_core_pkg::*;

    logic        nmi_pending_q;
    logic        nmi_level_q;
    logic        fault_seen_q;
    logic [DC_RT_IRQ_VECTOR_COUNT-1:0] pending;
    logic [DC_RT_IRQ_VECTOR_COUNT-1:0] eligible;
    logic        selected_valid;
    logic [3:0]  selected_slot;

    always_comb begin
        pending = '0;
        pending[DC_RT_IRQ_SLOT_NMI_FAULT] = nmi_pending_q | irq_nmi_fault;
        pending[DC_RT_IRQ_SLOT_FAST_ADC] = irq_fast_adc;
        pending[DC_RT_IRQ_SLOT_FAST_PWM] = irq_fast_pwm;
        pending[DC_RT_IRQ_SLOT_QEI] = irq_qei;
        pending[DC_RT_IRQ_SLOT_TIMER] = irq_timer;
        pending[DC_RT_IRQ_SLOT_IPC] = irq_ipc;
        pending[DC_RT_IRQ_SLOT_PLATFORM0 +: DC_RT_PLATFORM_IRQ_WIDTH] = irq_platform;

        eligible = '0;
        if (!handler_active) begin
            eligible[DC_RT_IRQ_SLOT_NMI_FAULT] = pending[DC_RT_IRQ_SLOT_NMI_FAULT];
            if (mstatus_mie)
                eligible[13:1] = pending[13:1] & mie;
        end

        selected_valid = 1'b0;
        selected_slot = 4'd0;
        for (int unsigned slot = 0; slot < DC_RT_IRQ_VECTOR_COUNT; slot++) begin
            if (!selected_valid && eligible[slot]) begin
                selected_valid = 1'b1;
                selected_slot = slot[3:0];
            end
        end

        mip = {18'd0, pending};
        accept = accept_enable && selected_valid;
        accepted_slot = selected_slot;
        fault_seen = fault_seen_q;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            nmi_pending_q <= 1'b0;
            nmi_level_q <= 1'b0;
            fault_seen_q <= 1'b0;
        end else begin
            nmi_level_q <= irq_nmi_fault;
            if (irq_nmi_fault)
                fault_seen_q <= 1'b1;
            if (accept && accepted_slot == DC_RT_IRQ_SLOT_NMI_FAULT[3:0]) begin
                nmi_pending_q <= 1'b0;
            end else if (irq_nmi_fault && !nmi_level_q) begin
                nmi_pending_q <= 1'b1;
            end
        end
    end
endmodule
