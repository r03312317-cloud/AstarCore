`timescale 1ns/1ps
// Cache control occupies 0x30000100..0x3000011f; original UART MMIO stays intact.
// Write 1 to +0 from ITCM: stop new fetches, drain accepted owners, invalidate
// both caches, then return the store response. This is NOT an implementation of
// FENCE.I or a flush of the frozen CPU's internal instruction queue.
module pg_cached_data_router #(
 parameter logic [31:0] DDR_BASE=32'h80000000,
 parameter logic [32:0] DDR_BYTES=33'h010000000
)(
 input logic clk,rst,
 input logic req_valid,req_write,req_is_fetch,input logic [31:0] req_addr,req_wdata,input logic [3:0] req_wstrb,output logic req_ready,
 output logic rsp_valid,rsp_error,output logic [31:0] rsp_rdata,input logic rsp_ready,
 output logic d_req_valid,d_req_write,d_req_fetch,output logic [31:0] d_req_addr,d_req_wdata,output logic [3:0] d_req_wstrb,input logic d_req_ready,
 input logic d_rsp_valid,d_rsp_error,input logic [31:0] d_rsp_rdata,output logic d_rsp_ready,
 output logic p_req_valid,p_req_write,p_req_is_fetch,output logic [31:0] p_req_addr,p_req_wdata,output logic [3:0] p_req_wstrb,input logic p_req_ready,
 input logic p_rsp_valid,p_rsp_error,input logic [31:0] p_rsp_rdata,output logic p_rsp_ready,
 output logic stop_new,input logic if_drained,
 output logic [1:0] invalidate_valid,input logic [1:0] invalidate_ready,invalidate_done,initialized,
 input logic [1:0][31:0] hit_count,miss_count,bypass_count,
 output logic [31:0] maintenance_count
);
 typedef enum logic [2:0]{IDLE,DDR_WAIT,PERIPH_WAIT,DRAIN,INVALIDATE,WAIT_DONE,LOCAL_RSP} state_t;
 state_t state;logic [31:0] data_q;logic error_q,to_ddr,to_control;logic [1:0] done_seen;
 assign to_ddr={1'b0,req_addr}>={1'b0,DDR_BASE}&&{1'b0,req_addr}<{1'b0,DDR_BASE}+DDR_BYTES;
 assign to_control=req_addr[31:5]==27'h1800008;
 assign req_ready=!rst&&state==IDLE&&(to_control?1'b1:to_ddr?d_req_ready:p_req_ready);
 assign d_req_valid=!rst&&state==IDLE&&!to_control&&to_ddr&&req_valid;
 assign p_req_valid=!rst&&state==IDLE&&!to_control&&!to_ddr&&req_valid;
 assign d_req_write=req_write;assign d_req_fetch=req_is_fetch;assign d_req_addr=req_addr;assign d_req_wdata=req_wdata;assign d_req_wstrb=req_wstrb;
 assign p_req_write=req_write;assign p_req_is_fetch=req_is_fetch;assign p_req_addr=req_addr;assign p_req_wdata=req_wdata;assign p_req_wstrb=req_wstrb;
 assign rsp_valid=!rst&&(state==LOCAL_RSP||(state==DDR_WAIT&&d_rsp_valid)||(state==PERIPH_WAIT&&p_rsp_valid));
 assign rsp_error=state==DDR_WAIT?d_rsp_error:state==PERIPH_WAIT?p_rsp_error:error_q;
 assign rsp_rdata=state==DDR_WAIT?d_rsp_rdata:state==PERIPH_WAIT?p_rsp_rdata:data_q;
 assign d_rsp_ready=!rst&&state==DDR_WAIT&&rsp_ready;
 assign p_rsp_ready=!rst&&state==PERIPH_WAIT&&rsp_ready;
 assign stop_new=state==DRAIN||state==INVALIDATE||state==WAIT_DONE;
 assign invalidate_valid=(!rst&&state==INVALIDATE&&invalidate_ready==3)?2'b11:2'b00;
 always_ff @(posedge clk)begin
  if(rst)begin state<=IDLE;data_q<=0;error_q<=0;done_seen<=0;maintenance_count<=0;end
  else case(state)
   IDLE:if(req_valid&&req_ready)begin
    data_q<=0;error_q<=0;
    if(!to_control)state<=to_ddr?DDR_WAIT:PERIPH_WAIT;
    else begin
     state<=LOCAL_RSP;
     if(req_is_fetch||req_addr[1:0]!=0)error_q<=1;
     else if(req_write)begin
      if(req_addr[4:2]!=0||req_wdata!=1||req_wstrb!=15)error_q<=1;
      else state<=DRAIN;
     end else case(req_addr[4:2])
      0:data_q<={30'b0,initialized};
      1:data_q<=hit_count[0];2:data_q<=miss_count[0];
      3:data_q<=hit_count[1];4:data_q<=miss_count[1];
      5:data_q<=bypass_count[1];6:data_q<=maintenance_count;
      7:data_q<=bypass_count[0];
     endcase
    end
   end
   DDR_WAIT:if(d_rsp_valid&&rsp_ready)state<=IDLE;
   PERIPH_WAIT:if(p_rsp_valid&&rsp_ready)state<=IDLE;
   DRAIN:if(if_drained&&initialized==3&&invalidate_ready==3)state<=INVALIDATE;
   INVALIDATE:if(invalidate_ready==3)begin done_seen<=0;state<=WAIT_DONE;end
   WAIT_DONE:begin done_seen<=done_seen|invalidate_done;if((done_seen|invalidate_done)==3)begin maintenance_count<=maintenance_count+1'b1;state<=LOCAL_RSP;end end
   LOCAL_RSP:if(rsp_ready)state<=IDLE;
   default:begin state<=LOCAL_RSP;error_q<=1;end
  endcase
 end
endmodule
