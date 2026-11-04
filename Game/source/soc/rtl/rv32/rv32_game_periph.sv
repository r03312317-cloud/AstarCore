// [ARCH] 适配非缓存访问，分别路由 MMIO 与 DDR 单次数据请求。
// [ARCH] 不同下游的响应必须送回原来保持中的事务所有者。
// [ARCH] 字节选通只允许修改有效字节，不能把所有写都扩大成整字。
// [ARCH] 外设可能有不可撤销副作用，软件保留访问两侧的排序屏障。
// [ARCH] mem_active 参与下游响应选择，不能仅按当前地址临时改选。
// RV32 non-cacheable scalar bus to the existing game MMIO and DDR ports.
// Every store is acknowledged only after the downstream response arrives.
module rv32_game_periph #(
 // [ARCH] DDR_BASE：后端 DDR 窗口基地址，先检查范围再转换为控制器地址。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 is_ddr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 parameter logic [31:0] DDR_BASE=32'h80000000,
 // [ARCH] DDR_BYTES：后端可访问范围的长度，需与实际 DDR 实现和地址检查一致。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 is_ddr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 parameter logic [32:0] DDR_BYTES=33'h010000000
)(
 // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
 input logic clk,rst,req,write,
 // [ARCH] gnt：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。
 output logic gnt,
 // [ARCH] addr：地址与当前请求/响应归属配对，不能独立于有效条件使用。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 is_ddr, address_q, data_q, strobe_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic [31:0] addr,wdata,input logic [3:0] be,
 // [ARCH] rvalid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 output logic rvalid,error,output logic [31:0] rdata,
 // [ARCH] system_req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic system_req_valid,input logic system_req_ready,
 // [ARCH] system_req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 system_req_write 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic [31:0] system_req_addr,system_req_wdata,
 // [ARCH] system_req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 system_req_addr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic system_req_write,output logic [3:0] system_req_wstrb,
 // [ARCH] system_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 input logic system_rsp_valid,output logic system_rsp_ready,
 // [ARCH] system_rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 result_q, error_q, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic [31:0] system_rsp_rdata,input logic system_rsp_error,
 output logic mem_active,mem_req_valid,input logic mem_req_ready,
 // [ARCH] mem_req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic mem_req_write,output logic [31:0] mem_req_addr,
 // [ARCH] mem_req_wdata：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic [127:0] mem_req_wdata,output logic [15:0] mem_req_wstrb,
 // [ARCH] mem_req_tag：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic [3:0] mem_req_tag,
 // [ARCH] mem_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 input logic mem_rsp_valid,output logic mem_rsp_ready,
 input logic mem_rsp_write,input logic [127:0] mem_rsp_rdata,
 // [ARCH] mem_rsp_tag：保存本接口的所有者/事务编号；匹配时仍需检查有效资格，不能混用其他接口的 tag。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 fault, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic [3:0] mem_rsp_tag,input logic mem_rsp_error,
 // [ARCH] fault：错误事实应记录到所属指令/事务，再在允许的精确边界处理。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 state, address_q, data_q, strobe_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic fault
);
 typedef enum logic [2:0] {IDLE,SYSTEM_REQ,SYSTEM_WAIT,DDR_REQ,DDR_WAIT,REPLY,STOP} state_t;
 state_t state;
 // [ARCH] address_q：保持当前事务地址，等待/背压期间不能换成下一请求的地址。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 system_req_addr, system_req_write, mem_req_addr, mem_req_wdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic [31:0] address_q,data_q,result_q;
 logic [3:0] strobe_q;
 logic write_q,error_q;
 wire is_ddr={1'b0,addr}>={1'b0,DDR_BASE}&&{1'b0,addr}<{1'b0,DDR_BASE}+DDR_BYTES;
 assign gnt=!rst&&state==IDLE;
 assign rvalid=!rst&&state==REPLY;
 assign rdata=result_q;assign error=error_q;
 assign system_req_valid=!rst&&state==SYSTEM_REQ;
 assign system_req_addr=address_q;assign system_req_write=write_q;
 assign system_req_wdata=data_q;assign system_req_wstrb=strobe_q;
 assign system_rsp_ready=!rst&&state==SYSTEM_WAIT;
 assign mem_active=state==DDR_REQ||state==DDR_WAIT;
 assign mem_req_valid=!rst&&state==DDR_REQ;
 assign mem_req_write=write_q;
 assign mem_req_addr={address_q[31:4],4'b0};
 assign mem_req_wdata={96'd0,data_q}<<{address_q[3:2],5'b0};
 assign mem_req_wstrb={12'd0,strobe_q}<<{address_q[3:2],2'b0};
 assign mem_req_tag=4'h8;
 assign mem_rsp_ready=!rst&&state==DDR_WAIT;
 always_ff @(posedge clk)begin
  if(rst)begin state<=IDLE;address_q<=0;data_q<=0;strobe_q<=0;write_q<=0;result_q<=0;error_q<=0;fault<=0;end
  else case(state)
   IDLE:if(req&&gnt)begin
    address_q<=addr;data_q<=wdata;strobe_q<=be;write_q<=write;error_q<=0;
    state<=is_ddr?DDR_REQ:SYSTEM_REQ;
   end
   SYSTEM_REQ:if(system_req_valid&&system_req_ready)state<=SYSTEM_WAIT;
   SYSTEM_WAIT:if(system_rsp_valid&&system_rsp_ready)begin
    result_q<=system_rsp_rdata;error_q<=system_rsp_error;state<=REPLY;
   end
   DDR_REQ:if(mem_req_valid&&mem_req_ready)state<=DDR_WAIT;
   DDR_WAIT:if(mem_rsp_valid&&mem_rsp_ready)begin
    if(mem_rsp_tag!=4'h8||mem_rsp_write!=write_q)begin fault<=1;state<=STOP;end
    else begin result_q<=mem_rsp_rdata[{address_q[3:2],5'b0}+:32];error_q<=mem_rsp_error;state<=REPLY;end
   end
   REPLY:state<=IDLE;
   STOP:state<=STOP;
   default:begin fault<=1;state<=STOP;end
  endcase
 end
endmodule
