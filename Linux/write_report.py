"""Produce the final integration report only after the full RTL acceptance passes."""
from pathlib import Path
import json
R=Path(__file__).resolve().parent
def main():
    v=json.loads((R/'reports/offline_verification.json').read_text(encoding='utf-8'))
    if not v['all_offline_checks_passed']:raise SystemExit('Wait for full Linux RTL acceptance')
    s=v['source_identity'];b=v['linux_full_system'];c=b['counter_values'];cpu=v['resources_hierarchical_logical']['+ processor(rv32_ooo_core)'];soc=v['resources_hierarchical_logical']['+ cpu(rv32_linux_soc_top)']
    unchanged=sum(x['unchanged_after_newline_normalization'] for x in s['modules'])
    report=f'''# rv32_core_01 CPU 替换及 Linux 离线验证报告

本次将 Linux＋UART＋HDMI 工程的 CPU 改为 `{s['source_build_id']}` 的 Linux 适配版。定向 RTL 回归、实际 CPU RTL 执行 Linux 与用户态交互、PDS 2025.2 综合布局布线均已通过，新位流已生成。**本版本尚未上板；不能把原版本的实板结论移用于本版。**

## 来源与工程入口

- 当前工程：`D:/workspace/riscv-fpga-soc/Soc_linux/linux_core01_20261102_01`。
- 用户指定来源：`D:/workspace/riscv-fpga-soc/XXX/rv32_core_01`，实际读取其中 `workspace/build/rv32cm120_ic2_120_20261102_18/snapshot/rtl` 的 14 个文件。
- 原核心 `rv32_ooo_core.v` SHA-256：`a7f5f6158bd1f58d74762910c5334154e0b444fa47eded9243873ee34049f68b`。
- 封存目录作为只读输入。14 个源文件在导入和最终核验时均与来源哈希一致。
- `rtl/` 是当前 CPU、缓存、MMU 和外设源码；顶层为 `inputs/gui/soc_linux_gui_top.sv`。PDS 采用 `source_manifest.json` 的 {s['ordered_hdl_sources']} 个有序 HDL 输入及 {s['pds_inputs_verified']} 个文件哈希。
- `provenance/core01_original/` 保存原始字节，`provenance/linux_before/` 保存原 Linux RTL，`provenance/b4_common_ancestor/` 保存共同祖先，`provenance/linux_adaptation/` 保存相对新核心的补丁。14 个来源模块中 {unchanged} 个经换行规范化后完全相同，其余用于移植 Linux 接口。

## 为什么需要 Linux 适配

封存 Core_01 是裸机 CPU 配置。Linux 工程需要 M/S/U 特权级、异常及中断委托、SRET、SATP/SFENCE.VMA、Sv32 页故障和 RV32A 原子访存接口。本次以 B4 为共同祖先移植原 Linux 工程已经使用的这些逻辑，保留新核心的执行、调度、预测器、流水线元数据和双路缓存实现。

主要合并点是：核心的 CSR/特权及陷阱逻辑、执行解码、AMO/SFENCE 标志、取指页故障传播、缓存的 Linux 物理地址分类、SoC 接口连接。优化后负载唤醒判断也使用完整的总线错误／页故障条件。原子事务的异常、中断及保留状态沿用 Linux 适配逻辑。

Linux SoC 的预测器配置为 B9/G12/H12；I-cache 128 组×2 路×64 B＝16 KiB，D-cache 64 组×2 路×64 B＝8 KiB。保留跨行取指命中路径。访存继续采用 `LOAD_BYPASS=0` 及保守的前瞻设置，避免地址翻译前投机访问 MMIO。

CPU 配置时钟为 **27 MHz**，板级 DDR、HDMI 和固件保持原集成配置。原裸机的 120 MHz 和 CoreMark/MHz 成绩不作为本次 Linux 适配版的性能结论。本次没有测得新的 CoreMark 成绩，也没有完成 150 MHz Linux 集成。

## 定向 RTL 验证

| 检查 | 本次结果及证据 |
| --- | --- |
| M/S/U、异常及 CSR | 22 项通过；`reports/privilege/run.log` |
| MIP/SEIP | 10 项通过；`reports/mip_seip/run.log` |
| 计数器访问权限 | 1296 项：允许 672，拒绝 624；`reports/counter_matrix/run.log` |
| Sv32 | 1557 项、3098 次页表读取；`reports/tool_recheck_02/sv32_tb_test.log` |
| MMU 与缓存桥、SFENCE | `reports/sv32_bridge_test.log`、`reports/sv32_cache_fence_test.log` 通过 |
| 真实 CPU 分页程序 | fence.i、页故障、ASID、SATP 取指四项，独立解码 UART 确认 PASS |
| 原子访存 | 20 项定向；Icarus 2541 项、Verilator 2542 项随机测试；aq/rl 实际核心排序 5 次提交、7 次物理事务 |
| 定时器 | 32 次间隔，最小／最大均 1002，累计 32064；符合测试范围 |
| 外部中断 | UART→PLIC→S 中断、MIP 读改写、claim/complete 实际 CPU 程序通过 |
| 加密计算 | 32 组完整 ChaCha20 分组结果，2048 字节比对通过；保留 Python 参考向量核验 |
| 外设及扫描 | 外设 2526 项、PLIC 1182 项；扫描及故障注入通过 |
| CPU 与视频共同访存 | 1843200 像素、230400 次显示读取、535903 条退休指令的所有权测试通过 |
| 串口测试夹具 | 引脚波形、保存恢复及逐字符回显输入检查通过 |

独立 UART 结果在 `reports/uart_capture_checks/`。首次回归因工具路径、参考头文件及失败构建缓存未完整执行的记录均保留；修复环境后在新目录复核。Core_01 的诊断 `$display` 会穿插于逐字节 UART stdout，因此给仿真夹具增加独立 UART 字节文件，定时器和加密检查据此判断，混合原始日志也保留。没有把诊断字符串过滤后的猜测当作串口结果。

Verilator 定向回归保留内部诊断及断言。长启动仿真选择与综合一致的 RTL 分支，以省去诊断影子状态运算；仍由实际 RTL 执行每条指令。Lint 无错误；原 Linux 基线已有的可选调试端口未接及组合依赖提示保持记录，未据此调整物理约束。

## 完整 Linux 与 GUI 验证

从复位开始运行本次实际 CPU RTL，并加载与上次实板相同的 OpenSBI 1.6、Linux 6.12.9 和用户空间镜像。固件清单 SHA-256 为 `fa44c249cc87ab0c4445255c5c43c964c265751fcfc0af981a43550feb4d9fc9`。

串口输入以真实 RX 引脚波形注入，输出从 TX 引脚解码。测试完成 root 登录、`uname -a`、`cat /proc/cpuinfo`、`ps`、GUI 状态页、后台计数程序启动／停止，并发送返回首页命令。计数样本为：A={c['COUNT_A'][0]}、B={c['COUNT_B'][0]}，停止时={c['COUNT_STOP'][0]}、等待后={c['COUNT_AFTER'][0]}。递增及停止保持均符合预期。企鹅启动、首页和状态页的真实扫描画面另经无损预览核对。

完成时仿真周期 {b['finish_metrics'][0]}，完整扫描帧 {b['finish_metrics'][1]}，显示读取 {b['finish_metrics'][2]} 次，underflow／DMA error／bounds error 均为 0。实际数字扫描像素见 `reports/compact_boot/run_01/captures/`；选取的画面及来源在 `reports/selected_captures.json`。这些是 RTL 数字扫描输出，不能当作实板 HDMI 照片。

启动仿真使用板级紧凑扫描器和帧提交 CDC，GUI 源像素 320×180、步幅 1280 B、2 倍显示，输出 720×480。CPU 与像素时钟在此夹具中共用 27 MHz 时钟，DDR 数据使用主机 RAM 响应。该项证明 CPU/内核/应用/逻辑扫描链路；Vendor DDR PHY、真实异步时钟边界、TMDS 和显示器兼容性仍需实板验收。

原始证据：`reports/compact_boot/run_01/uart.log`、`trace.log`、`inputs.sha256`、`exit_code.txt`。本轮核验了 {s['boot_inputs_and_model_verified']} 个启动输入与模型文件哈希，没有复用原 CPU 的启动检查点。

预览转换核对 RGB565 数据长度、逐像素 FNV 及 PPM 像素负载。原仿真夹具的 PPM 文件头仍标记旧宽度 1280，原始像素与 JSON 元数据实际为 720×480。`preview_scanout.py` 依元数据从原始像素无损生成 PNG，并保存校验记录；未改动正在执行的模型或原始像素。交付预览使用 PNG 与 RGB565，原 PPM 保留在工作目录中。

## PDS 2025.2 实现

目标器件 PG2L200H-6 FBB676。综合、器件映射、布局、布线和位流生成均由原生 PDS 完成，无原生错误。多角内部时序报告满足已有约束，慢角 setup 和快角 hold 无失败端点。

| 时钟域 | 配置频率 | 建立时间余量 |
| --- | ---: | ---: |
| CPU sys_clk | 27 MHz | +{v['cpu_setup_slack_ns']:.3f} ns |
| DDR 控制器 | 93.75 MHz | +1.077 ns |
| HDMI 像素 | 27 MHz | +28.779 ns |
| HDMI 串行 | 135 MHz | +2.489 ns |

CPU 快角保持时间余量为 +{v['cpu_fast_hold_slack_ns']:.3f} ns。报告对 CPU 时钟域的估计为 36.7971 MHz，不能解释成已经采用或实板验证该频率。

层次逻辑资源：CPU 核心 `{cpu['lut_logical']}` LUT、`{cpu['ff_logical']}` FF；含缓存、MMU 和外设的 CPU SoC 为 `{soc['lut_logical']}` LUT、`{soc['ff_logical']}` FF。层次表与包含常量／旁路单元的物理资源总量口径不同，原始数据保存在 `.ror` 报告。

79 个 DDR／HDMI 物理端口默认属性与原工程一致。PDS 仍报告 71 个 DDR、8 个 TMDS 端口缺少常规外部 I/O 延时约束；本轮未改变它们，不能把内部 `All Constraints Met` 称作完整的板外接口时序签核。相关原始报告、复位／同步器审计均在 `fpga_build_01/`。

位流 SHA-256：`{v['bitstream_sha256']}`。

## 复现与后续实板验收

1. 运行 `operator/runtime/python.exe -B verify_candidate.py` 检查交付包和源码；此命令不访问板卡。
2. 使用 `rebuild_fpga.py --prepare-only --output fpga_prepare_new` 生成并检查本地工程。实际重建使用 `rebuild_fpga.py --output fpga_rebuild_new`，需要 PDS 2025.2 与本机有效许可。输出必须选新目录；脚本拒绝覆盖既有证据。
3. `build_boot_sim.sh` 构建实际 RTL 模型，`run_boot_sim.sh` 保留本次调用，`run_boot_sim_replay.sh` 为后续复核选择新日志目录；工具依赖与已运行命令见各脚本和构建日志。
4. 获得新的上板授权后，使用本版启动工具进行 JTAG 下载、DDR 固件校验、真实启动、HDMI 首页／状态页、计数启停及用户自主串口命令验收。

原版本的可用位流、工程、固件和 2026-11-01 实板记录均保留。本轮没有连接或占用串口／JTAG，没有创建定时任务。
'''
    (R/'CPU替换验证报告_20261102.md').write_text(report,encoding='utf-8')
    readme=f'''# RV32 RV32 Linux · Core_01

已将 Linux＋UART＋HDMI 工程替换为用户封存的 `{s['source_build_id']}` CPU 的 Linux 适配版。RTL 定向验证、完整 Linux／GUI 串口交互及 PDS 2025.2 实现通过；**新位流尚未进行实板验收**。CPU 配置时钟仍为 **27 MHz**。

- 当前源码：`rtl/` 与 `inputs/`；PDS 顶层 `soc_linux_gui_top`，完整来源及补丁在 `provenance/`。
- 详细验证：[CPU 替换验证报告](CPU替换验证报告_20261102.md)、`reports/offline_verification.json`。
- 系统启动工具：解压后运行 `operator/Start_Linux.cmd`。新版本上板需要按用户要求另行取得授权。
- 源码及包校验：`operator/runtime/python.exe -B verify_candidate.py`；此检查不访问板卡。
- PDS 工程准备：`operator/runtime/python.exe -B rebuild_fpga.py --prepare-only --output fpga_prepare_new`。
- PDS 重建：`operator/runtime/python.exe -B rebuild_fpga.py --output fpga_rebuild_new`。通过 `--pds`、`--license` 可指定本机工具和许可；禁止覆盖既有构建。
- 原封存目录 `D:/workspace/riscv-fpga-soc/XXX/rv32_core_01` 保持只读；原 Linux 实板版本保留。

Core_01 的裸机配置需要移植 Linux 的特权、分页异常与原子接口。保留新核心的优化结构，I-cache 16 KiB／双路，D-cache 8 KiB／双路，预测器 B9/G12/H12，Linux 访存使用保守排序。

PDS 的 CPU setup 余量 +{v['cpu_setup_slack_ns']:.3f} ns、fast hold 余量 +{v['cpu_fast_hold_slack_ns']:.3f} ns；这些为现有约束覆盖的内部时序。外部 DDR／HDMI 电气和接口时序仍需实板验收。原裸机 CoreMark 和 120 MHz 结论不转移至本集成；本轮未验证 150 MHz。

RTL 启动执行实际 CPU，使用真实 UART 引脚输入命令并记录数字扫描像素。夹具以共享时钟和主机 RAM 提供外围响应，不能代替实板 DDR PHY／HDMI。启动验证证据见 `reports/compact_boot/run_01/`。

交付包保留运行固件、位流、硬件源码、许可证、工具和验证证据，按用户要求省去 Linux 上游源码原件。既有回归的环境失败及诊断输出混入记录保留，最终复核采用 `reports/tool_recheck_02/` 和 `reports/uart_capture_checks/` 的结果。
'''
    (R/'README.md').write_text(readme,encoding='utf-8')
    print('Final report and README written.')
if __name__=='__main__':main()
