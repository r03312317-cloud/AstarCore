# RV32 Linux 01 源码包

基于永久封存的 RV32-Linux_01，CPU 为 Core_01 的 Linux 适配版，配置 27 MHz。

## 包含范围

- rtl/、inputs/：全部 145 个原始 FPGA 输入，136 个有序 HDL 源，含 CPU、Sv32、cache、外设、DDR/HDMI 集成、CDC、约束和所需 Pango 受保护 IP 源文件。
- software_reference/：Linux BSP 驱动与配置、Buildroot/OpenSBI 适配、GUI/LVGL 8.3.11 源码归档、图形/字体素材和许可证。
- software_current/：从实际上板镜像导出的 27 MHz 且 framebuffer 已启用的 DTS，以及实际 rootfs 启动脚本、计数与切页脚本。DTS 各属性按原字节保留；来源和哈希见 runtime_source_manifest.json。
- operator/：Windows 串口控制台、下载和上传工具的源程序、psplash 适配源码、相关第三方源码和许可证。
- sim/、scripts/、tools/、provenance/：仿真、验证脚本、PDS 重建辅助、原核与 Linux 移植差异。
- docs/architecture/：18 页架构源码工作流报告及可点击源码的离线阅读版。打开其中的 HTML 报告即可阅读。

按此前要求，不包含 Linux 上游源码原件；不包含位流、运行镜像、便携 Python 运行库、已编译 GUI、原生 PDS 网表/数据库或大型仿真缓存。Linux 完整软件重建仍需对应上游源码、交叉工具链及依赖。Pango 商业工具和许可不在包内。

## 源码校验与硬件工程重建

在解压后的本包根目录，用本机 Python 3.9 或以上版本运行：

```text
python -B verify_sources.py
python -B rebuild_fpga.py --prepare-only --output fpga_prepare_NEW
python -B rebuild_fpga.py --output fpga_rebuild_NEW
```

第一项核对本包文件、145 个 FPGA 输入和 14 份原核源文件；第二项只生成本地 PDS 工程；第三项执行完整原生 PDS 构建，需自行安装 PDS 2025.2 和合法许可，可用 --pds 与 --license 指定路径。每个输出目录必须尚不存在，禁止在 XXX 封存目录内构建。

## 软件参考与实际配置

software_reference/linux/rv32-rv32.dts 保留早期 100 MHz、framebuffer disabled 的参考内容；本版实际上板配置请以 software_current/rv32-rv32-board27.dts 为准。software_current/rootfs_overlay 保存运行镜像中的实际脚本，旧 Buildroot overlay 仅为参考。构建设备树需要 dtc；导出的源与原 DTB 属性字节一致，不承诺 dtc 重新排列后的 DTB 二进制哈希与原件相同。

本包保留历史软件构建脚本中的原始绝对路径。修改前应准备独立工作目录，核对工具链、上游源码与 sysroot，再调整路径。完整 Linux 仿真另需运行镜像；本次仅打包源码，没有重新综合、运行 Linux 或进行上板。

## 与完整演示工程的关系

operator/ 内是源程序，未配套运行位流、固件和 Python，因此不应把本包当作可直接一键上板的运行包。直接演示请使用此前的完整上板工程，或从 XXX/RV32-Linux_01 恢复的可写演示副本。

本包使用 verify_sources.py 校验。docs/reference_verification/verify_candidate.py 和 operator/verify_kit.py 保留原验证代码供阅读，它们针对完整运行工程的文件布局，不是本源码包的入口。

本版实板已完成 Linux 启动、root 串口命令及用户确认 HDMI 正常；切页和计数启停本轮未继续复测。各文件原有版权、许可证与第三方声明完整保留，不能将全部文件统一宣称为同一许可证。
