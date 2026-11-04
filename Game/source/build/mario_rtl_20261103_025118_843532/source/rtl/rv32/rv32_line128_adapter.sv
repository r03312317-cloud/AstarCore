// RV32 eight-beat 64-bit cache line <-> unchanged D1 tagged 128-bit port.
// A write acknowledgement follows all four genuine downstream responses.
// Corrupt response ownership and failed writeback latch a reset-only fault;
// they never trigger automatic replay or successful completion.
module rv32_line128_adapter #(
 parameter logic [31:0] DDR_BASE=32'h80000000,
 parameter logic [32:0] DDR_BYTES=33'h010000000
)(
 input logic clk,rst,
 input logic rd_req,output logic rd_gnt,input logic [31:0] rd_addr,input logic rd_id,
 output logic rd_valid,input logic rd_ready,output logic [63:0] rd_data,
 output logic rd_error,rd_rid,
 input logic wr_req,output logic wr_gnt,input logic [31:0] wr_addr,
 input logic [63:0] wr_data,input logic wr_last,wr_id,
 output logic b_valid,b_error,b_id,output logic fault,
 output logic mem_req_valid,input logic mem_req_ready,output logic mem_req_write,
 output logic [31:0] mem_req_addr,output logic [127:0] mem_req_wdata,
 output logic [15:0] mem_req_wstrb,output logic [3:0] mem_req_tag,
 input logic mem_rsp_valid,output logic mem_rsp_ready,input logic mem_rsp_write,
 input logic [127:0] mem_rsp_rdata,input logic [3:0] mem_rsp_tag,input logic mem_rsp_error
);
 typedef enum logic [3:0] {IDLE,COLLECT,SEND,WAIT_RSP,READ_LOW,READ_HIGH,ACK,READ_ERROR,STOP} state_t;
 state_t state;
 logic [31:0] base_q;
 // Select the payload and its narrow validity together before masking.
 // This is the same visible value as masking all four lines before selecting,
 // including idle, partial-write, reset-recovery and error cycles.
 logic [127:0] line_payload[0:3];
 logic [7:0] line_initialized;
 logic [2:0] collect_q,error_beat;
 logic [1:0] index_q;
 wire [127:0] selected_payload=line_payload[index_q];
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
