`timescale 1ns/1ps
module sv32_bridge_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,sfence=0,reservation_kill=0;
 reg [1:0] privilege_mode=1,mmu_mpp=0;reg [31:0] mmu_satp=32'h80080001;
 reg mmu_sum=0,mmu_mxr=0,mmu_mprv=0;
 reg c_i_valid=0;wire c_i_ready;reg [31:0] c_i_addr=0;
 wire c_i_rsp_valid;reg c_i_rsp_ready=1;wire [63:0] c_i_rsp_data;wire [1:0] c_i_rsp_error,c_i_rsp_pagefault;
 reg c_d_valid=0;wire c_d_ready;reg [31:0] c_d_addr=0,c_d_wdata=0;
 reg c_d_write=0;reg [3:0] c_d_wstrb=15;reg [1:0] c_d_size=2;reg c_d_atomic=0;reg [4:0] c_d_amo=0;
 wire c_d_rsp_valid;reg c_d_rsp_ready=1;wire [31:0] c_d_rsp_data;wire c_d_rsp_error,c_d_rsp_pagefault;
 wire p_i_valid;reg p_i_ready=1;wire [31:0] p_i_addr;reg p_i_rsp_valid=0;wire p_i_rsp_ready;reg [63:0] p_i_rsp_data=0;reg [1:0] p_i_rsp_error=0;
 wire p_d_valid;reg p_d_ready=1;wire [31:0] p_d_addr,p_d_wdata;wire p_d_write;wire [3:0] p_d_wstrb;wire [1:0] p_d_size;
 reg p_d_rsp_valid=0;wire p_d_rsp_ready;reg [31:0] p_d_rsp_data=0;reg p_d_rsp_error=0;
 wire busy,flush_busy;
 reg [31:0] cache[0:8191];
 integer itimer=0,dtimer=0,checks=0,dreads=0,ireads=0;reg [31:0] ia,da,dd;reg dw;reg [3:0] db;
 rv32_linux_memory_bridge dut(.*);
 always @(posedge clk)begin
 if(reset)begin itimer<=0;dtimer<=0;p_i_rsp_valid<=0;p_d_rsp_valid<=0;end
 else begin
 if(p_i_rsp_valid&&p_i_rsp_ready)p_i_rsp_valid<=0;
 if(p_d_rsp_valid&&p_d_rsp_ready)p_d_rsp_valid<=0;
 if(p_i_valid&&p_i_ready)begin if(itimer||p_i_rsp_valid)$fatal(1,"I overlap");ia<=p_i_addr;itimer<=3;ireads<=ireads+1;end
 if(p_d_valid&&p_d_ready&&dut.am_lock&&dut.selection!=3)$fatal(1,"walk entered atomic lock");
 if(p_d_valid&&p_d_ready)begin if(dtimer||p_d_rsp_valid)$fatal(1,"D overlap");da<=p_d_addr;dd<=p_d_wdata;dw<=p_d_write;db<=p_d_wstrb;dtimer<=4;dreads<=dreads+1;end
 if(itimer>1)itimer<=itimer-1;
 if(itimer==1)begin itimer<=0;p_i_rsp_valid<=1;
 p_i_rsp_error<=(ia>=32'h80000000&&ia<32'h80008000)?0:3;
 p_i_rsp_data<={32'hdeadbeef,cache[ia[14:2]]};end
 if(dtimer>1)dtimer<=dtimer-1;
 if(dtimer==1)begin dtimer<=0;p_d_rsp_valid<=1;p_d_rsp_error<=!(da>=32'h80000000&&da<32'h80008000);p_d_rsp_data<=cache[da[14:2]];
 if(dw)for(integer b=0;b<4;b=b+1)if(db[b])cache[da[14:2]][b*8+:8]<=dd[b*8+:8];
 end
 end end
 task tick;begin @(posedge clk);#1;end endtask
 task fence;begin @(negedge clk);sfence=1;tick();@(negedge clk);sfence=0;while(flush_busy)tick();end endtask
 task data(input [31:0] addr,input bit wr,input [31:0] value,input bit atomic_op,input [4:0] amo,input bit err,input bit pf,input [31:0] result);
 integer timeout;begin
 while(!c_d_ready)tick();@(negedge clk);c_d_valid=1;c_d_addr=addr;c_d_write=wr;c_d_wdata=value;c_d_atomic=atomic_op;c_d_amo=amo;c_d_rsp_ready=0;
 tick();@(negedge clk);c_d_valid=0;timeout=0;
 while(!c_d_rsp_valid&&timeout<300)begin tick();timeout++;end
 if(!c_d_rsp_valid)$fatal(1,"D timeout");
 if(c_d_rsp_error!==err||c_d_rsp_pagefault!==pf||(!err&&!pf&&c_d_rsp_data!==result))$fatal(1,"D addr%h err%b pf%b data%h expected%b%b %h",addr,c_d_rsp_error,c_d_rsp_pagefault,c_d_rsp_data,err,pf,result);
 repeat(2)begin tick();if(!c_d_rsp_valid)$fatal(1,"D held response vanished");end
 @(negedge clk);c_d_rsp_ready=1;tick();checks++;
 end endtask
 task instruction(input [31:0] addr,input [63:0] result,input [1:0] err,pf);
 integer timeout;begin
 while(!c_i_ready)tick();@(negedge clk);c_i_valid=1;c_i_addr=addr;c_i_rsp_ready=0;
 tick();@(negedge clk);c_i_valid=0;timeout=0;
 while(!c_i_rsp_valid&&timeout<300)begin tick();timeout++;end
 if(!c_i_rsp_valid)$fatal(1,"I timeout");
 if(c_i_rsp_error!==err||c_i_rsp_pagefault!==pf||c_i_rsp_data!==result)$fatal(1,"I addr%h got%b%b %h expected%b%b %h",addr,c_i_rsp_error,c_i_rsp_pagefault,c_i_rsp_data,err,pf,result);
 repeat(2)begin tick();if(!c_i_rsp_valid)$fatal(1,"I held response vanished");end
 @(negedge clk);c_i_rsp_ready=1;tick();checks++;
 end endtask
 integer n,old_reads;
 initial begin
 for(n=0;n<8192;n++)cache[n]=0;
 cache['h1400/4]=32'h20000801; // root VPN1=256 -> next table 80002000
 cache['h2000/4]=32'h20000ccf; // VPN0=0 -> PA80003000 RWXAD
 cache['h2004/4]=32'h200014cf; // VPN0=1 -> PA80005000, noncontiguous
 cache['h3000/4]=32'h12345678;cache['h3ffc/4]=32'h11223344;cache['h5000/4]=32'h55667788;cache['h5004/4]=32'habcdef00;
 repeat(3)tick();@(negedge clk);reset=0;
 data(32'h40000000,0,0,0,0,0,0,32'h12345678);
 instruction(32'h40000ffc,64'h5566778811223344,0,0);
 data(32'h40000000,1,32'h11111111,0,0,0,0,0);
 data(32'h40000000,0,0,1,2,0,0,32'h11111111); // LR
 data(32'h40000000,1,32'h22222222,1,3,0,0,0); // successful SC
 data(32'h40000000,1,32'h33333333,1,3,0,0,1); // failed SC
 data(32'h40000000,1,5,1,0,0,0,32'h22222222); // AMOADD
 data(32'h40000000,0,0,0,0,0,0,32'h22222227);
 fence();
 fork
 data(32'h40000000,1,1,1,0,0,0,32'h22222227);
 instruction(32'h40000ffc,64'h5566778811223344,0,0);
 join
 // Dirty page-table store through same physical Dcache, then fence, then observe it.
 privilege_mode=3;data(32'h80002000,1,32'h200014cf,0,0,0,0,0);privilege_mode=1;
 fence();data(32'h40000000,0,0,0,0,0,0,32'h55667788);
 // Page 1 invalid: retain word0, attach fault only to upper instruction.
 cache['h2000/4]=32'h20000ccf;cache['h2004/4]=0;fence();
 instruction(32'h40000ffc,64'h0000000011223344,0,2);
 data(32'h40001000,0,0,0,0,0,1,0);
 // Physical high bits must never be silently truncated.
 cache['h2000/4]=32'hc00000cf;fence();old_reads=dreads;
 data(32'h40000000,0,0,0,0,1,0,0);
 if(dreads!=old_reads+2)$fatal(1,"highPA caused physical access");
 // High PTW address must produce access fault without truncated physical transaction.
 mmu_satp=32'h80300001;fence();old_reads=dreads;data(32'h40000000,0,0,0,0,1,0,0);
 if(dreads!=old_reads)$fatal(1,"highPTW truncated");mmu_satp=32'h80080001;
 // Page-table MMIO and RAM-end addresses must never reach physical port.
 mmu_satp=32'h80010000;fence();old_reads=dreads;data(32'h40000000,0,0,0,0,1,0,0);
 if(dreads!=old_reads)$fatal(1,"PTW MMIO read performed");
 mmu_satp=32'h80084000;fence();old_reads=dreads;data(32'h40000000,0,0,0,0,1,0,0);
 if(dreads!=old_reads)$fatal(1,"PTW above RAM performed");mmu_satp=32'h80080001;
 // Valid root pointing to a nonleaf MMIO page must stop after root read.
 cache['h1400/4]=32'h04000001;fence();old_reads=dreads;data(32'h40000000,1,1,0,0,1,0,0);
 if(dreads!=old_reads+1)$fatal(1,"nonleaf MMIO read performed");
 instruction(32'h40000000,64'h0,3,0);
 cache['h1400/4]=32'h20000801;fence();
 // Atomic MMIO rejection before memory port.
 privilege_mode=3;old_reads=dreads;data(32'h10000000,0,0,1,2,1,0,0);
 if(dreads!=old_reads)$fatal(1,"atomic MMIO performed");privilege_mode=1;
 // SFENCE while accepted translation in flight drains response, blocks new requests.
 cache['h2000/4]=32'h20000ccf;fence();
 @(negedge clk);c_i_valid=1;c_i_addr=32'h40000ffc;c_i_rsp_ready=0;tick();@(negedge clk);c_i_valid=0;sfence=1;tick();@(negedge clk);sfence=0;
 while(!c_i_rsp_valid)begin if(c_i_ready||c_d_ready)$fatal(1,"request accepted during deferred flush");tick();end
 if(!flush_busy)$fatal(1,"flush cleared before outstanding response consumed");
 repeat(3)tick();@(negedge clk);c_i_rsp_ready=1;tick();while(flush_busy)tick();checks++;
 $display("SV32 BRIDGE PASS checks=%0d coherent_reads=%0d fetch_reads=%0d",checks,dreads,ireads);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
