// 此驱动适配 RV32 UART 的 MMIO 寄存器和轮询或中断接口。
// OpenSBI 与 Linux 采用不同驱动入口，但最终都把字符交给同一板载 UART。
// 串口文字来自板上执行的软件；主机窗口只负责发送用户输入和展示收到的字节。
// 时钟和寄存器布局需与实际设备树及 RTL 一致，不能照搬 16550 的偏移和状态位。
// SPDX-License-Identifier: GPL-2.0-only
/* RV32 UART v1: custom MMIO, one-byte RX and single TX shift register. */
#include <linux/console.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/serial_core.h>
#include <linux/tty_flip.h>
#include <linux/interrupt.h>
#define TXDATA 0x00
#define RXDATA 0x04
#define CTRL 0x08
#define IE 0x0c
#define IP 0x10
#define DIV 0x14
#define STATUS 0x18
#define EMPTY BIT(31)
#define RXIRQ BIT(0)
#define TXIRQ BIT(1)
static struct uart_port *console_port;
static struct uart_driver ast_driver;
// 使用 Linux MMIO 读取访问寄存器，而不是普通 C 指针直接解引用。
// 偏移由 RV32 自定义寄存器图定义，不能套用 16550 字节偏移。
static u32 ar(struct uart_port *p, unsigned r) { return readl(p->membase+r); }
// 使用 Linux MMIO 写入保持驱动和硬件的寄存器访问契约。
// 写入某些控制或状态位会产生副作用，调用点必须持有正确的中断和锁状态。
static void aw(struct uart_port *p, unsigned r,u32 v) { writel(v,p->membase+r); }
static unsigned int ast_tx_empty(struct uart_port *p) { return ar(p,STATUS)&1 ? 0:TIOCSER_TEMT; }
// 当前硬件没有实现调制解调器控制引脚，保持这个回调为空操作。
// 不能据此声称本板支持硬件 RTS CTS 流控。
static void ast_set_mctrl(struct uart_port *p,unsigned int v) { }
// 向串口核心返回当前简化平台的固定调制解调器状态。
// 返回值属于驱动兼容约定，不代表真实接入了对应外部引脚。
static unsigned int ast_get_mctrl(struct uart_port *p) { return TIOCM_CTS|TIOCM_DSR|TIOCM_CAR; }
static void ast_stop_tx(struct uart_port *p) { aw(p,IE,ar(p,IE)&~TXIRQ); }
static void ast_start_tx(struct uart_port *p) { aw(p,IE,ar(p,IE)|TXIRQ); }
static void ast_stop_rx(struct uart_port *p) { aw(p,IE,ar(p,IE)&~RXIRQ); }
// 硬件没有实现独立 break 控制，此回调按当前简化接口为空操作。
static void ast_break_ctl(struct uart_port *p,int ctl) { }
// 一次最多把硬件可接受的一个字节交给 TX 寄存器。
// 上层队列进度由 serial core helper 推进，不用整个字符串覆盖浅硬件缓冲。
static void ast_tx(struct uart_port *p) {
 unsigned char ch;
 uart_port_tx_limited(p,ch,1,!(ar(p,TXDATA)&EMPTY),aw(p,TXDATA,ch),({}));
}
// 先在串口锁下读取挂起与使能位，确认为本端口中断后才处理。
// 收到的字节经 sysrq 判断后交给 tty flip buffer，用户 shell 从 tty 取得输入。
// TX 就绪中断继续发送队列；溢出状态需要单独计数并清除。
// 释放锁后才 push flip buffer，让 tty 层处理已收到的数据。
static irqreturn_t ast_irq(int irq,void *data) {
 struct uart_port *p=data; unsigned long flags; u32 pending, v; bool pushed=false;
 uart_port_lock_irqsave(p,&flags); pending=ar(p,IP)&ar(p,IE);
 if(!pending) { uart_port_unlock_irqrestore(p,flags);return IRQ_NONE; }
 if(pending&RXIRQ) {
  v=ar(p,RXDATA);
  if(!(v&EMPTY)) {
   p->icount.rx++;
   if(!uart_handle_sysrq_char(p,v&255)) uart_insert_char(p,0,0,v&255,TTY_NORMAL);
   pushed=true;
  }
 }
 if(pending&TXIRQ) ast_tx(p);
 if(ar(p,STATUS)&6) { p->icount.overrun++;aw(p,STATUS,6); }
 uart_port_unlock_irqrestore(p,flags);
 if(pushed) tty_flip_buffer_push(&p->state->port);
 return IRQ_HANDLED;
}
// 端口启用时申请真实 IRQ，失败直接返回给串口核心。
// 先配置控制寄存器，再打开 RX 中断，为 getty 与 shell 提供接收路径。
static int ast_startup(struct uart_port *p) {
 int r=request_irq(p->irq,ast_irq,0,"rv32-uart",p);
 if(r)return r;
 aw(p,CTRL,3);aw(p,IE,RXIRQ);return 0;
}
static void ast_shutdown(struct uart_port *p) { aw(p,IE,0);free_irq(p->irq,p); }
// 将 tty 参数收敛为当前硬件支持的 8N1，不宣称支持任意校验位和硬件流控。
// UART 时钟从设备树取得，按目标波特率四舍五入计算整数分频。
// 在锁下更新硬件分频和串口超时，随后向 tty 回报实际采用的波特配置。
static void ast_termios(struct uart_port *p,struct ktermios *t,const struct ktermios *old) {
 unsigned long flags; unsigned baud=uart_get_baud_rate(p,t,old,1200,p->uartclk/16);
 t->c_cflag &= ~(CSIZE|CSTOPB|PARENB|PARODD|CRTSCTS);t->c_cflag |= CS8|CLOCAL;
 uart_port_lock_irqsave(p,&flags);aw(p,DIV,DIV_ROUND_CLOSEST(p->uartclk,baud));
 uart_update_timeout(p,t->c_cflag,baud);uart_port_unlock_irqrestore(p,flags);
 tty_termios_encode_baud_rate(t,baud,baud);
}
static const char *ast_type(struct uart_port *p) { return "rv32-uart-v1"; }
static void ast_release(struct uart_port *p) { }
static int ast_request(struct uart_port *p) { return 0; }
static void ast_config(struct uart_port *p,int flags) { if(flags&UART_CONFIG_TYPE)p->type=PORT_GENERIC; }
static int ast_verify(struct uart_port *p,struct serial_struct *s) { return s->irq==p->irq?0:-EINVAL; }
static const struct uart_ops ast_ops={
 .tx_empty=ast_tx_empty,.set_mctrl=ast_set_mctrl,.get_mctrl=ast_get_mctrl,
 .stop_tx=ast_stop_tx,.start_tx=ast_start_tx,.stop_rx=ast_stop_rx,.break_ctl=ast_break_ctl,
 .startup=ast_startup,.shutdown=ast_shutdown,.set_termios=ast_termios,.type=ast_type,
 .release_port=ast_release,.request_port=ast_request,.config_port=ast_config,.verify_port=ast_verify
};
// 等待当前硬件发送槽可用后再写一个字符，供早期和常规控制台轮询输出。
// 这条路径能在中断服务尚未完整就绪时输出内核启动文字。
static void ast_putchar(struct uart_port *p,unsigned char ch) {
 while(ar(p,TXDATA)&EMPTY)cpu_relax();
 aw(p,TXDATA,ch);
}
#ifdef CONFIG_SERIAL_RV32_CONSOLE
// 控制台写入在锁下暂时关闭端口中断，避免和普通 TX 路径同时操作寄存器。
// 字符串写完后恢复原来的中断使能，不用固定值覆盖先前配置。
static void ast_console_write(struct console *c,const char *s,unsigned n) {
 struct uart_port *p=console_port; unsigned long flags; u32 ie;
 if(!p)return;
 uart_port_lock_irqsave(p,&flags);ie=ar(p,IE);aw(p,IE,0);
 uart_console_write(p,s,n,ast_putchar);aw(p,IE,ie);uart_port_unlock_irqrestore(p,flags);
}
// 默认控制台参数为 115200 8N1，若内核传入 options 则先解析。
// 只有真实端口资源已经建立，才调用串口核心完成控制台设置。
static int ast_console_setup(struct console *c,char *options) {
 int baud=115200,bits=8,flow='n',parity='n';
 if(!console_port)return -ENODEV;
 if(options)uart_parse_options(options,&baud,&parity,&bits,&flow);
 return uart_set_options(console_port,c,baud,parity,bits,flow);
}
static struct console ast_console={.name="ttyAS",.write=ast_console_write,.device=uart_console_device,
 .setup=ast_console_setup,.flags=CON_PRINTBUFFER,.index=-1,.data=&ast_driver};
#define AST_CONSOLE (&ast_console)
// earlycon 把 Linux 最早期内核文字送到同一 UART 轮询字符函数。
// earlycon 输出来自内核自身，与 OpenSBI 启动 banner 属于不同阶段。
static void ast_early_write(struct console *con,const char *s,unsigned n) {
 struct earlycon_device *dev=con->data;uart_console_write(&dev->port,s,n,ast_putchar);
}
// 把早期控制台的 write 回调绑定到 RV32 实现，要求已有 MMIO 映射。
// 设备树 compatible 与 EARLYCON 声明共同决定这一入口能否被匹配。
static int __init ast_early_setup(struct earlycon_device *dev,const char *options) {
 if(!dev->port.membase)return -ENODEV;
 dev->con->write=ast_early_write;return 0;
}
EARLYCON_DECLARE(rv32,ast_early_setup);
OF_EARLYCON_DECLARE(rv32,"rv32,uart-v1",ast_early_setup);
#else
#define AST_CONSOLE NULL
#endif
static struct uart_driver ast_driver={.owner=THIS_MODULE,.driver_name="rv32-uart",.dev_name="ttyAS",.nr=1,.cons=AST_CONSOLE};
// 从设备树和平台资源取得寄存器 IRQ 与输入时钟，再注册唯一 ttyAS 端口。
// 驱动的 fifo size 为一，主机逐字节等回显是对真实浅接收硬件的配合。
// 任一资源取得或注册失败都会返回错误，不能只凭设备树存在判断串口可用。
static int ast_probe(struct platform_device *pdev) {
 struct uart_port *p; struct resource *r;int ret;
 p=devm_kzalloc(&pdev->dev,sizeof(*p),GFP_KERNEL);if(!p)return -ENOMEM;
 p->membase=devm_platform_get_and_ioremap_resource(pdev,0,&r);if(IS_ERR(p->membase))return PTR_ERR(p->membase);
 p->mapbase=r->start;p->mapsize=resource_size(r);p->irq=platform_get_irq(pdev,0);if(p->irq<0)return p->irq;
 if(of_property_read_u32(pdev->dev.of_node,"clock-frequency",&p->uartclk))return -EINVAL;
 p->dev=&pdev->dev;p->iotype=UPIO_MEM32;p->flags=UPF_BOOT_AUTOCONF;p->fifosize=1;p->ops=&ast_ops;p->line=0;
 spin_lock_init(&p->lock);console_port=p;aw(p,CTRL,3);aw(p,IE,0);
 ret=uart_add_one_port(&ast_driver,p);if(ret){console_port=NULL;return ret;}
 platform_set_drvdata(pdev,p);return 0;
}
// 从串口核心注销端口并清除控制台引用，避免继续引用已释放设备。
static void ast_remove(struct platform_device *pdev) { uart_remove_one_port(&ast_driver,platform_get_drvdata(pdev));console_port=NULL; }
static const struct of_device_id ast_match[]={{.compatible="rv32,uart-v1"},{}};
MODULE_DEVICE_TABLE(of,ast_match);
static struct platform_driver ast_platform={.probe=ast_probe,.remove=ast_remove,.driver={.name="rv32-uart",.of_match_table=ast_match}};
// 先注册 uart driver，再注册平台驱动；第二阶段失败时撤销第一阶段资源。
static int __init ast_init(void) {int r=uart_register_driver(&ast_driver);if(r)return r;r=platform_driver_register(&ast_platform);if(r)uart_unregister_driver(&ast_driver);return r;}
// 按注册相反顺序撤销平台驱动与串口驱动，释放所属资源。
static void __exit ast_exit(void) {platform_driver_unregister(&ast_platform);uart_unregister_driver(&ast_driver);}
module_init(ast_init);module_exit(ast_exit);
MODULE_LICENSE("GPL");MODULE_DESCRIPTION("RV32 custom UART v1");
