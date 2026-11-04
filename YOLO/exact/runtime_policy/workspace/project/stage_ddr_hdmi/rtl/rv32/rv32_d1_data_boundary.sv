// Registered D-channel boundary for the full, unchanged RV32 core/cache.
// No combinational memory-ready, tag-hit or response path reaches the core.
// Requests and errors remain ordered; cache maintenance drains older owners.
module rv32_d1_data_boundary (
 input logic clk,rst,
 input logic c_valid,c_write,
 output logic c_ready,
 input logic [31:0] c_addr,c_wdata,
 input logic [3:0] c_strobe,
 input logic [1:0] c_size,
 output logic c_rsp_valid,c_rsp_error,
 input logic c_rsp_ready,
 output logic [31:0] c_rdata,
 input logic c_fence_i,c_fence_d,
 output logic m_valid,m_write,
 input logic m_ready,
 output logic [31:0] m_addr,m_wdata,
 output logic [3:0] m_strobe,
 output logic [1:0] m_size,
 input logic m_rsp_valid,m_rsp_error,
 output logic m_rsp_ready,
 input logic [31:0] m_rdata,
 output logic m_fence_i,m_fence_d,
 output logic barrier_pending,
 output logic fault
);
 logic request_full,response_full,pending_i,pending_d;
 logic [1:0] owners;
 wire push=c_valid&&c_ready;
 wire take=m_valid&&m_ready;
 wire receive=m_rsp_valid&&m_rsp_ready;
 wire consume=c_rsp_valid&&c_rsp_ready;
 wire barrier=(pending_i||pending_d)&&owners==0&&!request_full&&!response_full&&!fault;
 // Deliberately omit full+pop turnover: space and response validity depend
 // on registers only. Payload reset is unnecessary while validity is clear.
 assign c_ready=!rst&&!fault&&!request_full&&owners!=3&&
                !pending_i&&!pending_d&&!c_fence_i&&!c_fence_d;
 assign m_valid=!rst&&!fault&&request_full;
 assign m_rsp_ready=!rst&&!fault&&!response_full;
 assign c_rsp_valid=!rst&&!fault&&response_full;
 assign m_fence_i=barrier&&pending_i;
 assign m_fence_d=barrier&&pending_d;
 // Stop post-FENCE fetch admission during the drain/forward gap. Already
 // accepted old-epoch I responses still drain through the original frontend.
 assign barrier_pending=c_fence_i||c_fence_d||pending_i||pending_d;
 always_ff @(posedge clk)begin
  if(push)begin m_addr<=c_addr;m_wdata<=c_wdata;m_strobe<=c_strobe;m_size<=c_size;m_write<=c_write;end
  if(receive)begin c_rdata<=m_rdata;c_rsp_error<=m_rsp_error;end
  if(rst)begin request_full<=0;response_full<=0;pending_i<=0;pending_d<=0;owners<=0;fault<=0;end
  else begin
   if(take)request_full<=0;
   if(push)request_full<=1;
   if(consume)response_full<=0;
   if(receive)response_full<=1;
   case({push,consume})
    2'b10:owners<=owners+1'b1;
    2'b01:owners<=owners-1'b1;
    default:;
   endcase
   if(barrier)begin pending_i<=0;pending_d<=0;end
   if(c_fence_i)pending_i<=1;
   if(c_fence_d)pending_d<=1;
   if((receive&&owners==0)||(consume&&owners==0))fault<=1;
  end
 end
`ifdef VERILATOR
 always @(posedge clk)if(!rst)begin
  if(consume&&owners==0)$fatal(1,"RV32 registered D boundary response without owner");
  if((m_fence_i||m_fence_d)&&(owners!=0||request_full||response_full))$fatal(1,"RV32 registered D boundary FENCE overtook transaction");
 end
`endif
endmodule
