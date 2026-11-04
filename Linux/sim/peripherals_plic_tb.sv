`timescale 1ns/1ps
module peripherals_plic_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1;reg [3:0] sources=0;
 reg qv=0,qw=0,rr=1;wire qr,rv,re,im,is;reg [21:0] qa=0;reg [31:0] qd=0;reg [3:0] st=15;wire[31:0] rd;
 integer checks=0;reg[31:0] data;
 rv32_plic dut(.clk(clk),.reset(reset),.sources(sources),.req_valid(qv),.req_ready(qr),.req_write(qw),.req_addr(qa),.req_wdata(qd),.req_wstrb(st),.rsp_valid(rv),.rsp_ready(rr),.rsp_rdata(rd),.rsp_error(re),.irq_m(im),.irq_s(is));
 task check(input bit c,input[8*80-1:0]s);begin checks++;if(!c)begin $display("FAIL %0s",s);$fatal;end end endtask
 task bus(input bit w,input[21:0]a,input[31:0]d);begin
  @(negedge clk);qv=1;qw=w;qa=a;qd=d;@(posedge clk);while(!qr)@(posedge clk);@(negedge clk);qv=0;
  while(!rv)@(negedge clk);data=rd;check(!re,"bus");@(negedge clk);
 end endtask
 initial begin
  repeat(4)@(negedge clk);reset=0;
  bus(1,4,2);bus(1,8,2);bus(1,12,7);bus(1,16,0);
  sources=15;repeat(4)@(negedge clk);check(!im&&!is,"disabled interrupts pending but no notification");
  bus(0,22'h1000,0);check(data==30,"all gateways pending");
  bus(1,22'h2000,30);bus(1,22'h2080,30);check(im&&is,"both context notification");
  bus(0,22'h200004,0);check(data==3,"highest priority source3");
  bus(0,22'h201004,0);check(data==1,"equal priority picks lowest ID and no double claim");
  bus(0,22'h200004,0);check(data==2,"remaining source2");
  bus(0,22'h201004,0);check(data==0,"priorityzero unclaimable");
  check(!im&&!is,"claimed all nonzero priorities");
  repeat(8)@(negedge clk);bus(0,22'h1000,0);check(data==16,"no repend before complete");
  sources=0;bus(1,22'h200004,3);bus(1,22'h201004,1);bus(1,22'h200004,2);
  repeat(3)@(negedge clk);check(!im&&!is,"completed low source remains quiet");
  bus(1,16,1);check(im&&is,"priority raise releases latched source");bus(0,22'h201004,0);check(data==4,"priorityzero event retained");bus(1,22'h201004,4);
  // Every source produces one claim and cannot re-pend until completion.
  for(integer iter=0;iter<64;iter++)begin
   bus(1,4,1);bus(1,8,2);bus(1,12,3);bus(1,16,4);
   sources=15;repeat(3)@(negedge clk);sources=0;
   for(integer id=4;id>=1;id--)begin
    bus(0,22'h200004,0);check(data==id,"descending priority claims");
    bus(1,22'h200004,id);
   end
   bus(0,22'h200004,0);check(data==0,"no stale claim after complete");
  end
  $display("PASS PLIC checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
