// [ARCH] MMIO 偏移与访问属性需和 RTL 一起核对。
// [ARCH] 去抖电平与粘滞事件不能混用。
// [ARCH] COMMIT 排队，PUBLISHED/ACTIVE_FB 确认真正换帧。
// [ARCH] 视频地址受现有非缓存显示窗口限制。
/* -------------------------------------------------------------------------
 * game_regs.h -- rv32_soc_Game memory map as seen by the CPU.
 *
 * The values below are the addresses decoded by game_soc_top.  Changing one
 * without changing the RTL breaks the contract; keep both files in sync.
 * ------------------------------------------------------------------------- */
#ifndef GAME_REGS_H
#define GAME_REGS_H

// [ARCH] 复位代码 SRAM 基址，当前核从该范围起始处取第一条指令。
#define ITCM_BASE          0x10000000u   /* 64 KiB instruction TCM           */
// [ARCH] 独立数据 SRAM 基址，不能与 DDR 应用栈混淆。
#define DTCM_BASE          0x20000000u   /* 64 KiB data TCM                  */

// [ARCH] CPU 公共外设页，偏移与 pg_cpu_peripherals 解码一致。
#define MMIO_TIMER_BASE    0x30000000u   /* CP13 block                       */
// [ARCH] 历史名字包含 MS，但实际读出 CPU 周期计数低字，不是毫秒。
#define MMIO_TIMER_MS      0x30000000u   /* free-running CPU cycle counter   */
// [ARCH] 同一周期计数高字，拼接时要处理低字回绕。
#define MMIO_TIMER_MS_HI   0x30000004u
// [ARCH] 软件读取的频率声明，仍需用真实 PLL/约束确认其正确性。
#define MMIO_CLOCK_HZ      0x30000008u
// [ARCH] GPIO 输出寄存器，可用于板级状态显示。
#define MMIO_GPIO_OUT      0x30000010u   /* LEDs                             */
// [ARCH] 同一 GPIO 窗口的输入/读视图，不能当作游戏按键事件寄存器。
#define MMIO_GPIO_IN       0x30000010u
// [ARCH] 同步后的 GPIO 状态观察入口，存在同步传播延迟。
#define MMIO_GPIO_SYNC     0x30000014u
// [ARCH] 发送数据写口，软件必须遵守发送器背压/可写状态。
#define MMIO_UART_TX       0x30000020u
// [ARCH] 接收可读与发送可写条件，数据口本身不提供这些资格。
#define MMIO_UART_STATUS   0x30000024u
// [ARCH] 收到的字节数据口，读取与其有效状态配合。
#define MMIO_UART_RX       0x30000028u
// [ARCH] UART 状态维护入口，具体写语义由外设 RTL 定义。
#define MMIO_UART_CLEAR    0x3000002cu
// [ARCH] 平台保留的通信寄存器，不是当前游戏的主要控制入口。
#define MMIO_MAILBOX       0x300000fcu

// [ARCH] 游戏外设窗口总基址，页内再区分按键和视频。
#define MMIO_GAME_BASE     0x60001000u
// [ARCH] 按键寄存器页，读写偏移取 GIN_*。
#define MMIO_GAME_INPUT    0x60001000u   /* game_input page 0                */
// [ARCH] 视频描述符控制页，读写偏移取 GVID_*。
#define MMIO_GAME_VIDEO    0x60001100u   /* game_video_ctrl page 1           */

/* game_input registers */
// [ARCH] 设备身份只读项，用来识别当前按键控制器。
#define GIN_ID             0x00
// [ARCH] 去抖后的当前按住电平，不等于一次按下边沿。
#define GIN_LEVEL          0x04
// [ARCH] 粘滞按下事件，按 RW1C 规则清除。
#define GIN_PRESSED        0x08
// [ARCH] 粘滞松开事件，与当前电平可能不同。
#define GIN_RELEASED       0x0c
// [ARCH] 按住后的自动重复事件，时间参数独立于去抖。
#define GIN_REPEAT         0x10
// [ARCH] 稳定电平的毫秒门槛，Mario 初始化写入 6。
#define GIN_DEBOUNCE_MS    0x14
// [ARCH] 第一次自动重复前的保持延迟。
#define GIN_REPEAT_DELAY   0x18
// [ARCH] 连续重复事件的间隔。
#define GIN_REPEAT_PERIOD  0x1c
// [ARCH] 控制器内部毫秒时基，不是 NES 帧号。
#define GIN_MS_TICKS       0x20
// [ARCH] 当前/最近按键保持时间的观测量。
#define GIN_HOLD_MS        0x24

/* game_video_ctrl registers */
// [ARCH] 识别视频控制器寄存器布局的身份项。
#define GVID_ID            0x00
// [ARCH] 综合视频控制状态，与错误/活动地址分别检查。
#define GVID_STATUS        0x04
// [ARCH] 第一候选缓冲地址设置，不表示它当前正在扫描。
#define GVID_FB0           0x08
// [ARCH] 第二候选缓冲地址设置，应与软件第二缓冲常量一致。
#define GVID_FB1           0x0c
// [ARCH] 排队请求显示某个地址，写入不等于已经完成换帧。
#define GVID_COMMIT        0x10
// [ARCH] 硬件垂直同步观察量，不代表模拟器产生了同样多张新图。
#define GVID_VSYNC         0x14
// [ARCH] 发布序列的确认依据，软件保存提交前值以检查变化。
#define GVID_PUBLISHED     0x18
// [ARCH] 硬件当前活动地址，与发布计数共同证明缓冲所有权转移。
#define GVID_ACTIVE_FB     0x1c
// [ARCH] 显示读数不足的故障观察，不是 CPU cache miss 数量。
#define GVID_UNDERFLOW     0x20
// [ARCH] 实际扫描输出的完成观察量，口径不同于软件排队次数。
#define GVID_PRESENTED     0x24
// [ARCH] 视频控制维护寄存器，正常初始化写值由 board.c 决定。
#define GVID_CTRL          0x28
// [ARCH] 观察最长等待情况的寄存器，不是 CPU 的频率参数。
#define GVID_MAX_WAIT      0x2c
// [ARCH] 扫描/下游故障观察，finish_video 将其纳入失败判定。
#define GVID_FAULT         0x30
// [ARCH] 控制请求错误观察，不能与发布完成混为一谈。
#define GVID_ERROR         0x34

// [ARCH] 平台第一缓冲，仍属于非缓存显示窗口。
#define FB0_ADDR           0x82000000u
// [ARCH] 平台第二缓冲，轮换前应确认第一/第二地址的真实活动状态。
#define FB1_ADDR           0x82100000u
// [ARCH] 目标输出每行 640 像素，不是 NES 源画布宽度。
#define FB_WIDTH           640
// [ARCH] 目标输出 360 行，不是 HDMI 载波总垂直周期。
#define FB_HEIGHT          360
// [ARCH] RGB565 每像素两字节，一块有效图像为 460800 字节。
#define FB_BYTES           (FB_WIDTH * FB_HEIGHT * 2)

/* Button bits (game_input LEVEL / PRESSED). */
// [ARCH] 平台上方向逻辑位；Mario 另外在 input.c 将该实体键映射为开始。
#define BTN_UP             0x01
// [ARCH] 平台下方向逻辑位；Mario 另外把该实体键映射为加速。
#define BTN_DOWN           0x02
// [ARCH] 平台左方向位，在当前 Mario 映射中仍用于左移。
#define BTN_LEFT           0x04
// [ARCH] 平台右方向位，在当前 Mario 映射中仍用于右移。
#define BTN_RIGHT          0x08
// [ARCH] 实体 KEY0 的确认位，Mario 将其映射为跳跃。
#define BTN_A              0x10
// [ARCH] 保留的平台 B 位，不代表五个板载键中另有一个独立 B 键。
#define BTN_B              0x20
// [ARCH] 平台保留 Start 逻辑位，当前实体 KEY1 的映射由 Mario 软件完成。
#define BTN_START          0x40
// [ARCH] 保留 Select 逻辑位，当前五键演示没有单独 Select 按键。
#define BTN_SELECT         0x80

#endif /* GAME_REGS_H */
