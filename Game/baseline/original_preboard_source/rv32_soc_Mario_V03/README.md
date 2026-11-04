# rv32_soc Mario V03 — 离线帧率优化版

rv32_core_01 自研 RISC-V CPU 运行 LiteNES，模拟 NES 的 6502、PPU 和手柄，通过 DDR 双帧缓冲输出《超级马里奥兄弟》。本轮按用户要求只做离线优化；**V03 尚未上板，实际帧率和操控流畅度未测。** V01、V02 及其交付 ZIP 保留。

## 本版改动

1. 将 `FRAME_SKIP` 从 1 改为 0，正常运行时每个模拟帧都产生画面，取消原来的隔帧显示。游戏仍按最高 60 个模拟帧/秒限速；这个上限不代表已经达到 60 FPS。
2. 视频提交后立即继续计算下一帧，在再次使用后台缓冲前才检查前一次提交完成。必须同时确认发布计数增加、活动缓冲地址正确且没有视频错误，才轮换缓冲，避免写入正在显示的画面。
3. PPU 背景绘制直接访问当前画布行，将重复的函数调用、边界检查和调色板索引读取移出逐像素路径。背景命中信息、精灵逻辑和屏幕裁剪保持与参考一致。
4. 时间读取改用当前 CPU 已实现的 `mcycle/mcycleh`（CSR 0xb00/0xb80），按高、低、高顺序读取并在回绕时重试。每次计时不再需要原有三次设备读取和六次 I/O 屏障；真实外设访问仍保留必要屏障。
5. 保留 V02 的 ITCM 主代码、较小 DDR 绘图循环、8 位索引画布、PPU 行式布局、17 次/帧按键轮询，以及按两个物理缓冲分别记录历史的 16 像素分块增量绘制。

没有修改 CPU、SoC RTL、时钟或已验收位流。当前固件 70,932 字节，SHA-256：

`46ad6c47ada60bff9f0656da3175f0e7ea8a89fa0828d8db0bc71cf8eb4823bb`

## 离线验收

最终验收记录由 `build/QUALIFICATION.json` 绑定固件、源码、硬件、原生测试和 RTL 结果；打包工具解压交付 ZIP 后再次运行相同验收。

| 检查 | 覆盖范围 |
|---|---|
| 1000 帧原生回归 | 标题、进入 1-1、左右移动、跳跃落地、暂停恢复、碰撞扣命；996 次画面输出。逐帧状态、NES RAM CRC、PC 和每次输出的图像哈希与独立全帧率参考一致 |
| 双缓冲绘制 | 130 帧随机、稀疏、重复和边缘更新；两块缓冲从非零内容开始，核对 29,952,000 个像素，并检查缓冲边界 |
| 实际 CPU/缓存/SoC RTL | 执行同一 `mario.bin`，核对前四个 NES 帧 RAM CRC/PC、按钮引脚到软件事件、有效 HDMI 完整帧和 RGB565 图像；两块缓冲均预填非零内容，避免误把黑色回退画面判为成功 |
| 64 位计时 | RTL 启动测试将 CPU 周期计数器置于低 32 位回绕附近，检查跨回绕的单调性和高位进位；这种计数器写入仅在仿真引导程序中，游戏固件不执行 |
| 异步缓冲管理 | 7 组设备事件测试覆盖完成信号先后不同、重复提交、计数回绕、等待超时、毫秒回绕、提交已接受但报错，以及扫描输出故障；还确认测试能检出旧的“报错时提前释放缓冲”缺陷 |
| 固件与硬件一致性 | 编译输入冻结并逐项校验，14 个 CPU 文件和 74 个硬件源文件与原验收位流匹配 |

参考位于 `tests/reference_fullrate/`：从冻结的 V01 ZIP 提取原始代码，唯一游戏源码改动是 `FRAME_SKIP=0`。39 个参考文件已逐一与原 ZIP 核对；原生测试脚本、参考源码、来源 SHA 和逐帧轨迹一起保留。这样比较的是每帧均输出的原引擎，不会将“多显示的帧”误判为图像改变。

RTL 验收是启动与接口检查，不覆盖标题后的完整游戏。原生回归检查的是主机执行的游戏逻辑；完整关卡过关、实板长时间运行和音频尚未验收，音频当前未实现。主机截图和仿真截图都不是 FPGA 屏幕实拍。

## 帧率依据

V02 最后一次实板使用固件 `923b4995…01ee2`。标题阶段 28 个样本的加权平均为 19.94 个模拟帧/秒、9.93 次成功画面发布/秒；用户反馈“能操作，但仍然明显卡顿”。游戏 TASK=3 的样本较少且可能包含暂停，不作为持续游玩帧率保证。原始证据在 V02 的 `build/bringup/board_20261103_020631_249555/`，摘要见 `docs/PERFORMANCE_V02_R2.json`。

用户确认随后关电或重启，所以串口停止不能据此判为 CPU 卡死。本轮没有重新连接或下载开发板。V03 后续串口采集会记录进度到达时间，并拒绝把末尾超过 5 秒无新进度的采集判为持续运行通过。

模拟帧率、成功画面发布速率、HDMI 60 Hz 刷新频率是不同指标。V03 的 `VID` 只累计已确认完成的换帧，最多落后一个已排队帧；不将排队请求直接计为成功。不能用原生测试速度、取消隔帧的理论倍率或 HDMI 刷新率替代实板 FPS。

## 平台

- rv32_core_01 / RV32 I2W2，RV32IM，100 MHz；上传入口 `0x84000000`，栈顶 `0x88000000`。
- 主代码运行于 ITCM `0x10004000..0x1000A35F`，25,440 字节；DDR 绘图代码 `0x840000E0..0x840006D3`，1,524 字节。数据、ROM、BSS 和栈位于 DDR。
- 双帧缓冲 `0x82000000 / 0x82100000`，640×360 RGB565；NES 256×240 缩放为居中的 480×360，左右各留 80 像素。
- 既有 HDMI 读取窗口只接受 `0x82000000..0x823FFFFF`，这一段 CPU 访问不经过数据缓存。本版通过减少写入量优化，保留有效地址范围。
- 位流 SHA-256：`4d9712422b90649c03fa76c4f179aa85ab6aa5512303f59b5fa59da484f4c0ab`。原 10 组时序检查无失败端点，最差 setup +0.405 ns、hold +0.041 ns；39 个输入、79 个输出延时未约束项仍保留在报告中。

## 操作

| 板载按键 | 原理图 | 操作 |
|---|---|---|
| USER_BUTTON0 / KEY0 | S3 | 跳跃，按住影响跳跃高度 |
| USER_BUTTON1 / KEY1 | S4 | 开始、暂停、继续 |
| USER_BUTTON2 / KEY2 | S5 | 加速跑、取得能力后发射火焰 |
| USER_BUTTON3 / KEY3 | S6 | 左移 |
| USER_BUTTON4 / KEY4 | S7 | 右移 |
| KEY3 + KEY4 | S6 + S7 | 下方向 / 下蹲 |

KEY1 是开始键，RESET 是另一只独立按键。标题后按一次开始，等待 1-1 过场；重复按开始会切换暂停。未提供独立 Select / 上方向和持久化存档。

按键标识依据本机《教程1_盘古MINI系列开发板硬件指导手册_V1.3.pdf》第 34 页：`D:/workspace/riscv-fpga-soc/sources/Pango_100K200K_MINI/1_Demo_document/实验例程说明篇/教程1_盘古MINI系列开发板硬件指导手册_V1.3.pdf`。

## 离线复现

在本目录运行，首次从源码复现时先创建 `build` 目录：

```powershell
New-Item -ItemType Directory -Force build
D:\anaconda\python.exe -B -X utf8 tools\test_gameplay.py
D:\anaconda\python.exe -B -X utf8 tools\test_render.py
D:\anaconda\python.exe -B -X utf8 tools\test_video_queue.py
D:\anaconda\python.exe -B -X utf8 tools\build_mario.py
D:\anaconda\python.exe -B -X utf8 tools\test_mario_rtl.py
D:\anaconda\python.exe -B -X utf8 tools\program_mario.py --qualify-only
D:\anaconda\python.exe -B -X utf8 tools\package_preboard.py
```

工具使用 MinGW GCC、xPack RISC-V GCC 15.2 和 Verilator。主机默认对比 `tests/reference_fullrate/trace.csv`；RTL 可加 `--reuse-model build\mario_rtl_<已通过目录>` 复用相同硬件模型，工具会验证模型输入哈希。RTL 预装 DDR 仅省略 UART 传输，真实 CPU 仍执行固件入口和 ITCM 搬运。

重建独立参考时，在 `tests/reference_fullrate/source/` 创建 `build` 目录并运行其 `tools/test_gameplay.py`；生成的轨迹可与上层 `trace.csv` 校验。参考脚本保持 V01 原版，不默认引用 V03 轨迹。

## 后续上板

当前用户要求先离线优化，此节仅为后续复现说明，不自动执行。板卡获准使用且连接好后，运行：

```powershell
D:\anaconda\python.exe -B -X utf8 tools\program_mario.py --execute --capture-seconds 180
```

工具先验收固件、持有共享板卡锁，再做 SRAM 配置、924 字节 stage2、游戏上传及真实 UART 采集。逐块回读/CRC 和整包 CRC 通过才执行；不能绕过 stage2。退出释放 UART、JTAG 服务和锁，不写 Flash。串口按 CP210x VID/PID 识别，之前为 COM14。仍需真人观察游戏移动、跳跃和流畅度。

离线分析已有日志：

```powershell
D:\anaconda\python.exe -B -X utf8 tools\analyze_uart.py build\bringup\board_<时间>\mario_uart.bin
```

此前 MMIO 排序问题及兼容措施见 `docs/RTL_MMIO_NOTE.md`；本版保留外设屏障，未修改 CPU 核心。

## 来源与保留

引擎来自 NJU ProjectN LiteNES 固定提交 `9c433f7cf4b4e05d09543bf7e269b23502d1b2b6`。软件许可证和数据说明见 `THIRD_PARTY.md`、`docs/UPSTREAM.json`；`upstream/litenes/` 保留原始文件。

教学仓库随附的 `mario-rom.c` 已嵌入固件，为 40,976 字节 mapper 0 iNES，SHA-256 `f61548fdf1670cffefcc4f0b7bdcdd9eaba0c226e3b74f8666071496988248de`。引擎软件开源许可不代表 Nintendo 游戏数据获得同样许可。

独立版本来源见 `docs/V03_ORIGIN.json`。V01、V02 及已交付 ZIP 保留；原 rv32_soc_Game、仙剑工程和永久保留目录 XXX 未在 V03 优化中改动。
