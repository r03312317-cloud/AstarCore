// SPDX-License-Identifier: MIT
// Four level-sensitive sources, two contexts (hart0 M/S). IDs 1..4, priority 0..7.
// Gateway latches one pending event, waits for completion, then re-arms.
module rv32_plic(
 input clk,reset,input [3:0] sources,input req_valid,output req_ready,input req_write,
 input [21:0] req_addr,input [31:0] req_wdata,input [3:0] req_wstrb,
 output reg rsp_valid,input rsp_ready,output reg [31:0] rsp_rdata,output reg rsp_error,
 output irq_m,irq_s
);
 reg [2:0] priority_reg[1:4];reg [3:0] pending,busy;
 reg [3:0] enable_m,enable_s;reg [2:0] threshold_m,threshold_s;
 reg [2:0] best_m,best_s,pri_m,pri_s;integer j;
 assign req_ready=!rsp_valid||rsp_ready;
 always @*begin
  best_m=0;best_s=0;pri_m=0;pri_s=0;
  for(integer k=1;k<=4;k=k+1)begin
   if(pending[k-1]&&enable_m[k-1]&&priority_reg[k]>pri_m)begin best_m=k[2:0];pri_m=priority_reg[k];end
   if(pending[k-1]&&enable_s[k-1]&&priority_reg[k]>pri_s)begin best_s=k[2:0];pri_s=priority_reg[k];end
  end
 end
 assign irq_m=(best_m!=0)&&(pri_m>threshold_m);
 assign irq_s=(best_s!=0)&&(pri_s>threshold_s);
 always @(posedge clk)begin
  if(reset)begin
   pending<=0;busy<=0;enable_m<=0;enable_s<=0;threshold_m<=0;threshold_s<=0;
   rsp_valid<=0;rsp_error<=0;rsp_rdata<=0;for(j=1;j<=4;j=j+1)priority_reg[j]<=0;
  end else begin
   for(j=0;j<4;j=j+1)if(sources[j]&&!busy[j])begin pending[j]<=1;busy[j]<=1;end
   if(rsp_valid&&rsp_ready)rsp_valid<=0;
   if(req_valid&&req_ready)begin
    rsp_valid<=1;rsp_rdata<=0;rsp_error<=0;
    if(req_addr>=4&&req_addr<=16&&req_addr[1:0]==0)begin
     rsp_rdata<={29'd0,priority_reg[req_addr[4:2]]};
     if(req_write&&req_wstrb[0])priority_reg[req_addr[4:2]]<=req_wdata[2:0];
    end else case(req_addr)
     22'h000000:rsp_rdata<=0;
     22'h001000:begin rsp_rdata<={27'd0,pending,1'b0};if(req_write)rsp_error<=1;end
     22'h002000:begin rsp_rdata<={27'd0,enable_m,1'b0};if(req_write&&req_wstrb[0])enable_m<=req_wdata[4:1];end
     22'h002080:begin rsp_rdata<={27'd0,enable_s,1'b0};if(req_write&&req_wstrb[0])enable_s<=req_wdata[4:1];end
     22'h200000:begin rsp_rdata<={29'd0,threshold_m};if(req_write&&req_wstrb[0])threshold_m<=req_wdata[2:0];end
     22'h201000:begin rsp_rdata<={29'd0,threshold_s};if(req_write&&req_wstrb[0])threshold_s<=req_wdata[2:0];end
     22'h200004:begin
      if(req_write)begin if(req_wstrb==4'hf&&req_wdata>=1&&req_wdata<=4&&enable_m[req_wdata-1])busy[req_wdata-1]<=0;end
      else begin rsp_rdata<={29'd0,best_m};if(best_m!=0)pending[best_m-1]<=0;end
     end
     22'h201004:begin
      if(req_write)begin if(req_wstrb==4'hf&&req_wdata>=1&&req_wdata<=4&&enable_s[req_wdata-1])busy[req_wdata-1]<=0;end
      else begin rsp_rdata<={29'd0,best_s};if(best_s!=0)pending[best_s-1]<=0;end
     end
     default:rsp_error<=1;
    endcase
   end
  end
 end
endmodule
