module atomic_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1,kill=0,qv=0,qw=0,qa=1,rr=1;
 reg[31:0]addr=32'h80001000,data=0;reg[4:0]op=0;
 wire qr,rv,re,mv,mr,mw,mrr,lock;wire[31:0]rd,ma,md;wire[3:0]ms;wire[1:0]mz;
 reg mrv=0,merr=0;reg[31:0]mrd=0,word0=0;integer checks=0,writes=0;
 assign mr=!mrv;
 rv32_atomic_memory dut(.clk(clk),.reset(reset),.reservation_kill(kill),.req_valid(qv),.req_ready(qr),.req_addr(addr),.req_wdata(data),.req_write(qw),.req_wstrb(4'hf),.req_size(2'd2),.req_atomic(qa),.req_amo(op),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(rd),.rsp_error(re),.mem_valid(mv),.mem_ready(mr),.mem_addr(ma),.mem_wdata(md),.mem_write(mw),.mem_wstrb(ms),.mem_size(mz),.mem_rsp_valid(mrv),.mem_rsp_ready(mrr),.mem_rsp_data(mrd),.mem_rsp_error(merr),.lock(lock));
 always @(posedge clk)begin
 if(reset)mrv<=0;else begin
 if(mrv&&mrr)mrv<=0;
 if(mv&&mr)begin mrv<=1;mrd<=word0;if(mw&&!merr)begin word0<=md;writes<=writes+1;end end
 end end
 task x(input[4:0]a,input[31:0]d,input[31:0]expected,input err);
 integer timeout;begin
 @(negedge clk);op=a;data=d;qv=1;
 while(!qr)@(negedge clk);
 @(negedge clk);qv=0;timeout=0;
 while(!rv)begin @(negedge clk);timeout=timeout+1;if(timeout>30)$fatal(1,"timeout");end
 if(rd!==expected||re!==err)$fatal(1,"op%0d got%h err%b expected%h err%b",a,rd,re,expected,err);
 checks=checks+1;@(negedge clk);
 end endtask
 initial begin
 repeat(3)@(negedge clk);reset=0;word0=10;
 x(2,0,10,0);x(3,15,0,0);if(word0!=15)$fatal;
 x(3,22,1,0);if(word0!=15)$fatal;
 x(0,5,15,0);x(1,32'h80000000,20,0);
 x(16,1,32'h80000000,0);if(word0!=32'h80000000)$fatal;
 x(20,1,32'h80000000,0);if(word0!=1)$fatal;
 x(24,32'hffffffff,1,0);if(word0!=1)$fatal;
 x(28,32'hffffffff,1,0);if(word0!=32'hffffffff)$fatal;
 x(4,32'hff,32'hffffffff,0);x(12,32'hf0,32'hffffff00,0);x(8,3,0,0);
 x(2,0,3,0);@(negedge clk);kill=1;@(negedge clk);kill=0;x(3,20,1,0);
 x(2,0,3,0);qa=0;qw=1;x(0,9,0,0);qa=1;qw=0;x(3,30,1,0);
 merr=1;x(0,1,0,1);merr=0;
 addr=32'h80001002;x(0,1,0,1);addr=32'h80001000;x(31,1,0,1);
 $display("PASS atomic %0d checks writes=%0d",checks,writes);$finish;
 end
 initial begin #100000;$fatal(1,"global timeout");end
endmodule
