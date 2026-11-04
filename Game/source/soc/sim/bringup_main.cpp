#include "Vtb_game_bringup.h"
#include "verilated.h"
#include <algorithm>
#include <cstdint>
#include <cstdio>

struct Clock { uint64_t half, next; bool level; };
double sc_time_stamp() { return 0.0; }

int main(int argc, char **argv) {
    VerilatedContext ctx;
    ctx.commandArgs(argc, argv);
    Vtb_game_bringup top{&ctx};
    // picoseconds; sys and pixel clocks share the board's 27 MHz source.
    Clock cpu{5000, 5000, false}, mem{5333, 5333, false};
    Clock pix{18519, 18519, false};
    top.cpu_clk = top.mem_clk = top.pix_clk = top.sys_clk = top.ser_clk = 0;
    top.rst_n = 0;
    // Establish asynchronous reset with all clocks low before the first edge.
    ctx.time(0);
    top.eval();
    uint64_t t = 0, edges = 0;
    const uint64_t limit = 4000000000000ull; // 4 seconds in ps
    while (!ctx.gotFinish() && t < limit) {
        t = std::min(std::min(cpu.next, mem.next), pix.next);
        if (cpu.next == t) { cpu.level = !cpu.level; top.cpu_clk = cpu.level; cpu.next += cpu.half; }
        if (mem.next == t) { mem.level = !mem.level; top.mem_clk = mem.level; mem.next += mem.half; }
        if (pix.next == t) { pix.level = !pix.level; top.pix_clk = pix.level; top.sys_clk = pix.level; pix.next += pix.half; }
        if (t >= 4000000ull) top.rst_n = 1; // 4 us
        ctx.time(t);
        top.eval();
        if (++edges % 20000000ull == 0) {
            std::printf("\nSIM: %.3f ms frames=%d vsync=%u presented=%u active=%08x\n",
                        double(t)/1e9, top.frames_o, top.vsync_o, top.presented_o, top.active_fb_o);
            std::fflush(stdout);
        }
    }
    std::printf("\nSIM: stopped at %.3f ms after %llu edges\n", double(t)/1e9,
                static_cast<unsigned long long>(edges));
    top.final();
    return ctx.gotFinish() ? 0 : 1;
}
