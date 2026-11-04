#ifndef SOC_PORT_H
#define SOC_PORT_H
#include <stdint.h>
#include <stddef.h>
#define SOC_APP_BASE 0x84000000u
#define SOC_APP_LIMIT 0x84800000u
#define SOC_HEAP_BASE 0x84800000u
#define SOC_HEAP_LIMIT 0x85800000u
#define SOC_STACK_TOP 0x88000000u
#define SOC_ASSET_BASE 0x85800000u
#define SOC_ASSET_LIMIT 0x87c00000u
#define SOC_FB_WIDTH 640
#define SOC_FB_HEIGHT 360
uint64_t soc_cycles(void);
uint32_t soc_millis(void);
void soc_uart_putc(char c);
void soc_uart_puts(const char *s);
int soc_uart_getc(uint32_t timeout_ms);
uint8_t soc_buttons(void);
void soc_video_init(void);
uint16_t *soc_video_back(void);
int soc_video_publish(void);
void soc_fence_i(void);
uint32_t soc_crc32(const void *data,size_t length);
int soc_fs_mount(const void *image,size_t available);
int soc_fs_open(const char *path,int flags);
int soc_fs_close(int fd);
int soc_fs_read(int fd,void *buffer,size_t count);
int soc_fs_write(int fd,const void *buffer,size_t count);
long soc_fs_seek(int fd,long offset,int whence);
long soc_fs_size(int fd);
#endif
