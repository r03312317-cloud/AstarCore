// CPU 0x7000_0000+offset ready/valid transport to the supplied NPU's
// legacy 0x8020_0200 register bank. Transport errors do NOT rewrite NPU's
// command rejection/status semantics. Exactly one legacy write pulse.
// Zero strobe is an accepted no-op. Illegal/discontiguous strobes are rejected
// atomically; no read-modify-write of doorbell/W1C/action registers is used.
// 架构导读：pg_npu_mmio_bridge。
// 把本地寄存器事务转换为 NPU 控制端口格式。
module pg_npu_mmio_bridge (
 // 接口声明：input logic clk,rst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic clk,rst,
 // 接口声明：input logic req_valid,output logic req_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic req_valid,output logic req_ready,
 // 接口声明：input logic [15:0] req_addr,input logic req_write。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [15:0] req_addr,input logic req_write,
 // 接口声明：input logic [31:0] req_wdata,input logic [3:0] req_wstrb。
 // 按字节选择本次写入生效的 lane。
 input logic [31:0] req_wdata,input logic [3:0] req_wstrb,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_rdata,output logic rsp_error,
 output logic [31:0] legacy_addr,legacy_wdata,
 output logic legacy_wen,output logic [1:0] legacy_mask,
 input logic [31:0] legacy_rdata
);
 typedef enum logic [2:0] {IDLE,ISSUE,WAIT1,WAIT2,RESPONSE} state_t;
 state_t state;
 logic [31:0] addr_q,data_q,rdata_q;
 logic [1:0] mask_q;
 logic write_q,pulse_q,error_q;
 logic access_error,write_pulse;
 logic [31:0] converted_data;
 logic [1:0] converted_mask;
 // 过程边界：always_comb begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_comb begin
   access_error=req_addr[15:8]!=0;
   write_pulse=req_write&&(req_wstrb!=0);
   converted_data=0;converted_mask=0;
   if(write_pulse)begin
     if(req_wstrb==(4'b0001<<req_addr[1:0]))begin
       converted_mask=0;converted_data=req_wdata>>(8*req_addr[1:0]);
     end else if(!req_addr[0]&&(req_wstrb==(4'b0011<<req_addr[1:0])))begin
       converted_mask=1;converted_data=req_wdata>>(8*req_addr[1:0]);
     end else if(req_addr[1:0]==0&&req_wstrb==4'b1111)begin
       converted_mask=2;converted_data=req_wdata;
     end else access_error=1;
   end
 end
 assign req_ready=!rst&&(state==IDLE);
 assign rsp_valid=!rst&&(state==RESPONSE);
 assign rsp_rdata=rdata_q;
 assign rsp_error=error_q;
 assign legacy_addr=addr_q;
 assign legacy_wdata=data_q;
 assign legacy_mask=mask_q;
 assign legacy_wen=!rst&&(state==ISSUE)&&pulse_q;
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
   // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
   if(rst)begin state<=IDLE;addr_q<=0;data_q<=0;rdata_q<=0;mask_q<=0;
     write_q<=0;pulse_q<=0;error_q<=0;end
   else case(state)
     // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
     IDLE:if(req_valid)begin
       addr_q<=32'h8020_0200+{24'd0,req_addr[7:0]};
       data_q<=converted_data;mask_q<=converted_mask;
       write_q<=req_write;pulse_q<=write_pulse&&!access_error;
       error_q<=access_error;rdata_q<=0;
       state<=access_error?RESPONSE:ISSUE;
     end
     // 状态/选择分支 ISSUE：本分支规定该编码下的寄存器更新和下一步动作。
     ISSUE:state<=WAIT1;
     // 状态/选择分支 WAIT1：本分支规定该编码下的寄存器更新和下一步动作。
     WAIT1:state<=WAIT2;
     // 状态/选择分支 WAIT2：本分支规定该编码下的寄存器更新和下一步动作。
     WAIT2:begin rdata_q<=write_q?32'd0:legacy_rdata;state<=RESPONSE;end
     // 状态/选择分支 RESPONSE：本分支规定该编码下的寄存器更新和下一步动作。
     RESPONSE:if(rsp_ready)state<=IDLE;
     default:begin state<=RESPONSE;error_q<=1;rdata_q<=0;pulse_q<=0;end
   endcase
 end
endmodule
