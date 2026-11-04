`timescale 1ns/1ps
module peripherals_scanout_fault_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1;
 reg[31:0] base=32'h00002000;reg enable=1;wire vb,de,hs,vs;wire[15:0] pix;wire[11:0]x;wire[10:0]y;
 wire qv,rr;wire[31:0]qa;reg rv=0;reg[31:0]rd=0;wire[31:0]frames,uf,er,be;
 reg memstall=0,inflight=0;reg[31:0]held;integer checks=0,reads=0;reg allow_page0=1;
 rv32_framebuffer_scanout #(.REGION_BASE(32'h1000),.REGION_LIMIT(32'h2000),.H_ACTIVE(16),.H_FRONT(4),.H_SYNC(4),.H_BACK(8),.V_ACTIVE(8),.V_FRONT(1),.V_SYNC(1),.V_BACK(4))dut(
 .clk(clk),.reset(reset),.active_base(base),.active_enable(enable),.vblank(vb),.de(de),.hsync(hs),.vsync(vs),.pixel_rgb565(pix),.pixel_x(x),.pixel_y(y),
 .mem_req_valid(qv),.mem_req_ready(!inflight),.mem_req_addr(qa),.mem_rsp_valid(rv),.mem_rsp_ready(rr),.mem_rsp_data(rd),.mem_rsp_error(1'b0),.frame_count(frames),.underflow_rows(uf),.dma_errors(er),.bounds_errors(be));
 task check(input bit c,input[8*80-1:0]m);begin checks++;if(!c)begin $display("FAIL %0s f=%0d xy=%0d,%0d pix=%h",m,frames,x,y,pix);$fatal;end end endtask
 always @(posedge clk)begin
  if(reset)begin inflight<=0;rv<=0;end else begin
   if(qv&&!inflight)begin held<=qa;inflight<=1;reads<=reads+1;end
   if(inflight&&!rv&&!memstall)begin rv<=1;rd<=held<32'h1100 ? 32'h12341234:32'habcdabcd;end
   if(rv&&rr)begin rv<=0;inflight<=0;end
  end
 end
 always @(negedge clk)if(!reset&&de)begin
  if(!allow_page0)check(pix==0||pix==16'habcd,"stale page0 never displayed after new frame");
 end
 task frame;begin @(posedge vb);@(negedge clk);end endtask
 integer before_reads;
 initial begin
  repeat(5)@(negedge clk);reset=0;
  frame;check(be>=1&&reads==0,"out of bounds frame causes no reads");
  base=32'h1001;frame;check(be>=2&&reads==0,"unaligned frame causes no reads");
  base=32'h1000;memstall=1;
  wait(inflight);frame;frame;frame; // response held across >2 frames, tests no epoch-wrap bug
  base=32'h1100;frame;allow_page0=0;memstall=0;
  frame;frame;frame;
  check(reads>16,"recovers after stale response drain");
  wait(de&&x==4&&y==0);@(negedge clk);check(pix==16'habcd,"new page is scanned");
  enable=0;frame;frame;before_reads=reads;frame;check(reads==before_reads,"disabled scanner issues no read");
  check(pix==0,"disabled black");
  $display("PASS scanout fault checks=%0d reads=%0d bounds=%0d underflow=%0d",checks,reads,be,uf);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
