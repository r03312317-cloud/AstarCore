// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vscore.h for the primary calling header

#ifndef VERILATED_VSCORE_RV32_ALU_PREDECODE_H_
#define VERILATED_VSCORE_RV32_ALU_PREDECODE_H_  // guard

#include "verilated.h"


class Vscore__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vscore_rv32_alu_predecode final {
  public:

    // DESIGN SPECIFIC STATE
    IData/*31:0*/ instruction;
    IData/*31:0*/ control;

    // INTERNAL VARIABLES
    Vscore__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    Vscore_rv32_alu_predecode();
    ~Vscore_rv32_alu_predecode();
    void ctor(Vscore__Syms* symsp, const char* namep);
    void dtor();
    VL_UNCOPYABLE(Vscore_rv32_alu_predecode);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
