# rv32_soc Game — rv32_core_01 I2W2 / 100 MHz

《RV32 COURIER》运行在自研 RV32 双发射乱序 RISC-V CPU 上。CPU 来自用户指定的 `D:/workspace/riscv-fpga-soc/XXX/rv32_core_01/workspace/build/rv32cm120_ic2_120_20261102_18`，14 个 CPU/cache RTL 文件原样导入，SHA-256 见 `docs/cpu_rv32_import_manifest.json`。

本演示配置按已确认的选择保留游戏 **100 MHz** 时钟。CPU/cache 源自永久封存的 `rv32_core_01`（`RV32CM120_I2W2_28789b6a5d5e8ad6`），14 个文件原样导入；封存目录只读使用。以前 H5I8 版本的验收记录保留在 `docs/history/game_h5i8_20261102_111746/`，不作为本次结果。

## 硬件配置

| 项目 | 当前配置 |
| --- | --- |
| FPGA | Pango PG2L200H-6FBB676 |
| CPU | RV32，双发射、乱序执行、每周期最多退休两条指令 |
| CPU 时钟 | 100 MHz；125 MHz 差分参考输入 |
| 方向预测器 | B9 / G12 / 全局 H12；本地历史 H5、索引 I8 |
| I-cache | 16 KiB，2 路，64 字节缓存行 |
| D-cache | 8 KiB，2 路，64 字节缓存行，写回 |
| 片上存储 | 代码 SRAM 64 KiB + 数据 SRAM 64 KiB；均由缓存访问 |
| DDR | 保留原游戏 DDR3 与 128→256 位 AXI/HMIC 链路 |
| 显示 | 720×480p60 载波；640×360 RGB565 游戏图像，居中 1:1 显示 |
| UART / 按键 | 115200 baud（868 个 CPU 时钟/位）；按键 1 ms 时基（100000 分频） |

当前实例链路是 `game_board_top → game_soc_top → rv32_game_cpu_tile → rv32_ooo_core + rv32_memory_system`。`rtl/rv32/core/` 是原样导入的 I2W2 CPU；`rtl/rv32/rv32_game_*.sv` 是游戏 SoC 适配层。旧 `rtl/core/`、`rtl/cache/` 和 `soc_cpu_tile_v15.sv` 保留作历史参考，不在当前活动源文件清单中。活动清单由 `sim/build_sim.py:SOURCES` 与 `pds/flow.py` 提供。

## 地址与接口

| 地址 | 用途 |
| --- | --- |
| `0x10000000`，64 KiB | 代码 SRAM，复位入口 |
| `0x20000000`，64 KiB | 数据 SRAM：只读常量、数据、BSS、栈 |
| `0x30000000` | CPU 周期计时器、频率、GPIO、UART |
| `0x60001000` | 按键控制器 |
| `0x60001100` | 视频控制器 |
| `0x82000000` / `0x82100000` | 两个非缓存 RGB565 帧缓冲 |
| `0x84000000..0x8fffffff` | RV32 分类为缓存访问的 DDR，后端限制在本工程 DDR 地址范围内 |

原 RV32 的外围地址分类保持不变。为支持分离的代码/数据 SRAM 和 DDR，关闭了原 CoreMark 板级专用的单段 `ENABLE_DATA_RAM_GUARD`；SRAM 与 DDR 适配层分别检查范围、对齐和响应归属。原游戏保留的 `CACHE_*` 参数不改变 RV32 内部固定地址分类。

CPU 缓存行接口采用 8×64 位传输，适配器转换为原游戏的 4×128 位 DDR 请求；写入必须收到真实下游响应后才完成。片上镜像现在是 **每行 64 位、每个文件 8192 行**，不能直接使用旧核的 32 位 `.mem`。链接地址保持不变。

## 构建与验证

在工程目录运行：

```powershell
D:/anaconda/python.exe sim/run_bringup_probe.py --frames 180
# 等价入口：D:/anaconda/python.exe sim/build_sim.py build --frames 180
```

脚本建立独立证据目录，构建游戏 ELF 和 64 位 SRAM 镜像，先在实际 RV32 RTL 上执行 SRAM / 缓存 / DDR / MMIO 探针，再运行游戏。UART 从管脚解码；标题、确认键进入地图及两个帧缓冲与独立主机参考逐像素比较。原始日志保留；CPU 的 COVERAGE 文本与 UART 混排时另存规范化视图。`--validate-only <证据目录>` 可重新核验既有证据。

根据脚本打印的 `EVIDENCE_DIR` 启动 PDS：

```powershell
D:/anaconda/python.exe pds/run_snapshot.py --probe <EVIDENCE_DIR> --stage full
```

每次建立独立 PDS 运行目录，使用 100 MHz 约束，不修改旧运行。主机工具为 xPack RISC-V GCC 15.2.0、Verilator 5.048、MinGW GCC，以及 PDS 2025.2。需要先检查原生编译告警，再验收 fast/slow 的 setup、hold、recovery、removal、最小脉宽和时钟覆盖。

只核验、不使用板卡：

```powershell
D:/anaconda/python.exe tools/program_game_sram.py --probe <EVIDENCE_DIR> --pds-run <PDS_RUN> --qualify-only --report <报告.json>
```

上板工具使用项目共享锁，默认只写 FPGA SRAM；屏幕、移动、宝箱及对话仍需在实板上人工验收。已实板通过的旧核冻结工程独立保留。

当前迁移状态和最终产物见 `docs/RV32_MIGRATION_STATUS.json`。


本次 rv32_core_01 替换的[离线验收](docs/rv32_core_01_GAME_ACCEPTANCE_20261102.md)和[实板验收](docs/rv32_core_01_BOARD_ACCEPTANCE_20261102.md)均已通过。2026-11-02 SRAM 下载成功，操作者确认标题、移动、宝箱及 NPC 对话正常，120 秒串口采集中收到运行心跳且未见显示提交超时。下载器、串口和共享板卡锁已释放。位流、固件和离线报告位于 `build/releases/rv32_core_01_I2W2_100_20261102_143107/`。
