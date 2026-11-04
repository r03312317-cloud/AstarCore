// One owned uncached request. Retains D1 TCM, MMIO, NPU and shared DDR addresses.
// RV32 supplies aligned word data/strobes for subword stores; returned loads are
// complete 32-bit words so the original RV32 LSU performs sign/zero extension.
// 架构导读：rv32_d1_uncached。
// CPU 缓存/回填连接路径，维护访问命中、外部事务与响应边界。
module rv32_d1_uncached #(
 // 静态配置：parameter integer DTCM_ADDR_WIDTH=14,DTCM_READ_LATENCY=1。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer DTCM_ADDR_WIDTH=14,DTCM_READ_LATENCY=1,
 // 静态配置：parameter DTCM_INIT_FILE=""。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter DTCM_INIT_FILE="",
 // 静态配置：parameter logic [31:0] DDR_BASE=32'h80000000。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter logic [31:0] DDR_BASE=32'h80000000,
 // 静态配置：parameter logic [32:0] DDR_BYTES=33'h010000000。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter logic [32:0] DDR_BYTES=33'h010000000
)(
 // 接口声明：input logic clk,rst,input logic req,output logic gnt,input logic write。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic clk,rst,input logic req,output logic gnt,input logic write,
 // 接口声明：input logic [31:0] addr,wdata,input logic [3:0] be,input logic [1:0] size。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [31:0] addr,wdata,input logic [3:0] be,input logic [1:0] size,
 // 接口声明：output logic rvalid,error,output logic [31:0] rdata。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 output logic rvalid,error,output logic [31:0] rdata,
 // 接口声明：output logic native_req,input logic native_ready,output logic native_write。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic native_req,input logic native_ready,output logic native_write,
 // 接口声明：output logic [31:0] native_addr,native_wdata,output logic [3:0] native_strb。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [31:0] native_addr,native_wdata,output logic [3:0] native_strb,
 // 接口声明：input logic native_rvalid,output logic native_rready,input logic [31:0] native_rdata,input logic native_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 input logic native_rvalid,output logic native_rready,input logic [31:0] native_rdata,input logic native_error,
 output logic mem_active,mem_req_valid,input logic mem_req_ready,output logic mem_req_write,
 output logic [31:0] mem_req_addr,output logic [127:0] mem_req_wdata,
 output logic [15:0] mem_req_wstrb,output logic [3:0] mem_req_tag,
 input logic mem_rsp_valid,output logic mem_rsp_ready,input logic mem_rsp_write,
 input logic [127:0] mem_rsp_rdata,input logic [3:0] mem_rsp_tag,input logic mem_rsp_error,
 output logic maintenance_req,maintenance_done,input logic maintenance_busy,input logic cache_fault,
 output logic [31:0] control_addr,input logic [31:0] control_rdata,
 output logic fault,output logic [31:0] mmio_submits,mmio_wait_cycles,ddr_uncached_count
);
 typedef enum logic[3:0]{IDLE,DECODE,TCM_REQ,TCM_WAIT,NATIVE_REQ,NATIVE_WAIT,DDR_REQ,DDR_WAIT,MAINT_WAIT,REPLY,STOP} state_t;
 state_t state;
 logic [31:0] addr_q,data_q,reply_q;
 logic [3:0] be_q;
 logic write_q,error_q,seen_busy;
 logic [1:0] size_q;
 logic tr,sv,se;
 logic [31:0] td;
 wire is_tcm=addr_q>=32'h20000000&&{1'b0,addr_q}<33'h020000000+33'(4<<DTCM_ADDR_WIDTH);
 wire is_ddr={1'b0,addr_q}>={1'b0,DDR_BASE}&&{1'b0,addr_q}<{1'b0,DDR_BASE}+DDR_BYTES;
 wire is_control=addr_q[31:5]==27'h1800008;
 wire is_stats=addr_q[31:8]==24'h300002;
 assign gnt=!rst&&!fault&&state==IDLE;
 assign rvalid=!rst&&state==REPLY;
 assign rdata=reply_q;
 assign error=error_q;
 assign native_req=!rst&&state==NATIVE_REQ;
 assign native_addr=addr_q;assign native_wdata=data_q;assign native_strb=be_q;assign native_write=write_q;
 assign native_rready=!rst&&state==NATIVE_WAIT;
 assign mem_active=state==DDR_REQ||state==DDR_WAIT;
 assign mem_req_valid=!rst&&state==DDR_REQ;
 assign mem_req_write=write_q;assign mem_req_addr={addr_q[31:4],4'b0};
 assign mem_req_wdata={96'd0,data_q}<<(32*addr_q[3:2]);
 assign mem_req_wstrb=write_q?({12'd0,be_q}<<(4*addr_q[3:2])):16'd0;
 assign mem_req_tag=4'd8;
 assign mem_rsp_ready=!rst&&state==DDR_WAIT;
 assign control_addr=addr_q;
 dc_realtime_core_tcm_channel #(.ADDR_WIDTH(DTCM_ADDR_WIDTH),.BASE_ADDR(32'h20000000),
  .INIT_FILE(DTCM_INIT_FILE),.READ_LATENCY(DTCM_READ_LATENCY),.EARLY_STORE_ACK(1'b1)) dtcm(
  .clk,.rst,.req_valid(state==TCM_REQ&&!rst),.req_ready(tr),.req_addr(addr_q),.req_write(write_q),
  .req_wdata(data_q),.req_wstrb(be_q),.rsp_valid(sv),.rsp_ready(state==TCM_WAIT&&!rst),.rsp_rdata(td),.rsp_error(se));
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin state<=IDLE;addr_q<=0;data_q<=0;reply_q<=0;be_q<=0;write_q<=0;size_q<=0;
   error_q<=0;seen_busy<=0;maintenance_req<=0;maintenance_done<=0;fault<=0;mmio_submits<=0;mmio_wait_cycles<=0;ddr_uncached_count<=0;end
  else begin
   maintenance_req<=0;maintenance_done<=0;
   if(state==NATIVE_REQ||state==NATIVE_WAIT)mmio_wait_cycles<=mmio_wait_cycles+1'b1;
   // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case(state)
    // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
    IDLE:if(req&&gnt)begin addr_q<=addr;data_q<=wdata;be_q<=be;write_q<=write;size_q<=size;error_q<=0;reply_q<=0;state<=DECODE;end
    // 状态/选择分支 DECODE：本分支规定该编码下的寄存器更新和下一步动作。
    DECODE:begin
     if(size_q==3||(size_q==1&&addr_q[0])||(size_q==2&&addr_q[1:0]!=0))begin error_q<=1;state<=REPLY;end
     else if(is_control||is_stats)begin
      reply_q<=control_rdata;state<=REPLY;
      if(addr_q[1:0]!=0||size_q!=2)error_q<=1;
      else if(write_q)begin
       if(!is_control||addr_q[4:0]!=0||data_q!=1||be_q!=15)error_q<=1;
       else begin maintenance_req<=1;seen_busy<=0;state<=MAINT_WAIT;end
      end
     end else if(is_tcm)state<=TCM_REQ;
     else if(is_ddr)begin ddr_uncached_count<=ddr_uncached_count+1'b1;state<=DDR_REQ;end
     else begin mmio_submits<=mmio_submits+1'b1;state<=NATIVE_REQ;end
    end
    // 状态/选择分支 TCM_REQ：本分支规定该编码下的寄存器更新和下一步动作。
    TCM_REQ:if(tr)state<=TCM_WAIT;
    // 状态/选择分支 TCM_WAIT：本分支规定该编码下的寄存器更新和下一步动作。
    TCM_WAIT:if(sv)begin reply_q<=td;error_q<=se;state<=REPLY;end
    // 状态/选择分支 NATIVE_REQ：本分支规定该编码下的寄存器更新和下一步动作。
    NATIVE_REQ:if(native_req&&native_ready)state<=NATIVE_WAIT;
    // 状态/选择分支 NATIVE_WAIT：本分支规定该编码下的寄存器更新和下一步动作。
    NATIVE_WAIT:if(native_rvalid&&native_rready)begin reply_q<=native_rdata;error_q<=native_error;state<=REPLY;end
    // 状态/选择分支 DDR_REQ：本分支规定该编码下的寄存器更新和下一步动作。
    DDR_REQ:if(mem_req_valid&&mem_req_ready)state<=DDR_WAIT;
    // 状态/选择分支 DDR_WAIT：本分支规定该编码下的寄存器更新和下一步动作。
    DDR_WAIT:if(mem_rsp_valid&&mem_rsp_ready)begin
     if(mem_rsp_write!=write_q||mem_rsp_tag!=8)begin fault<=1;state<=STOP;end
     else begin reply_q<=mem_rsp_rdata[32*addr_q[3:2]+:32];error_q<=mem_rsp_error;state<=REPLY;end
    end
    // 状态/选择分支 MAINT_WAIT：本分支规定该编码下的寄存器更新和下一步动作。
    MAINT_WAIT:begin
     if(maintenance_busy)seen_busy<=1;
     if(cache_fault)begin error_q<=1;state<=REPLY;end
     else if(seen_busy&&!maintenance_busy)begin maintenance_done<=1;state<=REPLY;end
    end
    // 状态/选择分支 REPLY：本分支规定该编码下的寄存器更新和下一步动作。
    REPLY:state<=IDLE;
    // 状态/选择分支 STOP：本分支规定该编码下的寄存器更新和下一步动作。
    STOP:state<=STOP;
    default:begin fault<=1;state<=STOP;end
   endcase
  end
 end
endmodule
