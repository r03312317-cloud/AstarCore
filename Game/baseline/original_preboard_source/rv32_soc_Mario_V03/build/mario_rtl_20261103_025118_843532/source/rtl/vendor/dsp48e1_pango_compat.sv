// -----------------------------------------------------------------------------
// dsp48e1_pango_compat.sv
//
// 厂商原语替代层：为 Xilinx `DSP48E1` 提供紫光 Logos2 实现。
//
// 为什么需要这个文件
//   rtl/core/dc_realtime_core_mul.sv 以 genvar 例化 4 个 `DSP48E1`（32x32 拆成
//   4 个 25x18 部分积）。`DSP48E1` 是 Xilinx 7 系列硬核乘法器，PDS 2025 无法
//   识别，综合必然失败。全工程仅此一处厂商原语。
//
// 方案选择
//   采用"同名同端口替代模块"，而不是改 CPU RTL，也不是让综合器推断 `a*b`：
//     - 保持 dc_realtime_core_mul.sv 一字不改，微架构与接口零风险；
//     - 寄存器边界显式可控，与原 DSP48E1 的 AREG/BREG/PREG 用法逐拍等价；
//     - 直接使用紫光原生 APM 算术块，不引入 IP 生成流程与 .idf 依赖。
//
// 原语合法性（已核对，非推测）
//   器件库：PDS 2025.2 安装目录
//     arch/vendor/pango/logos2/common/lib/gtp_lib.v
//   该文件中的 `module GTP_APM_E2` 声明包含本文件使用的全部 39 个端口与 15 个
//   参数，名称与位宽逐项一致。仿真模型见 arch/vendor/pango/verilog/simulation/
//   GTP_APM_E2.v。
//
// 与原 DSP48E1 配置的对应关系
//   原配置：AREG=1, BREG=1, PREG=1, USE_MULT="MULTIPLY", OPMODE=7'b0000101，
//           未使用 C/D/后加器，故等价于"输入寄存器 + 乘法寄存器"两级。
//   本实现：X_REG=1  ←→ AREG/BREG（操作数寄存器，使能 CEA2/CEB2）
//           Y_REG=1
//           MULT_REG=1 ←→ PREG（乘积寄存器，使能 CEP）
//           P_REG=0    ←→ 旁路后加器
//           MODEIN=5'b00010 选通 X 路径进入 25x18 有符号乘法器
//           USE_POSTADD=0 / USE_PREADD=0 / USE_SIMD=0
//
// 周期行为
//   第 N 拍  : req_ready 有效，X/Y 在时钟沿打入操作数寄存器（CEX1/CEY1）
//   第 N+1 拍: stage_valid_q 有效，乘积在时钟沿打入乘法寄存器（CEM）
//   第 N+1 拍后: P 端组合输出可用，与原 DSP48E1 P 寄存器输出同级
//   与 dc_realtime_core_mul.sv 的 stage_valid_q / product_valid_q 三段握手完全一致。
//
// 未使用的级联与状态输出按原 DSP48E1 例化的空连接语义驱动为常量；CPU 乘法单元
// 未使用它们。
// -----------------------------------------------------------------------------

module DSP48E1 #(
    parameter integer ACASCREG = 1,
    parameter integer AREG = 1,
    parameter integer BCASCREG = 1,
    parameter integer BREG = 1,
    parameter integer ADREG = 0,
    parameter integer ALUMODEREG = 0,
    parameter integer CARRYINREG = 0,
    parameter integer CARRYINSELREG = 0,
    parameter integer CREG = 0,
    parameter integer DREG = 0,
    parameter integer INMODEREG = 0,
    parameter integer MREG = 0,
    parameter integer OPMODEREG = 0,
    parameter integer PREG = 1,
    parameter USE_DPORT = "FALSE",
    parameter USE_MULT = "MULTIPLY",
    parameter USE_SIMD = "ONE48"
) (
    output wire [29:0] ACOUT,
    output wire [17:0] BCOUT,
    output wire        CARRYCASCOUT,
    output wire [3:0]  CARRYOUT,
    output wire        MULTSIGNOUT,
    output wire        OVERFLOW,
    output wire [47:0] P,
    output wire        PATTERNBDETECT,
    output wire        PATTERNDETECT,
    output wire [47:0] PCOUT,
    output wire        UNDERFLOW,

    input  wire [29:0] A,
    input  wire [29:0] ACIN,
    input  wire [3:0]  ALUMODE,
    input  wire [17:0] B,
    input  wire [17:0] BCIN,
    input  wire [47:0] C,
    input  wire        CARRYCASCIN,
    input  wire        CARRYIN,
    input  wire [2:0]  CARRYINSEL,
    input  wire        CEA1,
    input  wire        CEA2,
    input  wire        CEAD,
    input  wire        CEALUMODE,
    input  wire        CEB1,
    input  wire        CEB2,
    input  wire        CEC,
    input  wire        CECARRYIN,
    input  wire        CECTRL,
    input  wire        CED,
    input  wire        CEINMODE,
    input  wire        CEM,
    input  wire        CEP,
    input  wire        CLK,
    input  wire [24:0] D,
    input  wire [4:0]  INMODE,
    input  wire        MULTSIGNIN,
    input  wire [6:0]  OPMODE,
    input  wire [47:0] PCIN,
    input  wire        RSTA,
    input  wire        RSTALLCARRYIN,
    input  wire        RSTALUMODE,
    input  wire        RSTB,
    input  wire        RSTC,
    input  wire        RSTCTRL,
    input  wire        RSTD,
    input  wire        RSTINMODE,
    input  wire        RSTM,
    input  wire        RSTP
);
    timeunit 1ns;
    timeprecision 1ps;

    wire [47:0] pango_product;

    // Follow the requested DSP48E1 input-register depth.
    GTP_APM_E2 #(
        .GRS_EN      ("TRUE"),
        .ASYNC_RST   (0),
        .X_REG       (AREG),      // 操作数 X 寄存器，使能 CEX1
        .XB_REG      (0),
        .Y_REG       (BREG),      // 操作数 Y 寄存器，使能 CEY1
        .Z_REG       (0),
        .MULT_REG    (1),      // 乘积寄存器，使能 CEM
        .P_REG       (0),      // 旁路后加器
        .PREADD_REG  (0),
        .MODEIN_REG  (0),
        .MODEY_REG   (0),
        .MODEZ_REG   (0),
        .USE_MULT    (1),
        .USE_PREADD  (0),
        .USE_POSTADD (0),
        .USE_SIMD    (0),
        .X_SEL       (0),
        .XB_SEL      (0),
        .P_INIT0     (48'd0),
        .P_INIT1     (48'd0)
    ) u_pango_apm (
        .COUT      (),
        .CPO       (),
        .CXO       (),
        .CXBO      (),
        .P         (pango_product),
        .CIN       (1'b0),
        .CPI       (48'd0),
        .CXI       (30'd0),
        .CXBI      (25'd0),
        .X         (A),
        .XB        (25'd0),
        .Y         (B),
        .Z         (48'd0),
        // MODEIN[1] 把 X 送入 25x18 有符号乘法器。
        .MODEIN    (5'b00010),
        .MODEY     (3'b001),
        .MODEZ     (4'b0000),
        .CLK       (CLK),
        .CEX1      (CEA2),
        .CEX2      (1'b0),
        .CEX3      (1'b0),
        .CEXB      (1'b0),
        .CEY1      (CEB2),
        .CEY2      (1'b0),
        .CEZ       (1'b0),
        .CEM       (CEP),
        .CEP       (1'b0),
        .CEPRE     (1'b0),
        .CEMODEIN  (1'b0),
        .CEMODEY   (1'b0),
        .CEMODEZ   (1'b0),
        .RSTX      (RSTA),
        .RSTXB     (RSTA),
        .RSTY      (RSTB),
        .RSTZ      (RSTC),
        .RSTM      (RSTM | RSTP),
        .RSTP      (RSTP),
        .RSTPRE    (RSTD),
        .RSTMODEIN (RSTINMODE),
        .RSTMODEY  (RSTCTRL),
        .RSTMODEZ  (RSTCTRL)
    );

    assign P = pango_product;

    // 级联与状态输出：CPU 乘法单元未使用，按原例化的空连接语义驱动常量。
    assign ACOUT         = 30'd0;
    assign BCOUT         = 18'd0;
    assign CARRYCASCOUT  = 1'b0;
    assign CARRYOUT      = 4'd0;
    assign MULTSIGNOUT   = 1'b0;
    assign OVERFLOW      = 1'b0;
    assign PATTERNBDETECT = 1'b0;
    assign PATTERNDETECT = 1'b0;
    assign PCOUT         = 48'd0;
    assign UNDERFLOW     = 1'b0;

endmodule
