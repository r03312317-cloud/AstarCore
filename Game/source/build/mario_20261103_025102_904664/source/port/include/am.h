#ifndef SOC_AM_H
#define SOC_AM_H
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
enum {AM_KEY_NONE=0,AM_KEY_J,AM_KEY_K,AM_KEY_U,AM_KEY_I,AM_KEY_W,AM_KEY_S,AM_KEY_A,AM_KEY_D};
typedef struct {uint64_t us;} AM_TIMER_UPTIME_T;
typedef struct {int width,height;} AM_GPU_CONFIG_T;
typedef struct {bool keydown;int keycode;} AM_INPUT_KEYBRD_T;
/* Mario port pixels are immutable NES palette indices, expanded to RGB565. */
typedef struct {int x,y;const uint8_t *pixels;int w,h;bool sync;} AM_GPU_FBDRAW_T;
AM_TIMER_UPTIME_T am_read_AM_TIMER_UPTIME(void);
AM_GPU_CONFIG_T am_read_AM_GPU_CONFIG(void);
AM_INPUT_KEYBRD_T am_read_AM_INPUT_KEYBRD(void);
void am_write_AM_GPU_FBDRAW(AM_GPU_FBDRAW_T request);
void ioe_init(void);
void putch(char c);
#define io_read(reg) am_read_##reg()
#define io_write(reg,...) am_write_##reg((reg##_T){__VA_ARGS__})
#endif
