// Isolated experiment: one native APM holds product and modulo48 accumulator.
// No vendor simulation source is copied; use the installed licensed library.
// 架构导读：npu_mac_pe。
// Pango APM 乘加单元，使用 48 位累加寄存器，清零优先于有效乘加使能。
module npu_mac_pe #(
 // 静态配置：parameter int ACC_W=48, MUL_PIPE_STAGES=2。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter int ACC_W=48, MUL_PIPE_STAGES=2
)(
 // 接口声明：input logic clk,rst,clear_acc,input_int16,a_valid_in,b_valid_in。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic clk,rst,clear_acc,input_int16,a_valid_in,b_valid_in,
 input logic signed [15:0] a_in,b_in,
 output logic a_valid_out,b_valid_out,
 output logic signed [15:0] a_out,b_out,
 output logic signed [ACC_W-1:0] acc_value
);
 // 静态配置：localparam int INPUT_REG=(MUL_PIPE_STAGES==2)?1:0。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam int INPUT_REG=(MUL_PIPE_STAGES==2)?1:0;
 logic signed [15:0] a_signed,b_signed;
 logic valid_pipe[0:MUL_PIPE_STAGES-1];
 wire [47:0] native_p;
 assign a_signed=input_int16 ? a_in : $signed({{8{a_in[7]}},a_in[7:0]});
 assign b_signed=input_int16 ? b_in : $signed({{8{b_in[7]}},b_in[7:0]});
 assign acc_value=$signed(native_p);
 // Transport payload is meaningful only with its separately reset valid.
 always_ff @(posedge clk)begin
  a_out<=a_in;b_out<=b_in;
 end
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin
   a_valid_out<=0;b_valid_out<=0;
   for(int p=0;p<MUL_PIPE_STAGES;p++)valid_pipe[p]<=0;
  end else begin
   a_valid_out<=a_valid_in;b_valid_out<=b_valid_in;
   valid_pipe[0]<=a_valid_in&&b_valid_in;
   for(int p=1;p<MUL_PIPE_STAGES;p++)valid_pipe[p]<=valid_pipe[p-1];
  end
 end
 // Input-register + M-register + P-register matches the original two product
 // stages followed by accumulation. With MUL_PIPE1 the input register bypasses.
 // P reset wins over CEP, as original clear_acc wins over a pending valid MAC.
 GTP_APM_E2 #(
  .GRS_EN("TRUE"),.ASYNC_RST(0),.USE_MULT(1),.USE_POSTADD(1),
  .USE_PREADD(0),.USE_SIMD(0),.X_REG(INPUT_REG),.Y_REG(INPUT_REG),
  .MULT_REG(1),.P_REG(1),.Z_REG(0),.XB_REG(0),.PREADD_REG(0),
  .MODEY_REG(0),.MODEZ_REG(0),.MODEIN_REG(0),.X_SEL(0),.XB_SEL(0),
  .P_INIT0(48'd0),.P_INIT1(48'd0),.ROUNDMODE_SEL(0),.USE_ACCLOW(0),.CIN_SEL(0)
 ) mac(
  .P(native_p),.CPO(),.COUT(),.CXO(),.CXBO(),
  .X({{14{a_signed[15]}},a_signed}),.Y({{2{b_signed[15]}},b_signed}),
  .XB(25'd0),.CXI(30'd0),.CXBI(25'd0),.Z(48'd0),.CPI(48'd0),.CIN(1'b0),
  .MODEIN(5'b00010),.MODEY(3'b001),.MODEZ(4'b0001),.CLK(clk),
  .CEX1(1'b1),.CEX2(1'b0),.CEX3(1'b0),.CEXB(1'b0),
  .CEY1(1'b1),.CEY2(1'b0),.CEZ(1'b0),.CEPRE(1'b0),.CEM(1'b1),
  .CEP(valid_pipe[MUL_PIPE_STAGES-1]),.CEMODEY(1'b0),.CEMODEZ(1'b0),.CEMODEIN(1'b0),
  // Input/product payload is overwritten before valid_pipe can enable CEP.
  // RSTP remains unchanged: reset/clear still wins over every pending MAC.
  .RSTX(1'b0),.RSTY(1'b0),.RSTM(1'b0),.RSTP(rst||clear_acc),
  // All six auxiliary register paths are statically bypassed or disabled.
  // Keep RSTP above: reset/clear of the48-bit accumulator is unchanged.
  .RSTXB(1'b0),.RSTZ(1'b0),.RSTPRE(1'b0),.RSTMODEY(1'b0),.RSTMODEZ(1'b0),.RSTMODEIN(1'b0)
 );
 initial begin
  if(ACC_W!=48||(MUL_PIPE_STAGES!=1&&MUL_PIPE_STAGES!=2))
   $fatal(1,"APM_MAC48 experimentalconfigurationunsupported");
 end
endmodule
