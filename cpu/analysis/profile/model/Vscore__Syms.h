// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VSCORE__SYMS_H_
#define VERILATED_VSCORE__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vscore.h"

// INCLUDE MODULE CLASSES
#include "Vscore___024root.h"
#include "Vscore_rv32_alu_predecode.h"
#include "Vscore_rv32_execute.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES) Vscore__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vscore* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vscore___024root               TOP;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__allocation_alu_decode0;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__allocation_alu_decode1;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__alu_contract_decode0;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__alu_contract_decode1;
    Vscore_rv32_execute        TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__decode0;
    Vscore_rv32_execute        TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__decode1;
    Vscore_rv32_execute        TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__execute0;
    Vscore_rv32_execute        TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__execute1;
    Vscore_rv32_execute        TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__frontend__DOT__response_decode0;
    Vscore_rv32_execute        TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__frontend__DOT__response_decode1;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__issue_alu_contract0;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__issue_alu_contract1;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__0__KET____DOT__decode;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__10__KET____DOT__decode;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__11__KET____DOT__decode;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__1__KET____DOT__decode;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__2__KET____DOT__decode;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__3__KET____DOT__decode;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__4__KET____DOT__decode;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__5__KET____DOT__decode;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__6__KET____DOT__decode;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__7__KET____DOT__decode;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__8__KET____DOT__decode;
    Vscore_rv32_alu_predecode  TOP__rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__queue_alu_contract__BRA__9__KET____DOT__decode;

    // CONSTRUCTORS
    Vscore__Syms(VerilatedContext* contextp, const char* namep, Vscore* modelp);
    ~Vscore__Syms();

    // METHODS
    const char* name() const { return TOP.vlNamep; }
};

#endif  // guard
