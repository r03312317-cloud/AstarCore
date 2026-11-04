"""Create the Chinese release guide, architecture notes, figures and PDF report.

All measurements are read from the archived physical-board evidence.  Report
creation neither opens a serial port nor changes the qualified program image.
"""
from pathlib import Path
import csv
import html
import json
import math
import textwrap

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'reports'
OUT.mkdir(exist_ok=True)


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, text):
    (ROOT / name).write_text(textwrap.dedent(text).strip() + '\n', encoding='utf-8')


accept = read('evidence/board/acceptance.json')
comments = read('audit/COMMENT_AUDIT.json')
resources = read('evidence/RESOURCE_SUMMARY.json')
scope = read('audit/SOURCE_SCOPE.json')
qual = read('audit/ANNOTATED_QUALIFICATION.json')
rebuild = read('audit/REBUILD_VERIFICATION.json')
assert rebuild['passed'] and comments['all_code_tokens_and_compiler_pragmas_equal']
BIN = accept['binary_sha256']
BIT = accept['bitstream_sha256']
STAGE = qual['stage2_sha256']
title = accept['title']['weighted_framebuffer_publications_per_second']
active = accept['right_held_active_gameplay']['weighted_framebuffer_publications_per_second']
v02 = accept['v02_title_baseline']['weighted_framebuffer_publications_per_second']
ratio = accept['title_publication_rate_ratio_to_v02']
percent = {k: v['comment_ratio'] * 100 for k, v in comments['totals'].items()}

# Keep the active source lists adjacent to the architecture guide. These are
# the production metric scope; vendor IP remains in its original tree.
write('reports/ACTIVE_RTL.f', '\n'.join('../source/' + n for n in scope['hardware_rtl']))
write('reports/ACTIVE_FIRMWARE.txt', '\n'.join('../source/' + n for n in scope['firmware_source']))

write('README.md', f'''
# Game 超级玛丽 V03：实板测试版架构源码

整理日期：2026-11-04。实板基线：2026-11-03 03:42–03:46（北京时间）V03；用户随后确认“能操作，明显更流畅”。

本包整理了该基线的 CPU、缓存、SoC、显示、输入、装载和游戏固件源码，附原始实板证据与功能/性能报告。本次为独立注释整理版：92 个统计范围内的生产源码文件只增加注释，可逐文件恢复原字节；位流、stage2 与游戏固件均沿用已经实板测试的原件。本次未再次上板，也未重新综合布线。

## 从这里阅读

- [实板功能与性能测试报告 PDF](reports/实板功能与性能测试报告.pdf)：用于技术审阅与归档。
- [报告文字版](reports/实板功能与性能测试报告.md)：数据口径、功能矩阵和证据索引。
- [架构与源码导航](reports/架构与源码导航.md)：真实层级、CPU 参数、地址布局、软件与显示流程。
- [复现与校验说明](reports/复现与校验说明.md)：离线审计、原固件等值重建和后续上板入口。
- [活动 RTL 文件表](reports/ACTIVE_RTL.f) / [生产固件文件表](reports/ACTIVE_FIRMWARE.txt)：按本表定位当前实现。

## 已实测的结果

| 项目 | 结果 | 范围 |
| --- | --- | --- |
| 显示、进入游戏、移动与跳跃 | 实板通过 | UART 记录 + 用户观察确认 |
| 五个板载键输入链路 | 事件齐全 | AM 键值 1、2、4、7、8 |
| 标题画面有效发布率 | {title:.2f} 帧/秒 | 34 个窗口；V02 同口径为 {v02:.2f} |
| 持续右移片段有效发布率 | {active:.2f} 帧/秒 | 6 个完整窗口，约 6.15 秒 |
| 连续采样 | 176 个窗口 / 179.5258 秒 | 64 位 CPU 周期、帧计数、发布计数差值一致 |
| 异常日志 | 未观察到指定错误标记 | 本次 180 秒采集请求的记录范围 |

上述帧率是确认完成的帧缓冲发布次数 / 板上 CPU 计时，不是 60 Hz HDMI 载波。未验证完整通关、音频和更长时间运行；当前音频未实现。短片段结果不能推为全关卡帧率。

## 注释率与源码一致性

| 统计组 | 文件数 | 纯注释行 | 代码行（含混合行） | 注释率 |
| --- | ---: | ---: | ---: | ---: |
| RTL | 49 | 4422 | 10600 | {percent['hardware']:.2f}% |
| 固件 | 43 | 888 | 2067 | {percent['firmware']:.2f}% |
| 合计 | 92 | 5310 | 12667 | {percent['all_production_source']:.2f}% |

口径：纯注释物理行 ÷（纯注释物理行 + 代码物理行），不计空行，代码与注释混合行计为代码；预处理指令计代码。范围见 `audit/SOURCE_SCOPE.json`。ROM 字节数组、厂商生成 IP、历史源码、工具、测试和冻结快照不参与生产架构源码统计，均明确列出。

新增注释以 `[ARCH]` 标记，覆盖模块契约、实际参数、状态/事务归属、恢复与退休边界、MMIO、软件模拟器和双缓冲显示。局部“定位线索”仅说明原版同一物理行出现的赋值目标，不是完整数据依赖证明。逐文件审计保留综合指令注释，不仅比较一般代码 token。

规范化重建得到与实板原件完全相同的 70,932 字节固件，SHA-256：`{BIN}`。

## 目录与使用边界

`source/` 是独立源码工作副本；`source/platform/` 和 `source/build/` 保留冻结产物与已有离线测试。`evidence/` 保存实板 UART、下载结果、用户反馈、V02 对照和离线证据；`audit/` 保存统计、等值检查及重建工具；`baseline/` 保存原始归档。

`source/build` 内的 `BUILT_NOT_BOARD_VALIDATED`、`physical_board_verified=false` 等标志记录构建时或纯离线验证状态，未被改写。最新实板结论由 `evidence/board/acceptance.json` 及其 `user_feedback.json` 支持；自动下载日志中的视觉未确认字段早于用户回执，不能单独覆盖后者。

为支持“只加注释”的源码校验，另新增 `source/tools/source_identity.py`，并调整 `source/tools/board_artifacts.py` 对已审计源码的身份比对；二进制及原始证据仍逐字节 SHA 校验。这是工具变更，未计入生产源码注释率。包内原版本镜像保存在 `baseline/original_preboard.zip`。


`source/README.md`、`source/docs/V03_ORIGIN.json` 继承 V03 实板完成后的状态更新，另保留 `V03_BOARD_ACCEPTANCE_20261103.json`。上板前原始文档和旧包清单仍完整保存在 `baseline/original_preboard.zip`；本包完整性以根目录新的 `MANIFEST_SHA256.json` 为准。全部来源差异另见 `audit/FULL_SOURCE_DIFF_AUDIT.json`。

第三方引擎、游戏资源与厂商 IP 的原有声明完整保留，见 `source/THIRD_PARTY.md`；LiteNES 的许可不构成对任天堂游戏资源的新授权。
''')

write('reports/架构与源码导航.md', '''
# V03 架构与源码导航

本说明对应已经实板验收的 V03 程序映像。本包只对生产源码增加注释，并保留全部构建来源。路径均相对包内 `source/`；当前活动 RTL 以 `soc/sim/build_sim.py:SOURCES` 和 `soc/pds/flow.py:rtl_files()` 为准。历史 `soc/rtl/core/`、上游镜像和部分供体包装文件不代表当前实例化路径。

## 实际硬件层级

```mermaid
flowchart TB
  BOARD[game_board_top：板级时钟、复位、DDR IP、HDMI 引脚]
  SOC[game_soc_top：CPU、内存互连、游戏 MMIO、扫描输出]
  TILE[rv32_game_cpu_tile：100 MHz CPU / Cache 集成]
  CPU[rv32_ooo_core：RV32 双发射乱序核心]
  CACHE[rv32_memory_system：I 16 KiB / D 8 KiB]
  SRAM[代码 / 数据 SRAM，各 64 KiB]
  DDR[行宽转换、仲裁、AXI、HMIC、DDR]
  IO[UART、GPIO、去抖按键、视频发布寄存器]
  HDMI[DDR 扫描、异步 FIFO、TMDS、HDMI]
  BOARD --> SOC
  SOC --> TILE
  TILE --> CPU
  CPU <--> CACHE
  CACHE --> SRAM
  CACHE --> DDR
  CACHE --> IO
  DDR --> HDMI
  IO --> HDMI
```

| 入口 | 作用与阅读重点 |
| --- | --- |
| `soc/rtl/top/game_board_top.sv` | 差分板时钟、CPU/视频 PLL、复位、DDR 和 HDMI 板级连接 |
| `soc/rtl/top/game_soc_top.sv` | tile、游戏 MMIO、CPU/显示共享内存、CDC 和故障收集 |
| `soc/rtl/rv32/rv32_game_cpu_tile.sv` | 当前真正生效的 CPU/cache 参数覆写与非缓存路径 |
| `soc/rtl/rv32/core/rv32_ooo_core.v` | ROB、寄存器映射、发射、完成、精确退休/恢复、CSR 与 LSU |
| `soc/rtl/rv32/core/rv32_ooo_frontend.v` | 8 项有序取指队列、取指信用和预测上下文 |
| `soc/rtl/rv32/core/rv32_hybrid_predictor.v` | 局部方向、GShare、选择器、查询与退休训练 |
| `soc/rtl/rv32/core/rv32_issue_bank.v` | 组合选择单元；候选状态在主核中保存，本模块自身不存储指令 |
| `soc/rtl/rv32/core/rv32_issue_scheduler.v` | 双通路候选、资源/年龄/访存准入与借用 |
| `soc/rtl/rv32/core/rv32_memory_system.v` | I/D cache，同步 RAM、行回填、写回和维护 |
| `soc/rtl/rv32/rv32_game_line_memory.sv`、`rv32_line128_adapter.sv` | SRAM/DDR 范围检查；8×64 位 cache beat 对接 4×128 位请求 |
| `soc/rtl/rv32/rv32_game_periph.sv` | 非缓存 MMIO 和 DDR 单次访问，保持响应所有者 |
| `soc/rtl/game/game_input.sv` | 五键同步、去抖、电平、粘滞事件及重复计时 |
| `soc/rtl/game/game_video_ctrl.sv` | COMMIT、PUBLISHED、ACTIVE_FB 与换帧/错误状态 |
| `soc/rtl/video/soc_hdmi_ddr_scanout.sv`、`soc_hdmi_axi_reader.sv` | DDR 图像读取、跨域 FIFO 和 HDMI 光栅 |
| `soc/rtl/video/soc_hmic_axi_adapter.sv` | AXI 128 位通路与 DDR IP 256 位用户接口适配 |

## 当前 CPU 配置

供体来自用户指定的 `rv32_core_01`，冻结身份为 `RV32CM120_I2W2_28789b6a5d5e8ad6`。供体名字含 120，当前游戏实际运行 **100 MHz**。固件编译目标为 `rv32im_zicsr/ilp32`；不能仅凭译码候选或 CSR MISA 常量宣称所有其他 ISA 扩展已经验收。

| 项目 | 本实例配置 |
| --- | --- |
| 发射 / 退休 | 支持双发射、最多每拍退休两条；实际准入受依赖、资源和顺序边界限制 |
| ROB | 16 项环形编号；序列/年龄区分回绕后的所有者 |
| 发射队列 | 保留 12 个逻辑编号，`ACTIVE_QUEUE_MASK=0x733` 实际启用 7 槽：整数 2+2，复杂 3 |
| 前端 | 8 项队列、2 个取指信用、64 位取指返回 |
| 分支预测 | B9/G12/H12，局部历史 H5 / 索引 I8，提交式 RAS 16 项 |
| 缓存 | I-cache 16 KiB（128 组×2 路×64 B）；D-cache 8 KiB（64 组×2 路×64 B），写回 |
| 运算 | 整数执行、传统乘除后端和低位乘法流；此报告不单独给出其延迟或游戏 IPC |
| 访存 | 准备槽、已提出请求、等待返回的资格分开；恢复不能撤销已被外部接受的事务 |
| 精确状态 | 寄存器/CSR 提交受有序退休约束；计时器等自由运行状态单独更新 |

不要把双发射能力直接写成“IPC=2”，也不要把整机资源占用写成 CPU 单核资源。

## 地址与时钟

| 地址/范围 | 用途 |
| --- | --- |
| `0x10000000` 起 64 KiB | 代码 SRAM；复位装载器入口 |
| `0x10002000` | stage2 运行地址 |
| `0x10004000..0x1000a35f` | 当前固件复制到 ITCM 的热代码，25,440 字节 |
| `0x20000000` 起 64 KiB | 独立数据 SRAM，与代码 SRAM 分离 |
| `0x82000000` / `0x82100000` | 两块非缓存 RGB565 帧缓冲，各 460,800 字节 |
| `0x82000000..0x823fffff` | 扫描器允许的帧缓冲地址窗口 |
| `0x84000000..0x84800000`（不含上界） | APP 预留窗口 8 MiB；当前二进制入口 `0x84000000` |
| `0x84800000..0x85800000`（不含上界） | 16 MiB 堆窗口 |
| `0x85800000..0x87c00000`（不含上界） | 继承的资源包窗口，当前内嵌 ROM 不依赖它 |
| `0x88000000` | 软件栈初始顶端 |

DDR 参数中的逻辑窗口长度不作为物理内存芯片容量证明。板级参考为 125 MHz 差分时钟，CPU 100 MHz，视频像素 27 MHz，TMDS 135 MHz。HDMI 输出 720×480p60 载波；游戏逻辑图像 256×240，经软件放大为居中的 480×360，再放入 640×360 RGB565 缓冲。60 Hz 扫描和新游戏图像更新率分别统计。

## 游戏软件与输入输出

```mermaid
flowchart LR
  KEY[KEY0..4] --> MMIO[硬件同步去抖 / MMIO]
  MMIO --> IN[port/input.c：AM 键值]
  ROM[内嵌 Mapper 0 iNES ROM] --> NES[LiteNES 软件 6502 / PPU]
  IN --> NES
  NES --> PIX[256×240 八位调色板索引画布]
  PIX --> SCALE[port/render.c：每行 16 源像素块比较]
  SCALE --> FB[两块 RGB565 目标，各维护独立历史]
  FB --> PUB[port/board.c：排队、确认、转交所有权]
  PUB --> SCAN[DDR 扫描输出 HDMI]
```

自研 RV32 CPU 执行 LiteNES 的软件 6502 指令模拟、PPU、输入和缩放程序；这版没有单独的硬件 6502，也没有由电脑逐帧送入游戏画面。NJU ProjectN LiteNES 引擎与上游版本身份、许可见 `THIRD_PARTY.md`。

| 软件源码 | 作用 |
| --- | --- |
| `boot/loader.c`、`boot/stage2.c`、`tools/uart_mario.py` | SRAM 装载协议、924 字节 stage2、CRC 校验和 DDR 跳转 |
| `boot/mario_start.S`、`port/ddr.ld` | 启动、栈/BSS、ITCM 热代码与 DDR 映像布局 |
| `port/main.c`、`src/nes/fce.c` | ROM 检查、模拟主循环、逐帧输入/PPU、性能采样 |
| `src/nes/cpu.c`、`cpu-addressing.c`、`cpu-internal.h` | 软件 6502 状态、寻址、操作码与预算 |
| `src/nes/ppu.c` | 背景/精灵、调色板、PPU 寄存器与中断模拟 |
| `port/render.c` | 16→30 横向块展开、240→360 纵向 2/1 行重复、每个物理缓冲独立的差分历史 |
| `port/board.c` | 获取可写后台、异步提交、发布计数/活动地址共同确认、安全超时 |
| `port/input.c` | KEY0 跳跃、KEY1 开始、KEY2 加速、KEY3/4 左右；左右同时对应下 |
| `port/platform.c`、`port/include/mario_profile.h` | 64 位 `mcycle/mcycleh` 一致读取与分阶段耗时 |

V03 的 `FRAME_SKIP=0`；每 NES 帧有 17 次输入轮询。每块目标缓冲保留自己上次使用时的索引画布，不能用“上一模拟帧”统一替代，否则双缓冲会出现残影。异步发布必须等确认后才允许重用原前台，COMMIT 写入本身不等于换帧完成。

## 注释阅读方式

新增 `[ARCH]` 注释与原版权/实现注释并存；原字节恢复和 token 审计见 `audit/COMMENT_AUDIT.json`。工具脚本、测试夹具和历史快照没有为了提高百分比而纳入统计。完整活动源码与排除规则见 `audit/SOURCE_SCOPE.json`。
''')

write('reports/复现与校验说明.md', f'''
# V03 注释整理版复现与校验

先将整个压缩包解压到较短路径，例如 `D:\\MarioV03`。不要只复制 `source/`：身份审计需要并列的 `audit/` 和 `baseline/`。以下命令在包根目录执行。

## 已完成的离线复核

```powershell
D:\\anaconda\\python.exe -B -X utf8 audit/audit_comments.py --verify
D:\\anaconda\\python.exe -B -X utf8 audit/verify_evidence.py
D:\\anaconda\\python.exe -B -X utf8 source/tools/program_mario.py --qualify-only --report audit/LOCAL_QUALIFICATION.json
```

第一项校验注释率、精确恢复 92 个原始源码文件、非注释 token 与综合指令一致；需要 Pygments（本次使用 2.19.2）。第二项直接解析原始 UART，核对 CSV、64 位周期差、模拟帧差、发布帧差、实物右键按住边界和 V02 同口径数据。第三项只检查文件、已有仿真和时序证据，不接触板卡。

本次已在独立目录完成规范化重建：

```powershell
D:\\anaconda\\python.exe -B -X utf8 audit/rebuild_verified_firmware.py
```

交叉编译器路径来自 `source/tools/build_mario.py`：用户目录下 xPacks `riscv-none-elf-gcc-15.2.0-1/bin`，目标 `rv32im_zicsr/ilp32`。该命令从注释源码中移除仅含 `[ARCH]` 的新增行，核对原编译输入 SHA，并把编译路径映射回原基线，以保留 `assert` 使用的 `__FILE__` / `__LINE__`。它不会覆盖已验收的固件。

重建结果：70,932 字节，SHA-256 `{BIN}`，与真实上板程序逐字节相同。普通直接构建注释版也会受到诊断行号/路径变化影响；需要严格复现相同二进制时使用上述规范化入口。不要只用“代码 token 相同”推断诊断字符串也相同。

## 后续演示入口

本次任务未再使用板卡。得到新的上板安排、确认共享板卡空闲后，使用包内原下载入口：

```powershell
D:\\anaconda\\python.exe -B -X utf8 source/tools/program_mario.py --execute --capture-seconds 180
```

它先做离线资格检查，再经 JTAG 写 FPGA SRAM，等待 DDR 装载器，通过 COM14（CP210x，115200/8N1）传入 stage2 和游戏，窗口会打印阶段与 UART 进展。它不写配置 Flash，掉电后需重新装载。共享板卡锁使用原工程的 `docs/BOARD_RESOURCE.lock`；迁移到别的电脑时须调整下载器/PDS 路径、串口及共享锁位置，而不能绕过板卡占用检查。

本机 PDS 路径为 `D:/PDS_2025.2-ads-win64/pango/PDS_2025.2-ads/bin`。输入为 KEY0/S3 跳跃、KEY1/S4 开始或暂停、KEY2/S5 加速、KEY3/S6 左、KEY4/S7 右。按一次开始，进入 1-1 后再长按方向/跳跃；板上 KEY 标号优先。

## 重建硬件时的输入

本包保留活动 RTL、DDR/PLL IP、约束、原始 PDS 日志、25 项平台产物的 SHA 清单和装载器 ITCM/DTCM 初始化镜像。硬件构建入口是 `source/soc/pds/flow.py`；其 `rtl_files()` 把活动 RTL 和厂商 IP 加入同一工程。进行新的 PDS 构建时，应在新的工作副本/独立构建目录中使用 `source/platform/loader-game-itcm.mem`、`loader-game-dtcm.mem` 作为匹配的 64 位、8192 行初始化输入，并核对固定 100 MHz 的时钟与约束。构建期辅助脚本可能仍使用旧工程路径，应据实际新目录配置，不能在永久封存副本内构建。

本次仅做注释整理，未重跑 PDS，因此不声明“新布线产物已实板通过”。实际交付的 `.sbit` 是已验收原件：`{BIT}`。完整平台原件清单见 `source/platform/manifest.json`，时序原始数据库见其 `timing/`。

## 证据和状态文件的时间关系

- `source/build/LATEST_MARIO.json`：编译完成时状态，早于实板测试。
- `source/build/QUALIFICATION.json` 与 `audit/ANNOTATED_QUALIFICATION.json`：纯离线资格检查；不会替用户观察屏幕。
- `evidence/board/result.json`：自动下载和串口阶段结果，视觉字段仍未确认。
- `evidence/board/user_feedback.json`、`acceptance.json`：测试完成后的用户确认及合并验收结果。

原始记录按产生时的事实保存，不通过改写历史布尔值制造“通过”。报告以合并验收与原始 UART/用户回执相互佐证。若后续改动程序、时钟、渲染、缓存参数或位流，不能继续套用本次实板结论，应新增对应验证。
''')

functional_rows = [
    ('SRAM 配置与启动', '实板通过', '器件 ID 00603899；下载返回 0，DONE=1、PLL lock=1；DDR 装载器就绪。'),
    ('游戏装载与首检查点', '实板通过', 'stage2 就绪、分块回读 CRC 与总 CRC；传输 8.672 秒；RAM=6bac34ff、PC=90d4。'),
    ('HDMI 标题 / 进入 1-1', '实板通过', '用户对“开始、进入地图、右移、跳跃”流程确认“能操作，明显更流畅”。'),
    ('移动与跳跃', '实板通过', '用户观察确认；右键保持期间 X=43、75、106、135、162、190。'),
    ('五个板载按键输入', '实板通过', 'AM 1、2、4、7、8 的按下/松开事件均在原始 UART 出现。'),
    ('连续采样与 64 位计时', '实板通过', '176 个窗口 / 179.5258 秒；计时高字 0→4，周期/帧/发布差值一致。'),
    ('暂停恢复、碰撞掉命', '本机模拟通过', '1000 帧游戏回归及参考逐帧比较；未据此宣称完整实板功能验收。'),
    ('显示像素与缓冲边界', '离线通过', '130 帧、两目标缓冲、29,952,000 像素比较；非零初值及边界检查。'),
    ('发布所有权与错误路径', '离线通过', '7 个场景；延迟、回绕、超时、接纳后错误和扫描故障；负对照检出旧错误。'),
    ('实际 CPU / Cache / SoC', 'RTL 仿真通过', '同一固件前四个 NES 帧 RAM/PC 一致、HDMI 像素一致；完整游戏未做 RTL 回归。'),
    ('音频 / 完整通关 / 长期运行', '未覆盖', '音频未实现；未验证整关完成及超过本次记录的长期稳定性。'),
]

write('reports/实板功能与性能测试报告.md', f'''
# Game 超级玛丽 V03 实板功能与性能测试报告

整理日期：2026-11-04；测试日期：2026-11-03；时区：Asia/Shanghai。结论对应 100 MHz、70,932 字节 V03 固件与冻结平台位流。报告由实板原始记录和源码生成，本次注释整理未重新使用板卡。

## 1. 验收结论

显示、开始进入 1-1、移动和跳跃已由用户观察确认；五个实体键的输入事件完整。请求采集 180 秒，获得 176 个性能窗口，板上累计样本时间 179.52579217 秒，最终 NES 帧号 3831。记录内未发现 `MARIO_VIDEO_TIMEOUT`、`MARIO_VIDEO_BAD_REQUEST`、`MARIO_ROM_REJECTED`、`MARIO_EXIT` 或 `TRAP=` 标记；结束时最近进展记录距采集终点 0.406 秒。此结论限本次采样范围。

用户原话：“能操作，明显更流畅”。测试提示为 KEY1 开始、进入 1-1 后 KEY4 右移与 KEY0 跳跃。没有独立录屏，本报告以原始 UART 与用户回执说明显示和操作结果。

## 2. 架构与平台

PG2L200H（-6，FBB676），PDS 2025.2；自研 RV32 双发射乱序 RV32 核，CPU 100 MHz，16 项 ROB，7 个实际启用的发射槽，I-cache 16 KiB / D-cache 8 KiB。固件采用 `rv32im_zicsr/ilp32`，裸机运行 LiteNES 软件 6502/PPU。CPU、MMIO 输入和 DDR 图像扫描均在 FPGA SoC 中，电脑负责装载及日志采集。

HDMI 720×480p60；游戏源 256×240，软件最近邻放大到 480×360，置于 640×360 RGB565 双缓冲。显示载波 60 Hz 不等于新游戏图像 60 帧/秒。完整参数与文件路径见《架构与源码导航》。

## 3. 功能测试矩阵

| 项目 | 证据级别 / 结果 | 已证明范围 |
| --- | --- | --- |
''' + '\n'.join('| ' + ' | '.join(row) + ' |' for row in functional_rows) + f'''

按键映射：KEY0/USER_BUTTON0/S3 跳跃；KEY1/S4 开始或暂停；KEY2/S5 加速/有能力时开火；KEY3/S6 左；KEY4/S7 右。KEY2 已证明输入事件，未单独验证加速幅度或火力状态。暂停恢复、碰撞掉命在本机回归通过，不写成独立实板验收项。此游戏没有旧像素游戏的宝箱/NPC 交互。

## 4. 性能方法与结果

每个采样窗口以板上 100,000,000 Hz 的 64 位周期计时；标题和活动片段均使用总次数除总时间，而非简单平均各窗口 FPS：

`有效发布率 = 100000000 × ΣVDELTA / ΣCYCLES`

`模拟 NES 帧率 = 100000000 × ΣDELTA / ΣCYCLES`

前者使用已确认完成的帧缓冲发布计数，后者使用模拟器完成帧计数。装载、下载、初始化时间不进入上述性能分母。原始 UART、CSV、各窗口 64 位时间戳、模拟帧与发布差值已复算一致。

| 场景 | 窗口 | 有效发布率（帧/秒） | 解释 |
| --- | ---: | ---: | --- |
| V03 标题：MODE=0 且 X=40 | 34 | {title:.6f} | 可与 V02 相同判据对照 |
| V02 标题：相同判据 | 28 | {v02:.6f} | 原实板 UART 同口径重算 |
| V03 持续右移：MODE=1、TASK=3 | 6 | {active:.6f} | 6.15019386 秒短活动片段 |

V03 标题有效发布率为 V02 的 {ratio:.6f} 倍。两版标题模拟 NES 速度分别为 19.8803 和 19.9381 帧/秒；主要改善是 `FRAME_SKIP=0`、异步发布和渲染组织下的实际图像发布频率，不能据此宣称 CPU 运算性能翻倍或所有关卡翻倍。

右键实物按住边界为 NES 帧 2239→2381，只选取完整落在该范围内的 6 个窗口；每窗口发布率范围 18.1275–23.5953 帧/秒，角色 X 值连续增加。MODE=1 的其他汇总可能含暂停、过场或站立，不用作“持续游玩帧率”。全部窗口混合发布率为 21.2504，仅供完整性参考。

![176 个采样窗口的有效发布率](publication_timeline.png)

![标题同口径对照](title_comparison.png)

标题阶段占总周期：软件 6502 CPU 34.7105%、背景绘制 31.6378%、缩放 13.5651%、画布清理 9.5105%、输入 4.0989%、精灵 3.4067%、发布 0.2104%。采样、串口和未归入这些阶段的工作会使这些比例之和小于 100%。这说明发布等待开销已经很小，不能把全部剩余耗时归于显示等待。

## 5. 时序和资源

结果来自与交付位流绑定的冻结 PDS 日志及报告数据库。快/慢角 setup、hold、recovery、removal、最小脉宽共 10 组均无失败端点；最差 setup +0.405 ns，最差 hold +0.041 ns，no_clock=0。尚有 39 项输入和 79 项输出缺少 delay 约束，因此结论只覆盖现有约束内路径。

| 资源 | 使用 / 可用 | 占比 |
| --- | ---: | ---: |
''' + '\n'.join(f"| {label} | {resources[key]['used']:,} / {resources[key]['available']:,} | {resources[key]['percent']:.2f}% |" for key, label in [('LUT','LUT'),('FF','FF'),('DRM_grid','DRM（grid）'),('APM_grid','APM（grid）'),('IO','I/O'),('GPLL','GPLL')]) + f'''

以上为含 CPU、缓存、DDR、视频和外设的**整机 SoC**。APM grid=5 与 APM 实体=8 使用不同计数单位；DRM grid=84 不应与 DRM18K/36K 实体数量相加。当前实测频率为 100 MHz，不以供体名称或其他工程的 120 MHz 结果替代。

## 6. 注释整理与同版证明

49 个 RTL 文件 + 43 个生产固件文件，纯注释 5,310 行、代码 12,667 行，注释率 {percent['all_production_source']:.2f}%（RTL {percent['hardware']:.2f}%，固件 {percent['firmware']:.2f}%）。公式为纯注释物理行除以非空物理行，混合行算代码；统计范围及排除项写入 `audit/SOURCE_SCOPE.json`。ROM 数组、厂商生成 IP、历史代码、工具、测试和快照不参与该生产架构指标。

全部 92 个文件在移除新增 `[ARCH]` 行后可恢复原字节；非注释 token 与综合指令也一致。考虑 `__FILE__`/`__LINE__` 会进入断言诊断，另完成规范化重建，生成同一 70,932 字节固件 SHA。本次未重新综合或上板，复用的是同一原件与其已有实板证据。校验工具增加了严格的已审计注释版身份匹配；位流和固件继续检查原始 SHA。

## 7. 产物身份与证据索引

| 产物 | SHA-256 |
| --- | --- |
| `source/platform/game_board_top.sbit` | `{BIT}` |
| `source/platform/stage2.bin` | `{STAGE}` |
| `source/build/mario_20261103_025102_904664/mario.bin` | `{BIN}` |
| `evidence/board/mario_uart.bin` | `{accept['raw_uart_sha256']}` |

| 证据 | 文件 / 范围 |
| --- | --- |
| E1 实板合并验收 | `evidence/board/acceptance.json`、`user_feedback.json` |
| E2 原始采集 | 同目录 `mario_uart.bin`、`frame_samples.csv`、`progress_timeline.json` |
| E3 下载与装载 | 同目录 `scan.log`、`program.log`、`result.json`、`mario_runtime.json` |
| E4 V02 对照 | `evidence/baseline_v02/`；原始 UART 与性能报告 |
| E5 离线功能 | `evidence/native/`、`render/`、`video_queue/`、`rtl/`；原始完整冻结输入另见 `source/build/` |
| E6 时序资源 | `source/platform/pds.log`、`timing/`、`manifest.json`，`evidence/resource_table.txt` |
| E7 注释与二进制等值 | `audit/COMMENT_AUDIT.json`、`REBUILD_VERIFICATION.json`、`ANNOTATED_QUALIFICATION.json` |
| E8 独立复算 | `audit/verify_evidence.py` 与 `PERFORMANCE_RECALCULATION.json` |

构建时/自动下载阶段的历史未确认字段保留原样；后续用户回执记录在 E1。本报告未将本机测试、RTL 仿真和实板观察混为同一证据级别。第三方来源、许可和资源声明见 `source/THIRD_PARTY.md`。
''')


def create_figures():
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib import font_manager
    font = font_manager.FontProperties(fname=r'C:\Windows\Fonts\msyh.ttc')
    plt.rcParams.update({'axes.spines.top': False, 'axes.spines.right': False,
                         'figure.facecolor': 'white', 'axes.facecolor': 'white',
                         'font.size': 9, 'axes.labelcolor': '#334155',
                         'xtick.color': '#475569', 'ytick.color': '#475569'})
    with (ROOT / 'evidence/board/frame_samples.csv').open(newline='') as handle:
        samples = [{k: int(v) for k, v in row.items()} for row in csv.DictReader(handle)]
    elapsed = []; now = 0
    for s in samples:
        now += s['CYCLES'] / 100_000_000
        elapsed.append(now)
    rates = [100_000_000 * s['VDELTA'] / s['CYCLES'] for s in samples]
    fig, ax = plt.subplots(figsize=(7.05, 2.65), dpi=180)
    ax.plot(elapsed, rates, color='#94a3b8', lw=0.9, label='全部窗口（含过场/暂停等）')
    for color, label, pred in [('#186eac','标题窗口',lambda s:s['MODE']==0 and s['X']==40),
                               ('#d66a36','持续右移完整窗口',lambda s:s['MODE']==1 and s['TASK']==3 and s['MARIO_FRAME']-s['DELTA']>=2239 and s['MARIO_FRAME']<=2381)]:
        points = [(x, y) for x, y, s in zip(elapsed, rates, samples) if pred(s)]
        ax.scatter(*zip(*points), color=color, s=12, zorder=3, label=label)
    ax.set_xlim(0,180); ax.set_ylim(0, max(rates)*1.16)
    ax.set_xlabel('累计采样 CPU 时间 / 秒（不含装载）',fontproperties=font)
    ax.set_ylabel('确认发布 / 秒',fontproperties=font)
    ax.grid(axis='y', alpha=.16)
    ax.legend(prop=font,loc='upper left',ncol=1,frameon=False,fontsize=8)
    fig.tight_layout(pad=1.3)
    fig.savefig(OUT/'publication_timeline.png');plt.close(fig)
    fig, ax = plt.subplots(figsize=(6.6,2.55),dpi=180)
    bars=ax.barh([1,0],[v02,title],color=['#a4b8c8','#186eac'],height=.48)
    ax.set_yticks([1,0],['V02 标题（28 窗口）','V03 标题（34 窗口）'],fontproperties=font)
    for bar,value in zip(bars,[v02,title]):
        ax.text(value+.35,bar.get_y()+bar.get_height()/2,f'{value:.2f}',va='center',fontsize=11,color='#12344a')
    ax.set_xlim(0,24);ax.set_xlabel('确认发布 / 秒；相同标题采样判据',fontproperties=font)
    ax.grid(axis='x',alpha=.16);ax.set_axisbelow(True)
    ax.text(.98,.95,f'{ratio:.3f}×',ha='right',va='top',transform=ax.transAxes,fontsize=16,color='#186eac')
    fig.tight_layout(pad=1.3);fig.savefig(OUT/'title_comparison.png');plt.close(fig)


def create_pdf():
    from reportlab.pdfgen import canvas
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_LEFT
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.platypus import Paragraph, Table, TableStyle
    from reportlab.lib.utils import ImageReader
    pdfmetrics.registerFont(TTFont('Yahei',r'C:\Windows\Fonts\msyh.ttc',subfontIndex=0))
    pdfmetrics.registerFont(TTFont('YaheiBold',r'C:\Windows\Fonts\msyhbd.ttc',subfontIndex=0))
    pdfmetrics.registerFontFamily('Yahei',normal='Yahei',bold='YaheiBold',italic='Yahei',boldItalic='YaheiBold')
    W,H=A4; margin=43; width=W-2*margin
    c=canvas.Canvas(str(OUT/'实板功能与性能测试报告.pdf'),pagesize=A4)
    c.setTitle('Game 超级玛丽 V03 · 实板功能与性能测试报告')
    c.setAuthor('rv32_soc / V03 archived evidence')
    body=ParagraphStyle('body',fontName='Yahei',fontSize=9.1,leading=15,wordWrap='CJK',textColor=colors.HexColor('#243a4b'))
    small=ParagraphStyle('small',parent=body,fontSize=7.7,leading=12)
    th=ParagraphStyle('th',parent=body,fontName='YaheiBold',fontSize=8,leading=12,textColor=colors.white)
    cell=ParagraphStyle('cell',parent=body,fontSize=8.1,leading=12.5)
    y=0; page=0
    def p(text,style=body,gap=9):
        nonlocal y
        par=Paragraph(text,style);_,height=par.wrap(width,y-45)
        if y-height < 42: raise RuntimeError(f'PDF page {page} overflows: {text[:45]}')
        par.drawOn(c,margin,y-height);y-=height+gap
    def section(text):
        nonlocal y
        y-=5;c.setFont('YaheiBold',12);c.setFillColor(colors.HexColor('#155f8d'));c.drawString(margin,y,text);y-=23
    def table(headers,rows,widths):
        nonlocal y
        data=[[Paragraph(html.escape(str(v)),th) for v in headers]]
        data += [[Paragraph(html.escape(str(v)),cell) for v in row] for row in rows]
        t=Table(data,colWidths=widths,hAlign='LEFT')
        t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#174e6a')),
            ('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8),
            ('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7),
            ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.HexColor('#f0f5f8'),colors.white]),
            ('LINEBELOW',(0,0),(-1,0),.4,colors.HexColor('#174e6a')),
            ('LINEBELOW',(0,1),(-1,-1),.3,colors.HexColor('#d9e3e9'))]))
        _,height=t.wrap(width,y-45)
        if y-height < 42:raise RuntimeError(f'PDF table overflow on page {page}, bottom={y-height}')
        t.drawOn(c,margin,y-height);y-=height+13
    def start(title_text,kicker):
        nonlocal page,y
        if page:c.showPage()
        page+=1;c.setFillColor(colors.HexColor('#174e6a'));c.rect(0,H-9,W,9,fill=1,stroke=0)
        c.setFont('Yahei',8);c.setFillColor(colors.HexColor('#5f798b'))
        c.drawString(margin,H-35,'RV32_SOC  /  GAME MARIO V03')
        c.drawRightString(W-margin,H-35,'归档报告 · 2026-11-04')
        c.setFont('YaheiBold',21);c.setFillColor(colors.HexColor('#12344a'));c.drawString(margin,H-73,title_text)
        c.setFont('Yahei',9);c.setFillColor(colors.HexColor('#637c8f'));c.drawString(margin,H-95,kicker)
        c.setStrokeColor(colors.HexColor('#d7e3ea'));c.line(margin,40,W-margin,40)
        c.setFont('Yahei',7.5);c.drawString(margin,27,'100 MHz · 实板记录与源码一致性审计 · 保留原始证据')
        c.drawRightString(W-margin,27,f'{page} / 8')
        y=H-121
    def image(name,height):
        nonlocal y
        if y-height < 42:raise RuntimeError('PDF image overflow')
        c.drawImage(ImageReader(str(OUT/name)),margin,y-height,width=width,height=height,preserveAspectRatio=True,anchor='c',mask='auto');y-=height+8
    start('实板功能与性能测试报告','超级玛丽 V03 / 归档基线 2026-11-03 / 注释整理版')
    p('V03 已完成真实 FPGA 的游戏演示：用户确认显示、开始进入游戏、移动与跳跃正常，并反馈“能操作，明显更流畅”。本报告保留确认发布率、短活动片段与离线回归的各自范围。')
    table(['关键结果','数值 / 结论','采样范围'],[
        ['标题图像有效发布率',f'{title:.2f} 帧/秒','34 个窗口，MODE=0、X=40'],
        ['持续右移片段',f'{active:.2f} 帧/秒','6 个完整窗口，共 6.1502 秒'],
        ['连续性能记录','176 个窗口 / 179.5258 秒','请求采集 180 秒，最终 NES 帧号 3831'],
        ['标题对照 V02',f'{ratio:.3f} 倍有效发布率',f'V02 {v02:.2f} → V03 {title:.2f} 帧/秒'],
        ['游戏操作','实板通过','输入事件 + 用户显示/移动/跳跃回执'],
    ],[135,159,width-294])
    section('版本与实板身份')
    p('测试时间为北京时间 2026-11-03 03:42–03:46；CPU 100 MHz，固件 70,932 字节。JTAG SRAM 下载返回 0，DONE=1、PLL lock=1；未写配置 Flash。stage2 和游戏通过串口装载，游戏传输耗时 8.672 秒。')
    p('本次独立整理源码、注释与报告，未再次上板或重新综合布线。新增注释可移除并恢复原文件；规范化重建与原实板固件逐字节相同。完整 SHA-256 和证据位置见第 8 页。')
    section('范围说明')
    p('帧率为已确认的帧缓冲发布次数除以板上 CPU 时间。HDMI 扫描载波为 60 Hz；本次游戏图像更新约 20 帧/秒。持续右移数据来自短片段，不能推广为整关帧率。音频未实现，完整通关与更长时间运行尚未验证。')
    p('原始来源：evidence/board/acceptance.json、mario_uart.bin、user_feedback.json；报告复算工具：audit/verify_evidence.py。',small)

    start('CPU 与 SoC 架构','实际实例化路径 / 裸机软件模拟器 / 共享 DDR 显示')
    p('板级 game_board_top → game_soc_top → rv32_game_cpu_tile → rv32_ooo_core + rv32_memory_system。CPU 执行 LiteNES 软件 6502 / PPU、输入和缩放；DDR 控制器与视频扫描链路输出 HDMI，电脑负责下载和日志采集。')
    table(['项目','本版实际配置'],[
        ['CPU','RV32 双发射乱序 RV32 核，100 MHz；固件 rv32im_zicsr / ilp32'],
        ['执行与退休','最多双发射、双退休；16 项 ROB；精确异常与有序提交'],
        ['发射容量','12 个逻辑编号，ACTIVE_QUEUE_MASK=0x733 实际启用 7 槽（2+2+3）'],
        ['前端与预测','8 项取指队列，2 信用；B9/G12/H12、局部 H5/I8、提交 RAS 16 项'],
        ['缓存与片上存储','I-cache 16 KiB；D-cache 8 KiB、写回；64 字节行、各两路；代码/数据 SRAM 各 64 KiB'],
        ['DDR 通路','8×64 位 cache beat → 4×128 位请求；AXI / HMIC 对接 256 位 DDR 用户接口'],
    ],[103,width-103])
    section('软件到图像的流程')
    p('实体键 → 硬件同步去抖 → MMIO → port/input.c → LiteNES（软件 6502 + PPU）→ 256×240 索引画布 → port/render.c 差分缩放 → RGB565 双缓冲 → 发布确认 → DDR 扫描 → TMDS / HDMI。')
    table(['地址 / 时钟','用途'],[
        ['0x10000000 / 0x10002000','代码 SRAM 装载器 / stage2；热代码复制至 0x10004000'],
        ['0x82000000 / 0x82100000','两块非缓存帧缓冲，各 460,800 字节（640×360×2）'],
        ['0x84000000 / 0x84800000','APP 入口 / 堆起点；栈初值 0x88000000'],
        ['CPU 100 / 像素 27 / TMDS 135 MHz','720×480p60 载波；480×360 游戏图像居于 640×360 缓冲'],
    ],[180,width-180])
    p('双发射描述的是架构能力，未测游戏 IPC；逻辑 DDR 窗口不作为物理芯片容量证明。源码入口及完整地址表见《架构与源码导航》。',small)

    start('功能验收与测试边界','实板观察、输入记录、本机回归与 RTL 仿真分别列示')
    table(['项目','证据级别','已经证明的范围'],functional_rows,[102,84,width-186])
    p('实板回执为用户对 KEY1 开始、KEY4 右移、KEY0 跳跃测试的确认；本包无独立录屏。五键事件完整不代表所有能力（如火力）已经分别实测。',small)

    start('帧率的计时与采样','100 MHz 板上 64 位周期 / 176 个窗口 / 区分模拟帧与有效发布')
    p('<b>有效发布率 = 100,000,000 × ΣVDELTA ÷ ΣCYCLES</b><br/>模拟 NES 帧率改用 ΣDELTA；按总次数除总时间加权，不简单平均窗口 FPS。计时不含下载、装载与初始化。')
    image('publication_timeline.png',195)
    table(['场景','窗口 / 时间','有效发布率'],[
        ['V03 标题（MODE=0、X=40）','34 个窗口',f'{title:.6f} 帧/秒'],
        ['V03 实物右键保持片段','6 个窗口 / 6.1502 秒',f'{active:.6f} 帧/秒'],
        ['右移片段窗口范围','NES 帧 2239→2381','18.1275–23.5953 帧/秒'],
    ],[206,151,width-357])
    p('右移只选取完整落在实物右键按下/松开边界内且 MODE=1、TASK=3 的窗口。角色 X=43、75、106、135、162、190，支持该片段处于活动移动状态。其他 MODE=1 数据可能包含暂停、过场或站立，不能替代活动测试。')
    p('原始 UART 的 64 位周期差、NES 帧差和 VID 差均逐窗口核对；高字从 0 变化至 4，未受 32 位计数回绕影响。采集终点最近进展年龄 0.406 秒，记录内未发现指定视频超时、拒绝、退出或 TRAP 标记。')
    p('图中灰色曲线包含不同场景，仅展示完整采样；不以混合窗口的 21.2504 帧/秒作为全程活动游玩指标。',small)

    start('改进对照与运行成本','相同标题判据 / V02 与 V03 / 阶段周期分布')
    image('title_comparison.png',180)
    p(f'标题确认发布率由 {v02:.4f} 提升至 {title:.4f} 帧/秒，为 {ratio:.3f} 倍。两版标题模拟器速度约为 19.94 与 19.88 帧/秒；本结果说明图像发布改善，不能写成 CPU 运算性能翻倍。V03 使用 FRAME_SKIP=0、异步发布和分块差分缩放。')
    costs=accept['title']['profile_percent_of_elapsed']
    names=[('CPU','软件 6502 指令模拟'),('BG','背景绘制'),('SCALE','缩放与 RGB565 写入'),('CLEAR','索引画布清理'),('INPUT','输入轮询与映射'),('SPR','精灵绘制'),('PUB','图像发布阶段')]
    table(['阶段','标题阶段耗时占比','对应工作'],[[k,f'{costs[k]:.2f}%',n] for k,n in names],[66,130,width-196])
    p('比例分母为窗口总周期；未归入这些阶段的采样、日志及其他工作使总和低于 100%。当前主要成本为软件 6502、背景和缩放。发布阶段约 0.21%，不能把剩余全部耗时归于换帧等待。',small)

    start('100 MHz 时序与整机资源','冻结 PDS 2025.2 报告 / 与交付位流绑定 / 现有约束范围')
    p('快/慢角 setup、hold、recovery、removal、最小脉宽共 10 组检查均无失败端点。最差 setup 为 +0.405 ns，最差 hold 为 +0.041 ns，no_clock=0。仍有 39 项输入、79 项输出缺少 delay 约束；本结论限现有约束内路径。')
    table(['资源（整机）','使用 / 可用','计算占比'],[
        [label,f"{resources[k]['used']:,} / {resources[k]['available']:,}",f"{resources[k]['percent']:.2f}%"]
        for k,label in [('LUT','LUT'),('FF','FF'),('DRM_grid','DRM（grid）'),('APM_grid','APM（grid）'),('IO','I/O'),('GPLL','GPLL')]
        ],[160,197,width-357])
    p('资源包含 CPU、缓存、DDR 控制/适配、视频和外设，不能标为 CPU 单核占用。PDS 的 grid 与实体是不同计数单位：APM 为 5 grid 或 8 个实体，不相加；DRM 为 84 grid。报告百分比由原始数量计算，PDS 表中可能显示向上取整值。')
    section('按键与现场演示')
    table(['板上标号','软件行为','本次证据'],[
        ['KEY0 / USER_BUTTON0 / S3','跳跃','实板输入 + 用户跳跃确认'],
        ['KEY1 / USER_BUTTON1 / S4','开始 / 暂停','开始实板确认；暂停恢复本机回归'],
        ['KEY2 / USER_BUTTON2 / S5','加速 / 有能力时开火','已记录按下/松开，未单独验火力'],
        ['KEY3 / S6；KEY4 / S7','左；右','两个键事件齐全；右移实板确认'],
    ],[177,142,width-319])
    p('本次只整理与复核现有结果，不占用开发板；下次上板使用原下载入口并新增测试记录。',small)

    start('源码注释与同版复现','生产源码范围 / 严格物理行统计 / 原字节、token 与固件三层核对')
    table(['生产源码组','文件','纯注释行','代码行','注释率'],[
        ['RTL','49','4,422','10,600',f"{percent['hardware']:.2f}%"],
        ['固件','43','888','2,067',f"{percent['firmware']:.2f}%"],
        ['合计','92','5,310','12,667',f"{percent['all_production_source']:.2f}%"],
    ],[116,61,100,116,width-393])
    p('口径为纯注释物理行 ÷（纯注释行 + 代码行），空行不计，混合行算代码，预处理指令算代码。范围由 audit/SOURCE_SCOPE.json 固定：49 个当前平台 RTL 与 43 个生产 C/H/S/LD。排除 ROM 数组、厂商生成 IP、历史/上游镜像、工具、测试和冻结快照。')
    section('一致性结果')
    p('① 新增注释以 [ARCH] 标记；移除后 92 个文件全部恢复原字节。<br/>② 非注释 token 与综合指令注释保持相同；模块参数、信号和指令行为未修改。<br/>③ 从注释版派生规范化编译输入，恢复诊断路径/行号，重建 70,932 字节固件，与已实板程序 SHA-256 相同。')
    p('assert 可把 __FILE__ / __LINE__ 放入固件。为避免仅加注释/迁移目录改变二进制，等值重建移除新增标记行并映射原编译路径；这一步依据原始输入清单逐文件校验，不从旧 .bin 伪造重建结果。')
    section('工具与记录的区别')
    p('source/tools/source_identity.py 与 board_artifacts.py 允许确切、已审计的注释版源码匹配原源码身份。固件、位流及原始证据继续按原始字节 SHA 检查；负对照已确认修改执行 token 会被拒绝。')
    p('历史 BUILT_NOT_BOARD_VALIDATED、离线 physical_board_verified=false 与下载阶段视觉未确认字段保留原样。实板最终结论由后续 acceptance.json 与用户回执补充。本次未重新综合布线，也未新增上板结论。')
    section('离线复核入口')
    p('audit/audit_comments.py --verify<br/>audit/verify_evidence.py<br/>audit/rebuild_verified_firmware.py<br/>source/tools/program_mario.py --qualify-only',small)

    start('交付身份与证据索引','原始 UART、用户回执、冻结平台、离线回归与审计结果共同归档')
    for label,digest in [('游戏固件 / 70,932 字节',BIN),('平台位流 / 9,188,552 字节',BIT),('stage2 / 924 字节',STAGE),('原始实板 UART',accept['raw_uart_sha256'])]:
        p('<b>'+label+'</b><br/>'+digest,small,gap=9)
    table(['编号','包内位置','用途'],[
        ['E1','evidence/board/acceptance.json、user_feedback.json','合并验收 / 用户视觉与操作确认'],
        ['E2','evidence/board/mario_uart.bin、frame_samples.csv','原始串口与逐窗口数据'],
        ['E3','evidence/board/program.log、result.json','JTAG、装载和自动阶段结果'],
        ['E4','evidence/baseline_v02/','相同标题口径实板对照'],
        ['E5','evidence/native、render、video_queue、rtl','本机 / 像素 / 所有权 / RTL 离线证据'],
        ['E6','source/platform/pds.log、timing、manifest.json','资源 / 时序 / 位流来源与 SHA'],
        ['E7','audit/COMMENT_AUDIT.json、REBUILD_VERIFICATION.json','注释统计、源码恢复、固件等值重建'],
        ['E8','audit/PERFORMANCE_RECALCULATION.json','直接从原始 UART 的独立复算'],
    ],[36,280,width-316])
    p('完整源码导航、重建命令、原始归档和第三方声明均随包提供。图表展示已记录样本；未测音频、完整通关和超过本次采集范围的长期稳定性。',small)
    c.save()
    (OUT/'REPORT_FACTS.json').write_text(json.dumps({
        'date':'2026-11-04','board_date':'2026-11-03','pages':page,
        'binary_sha256':BIN,'bitstream_sha256':BIT,'title_publications_fps':title,
        'held_right_publications_fps':active,'production_comment_percent':percent,
        'new_board_session':False,'new_place_and_route':False,
        'sources':['evidence/board/acceptance.json','audit/COMMENT_AUDIT.json','audit/REBUILD_VERIFICATION.json']},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Report PDF authored:',OUT/'实板功能与性能测试报告.pdf','pages',page)


if __name__ == '__main__':
    create_figures()
    create_pdf()
