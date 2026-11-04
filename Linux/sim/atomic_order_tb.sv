module atomic_order_tb;
reg clk=0;always #5 clk=~clk;reg reset=1;
wire iq,ir;wire[31:0]ia;reg iv=0;reg[63:0]id=0;wire[1:0]ie=0,ipf=0;
wire dq,dr,dw,atomic,dv,de,dready;wire[4:0]atomic_op;wire[31:0]da,dd,dvalue;wire[3:0]ds;wire[1:0]dz;wire dp=0,irq=0;
wire[1:0]priv,rv;wire[31:0]satp,val0,val1,pc0,pc1;wire[4:0]rd0,rd1;wire sfence;
reg[31:0]mem[0:1023];
wire mv,mw,mready,mrr,lock;wire[31:0]ma,md;wire[3:0]ms;wire[1:0]mz;
reg mrv=0;reg[31:0]mrd=0,word0=0;integer cycles=0,transactions=0,latency=0;reg pending=0;
assign mready=!pending&&!mrv&&(cycles%5==0);
rv32_ooo_core #(.RESET_VECTOR(32'h80000000),.ENABLE_TRACE(1)) dut(
.clk(clk),.reset(reset),.imem_request_valid(iq),.imem_request_ready(!iv),.imem_request_address(ia),
.imem_response_valid(iv),.imem_response_ready(ir),.imem_response_data(id),.imem_response_error(ie),.imem_response_page_fault(ipf),
.dmem_request_is_atomic(atomic),.dmem_request_atomic(atomic_op),.dmem_request_valid(dq),.dmem_request_ready(dready),.dmem_request_address(da),.dmem_request_write(dw),.dmem_request_size(dz),.dmem_request_wdata(dd),.dmem_request_wstrb(ds),
.dmem_response_valid(dv),.dmem_response_ready(dr),.dmem_response_rdata(dvalue),.dmem_response_error(de),.dmem_response_page_fault(dp),
.irq_software(1'b0),.irq_timer(irq),.irq_external(1'b0),.irq_supervisor_external(1'b0),.mtime(64'h123456789),
.event_icache_refill(1'b0),.event_dcache_refill(1'b0),.event_dcache_writeback(1'b0),
.privilege_mode(priv),.mmu_satp(satp),.mmu_sfence(sfence),
.retire_valid(rv),.retire_pc0(pc0),.retire_pc1(pc1),.retire_destination0(rd0),.retire_destination1(rd1),.retire_value0(val0),.retire_value1(val1));
rv32_atomic_memory atomic_unit(.clk(clk),.reset(reset),.reservation_kill(1'b0),.req_valid(dq),.req_ready(dready),.req_addr(da),.req_wdata(dd),.req_write(dw),.req_wstrb(ds),.req_size(dz),.req_atomic(atomic),.req_amo(atomic_op),.rsp_valid(dv),.rsp_ready(dr),.rsp_data(dvalue),.rsp_error(de),.mem_valid(mv),.mem_ready(mready),.mem_addr(ma),.mem_wdata(md),.mem_write(mw),.mem_wstrb(ms),.mem_size(mz),.mem_rsp_valid(mrv),.mem_rsp_ready(mrr),.mem_rsp_data(mrd),.mem_rsp_error(1'b0),.lock(lock));
function[31:0]amo(input[4:0]op,input[1:0]aqrl,input integer rd,rs2);amo=(op<<27)|(aqrl<<25)|(rs2<<20)|(1<<15)|(2<<12)|(rd<<7)|32'h2f;endfunction
integer i;integer retired=0;
task checkret(input[4:0]rd,input[31:0]v);begin
 case(rd)
 3:begin if(v!=10)$fatal(1,"AMO old before prior store");retired=retired+1;end
 4:begin if(v!=15)$fatal(1,"load bypassed AMO.aqrl");retired=retired+1;end
 5:begin if(v!=15)$fatal(1,"LR.aq returned wrong value");retired=retired+1;end
 6:begin if(v!=0)$fatal(1,"SC.rl failed");retired=retired+1;end
 7:begin if(v!=5)$fatal(1,"load bypassed SC.rl");retired=retired+1;end
 8:begin
 if(retired!=5||transactions!=7||word0!=5)$fatal(1,"missing ordered operations");
 $display("PASS actual core atomic aqrl ordering retire_checks=%0d physical_transactions=%0d",retired,transactions);$finish;
 end
 endcase end endtask
always @(posedge clk)begin
 if(reset)begin iv<=0;mrv<=0;pending<=0;cycles<=0;end else begin
 cycles<=cycles+1;
 if(iv&&ir)iv<=0;
 if(iq&&!iv)begin iv<=1;id<={mem[((ia-32'h80000000)>>2)+1],mem[(ia-32'h80000000)>>2]};end
 if(mrv&&mrr)mrv<=0;
 if(pending)begin if(latency==0)begin pending<=0;mrv<=1;end else latency<=latency-1;end
 if(mv&&mready)begin
 if(ma!=32'h80001000||ms!=15||mz!=2||!lock)$fatal(1,"physical metadata/lock");
 // Store, AMO read/write, load, LR, SC, load: exactly this order.
 if(mw!==(transactions==0||transactions==2||transactions==5))$fatal(1,"memory order index%0d",transactions);
 transactions<=transactions+1;mrd<=word0;if(mw)word0<=md;pending<=1;latency<=11;
 end
 if(rv[0])checkret(rd0,val0);if(rv[1])checkret(rd1,val1);
 if(cycles>5000)$fatal(1,"timeout");
 end end
initial begin
 for(i=0;i<1024;i=i+1)mem[i]=32'h13;
 mem[0]=32'h800010b7; // lui x1,0x80001
 mem[1]=32'h00a00113; // addi x2,0,10
 mem[2]=32'h0020a023; // sw x2,0(x1)
 mem[3]=32'h00500113; // addi x2,0,5
 mem[4]=amo(0,3,3,2); // amoadd.w.aqrl x3,x2,(x1)
 mem[5]=32'h0000a203; // lw x4,0(x1)
 mem[6]=amo(2,2,5,0); // lr.w.aq x5,(x1)
 mem[7]=amo(3,1,6,2); // sc.w.rl x6,x2,(x1)
 mem[8]=32'h0000a383; // lw x7,0(x1)
 mem[9]=32'h00100413; // success marker
 mem[10]=32'h0000006f;
 repeat(4)@(negedge clk);reset=0;
end
endmodule
