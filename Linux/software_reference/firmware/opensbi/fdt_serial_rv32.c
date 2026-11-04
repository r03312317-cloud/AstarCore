// 此驱动适配 RV32 UART 的 MMIO 寄存器和轮询或中断接口。
// OpenSBI 与 Linux 采用不同驱动入口，但最终都把字符交给同一板载 UART。
// 串口文字来自板上执行的软件；主机窗口只负责发送用户输入和展示收到的字节。
// 时钟和寄存器布局需与实际设备树及 RTL 一致，不能照搬 16550 的偏移和状态位。
// SPDX-License-Identifier: BSD-2-Clause
// RV32 custom UART, deliberately not marked ns16550-compatible.
#include <sbi/riscv_io.h>
#include <sbi/sbi_console.h>
#include <sbi/sbi_error.h>
#include <sbi_utils/fdt/fdt_helper.h>
#include <sbi_utils/serial/fdt_serial.h>
static unsigned long base;
static void ast_putc(char ch) {
 while (readl((void *)(base + 0x00)) & 0x80000000U) ;
 writel((unsigned char)ch, (void *)(base + 0x00));
}
static int ast_getc(void) {
 unsigned int v = readl((void *)(base + 0x04));
 return (v & 0x80000000U) ? -1 : (int)(v & 255);
}
static struct sbi_console_device ast_console = {
 .name = "rv32-uart-v1", .console_putc = ast_putc, .console_getc = ast_getc
};
// 先注册 uart driver，再注册平台驱动；第二阶段失败时撤销第一阶段资源。
static int ast_init(const void *fdt, int node, const struct fdt_match *match) {
 uint64_t addr, size; int ret = fdt_get_node_addr_size(fdt, node, 0, &addr, &size);
 (void)match; if (ret) return ret;
 if (size < 0x1c || addr > 0xffffffffUL) return SBI_EINVAL;
 base = (unsigned long)addr;
 writel(0, (void *)(base + 0x0c));
 writel(3, (void *)(base + 0x08));
 sbi_console_set_device(&ast_console); return 0;
}
static const struct fdt_match ast_match[] = {
 { .compatible = "rv32,uart-v1" }, { }
};
const struct fdt_driver fdt_serial_rv32 = {
 .match_table = ast_match, .init = ast_init
};
