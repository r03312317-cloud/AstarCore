# Linux 适配子系统

本目录包含 RV32 特权架构、Sv32 地址翻译、板级集成、设备树、平台驱动、
GUI、启动及镜像传输工具源码。参考软件组合为 OpenSBI、Linux 6.12.9、
BusyBox 与 LVGL 8.3.11，参考 CPU 时钟为 27 MHz。

| 目录 | 内容 |
| --- | --- |
| `rtl/`、`inputs/` | CPU/SoC RTL 与板级输入 |
| `software_current/` | 设备树、驱动与 GUI 输入 |
| `software_reference/` | 上游参考、第三方归档、字体和许可材料 |
| `operator/` | 启动、镜像传输和图形启动工具源码 |
| `scripts/`、`sim/`、`tools/` | 构建、仿真与离线验证工具 |
| `provenance/` | 来源布局和参考源码副本 |

硬件构建入口为 `rebuild_fpga.py`。需先生成授权厂商 IP，再配置 PDS、
RV32 工具链、Linux/OpenSBI/Buildroot 输入及本地输出目录。
源码目录不包含完整上游内核源码、位流、根文件系统镜像或便携工具运行环境。

内核驱动和 psplash 适配保留各自 GPL 声明；其他依赖按对应许可分发。
根目录 MIT 许可不替代这些声明。

当前文件采用通用命名，固件与位流需要重新生成并验收。
完整性检查从仓库根目录执行 `python 校验代码包.py`。
