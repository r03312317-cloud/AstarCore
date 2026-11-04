# 第三方来源与许可

根目录 MIT 许可适用于独立自研部分。第三方源文件、派生文件、模型与资源
保留各自的权利与义务，不由根目录 MIT 许可重新授权。

| 组件 | 位置 | 许可与说明 |
| --- | --- | --- |
| EEMBC CoreMark | `cpu/software/src/coremark/` | 源码 Apache-2.0 声明、原 `LICENSE.md` 使用协议及 `LICENSES/Apache-2.0.txt` |
| LiteNES / AbstractMachine | `Game/source/upstream/litenes/` 及其参考副本 | 上游 MIT `LICENSE` 与原文件声明；更早的模拟器来源链见该目录 README |
| OpenSBI | `Linux/software_reference/firmware/opensbi/` | BSD-2-Clause 与各文件单独声明 |
| Linux 内核参考与平台驱动 | `Linux/software_reference/linux/` | 原 GPL-2.0-only 声明；UAPI 例外见内核许可文件 |
| BusyBox | `Linux/software_reference/licenses/software/` 及软件配置 | GPL 及各文件保留的许可；许可材料不等同于完整上游源码 |
| psplash 与适配 | `Linux/operator/sources/` | GPL-2.0-or-later；保留源码、COPYING 与上游归档 |
| musl 1.2.5 | `Linux/operator/sources/musl-1.2.5.tar.gz` | 上游 COPYRIGHT 及文件声明 |
| LVGL 8.3.11 | `Linux/software_reference/upstream/lvgl-8.3.11.tar.gz` | 归档内 MIT `LICENCE.txt` |
| Noto Sans SC | 两份 TTF 及字体资源 | 随附 SIL OFL 1.1 正文 |
| pySerial 3.5 | `Linux/operator/vendor/` | BSD-3-Clause，见 `PYSERIAL_LICENSE.txt` |
| YOLOv5 模型训练/导出来源 | `YOLO/model/` 及其派生部署数据 | 已核对导出所用框架文件的 AGPL-3.0 来源；见 `YOLO/model/NOTICE.md` 与 `LICENSES/AGPL-3.0.txt` |
| GCC 运行库许可材料 | `Linux/software_reference/licenses/software/gcc-final-13.3.0/` | 保留运行库例外；不代表仓库包含 GCC 编译器源码 |

完整来源与实际衍生关系决定具体许可边界。独立软件的同仓分发本身不改变
其他独立代码的许可证；复制、修改、链接或模型派生关系仍须分别核对。

Pango 受限 IP、商业游戏 ROM 与含相应载荷的初始化数据没有分发。
相关输入路径见 `docs/PUBLIC_EXCLUSIONS.json`，本地重建说明见 `docs/BUILD.md`。
