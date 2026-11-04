// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vscore.h for the primary calling header

#ifndef VERILATED_VSCORE_RV32_EXECUTE_H_
#define VERILATED_VSCORE_RV32_EXECUTE_H_  // guard

#include "verilated.h"


class Vscore__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vscore_rv32_execute final {
  public:

    // DESIGN SPECIFIC STATE
    // Anonymous structures to workaround compiler member-count bugs
    struct {
        CData/*5:0*/ __VlemCall_2__population;
        CData/*5:0*/ __VlemCall_1__trailing_zeroes;
        CData/*5:0*/ __VlemCall_0__leading_zeroes;
        CData/*4:0*/ source1;
        CData/*4:0*/ source2;
        CData/*4:0*/ destination;
        CData/*0:0*/ uses_source1;
        CData/*0:0*/ uses_source2;
        CData/*0:0*/ writes_destination;
        CData/*0:0*/ memory;
        CData/*0:0*/ memory_write;
        CData/*1:0*/ memory_size;
        CData/*0:0*/ memory_unsigned;
        CData/*0:0*/ arithmetic;
        CData/*2:0*/ arithmetic_operation;
        CData/*0:0*/ control;
        CData/*0:0*/ conditional;
        CData/*0:0*/ taken;
        CData/*0:0*/ csr;
        CData/*0:0*/ csr_write;
        CData/*2:0*/ system_operation;
        CData/*0:0*/ illegal;
        CData/*5:0*/ __PVT__leading_zeroes_reference__Vstatic__amount;
        CData/*4:0*/ __Vfunc_leading_zeroes__0____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__0____Vlvbound_hf4143080__0;
        CData/*4:0*/ __Vfunc_leading_zeroes__3____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__3____Vlvbound_hf4143080__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__3____Vlvbound_he707e711__0;
        CData/*5:0*/ __Vfunc_leading_zeroes__3____VlefCall_0__leading_zeroes_reference;
        CData/*5:0*/ __Vfunc_leading_zeroes_reference__4__Vfuncout;
        CData/*4:0*/ __Vfunc_leading_zeroes__6____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__6____Vlvbound_hf4143080__0;
        CData/*4:0*/ __Vfunc_leading_zeroes__9____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__9____Vlvbound_hf4143080__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__9____Vlvbound_he707e711__0;
        CData/*5:0*/ __Vfunc_leading_zeroes__9____VlefCall_0__leading_zeroes_reference;
        CData/*5:0*/ __Vfunc_leading_zeroes_reference__10__Vfuncout;
        CData/*4:0*/ __Vfunc_leading_zeroes__12____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__12____Vlvbound_hf4143080__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__12____Vlvbound_he707e711__0;
        CData/*5:0*/ __Vfunc_leading_zeroes__12____VlefCall_0__leading_zeroes_reference;
        CData/*5:0*/ __Vfunc_leading_zeroes_reference__13__Vfuncout;
        CData/*4:0*/ __Vfunc_leading_zeroes__15____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__15____Vlvbound_hf4143080__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__15____Vlvbound_he707e711__0;
        CData/*5:0*/ __Vfunc_leading_zeroes__15____VlefCall_0__leading_zeroes_reference;
        CData/*5:0*/ __Vfunc_leading_zeroes_reference__16__Vfuncout;
        CData/*4:0*/ __Vfunc_leading_zeroes__18____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__18____Vlvbound_hf4143080__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__18____Vlvbound_he707e711__0;
        CData/*5:0*/ __Vfunc_leading_zeroes__18____VlefCall_0__leading_zeroes_reference;
        CData/*5:0*/ __Vfunc_leading_zeroes_reference__19__Vfuncout;
        CData/*4:0*/ __Vfunc_leading_zeroes__21____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__21____Vlvbound_hf4143080__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__21____Vlvbound_he707e711__0;
        CData/*5:0*/ __Vfunc_leading_zeroes__21____VlefCall_0__leading_zeroes_reference;
        CData/*5:0*/ __Vfunc_leading_zeroes_reference__22__Vfuncout;
        CData/*4:0*/ __Vfunc_leading_zeroes__24____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__24____Vlvbound_hf4143080__0;
        CData/*4:0*/ __Vfunc_leading_zeroes__27____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__27____Vlvbound_hf4143080__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__27____Vlvbound_he707e711__0;
        CData/*5:0*/ __Vfunc_leading_zeroes__27____VlefCall_0__leading_zeroes_reference;
        CData/*5:0*/ __Vfunc_leading_zeroes_reference__28__Vfuncout;
    };
    struct {
        CData/*4:0*/ __Vfunc_leading_zeroes__30____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__30____Vlvbound_hf4143080__0;
        CData/*4:0*/ __Vfunc_leading_zeroes__33____Vlvbound_he806b239__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__33____Vlvbound_hf4143080__0;
        CData/*0:0*/ __Vfunc_leading_zeroes__33____Vlvbound_he707e711__0;
        CData/*5:0*/ __Vfunc_leading_zeroes__33____VlefCall_0__leading_zeroes_reference;
        CData/*5:0*/ __Vfunc_leading_zeroes_reference__34__Vfuncout;
        CData/*0:0*/ __VdfgRegularize_h6e95ff9d_0_313;
        SData/*11:0*/ csr_number;
        IData/*31:0*/ instruction;
        IData/*31:0*/ pc;
        IData/*31:0*/ left;
        IData/*31:0*/ right;
        IData/*31:0*/ csr_value;
        IData/*31:0*/ value;
        IData/*31:0*/ address;
        IData/*31:0*/ store_value;
        IData/*31:0*/ next_pc;
        IData/*31:0*/ sequential_target;
        IData/*31:0*/ branch_jump_target;
        IData/*31:0*/ indirect_jump_target;
        IData/*31:0*/ csr_new_value;
        IData/*31:0*/ __PVT__immediate_i;
        IData/*31:0*/ __PVT__immediate_b;
        IData/*31:0*/ __PVT__reversed_left;
        IData/*31:0*/ __PVT__leading_zeroes_reference__Vstatic__shifted;
        IData/*31:0*/ __PVT__trailing_zeroes__Vstatic__reversed;
        IData/*31:0*/ __Vfunc_leading_zeroes__3__word;
        IData/*31:0*/ __Vfunc_leading_zeroes_reference__4__word;
        IData/*31:0*/ __Vfunc_leading_zeroes__9__word;
        IData/*31:0*/ __Vfunc_leading_zeroes_reference__10__word;
        IData/*31:0*/ __Vfunc_leading_zeroes__12__word;
        IData/*31:0*/ __Vfunc_leading_zeroes_reference__13__word;
        IData/*31:0*/ __Vfunc_trailing_zeroes__14__word;
        IData/*31:0*/ __Vfunc_leading_zeroes__15__word;
        IData/*31:0*/ __Vfunc_leading_zeroes_reference__16__word;
        IData/*31:0*/ __Vfunc_population__17__word;
        IData/*31:0*/ __Vfunc_leading_zeroes__18__word;
        IData/*31:0*/ __Vfunc_leading_zeroes_reference__19__word;
        IData/*31:0*/ __Vfunc_trailing_zeroes__20__word;
        IData/*31:0*/ __Vfunc_leading_zeroes__21__word;
        IData/*31:0*/ __Vfunc_leading_zeroes_reference__22__word;
        IData/*31:0*/ __Vfunc_population__23__word;
        IData/*31:0*/ __Vfunc_leading_zeroes__27__word;
        IData/*31:0*/ __Vfunc_leading_zeroes_reference__28__word;
        IData/*31:0*/ __Vfunc_leading_zeroes__33__word;
        IData/*31:0*/ __Vfunc_leading_zeroes_reference__34__word;
        IData/*31:0*/ __VdfgRegularize_h6e95ff9d_0_2;
        IData/*31:0*/ __VdfgRegularize_h6e95ff9d_0_3;
        IData/*31:0*/ __VdfgRegularize_h6e95ff9d_0_4;
        IData/*31:0*/ __VdfgRegularize_h6e95ff9d_0_5;
        IData/*31:0*/ __VdfgRegularize_h6e95ff9d_0_12;
        IData/*31:0*/ __VdfgRegularize_h6e95ff9d_0_13;
        QData/*62:0*/ __PVT__leading_zeroes__Vstatic__subtree_valid;
        VlUnpacked<CData/*4:0*/, 63> __PVT__leading_zeroes__Vstatic__position;
        VlUnpacked<CData/*1:0*/, 16> __PVT__population__Vstatic__pairs;
        VlUnpacked<CData/*2:0*/, 8> __PVT__population__Vstatic__quads;
        VlUnpacked<CData/*3:0*/, 4> __PVT__population__Vstatic__octets;
        VlUnpacked<CData/*4:0*/, 2> __PVT__population__Vstatic__halves;
    };

    // INTERNAL VARIABLES
    Vscore__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    Vscore_rv32_execute();
    ~Vscore_rv32_execute();
    void ctor(Vscore__Syms* symsp, const char* namep);
    void dtor();
    VL_UNCOPYABLE(Vscore_rv32_execute);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
