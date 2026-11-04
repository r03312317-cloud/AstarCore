// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Primary model header
//
// This header should be included by all source files instantiating the design.
// The class here is then constructed to instantiate the design.
// See the Verilator manual for examples.

#ifndef VERILATED_VSCORE_H_
#define VERILATED_VSCORE_H_  // guard

#include "verilated.h"

class Vscore__Syms;
class Vscore___024root;
class Vscore_rv32_alu_predecode;
class Vscore_rv32_execute;


// This class is the main interface to the Verilated model
class alignas(VL_CACHE_LINE_BYTES) Vscore VL_NOT_FINAL : public VerilatedModel {
  private:
    // Symbol table holding complete model state (owned by this class)
    Vscore__Syms* const vlSymsp;

  public:

    // CONSTEXPR CAPABILITIES
    // Verilated with --trace?
    static constexpr bool traceCapable = false;

    // PORTS
    // The application code writes and reads these signals to
    // propagate new values into/out from the Verilated model.
    VL_IN8(&clk,0,0);
    VL_IN8(&reset,0,0);
    VL_IN8(&uart_rx,0,0);
    VL_OUT8(&uart_tx,0,0);
    VL_OUT8(&done,0,0);
    VL_OUT8(&fault,0,0);
    VL_OUT8(&debug_uart_valid,0,0);
    VL_OUT8(&debug_uart_data,7,0);
    VL_OUT8(&debug_timer_valid,0,0);
    VL_OUT8(&debug_retire,1,0);
    VL_OUT8(&debug_i_fill,0,0);
    VL_OUT8(&debug_d_fill,0,0);
    VL_OUT8(&debug_writeback,0,0);
    VL_OUT8(&debug_bus_read_error,0,0);
    VL_OUT8(&loading,0,0);
    VL_OUT(&exit_code,31,0);
    VL_OUT(&debug_timer_value,31,0);
    VL_OUT64(&elapsed_clocks,63,0);
    VL_OUT64(&debug_retired_start,63,0);
    VL_OUT64(&debug_retired_stop,63,0);

    // CELLS
    // Public to allow access to /* verilator public */ items.
    // Otherwise the application code can consider these internals.
    Vscore_rv32_execute* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__decode0;
    Vscore_rv32_execute* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__decode1;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__allocation_alu_decode0;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__allocation_alu_decode1;
    Vscore_rv32_execute* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__execute0;
    Vscore_rv32_execute* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__execute1;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__issue_alu_contract0;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__issue_alu_contract1;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__alu_contract_decode0;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__alu_contract_decode1;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__0__KET____DOT__decode;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__1__KET____DOT__decode;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__2__KET____DOT__decode;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__3__KET____DOT__decode;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__4__KET____DOT__decode;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__5__KET____DOT__decode;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__6__KET____DOT__decode;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__7__KET____DOT__decode;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__8__KET____DOT__decode;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__9__KET____DOT__decode;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__10__KET____DOT__decode;
    Vscore_rv32_alu_predecode* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__11__KET____DOT__decode;
    Vscore_rv32_execute* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__frontend__DOT__response_decode0;
    Vscore_rv32_execute* const __PVT__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__frontend__DOT__response_decode1;

    // Root instance pointer to allow access to model internals,
    // including inlined /* verilator public_flat_* */ items.
    Vscore___024root* const rootp;

    // CONSTRUCTORS
    /// Construct the model; called by application code
    /// If contextp is null, then the model will use the default global context
    /// If name is "", then makes a wrapper with a
    /// single model invisible with respect to DPI scope names.
    explicit Vscore(VerilatedContext* contextp, const char* name = "TOP");
    explicit Vscore(const char* name = "TOP");
    /// Destroy the model; called (often implicitly) by application code
    virtual ~Vscore();
  private:
    VL_UNCOPYABLE(Vscore);  ///< Copying not allowed

  public:
    // API METHODS
    /// Evaluate the model.  Application must call when inputs change.
    void eval() { eval_step(); }
    /// Evaluate when calling multiple units/models per time step.
    void eval_step();
    /// Evaluate at end of a timestep for tracing, when using eval_step().
    /// Application must call after all eval() and before time changes.
    void eval_end_step() {}
    /// Simulation complete, run final blocks.  Application must call on completion.
    void final();
    /// Are there scheduled events to handle?
    bool eventsPending();
    /// Returns time at next time slot. Aborts if !eventsPending()
    uint64_t nextTimeSlot();
    /// Trace signals in the model; called by application code
    void trace(VerilatedTraceBaseC* tfp, int levels, int options = 0) { contextp()->trace(tfp, levels, options); }
    /// Retrieve name of this model instance (as passed to constructor).
    const char* name() const;

    // Abstract methods from VerilatedModel
    const char* hierName() const override final;
    const char* modelName() const override final;
    unsigned threads() const override final;
    /// Prepare for cloning the model at the process level (e.g. fork in Linux)
    /// Release necessary resources. Called before cloning.
    void prepareClone() const;
    /// Re-init after cloning the model at the process level (e.g. fork in Linux)
    /// Re-allocate necessary resources. Called after cloning.
    void atClone() const;
  private:
    // Internal functions - trace registration
    void traceBaseModel(VerilatedTraceBaseC* tfp, int levels, int options);
};

#endif  // guard
