# 可选真实串口分阶段输入

`linux_soc_main.cpp` 和 `linux_video_boot_main.cpp` 共用 `../uart_terminal.h`。
默认关闭，不更改 guest RAM、CPU 状态或启动参数，不制造 TX 控制台内容。
本功能仅在观测到真实 RTL UART TX 字节之后，通过 RX 引脚发送 8N1 波形：
每位 868 个模型时钟，每字节之后额外空闲 8,680 个时钟。

新接口：

```sh
RV32_UART_SCRIPT=sim/terminal/login_smoke.tsv <现有模拟器命令及启动镜像>
```

修改宿主源码后需要正常重新构建模拟器，既有二进制不会自动增加该功能。
示例脚本等待 `rv32 login:`，输入 `root\n`，随后等待新出现的 `# `，
再发送只读检查命令。它不绕过登录、不强制 shell；如果系统要求密码或没有
该提示符，阶段会一直等待至模拟器已有的运行周期上限，不会擅自继续。

格式：每个非空行是 `触发文本<TAB>发送内容`，中间必须为一个真实 TAB。
两栏均支持 `\n`、`\r`、`\t`、`\\`、`\xHH` 转义。支持 CRLF 文件和空行；
不支持注释行，避免 `# ` shell 提示符与注释语法冲突。
触发文本/内容不可为空。触发文本可以分多次 TX 字节到达。

发送当前阶段期间观测到的 TX 不会预触发下一阶段；最后一个停止位完成后，
才开始匹配下一阶段的新输出。下一提示符即使出现在额外空闲间隔内也能捕获，
但不能缩短间隔。每个阶段仅执行一次。阶段触发/发送完成消息写到 stderr，
不混入 guest TX 字节流。

旧接口保留：`RV32_UART_INPUT=<原始字节文件>`，可选
`RV32_UART_TRIGGER=<原始触发文本>`，默认 `# `；空字节文件关闭输入。
新旧 INPUT/SCRIPT 同时设置会报配置错误并退出（状态 2），不静默选择一个。
限制：文件/解码总量至多 1 MiB、至多 128 阶段、每触发文本 4,096 字节、
每阶段发送内容 65,536 字节。非法转义、格式错误、超限或文件打开失败均拒绝。

运行 `scripts/test_uart_terminal.sh`：独立宿主测试对每个时钟比较实际 RX 电平，
独立中点解码，覆盖所有帧位长度、字节间隔、二进制 0/255、分段触发、
缺少提示符不发送、旧提示符不能复用、复位空闲、旧接口及文件解析错误。
日志：`reports/uart_terminal/test.log`。这些宿主测试不证明 Linux 已启动或登录成功；
系统交互仍须由实际 guest UART 输出证明。

额外 ASan/UBSan 执行通过（`reports/uart_terminal/sanitized_no_lsan.log`）；
当前执行器的 ptrace 环境不支持 LeakSanitizer，因此该次显式设置
`ASAN_OPTIONS=detect_leaks=0`。不宣称完成泄漏检查，原限制日志亦保留。

完整待验证交互脚本：`sim/linux_shell_commands.tsv`。
阶段 1 登录；阶段 2 查询 uname/cpuinfo/meminfo/fb0 并打印
`ACTUAL_RTL_SHELL_COMMANDS_DONE`；阶段 3 经 `gui-command` 私有 FIFO
依次发送 status、settings、home，中间 sleep 1，最后打印
`ACTUAL_RTL_GUI_COMMANDS_SENT`。后一个标记**仅表示命令发送阶段**，
不是 GUI 视觉成功、实际页面绘制或物理 HDMI 成功证明。
shell 自身可能回显输入命令，因此不能仅在 UART 文本中搜索标记就认定
命令执行成功；应区分输入回显、命令结果及后续提示符，并单独检查帧证据。

## UART 检查点接口

```cpp
terminal.save(output_stream);
terminal = UartTerminal::restore(input_stream, &std::cerr);
```

在一个完整模拟时钟及其 TX 字节处理之后调用。记录以 `AURT0001` 开头，
所有长度/数值均为固定 32 位小端，无宿主对象地址；保存完整阶段配置、
当前阶段、字节索引、已发字节数、位序、剩余位时钟、额外间隔、active 状态
及部分触发文本。`ostream*` 不序列化，恢复时重新提供。
恢复不读取环境或原脚本文件；整体宿主检查点应另行核对初始配置身份，
防止用户误把不同脚本和旧检查点混用。这里的可移植性仅指 UART 记录格式，
不表示整个 Verilator 模型检查点可跨模型版本/构建恢复。

恢复检查魔数/版本、配置总量和每段边界、阶段/索引范围、位时钟范围、
间隔与发送状态一致性、累计字节数和触发尾部长度；截断或非法记录抛异常。
输入流只消费一个记录，可嵌入宿主状态流；如果宿主用独立字符串封装，
恢复之后还应检查字符串流 EOF。外层宿主负责检查点原子落盘和完整性验证。

`sim/uart_terminal_checkpoint_test.cpp` 在 200,000 个时钟内执行 1,465 次
任意边界保存/恢复，与不中断实例逐时钟比较 RX 电平、阶段、字节计数、
完成状态和事件日志。覆盖部分触发文本、字节中途、空闲间隔、后续阶段，
并测试截断/非法状态/配置边界、完成及禁用状态。803,014 项通过，日志为
`reports/uart_terminal/checkpoint_test.log`；原有测试同时保持通过。
