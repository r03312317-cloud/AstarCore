// [ARCH] 8 个 64 位 RV32 beat 与 4 个 128 位后端请求对应同一缓存行。
// [ARCH] 拼接保持小端字节位置，宽度转换不能忽略 beat 索引。
// [ARCH] 读请求和响应是分开的阶段，错误需要属于当前行。
// [ARCH] 写回等待真实下游写响应，不能在数据仅排队时提前完成。
// [ARCH] 请求和响应 tag 用于核对事务归属。
// RV32 eight-beat 64-bit cache line <-> unchanged D1 tagged 128-bit port.
// A write acknowledgement follows all four genuine downstream responses.
// Corrupt response ownership and failed writeback latch a reset-only fault;
// they never trigger automatic replay or successful completion.
// [ARCH] 读路径需要按半拍选择重新组成 64 位返回。
// [ARCH] 写路径需要同时保持两个半段的字节掩码。
// [ARCH] 最后 beat 与写确认属于不同事件。
// [ARCH] 任何优化都必须保留原来的错误累计和事务 tag。
module rv32_line128_adapter #(
 // [ARCH] DDR_BASE：后端 DDR 窗口基地址，先检查范围再转换为控制器地址。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 legal_rd, d64, legal_wr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 parameter logic [31:0] DDR_BASE=32'h80000000,
 // [ARCH] DDR_BYTES：后端可访问范围的长度，需与实际 DDR 实现和地址检查一致。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 d64 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 parameter logic [32:0] DDR_BYTES=33'h010000000
)(
 // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
 input logic clk,rst,
 // [ARCH] rd_req：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 wr_gnt 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic rd_req,output logic rd_gnt,input logic [31:0] rd_addr,input logic rd_id,
 // [ARCH] rd_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic rd_valid,input logic rd_ready,output logic [63:0] rd_data,
 // [ARCH] rd_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
 output logic rd_error,rd_rid,
 // [ARCH] wr_req：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 input logic wr_req,output logic wr_gnt,input logic [31:0] wr_addr,
 // [ARCH] wr_data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 base_q, id_q, write_q, collect_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic [63:0] wr_data,input logic wr_last,wr_id,
 // [ARCH] b_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 output logic b_valid,b_error,b_id,output logic fault,
 // [ARCH] mem_req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic mem_req_valid,input logic mem_req_ready,output logic mem_req_write,
 // [ARCH] mem_req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic [31:0] mem_req_addr,output logic [127:0] mem_req_wdata,
 // [ARCH] mem_req_wstrb：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic [15:0] mem_req_wstrb,output logic [3:0] mem_req_tag,
 // [ARCH] mem_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 input logic mem_rsp_valid,output logic mem_rsp_ready,input logic mem_rsp_write,
 // [ARCH] mem_rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 line_payload, line_initialized, error_q, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic [127:0] mem_rsp_rdata,input logic [3:0] mem_rsp_tag,input logic mem_rsp_error
);
 typedef enum logic [3:0] {IDLE,COLLECT,SEND,WAIT_RSP,READ_LOW,READ_HIGH,ACK,READ_ERROR,STOP} state_t;
 state_t state;
 logic [31:0] base_q;
 // Select the payload and its narrow validity together before masking.
 // This is the same visible value as masking all four lines before selecting,
 // including idle, partial-write, reset-recovery and error cycles.
 logic [127:0] line_payload[0:3];
 // [ARCH] line_initialized：初始化完成门控，防止把尚未设置的 RAM 内容当作有效状态。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 selected_initialized, write_q, error_q, error_beat 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic [7:0] line_initialized;
 logic [2:0] collect_q,error_beat;
 // [ARCH] index_q：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 selected_payload, selected_initialized, mem_req_addr, mem_req_tag 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic [1:0] index_q;
 wire [127:0] selected_payload=line_payload[index_q];
 // [ARCH] selected_initialized：初始化完成门控，防止把尚未设置的 RAM 内容当作有效状态。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 selected_line 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire [1:0] selected_initialized=line_initialized[{index_q,1'b0}+:2];
 wire [127:0] selected_line;
 assign selected_line[63:0]=selected_initialized[0]?selected_payload[63:0]:64'd0;
 assign selected_line[127:64]=selected_initialized[1]?selected_payload[127:64]:64'd0;
 logic write_q,id_q,error_q;
 wire legal_rd=rd_addr[5:0]==0&&{1'b0,rd_addr}>={1'b0,DDR_BASE}&&
    {1'b0,rd_addr}+33'd64<={1'b0,DDR_BASE}+DDR_BYTES;
 wire legal_wr=wr_addr[5:0]==0&&{1'b0,wr_addr}>={1'b0,DDR_BASE}&&
    {1'b0,wr_addr}+33'd64<={1'b0,DDR_BASE}+DDR_BYTES;
 assign rd_gnt=!rst&&!fault&&state==IDLE;
 assign wr_gnt=!rst&&!fault&&((state==IDLE&&!rd_req)||state==COLLECT);
 assign rd_valid=!rst&&(state==READ_LOW||state==READ_HIGH||state==READ_ERROR);
 assign rd_data=state==READ_ERROR?64'd0:state==READ_HIGH?selected_line[127:64]:selected_line[63:0];
 assign rd_error=state==READ_ERROR||error_q;
 assign rd_rid=id_q;
 assign b_valid=!rst&&state==ACK;
 assign b_error=error_q;
 assign b_id=id_q;
 assign mem_req_valid=!rst&&!fault&&state==SEND;
 assign mem_req_write=write_q;
 assign mem_req_addr=base_q+{26'd0,index_q,4'b0};
 assign mem_req_wdata=selected_line;
 assign mem_req_wstrb=write_q?16'hffff:16'd0;
 assign mem_req_tag={2'b00,index_q};
 assign mem_rsp_ready=!rst&&state==WAIT_RSP;
 always_ff @(posedge clk)begin
  if(rst)begin state<=IDLE;fault<=0;base_q<=0;collect_q<=0;index_q<=0;id_q<=0;
   write_q<=0;error_q<=0;error_beat<=0;line_initialized<='0;end
  else case(state)
   IDLE:begin
    error_q<=0;index_q<=0;
    if(rd_req&&rd_gnt)begin
     base_q<=rd_addr;id_q<=rd_id;write_q<=0;
     if(legal_rd)state<=SEND;else begin state<=READ_ERROR;error_beat<=0;end
    end else if(wr_req&&wr_gnt)begin
     base_q<=wr_addr;id_q<=wr_id;write_q<=1;collect_q<=1;line_payload[0][63:0]<=wr_data;line_initialized[0]<=1'b1;
     if(!legal_wr||wr_last)begin fault<=1;error_q<=1;state<=ACK;end
     else state<=COLLECT;
    end
   end
   COLLECT:if(wr_req&&wr_gnt)begin
    if(wr_addr!=base_q||wr_id!=id_q||wr_last!=(collect_q==7))begin
     fault<=1;error_q<=1;state<=ACK;
    end else begin
     if(collect_q[0])line_payload[collect_q[2:1]][127:64]<=wr_data;
     else line_payload[collect_q[2:1]][63:0]<=wr_data;
     line_initialized[collect_q]<=1'b1;
     if(collect_q==7)begin index_q<=0;state<=SEND;end
     else collect_q<=collect_q+1'b1;
    end
   end
   SEND:if(mem_req_valid&&mem_req_ready)state<=WAIT_RSP;
   WAIT_RSP:if(mem_rsp_valid&&mem_rsp_ready)begin
    if(mem_rsp_write!=write_q||mem_rsp_tag!={2'b00,index_q})begin fault<=1;state<=STOP;end
    else if(write_q)begin
     if(mem_rsp_error)begin fault<=1;error_q<=1;state<=ACK;end
     else if(index_q==3)state<=ACK;
     else begin index_q<=index_q+1'b1;state<=SEND;end
    end else begin
     line_payload[index_q]<=mem_rsp_rdata;line_initialized[{index_q,1'b0}+:2]<=2'b11;error_q<=mem_rsp_error;state<=READ_LOW;
    end
   end
   READ_LOW:if(rd_valid&&rd_ready)state<=READ_HIGH;
   READ_HIGH:if(rd_valid&&rd_ready)begin
    if(index_q==3)state<=IDLE;
    else begin index_q<=index_q+1'b1;state<=SEND;end
   end
   READ_ERROR:if(rd_valid&&rd_ready)begin
    if(error_beat==7)state<=IDLE;else error_beat<=error_beat+1'b1;
   end
   ACK:state<=fault?STOP:IDLE;
   STOP:state<=STOP;
   default:begin fault<=1;state<=STOP;end
  endcase
 end
endmodule
