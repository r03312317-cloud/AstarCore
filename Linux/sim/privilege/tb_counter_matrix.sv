module tb_counter_matrix;
reg clk=0;always #5 clk=~clk;reg reset=1;
wire iq,ir;wire[31:0]ia;reg iv=0;reg[63:0]id=0;wire[1:0]ie=0,ipf=0;
wire dq,dr,dw,atomic;wire[4:0]atomic_op;wire[31:0]da,dd;wire[3:0]ds;wire[1:0]dz;wire dv=0,de=0,dp=0,irq=0;wire[31:0]dvalue=0;
wire[1:0]priv,rv;wire[31:0]satp,val0,val1,pc0,pc1;wire[4:0]rd0,rd1;wire sfence;
reg[31:0]mem[0:1023];integer cycles=0,checks=0,allowed=0,denied=0;reg done=0,expect_allowed=0;
integer csrnum=0,target_priv=0,cm=0,cs=0,form=0;reg[31:0]fault_insn=0,first_value=0;integer reads=0,trapreads=0;
rv32_ooo_core #(.RESET_VECTOR(32'h80000000),.ENABLE_TRACE(1)) dut(
.clk(clk),.reset(reset),.imem_request_valid(iq),.imem_request_ready(!iv),.imem_request_address(ia),
.imem_response_valid(iv),.imem_response_ready(ir),.imem_response_data(id),.imem_response_error(ie),.imem_response_page_fault(ipf),
.dmem_request_is_atomic(atomic),.dmem_request_atomic(atomic_op),.dmem_request_valid(dq),.dmem_request_ready(1'b1),.dmem_request_address(da),.dmem_request_write(dw),.dmem_request_size(dz),.dmem_request_wdata(dd),.dmem_request_wstrb(ds),
.dmem_response_valid(dv),.dmem_response_ready(dr),.dmem_response_rdata(dvalue),.dmem_response_error(de),.dmem_response_page_fault(dp),
.irq_software(1'b0),.irq_timer(irq),.irq_external(1'b0),.irq_supervisor_external(1'b0),.mtime(64'hfedcba9889abcdef),
.event_icache_refill(1'b0),.event_dcache_refill(1'b0),.event_dcache_writeback(1'b0),
.privilege_mode(priv),.mmu_satp(satp),.mmu_sfence(sfence),
.retire_valid(rv),.retire_pc0(pc0),.retire_pc1(pc1),.retire_destination0(rd0),.retire_destination1(rd1),.retire_value0(val0),.retire_value1(val1));

function[31:0]csr(input integer number,f,rd,src);csr=(number<<20)|(src<<15)|(f<<12)|(rd<<7)|32'h73;endfunction
function[31:0]addi(input integer rd,rs,value);addi=(value<<20)|(rs<<15)|(rd<<7)|32'h13;endfunction
function[31:0]lui(input integer rd,input[31:0]value);lui=(value&32'hfffff000)|(rd<<7)|32'h37;endfunction
always @(posedge clk)begin
 if(reset)begin iv<=0;cycles<=0;done<=0;reads=0;trapreads=0;end else begin
 cycles<=cycles+1;if(cycles>2000)$fatal(1,"timeout CSR%h priv%0d masks%0d/%0d form%0d",csrnum,target_priv,cm,cs,form);
 if(iv&&ir)iv<=0;
 if(iq&&!iv)begin iv<=1;id<={mem[((ia-32'h80000000)>>2)+1],mem[(ia-32'h80000000)>>2]};end
 if(rv[0])checkret(rd0,val0);if(rv[1])checkret(rd1,val1);
 end end
 task checkret(input[4:0]rd,input[31:0]v);begin
 if(rd==10||rd==11)begin
 if(!expect_allowed)$fatal(1,"Forbidden counter retired CSR%h priv%0d masks%0d/%0d form%0d",csrnum,target_priv,cm,cs,form);
 if(csrnum=='hc01&&v!==32'h89abcdef)$fatal(1,"time low incorrect");
 if(csrnum=='hc81&&v!==32'hfedcba98)$fatal(1,"time high incorrect");
 if(csrnum=='hc80&&v!==32'h13579bdf)$fatal(1,"cycle high alias incorrect");
 if(csrnum=='hc82&&v!==32'h2468ace0)$fatal(1,"instret high alias incorrect");
 if(rd==10)first_value=v;
 if((csrnum=='hc00||csrnum=='hc02)&&((rd==10&&v==0)||(rd==11&&v<=first_value)))$fatal(1,"cycle/instret not increasing");
 reads=reads+1;
 end
 if(rd==20)begin if(expect_allowed||v!=2)$fatal(1,"wrong trap cause/permission");trapreads=trapreads+1;end
 if(rd==21)begin if(v!=32'h80000100)$fatal(1,"wrong faultPC %h",v);trapreads=trapreads+1;end
 if(rd==22)begin if(v!=fault_insn)$fatal(1,"wrong mtval %h expected%h",v,fault_insn);trapreads=trapreads+1;end
 if(rd==31)begin
 if(expect_allowed)begin if(v!=1||reads!=2||trapreads!=0)$fatal(1,"allowed path incomplete");allowed=allowed+1;end
 else begin if(v!=2||reads!=0||trapreads!=3)$fatal(1,"denied path incomplete");denied=denied+1;end
 done<=1;checks=checks+1;
 end
 end endtask
 task run(input integer number,p,m,s,f,src);
 integer j;begin
 @(negedge clk);reset=1;csrnum=number;target_priv=p;cm=m;cs=s;form=f;
 expect_allowed=(p==3||((m&(1<<(number&3)))!=0&&(p==1||(s&(1<<(number&3)))!=0)))&&(f==2&&src==0);
 for(j=0;j<1024;j++)mem[j]=32'h6f;
 mem[0]=lui(1,32'h80000000);mem[1]=addi(1,1,768);mem[2]=csr('h305,1,0,1);
 mem[3]=addi(1,0,m);mem[4]=csr('h306,1,0,1);mem[5]=addi(1,0,s);mem[6]=csr('h106,1,0,1);
 mem[7]=lui(1,32'h80000000);mem[8]=addi(1,1,256);mem[9]=csr('h341,1,0,1);
 mem[10]=lui(1,p==3?32'h2000:p==1?32'h1000:0);mem[11]=addi(1,1,p==0?0:-2048);mem[12]=csr('h300,1,0,1);
 mem[13]=lui(1,32'h1357a000);mem[14]=addi(1,1,-1057);mem[15]=csr('hb80,1,0,1);
 mem[16]=lui(1,32'h2468b000);mem[17]=addi(1,1,-800);mem[18]=csr('hb82,1,0,1);
 mem[19]=addi(2,0,1);mem[20]=32'h30200073;
 fault_insn=csr(number,f,10,src);mem[64]=fault_insn;
 mem[65]=addi(2,2,1);mem[66]=addi(2,2,1);mem[67]=addi(2,2,1);mem[68]=addi(2,2,1);
 mem[69]=csr(number,2,11,0);mem[70]=addi(31,0,1);
 mem[192]=csr('h342,2,20,0);mem[193]=csr('h341,2,21,0);mem[194]=csr('h343,2,22,0);mem[195]=addi(31,0,2);
 repeat(4)@(negedge clk);reset=0;while(!done)@(negedge clk);
 end endtask
 integer a,p,m,s,f;integer aliases[0:5];integer modes[0:2];integer forms[0:5];
 initial begin
 aliases[0]='hc00;aliases[1]='hc80;aliases[2]='hc01;aliases[3]='hc81;aliases[4]='hc02;aliases[5]='hc82;
 modes[0]=3;modes[1]=1;modes[2]=0;forms[0]=1;forms[1]=2;forms[2]=3;forms[3]=5;forms[4]=6;forms[5]=7;
 for(a=0;a<6;a=a+1)for(p=0;p<3;p=p+1)for(m=0;m<8;m=m+1)for(s=0;s<8;s=s+1)run(aliases[a],modes[p],m,s,2,0);
 for(a=0;a<6;a=a+1)for(p=0;p<3;p=p+1)for(f=0;f<6;f=f+1)run(aliases[a],modes[p],7,7,forms[f],2);
 // CSRRW/CSRRWI source=0 still constitutes a forbidden write.
 for(a=0;a<6;a=a+1)for(p=0;p<3;p=p+1)begin run(aliases[a],modes[p],7,7,1,0);run(aliases[a],modes[p],7,7,5,0);end
 $display("COUNTER MATRIX PASS cases=%0d allowed=%0d denied=%0d",checks,allowed,denied);$finish;
 end
endmodule
