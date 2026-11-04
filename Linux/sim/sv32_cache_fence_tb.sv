`timescale 1ns/1ps
module sv32_cache_fence_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1;
 reg dvalid=0;wire dready,drvalid;reg[31:0]addr=32'h80000000,data=32'h12345678;
 reg fi=0;wire busy;wire rdreq;reg rv=0;wire rr;reg[63:0]rd=0;
 wire wr,last;wire[31:0]wa;wire[63:0]wd;reg bv=0,be=0;
 wire preq;wire[31:0]pa;integer rbeat=0,wbeat=0,bdelay=0,retries=0,accepted_io=0;reg reading=0,good_ack=0;
 reg[63:0]ram[0:7];
 rv32_memory_system #(.I_INDEX_BITS(2),.D_INDEX_BITS(2),.LINUX_PHYSICAL_MAP(1),.ENABLE_DATA_RAM_GUARD(1),.DATA_RAM_BASE(32'h80000000),.DATA_RAM_LIMIT(32'h83ffffff)) dut(
 .clk(clk),.reset(reset),.imem_request_valid(1'b0),.imem_request_ready(),.imem_request_address(32'h80000000),.imem_response_valid(),.imem_response_ready(1'b1),.imem_response_data(),.imem_response_error(),
 .dmem_request_valid(dvalid),.dmem_request_ready(dready),.dmem_request_address(addr),.dmem_request_write(1'b1),.dmem_request_wdata(data),.dmem_request_wstrb(4'hf),.dmem_request_size(2'd2),.dmem_response_valid(drvalid),.dmem_response_ready(1'b1),.dmem_response_rdata(),.dmem_response_error(),
 .fence_i(fi),.fence_d(1'b0),.maintenance_busy(busy),.event_icache_refill(),.event_dcache_refill(),.event_dcache_writeback(),
 .instr_req_o(),.instr_gnt_i(1'b1),.instr_addr_o(),.instr_io_o(),.instr_rvalid_i(1'b0),.instr_rready_o(),.instr_rdata_i(64'b0),.instr_err_i(1'b0),
 .data_rd_req_o(rdreq),.data_rd_gnt_i(1'b1),.data_rd_id_o(),.data_rd_addr_o(),.data_rd_rvalid_i(rv),.data_rd_rready_o(rr),.data_rd_rid_i(1'b0),.data_rd_rdata_i(rd),.data_rd_err_i(1'b0),
 .data_wr_req_o(wr),.data_wr_gnt_i(1'b1),.data_wr_last_o(last),.data_wr_addr_o(wa),.data_wr_data_o(wd),.data_wr_id_o(),.data_wr_bvalid_i(bv),.data_wr_berr_i(be),.data_wr_bid_i(1'b0),
 .periph_req_o(preq),.periph_gnt_i(1'b1),.periph_we_o(),.periph_addr_o(pa),.periph_wdata_o(),.periph_be_o(),.periph_size_o(),.periph_rvalid_i(preq),.periph_err_i(1'b0),.periph_rdata_i(32'b0));
 always @(negedge clk)begin
 if(reset)begin rv=0;reading=0;bv=0;bdelay=0;end
 else begin
 bv=0;
 if(reading)begin
 if(rv&&rr)begin if(rbeat==7)begin rv=0;reading=0;end else rbeat=rbeat+1;end
 if(reading)begin rv=1;rd=ram[rbeat];end
 end
 if(rdreq&&!reading)begin reading=1;rbeat=0;rv=1;rd=ram[0];end
 if(bdelay>0)begin bdelay=bdelay-1;if(bdelay==0)begin bv=1;be=retries==1;if(!be)good_ack=1;end end
 end end
 always @(posedge clk)if(!reset)begin
 if(wr)begin
 if(wa!=32'h80000000)$fatal(1,"wrong line base");
 if(last!=(wbeat==7))$fatal(1,"bad writeback final");
 ram[wbeat]<=wd;
 if(last)begin wbeat<=0;bdelay<=5;retries<=retries+1;end else wbeat<=wbeat+1;
 end
 if(preq)begin
 if(!good_ack||busy)$fatal(1,"MMIO side effect before completed clean");
 if(ram[0][31:0]!=32'h12345678)$fatal(1,"clean lost store data");accepted_io<=accepted_io+1;
 end
 if(bv&&be && !dut.data_dirty[0])$fatal(1,"dirty line dropped after B error");
 end
 task tick;begin @(posedge clk);#1;end endtask
 integer k;
 initial begin
 for(k=0;k<8;k++)ram[k]=0;
 repeat(3)tick();@(negedge clk);reset=0;@(negedge clk);dvalid=1;
 while(!dready)tick();tick();@(negedge clk);dvalid=0;
 while(!drvalid)tick();tick();
 @(negedge clk);fi=1;tick();@(negedge clk);fi=0;addr=32'h10000000;data=32'h41;dvalid=1;
 while(!dready)tick();tick();@(negedge clk);dvalid=0;
 while(!drvalid)tick();tick();
 if(retries!=2||accepted_io!=1||busy)$fatal(1,"retry/retirement failed %0d %0d",retries,accepted_io);
 $display("CACHE FENCE PASS writeback_attempts=%0d mmio_after_success=%0d",retries,accepted_io);$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
