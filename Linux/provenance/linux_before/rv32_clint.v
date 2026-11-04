// SPDX-License-Identifier: MIT
// Single-hart CLINT-compatible register layout; little-endian 32-bit accesses.
module rv32_clint #(parameter TICK_DIV=100)(
 input clk,reset,input req_valid,output req_ready,input req_write,
 input [15:0] req_addr,input [31:0] req_wdata,input [3:0] req_wstrb,
 output reg rsp_valid,input rsp_ready,output reg [31:0] rsp_rdata,output reg rsp_error,
 output [63:0] mtime,output irq_timer,output irq_software
);
 reg [63:0] time_reg,compare_reg; reg software_reg; reg [31:0] tick;
 assign mtime=time_reg; assign irq_timer=time_reg>=compare_reg;
 assign irq_software=software_reg; assign req_ready=!rsp_valid||rsp_ready;
 integer i;
 always @(posedge clk) begin
  if(reset)begin time_reg<=0;compare_reg<=64'hffffffffffffffff;software_reg<=0;tick<=0;rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;end
  else begin
   if(tick==TICK_DIV-1)begin tick<=0;time_reg<=time_reg+1'b1;end else tick<=tick+1'b1;
   if(rsp_valid&&rsp_ready)rsp_valid<=0;
   if(req_valid&&req_ready)begin
    rsp_valid<=1;rsp_error<=0;rsp_rdata<=0;
    case(req_addr)
     16'h0000:begin rsp_rdata<={31'd0,software_reg};if(req_write&&req_wstrb[0])software_reg<=req_wdata[0];end
     16'h4000:begin rsp_rdata<=compare_reg[31:0];if(req_write)for(i=0;i<4;i=i+1)if(req_wstrb[i])compare_reg[i*8+:8]<=req_wdata[i*8+:8];end
     16'h4004:begin rsp_rdata<=compare_reg[63:32];if(req_write)for(i=0;i<4;i=i+1)if(req_wstrb[i])compare_reg[32+i*8+:8]<=req_wdata[i*8+:8];end
     16'hbff8:begin rsp_rdata<=time_reg[31:0];if(req_write)for(i=0;i<4;i=i+1)if(req_wstrb[i])time_reg[i*8+:8]<=req_wdata[i*8+:8];end
     16'hbffc:begin rsp_rdata<=time_reg[63:32];if(req_write)for(i=0;i<4;i=i+1)if(req_wstrb[i])time_reg[32+i*8+:8]<=req_wdata[i*8+:8];end
     default:rsp_error<=1;
    endcase
   end
  end
 end
endmodule
