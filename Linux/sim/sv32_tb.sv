`timescale 1ns/1ps
module sv32_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,flush=0,req_valid=0,rsp_ready=1;
 wire req_ready,rsp_valid,rsp_fault,busy;
 reg [31:0] req_vaddr=0,req_satp=32'h80000001;
 reg [1:0] req_access=1,req_priv=1,req_mpp=0;
 reg req_mprv=0,req_sum=0,req_mxr=0;
 wire [33:0] rsp_paddr,ptw_req_addr;
 wire [4:0] rsp_cause;
 wire [31:0] rsp_tval;
 wire ptw_req_valid,ptw_rsp_ready;
 reg ptw_req_ready=1,ptw_rsp_valid=0,ptw_rsp_error=0;
 reg [31:0] ptw_rsp_data=0;
 reg [31:0] root_pte=32'h00000801,leaf_pte=32'h200000cf;
 reg error_root=0,error_leaf=0;
 integer countdown=0,delay_cycles=2,reads=0,checks=0;
 reg [33:0] saved_addr;
 rv32_sv32_mmu dut(.*);
 always @(posedge clk) begin
 if(reset)begin countdown<=0;ptw_rsp_valid<=0;reads<=0;end
 else begin
 if(ptw_rsp_valid&&ptw_rsp_ready)ptw_rsp_valid<=0;
 if(ptw_req_valid&&ptw_req_ready)begin
 if(countdown!=0 || ptw_rsp_valid)$fatal(1,"PTW overlapping reads");
 saved_addr<=ptw_req_addr;countdown<=delay_cycles;reads<=reads+1;
 end
 if(countdown>1)countdown<=countdown-1;
 if(countdown==1)begin
 countdown<=0;ptw_rsp_valid<=1;
 if(saved_addr[33:12]==22'h1)begin ptw_rsp_data<=root_pte;ptw_rsp_error<=error_root;end
 else if(saved_addr[33:12]==22'h2)begin ptw_rsp_data<=leaf_pte;ptw_rsp_error<=error_leaf;end
 else begin ptw_rsp_data<=0;ptw_rsp_error<=1;end
 end
 end end
 task tick;begin @(posedge clk);#1;end endtask
 task clear_tlb;begin @(negedge clk);flush=1;tick();@(negedge clk);flush=0;while(busy)tick();end endtask
 task translate(input [31:0] va,input bit expected_fault,input [4:0] expected_cause,input [33:0] pa);
 integer timeout;reg [33:0] saved_pa;reg [4:0] saved_cause;reg saved_fault;
 begin
 while(!req_ready)tick();@(negedge clk);req_vaddr=va;req_valid=1;rsp_ready=0;
 tick();@(negedge clk);req_valid=0;
 timeout=0;while(!rsp_valid && timeout<100)begin tick();timeout=timeout+1;end
 if(!rsp_valid)$fatal(1,"translation timeout");
 if(rsp_fault!==expected_fault || rsp_cause!==expected_cause || rsp_tval!==va || (!expected_fault&&rsp_paddr!==pa))
 $fatal(1,"va=%h access=%d priv=%d pte=%h: got fault%0d cause%0d pa%h expected %0d %0d %h",va,req_access,req_priv,leaf_pte,rsp_fault,rsp_cause,rsp_paddr,expected_fault,expected_cause,pa);
 saved_pa=rsp_paddr;saved_fault=rsp_fault;saved_cause=rsp_cause;
 repeat(3)begin tick();if(!rsp_valid||rsp_paddr!==saved_pa||rsp_fault!==saved_fault||rsp_cause!==saved_cause)$fatal(1,"unstable backpressure response");end
 @(negedge clk);rsp_ready=1;tick();checks=checks+1;
 end endtask
 integer before_reads,p,a,u,s,m,r,w,x,ad;
 reg allowed;
 initial begin
 repeat(3)tick();@(negedge clk);reset=0;
 // Bare and machine bypass; MPRV applies to data but never instruction fetch.
 req_satp=0;translate(32'hffffffff,0,0,34'h0ffffffff);
 req_satp=32'h80000001;req_priv=3;translate(32'hffffffff,0,0,34'h0ffffffff);
 req_mprv=1;req_mpp=1;req_access=0;translate(32'hffffffff,0,0,34'h0ffffffff);
 req_access=1;translate(32'h40000123,0,0,34'h080000123);
 req_mprv=0;req_priv=1;
 // Hit avoids PTW, offset must not be cached.
 before_reads=reads;translate(32'h40000456,0,0,34'h080000456);
 if(reads!=before_reads)$fatal(1,"TLB miss on same page");
 // Different ASID forces walk; full sfence invalidates all.
 req_satp=32'h80400001;translate(32'h40000789,0,0,34'h080000789);
 if(reads!=before_reads+2)$fatal(1,"ASID not matched");
 clear_tlb();root_pte=32'h00000821; // inherited global
 translate(32'h40000000,0,0,34'h080000000);before_reads=reads;
 req_satp=32'h80800001;translate(32'h40000020,0,0,34'h080000020);
 if(reads!=before_reads)$fatal(1,"global mapping not reused");
 // Superpage uses VPN0, rejects unaligned PPN0.
 clear_tlb();root_pte=32'h240000cf;
 translate(32'h40345123,0,0,34'h090345123);
 root_pte=32'h240004cf;clear_tlb();translate(32'h40345123,1,13,0);
 // Full 34-bit PA must survive, integrator must reject unsupported PA, not truncate.
 root_pte=32'hc00000cf;clear_tlb();translate(32'h40000100,0,0,34'h300000100);
 root_pte=32'h00000801;
 // PTE errors, invalid encodings, nonleaf reserved fields, exhausted level.
 leaf_pte=0;clear_tlb();translate(32'h40000000,1,13,0);
 leaf_pte=32'h200000c5;clear_tlb();translate(32'h40000000,1,13,0);
 leaf_pte=32'h00000c01;clear_tlb();translate(32'h40000000,1,13,0);
 root_pte=32'h00000811;clear_tlb();translate(32'h40000000,1,13,0);
 root_pte=32'h00000841;clear_tlb();translate(32'h40000000,1,13,0);
 root_pte=32'h00000881;clear_tlb();translate(32'h40000000,1,13,0);
 root_pte=32'h00000801;leaf_pte=32'h200000cf;
 error_root=1;clear_tlb();translate(32'h40000000,1,5,0);error_root=0;
 error_leaf=1;clear_tlb();req_access=0;translate(32'h40000000,1,1,0);req_access=2;translate(32'h40000000,1,7,0);error_leaf=0;
 // Exhaustive permissions: U/S, fetch/load/store, PTE RWX/U, SUM, MXR, A/D.
 for(p=0;p<2;p=p+1)for(a=0;a<3;a=a+1)for(u=0;u<2;u=u+1)
 for(s=0;s<2;s=s+1)for(m=0;m<2;m=m+1)for(r=0;r<2;r=r+1)
 for(w=0;w<2;w=w+1)for(x=0;x<2;x=x+1)for(ad=0;ad<4;ad=ad+1)begin
 req_priv=p;req_access=a;req_sum=s;req_mxr=m;
 leaf_pte=32'h20000001 | (r<<1)|(w<<2)|(x<<3)|(u<<4)|((ad&1)<<6)|((ad>>1)<<7);
 allowed=(r||x)&&(!w||r)&&(ad&1)&&((a!=2)||((ad>>1)&1));
 if(p==0&&!u)allowed=0;
 if(p==1&&u&&(a==0||!s))allowed=0;
 if(a==0&&!x)allowed=0;
 if(a==1&&!(r||(m&&x)))allowed=0;
 if(a==2&&!w)allowed=0;
 clear_tlb();translate(32'h40000abc,!allowed,allowed?0:(a==0?12:(a==1?13:15)),34'h080000abc);
 end
 // Flush accepted PTW request must drain old answer; no stale refill/response.
 clear_tlb();req_priv=1;req_access=1;req_sum=0;req_mxr=0;leaf_pte=32'h200000cf;delay_cycles=10;
 @(negedge clk);req_vaddr=32'h40000000;req_valid=1;tick();@(negedge clk);req_valid=0;
 while(!ptw_req_valid)tick();tick();@(negedge clk);flush=1;tick();@(negedge clk);flush=0;
 while(busy)begin if(rsp_valid)$fatal(1,"stale response after flush");tick();end
 delay_cycles=2;leaf_pte=32'h280000cf;translate(32'h40000000,0,0,34'h0a0000000);
 $display("SV32 PASS checks=%0d PTW reads=%0d",checks,reads);$finish;
 end
 initial begin #2000000;$fatal(1,"global timeout");end
endmodule
