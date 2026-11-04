`timescale 1ns/1ps
module peripherals_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1;
 reg req_valid=0,req_write=0,rsp_ready=0;reg [31:0] req_addr=0,req_wdata=0;reg [3:0] req_wstrb=15;
 wire req_ready,rsp_valid,rsp_error;wire [31:0] rsp_rdata;
 reg ext_rx=1,loopback=0,vblank=0;wire tx;wire rx=loopback?tx:ext_rx;
 wire [31:0] fb_base;wire fb_enable;wire [63:0] mtime;wire it,is,im,iss;
 integer checks=0;reg [31:0] data;reg error;reg [63:0] t0;
 rv32_linux_peripherals #(.TIMER_DIV(4),.UART_DIV(8)) dut(
 .clk(clk),.reset(reset),.req_valid(req_valid),.req_ready(req_ready),.req_write(req_write),.req_addr(req_addr),.req_wdata(req_wdata),.req_wstrb(req_wstrb),
 .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_rdata(rsp_rdata),.rsp_error(rsp_error),.uart_rx(rx),.uart_tx(tx),.vblank(vblank),.fb_base(fb_base),.fb_enable(fb_enable),
 .mtime(mtime),.irq_timer(it),.irq_software(is),.irq_external_m(im),.irq_external_s(iss));
 task check(input bit condition,input [8*120-1:0] what);begin checks=checks+1;if(!condition)begin $display("FAIL %0s at%0t",what,$time);$fatal;end end endtask
 task bus(input bit wr,input [31:0] addr,input [31:0] value,input [3:0] strobe);reg [31:0] saved;reg saved_error;begin
  @(negedge clk);req_valid=1;req_write=wr;req_addr=addr;req_wdata=value;req_wstrb=strobe;rsp_ready=0;
  @(posedge clk);while(!req_ready)@(posedge clk);
  @(negedge clk);req_valid=0;
  while(!rsp_valid)@(negedge clk);
  saved=rsp_rdata;saved_error=rsp_error;
  repeat(3)begin @(negedge clk);check(rsp_valid&&rsp_rdata===saved&&rsp_error===saved_error,"response stable under backpressure");end
  data=saved;error=saved_error;rsp_ready=1;@(negedge clk);rsp_ready=0;
 end endtask
 task write(input [31:0] addr,input [31:0] value);begin bus(1,addr,value,15);check(!error,"valid write");end endtask
 task read(input [31:0] addr);begin bus(0,addr,0,15);check(!error,"valid read");end endtask
 task blank;begin @(negedge clk);vblank=1;@(negedge clk);vblank=0;end endtask
 task sendbyte(input [7:0] value,input bit stop);begin
  @(negedge clk);ext_rx=0;repeat(8)@(negedge clk);
  for(integer b=0;b<8;b=b+1)begin ext_rx=value[b];repeat(8)@(negedge clk);end
  ext_rx=stop;repeat(8)@(negedge clk);ext_rx=1;repeat(8)@(negedge clk);
 end endtask
 initial begin
  repeat(5)@(negedge clk);reset=0;
  check(!it&&!is&&!im&&!iss&&!fb_enable&&tx,"reset state");
  bus(0,32'hdead0000,0,15);check(error,"unknown MMIO rejected");
  bus(1,32'h02000001,1,15);check(error&&!is,"unaligned rejected without side effect");
  write(32'h02000000,1);check(is,"MSIP asserted");write(32'h02000000,0);check(!is,"MSIP cleared");
  write(32'h02004004,0);write(32'h02004000,0);check(it,"MTIP compare asserts");
  write(32'h02004004,32'hffffffff);check(!it,"MTIP compare clears");
  bus(1,32'h02004000,32'h12345678,4'b0101);check(!error,"timer strobes");read(32'h02004000);check(data==32'h00340078,"timer strobes preserve bytes");
  t0=mtime;repeat(16)@(negedge clk);check(mtime==t0+4,"timebase divider");
  write(32'h1000000c,1);loopback=1;write(32'h10000000,8'ha6);repeat(100)@(negedge clk);
  read(32'h10000004);check(data==8'ha6,"UART bit-level loopback");read(32'h10000004);check(data[31],"UART RX pops once despite rsp stall");loopback=0;
  sendbyte(8'h55,1);sendbyte(8'h33,1);read(32'h10000018);check(data[1],"UART overrun latched");read(32'h10000004);check(data[7:0]==8'h55,"UART retains unread data");
  write(32'h10000018,2);read(32'h10000018);check(!data[1],"UART overrun W1C");
  sendbyte(8'h11,0);read(32'h10000018);check(data[2],"UART framing error");write(32'h10000018,4);
  bus(1,32'h10000014,0,15);check(error,"zero baud divisor rejected");
  write(32'h0c000004,3);write(32'h0c002080,2);write(32'h0c201000,0);
  sendbyte(8'hbe,1);repeat(3)@(negedge clk);check(iss&&!im,"PLIC S routing");
  write(32'h0c201000,7);check(!iss,"PLIC threshold suppresses IRQ");
  read(32'h0c201004);check(data==1,"PLIC claim ignores threshold");
  read(32'h0c201004);check(data==0,"PLIC one claim only");
  write(32'h0c201000,0);write(32'h0c201004,1);repeat(3)@(negedge clk);check(iss,"level re-pends after complete");
  read(32'h0c201004);check(data==1,"second claim");read(32'h10000004);check(data[7:0]==8'hbe,"drain UART");write(32'h0c201004,1);repeat(3)@(negedge clk);check(!iss,"no IRQ after source cleared and complete");
  write(32'h10001000,32'h83f70800);write(32'h10001004,1);write(32'h10001008,1);check(!fb_enable,"display changes only at vblank");
  bus(1,32'h10001008,1,15);check(error,"pending framebuffer cannot overwrite");blank;check(fb_enable&&fb_base==32'h83f70800,"vblank atomic framebuffer commit");
  write(32'h10001000,32'h83ffffc0);bus(1,32'h10001008,1,15);check(error,"frame end beyond reservation rejected");
  write(32'h10001000,32'h83f00001);bus(1,32'h10001008,1,15);check(error,"unaligned framebuffer rejected");
  write(32'h10001004,0);write(32'h10001008,1);blank;check(!fb_enable,"safe disable");
  write(32'h10001018,1);read(32'h1000101c);check(data==1,"vblank pending");write(32'h1000101c,1);read(32'h1000101c);check(data==0,"vblank W1C");
  read(32'h10001020);check(data==640,"width");read(32'h10001024);check(data==360,"height");read(32'h10001028);check(data==1280,"stride");
  // Exhaustive byte framing in both directions through physical serial pins.
  loopback=1;
  for(integer value=0;value<256;value=value+1)begin
   write(32'h10000000,value);repeat(90)@(negedge clk);
   read(32'h10000004);check(data==value,"all256 UART bytes loopback");
  end
  loopback=0;
  // Reset discards an outstanding response and restores all peripheral state.
  @(negedge clk);req_valid=1;req_write=1;req_addr=32'h02000000;req_wdata=1;rsp_ready=0;
  @(negedge clk);req_valid=0;reset=1;repeat(2)@(negedge clk);reset=0;
  check(!rsp_valid&&!is&&!it&&!fb_enable,"reset discards outstanding response");
  $display("PASS peripherals checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
