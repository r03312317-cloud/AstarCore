# 构建说明

## 环境与依赖

- FPGA 平台：Pango PG2L200H；硬件工程使用 PDS 2025.2 输入格式。
- 脚本：Python 3.9 或更高版本，额外依赖以各工具的导入和说明为准。
- 裸机软件：RV32 GCC、对应启动文件、链接脚本和 BSP。
- Linux 软件：RV32 Linux 工具链、Linux 6.12.9、OpenSBI、Buildroot 与 GUI 依赖。

在独立、可写且较短的目录构建。部分保留的辅助工具包含环境路径，
运行前应将这些路径配置为本地工具链及工作目录。

## 外部输入

1. 使用授权 PDS 安装生成对应 PLL、DDR 控制器及 PHY 等 IP，模块接口需
   与集成层和约束一致。不同工程具有各自的时钟配置。
2. 固件初始化镜像从当前固件源码生成。源码集合未保留含其他命名标识的
   CPU 初始化 HEX 和视觉固件 ITCM/DTCM 镜像；具体位置见 `GENERATED_INPUTS.md`。
3. Game 的模拟器需要单独准备有权使用的 ROM。商业游戏 ROM 数组及其
   DDR 初始化数据没有分发。
4. 模型数据使用前应核对 `YOLO/model/NOTICE.md` 中的许可边界。

## CPU

架构文件表为 `cpu/rtl_filelist.f`，板级文件表为 `cpu/board_filelist.f`。
核心源码位于 `cpu/rtl/`，CoreMark 与 BSP 位于 `cpu/software/src/`。
入口及内存布局分别由顶层模块、启动文件和链接脚本确定。

## 视觉推理

`YOLO/annotated/project/stage_ddr_hdmi/` 为说明性源码入口，
`YOLO/exact/` 为构建输入与工具的参考副本，`YOLO/model/` 为模型与部署数据。
使用选定配置的来源列表组织工程，不将所有副本递归加入同一次编译。
重新生成固件、补齐厂商 IP 后，应重新登记构建器使用的输入路径及哈希。

## Linux

查看 `Linux/rebuild_fpga.py` 和 RTL 文件清单。
实际板级设备树入口为 `Linux/software_current/rv32-rv32-board27.dts`。
其他频率或 headless 配置作为参考输入保留，需与实际硬件配套。

## 图形外设验证

主要源码位于 `Game/source/`，构建入口为 `Game/source/tools/build_mario.py`。
`Game/baseline/` 保存原始参考布局；测试源码位于 `Game/source/tests/`。

## 验证顺序

先执行根目录离线完整性校验，随后按工程完成语法检查、仿真、固件重建、
综合布局布线和时序检查。生成的位流与软件镜像应在对应硬件上重新验收。
命名规范化后的源码具有新的文件哈希和固件身份，历史记录不构成本版本的新实测结果。
