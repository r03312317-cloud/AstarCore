# Linux 发行版风格启动演示

本工作副本在 linux_gui_compact_20261031_01 基础上增加 Linux 启动阶段的图形画面。保持现有 PDS 位流、Linux 内核、UART 启动日志和 LVGL 状态页，固件必须与 320×180 扫描位流配套。

- 图形启动组件是 Buildroot 2025.02.1 所选的上游 psplash（Yocto/OpenEmbedded，修订 44afb7506d43cca15582b4c5b90ba5580344d75d，GPL-2.0-or-later）。下载归档的 SHA-256 与 Buildroot 包清单相符。
- 深色主题由本工程制作，使用 Linux 6.12.9 内核源码的 224 色企鹅图案；Starting Linux 后的版本号由运行中的 uname -r 读取。当前实际系统是 Buildroot，启动画面不声称是 Ubuntu、Plymouth 或内核直接绘制。
- psplash_adapted/ 保留对应源码。对 framebuffer 后端的适配将 320×180 区域写入 640×360 页面，使用已实现的 FBIOPAN_DISPLAY 完成缓存清理和垂直同步；失败时不切换缓冲区。FIFO 使用双向打开以避免无写入者时空转。主题及配色也经过本地修改。
- S00psplash 在内核启动、进入 Buildroot 用户空间后启动画面；S99rv32-gui 等待启动画面进程退出再运行 LVGL。启动画面无法打开 framebuffer 时，系统继续启动；画面程序无法退出时则拒绝让 GUI 并发占用 framebuffer。
- 采用已有的 S01syslogd 防误报修正：内核不支持 AF_UNIX 时明确输出 SKIP，避免将后台启动器返回成功误认为日志服务已运行。
- 企鹅图案属于 Linux 源码中的 drivers/video/logo/logo_linux_clut224.ppm；保留其原文件及 Linux 源码/许可证。字体为 Noto Sans SC，许可证见已有工程的 deps/NotoSansSC-OFL.txt。其余 Linux、musl、GUI 等源码和许可证保存在此前完整工程包。

## 验证范围

fbdev_host_02/ 为主机模拟 fbdev 的真实 psplash 程序测试，覆盖两种初始页、区域越界、活动页写入、翻页失败和 FIFO 空闲 CPU 行为。handover_host_01/ 测试正常交接、无 framebuffer 回退和卡住时禁止并发。qemu_user_fb_05/ 在 QEMU 用户态运行实际 RV32 psplash，并以软件模拟 fbdev ioctl，验证启动画面与状态文字的像素和主机测试一致。qemu_linux_02/ 在 64 MiB RV32 QEMU virt 中验证无 framebuffer 时仍可启动、登录、切页和启停计数，并检查日志服务状态如实输出；QEMU 系统仿真此项不显示启动画面。

**尚未对新版固件、先前的紧凑扫描位流或启动画面做实板验证。** 上述测试不能证明真实 DDR、HDMI、显示完整性或现场串口加载通过。DDR/HDMI 外部 I/O 延时预算仍不完整；CPU 时钟配置为 27 MHz。测试期间未访问或占用板卡。

## 使用

解压配套自助启动包，连接电源、JTAG、USB 串口和 HDMI，运行 Start_Linux.cmd。窗口先出现，由用户选择串口并启动加载；串口仍显示真实 OpenSBI 和 Linux 日志。固件传输通常需要十几分钟。Linux 进入用户空间后显示 psplash，随后进入 LVGL 首页。断电后需重新加载。
