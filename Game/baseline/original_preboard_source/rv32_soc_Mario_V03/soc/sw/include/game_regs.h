/* -------------------------------------------------------------------------
 * game_regs.h -- rv32_soc_Game memory map as seen by the CPU.
 *
 * The values below are the addresses decoded by game_soc_top.  Changing one
 * without changing the RTL breaks the contract; keep both files in sync.
 * ------------------------------------------------------------------------- */
#ifndef GAME_REGS_H
#define GAME_REGS_H

#define ITCM_BASE          0x10000000u   /* 64 KiB instruction TCM           */
#define DTCM_BASE          0x20000000u   /* 64 KiB data TCM                  */

#define MMIO_TIMER_BASE    0x30000000u   /* CP13 block                       */
#define MMIO_TIMER_MS      0x30000000u   /* free-running CPU cycle counter   */
#define MMIO_TIMER_MS_HI   0x30000004u
#define MMIO_CLOCK_HZ      0x30000008u
#define MMIO_GPIO_OUT      0x30000010u   /* LEDs                             */
#define MMIO_GPIO_IN       0x30000010u
#define MMIO_GPIO_SYNC     0x30000014u
#define MMIO_UART_TX       0x30000020u
#define MMIO_UART_STATUS   0x30000024u
#define MMIO_UART_RX       0x30000028u
#define MMIO_UART_CLEAR    0x3000002cu
#define MMIO_MAILBOX       0x300000fcu

#define MMIO_GAME_BASE     0x60001000u
#define MMIO_GAME_INPUT    0x60001000u   /* game_input page 0                */
#define MMIO_GAME_VIDEO    0x60001100u   /* game_video_ctrl page 1           */

/* game_input registers */
#define GIN_ID             0x00
#define GIN_LEVEL          0x04
#define GIN_PRESSED        0x08
#define GIN_RELEASED       0x0c
#define GIN_REPEAT         0x10
#define GIN_DEBOUNCE_MS    0x14
#define GIN_REPEAT_DELAY   0x18
#define GIN_REPEAT_PERIOD  0x1c
#define GIN_MS_TICKS       0x20
#define GIN_HOLD_MS        0x24

/* game_video_ctrl registers */
#define GVID_ID            0x00
#define GVID_STATUS        0x04
#define GVID_FB0           0x08
#define GVID_FB1           0x0c
#define GVID_COMMIT        0x10
#define GVID_VSYNC         0x14
#define GVID_PUBLISHED     0x18
#define GVID_ACTIVE_FB     0x1c
#define GVID_UNDERFLOW     0x20
#define GVID_PRESENTED     0x24
#define GVID_CTRL          0x28
#define GVID_MAX_WAIT      0x2c
#define GVID_FAULT         0x30
#define GVID_ERROR         0x34

#define FB0_ADDR           0x82000000u
#define FB1_ADDR           0x82100000u
#define FB_WIDTH           640
#define FB_HEIGHT          360
#define FB_BYTES           (FB_WIDTH * FB_HEIGHT * 2)

/* Button bits (game_input LEVEL / PRESSED). */
#define BTN_UP             0x01
#define BTN_DOWN           0x02
#define BTN_LEFT           0x04
#define BTN_RIGHT          0x08
#define BTN_A              0x10
#define BTN_B              0x20
#define BTN_START          0x40
#define BTN_SELECT         0x80

#endif /* GAME_REGS_H */
