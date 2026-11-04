// ---------------------------------------------------------------------------
// sim_main.cpp -- clock driver for the rv32_soc_Game full-SoC testbench.
//
// Verilator's --timing scheduler is roughly an order of magnitude slower than
// plain eval() calls, and the testbench only needs four periodic clocks.  This
// harness owns those clocks and calls eval() once per clock edge, which keeps a
// full 60 Hz frame in the low seconds on a laptop.
// ---------------------------------------------------------------------------
#include "Vtb_game_board.h"
#include "verilated.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

namespace {

constexpr uint64_t PS = 1;                 // time base: picoseconds
constexpr uint64_t NS = 1000 * PS;

struct Clock {
    uint64_t half;      // half period in ps
    uint64_t next;      // next edge time
    bool     level;
};

}  // namespace

// MinGW Verilator runtime still references the SystemC hook; provide the C++
// symbol (no extern "C") exactly as the mainline builds do.
double sc_time_stamp() { return 0.0; }

int main(int argc, char** argv)
{
    VerilatedContext ctx;
    ctx.commandArgs(argc, argv);

    Vtb_game_board* top = new Vtb_game_board{&ctx};

    // 100 MHz CPU, 93.75 MHz DDR user clock, 74.25 MHz pixel, 1 MHz slow
    // domain (LED synchronisers) and an idle TMDS serial clock.
    Clock cpu{5000, 5000, false};
    Clock mem{5333, 5333, false};
    Clock pix{6734, 6734, false};
    Clock sys{500000, 500000, false};

    top->cpu_clk = 0;
    top->mem_clk = 0;
    top->pix_clk = 0;
    top->sys_clk = 0;
    top->ser_clk = 0;
    top->rst_n = 0;

    ctx.time(0);
    top->eval();
    uint64_t t = 0;
    const uint64_t reset_release = 4000 * NS;     // 4 us
    const uint64_t limit = 3000ull * 1000 * 1000 * NS;  // 3 s safety stop
    uint64_t edges = 0;

    while (!ctx.gotFinish() && t < limit) {
        uint64_t next = std::min(std::min(cpu.next, mem.next),
                                 std::min(pix.next, sys.next));
        t = next;
        if (cpu.next == next) { cpu.level = !cpu.level; top->cpu_clk = cpu.level; cpu.next += cpu.half; }
        if (mem.next == next) { mem.level = !mem.level; top->mem_clk = mem.level; mem.next += mem.half; }
        if (pix.next == next) { pix.level = !pix.level; top->pix_clk = pix.level; pix.next += pix.half; }
        if (sys.next == next) { sys.level = !sys.level; top->sys_clk = sys.level; sys.next += sys.half; }
        if (t >= reset_release) top->rst_n = 1;
        ctx.time(t);
        top->eval();
        edges++;
        if ((edges % 20000000ull) == 0) {
            std::printf("SIM: t=%.2f us edges=%llu frames=%d vsync=%u presented=%u de=%d\n",
                        double(t) / 1e6, (unsigned long long)edges,
                        top->frames_o, top->vsync_o, top->present_o, (int)top->de_seen_o);
            std::fflush(stdout);
        }
    }

    std::printf("SIM: stopped at %.3f ms after %llu clock edges\n",
                double(t) / double(NS) / 1e6, (unsigned long long)edges);
    top->final();
    delete top;
    return ctx.gotFinish() ? 0 : 1;
}
