// Read the target system's actual debug UART and counter snapshot ports.
#include "Vscore.h"
#include "Vscore___024root.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

double sc_time_stamp() { return 0; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::threadContextp()->threads(1);
    Vscore d;
    FILE* pipe=std::fopen("algorithm_cycles.csv","wb");
    FILE* uart=std::fopen("uart_raw.log","wb");
    FILE* debug=std::fopen("uart_debug.log","wb");
    if(!uart || !debug || !pipe) return 2;
    std::fprintf(pipe,"cycle,window_index,ex_valid0,ex_valid1,ex_hold,issue0_accept,issue1_accept,queued_issue0,queued_issue1,dispatch_bypass0,dispatch_bypass1,retire0_raw,retire1_raw,retire_registered_mask,rob_count,rob_head,rob_tail,head_done,head_fault,head_response_success,head_conditional,predictor_training_ready,fetch_count,allocate_count,frontend_empty,dispatch_stall,rob_commit_wait,recovery,trap_enter,serial_pending,mdu_active,mul_occupancy,iq_count,eligible_count,ex_pc0,ex_pc1,head_pc,second_pc,head_instruction,second_instruction,ex_instruction0,ex_instruction1,ex_tag0,ex_tag1,counter_events\n");
    uint64_t window_cycles=0;
    d.clk=0; d.reset=1; d.uart_rx=1;
    for (int i=0;i<8;i++) { d.clk=0; d.eval(); d.clk=1; d.eval(); }
    d.reset=0;
    uint64_t cycles=0, timer_reads=0, measured_events[4]={0,0,0,0};
    unsigned bits=0, delay=0, current=0, bad_stop=0, flush=0;
    bool previous=true, receiving=false;
    std::vector<unsigned char> transmitted, accepted;
    bool window=false;
    const uint64_t cap=argc>1 ? std::strtoull(argv[1],nullptr,10) : 10000000ull;
    while (cycles<cap && !d.fault && (!d.done || flush<64)) {
        d.clk=0; d.eval();
        if(d.debug_timer_valid) {
            timer_reads++;
            if(timer_reads==1) window=true;
            if(timer_reads==2) window=false;
        }
        if(window) {
            unsigned iq_count=0,eligible_count=0;
            for(unsigned j=0;j<12;j++) {
                if(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__q_valid[j]) iq_count++;
                if((d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__eligible>>j)&1u)eligible_count++;
            }
            std::fprintf(pipe,"%llu,%llu,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u\n",
                (unsigned long long)cycles,(unsigned long long)window_cycles,
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_valid0),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_valid1),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_hold),
                unsigned((!d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__recovery&&!d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_hold&&(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ordered_valid0||int32_t(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__dispatch_ex0)>=0))),
                unsigned((!d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__recovery&&(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ordered_valid1||int32_t(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__dispatch_ex1)>=0))),
                unsigned((!d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__recovery&&!d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_hold&&d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ordered_valid0)),
                unsigned((!d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__recovery&&d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ordered_valid1)),
                unsigned((!d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__recovery&&!d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_hold&&int32_t(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__dispatch_ex0)>=0)),
                unsigned((!d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__recovery&&int32_t(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__dispatch_ex1)>=0)),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__retire0),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__retire1),
                unsigned(d.debug_retire),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_count),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_tail),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_done[d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head]),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_fault[d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head]),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__head_response_success),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_conditional[d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head]),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__predictor_training_ready),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__fetch_count),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__allocate_count),
                unsigned((d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__fetch_count==0)),
                unsigned((d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__fetch_count!=0&&d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__allocate_count==0)),
                unsigned((d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_count!=0&&!d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__retire0&&!d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__recovery)),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__recovery),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__trap_enter),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__serial_pending),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__mdu_active),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__mul_occupancy),
                unsigned(iq_count),
                unsigned(eligible_count),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_pc0),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_pc1),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__architectural_pc),
                unsigned(((d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head&1)?d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_prediction_odd[d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head>>1]:d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_prediction_even[d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head>>1])),
                unsigned(((d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head&1)?d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_instruction_odd[d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head>>1]:d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_instruction_even[d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head>>1])),
                unsigned(((((d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head+1)&15)&1)?d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_instruction_odd[((d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head+1)&15)>>1]:d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_instruction_even[((d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__rob_head+1)&15)>>1])),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_instruction0),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_instruction1),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_tag0),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__ex_tag1),
                unsigned(d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__counter_event_step));
            window_cycles++;

            auto events=d.rootp->rv32_coremark_system_boot__DOT__cpu__DOT__processor__DOT__counter_event_step;
            for(unsigned i=0;i<4;i++) if((events>>i)&1) measured_events[i]++;
        }
        d.clk=1; d.eval();
        if(d.debug_uart_valid) {
            auto value=(unsigned char)d.debug_uart_data;
            std::fputc(value,debug); accepted.push_back(value);
        }
        bool pin=d.uart_tx;
        if(!receiving) {
            if(previous && !pin) { receiving=true; delay=6; bits=0; current=0; }
        } else if(delay>0 && --delay==0) {
            if(bits<8) { if(pin) current|=1u<<bits; bits++; delay=4; }
            else {
                if(!pin) bad_stop++;
                std::fputc(current,uart); transmitted.push_back((unsigned char)current);
                receiving=false;
            }
        }
        previous=pin;
        if(d.done) flush++;
        cycles++;
    }
    std::fclose(pipe);
    std::fclose(uart);
    std::fclose(debug);
    const bool serial_ok=transmitted==accepted && !bad_stop && !receiving;
    std::fprintf(stderr,"cycles=%llu done=%u fault=%u exit=%u timer_reads=%llu retired_start=%llu retired_stop=%llu event_window=%llu,%llu,%llu,%llu serial_bytes=%zu accepted_bytes=%zu bad_stop=%u serial_ok=%u\n",
        (unsigned long long)cycles,(unsigned)d.done,(unsigned)d.fault,(unsigned)d.exit_code,
        (unsigned long long)timer_reads,(unsigned long long)d.debug_retired_start,
        (unsigned long long)d.debug_retired_stop,(unsigned long long)measured_events[0],
        (unsigned long long)measured_events[1],(unsigned long long)measured_events[2],
        (unsigned long long)measured_events[3],transmitted.size(),accepted.size(),bad_stop,(unsigned)serial_ok);
    d.final();
    std::fprintf(stderr,"simulation_final_complete=1\n");
    return d.done && !d.fault && !d.exit_code && serial_ok ? 0 : 1;
}
