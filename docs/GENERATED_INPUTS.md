# 初始化输入生成

以下位置由当前固件构建流程生成，源码分发中不附带对应的旧预编译镜像：

- `YOLO/artifacts/firmware/coremark-dtcm.mem`
- `YOLO/artifacts/firmware/coremark-itcm.mem`
- `YOLO/exact/runtime_policy/workspace/firmware_runtime_02/coremark-dtcm.mem`
- `YOLO/exact/runtime_policy/workspace/firmware_runtime_02/coremark-itcm.mem`
- `cpu/firmware.hex`
- `cpu/software/builds/performance10/firmware.hex`
- `cpu/software/builds/performance20000/firmware.hex`
- `cpu/software/builds/validation10/firmware.hex`

CPU 构建入口为 `cpu/software/build_firmware.py`；视觉固件构建入口位于
`YOLO/exact/runtime_policy/workspace/project/build_ddr_hdmi_firmware.py`。
运行前应配置相应 RV32 工具链及输出目录，并将生成的 HEX/MEM 输入接入
对应的板级工程。各文件的实际内容和固件身份以本次构建结果为准。
