RV32 CPU 子系统

rtl/：乱序双发射 CPU、混合分支预测、操作数队列、ROB、执行与提交路径。
board/：SRAM、启动装载及板级接口；constraints/：实现约束。
software/：CoreMark、平台层、启动、链接与固件构建脚本。
original/：参考架构副本；analysis/：生成的 C++ 仿真模型代码。
tools/：源码、语法、分析和技术文档工具。

文件表：rtl_filelist.f、board_filelist.f。
参考硬件配置为 130 MHz，历史 CoreMark 结果为 7.483006501 CoreMark/MHz。
当前命名版本未重新执行实板测试，该结果只用于说明原实现的参考测试条件。

厂商 PLL 输入需在本地生成；固件 HEX 从当前软件源码重新构建。
根目录 SHA-256 清单核对当前分发内容。工程内部的历史校验工具可能依赖
完整实现输出，不能替代当前根校验器。

CoreMark 原 Apache-2.0 声明及 EEMBC 使用协议保持原样。
