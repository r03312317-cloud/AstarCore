# 目录与来源审查

## 目录职责

| 位置 | 内容与来源 |
| --- | --- |
| `cpu/rtl/`、`cpu/board/` | CPU 架构及板级适配 |
| `cpu/original/` | 对应架构的参考副本，与主目录存在重复文件 |
| `cpu/analysis/profile/model/` | 由 RTL 生成的 C++ 仿真模型代码 |
| `cpu/software/` | CoreMark、平台层、启动及链接输入 |
| `YOLO/annotated/`、`YOLO/exact/` | 同一视觉系统的说明性副本与构建参考输入 |
| `YOLO/model/` | ONNX、权重、算子描述符和参考张量 |
| `Linux/rtl/`、`Linux/inputs/` | 特权/MMU 适配与板级集成输入 |
| `Linux/software_current/` | 当前设备树、驱动和用户空间程序输入 |
| `Linux/software_reference/` | 上游软件参考、归档、字体和许可材料 |
| `Linux/operator/` | 启动、镜像传输、图形启动及显示工具源码 |
| `Game/source/` | 模拟器适配、平台、固件与验证代码 |
| `Game/source/soc/sw/` | 复用平台中保留的 RPG 图形示例，与 LiteNES 主程序分别使用 |
| `Game/baseline/`、各 `build/`、`provenance/` | 同工程的参考布局与构建源码快照 |

目录包含明确的第三方依赖、平台图形示例和同工程重复副本。旧标题预览拼图未分发，相关源程序与其他地图、图块资源仍保留。仅根据目录、文件名及
源码头部检查，不能证明所有实现均为原创；本审查不把重复快照认定为外部项目混入。

## 许可边界

MIT、Apache-2.0、BSD、GPL、OFL 等许可证同时存在。根 MIT 许可不能覆盖
已经标注 GPL 的内核驱动或 psplash 派生文件，也不能替代模型的来源授权。
软件工具链或独立软件的同仓分发，不足以单独推导 CPU/NPU RTL 成为 GPL 派生作品。
具体复制、修改、链接及派生关系需以源代码和对应构建方式判断。

Linux 平台 framebuffer 驱动明确带有 `GPL-2.0-only`，psplash 适配文件
带有 `GPL-2.0-or-later`，这些许可均保留。
Game 的上游目录附有 AbstractMachine MIT 声明；其 README 指向更早的模拟器来源，
使用者还应按实际导入版本核对该来源链。

## 模型来源缺口

模型导出记录列出的五份 YOLOv5 框架文件与本地带 AGPL-3.0 声明的版本
逐字节匹配。该来源已在模型 NOTICE 与根第三方索引中单独列出。
模型不属于本项目额外授予 MIT 权利的范围。

当前分发并未完整附带训练配方、数据集授权凭据和训练框架的不可变版本号。
因此不能根据仓库中附有许可证正文，就断言模型的全部再分发条件已经满足。
模型的实际许可应结合训练版本、权利人授权及衍生关系进一步确认。

## 参考依据

- [GNU 对独立聚合与组合程序的说明](https://www.gnu.org/licenses/gpl-faq.en.html#MereAggregation)
- [Linux 内核许可规则与 UAPI 边界](https://docs.kernel.org/process/license-rules.html)
- [Ultralytics 许可说明](https://www.ultralytics.com/license)
- [AbstractMachine 对应版本的许可](https://github.com/NJU-ProjectN/am-kernels/blob/9c433f7cf4b4e05d09543bf7e269b23502d1b2b6/LICENSE)
