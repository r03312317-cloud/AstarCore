module tb_privilege;
reg clk=0; always #5 clk=~clk;
reg reset=1;
wire iq,ir;wire[31:0] ia; reg iv=0;reg[63:0] id=0;reg[1:0] ie=0,ipf=0;
wire dq,dr,dw;wire atomic;wire[4:0] atomic_op;reg dv=0;reg de=0,dp=0;reg[31:0] dvalue=0;integer memchecks=0;wire[31:0] da,dd;wire[3:0] ds;wire[1:0] dz;
wire[1:0] priv;wire[31:0] satp;wire sfence;
wire[1:0] rv;wire[4:0] rd0,rd1;wire[31:0] val0,val1,pc0,pc1;
reg[31:0] mem[0:1023];integer test=0,cycles=0,checks=0;reg passed=0;
reg[31:0] fault_addr=32'hffffffff;reg irq=0;
rv32_ooo_core #(.RESET_VECTOR(32'h80000000),.ENABLE_TRACE(1)) dut(
.clk(clk),.reset(reset),.imem_request_valid(iq),.imem_request_ready(!iv),.imem_request_address(ia),
.imem_response_valid(iv),.imem_response_ready(ir),.imem_response_data(id),.imem_response_error(ie),.imem_response_page_fault(ipf),
.dmem_request_is_atomic(atomic),.dmem_request_atomic(atomic_op),.dmem_request_valid(dq),.dmem_request_ready(1'b1),.dmem_request_address(da),.dmem_request_write(dw),.dmem_request_size(dz),.dmem_request_wdata(dd),.dmem_request_wstrb(ds),
.dmem_response_valid(dv),.dmem_response_ready(dr),.dmem_response_rdata(dvalue),.dmem_response_error(de),.dmem_response_page_fault(dp),
.irq_software(1'b0),.irq_timer(irq),.irq_external(1'b0),.irq_supervisor_external(1'b0),.mtime(64'h123456789),
.event_icache_refill(1'b0),.event_dcache_refill(1'b0),.event_dcache_writeback(1'b0),
.privilege_mode(priv),.mmu_satp(satp),.mmu_sfence(sfence),
.retire_valid(rv),.retire_pc0(pc0),.retire_pc1(pc1),.retire_destination0(rd0),.retire_destination1(rd1),.retire_value0(val0),.retire_value1(val1));
function[31:0] addi(input integer rd,rs,imm);addi=((imm&4095)<<20)|(rs<<15)|(rd<<7)|32'h13;endfunction
function[31:0] lui(input integer rd,input[31:0] val);lui=(val&32'hfffff000)|(rd<<7)|32'h37;endfunction
function[31:0] csrw(input integer csr,rs);csrw=(csr<<20)|(rs<<15)|32'h1073;endfunction
function[31:0] csrr(input integer rd,csr);csrr=(csr<<20)|(rd<<7)|32'h2073;endfunction
function[31:0] beq(input integer rs1,rs2,off);beq=(((off>>12)&1)<<31)|(((off>>5)&63)<<25)|(rs2<<20)|(rs1<<15)|(((off>>1)&15)<<8)|(((off>>11)&1)<<7)|32'h63;endfunction
integer i;
always @(posedge clk)begin
 if(!reset&&(dut.trap_enter||dut.return_from_trap||dut.satp_context_commit)&&iq&& !iv && dut.frontend.request_live)
  $fatal(1,"Live fetch accepted on old translation-context edge");
 if(reset)begin de<=0;dp<=0;dv<=0;iv<=0;ipf<=0;ie<=0;end
 else begin
  if(dv&&dr)dv<=0;
  if(dq)begin
   if(dz!=2||da!=32'h80000100)$fatal(1,"Memory metadata lost");
   if(test<19&&!atomic)$fatal(1,"Atomic flag lost");
   if(atomic&&atomic_op==2&&dw)$fatal(1,"LR must request load permission");
   if(atomic&&atomic_op!=2&&!dw)$fatal(1,"AMO/SC must request store permission");
   memchecks=memchecks+1;de<=test==19||test==21;dp<=test==20||test==22;dv<=1;dvalue<=atomic_op==3?0:32'h55;
  end
  if(iv&&ir)iv<=0;
  if(iq&&!iv)begin iv<=1;id<={mem[((ia-32'h80000000)>>2)+1],mem[(ia-32'h80000000)>>2]};
   ipf<={(ia+4)==fault_addr,ia==fault_addr};ie<=0;end
 end
end
always @(negedge clk)if(!reset)begin
 cycles=cycles+1;
 if(test>=19&&((rv[0]&&rd0==6)||(rv[1]&&rd1==6)))$fatal(1,"Younger instruction retired across memory fault");
 if(rv[0]&&rd0==31)begin if(val0==1)passed=1;else $fatal(1,"FAIL signature test=%0d value=%h pc=%h",test,val0,pc0);end
 if(rv[1]&&rd1==31)begin if(val1==1)passed=1;else $fatal(1,"FAIL signature test=%0d value=%h pc=%h",test,val1,pc1);end
 if(cycles>5000)$fatal(1,"Timeout test=%0d priv=%d pc=%h mcause=%h mepc=%h scause=%h sepc=%h",test,priv,dut.architectural_pc,dut.csr_cause,dut.csr_exception_pc,dut.csr_scause,dut.csr_sepc);
end
task clear_program;
 begin reset=1;repeat(4)@(negedge clk);for(i=0;i<1024;i=i+1)mem[i]=32'h0000006f;cycles=0;passed=0;fault_addr=32'hffffffff;irq=0;end
endtask
task run_test;
 begin reset=0;wait(passed);@(negedge clk);checks=checks+1;$display("PRIV PASS test=%0d cycles=%0d",test,cycles);end
endtask
// initialize M trap handler at 0x80000300, S handler at 0x80000200
 task setup;
 begin
 mem[0]=lui(1,32'h80000000);mem[1]=addi(1,1,768);mem[2]=csrw('h305,1);
 mem[3]=lui(1,32'h80000000);mem[4]=addi(1,1,512);mem[5]=csrw('h105,1);
 mem[6]=addi(1,0,260);mem[7]=csrw('h302,1); // delegate U ECALL and illegal
 mem[8]=lui(1,32'h80000000);mem[9]=addi(1,1,128);mem[10]=csrw('h341,1);
 mem[11]=lui(1,32'h1000);mem[12]=addi(1,1,-2048);mem[13]=csrw('h300,1);mem[14]=32'h30200073;
 mem[192]=addi(31,0,-1);
 end endtask
initial begin
 // MRET to S, SRET to U, delegated ECALL to S. Handler verifies origin and PC.
 test=1;clear_program;setup;
 mem[32]=addi(2,0,42);mem[33]=csrw('h140,2);mem[34]=csrr(3,'h140);
 mem[35]=beq(2,3,8);mem[36]=addi(31,0,-2);
 mem[37]=lui(1,32'h80000000);mem[38]=addi(1,1,256);mem[39]=csrw('h141,1);mem[40]=32'h10200073;
 mem[64]=32'h00000073;
 mem[128]=csrr(2,'h142);mem[129]=addi(3,0,8);mem[130]=beq(2,3,8);mem[131]=addi(31,0,-3);
 mem[132]=csrr(2,'h141);mem[133]=lui(3,32'h80000000);mem[134]=addi(3,3,256);mem[135]=beq(2,3,8);mem[136]=addi(31,0,-4);mem[137]=addi(31,0,1);
 run_test;
 // Supervisor illegal M CSR access must trap to S without writing M status.
 test=2;clear_program;setup;mem[32]=csrr(2,'h300);
 mem[128]=csrr(2,'h142);mem[129]=addi(3,0,2);mem[130]=beq(2,3,8);mem[131]=addi(31,0,-5);mem[132]=addi(31,0,1);run_test;
 // instruction page fault sideband, no virtual high-nibble restriction.
 test=3;clear_program;setup;mem[6]=lui(1,32'h1000);mem[7]=csrw('h302,1);fault_addr=32'h80000080;
 mem[128]=csrr(2,'h142);mem[129]=addi(3,0,12);mem[130]=beq(2,3,8);mem[131]=addi(31,0,-6);mem[132]=csrr(2,'h143);mem[133]=lui(3,32'h80000000);mem[134]=addi(3,3,128);mem[135]=beq(2,3,8);mem[136]=addi(31,0,-7);mem[137]=addi(31,0,1);run_test;

 // S counter read without mcounteren is illegal.
 test=4;clear_program;setup;mem[32]=csrr(2,'hc01);
 mem[128]=csrr(2,'h142);mem[129]=addi(3,0,2);mem[130]=beq(2,3,8);mem[131]=addi(31,0,-8);mem[132]=addi(31,0,1);run_test;
 // mcounteren permits S time, with exact external 64-bit timer low half.
 test=5;clear_program;setup;mem[14]=addi(1,0,7);mem[15]=csrw('h306,1);mem[16]=32'h30200073;
 mem[32]=csrr(2,'hc01);mem[33]=lui(3,32'h23456000);mem[34]=addi(3,3,1929);mem[35]=beq(2,3,8);mem[36]=addi(31,0,-9);mem[37]=addi(31,0,1);run_test;
 // TSR forces SRET in S to illegal instruction.
 test=6;clear_program;setup;mem[11]=lui(1,32'h00401000);mem[12]=addi(1,1,-2048);mem[32]=32'h10200073;
 mem[128]=csrr(2,'h142);mem[129]=addi(3,0,2);mem[130]=beq(2,3,8);mem[131]=addi(31,0,-10);mem[132]=addi(31,0,1);run_test;
 // TVM forces S SATP access and SFENCE to illegal; exercise SFENCE here.
 test=7;clear_program;setup;mem[11]=lui(1,32'h00101000);mem[12]=addi(1,1,-2048);mem[32]=32'h12000073;
 mem[128]=csrr(2,'h142);mem[129]=addi(3,0,2);mem[130]=beq(2,3,8);mem[131]=addi(31,0,-11);mem[132]=addi(31,0,1);run_test;
 // TW implementation traps S WFI immediately, permitted bounded timeout.
 test=8;clear_program;setup;mem[11]=lui(1,32'h00201000);mem[12]=addi(1,1,-2048);mem[32]=32'h10500073;
 mem[128]=csrr(2,'h142);mem[129]=addi(3,0,2);mem[130]=beq(2,3,8);mem[131]=addi(31,0,-12);mem[132]=addi(31,0,1);run_test;
 // Machine timer interrupt is enabled in S regardless of mstatus.MIE=0.
 test=9;clear_program;setup;mem[14]=addi(1,0,128);mem[15]=csrw('h304,1);mem[16]=32'h30200073;
 mem[192]=csrr(2,'h342);mem[193]=lui(3,32'h80000000);mem[194]=addi(3,3,7);mem[195]=beq(2,3,8);mem[196]=addi(31,0,-13);mem[197]=addi(31,0,1);irq=1;run_test;
 // S SATP stores full value; committed SFENCE flush pulse occurs once.
 test=10;clear_program;setup;mem[32]=lui(2,32'h81234000);mem[33]=addi(2,2,56);mem[34]=csrw('h180,2);mem[35]=32'h12000073;mem[36]=csrr(3,'h180);mem[37]=beq(2,3,8);mem[38]=addi(31,0,-14);mem[39]=addi(31,0,1);run_test;

 // Decode and owner metadata for LR/SC/AMO. Physical atomicity tested in adapter suite.
 test=11;clear_program;mem[0]=lui(1,32'h80000000);mem[1]=addi(1,1,256);mem[2]=32'h1000a12f;
 mem[3]=addi(3,0,85);mem[4]=beq(2,3,8);mem[5]=addi(31,0,-15);
 mem[6]=32'h1830a12f;mem[7]=beq(2,0,8);mem[8]=addi(31,0,-16);
 mem[9]=32'h0030a12f;mem[10]=beq(2,3,8);mem[11]=addi(31,0,-17);mem[12]=addi(31,0,1);run_test;
 if(memchecks!=3)$fatal(1,"atomic request count %0d",memchecks);

 // Delegated STIP must not interrupt M; vectored S trap adds 4*cause.
 test=12;clear_program;setup;
 mem[4]=addi(1,1,513); // stvec base0x200, vectored
 mem[11]=lui(1,32'h1000);mem[12]=addi(1,1,-2046); // MPP=S, SIE=1
 mem[14]=addi(1,0,32);mem[15]=csrw('h303,1);mem[16]=csrw('h304,1);mem[17]=csrw('h344,1);mem[18]=32'h30200073;
 mem[128]=addi(31,0,-18); // direct target must not be used
 mem[133]=csrr(2,'h142);mem[134]=lui(3,32'h80000000);mem[135]=addi(3,3,5);mem[136]=beq(2,3,8);mem[137]=addi(31,0,-19);mem[138]=addi(31,0,1);run_test;
 // MPP reserved encoding2 coerces to U, not an unimplemented H mode.
 test=13;clear_program;setup;mem[11]=lui(1,32'h1000);mem[12]=addi(1,1,0);
 mem[32]=32'h00000073;mem[128]=csrr(2,'h142);mem[129]=addi(3,0,8);mem[130]=beq(2,3,8);mem[131]=addi(31,0,-20);mem[132]=addi(31,0,1);run_test;

 // Reserved LR rs2 and AMO funct5 are illegal, with no external side effect.
 test=14;clear_program;setup;mem[6]=32'h1010a12f;
 mem[192]=csrr(2,'h342);mem[193]=addi(3,0,2);mem[194]=beq(2,3,8);mem[195]=addi(31,0,-21);mem[196]=addi(31,0,1);run_test;
 test=15;clear_program;setup;mem[6]=32'hf800a12f;
 mem[192]=csrr(2,'h342);mem[193]=addi(3,0,2);mem[194]=beq(2,3,8);mem[195]=addi(31,0,-22);mem[196]=addi(31,0,1);run_test;
 test=16;clear_program;setup;mem[6]=addi(1,1,1);mem[7]=32'h1000a12f;
 mem[192]=csrr(2,'h342);mem[193]=addi(3,0,4);mem[194]=beq(2,3,8);mem[195]=addi(31,0,-23);mem[196]=addi(31,0,1);run_test;
 test=17;clear_program;setup;mem[6]=addi(1,1,1);mem[7]=32'h0030a12f;
 mem[192]=csrr(2,'h342);mem[193]=addi(3,0,6);mem[194]=beq(2,3,8);mem[195]=addi(31,0,-24);mem[196]=addi(31,0,1);run_test;
 // Wrong-path atomic must never acquire external side-effect ownership.
 test=18;clear_program;mem[0]=lui(1,32'h80000000);mem[1]=addi(1,1,256);mem[2]=beq(0,0,12);mem[3]=32'h0030a12f;mem[4]=addi(31,0,-25);mem[5]=addi(31,0,1);run_test;
 if(memchecks!=3)$fatal(1,"faulted/wrong-path atomic escaped count=%0d",memchecks);

 // Bus error versus page fault preserve the precise load/store cause and VA.
 test=19;
 clear_program;setup;
 mem[6]=lui(1,32'h80000000);mem[7]=addi(1,1,256);
 mem[8]=test<21?32'h0000a103:32'h0020a023;mem[9]=addi(6,0,99);
 mem[192]=csrr(2,'h342);mem[193]=addi(3,0,test==19?5:(test==20?13:(test==21?7:15)));
 mem[194]=beq(2,3,8);mem[195]=addi(31,0,-26);
 mem[196]=csrr(2,'h343);mem[197]=beq(2,1,8);mem[198]=addi(31,0,-27);mem[199]=addi(31,0,1);run_test;
 test=20;
 clear_program;setup;
 mem[6]=lui(1,32'h80000000);mem[7]=addi(1,1,256);
 mem[8]=test<21?32'h0000a103:32'h0020a023;mem[9]=addi(6,0,99);
 mem[192]=csrr(2,'h342);mem[193]=addi(3,0,test==19?5:(test==20?13:(test==21?7:15)));
 mem[194]=beq(2,3,8);mem[195]=addi(31,0,-26);
 mem[196]=csrr(2,'h343);mem[197]=beq(2,1,8);mem[198]=addi(31,0,-27);mem[199]=addi(31,0,1);run_test;
 test=21;
 clear_program;setup;
 mem[6]=lui(1,32'h80000000);mem[7]=addi(1,1,256);
 mem[8]=test<21?32'h0000a103:32'h0020a023;mem[9]=addi(6,0,99);
 mem[192]=csrr(2,'h342);mem[193]=addi(3,0,test==19?5:(test==20?13:(test==21?7:15)));
 mem[194]=beq(2,3,8);mem[195]=addi(31,0,-26);
 mem[196]=csrr(2,'h343);mem[197]=beq(2,1,8);mem[198]=addi(31,0,-27);mem[199]=addi(31,0,1);run_test;
 test=22;
 clear_program;setup;
 mem[6]=lui(1,32'h80000000);mem[7]=addi(1,1,256);
 mem[8]=test<21?32'h0000a103:32'h0020a023;mem[9]=addi(6,0,99);
 mem[192]=csrr(2,'h342);mem[193]=addi(3,0,test==19?5:(test==20?13:(test==21?7:15)));
 mem[194]=beq(2,3,8);mem[195]=addi(31,0,-26);
 mem[196]=csrr(2,'h343);mem[197]=beq(2,1,8);mem[198]=addi(31,0,-27);mem[199]=addi(31,0,1);run_test;
 $display("PRIVILEGE PASS checks=%0d",checks);$finish;
end
endmodule
