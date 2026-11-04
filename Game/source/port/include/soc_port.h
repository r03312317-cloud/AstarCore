// [ARCH] 共同定义 APP、堆、资源、栈和两块帧缓冲地址。
// [ARCH] 上传从 0x84000000 开始，帧缓冲保留在已实现的非缓存窗口。
// [ARCH] 双缓冲相隔 1 MiB，但单帧并非 1 MiB。
// [ARCH] 取得后台缓冲可能返回 NULL，表示前次发布未安全完成。
// [ARCH] 文件兼容接口不保证持久化或完整 POSIX 语义。
#ifndef SOC_PORT_H
#define SOC_PORT_H
#include <stdint.h>
#include <stddef.h>
// [ARCH] 上传映像起点，入口与主机 APAL 跳转地址一致。
#define SOC_APP_BASE 0x84000000u
// [ARCH] APP 窗口的排他上界，长度检查使用减法防止地址回绕。
#define SOC_APP_LIMIT 0x84800000u
// [ARCH] newlib 堆起点，和装载映像预留区分开。
#define SOC_HEAP_BASE 0x84800000u
// [ARCH] 堆可增长到的排他上界，_sbrk 拒绝越界扩张。
#define SOC_HEAP_LIMIT 0x85800000u
// [ARCH] DDR 栈的初始顶端，启动代码再保证 ABI 对齐。
#define SOC_STACK_TOP 0x88000000u
// [ARCH] 继承的资源包窗口起点，当前内嵌 ROM 不依赖外部资源包。
#define SOC_ASSET_BASE 0x85800000u
// [ARCH] 资源窗口排他上界，必须在阶段接收器允许范围内。
#define SOC_ASSET_LIMIT 0x87c00000u
/* Existing HDMI bitstream accepts 0x82000000..0x823fffff only. These CPU
 * writes are uncached; the renderer avoids rewriting unchanged blocks. */
// [ARCH] Mario 第一块 RGB565 目标缓冲，与实际 HDMI 窗口匹配。
#define SOC_VIDEO_FB0 0x82000000u
// [ARCH] Mario 第二块目标缓冲，不能迁到未被扫描器支持的新窗口。
#define SOC_VIDEO_FB1 0x82100000u
// [ARCH] 每行目标像素数，缩放器按该行距形成输出地址。
#define SOC_FB_WIDTH 640
// [ARCH] 目标缓冲行数，双缓冲像素测试据此检查边界。
#define SOC_FB_HEIGHT 360
// [ARCH] 一致读取的 64 位真实 CPU 周期；主性能统计使用它作为时基。
uint64_t soc_cycles(void);
// [ARCH] 32 位毫秒短超时接口，差值应按无符号方式计算。
uint32_t soc_millis(void);
// [ARCH] 一个字符的阻塞发送，繁忙状态下会等待可写。
void soc_uart_putc(char c);
// [ARCH] 顺序发送零结尾字符串，不会生成游戏按键事件。
void soc_uart_puts(const char *s);
// [ARCH] 有限等待接收字节，超时返回负值。
int soc_uart_getc(uint32_t timeout_ms);
// [ARCH] 读取硬件去抖 LEVEL，软件事件映射在另一层完成。
uint8_t soc_buttons(void);
// [ARCH] 设置固定双缓冲和去抖参数，建立软件初始前台身份。
void soc_video_init(void);
// [ARCH] 等待前次发布后交出可写地址，失败返回 NULL。
uint16_t *soc_video_back(void);
// [ARCH] 只排队当前后台，不同步等待所有显示步骤完成。
int soc_video_publish(void);
// [ARCH] 只统计已确认完成的换帧，可落后一个排队请求。
unsigned soc_video_completed(void);
// [ARCH] 在上传/搬运新指令后同步数据和取指视图。
void soc_fence_i(void);
// [ARCH] 对明确地址/长度的字节内容做完整性校验。
uint32_t soc_crc32(const void *data,size_t length);
// [ARCH] 先验证整个只读资源表，再替换当前资源视图。
int soc_fs_mount(const void *image,size_t available);
// [ARCH] 有界兼容资源句柄，不提供宿主操作系统文件访问。
int soc_fs_open(const char *path,int flags);
// [ARCH] 释放一个兼容句柄，不删除对应的资源对象。
int soc_fs_close(int fd);
// [ARCH] 按句柄位置读取，返回长度受剩余内容限制。
int soc_fs_read(int fd,void *buffer,size_t count);
// [ARCH] 仅对允许的 RAM 可写对象写入，容量有限。
int soc_fs_write(int fd,const void *buffer,size_t count);
// [ARCH] 在有限资源对象中改变位置，不映射真实磁盘偏移。
long soc_fs_seek(int fd,long offset,int whence);
// [ARCH] 读取兼容对象长度，不从板外文件系统查询。
long soc_fs_size(int fd);
#endif
