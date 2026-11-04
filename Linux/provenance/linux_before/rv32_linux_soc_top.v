// Linux experimental SoC. External cache-line ports are NOT a DDR PHY.
// RAM bounds are simulation/integration parameters, not measured board capacity.
module rv32_linux_soc_top #(
 parameter [31:0] RESET_VECTOR=32'h80000000,
 parameter [31:0] RAM_BASE=32'h80000000,RAM_LIMIT=32'h84000000,
 parameter TIMER_DIV=100,UART_DIV=868
)(
 input clk,reset,input uart_rx,output uart_tx,input vblank,
 output [31:0] framebuffer_base,output framebuffer_enable,
 input reservation_kill,
 output instr_req_o,input instr_gnt_i,output [31:0]instr_addr_o,output instr_io_o,
 input instr_rvalid_i,output instr_rready_o,input[63:0]instr_rdata_i,input instr_err_i,
 output data_rd_req_o,input data_rd_gnt_i,output data_rd_id_o,output[31:0]data_rd_addr_o,
 input data_rd_rvalid_i,output data_rd_rready_o,input data_rd_rid_i,input[63:0]data_rd_rdata_i,input data_rd_err_i,
 output data_wr_req_o,input data_wr_gnt_i,output data_wr_last_o,output[31:0]data_wr_addr_o,
 output[63:0]data_wr_data_o,output data_wr_id_o,input data_wr_bvalid_i,data_wr_berr_i,data_wr_bid_i,
 output[1:0]retire_valid,output[31:0]retire_pc0,retire_pc1,retire_instruction0,retire_instruction1,
 output[4:0]retire_destination0,retire_destination1,output[31:0]retire_value0,retire_value1,
 output debug_trap,output[1:0]debug_privilege,output[31:0]debug_satp,
 output[31:0]debug_mepc,debug_mcause,debug_mtval,debug_sepc,debug_scause,debug_stval,debug_architectural_pc
);
 wire ci_v,ci_r,ci_rv,ci_rr;wire[31:0]ci_a;wire[63:0]ci_data;wire[1:0]ci_err,ci_pf;
 wire cd_v,cd_r,cd_w,cd_rv,cd_rr,cd_err,cd_pf,cd_atomic;wire[4:0]cd_amo;
 wire[31:0]cd_a,cd_wd,cd_rd;wire[3:0]cd_st;wire[1:0]cd_sz;
 wire pi_v,pi_r,pi_rv,pi_rr;wire[31:0]pi_a;wire[63:0]pi_data;wire[1:0]pi_err;
 wire pd_v,pd_r,pd_w,pd_rv,pd_rr,pd_err;wire[31:0]pd_a,pd_wd,pd_rd;wire[3:0]pd_st;wire[1:0]pd_sz;
 wire fi,fd,sfence,mmu_sum,mmu_mxr,mmu_mprv;wire[1:0]mmu_mpp;
 wire[63:0]mtime;wire itimer,isoft,iextm,iexts,ei,ed,ew,maintenance_busy;
 wire pr,pg,pw,pv,pe;wire[31:0]pa,pwd,prd;wire[3:0]pst;wire[1:0]psz;
 rv32_ooo_core #(.RESET_VECTOR(RESET_VECTOR),.ENABLE_TRACE(0),.ENABLE_PAIRING(1),
 .LOAD_BYPASS(0),.ENABLE_STORE_HEAD_LOOKAHEAD(0),.ENABLE_STORE_ISSUE_LOOKAHEAD(0)) processor(
 .clk(clk),.reset(reset),
 .imem_request_valid(ci_v),.imem_request_ready(ci_r),.imem_request_address(ci_a),
 .imem_response_valid(ci_rv),.imem_response_ready(ci_rr),.imem_response_data(ci_data),.imem_response_error(ci_err),.imem_response_page_fault(ci_pf),
 .dmem_request_valid(cd_v),.dmem_request_ready(cd_r),.dmem_request_address(cd_a),.dmem_request_write(cd_w),
 .dmem_request_size(cd_sz),.dmem_request_wdata(cd_wd),.dmem_request_wstrb(cd_st),
 .dmem_request_is_atomic(cd_atomic),.dmem_request_atomic(cd_amo),
 .dmem_response_valid(cd_rv),.dmem_response_ready(cd_rr),.dmem_response_rdata(cd_rd),.dmem_response_error(cd_err),.dmem_response_page_fault(cd_pf),
 .irq_software(isoft),.irq_timer(itimer),.irq_external(iextm),.irq_supervisor_external(iexts),.mtime(mtime),
 .privilege_mode(debug_privilege),.mmu_satp(debug_satp),.mmu_sum(mmu_sum),.mmu_mxr(mmu_mxr),.mmu_mprv(mmu_mprv),.mmu_mpp(mmu_mpp),.mmu_sfence(sfence),
 .event_icache_refill(ei),.event_dcache_refill(ed),.event_dcache_writeback(ew),.fence_i(fi),.fence_d(fd),
 .debug_trap(debug_trap),.debug_mepc(debug_mepc),.debug_mcause(debug_mcause),.debug_mtval(debug_mtval),.debug_sepc(debug_sepc),.debug_scause(debug_scause),.debug_stval(debug_stval),.debug_architectural_pc(debug_architectural_pc),.retire_valid(retire_valid),.retire_pc0(retire_pc0),.retire_pc1(retire_pc1),
 .retire_instruction0(retire_instruction0),.retire_instruction1(retire_instruction1),
 .retire_destination0(retire_destination0),.retire_destination1(retire_destination1),.retire_value0(retire_value0),.retire_value1(retire_value1));
 rv32_linux_memory_bridge #(.RAM_BASE(RAM_BASE),.RAM_LIMIT(RAM_LIMIT)) translation(
 .clk(clk),.reset(reset),.sfence(sfence),.reservation_kill(reservation_kill),
 .privilege_mode(debug_privilege),.mmu_satp(debug_satp),.mmu_sum(mmu_sum),.mmu_mxr(mmu_mxr),.mmu_mprv(mmu_mprv),.mmu_mpp(mmu_mpp),
 .c_i_valid(ci_v),.c_i_ready(ci_r),.c_i_addr(ci_a),.c_i_rsp_valid(ci_rv),.c_i_rsp_ready(ci_rr),.c_i_rsp_data(ci_data),.c_i_rsp_error(ci_err),.c_i_rsp_pagefault(ci_pf),
 .c_d_valid(cd_v),.c_d_ready(cd_r),.c_d_addr(cd_a),.c_d_write(cd_w),.c_d_wdata(cd_wd),.c_d_wstrb(cd_st),.c_d_size(cd_sz),.c_d_atomic(cd_atomic),.c_d_amo(cd_amo),
 .c_d_rsp_valid(cd_rv),.c_d_rsp_ready(cd_rr),.c_d_rsp_data(cd_rd),.c_d_rsp_error(cd_err),.c_d_rsp_pagefault(cd_pf),
 .p_i_valid(pi_v),.p_i_ready(pi_r),.p_i_addr(pi_a),.p_i_rsp_valid(pi_rv),.p_i_rsp_ready(pi_rr),.p_i_rsp_data(pi_data),.p_i_rsp_error(pi_err),
 .p_d_valid(pd_v),.p_d_ready(pd_r),.p_d_addr(pd_a),.p_d_write(pd_w),.p_d_wdata(pd_wd),.p_d_wstrb(pd_st),.p_d_size(pd_sz),
 .p_d_rsp_valid(pd_rv),.p_d_rsp_ready(pd_rr),.p_d_rsp_data(pd_rd),.p_d_rsp_error(pd_err),.busy(),.flush_busy());
 rv32_memory_system #(.LINUX_PHYSICAL_MAP(1),.ENABLE_DATA_RAM_GUARD(1),.DATA_RAM_BASE(RAM_BASE),.DATA_RAM_LIMIT(RAM_LIMIT-1),.I_INDEX_BITS(8),.D_INDEX_BITS(6),.D_WAYS(2)) cache(
 .clk(clk),.reset(reset),.imem_request_valid(pi_v),.imem_request_ready(pi_r),.imem_request_address(pi_a),
 .imem_response_valid(pi_rv),.imem_response_ready(pi_rr),.imem_response_data(pi_data),.imem_response_error(pi_err),
 .dmem_request_valid(pd_v),.dmem_request_ready(pd_r),.dmem_request_address(pd_a),.dmem_request_write(pd_w),.dmem_request_wdata(pd_wd),.dmem_request_wstrb(pd_st),.dmem_request_size(pd_sz),
 .dmem_response_valid(pd_rv),.dmem_response_ready(pd_rr),.dmem_response_rdata(pd_rd),.dmem_response_error(pd_err),
 .fence_i(fi),.fence_d(fd),.maintenance_busy(maintenance_busy),.event_icache_refill(ei),.event_dcache_refill(ed),.event_dcache_writeback(ew),
 .instr_req_o(instr_req_o),.instr_gnt_i(instr_gnt_i),.instr_addr_o(instr_addr_o),.instr_io_o(instr_io_o),.instr_rvalid_i(instr_rvalid_i),.instr_rready_o(instr_rready_o),.instr_rdata_i(instr_rdata_i),.instr_err_i(instr_err_i),
 .data_rd_req_o(data_rd_req_o),.data_rd_gnt_i(data_rd_gnt_i),.data_rd_id_o(data_rd_id_o),.data_rd_addr_o(data_rd_addr_o),.data_rd_rvalid_i(data_rd_rvalid_i),.data_rd_rready_o(data_rd_rready_o),.data_rd_rid_i(data_rd_rid_i),.data_rd_rdata_i(data_rd_rdata_i),.data_rd_err_i(data_rd_err_i),
 .data_wr_req_o(data_wr_req_o),.data_wr_gnt_i(data_wr_gnt_i),.data_wr_last_o(data_wr_last_o),.data_wr_addr_o(data_wr_addr_o),.data_wr_data_o(data_wr_data_o),.data_wr_id_o(data_wr_id_o),.data_wr_bvalid_i(data_wr_bvalid_i),.data_wr_berr_i(data_wr_berr_i),.data_wr_bid_i(data_wr_bid_i),
 .periph_req_o(pr),.periph_gnt_i(pg),.periph_we_o(pw),.periph_addr_o(pa),.periph_wdata_o(pwd),.periph_be_o(pst),.periph_size_o(psz),.periph_rvalid_i(pv),.periph_err_i(pe),.periph_rdata_i(prd));
 rv32_linux_peripherals #(.TIMER_DIV(TIMER_DIV),.UART_DIV(UART_DIV)) peripherals(
 .clk(clk),.reset(reset),.req_valid(pr),.req_ready(pg),.req_write(pw),.req_addr(pa),.req_wdata(pwd),.req_wstrb(pst),
 .rsp_valid(pv),.rsp_ready(1'b1),.rsp_rdata(prd),.rsp_error(pe),.uart_rx(uart_rx),.uart_tx(uart_tx),.vblank(vblank),
 .fb_base(framebuffer_base),.fb_enable(framebuffer_enable),.mtime(mtime),.irq_timer(itimer),.irq_software(isoft),.irq_external_m(iextm),.irq_external_s(iexts));
endmodule
