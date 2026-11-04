// RV32 non-cacheable scalar bus to the existing game MMIO and DDR ports.
// Every store is acknowledged only after the downstream response arrives.
module rv32_game_periph #(
 parameter logic [31:0] DDR_BASE=32'h80000000,
 parameter logic [32:0] DDR_BYTES=33'h010000000
)(
 input logic clk,rst,req,write,
 output logic gnt,
 input logic [31:0] addr,wdata,input logic [3:0] be,
 output logic rvalid,error,output logic [31:0] rdata,
 output logic system_req_valid,input logic system_req_ready,
 output logic [31:0] system_req_addr,system_req_wdata,
 output logic system_req_write,output logic [3:0] system_req_wstrb,
 input logic system_rsp_valid,output logic system_rsp_ready,
 input logic [31:0] system_rsp_rdata,input logic system_rsp_error,
 output logic mem_active,mem_req_valid,input logic mem_req_ready,
 output logic mem_req_write,output logic [31:0] mem_req_addr,
 output logic [127:0] mem_req_wdata,output logic [15:0] mem_req_wstrb,
 output logic [3:0] mem_req_tag,
 input logic mem_rsp_valid,output logic mem_rsp_ready,
 input logic mem_rsp_write,input logic [127:0] mem_rsp_rdata,
 input logic [3:0] mem_rsp_tag,input logic mem_rsp_error,
 output logic fault
);
 typedef enum logic [2:0] {IDLE,SYSTEM_REQ,SYSTEM_WAIT,DDR_REQ,DDR_WAIT,REPLY,STOP} state_t;
 state_t state;
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
