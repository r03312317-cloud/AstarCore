module tb_mip_seip;
reg clk=0;always #5 clk=~clk;reg reset=1,ext=1;
wire iq,ir;wire[31:0]ia;reg iv=0;reg[63:0]id=0;wire[1:0]ie=0,ipf=0;
wire dq,dr,dw,atomic;wire[4:0]atomic_op;wire[31:0]da,dd;wire[3:0]ds;wire[1:0]dz;wire dv=0,de=0,dp=0,irq=0;wire[31:0]dvalue=0;
wire[1:0]priv,rv;wire[31:0]satp,val0,val1,pc0,pc1;wire[4:0]rd0,rd1;wire sfence;
reg[31:0]mem[0:1023];integer cycles=0,test=0,checks=0;reg done=0;
reg[31:0]before_value,after_value;
rv32_ooo_core #(.RESET_VECTOR(32'h80000000),.ENABLE_TRACE(1)) dut(
.clk(clk),.reset(reset),.imem_request_valid(iq),.imem_request_ready(!iv),.imem_request_address(ia),
.imem_response_valid(iv),.imem_response_ready(ir),.imem_response_data(id),.imem_response_error(ie),.imem_response_page_fault(ipf),
.dmem_request_is_atomic(atomic),.dmem_request_atomic(atomic_op),.dmem_request_valid(dq),.dmem_request_ready(1'b1),.dmem_request_address(da),.dmem_request_write(dw),.dmem_request_size(dz),.dmem_request_wdata(dd),.dmem_request_wstrb(ds),
.dmem_response_valid(dv),.dmem_response_ready(dr),.dmem_response_rdata(dvalue),.dmem_response_error(de),.dmem_response_page_fault(dp),
.irq_software(1'b0),.irq_timer(irq),.irq_external(1'b0),.irq_supervisor_external(ext),.mtime(64'h123456789),
.event_icache_refill(1'b0),.event_dcache_refill(1'b0),.event_dcache_writeback(1'b0),
.privilege_mode(priv),.mmu_satp(satp),.mmu_sfence(sfence),
.retire_valid(rv),.retire_pc0(pc0),.retire_pc1(pc1),.retire_destination0(rd0),.retire_destination1(rd1),.retire_value0(val0),.retire_value1(val1));

function[31:0]csr(input integer f,rd,src);csr=(32'h344<<20)|(src<<15)|(f<<12)|(rd<<7)|32'h73;endfunction
function[31:0]addi(input integer rd,value);addi=(value<<20)|(rd<<7)|32'h13;endfunction
always @(posedge clk)begin
 if(reset)begin iv<=0;cycles<=0;done<=0;end else begin
 cycles<=cycles+1;if(cycles>2000)$fatal(1,"timeout");
 if(iv&&ir)iv<=0;
 if(iq&&!iv)begin iv<=1;id<={mem[((ia-32'h80000000)>>2)+1],mem[(ia-32'h80000000)>>2]};end
 if(rv[0])checkret(rd0,val0);if(rv[1])checkret(rd1,val1);
 end end
 task checkret(input[4:0]rd,input[31:0]v);begin
 if(rd==3)begin
 if(v!==before_value)$fatal(1,"case%0d CSR rd readback %h expected%h",test,v,before_value);
 ext<=0;
 end
 if(rd==4&&v!==after_value)$fatal(1,"case%0d GHOST SEIP / wrong software latch: mip after external low %h expected%h",test,v,after_value);
 if(rd==8)begin done<=1;checks=checks+1;$display("MIP SEIP PASS test=%0d",test);end
 end endtask
 task run(input integer sub,source,input[31:0]initial_pending,operand,expected);
 integer j;begin
 @(negedge clk);reset=1;ext=1;before_value=initial_pending|32'h200;after_value=expected;
 for(j=0;j<1024;j++)mem[j]=32'h13;
 mem[0]=addi(1,initial_pending);mem[1]=csr(1,0,1);
 mem[2]=addi(1,operand);mem[3]=csr(sub,3,source);
 mem[4]=csr(2,4,0);mem[5]=addi(8,1);mem[6]=32'h6f;
 repeat(4)@(negedge clk);reset=0;while(!done)@(negedge clk);
 end endtask
 initial begin
 test=1;run(2,1,0,32'h20,32'h20); // CSRRS STIP while external high must not latch SEIP
 test=2;run(3,1,32'h20,32'h20,0); // CSRRC STIP while external high
 test=3;run(6,2,0,0,2); // CSRRSI SSIP (immediate) while external high
 test=4;run(7,2,2,0,0); // CSRRCI SSIP (immediate)
 test=5;run(2,1,0,32'h200,32'h200); // explicit software SEIP set stays set
 test=6;run(3,1,32'h200,32'h200,0); // software SEIP clear independent of external
 test=7;run(1,1,32'h200,32'h20,32'h20); // CSRRW takes source directly
 test=8;run(2,0,0,0,0); // zero-source read-only doesn't write pending
 test=9;run(2,1,32'h200,32'h20,32'h220); // preserve previously set software SEIP
 test=10;run(3,1,32'h220,32'h20,32'h200);
 $display("MIP SEIP PASS checks=%0d",checks);$finish;
 end
endmodule
