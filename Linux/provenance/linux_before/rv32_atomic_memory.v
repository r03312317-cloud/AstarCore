// Single-hart atomic owner. Place behind address translation and ahead of the
// physical D-cache arbiter. lock remains asserted through read/modify/write.
// External masters that write shared words must assert reservation_kill.
module rv32_atomic_memory(
 input clk,reset,reservation_kill,
 input req_valid,output req_ready,input [31:0] req_addr,req_wdata,
 input req_write,input [3:0] req_wstrb,input [1:0] req_size,
 input req_atomic,input [4:0] req_amo,
 output reg rsp_valid,input rsp_ready,output reg [31:0] rsp_data,output reg rsp_error,
 output mem_valid,input mem_ready,output [31:0] mem_addr,mem_wdata,
 output mem_write,output [3:0] mem_wstrb,output [1:0] mem_size,
 input mem_rsp_valid,output mem_rsp_ready,input [31:0] mem_rsp_data,input mem_rsp_error,
 output lock
);
 localparam IDLE=0, READ_REQ=1, READ_WAIT=2, WRITE_REQ=3, WRITE_WAIT=4;
 reg [2:0] state;
 reg [31:0] addr,data,result,write_data;
 reg [3:0] strb;reg [1:0] size;reg write_op,atomic_op;reg [4:0] amo;
 reg reserved;reg [29:0] reserved_word;
 wire lr=atomic_op&&amo==5'b00010;
 wire sc=atomic_op&&amo==5'b00011;
 assign req_ready=!reset&&state==IDLE&&!rsp_valid;
 assign mem_valid=!reset&&(state==READ_REQ||state==WRITE_REQ);
 assign mem_addr=addr;assign mem_wdata=write_data;
 assign mem_write=state==WRITE_REQ;assign mem_wstrb=atomic_op?4'hf:strb;
 assign mem_size=atomic_op?2'd2:size;
 assign mem_rsp_ready=state==READ_WAIT||state==WRITE_WAIT;
 assign lock=state!=IDLE;
 function [31:0] apply_amo;
 input [4:0] op;input [31:0] old_value,operand;
 begin case(op)
 5'b00001:apply_amo=operand;
 5'b00000:apply_amo=old_value+operand;
 5'b00100:apply_amo=old_value^operand;
 5'b01100:apply_amo=old_value&operand;
 5'b01000:apply_amo=old_value|operand;
 5'b10000:apply_amo=$signed(old_value)<$signed(operand)?old_value:operand;
 5'b10100:apply_amo=$signed(old_value)>$signed(operand)?old_value:operand;
 5'b11000:apply_amo=old_value<operand?old_value:operand;
 5'b11100:apply_amo=old_value>operand?old_value:operand;
 default:apply_amo=0;
 endcase end endfunction
 function legal_amo;
 input [4:0] op;
 begin case(op) 0,1,2,3,4,8,12,16,20,24,28:legal_amo=1;default:legal_amo=0;endcase end
 endfunction
 always @(posedge clk)begin
 if(reset)begin state<=IDLE;rsp_valid<=0;rsp_data<=0;rsp_error<=0;reserved<=0;reserved_word<=0;
 addr<=0;data<=0;result<=0;write_data<=0;strb<=0;size<=0;write_op<=0;atomic_op<=0;amo<=0;end
 else begin
 if(reservation_kill)reserved<=0;
 if(rsp_valid&&rsp_ready)rsp_valid<=0;
 case(state)
 IDLE:if(req_valid&&req_ready)begin
 addr<=req_addr;data<=req_wdata;write_data<=req_wdata;strb<=req_wstrb;size<=req_size;
 write_op<=req_write;atomic_op<=req_atomic;amo<=req_amo;result<=0;rsp_error<=0;
 if(req_atomic&&(req_addr[1:0]!=0||req_size!=2||!legal_amo(req_amo)))begin
 rsp_valid<=1;rsp_error<=1;rsp_data<=0;reserved<=0;
 end else if(req_atomic&&req_amo==3)begin
 reserved<=0;
 if(reserved&&!reservation_kill&&reserved_word==req_addr[31:2])state<=WRITE_REQ;
 else begin rsp_valid<=1;rsp_data<=1;end
 end else if(req_atomic||!req_write)begin state<=READ_REQ;end
 else begin state<=WRITE_REQ;if(reserved_word==req_addr[31:2])reserved<=0;end
 end
 READ_REQ:if(mem_ready)state<=READ_WAIT;
 READ_WAIT:if(mem_rsp_valid)begin
 if(mem_rsp_error)begin rsp_valid<=1;rsp_error<=1;rsp_data<=0;state<=IDLE;reserved<=0;end
 else if(!atomic_op||lr)begin
 rsp_valid<=1;rsp_data<=mem_rsp_data;state<=IDLE;
 if(lr&&!reservation_kill)begin reserved<=1;reserved_word<=addr[31:2];end
 end else begin result<=mem_rsp_data;write_data<=apply_amo(amo,mem_rsp_data,data);state<=WRITE_REQ;reserved<=0;end
 end
 WRITE_REQ:if(mem_ready)state<=WRITE_WAIT;
 WRITE_WAIT:if(mem_rsp_valid)begin rsp_valid<=1;rsp_error<=mem_rsp_error;
 rsp_data<=sc?0:(atomic_op?result:0);state<=IDLE;end
 default:state<=IDLE;
 endcase
 end
 end
endmodule
