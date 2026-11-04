/* Verilator-only autorun entry. The production monitor is main.c. */
#define BOARD_SIM_NO_CAMERA 1
#define BOARD_SIM_GRAPH_METRICS 1
#define main soc_monitor_main
#include "main.c"
#undef main

int main(void) {
    /* Test BFM header: descriptor address, op count, trace address,
     * final address, final byte count. The memory model preloads the input. */
    uint32_t descriptor=R32(DDR_BASE);
    uint32_t count=R32(DDR_BASE+4u);
    uint32_t trace=R32(DDR_BASE+8u);
    uint32_t output=R32(DDR_BASE+12u);
    uint32_t bytes=R32(DDR_BASE+16u);
    crc_init();
    R32(0x50000000u)=4u;
    data_len=16u;
    set32(data,count);set32(data+4u,trace);
    set32(data+8u,output);set32(data+12u,bytes);
    uint32_t status=graph_run(descriptor);
    R32(0x2000ff04u)=status;
    R32(0x2000ff08u)=get32(data+28u);
    R32(0x2000ff0cu)=get32(data+8u);
    R32(0x2000ff10u)=get32(data+12u);
    R32(0x2000ff14u)=get32(data+16u);
    R32(0x2000ff18u)=sim_npu_cycles;
    R32(0x2000ff1cu)=sim_npu_commands;
    R32(0x2000ff20u)=sim_im2col_ticks;
    fence_all();
    R32(0x2000ff00u)=0x434d4f4bu; /* top.done = CMOK */
    for(;;) { }
}
