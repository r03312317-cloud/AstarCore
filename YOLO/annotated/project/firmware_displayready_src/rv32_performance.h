/* RV32 D1 counter ABI 1. Passive MMIO reads at two workflow boundaries only.
 * The interval starts before START event arming and ends after digital HDMI
 * completion/error, before reply formatting. It includes polling and waiting.
 * Cache/maintenance/MMIO activities overlap elapsed CPU cycles. */
// 架构导读：rv32_performance。
// 读取并编码 RV32 及相关加速器性能统计字段。
#define RV32_PERF_ID 0x31503252u
#define RV32_PERF_COUNT 18u
static uint64_t rv32_perf_before[RV32_PERF_COUNT],rv32_perf_after[RV32_PERF_COUNT];
static uint32_t rv32_perf_frame,rv32_perf_run,rv32_perf_status,rv32_perf_valid;
// 服务函数 rv32_counter64。
// 接口参数：uint32_t low；返回值及副作用由下列函数体定义。
// 参数入口：low；类型、指针限定及返回约定沿用下列声明。
static uint64_t rv32_counter64(uint32_t low) {
    uint32_t lo=R32(low),hi=R32(low+4u);
    return ((uint64_t)hi<<32)|lo;
}
// 服务函数 rv32_perf_sample。
// 接口参数：uint64_t out[RV32_PERF_COUNT]；返回值及副作用由下列函数体定义。
// 参数入口：RV32_PERF_COUNT；类型、指针限定及返回约定沿用下列声明。
static void rv32_perf_sample(uint64_t out[RV32_PERF_COUNT]) {
    /* first two entries are 64-bit snapshots; all others wrap at 32 bits */
    out[0]=rv32_counter64(0x30000204u);
    out[1]=rv32_counter64(0x3000020cu);
    const uint32_t address[16]={0x30000104u,0x30000108u,0x3000010cu,0x30000110u,
        0x30000214u,0x30000218u,0x3000021cu,0x30000220u,0x30000224u,
        0x30000228u,0x30000114u,0x30000118u,0x3000022cu,0x30000200u,
        0x30000230u,0x30000234u};
    for(uint32_t i=0;i<16u;i++)out[i+2u]=R32(address[i]);
}
// 服务函数 rv32_perf_begin。
static void rv32_perf_begin(uint32_t frame,uint32_t run) {
    rv32_perf_valid=0u;rv32_perf_frame=frame;rv32_perf_run=run;
    rv32_perf_sample(rv32_perf_before);
}
static void rv32_perf_end(uint32_t status) {
    rv32_perf_sample(rv32_perf_after);rv32_perf_status=status;rv32_perf_valid=1u;
}
static void rv32_perf_reply(void) {
    set32(data,RV32_PERF_ID);set32(data+4u,1u);set32(data+8u,rv32_perf_valid);
    set32(data+12u,rv32_perf_frame);set32(data+16u,rv32_perf_run);
    set32(data+20u,rv32_perf_status);set32(data+24u,HZ);set32(data+28u,RV32_PERF_COUNT);
    for(uint32_t i=0;i<RV32_PERF_COUNT;i++) {
        set64(data+32u+i*8u,rv32_perf_before[i]);
        set64(data+32u+(RV32_PERF_COUNT+i)*8u,rv32_perf_after[i]);
    }
    reply(OK,32u+RV32_PERF_COUNT*16u);
}
