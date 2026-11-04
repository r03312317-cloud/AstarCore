`timescale 1ns/1ps
module peripherals_scanout_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1;
 reg [31:0] base=32'h83f00000;reg enable=1;wire vb,de,hs,vs;wire[15:0] pixel;wire[11:0] x;wire[10:0] y;
 wire qv,qr,rr;wire[31:0] qa;reg rv=0,err=0;reg[31:0] rd=0;
 wire[31:0] frames,underflows,errors,bounds;
 integer cycles=0,delay_count=0,checks=0,reads=0,pixels=0;reg inflight=0;reg[31:0] held_addr;
 reg[31:0] hash=32'h811c9dc5,expected_hash=32'h811c9dc5;reg [15:0] expected_pixel;
 reg inject_error=0;reg[31:0] stable_addr;reg stalled=0;
 assign qr=!inflight&&!rv&&(cycles%5!=0);
 rv32_framebuffer_scanout dut(.clk(clk),.reset(reset),.active_base(base),.active_enable(enable),.vblank(vb),.de(de),.hsync(hs),.vsync(vs),.pixel_rgb565(pixel),.pixel_x(x),.pixel_y(y),.mem_req_valid(qv),.mem_req_ready(qr),.mem_req_addr(qa),.mem_rsp_valid(rv),.mem_rsp_ready(rr),.mem_rsp_data(rd),.mem_rsp_error(err),.frame_count(frames),.underflow_rows(underflows),.dma_errors(errors),.bounds_errors(bounds));
 function [15:0] pattern(input integer sx,input integer sy,input bit page);
 reg [15:0] c;begin
  case(sx/80)
   0:c=16'hffff;1:c=16'hffe0;2:c=16'h07ff;3:c=16'h07e0;
   4:c=16'hf81f;5:c=16'hf800;6:c=16'h001f;default:c=16'h0000;
  endcase
  // An 8x8 block glyph and rectangular patch exercise local/nonuniform updates.
  if(sx>=100&&sx<164&&sy>=40&&sy<104&&(((sx-100)/8==0)||((sx-100)/8==7)||((sy-40)/8==0)||((sy-40)/8==3)))c=16'h1234;
  if(sx>=300&&sx<420&&sy>=200&&sy<250)c={sx[4:0],sy[5:0],sx[4:0]};
  pattern=page?~c:c;
 end endfunction
 function [31:0] memory_word(input[31:0] a);integer off,sx,sy;reg page;begin
  page=a>=32'h83f70800;off=a-(page?32'h83f70800:32'h83f00000);sy=off/1280;sx=(off%1280)/2;
  memory_word={pattern(sx+1,sy,page),pattern(sx,sy,page)};
 end endfunction
 task check(input bit cond,input[8*80-1:0]msg);begin checks++;if(!cond)begin $display("FAIL %0s f=%0d xy=%0d,%0d pixel=%h expected=%h addr=%h",msg,frames,x,y,pixel,expected_pixel,qa);$fatal;end end endtask
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(reset)begin inflight<=0;rv<=0;err<=0;delay_count<=0;end else begin
   if(rv&&rr)begin rv<=0;inflight<=0;end
   if(qv&&qr)begin
    check(qa>=32'h83f00000&&qa<32'h83fe1000&&qa[1:0]==0,"bounded aligned read");
    held_addr<=qa;inflight<=1;delay_count<=1;reads<=reads+1;
   end
   if(inflight&&!rv)begin
    if(delay_count==0)begin rv<=1;rd<=memory_word(held_addr);err<=inject_error&&held_addr==32'h83f02300;end
    else delay_count<=delay_count-1;
   end
  end
 end
 always @(negedge clk)begin
  if(!reset)begin
   if(stalled)check(qv&&qa==stable_addr,"request stable under backpressure");
   stalled=qv&&!qr;stable_addr=qa;
   if(de)begin
    expected_pixel=pattern(x/2,y/2,frames==2);
    if(frames==3&&y/2==7)expected_pixel=0;
    check(pixel===expected_pixel,"exact RGB565 twice replicated");
    hash=(hash^{16'd0,pixel})*32'h01000193;
    expected_hash=(expected_hash^{16'd0,expected_pixel})*32'h01000193;
    pixels++;
   end
   if(vb&&frames>0)begin
    check(pixels==1280*720,"active pixel count");check(hash==expected_hash,"framehash");
    $display("FRAME %0d PASS hash=%08x reads_total=%0d underflow=%0d dma_errors=%0d",frames,hash,reads,underflows,errors);
    pixels=0;hash=32'h811c9dc5;expected_hash=32'h811c9dc5;
    if(frames==1)base=32'h83f70800;
    if(frames==2)begin base=32'h83f00000;inject_error=1;end
    if(frames==3)begin
     check(underflows==1&&errors==1,"one bad source row blackens both scanlines");
     $display("PASS scanout checks=%0d reads=%0d",checks,reads);$finish;
    end
   end
  end
 end
 initial begin repeat(5)@(negedge clk);reset=0;end
 initial begin #50000000;$fatal(1,"timeout");end
endmodule
