// Deterministic randomized single-writer scoreboard. No multi-master claim.
module atomic_random_tb;
 reg clk=0; always #5 clk=~clk;
 reg reset=1,kill=0,qv=0,qw=0,qa=1,rr=0;
 reg[31:0]addr=32'h80001000,data=0; reg[4:0]op=0;
 wire qr,rv,re,mv,mw,mrr,lock; wire[31:0]rd,ma,md;wire[3:0]ms;wire[1:0]mz;
 reg mr=0,mrv=0,merr=0;reg[31:0]mrd=0;
 reg[31:0]memory[0:3],model[0:3];reg reserved=0;integer rword=0;
 integer checks=0,reads=0,writes=0,delay_left=0,fail_phase=0,phase=0;
 reg pending=0;reg[31:0]seed=32'h521a09ec;integer idx;
 reg hold_req=0,hold_rsp=0;reg[70:0]saved_req;reg[32:0]saved_rsp;
 function[31:0]rand32;begin seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);rand32=seed;end endfunction
 function[31:0]calc(input[4:0]f,input[31:0]a,b);begin case(f)
 0:calc=a+b;1:calc=b;4:calc=a^b;8:calc=a|b;12:calc=a&b;
 16:calc=$signed(a)<$signed(b)?a:b;20:calc=$signed(a)>$signed(b)?a:b;
 24:calc=a<b?a:b;28:calc=a>b?a:b;default:calc=0;endcase end endfunction
 rv32_atomic_memory dut(.clk(clk),.reset(reset),.reservation_kill(kill),.req_valid(qv),.req_ready(qr),.req_addr(addr),.req_wdata(data),.req_write(qw),.req_wstrb(4'hf),.req_size(2'd2),.req_atomic(qa),.req_amo(op),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(rd),.rsp_error(re),.mem_valid(mv),.mem_ready(mr),.mem_addr(ma),.mem_wdata(md),.mem_write(mw),.mem_wstrb(ms),.mem_size(mz),.mem_rsp_valid(mrv),.mem_rsp_ready(mrr),.mem_rsp_data(mrd),.mem_rsp_error(merr),.lock(lock));
 // Slave supplies randomized request stalls and delayed responses; all signals
 // change at the falling edge, avoiding testbench/DUT sampling races.
 always @(negedge clk)begin
 if(reset)begin mr=0;mrv<=0;pending=0;end
 else begin
 mr=!pending&&!mrv&&((rand32()&3)!=0);
 if(pending&&!mrv)begin
 if(delay_left==0)begin mrv<=1;pending=0;end else delay_left=delay_left-1;
 end
 end end
 always @(posedge clk)begin
 if(reset)begin hold_req=0;hold_rsp=0;end else begin
 if(hold_req&&(!mv||{ma,md,mw,ms,mz}!==saved_req))$fatal(1,"request unstable under backpressure");
 if(hold_rsp&&(!rv||{re,rd}!==saved_rsp))$fatal(1,"response unstable under backpressure");
 hold_req=mv&&!mr;saved_req={ma,md,mw,ms,mz};
 hold_rsp=rv&&!rr;saved_rsp={re,rd};
 if(mv&&!lock)$fatal(1,"memory request without lock");
 if((pending||mrv)&&!lock)$fatal(1,"lock dropped before memory completion");
 if((pending||mrv||rv)&&qr)$fatal(1,"new owner admitted while outstanding");
 if(mrv&&mrr)mrv<=0;
 if(mv&&mr)begin
 if(pending||mrv)$fatal(1,"multiple physical owners");
 if(ma<32'h80001000||ma>32'h8000100c||ms!=15||mz!=2)$fatal(1,"metadata");
 idx=(ma-32'h80001000)>>2;phase=phase+1;merr=(phase==fail_phase);
 mrd=memory[idx];if(mw)begin writes=writes+1;if(!merr)memory[idx]=md;end else reads=reads+1;
 pending=1;delay_left=rand32()%9;
 end
 end end
 task x(input bit atom,input bit wr,input[4:0]f,input integer wordidx,input[31:0]operand,input integer faultphase);
 reg[31:0]expected;reg err,scok;integer timeout,k,stall,expected_phases;begin
 expected_phases=(!atom||f==2)?1:2;expected=0;err=0;scok=reserved&&(rword==wordidx);
 if(atom&&f==3)begin expected_phases=scok?1:0;reserved=0;expected=scok?0:1;if(scok)begin err=faultphase==1;if(!err)model[wordidx]=operand;end end
 else if(!atom&&wr)begin if(rword==wordidx)reserved=0;err=faultphase==1;if(!err)model[wordidx]=operand;end
 else begin
 err=faultphase==1;if(err)expected_phases=1;expected=err?0:model[wordidx];
 if(err)reserved=0;
 else if(atom&&f==2)begin reserved=1;rword=wordidx;end
 else if(atom)begin reserved=0;err=faultphase==2;if(!err)model[wordidx]=calc(f,model[wordidx],operand);end
 end
 @(negedge clk);qa=atom;qw=wr;op=f;addr=32'h80001000+wordidx*4;data=operand;fail_phase=faultphase;phase=0;qv=1;rr=0;
 while(!qr)@(negedge clk);
 @(negedge clk);qv=0;timeout=0;
 while(!rv)begin @(negedge clk);timeout=timeout+1;if(timeout>100)$fatal(1,"timeout");end
 stall=1+(rand32()%8);repeat(stall)@(negedge clk);
 if(rd!==expected||re!==err)$fatal(1,"check%0d op%0d fault%0d got%h/%b expected%h/%b",checks,f,faultphase,rd,re,expected,err);
 for(k=0;k<4;k=k+1)if(memory[k]!==model[k])$fatal(1,"memory mismatch check%0d word%0d",checks,k);
 if(phase!=expected_phases)$fatal(1,"unexpected physical transaction count op%0d got%0d expected%0d",f,phase,expected_phases);
 checks=checks+1;rr=1;@(negedge clk);rr=0;
 end endtask
 task invalidate;begin @(negedge clk);kill=1;reserved=0;@(negedge clk);kill=0;end endtask
 integer i,j,n,sel;reg[4:0]ops[0:8];reg[31:0]extremes[0:5];reg[31:0]v;
 initial begin
 ops[0]=0;ops[1]=1;ops[2]=4;ops[3]=8;ops[4]=12;ops[5]=16;ops[6]=20;ops[7]=24;ops[8]=28;
 extremes[0]=0;extremes[1]=1;extremes[2]=32'hffffffff;extremes[3]=32'h80000000;extremes[4]=32'h7fffffff;extremes[5]=32'h80000001;
 for(i=0;i<4;i=i+1)begin memory[i]=0;model[i]=0;end
 repeat(3)@(negedge clk);reset=0;
 for(i=0;i<9;i=i+1)for(j=0;j<6;j=j+1)for(n=0;n<6;n=n+1)begin
 x(0,1,0,0,extremes[j],0);x(1,1,ops[i],0,extremes[n],0);end
 // Explicit reservation invalidation and error coverage, including AMO write B.
 x(1,0,2,0,0,0);x(0,1,0,0,123,0);x(1,1,3,0,456,0);
 x(1,0,2,0,0,0);invalidate();x(1,1,3,0,456,0);
 x(1,0,2,0,0,0);x(1,0,2,1,0,1);x(1,1,3,0,456,0);
 x(1,0,2,0,0,0);x(1,1,3,0,456,1);x(1,1,3,0,456,0);
 for(i=0;i<9;i=i+1)begin x(1,1,ops[i],0,rand32(),1);x(1,1,ops[i],0,rand32(),2);end
 for(i=0;i<2000;i=i+1)begin
 sel=rand32()%14;n=rand32()%4;v=rand32();
 if(sel<9)x(1,1,ops[sel],n,v,(rand32()%17)==0?2:0);
 else if(sel==9)x(1,0,2,n,0,(rand32()%13)==0?1:0);
 else if(sel==10)x(1,1,3,n,v,0);
 else if(sel==11)x(0,1,0,n,v,0);
 else if(sel==12)x(0,0,0,n,0,0);else invalidate();
 end
 $display("PASS atomic randomized checks=%0d reads=%0d writes=%0d seed=%h",checks,reads,writes,seed);$finish;
 end
 initial begin #10000000;$fatal(1,"global timeout");end
endmodule
