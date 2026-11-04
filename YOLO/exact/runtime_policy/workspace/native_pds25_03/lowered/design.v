module soc_cpu_tile_v15 (
	clk,
	rst,
	system_req_valid,
	system_req_ready,
	system_req_addr,
	system_req_write,
	system_req_wdata,
	system_req_wstrb,
	system_req_is_fetch,
	system_rsp_valid,
	system_rsp_ready,
	system_rsp_rdata,
	system_rsp_error,
	npu_req_valid,
	npu_req_ready,
	npu_req_addr,
	npu_req_write,
	npu_req_wdata,
	npu_req_wstrb,
	npu_rsp_valid,
	npu_rsp_ready,
	npu_rsp_rdata,
	npu_rsp_error,
	npu_irq,
	cache_mem_req_valid,
	cache_mem_req_write,
	cache_mem_req_ready,
	cache_mem_req_addr,
	cache_mem_req_wdata,
	cache_mem_req_wstrb,
	cache_mem_req_tag,
	cache_mem_rsp_valid,
	cache_mem_rsp_write,
	cache_mem_rsp_error,
	cache_mem_rsp_ready,
	cache_mem_rsp_rdata,
	cache_mem_rsp_tag,
	cache_protocol_fault,
	cache_hit_count,
	cache_miss_count,
	cache_bypass_count,
	maintenance_count,
	irq_nmi_fault,
	irq_fast_adc,
	irq_fast_pwm,
	irq_qei,
	irq_timer,
	irq_ipc,
	irq_platform,
	core_sleeping,
	retire_valid_diag,
	retire_pc_diag,
	irq_accept_diag,
	irq_vector_pc_diag,
	handler_entry_diag,
	fatal_state_diag
);
	reg _sv2v_0;
	parameter [31:0] BTB_INDEX_BITS = 9;
	parameter [0:0] REGISTERED_AGU = 1;
	parameter [0:0] LOAD_BRANCH_BYPASS = 1;
	parameter [0:0] MDU_WB_ONLY = 1;
	parameter [31:0] HART_ID = 32'd0;
	parameter [31:0] RESET_PC = 32'h10000000;
	parameter [31:0] FAST_VECTOR_BASE = RESET_PC + 32'h00000100;
	parameter [31:0] FAST_VECTOR_STRIDE = 32'd4;
	parameter [0:0] BPU_ENABLE = 1'b1;
	parameter [0:0] NPU_ENABLE = 1'b1;
	parameter [31:0] ITCM_ADDR_WIDTH = 14;
	parameter [31:0] DTCM_ADDR_WIDTH = 14;
	parameter [31:0] DTCM_READ_LATENCY = 1;
	parameter ITCM_INIT_FILE = "";
	parameter DTCM_INIT_FILE = "";
	parameter integer CACHE_CAPACITY_BYTES = 16384;
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [31:0] CACHE_BASE = 32'h84000000;
	parameter [32:0] DDR_BYTES = 33'h010000000;
	parameter [32:0] CACHE_BYTES = 33'h004000000;
	parameter [0:0] EARLY_STORE_ACK = 1'b1;
	input wire clk;
	input wire rst;
	output wire system_req_valid;
	input wire system_req_ready;
	output wire [31:0] system_req_addr;
	output wire system_req_write;
	output wire [31:0] system_req_wdata;
	output wire [3:0] system_req_wstrb;
	output wire system_req_is_fetch;
	input wire system_rsp_valid;
	output wire system_rsp_ready;
	input wire [31:0] system_rsp_rdata;
	input wire system_rsp_error;
	output wire npu_req_valid;
	input wire npu_req_ready;
	output wire [15:0] npu_req_addr;
	output wire npu_req_write;
	output wire [31:0] npu_req_wdata;
	output wire [3:0] npu_req_wstrb;
	input wire npu_rsp_valid;
	output wire npu_rsp_ready;
	input wire [31:0] npu_rsp_rdata;
	input wire npu_rsp_error;
	input wire npu_irq;
	output wire [1:0] cache_mem_req_valid;
	output wire [1:0] cache_mem_req_write;
	input wire [1:0] cache_mem_req_ready;
	output wire [63:0] cache_mem_req_addr;
	output wire [255:0] cache_mem_req_wdata;
	output wire [31:0] cache_mem_req_wstrb;
	output wire [7:0] cache_mem_req_tag;
	input wire [1:0] cache_mem_rsp_valid;
	input wire [1:0] cache_mem_rsp_write;
	input wire [1:0] cache_mem_rsp_error;
	output wire [1:0] cache_mem_rsp_ready;
	input wire [255:0] cache_mem_rsp_rdata;
	input wire [7:0] cache_mem_rsp_tag;
	output wire cache_protocol_fault;
	output reg [63:0] cache_hit_count;
	output reg [63:0] cache_miss_count;
	output reg [63:0] cache_bypass_count;
	output reg [31:0] maintenance_count;
	input wire irq_nmi_fault;
	input wire irq_fast_adc;
	input wire irq_fast_pwm;
	input wire irq_qei;
	input wire irq_timer;
	input wire irq_ipc;
	input wire [7:0] irq_platform;
	output wire core_sleeping;
	output wire retire_valid_diag;
	output wire [31:0] retire_pc_diag;
	output wire irq_accept_diag;
	output wire [31:0] irq_vector_pc_diag;
	output wire handler_entry_diag;
	output wire fatal_state_diag;
	(* syn_keep = 1 *) wire region_reset_core;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_core(
		.I0(rst),
		.Z(region_reset_core)
	);
	(* syn_keep = 1 *) wire region_reset_memory;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_memory(
		.I0(rst),
		.Z(region_reset_memory)
	);
	(* syn_keep = 1 *) wire region_reset_data_boundary;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_data_boundary(
		.I0(rst),
		.Z(region_reset_data_boundary)
	);
	(* syn_keep = 1 *) wire region_reset_ifill;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_ifill(
		.I0(rst),
		.Z(region_reset_ifill)
	);
	(* syn_keep = 1 *) wire region_reset_data_lines;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_data_lines(
		.I0(rst),
		.Z(region_reset_data_lines)
	);
	(* syn_keep = 1 *) wire region_reset_uncached;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_uncached(
		.I0(rst),
		.Z(region_reset_uncached)
	);
	(* syn_keep = 1 *) wire region_reset_router;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_router(
		.I0(rst),
		.Z(region_reset_router)
	);
	wire iv;
	wire ir;
	wire ipv;
	wire ipr;
	wire [31:0] ia;
	wire [63:0] ipd;
	wire [1:0] ipe;
	wire dv;
	wire dr;
	wire dw;
	wire dpv;
	wire dpr;
	wire dpe;
	wire [31:0] da;
	wire [31:0] dwd;
	wire [31:0] dpd;
	wire [3:0] ds;
	wire [1:0] dz;
	wire cv;
	wire cr;
	wire cw;
	wire cpv;
	wire cpr;
	wire cpe;
	wire [31:0] ca;
	wire [31:0] cwd;
	wire [31:0] cpd;
	wire [3:0] cs;
	wire [1:0] cz;
	wire memory_fence_i;
	wire memory_fence_d;
	wire boundary_fault;
	wire boundary_barrier;
	wire memory_ir;
	wire fi;
	wire fd;
	wire maint_busy;
	wire manual_maint;
	wire manual_maint_done;
	wire ei;
	wire ed;
	wire ew;
	wire ih;
	wire im;
	wire dh;
	wire dm;
	wire line_i_req;
	wire line_i_gnt;
	wire line_i_valid;
	wire line_i_ready;
	wire line_i_error;
	wire line_i_io;
	wire [31:0] line_i_addr;
	wire [63:0] line_i_data;
	wire line_d_req;
	wire line_d_gnt;
	wire line_d_id;
	wire line_d_valid;
	wire line_d_ready;
	wire line_d_error;
	wire line_d_rid;
	wire [31:0] line_d_addr;
	wire [63:0] line_d_data;
	wire wr_req;
	wire wr_gnt;
	wire wr_last;
	wire wr_id;
	wire b_valid;
	wire b_error;
	wire b_id;
	wire [31:0] wr_addr;
	wire [63:0] wr_data;
	wire preq;
	wire pgnt;
	wire pwrite;
	wire prvalid;
	wire perror;
	wire [31:0] paddr;
	wire [31:0] pdata;
	wire [31:0] prdata;
	wire [3:0] pbe;
	wire [1:0] psize;
	wire [1:0] retired_mask;
	wire [31:0] rpc0;
	wire [31:0] rpc1;
	wire [31:0] rinstr0;
	wire [31:0] rinstr1;
	wire [31:0] rv0;
	wire [31:0] rv1;
	wire [4:0] rd0;
	wire [4:0] rd1;
	wire trap_event;
	wire redirect_event;
	wire [31:0] trap_cause;
	wire [31:0] trap_vector;
	reg [63:0] cycles;
	reg [63:0] retired_total;
	reg [63:0] cycle_snapshot;
	reg [63:0] retired_snapshot;
	reg [31:0] irq_vector_q;
	wire [31:0] retired_next_pc0;
	reg handler_armed;
	reg [31:0] writebacks;
	reg [31:0] fences;
	reg [31:0] maintenance_cycles;
	reg [31:0] i_refills;
	reg [31:0] d_refills;
	wire [31:0] mmio_submits;
	wire [31:0] mmio_wait_cycles;
	wire [31:0] uncached_ddr_count;
	wire [31:0] control_addr;
	reg [31:0] control_rdata;
	wire ifault;
	wire dfault;
	wire pfault;
	assign ir = memory_ir && !boundary_barrier;
	wire mdv;
	wire mdr;
	wire mdpv;
	wire mdpr;
	wire mdpe;
	wire [31:0] mdpd;
	reg [1:0] manual_state;
	reg manual_error;
	reg manual_seen_busy;
	wire manual_select = dw && (da == 32'h30000100);
	assign mdv = (dv && !manual_select) && (manual_state == 0);
	assign dr = (manual_state == 0 ? (manual_select ? mdr && !mdpv : mdr) : 1'b0);
	assign dpv = (manual_state == 3 ? 1'b1 : (manual_state == 0 ? mdpv : 1'b0));
	assign dpd = (manual_state == 3 ? 32'd0 : mdpd);
	assign dpe = (manual_state == 3 ? manual_error : mdpe);
	assign mdpr = dpr && (manual_state == 0);
	assign manual_maint = (manual_state == 1) && !manual_error;
	assign manual_maint_done = ((manual_state == 3) && dpr) && !manual_error;
	always @(posedge clk)
		if (rst) begin
			manual_state <= 0;
			manual_error <= 0;
			manual_seen_busy <= 0;
		end
		else
			case (manual_state)
				0:
					if ((dv && dr) && manual_select) begin
						manual_error <= ((dz != 2) || (ds != 15)) || (dwd != 1);
						manual_seen_busy <= 0;
						manual_state <= 1;
					end
				1: manual_state <= (manual_error ? 3 : 2);
				2: begin
					if (maint_busy)
						manual_seen_busy <= 1;
					if (cache_protocol_fault) begin
						manual_error <= 1;
						manual_state <= 3;
					end
					else if (manual_seen_busy && !maint_busy)
						manual_state <= 3;
				end
				3:
					if (dpr)
						manual_state <= 0;
			endcase
	assign cache_protocol_fault = ((ifault | dfault) | pfault) | boundary_fault;
	assign core_sleeping = 1'b0;
	assign retire_valid_diag = |retired_mask;
	assign retire_pc_diag = rpc0;
	assign irq_accept_diag = trap_event && trap_cause[31];
	assign irq_vector_pc_diag = irq_vector_q;
	assign handler_entry_diag = (handler_armed && retired_mask[0]) && (rpc0 == irq_vector_q);
	assign fatal_state_diag = cache_protocol_fault;
	rv32_ooo_core #(
		.RESET_VECTOR(RESET_PC),
		.ENABLE_PAIRING(1),
		.LOAD_ORDER_ISSUE_LOOKAHEAD(1),
		.MEMORY_CREDITS(3),
		.FETCH_CREDITS(2),
		.ENABLE_COMMITTED_RAS(1),
		.RAS_DEPTH(16),
		.ENABLE_ORDERED_STORE_PREP(1),
		.ENABLE_STORE_HEAD_LOOKAHEAD(1),
		.ENABLE_STORE_ISSUE_LOOKAHEAD(1),
		.ENABLE_REDIRECT_FETCH(0),
		.ENABLE_CURRENT_INTEGER_PAIR(1),
		.ENABLE_DISPATCH_BYPASS(1),
		.DISPATCH_BYPASS_UNMAPPED_ONLY(1),
		.ENABLE_CONTROL_DISPATCH(1),
		.BANKED_ISSUE(1),
		.DECOUPLED_ALLOCATION_PAYLOAD(1),
		.CARRIED_COMPLETION_WRITES(1),
		.FAST_WAKEUP(1),
		.ENABLE_SAME_CYCLE_REUSE(0),
		.ENABLE_TRACE(0)
	) core(
		.clk(clk),
		.reset(region_reset_core),
		.d1_trap_cause(trap_cause),
		.d1_trap_vector(trap_vector),
		.d1_retire_next_pc0(retired_next_pc0),
		.imem_request_valid(iv),
		.imem_request_ready(ir),
		.imem_request_address(ia),
		.imem_response_valid(ipv),
		.imem_response_ready(ipr),
		.imem_response_data(ipd),
		.imem_response_error(ipe),
		.dmem_request_valid(cv),
		.dmem_request_ready(cr),
		.dmem_request_address(ca),
		.dmem_request_write(cw),
		.dmem_request_size(cz),
		.dmem_request_wdata(cwd),
		.dmem_request_wstrb(cs),
		.dmem_response_valid(cpv),
		.dmem_response_ready(cpr),
		.dmem_response_rdata(cpd),
		.dmem_response_error(cpe),
		.irq_software(irq_ipc),
		.irq_timer(irq_timer),
		.irq_external((((((npu_irq | (|irq_platform)) | irq_fast_adc) | irq_fast_pwm) | irq_qei) | irq_nmi_fault) | cache_protocol_fault),
		.mtime(cycles),
		.event_icache_refill(ei),
		.event_dcache_refill(ed),
		.event_dcache_writeback(ew),
		.fence_i(fi),
		.fence_d(fd),
		.debug_redirect(redirect_event),
		.debug_trap(trap_event),
		.debug_branch_miss(),
		.debug_jump_miss(),
		.debug_dispatch_stall(),
		.debug_frontend_stall(),
		.retire_valid(retired_mask),
		.retire_pc0(rpc0),
		.retire_pc1(rpc1),
		.retire_instruction0(rinstr0),
		.retire_instruction1(rinstr1),
		.retire_destination0(rd0),
		.retire_destination1(rd1),
		.retire_value0(rv0),
		.retire_value1(rv1)
	);
	rv32_d1_data_boundary data_boundary(
		.clk(clk),
		.rst(region_reset_data_boundary),
		.c_valid(cv),
		.c_ready(cr),
		.c_addr(ca),
		.c_write(cw),
		.c_wdata(cwd),
		.c_strobe(cs),
		.c_size(cz),
		.c_rsp_valid(cpv),
		.c_rsp_ready(cpr),
		.c_rdata(cpd),
		.c_rsp_error(cpe),
		.c_fence_i(fi),
		.c_fence_d(fd),
		.m_valid(dv),
		.m_ready(dr),
		.m_addr(da),
		.m_write(dw),
		.m_wdata(dwd),
		.m_strobe(ds),
		.m_size(dz),
		.m_rsp_valid(dpv),
		.m_rsp_ready(dpr),
		.m_rdata(dpd),
		.m_rsp_error(dpe),
		.m_fence_i(memory_fence_i),
		.m_fence_d(memory_fence_d),
		.barrier_pending(boundary_barrier),
		.fault(boundary_fault)
	);
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	rv32_memory_system #(
		.I_INDEX_BITS(8),
		.D_INDEX_BITS(6),
		.D_WAYS(2),
		.ENABLE_FAST_ICROSS(1),
		.D1_COMPAT(1),
		.D1_CACHE_BASE(CACHE_BASE),
		.D1_CACHE_BYTES(CACHE_BYTES),
		.ENABLE_DATA_RAM_GUARD(1),
		.DATA_RAM_BASE(CACHE_BASE),
		.DATA_RAM_LIMIT((CACHE_BASE + sv2v_cast_32(CACHE_BYTES)) - 1)
	) memory(
		.clk(clk),
		.reset(region_reset_memory),
		.imem_request_valid(iv && !boundary_barrier),
		.imem_request_ready(memory_ir),
		.imem_request_address(ia),
		.imem_response_valid(ipv),
		.imem_response_ready(ipr),
		.imem_response_data(ipd),
		.imem_response_error(ipe),
		.dmem_request_valid(mdv),
		.dmem_request_ready(mdr),
		.dmem_request_address(da),
		.dmem_request_write(dw),
		.dmem_request_wdata(dwd),
		.dmem_request_wstrb(ds),
		.dmem_request_size(dz),
		.dmem_response_valid(mdpv),
		.dmem_response_ready(mdpr),
		.dmem_response_rdata(mdpd),
		.dmem_response_error(mdpe),
		.fence_i(memory_fence_i | manual_maint),
		.fence_d(memory_fence_d | manual_maint),
		.maintenance_busy(maint_busy),
		.event_icache_refill(ei),
		.event_dcache_refill(ed),
		.event_dcache_writeback(ew),
		.event_icache_hit(ih),
		.event_icache_miss(im),
		.event_dcache_hit(dh),
		.event_dcache_miss(dm),
		.instr_req_o(line_i_req),
		.instr_gnt_i(line_i_gnt),
		.instr_addr_o(line_i_addr),
		.instr_io_o(line_i_io),
		.instr_rvalid_i(line_i_valid),
		.instr_rready_o(line_i_ready),
		.instr_rdata_i(line_i_data),
		.instr_err_i(line_i_error),
		.data_rd_req_o(line_d_req),
		.data_rd_gnt_i(line_d_gnt),
		.data_rd_id_o(line_d_id),
		.data_rd_addr_o(line_d_addr),
		.data_rd_rvalid_i(line_d_valid),
		.data_rd_rready_o(line_d_ready),
		.data_rd_rid_i(line_d_rid),
		.data_rd_rdata_i(line_d_data),
		.data_rd_err_i(line_d_error),
		.data_wr_req_o(wr_req),
		.data_wr_gnt_i(wr_gnt),
		.data_wr_last_o(wr_last),
		.data_wr_addr_o(wr_addr),
		.data_wr_data_o(wr_data),
		.data_wr_id_o(wr_id),
		.data_wr_bvalid_i(b_valid),
		.data_wr_berr_i(b_error),
		.data_wr_bid_i(b_id),
		.periph_req_o(preq),
		.periph_gnt_i(pgnt),
		.periph_we_o(pwrite),
		.periph_addr_o(paddr),
		.periph_wdata_o(pdata),
		.periph_be_o(pbe),
		.periph_size_o(psize),
		.periph_rvalid_i(prvalid),
		.periph_err_i(perror),
		.periph_rdata_i(prdata)
	);
	rv32_d1_ifill #(
		.ITCM_ADDR_WIDTH(ITCM_ADDR_WIDTH),
		.ITCM_INIT_FILE(ITCM_INIT_FILE),
		.DDR_BASE(DDR_BASE),
		.DDR_BYTES(DDR_BYTES)
	) ifill(
		.clk(clk),
		.rst(region_reset_ifill),
		.req(line_i_req),
		.gnt(line_i_gnt),
		.addr(line_i_addr),
		.rvalid(line_i_valid),
		.rready(line_i_ready),
		.rdata(line_i_data),
		.error(line_i_error),
		.fault(ifault),
		.mem_req_valid(cache_mem_req_valid[0]),
		.mem_req_ready(cache_mem_req_ready[0]),
		.mem_req_write(cache_mem_req_write[0]),
		.mem_req_addr(cache_mem_req_addr[0+:32]),
		.mem_req_wdata(cache_mem_req_wdata[0+:128]),
		.mem_req_wstrb(cache_mem_req_wstrb[0+:16]),
		.mem_req_tag(cache_mem_req_tag[0+:4]),
		.mem_rsp_valid(cache_mem_rsp_valid[0]),
		.mem_rsp_ready(cache_mem_rsp_ready[0]),
		.mem_rsp_write(cache_mem_rsp_write[0]),
		.mem_rsp_rdata(cache_mem_rsp_rdata[0+:128]),
		.mem_rsp_tag(cache_mem_rsp_tag[0+:4]),
		.mem_rsp_error(cache_mem_rsp_error[0])
	);
	wire lv;
	wire lr;
	wire lw;
	wire lsv;
	wire lsr;
	wire lsw;
	wire lse;
	wire [31:0] la;
	wire [127:0] ld;
	wire [15:0] lm;
	wire [3:0] lt;
	wire pv;
	wire pr;
	wire pw;
	wire psv;
	wire psr;
	wire psw;
	wire pse;
	wire pactive;
	wire [31:0] pa;
	wire [127:0] pd;
	wire [15:0] pm;
	wire [3:0] pt;
	rv32_line128_adapter #(
		.DDR_BASE(DDR_BASE),
		.DDR_BYTES(DDR_BYTES)
	) data_lines(
		.clk(clk),
		.rst(region_reset_data_lines),
		.rd_req(line_d_req),
		.rd_gnt(line_d_gnt),
		.rd_addr(line_d_addr),
		.rd_id(line_d_id),
		.rd_valid(line_d_valid),
		.rd_ready(line_d_ready),
		.rd_data(line_d_data),
		.rd_error(line_d_error),
		.rd_rid(line_d_rid),
		.wr_req(wr_req),
		.wr_gnt(wr_gnt),
		.wr_addr(wr_addr),
		.wr_data(wr_data),
		.wr_last(wr_last),
		.wr_id(wr_id),
		.b_valid(b_valid),
		.b_error(b_error),
		.b_id(b_id),
		.fault(dfault),
		.mem_req_valid(lv),
		.mem_req_ready(lr),
		.mem_req_write(lw),
		.mem_req_addr(la),
		.mem_req_wdata(ld),
		.mem_req_wstrb(lm),
		.mem_req_tag(lt),
		.mem_rsp_valid(lsv),
		.mem_rsp_ready(lsr),
		.mem_rsp_write(cache_mem_rsp_write[1]),
		.mem_rsp_rdata(cache_mem_rsp_rdata[128+:128]),
		.mem_rsp_tag(cache_mem_rsp_tag[4+:4]),
		.mem_rsp_error(cache_mem_rsp_error[1])
	);
	assign cache_mem_req_valid[1] = (pactive ? pv : lv);
	assign cache_mem_req_write[1] = (pactive ? pw : lw);
	assign cache_mem_req_addr[32+:32] = (pactive ? pa : la);
	assign cache_mem_req_wdata[128+:128] = (pactive ? pd : ld);
	assign cache_mem_req_wstrb[16+:16] = (pactive ? pm : lm);
	assign cache_mem_req_tag[4+:4] = (pactive ? pt : lt);
	assign lr = cache_mem_req_ready[1] && !pactive;
	assign pr = cache_mem_req_ready[1] && pactive;
	assign lsv = cache_mem_rsp_valid[1] && !pactive;
	assign psv = cache_mem_rsp_valid[1] && pactive;
	assign cache_mem_rsp_ready[1] = (pactive ? psr : lsr);
	wire nv;
	wire nr;
	wire nw;
	wire nsv;
	wire nsr;
	wire nse;
	wire [31:0] na;
	wire [31:0] nd;
	wire [31:0] nsd;
	wire [3:0] nm;
	rv32_d1_uncached #(
		.DTCM_ADDR_WIDTH(DTCM_ADDR_WIDTH),
		.DTCM_READ_LATENCY(DTCM_READ_LATENCY),
		.DTCM_INIT_FILE(DTCM_INIT_FILE),
		.DDR_BASE(DDR_BASE),
		.DDR_BYTES(DDR_BYTES)
	) uncached(
		.clk(clk),
		.rst(region_reset_uncached),
		.req(preq),
		.gnt(pgnt),
		.write(pwrite),
		.addr(paddr),
		.wdata(pdata),
		.be(pbe),
		.size(psize),
		.rvalid(prvalid),
		.error(perror),
		.rdata(prdata),
		.native_req(nv),
		.native_ready(nr),
		.native_write(nw),
		.native_addr(na),
		.native_wdata(nd),
		.native_strb(nm),
		.native_rvalid(nsv),
		.native_rready(nsr),
		.native_rdata(nsd),
		.native_error(nse),
		.mem_active(pactive),
		.mem_req_valid(pv),
		.mem_req_ready(pr),
		.mem_req_write(pw),
		.mem_req_addr(pa),
		.mem_req_wdata(pd),
		.mem_req_wstrb(pm),
		.mem_req_tag(pt),
		.mem_rsp_valid(psv),
		.mem_rsp_ready(psr),
		.mem_rsp_write(cache_mem_rsp_write[1]),
		.mem_rsp_rdata(cache_mem_rsp_rdata[128+:128]),
		.mem_rsp_tag(cache_mem_rsp_tag[4+:4]),
		.mem_rsp_error(cache_mem_rsp_error[1]),
		.maintenance_req(),
		.maintenance_done(),
		.maintenance_busy(maint_busy),
		.cache_fault(cache_protocol_fault),
		.control_addr(control_addr),
		.control_rdata(control_rdata),
		.fault(pfault),
		.mmio_submits(mmio_submits),
		.mmio_wait_cycles(mmio_wait_cycles),
		.ddr_uncached_count(uncached_ddr_count)
	);
	dc_realtime_core_npu_router #(.NPU_ENABLE(NPU_ENABLE)) router(
		.clk(clk),
		.rst(region_reset_router),
		.core_req_valid(nv),
		.core_req_ready(nr),
		.core_req_addr(na),
		.core_req_write(nw),
		.core_req_wdata(nd),
		.core_req_wstrb(nm),
		.core_req_is_fetch(1'b0),
		.core_rsp_valid(nsv),
		.core_rsp_ready(nsr),
		.core_rsp_rdata(nsd),
		.core_rsp_error(nse),
		.system_req_valid(system_req_valid),
		.system_req_ready(system_req_ready),
		.system_req_addr(system_req_addr),
		.system_req_write(system_req_write),
		.system_req_wdata(system_req_wdata),
		.system_req_wstrb(system_req_wstrb),
		.system_req_is_fetch(system_req_is_fetch),
		.system_rsp_valid(system_rsp_valid),
		.system_rsp_ready(system_rsp_ready),
		.system_rsp_rdata(system_rsp_rdata),
		.system_rsp_error(system_rsp_error),
		.npu_req_valid(npu_req_valid),
		.npu_req_ready(npu_req_ready),
		.npu_req_addr(npu_req_addr),
		.npu_req_write(npu_req_write),
		.npu_req_wdata(npu_req_wdata),
		.npu_req_wstrb(npu_req_wstrb),
		.npu_rsp_valid(npu_rsp_valid),
		.npu_rsp_ready(npu_rsp_ready),
		.npu_rsp_rdata(npu_rsp_rdata),
		.npu_rsp_error(npu_rsp_error)
	);
	always @(*) begin
		if (_sv2v_0)
			;
		control_rdata = 0;
		case (control_addr)
			32'h30000100: control_rdata = 3;
			32'h30000104: control_rdata = cache_hit_count[0+:32];
			32'h30000108: control_rdata = cache_miss_count[0+:32];
			32'h3000010c: control_rdata = cache_hit_count[32+:32];
			32'h30000110: control_rdata = cache_miss_count[32+:32];
			32'h30000114: control_rdata = cache_bypass_count[32+:32];
			32'h30000118: control_rdata = maintenance_count;
			32'h3000011c: control_rdata = cache_bypass_count[0+:32];
			32'h30000200: control_rdata = 32'h44323552;
			32'h30000204: control_rdata = cycle_snapshot[31:0];
			32'h30000208: control_rdata = cycle_snapshot[63:32];
			32'h3000020c: control_rdata = retired_snapshot[31:0];
			32'h30000210: control_rdata = retired_snapshot[63:32];
			32'h30000214: control_rdata = writebacks;
			32'h30000218: control_rdata = fences;
			32'h3000021c: control_rdata = maintenance_cycles;
			32'h30000220: control_rdata = mmio_submits;
			32'h30000224: control_rdata = mmio_wait_cycles;
			32'h30000228: control_rdata = uncached_ddr_count;
			32'h3000022c: control_rdata = {28'd0, maint_busy, pfault, dfault, ifault};
			32'h30000230: control_rdata = i_refills;
			32'h30000234: control_rdata = d_refills;
			default: control_rdata = 0;
		endcase
	end
	function automatic [63:0] sv2v_cast_64;
		input reg [63:0] inp;
		sv2v_cast_64 = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			cycles <= 0;
			retired_total <= 0;
			cycle_snapshot <= 0;
			retired_snapshot <= 0;
			irq_vector_q <= 0;
			handler_armed <= 0;
			cache_hit_count <= 1'sb0;
			cache_miss_count <= 1'sb0;
			cache_bypass_count <= 1'sb0;
			maintenance_count <= 0;
			writebacks <= 0;
			fences <= 0;
			maintenance_cycles <= 0;
			i_refills <= 0;
			d_refills <= 0;
		end
		else begin
			cycles <= cycles + 1'b1;
			retired_total <= (retired_total + sv2v_cast_64(retired_mask[0])) + sv2v_cast_64(retired_mask[1]);
			if ((preq && pgnt) && (paddr == 32'h30000204))
				cycle_snapshot <= cycles;
			if ((preq && pgnt) && (paddr == 32'h3000020c))
				retired_snapshot <= retired_total;
			if (handler_entry_diag)
				handler_armed <= 0;
			if (irq_accept_diag) begin
				irq_vector_q <= trap_vector;
				handler_armed <= 1;
			end
			if (ih)
				cache_hit_count[0+:32] <= cache_hit_count[0+:32] + 1'b1;
			if (im)
				cache_miss_count[0+:32] <= cache_miss_count[0+:32] + 1'b1;
			if (dh)
				cache_hit_count[32+:32] <= cache_hit_count[32+:32] + 1'b1;
			if (dm)
				cache_miss_count[32+:32] <= cache_miss_count[32+:32] + 1'b1;
			if (preq && pgnt)
				cache_bypass_count[32+:32] <= cache_bypass_count[32+:32] + 1'b1;
			if (ew)
				writebacks <= writebacks + 1'b1;
			if (ei)
				i_refills <= i_refills + 1'b1;
			if (ed)
				d_refills <= d_refills + 1'b1;
			if ((fi || fd) || manual_maint)
				fences <= fences + 1'b1;
			if (manual_maint_done)
				maintenance_count <= maintenance_count + 1'b1;
			if (maint_busy)
				maintenance_cycles <= maintenance_cycles + 1'b1;
		end
	initial _sv2v_0 = 0;
endmodule
module rv32_d1_data_boundary (
	clk,
	rst,
	c_valid,
	c_write,
	c_ready,
	c_addr,
	c_wdata,
	c_strobe,
	c_size,
	c_rsp_valid,
	c_rsp_error,
	c_rsp_ready,
	c_rdata,
	c_fence_i,
	c_fence_d,
	m_valid,
	m_write,
	m_ready,
	m_addr,
	m_wdata,
	m_strobe,
	m_size,
	m_rsp_valid,
	m_rsp_error,
	m_rsp_ready,
	m_rdata,
	m_fence_i,
	m_fence_d,
	barrier_pending,
	fault
);
	input wire clk;
	input wire rst;
	input wire c_valid;
	input wire c_write;
	output wire c_ready;
	input wire [31:0] c_addr;
	input wire [31:0] c_wdata;
	input wire [3:0] c_strobe;
	input wire [1:0] c_size;
	output wire c_rsp_valid;
	output reg c_rsp_error;
	input wire c_rsp_ready;
	output reg [31:0] c_rdata;
	input wire c_fence_i;
	input wire c_fence_d;
	output wire m_valid;
	output reg m_write;
	input wire m_ready;
	output reg [31:0] m_addr;
	output reg [31:0] m_wdata;
	output reg [3:0] m_strobe;
	output reg [1:0] m_size;
	input wire m_rsp_valid;
	input wire m_rsp_error;
	output wire m_rsp_ready;
	input wire [31:0] m_rdata;
	output wire m_fence_i;
	output wire m_fence_d;
	output wire barrier_pending;
	output reg fault;
	reg request_full;
	reg response_full;
	reg pending_i;
	reg pending_d;
	reg [1:0] owners;
	wire push = c_valid && c_ready;
	wire take = m_valid && m_ready;
	wire receive = m_rsp_valid && m_rsp_ready;
	wire consume = c_rsp_valid && c_rsp_ready;
	wire barrier = ((((pending_i || pending_d) && (owners == 0)) && !request_full) && !response_full) && !fault;
	assign c_ready = ((((((!rst && !fault) && !request_full) && (owners != 3)) && !pending_i) && !pending_d) && !c_fence_i) && !c_fence_d;
	assign m_valid = (!rst && !fault) && request_full;
	assign m_rsp_ready = (!rst && !fault) && !response_full;
	assign c_rsp_valid = (!rst && !fault) && response_full;
	assign m_fence_i = barrier && pending_i;
	assign m_fence_d = barrier && pending_d;
	assign barrier_pending = ((c_fence_i || c_fence_d) || pending_i) || pending_d;
	always @(posedge clk) begin
		if (push) begin
			m_addr <= c_addr;
			m_wdata <= c_wdata;
			m_strobe <= c_strobe;
			m_size <= c_size;
			m_write <= c_write;
		end
		if (receive) begin
			c_rdata <= m_rdata;
			c_rsp_error <= m_rsp_error;
		end
		if (rst) begin
			request_full <= 0;
			response_full <= 0;
			pending_i <= 0;
			pending_d <= 0;
			owners <= 0;
			fault <= 0;
		end
		else begin
			if (take)
				request_full <= 0;
			if (push)
				request_full <= 1;
			if (consume)
				response_full <= 0;
			if (receive)
				response_full <= 1;
			case ({push, consume})
				2'b10: owners <= owners + 1'b1;
				2'b01: owners <= owners - 1'b1;
				default:
					;
			endcase
			if (barrier) begin
				pending_i <= 0;
				pending_d <= 0;
			end
			if (c_fence_i)
				pending_i <= 1;
			if (c_fence_d)
				pending_d <= 1;
			if ((receive && (owners == 0)) || (consume && (owners == 0)))
				fault <= 1;
		end
	end
endmodule
module rv32_d1_ifill (
	clk,
	rst,
	req,
	gnt,
	addr,
	rvalid,
	rready,
	rdata,
	error,
	fault,
	mem_req_valid,
	mem_req_ready,
	mem_req_write,
	mem_req_addr,
	mem_req_wdata,
	mem_req_wstrb,
	mem_req_tag,
	mem_rsp_valid,
	mem_rsp_ready,
	mem_rsp_write,
	mem_rsp_rdata,
	mem_rsp_tag,
	mem_rsp_error
);
	parameter integer ITCM_ADDR_WIDTH = 14;
	parameter ITCM_INIT_FILE = "";
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [32:0] DDR_BYTES = 33'h010000000;
	input wire clk;
	input wire rst;
	input wire req;
	output wire gnt;
	input wire [31:0] addr;
	output wire rvalid;
	input wire rready;
	output wire [63:0] rdata;
	output wire error;
	output wire fault;
	output wire mem_req_valid;
	input wire mem_req_ready;
	output wire mem_req_write;
	output wire [31:0] mem_req_addr;
	output wire [127:0] mem_req_wdata;
	output wire [15:0] mem_req_wstrb;
	output wire [3:0] mem_req_tag;
	input wire mem_rsp_valid;
	output wire mem_rsp_ready;
	input wire mem_rsp_write;
	input wire [127:0] mem_rsp_rdata;
	input wire [3:0] mem_rsp_tag;
	input wire mem_rsp_error;
	reg [2:0] state;
	reg [31:0] base_q;
	reg [31:0] lower_q;
	reg [3:0] word_q;
	reg error_q;
	reg [63:0] pair_q;
	function automatic signed [32:0] sv2v_cast_33_signed;
		input reg signed [32:0] inp;
		sv2v_cast_33_signed = inp;
	endfunction
	wire select_tcm = (addr >= 32'h10000000) && (({1'b0, addr} + 33'd64) <= (33'h010000000 + sv2v_cast_33_signed(4 << ITCM_ADDR_WIDTH)));
	wire tv;
	wire tr;
	wire sv;
	wire sr;
	wire se;
	wire [31:0] td;
	wire dg;
	wire dv;
	wire de;
	wire unused_rid;
	wire [63:0] dd;
	assign gnt = (!rst && (state == 3'd0)) && (select_tcm || dg);
	assign rvalid = (state == 3'd3) || ((state == 3'd4) && dv);
	assign rdata = (state == 3'd3 ? pair_q : dd);
	assign error = (state == 3'd3 ? error_q : de);
	assign tv = !rst && (state == 3'd1);
	assign sr = !rst && (state == 3'd2);
	dc_realtime_core_itcm_channel #(
		.ADDR_WIDTH(ITCM_ADDR_WIDTH),
		.INIT_FILE(ITCM_INIT_FILE)
	) itcm(
		.clk(clk),
		.rst(rst),
		.req_valid(tv),
		.req_ready(tr),
		.req_addr(base_q + {26'd0, word_q, 2'b00}),
		.rsp_valid(sv),
		.rsp_ready(sr),
		.rsp_rdata(td),
		.rsp_error(se)
	);
	rv32_line128_adapter #(
		.DDR_BASE(DDR_BASE),
		.DDR_BYTES(DDR_BYTES)
	) ddr(
		.clk(clk),
		.rst(rst),
		.rd_req((req && (state == 3'd0)) && !select_tcm),
		.rd_gnt(dg),
		.rd_addr(addr),
		.rd_id(1'b0),
		.rd_valid(dv),
		.rd_ready(rready && (state == 3'd4)),
		.rd_data(dd),
		.rd_error(de),
		.rd_rid(unused_rid),
		.wr_req(1'b0),
		.wr_gnt(),
		.wr_addr(32'd0),
		.wr_data(64'd0),
		.wr_last(1'b0),
		.wr_id(1'b0),
		.b_valid(),
		.b_error(),
		.b_id(),
		.fault(fault),
		.mem_req_valid(mem_req_valid),
		.mem_req_ready(mem_req_ready),
		.mem_req_write(mem_req_write),
		.mem_req_addr(mem_req_addr),
		.mem_req_wdata(mem_req_wdata),
		.mem_req_wstrb(mem_req_wstrb),
		.mem_req_tag(mem_req_tag),
		.mem_rsp_valid(mem_rsp_valid),
		.mem_rsp_ready(mem_rsp_ready),
		.mem_rsp_write(mem_rsp_write),
		.mem_rsp_rdata(mem_rsp_rdata),
		.mem_rsp_tag(mem_rsp_tag),
		.mem_rsp_error(mem_rsp_error)
	);
	reg [2:0] ddr_beat;
	always @(posedge clk)
		if (rst) begin
			state <= 3'd0;
			base_q <= 0;
			lower_q <= 0;
			word_q <= 0;
			pair_q <= 0;
			error_q <= 0;
			ddr_beat <= 0;
		end
		else
			case (state)
				3'd0:
					if (req && gnt) begin
						base_q <= addr;
						word_q <= 0;
						error_q <= addr[5:0] != 0;
						ddr_beat <= 0;
						state <= (select_tcm ? 3'd1 : 3'd4);
					end
				3'd1:
					if (tv && tr)
						state <= 3'd2;
				3'd2:
					if (sv && sr) begin
						error_q <= error_q | se;
						if (word_q[0]) begin
							pair_q <= {td, lower_q};
							state <= 3'd3;
						end
						else begin
							lower_q <= td;
							word_q <= word_q + 1'b1;
							state <= 3'd1;
						end
					end
				3'd3:
					if (rvalid && rready) begin
						if (word_q == 15)
							state <= 3'd0;
						else begin
							word_q <= word_q + 1'b1;
							state <= 3'd1;
						end
					end
				3'd4:
					if (dv && rready) begin
						if (ddr_beat == 7)
							state <= 3'd0;
						else
							ddr_beat <= ddr_beat + 1'b1;
					end
				default: state <= 3'd0;
			endcase
endmodule
module rv32_d1_uncached (
	clk,
	rst,
	req,
	gnt,
	write,
	addr,
	wdata,
	be,
	size,
	rvalid,
	error,
	rdata,
	native_req,
	native_ready,
	native_write,
	native_addr,
	native_wdata,
	native_strb,
	native_rvalid,
	native_rready,
	native_rdata,
	native_error,
	mem_active,
	mem_req_valid,
	mem_req_ready,
	mem_req_write,
	mem_req_addr,
	mem_req_wdata,
	mem_req_wstrb,
	mem_req_tag,
	mem_rsp_valid,
	mem_rsp_ready,
	mem_rsp_write,
	mem_rsp_rdata,
	mem_rsp_tag,
	mem_rsp_error,
	maintenance_req,
	maintenance_done,
	maintenance_busy,
	cache_fault,
	control_addr,
	control_rdata,
	fault,
	mmio_submits,
	mmio_wait_cycles,
	ddr_uncached_count
);
	parameter integer DTCM_ADDR_WIDTH = 14;
	parameter integer DTCM_READ_LATENCY = 1;
	parameter DTCM_INIT_FILE = "";
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [32:0] DDR_BYTES = 33'h010000000;
	input wire clk;
	input wire rst;
	input wire req;
	output wire gnt;
	input wire write;
	input wire [31:0] addr;
	input wire [31:0] wdata;
	input wire [3:0] be;
	input wire [1:0] size;
	output wire rvalid;
	output wire error;
	output wire [31:0] rdata;
	output wire native_req;
	input wire native_ready;
	output wire native_write;
	output wire [31:0] native_addr;
	output wire [31:0] native_wdata;
	output wire [3:0] native_strb;
	input wire native_rvalid;
	output wire native_rready;
	input wire [31:0] native_rdata;
	input wire native_error;
	output wire mem_active;
	output wire mem_req_valid;
	input wire mem_req_ready;
	output wire mem_req_write;
	output wire [31:0] mem_req_addr;
	output wire [127:0] mem_req_wdata;
	output wire [15:0] mem_req_wstrb;
	output wire [3:0] mem_req_tag;
	input wire mem_rsp_valid;
	output wire mem_rsp_ready;
	input wire mem_rsp_write;
	input wire [127:0] mem_rsp_rdata;
	input wire [3:0] mem_rsp_tag;
	input wire mem_rsp_error;
	output reg maintenance_req;
	output reg maintenance_done;
	input wire maintenance_busy;
	input wire cache_fault;
	output wire [31:0] control_addr;
	input wire [31:0] control_rdata;
	output reg fault;
	output reg [31:0] mmio_submits;
	output reg [31:0] mmio_wait_cycles;
	output reg [31:0] ddr_uncached_count;
	reg [3:0] state;
	reg [31:0] addr_q;
	reg [31:0] data_q;
	reg [31:0] reply_q;
	reg [3:0] be_q;
	reg write_q;
	reg error_q;
	reg seen_busy;
	reg [1:0] size_q;
	wire tr;
	wire sv;
	wire se;
	wire [31:0] td;
	function automatic signed [32:0] sv2v_cast_33_signed;
		input reg signed [32:0] inp;
		sv2v_cast_33_signed = inp;
	endfunction
	wire is_tcm = (addr_q >= 32'h20000000) && ({1'b0, addr_q} < (33'h020000000 + sv2v_cast_33_signed(4 << DTCM_ADDR_WIDTH)));
	wire is_ddr = ({1'b0, addr_q} >= {1'b0, DDR_BASE}) && ({1'b0, addr_q} < ({1'b0, DDR_BASE} + DDR_BYTES));
	wire is_control = addr_q[31:5] == 27'h1800008;
	wire is_stats = addr_q[31:8] == 24'h300002;
	assign gnt = (!rst && !fault) && (state == 4'd0);
	assign rvalid = !rst && (state == 4'd9);
	assign rdata = reply_q;
	assign error = error_q;
	assign native_req = !rst && (state == 4'd4);
	assign native_addr = addr_q;
	assign native_wdata = data_q;
	assign native_strb = be_q;
	assign native_write = write_q;
	assign native_rready = !rst && (state == 4'd5);
	assign mem_active = (state == 4'd6) || (state == 4'd7);
	assign mem_req_valid = !rst && (state == 4'd6);
	assign mem_req_write = write_q;
	assign mem_req_addr = {addr_q[31:4], 4'b0000};
	assign mem_req_wdata = {96'd0, data_q} << (32 * addr_q[3:2]);
	assign mem_req_wstrb = (write_q ? {12'd0, be_q} << (4 * addr_q[3:2]) : 16'd0);
	assign mem_req_tag = 4'd8;
	assign mem_rsp_ready = !rst && (state == 4'd7);
	assign control_addr = addr_q;
	dc_realtime_core_tcm_channel #(
		.ADDR_WIDTH(DTCM_ADDR_WIDTH),
		.BASE_ADDR(32'h20000000),
		.INIT_FILE(DTCM_INIT_FILE),
		.READ_LATENCY(DTCM_READ_LATENCY),
		.EARLY_STORE_ACK(1'b1)
	) dtcm(
		.clk(clk),
		.rst(rst),
		.req_valid((state == 4'd2) && !rst),
		.req_ready(tr),
		.req_addr(addr_q),
		.req_write(write_q),
		.req_wdata(data_q),
		.req_wstrb(be_q),
		.rsp_valid(sv),
		.rsp_ready((state == 4'd3) && !rst),
		.rsp_rdata(td),
		.rsp_error(se)
	);
	always @(posedge clk)
		if (rst) begin
			state <= 4'd0;
			addr_q <= 0;
			data_q <= 0;
			reply_q <= 0;
			be_q <= 0;
			write_q <= 0;
			size_q <= 0;
			error_q <= 0;
			seen_busy <= 0;
			maintenance_req <= 0;
			maintenance_done <= 0;
			fault <= 0;
			mmio_submits <= 0;
			mmio_wait_cycles <= 0;
			ddr_uncached_count <= 0;
		end
		else begin
			maintenance_req <= 0;
			maintenance_done <= 0;
			if ((state == 4'd4) || (state == 4'd5))
				mmio_wait_cycles <= mmio_wait_cycles + 1'b1;
			case (state)
				4'd0:
					if (req && gnt) begin
						addr_q <= addr;
						data_q <= wdata;
						be_q <= be;
						write_q <= write;
						size_q <= size;
						error_q <= 0;
						reply_q <= 0;
						state <= 4'd1;
					end
				4'd1:
					if (((size_q == 3) || ((size_q == 1) && addr_q[0])) || ((size_q == 2) && (addr_q[1:0] != 0))) begin
						error_q <= 1;
						state <= 4'd9;
					end
					else if (is_control || is_stats) begin
						reply_q <= control_rdata;
						state <= 4'd9;
						if ((addr_q[1:0] != 0) || (size_q != 2))
							error_q <= 1;
						else if (write_q) begin
							if (((!is_control || (addr_q[4:0] != 0)) || (data_q != 1)) || (be_q != 15))
								error_q <= 1;
							else begin
								maintenance_req <= 1;
								seen_busy <= 0;
								state <= 4'd8;
							end
						end
					end
					else if (is_tcm)
						state <= 4'd2;
					else if (is_ddr) begin
						ddr_uncached_count <= ddr_uncached_count + 1'b1;
						state <= 4'd6;
					end
					else begin
						mmio_submits <= mmio_submits + 1'b1;
						state <= 4'd4;
					end
				4'd2:
					if (tr)
						state <= 4'd3;
				4'd3:
					if (sv) begin
						reply_q <= td;
						error_q <= se;
						state <= 4'd9;
					end
				4'd4:
					if (native_req && native_ready)
						state <= 4'd5;
				4'd5:
					if (native_rvalid && native_rready) begin
						reply_q <= native_rdata;
						error_q <= native_error;
						state <= 4'd9;
					end
				4'd6:
					if (mem_req_valid && mem_req_ready)
						state <= 4'd7;
				4'd7:
					if (mem_rsp_valid && mem_rsp_ready) begin
						if ((mem_rsp_write != write_q) || (mem_rsp_tag != 8)) begin
							fault <= 1;
							state <= 4'd10;
						end
						else begin
							reply_q <= mem_rsp_rdata[32 * addr_q[3:2]+:32];
							error_q <= mem_rsp_error;
							state <= 4'd9;
						end
					end
				4'd8: begin
					if (maintenance_busy)
						seen_busy <= 1;
					if (cache_fault) begin
						error_q <= 1;
						state <= 4'd9;
					end
					else if (seen_busy && !maintenance_busy) begin
						maintenance_done <= 1;
						state <= 4'd9;
					end
				end
				4'd9: state <= 4'd0;
				4'd10: state <= 4'd10;
				default: begin
					fault <= 1;
					state <= 4'd10;
				end
			endcase
		end
endmodule
module rv32_line128_adapter (
	clk,
	rst,
	rd_req,
	rd_gnt,
	rd_addr,
	rd_id,
	rd_valid,
	rd_ready,
	rd_data,
	rd_error,
	rd_rid,
	wr_req,
	wr_gnt,
	wr_addr,
	wr_data,
	wr_last,
	wr_id,
	b_valid,
	b_error,
	b_id,
	fault,
	mem_req_valid,
	mem_req_ready,
	mem_req_write,
	mem_req_addr,
	mem_req_wdata,
	mem_req_wstrb,
	mem_req_tag,
	mem_rsp_valid,
	mem_rsp_ready,
	mem_rsp_write,
	mem_rsp_rdata,
	mem_rsp_tag,
	mem_rsp_error
);
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [32:0] DDR_BYTES = 33'h010000000;
	input wire clk;
	input wire rst;
	input wire rd_req;
	output wire rd_gnt;
	input wire [31:0] rd_addr;
	input wire rd_id;
	output wire rd_valid;
	input wire rd_ready;
	output wire [63:0] rd_data;
	output wire rd_error;
	output wire rd_rid;
	input wire wr_req;
	output wire wr_gnt;
	input wire [31:0] wr_addr;
	input wire [63:0] wr_data;
	input wire wr_last;
	input wire wr_id;
	output wire b_valid;
	output wire b_error;
	output wire b_id;
	output reg fault;
	output wire mem_req_valid;
	input wire mem_req_ready;
	output wire mem_req_write;
	output wire [31:0] mem_req_addr;
	output wire [127:0] mem_req_wdata;
	output wire [15:0] mem_req_wstrb;
	output wire [3:0] mem_req_tag;
	input wire mem_rsp_valid;
	output wire mem_rsp_ready;
	input wire mem_rsp_write;
	input wire [127:0] mem_rsp_rdata;
	input wire [3:0] mem_rsp_tag;
	input wire mem_rsp_error;
	reg [3:0] state;
	reg [31:0] base_q;
	reg [127:0] line_payload [0:3];
	reg [7:0] line_initialized;
	reg [2:0] collect_q;
	reg [2:0] error_beat;
	reg [1:0] index_q;
	wire [127:0] selected_payload = line_payload[index_q];
	wire [1:0] selected_initialized = line_initialized[{index_q, 1'b0}+:2];
	wire [127:0] selected_line;
	assign selected_line[63:0] = (selected_initialized[0] ? selected_payload[63:0] : 64'd0);
	assign selected_line[127:64] = (selected_initialized[1] ? selected_payload[127:64] : 64'd0);
	reg write_q;
	reg id_q;
	reg error_q;
	wire legal_rd = ((rd_addr[5:0] == 0) && ({1'b0, rd_addr} >= {1'b0, DDR_BASE})) && (({1'b0, rd_addr} + 33'd64) <= ({1'b0, DDR_BASE} + DDR_BYTES));
	wire legal_wr = ((wr_addr[5:0] == 0) && ({1'b0, wr_addr} >= {1'b0, DDR_BASE})) && (({1'b0, wr_addr} + 33'd64) <= ({1'b0, DDR_BASE} + DDR_BYTES));
	assign rd_gnt = (!rst && !fault) && (state == 4'd0);
	assign wr_gnt = (!rst && !fault) && (((state == 4'd0) && !rd_req) || (state == 4'd1));
	assign rd_valid = !rst && (((state == 4'd4) || (state == 4'd5)) || (state == 4'd7));
	assign rd_data = (state == 4'd7 ? 64'd0 : (state == 4'd5 ? selected_line[127:64] : selected_line[63:0]));
	assign rd_error = (state == 4'd7) || error_q;
	assign rd_rid = id_q;
	assign b_valid = !rst && (state == 4'd6);
	assign b_error = error_q;
	assign b_id = id_q;
	assign mem_req_valid = (!rst && !fault) && (state == 4'd2);
	assign mem_req_write = write_q;
	assign mem_req_addr = base_q + {26'd0, index_q, 4'b0000};
	assign mem_req_wdata = selected_line;
	assign mem_req_wstrb = (write_q ? 16'hffff : 16'd0);
	assign mem_req_tag = {2'b00, index_q};
	assign mem_rsp_ready = !rst && (state == 4'd3);
	always @(posedge clk)
		if (rst) begin
			state <= 4'd0;
			fault <= 0;
			base_q <= 0;
			collect_q <= 0;
			index_q <= 0;
			id_q <= 0;
			write_q <= 0;
			error_q <= 0;
			error_beat <= 0;
			line_initialized <= 1'sb0;
		end
		else
			case (state)
				4'd0: begin
					error_q <= 0;
					index_q <= 0;
					if (rd_req && rd_gnt) begin
						base_q <= rd_addr;
						id_q <= rd_id;
						write_q <= 0;
						if (legal_rd)
							state <= 4'd2;
						else begin
							state <= 4'd7;
							error_beat <= 0;
						end
					end
					else if (wr_req && wr_gnt) begin
						base_q <= wr_addr;
						id_q <= wr_id;
						write_q <= 1;
						collect_q <= 1;
						line_payload[0][63:0] <= wr_data;
						line_initialized[0] <= 1'b1;
						if (!legal_wr || wr_last) begin
							fault <= 1;
							error_q <= 1;
							state <= 4'd6;
						end
						else
							state <= 4'd1;
					end
				end
				4'd1:
					if (wr_req && wr_gnt) begin
						if (((wr_addr != base_q) || (wr_id != id_q)) || (wr_last != (collect_q == 7))) begin
							fault <= 1;
							error_q <= 1;
							state <= 4'd6;
						end
						else begin
							if (collect_q[0])
								line_payload[collect_q[2:1]][127:64] <= wr_data;
							else
								line_payload[collect_q[2:1]][63:0] <= wr_data;
							line_initialized[collect_q] <= 1'b1;
							if (collect_q == 7) begin
								index_q <= 0;
								state <= 4'd2;
							end
							else
								collect_q <= collect_q + 1'b1;
						end
					end
				4'd2:
					if (mem_req_valid && mem_req_ready)
						state <= 4'd3;
				4'd3:
					if (mem_rsp_valid && mem_rsp_ready) begin
						if ((mem_rsp_write != write_q) || (mem_rsp_tag != {2'b00, index_q})) begin
							fault <= 1;
							state <= 4'd8;
						end
						else if (write_q) begin
							if (mem_rsp_error) begin
								fault <= 1;
								error_q <= 1;
								state <= 4'd6;
							end
							else if (index_q == 3)
								state <= 4'd6;
							else begin
								index_q <= index_q + 1'b1;
								state <= 4'd2;
							end
						end
						else begin
							line_payload[index_q] <= mem_rsp_rdata;
							line_initialized[{index_q, 1'b0}+:2] <= 2'b11;
							error_q <= mem_rsp_error;
							state <= 4'd4;
						end
					end
				4'd4:
					if (rd_valid && rd_ready)
						state <= 4'd5;
				4'd5:
					if (rd_valid && rd_ready) begin
						if (index_q == 3)
							state <= 4'd0;
						else begin
							index_q <= index_q + 1'b1;
							state <= 4'd2;
						end
					end
				4'd7:
					if (rd_valid && rd_ready) begin
						if (error_beat == 7)
							state <= 4'd0;
						else
							error_beat <= error_beat + 1'b1;
					end
				4'd6: state <= (fault ? 4'd8 : 4'd0);
				4'd8: state <= 4'd8;
				default: begin
					fault <= 1;
					state <= 4'd8;
				end
			endcase
endmodule
module dc_realtime_core_itcm_channel (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error
);
	parameter [31:0] ADDR_WIDTH = 14;
	parameter [31:0] BASE_ADDR = 32'h10000000;
	parameter INIT_FILE = "";
	input wire clk;
	input wire rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	reg [1:0] outstanding_count_q;
	reg read_stage1_valid_q;
	reg read_stage1_error_q;
	reg read_stage2_valid_q;
	reg read_stage2_error_q;
	wire [31:0] bram_rdata;
	reg [31:0] response_data_q [0:1];
	reg response_error_q [0:1];
	reg response_read_ptr_q;
	reg response_write_ptr_q;
	reg [1:0] response_count_q;
	wire req_accept;
	wire req_address_valid;
	wire rsp_accept;
	wire response_fifo_push;
	wire response_fifo_pop;
	assign rsp_valid = !rst && ((response_count_q != 0) || read_stage2_valid_q);
	assign rsp_rdata = (response_count_q != 0 ? response_data_q[response_read_ptr_q] : (read_stage2_error_q ? 32'd0 : bram_rdata));
	assign rsp_error = (response_count_q != 0 ? response_error_q[response_read_ptr_q] : read_stage2_error_q);
	assign rsp_accept = rsp_valid && rsp_ready;
	assign req_ready = !rst && ((outstanding_count_q < 2) || rsp_accept);
	assign req_accept = req_valid && req_ready;
	assign req_address_valid = ((req_addr >= BASE_ADDR) && (req_addr < (BASE_ADDR + (32'd4 << ADDR_WIDTH)))) && (req_addr[1:0] == 2'b00);
	assign response_fifo_pop = (response_count_q != 0) && rsp_ready;
	assign response_fifo_push = read_stage2_valid_q && !((response_count_q == 0) && rsp_ready);
	dc_realtime_core_tcm_bram #(
		.ADDR_WIDTH(ADDR_WIDTH),
		.INIT_FILE(INIT_FILE)
	) tcm_memory(
		.clk(clk),
		.enable(req_accept && req_address_valid),
		.address(req_addr[ADDR_WIDTH + 1:2]),
		.write(1'b0),
		.wdata(32'd0),
		.wstrb(4'd0),
		.rdata(bram_rdata)
	);
	always @(posedge clk)
		if (rst) begin
			outstanding_count_q <= 2'd0;
			read_stage1_valid_q <= 1'b0;
			read_stage1_error_q <= 1'b0;
			read_stage2_valid_q <= 1'b0;
			read_stage2_error_q <= 1'b0;
			response_read_ptr_q <= 1'b0;
			response_write_ptr_q <= 1'b0;
			response_count_q <= 2'd0;
			begin : sv2v_autoblock_1
				reg [31:0] index;
				for (index = 0; index < 2; index = index + 1)
					begin
						response_data_q[index] <= 32'd0;
						response_error_q[index] <= 1'b0;
					end
			end
		end
		else begin
			case ({req_accept, rsp_accept})
				2'b10: outstanding_count_q <= outstanding_count_q + 2'd1;
				2'b01: outstanding_count_q <= outstanding_count_q - 2'd1;
				default:
					;
			endcase
			read_stage1_valid_q <= req_accept;
			read_stage1_error_q <= req_accept && !req_address_valid;
			read_stage2_valid_q <= read_stage1_valid_q;
			read_stage2_error_q <= read_stage1_error_q;
			case ({response_fifo_push, response_fifo_pop})
				2'b10: response_count_q <= response_count_q + 2'd1;
				2'b01: response_count_q <= response_count_q - 2'd1;
				default:
					;
			endcase
			if (response_fifo_push) begin
				response_data_q[response_write_ptr_q] <= (read_stage2_error_q ? 32'd0 : bram_rdata);
				response_error_q[response_write_ptr_q] <= read_stage2_error_q;
				response_write_ptr_q <= response_write_ptr_q + 1'b1;
			end
			if (response_fifo_pop)
				response_read_ptr_q <= response_read_ptr_q + 1'b1;
		end
endmodule
module dc_realtime_core_tcm_bram (
	clk,
	enable,
	address,
	write,
	wdata,
	wstrb,
	rdata
);
	parameter [31:0] ADDR_WIDTH = 8;
	parameter [31:0] READ_LATENCY = 2;
	parameter INIT_FILE = "";
	input wire clk;
	input wire enable;
	input wire [ADDR_WIDTH - 1:0] address;
	input wire write;
	input wire [31:0] wdata;
	input wire [3:0] wstrb;
	output reg [31:0] rdata;
	localparam [31:0] WORDS = 1 << ADDR_WIDTH;
	(* ram_style = "block" *) reg [31:0] memory [0:WORDS - 1];
	(* syn_keep = 1 *) reg [31:0] memory_rdata_q;
	initial if (INIT_FILE != "")
		$readmemh(INIT_FILE, memory);
	generate
		if (READ_LATENCY == 2) begin : g_output_register
			always @(posedge clk) rdata <= memory_rdata_q;
		end
		else begin : g_native_sync_output
			wire [32:1] sv2v_tmp_01BCE;
			assign sv2v_tmp_01BCE = memory_rdata_q;
			always @(*) rdata = sv2v_tmp_01BCE;
		end
	endgenerate
	always @(posedge clk)
		if (enable) begin
			if (write) begin
				if (wstrb[0])
					memory[address][7:0] <= wdata[7:0];
				if (wstrb[1])
					memory[address][15:8] <= wdata[15:8];
				if (wstrb[2])
					memory[address][23:16] <= wdata[23:16];
				if (wstrb[3])
					memory[address][31:24] <= wdata[31:24];
			end
			memory_rdata_q <= memory[address];
		end
endmodule
module dc_realtime_core_tcm_channel (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error
);
	parameter [31:0] ADDR_WIDTH = 14;
	parameter [31:0] BASE_ADDR = 32'd0;
	parameter INIT_FILE = "";
	parameter [0:0] READ_ONLY = 1'b0;
	parameter [31:0] READ_LATENCY = 2;
	parameter [0:0] EARLY_STORE_ACK = 1'b0;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	reg pending_q;
	reg fast_store_q;
	reg rsp_valid_q;
	reg rsp_error_q;
	wire [31:0] bram_rdata;
	wire req_accept;
	wire bram_enable;
	wire bram_write;
	wire req_address_valid;
	assign req_ready = (!rst && !pending_q) && (!rsp_valid_q || rsp_ready);
	assign req_accept = req_valid && req_ready;
	assign req_address_valid = (req_addr >= BASE_ADDR) && (req_addr < (BASE_ADDR + (32'd4 << ADDR_WIDTH)));
	assign bram_enable = (req_accept && req_address_valid) && (!READ_ONLY || !req_write);
	assign bram_write = ((req_accept && req_address_valid) && !READ_ONLY) && req_write;
	assign rsp_valid = !rst && rsp_valid_q;
	assign rsp_rdata = (!rsp_error_q && !fast_store_q ? bram_rdata : 32'd0);
	assign rsp_error = rsp_valid && rsp_error_q;
	dc_realtime_core_tcm_bram #(
		.ADDR_WIDTH(ADDR_WIDTH),
		.READ_LATENCY(READ_LATENCY),
		.INIT_FILE(INIT_FILE)
	) tcm_memory(
		.clk(clk),
		.enable(bram_enable),
		.address(req_addr[ADDR_WIDTH + 1:2]),
		.write(bram_write),
		.wdata(req_wdata),
		.wstrb(req_wstrb),
		.rdata(bram_rdata)
	);
	always @(posedge clk)
		if (rst) begin
			pending_q <= 1'b0;
			fast_store_q <= 1'b0;
			rsp_valid_q <= 1'b0;
			rsp_error_q <= 1'b0;
		end
		else begin
			if (rsp_valid_q && rsp_ready) begin
				fast_store_q <= 1'b0;
				rsp_valid_q <= 1'b0;
				rsp_error_q <= 1'b0;
			end
			if (pending_q) begin
				pending_q <= 1'b0;
				rsp_valid_q <= 1'b1;
			end
			if (req_accept) begin
				if ((EARLY_STORE_ACK && bram_write) || (READ_LATENCY == 1)) begin
					pending_q <= 1'b0;
					rsp_valid_q <= 1'b1;
					fast_store_q <= bram_write;
				end
				else begin
					pending_q <= 1'b1;
					fast_store_q <= 1'b0;
				end
				rsp_error_q <= !req_address_valid || (READ_ONLY && req_write);
			end
		end
endmodule
module soc_async_fifo (
	w_clk,
	w_rst,
	w_valid,
	w_ready,
	w_data,
	r_clk,
	r_rst,
	r_valid,
	r_ready,
	r_data
);
	parameter integer WIDTH = 32;
	parameter integer ADDR_BITS = 4;
	input wire w_clk;
	input wire w_rst;
	input wire w_valid;
	output wire w_ready;
	input wire [WIDTH - 1:0] w_data;
	input wire r_clk;
	input wire r_rst;
	output wire r_valid;
	input wire r_ready;
	output wire [WIDTH - 1:0] r_data;
	localparam integer DEPTH = 1 << ADDR_BITS;
	localparam integer PW = ADDR_BITS + 1;
	(* syn_ramstyle = "registers" *) reg [WIDTH - 1:0] storage [0:DEPTH - 1];
	reg [PW - 1:0] wbin;
	reg [PW - 1:0] wgray;
	reg [PW - 1:0] rbin;
	reg [PW - 1:0] rgray;
	wire [PW - 1:0] wbin_next;
	wire [PW - 1:0] wgray_next;
	wire [PW - 1:0] rbin_next;
	wire [PW - 1:0] rgray_next;
	(* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [PW - 1:0] rgray_w1;
	(* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [PW - 1:0] rgray_w2;
	(* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [PW - 1:0] wgray_r1;
	(* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [PW - 1:0] wgray_r2;
	reg full;
	reg empty;
	initial if ((ADDR_BITS < 2) || (WIDTH < 1)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/cdc/soc_async_fifo.sv:21:38 - soc_async_fifo.<unnamed_block>\n msg: ", $time, "SOC_ASYNC_FIFO_PARAMETERS");
		$finish(1);
	end
	assign w_ready = !w_rst && !full;
	assign r_valid = !r_rst && !empty;
	assign r_data = storage[rbin[ADDR_BITS - 1:0]];
	assign wbin_next = wbin + {{PW - 1 {1'b0}}, w_valid && w_ready};
	assign rbin_next = rbin + {{PW - 1 {1'b0}}, r_valid && r_ready};
	assign wgray_next = (wbin_next >> 1) ^ wbin_next;
	assign rgray_next = (rbin_next >> 1) ^ rbin_next;
	always @(posedge w_clk or posedge w_rst)
		if (w_rst) begin
			wbin <= 1'sb0;
			wgray <= 1'sb0;
			full <= 0;
			rgray_w1 <= 1'sb0;
			rgray_w2 <= 1'sb0;
		end
		else begin
			rgray_w1 <= rgray;
			rgray_w2 <= rgray_w1;
			wbin <= wbin_next;
			wgray <= wgray_next;
			full <= wgray_next == {~rgray_w2[PW - 1:PW - 2], rgray_w2[PW - 3:0]};
		end
	always @(posedge w_clk)
		if (w_valid && w_ready)
			storage[wbin[ADDR_BITS - 1:0]] <= w_data;
	always @(posedge r_clk or posedge r_rst)
		if (r_rst) begin
			rbin <= 1'sb0;
			rgray <= 1'sb0;
			empty <= 1;
			wgray_r1 <= 1'sb0;
			wgray_r2 <= 1'sb0;
		end
		else begin
			wgray_r1 <= wgray;
			wgray_r2 <= wgray_r1;
			rbin <= rbin_next;
			rgray <= rgray_next;
			empty <= rgray_next == wgray_r2;
		end
endmodule
module soc_level_sync (
	clk,
	rst,
	async_level,
	level
);
	input wire clk;
	input wire rst;
	input wire async_level;
	output wire level;
	(* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg meta_q;
	(* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg sync_q;
	always @(posedge clk or posedge rst)
		if (rst) begin
			meta_q <= 0;
			sync_q <= 0;
		end
		else begin
			meta_q <= async_level;
			sync_q <= meta_q;
		end
	assign level = sync_q;
endmodule
module soc_native_cdc (
	s_clk,
	s_rst,
	s_req_valid,
	s_req_ready,
	s_req_write,
	s_req_addr,
	s_req_wdata,
	s_req_wstrb,
	s_req_tag,
	s_rsp_valid,
	s_rsp_ready,
	s_rsp_write,
	s_rsp_rdata,
	s_rsp_tag,
	s_rsp_error,
	m_clk,
	m_rst,
	m_req_valid,
	m_req_ready,
	m_req_write,
	m_req_addr,
	m_req_wdata,
	m_req_wstrb,
	m_req_tag,
	m_rsp_valid,
	m_rsp_ready,
	m_rsp_write,
	m_rsp_rdata,
	m_rsp_tag,
	m_rsp_error
);
	parameter integer ADDR_W = 32;
	parameter integer DATA_W = 128;
	parameter integer TAG_W = 4;
	parameter integer FIFO_ADDR_BITS = 4;
	input wire s_clk;
	input wire s_rst;
	input wire s_req_valid;
	output wire s_req_ready;
	input wire s_req_write;
	input wire [ADDR_W - 1:0] s_req_addr;
	input wire [DATA_W - 1:0] s_req_wdata;
	input wire [(DATA_W / 8) - 1:0] s_req_wstrb;
	input wire [TAG_W - 1:0] s_req_tag;
	output wire s_rsp_valid;
	input wire s_rsp_ready;
	output wire s_rsp_write;
	output wire [DATA_W - 1:0] s_rsp_rdata;
	output wire [TAG_W - 1:0] s_rsp_tag;
	output wire s_rsp_error;
	input wire m_clk;
	input wire m_rst;
	output wire m_req_valid;
	input wire m_req_ready;
	output wire m_req_write;
	output wire [ADDR_W - 1:0] m_req_addr;
	output wire [DATA_W - 1:0] m_req_wdata;
	output wire [(DATA_W / 8) - 1:0] m_req_wstrb;
	output wire [TAG_W - 1:0] m_req_tag;
	input wire m_rsp_valid;
	output wire m_rsp_ready;
	input wire m_rsp_write;
	input wire [DATA_W - 1:0] m_rsp_rdata;
	input wire [TAG_W - 1:0] m_rsp_tag;
	input wire m_rsp_error;
	localparam integer QW = (((1 + ADDR_W) + DATA_W) + (DATA_W / 8)) + TAG_W;
	localparam integer SW = ((1 + DATA_W) + TAG_W) + 1;
	soc_async_fifo #(
		.WIDTH(QW),
		.ADDR_BITS(FIFO_ADDR_BITS)
	) request_fifo(
		.w_clk(s_clk),
		.w_rst(s_rst),
		.w_valid(s_req_valid),
		.w_ready(s_req_ready),
		.w_data({s_req_write, s_req_addr, s_req_wdata, s_req_wstrb, s_req_tag}),
		.r_clk(m_clk),
		.r_rst(m_rst),
		.r_valid(m_req_valid),
		.r_ready(m_req_ready),
		.r_data({m_req_write, m_req_addr, m_req_wdata, m_req_wstrb, m_req_tag})
	);
	soc_async_fifo #(
		.WIDTH(SW),
		.ADDR_BITS(FIFO_ADDR_BITS)
	) response_fifo(
		.w_clk(m_clk),
		.w_rst(m_rst),
		.w_valid(m_rsp_valid),
		.w_ready(m_rsp_ready),
		.w_data({m_rsp_write, m_rsp_rdata, m_rsp_tag, m_rsp_error}),
		.r_clk(s_clk),
		.r_rst(s_rst),
		.r_valid(s_rsp_valid),
		.r_ready(s_rsp_ready),
		.r_data({s_rsp_write, s_rsp_rdata, s_rsp_tag, s_rsp_error})
	);
endmodule
module soc_reset_sync (
	clk,
	arst,
	rst
);
	input wire clk;
	input wire arst;
	output wire rst;
	(* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [2:0] release_pipe;
	always @(posedge clk or posedge arst)
		if (arst)
			release_pipe <= 3'b111;
		else
			release_pipe <= {release_pipe[1:0], 1'b0};
	assign rst = release_pipe[2];
endmodule
module npu_accel_top (
	clk,
	resident_enable,
	resident_model_epoch,
	resident_frame_epoch,
	resident_task_generation,
	resident_a_generation,
	resident_b_base,
	resident_next_a_rows,
	resident_b_columns,
	resident_b_group,
	rst,
	perip_addr,
	perip_wdata,
	perip_wen,
	perip_mask,
	legacy_perip_rdata,
	combined_perip_rdata,
	irq,
	exclusive_idle,
	dma_req_valid,
	dma_req_ready,
	dma_req_write,
	dma_req_addr,
	dma_req_wdata,
	dma_req_wstrb,
	dma_req_id,
	dma_rsp_valid,
	dma_rsp_ready,
	dma_rsp_write,
	dma_rsp_id,
	dma_rsp_rdata,
	dma_rsp_error
);
	parameter signed [31:0] ARRAY_ROWS = 4;
	parameter [0:0] IN_ORDER_TRANSPORT = 1'b0;
	parameter [0:0] RESIDENT_A_PREFETCH = 1'b0;
	parameter signed [31:0] RESIDENT_RESULT_CHUNK_COLUMNS = 256;
	parameter [0:0] RESIDENT_FULL_K_ENABLE = 1'b1;
	parameter [0:0] RESIDENT_GROUP_REUSE_ENABLE = 1'b1;
	parameter [0:0] RESIDENT_STORE_VECTOR4 = 1'b1;
	parameter [0:0] RESIDENT_PACK_PIPELINED = 1'b1;
	parameter signed [31:0] ARRAY_COLS = 4;
	parameter signed [31:0] K_TILE = 32;
	parameter signed [31:0] SPAD_LOAD_ELEMS = 8;
	parameter [0:0] A_PACKED_INT8_16 = 1'b0;
	parameter signed [31:0] ACC_W = 48;
	parameter signed [31:0] MEM_ADDR_W = 32;
	parameter signed [31:0] MEM_DATA_W = 32;
	parameter signed [31:0] MEM_ID_W = 2;
	parameter signed [31:0] MEM_OUTSTANDING = 4;
	parameter signed [31:0] DMA_READ_PIPELINE = 1;
	parameter signed [31:0] DMA_RSP_DEPTH = 2;
	parameter signed [31:0] DMA_TIMEOUT_CYCLES = 4096;
	parameter signed [31:0] CMDQ_DEPTH = 4;
	parameter signed [31:0] COMPQ_DEPTH = 4;
	parameter signed [31:0] MUL_PIPE_STAGES = 1;
	parameter [31:0] DRAM_BASE = 32'h80100000;
	parameter [32:0] DRAM_BYTES = 33'h000040000;
	input wire clk;
	input wire resident_enable;
	input wire [31:0] resident_model_epoch;
	input wire [31:0] resident_frame_epoch;
	input wire [31:0] resident_task_generation;
	input wire [31:0] resident_a_generation;
	input wire [31:0] resident_b_base;
	input wire [4:0] resident_next_a_rows;
	input wire [8:0] resident_b_columns;
	input wire [4:0] resident_b_group;
	input wire rst;
	input wire [31:0] perip_addr;
	input wire [31:0] perip_wdata;
	input wire perip_wen;
	input wire [1:0] perip_mask;
	input wire [31:0] legacy_perip_rdata;
	output wire [31:0] combined_perip_rdata;
	output wire irq;
	output wire exclusive_idle;
	output wire dma_req_valid;
	input wire dma_req_ready;
	output wire dma_req_write;
	output wire [MEM_ADDR_W - 1:0] dma_req_addr;
	output wire [MEM_DATA_W - 1:0] dma_req_wdata;
	output wire [(MEM_DATA_W / 8) - 1:0] dma_req_wstrb;
	output wire [MEM_ID_W - 1:0] dma_req_id;
	input wire dma_rsp_valid;
	output wire dma_rsp_ready;
	input wire dma_rsp_write;
	input wire [MEM_ID_W - 1:0] dma_rsp_id;
	input wire [MEM_DATA_W - 1:0] dma_rsp_rdata;
	input wire dma_rsp_error;
	(* syn_keep = 1 *) wire region_reset_u_order;
	wire core_rst;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_u_order(
		.I0(core_rst),
		.Z(region_reset_u_order)
	);
	(* syn_keep = 1 *) wire region_reset_u_resident;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_u_resident(
		.I0(core_rst),
		.Z(region_reset_u_resident)
	);
	(* syn_keep = 1 *) wire region_reset_u_mmio;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_u_mmio(
		.I0(core_rst),
		.Z(region_reset_u_mmio)
	);
	(* syn_keep = 1 *) wire region_reset_u_cmdq;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_u_cmdq(
		.I0(core_rst),
		.Z(region_reset_u_cmdq)
	);
	(* syn_keep = 1 *) wire region_reset_u_compq;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_u_compq(
		.I0(core_rst),
		.Z(region_reset_u_compq)
	);
	(* syn_keep = 1 *) wire region_reset_u_scheduler;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_u_scheduler(
		.I0(core_rst),
		.Z(region_reset_u_scheduler)
	);
	(* syn_keep = 1 *) wire region_reset_u_dma;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_u_dma(
		.I0(core_rst),
		.Z(region_reset_u_dma)
	);
	(* syn_keep = 1 *) wire region_reset_u_spad;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_u_spad(
		.I0(core_rst),
		.Z(region_reset_u_spad)
	);
	(* syn_keep = 1 *) wire region_reset_u_array;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_u_array(
		.I0(core_rst),
		.Z(region_reset_u_array)
	);
	(* syn_keep = 1 *) wire region_reset_u_postprocess;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_u_postprocess(
		.I0(core_rst),
		.Z(region_reset_u_postprocess)
	);
	localparam signed [31:0] CMD_COUNT_W = (CMDQ_DEPTH < 2 ? 1 : $clog2(CMDQ_DEPTH + 1));
	localparam signed [31:0] COMP_COUNT_W = (COMPQ_DEPTH < 2 ? 1 : $clog2(COMPQ_DEPTH + 1));
	localparam signed [31:0] SPAD_LANE_W = (ARRAY_ROWS > ARRAY_COLS ? (ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1) : (ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1));
	localparam signed [31:0] K_INDEX_W = (K_TILE > 1 ? $clog2(K_TILE) : 1);
	localparam signed [31:0] ROW_INDEX_W = (ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1);
	localparam signed [31:0] COL_INDEX_W = (ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1);
	localparam signed [31:0] OUTSTANDING_W = (MEM_OUTSTANDING > 0 ? $clog2(MEM_OUTSTANDING + 1) : 1);
	localparam signed [31:0] SAFE_MEM_ID_W = ((MEM_ID_W >= 1) && (MEM_ID_W <= 30) ? MEM_ID_W : 1);
	localparam [63:0] DMA_ID_CAPACITY = 64'd1 << SAFE_MEM_ID_W;
	function automatic signed [63:0] sv2v_cast_64_signed;
		input reg signed [63:0] inp;
		sv2v_cast_64_signed = inp;
	endfunction
	localparam [63:0] MEM_OUTSTANDING_U64 = (MEM_OUTSTANDING > 0 ? sv2v_cast_64_signed(MEM_OUTSTANDING) : 64'd0);
	localparam [64:0] DRAM_LIMIT = {33'd0, DRAM_BASE} + {32'd0, DRAM_BYTES};
	wire soft_reset_req;
	wire soft_reset_accept;
	reg soft_reset_accept_q;
	wire soft_reset_fire;
	wire cmd_push_valid;
	wire cmd_push_ready;
	wire [347:0] cmd_push_data;
	wire cmd_pop_valid;
	wire cmd_pop_ready;
	wire [347:0] cmd_pop_data;
	wire [CMD_COUNT_W - 1:0] cmd_level;
	wire cmd_full;
	wire cmd_empty;
	wire completion_reserve_valid;
	wire completion_reserve_ready;
	wire completion_release_reservation;
	wire completion_enqueue_valid;
	wire completion_enqueue_ready;
	wire [136:0] completion_enqueue_data;
	wire completion_head_valid;
	wire completion_pop;
	wire [136:0] completion_head_data;
	wire [COMP_COUNT_W - 1:0] completion_level;
	wire [COMP_COUNT_W - 1:0] unused_completion_reserved;
	wire completion_empty;
	wire completion_full;
	wire completion_enqueued;
	wire scheduler_active;
	wire error_event_valid;
	wire [7:0] error_event_code;
	wire [1:0] unused_irq_status;
	wire [11:0] unused_error_status;
	wire [31:0] unused_error_tag;
	wire [31:0] unused_reject_count;
	wire _unused_leaf_observability = &{1'b0, unused_completion_reserved, unused_irq_status, unused_error_status, unused_error_tag, unused_reject_count};
	wire dma_job_valid;
	wire dma_job_ready;
	wire [100:0] dma_job_data;
	wire dma_job_done;
	wire dma_job_error;
	wire dma_partial_output;
	wire [7:0] dma_error_code;
	wire [OUTSTANDING_W - 1:0] dma_outstanding;
	wire store_elem_valid;
	wire store_elem_ready;
	wire store_elem_vector4;
	wire [127:0] store_elem_vector_data;
	wire signed [31:0] store_elem_data;
	wire [2:0] store_elem_bytes;
	wire [15:0] store_elem_row;
	wire [15:0] store_elem_col;
	wire spad_owner_valid;
	wire spad_owner_is_b;
	wire spad_owner_bank;
	wire [1:0] spad_owner_state;
	wire [3:0] spad_a_owner;
	wire [3:0] spad_b_owner;
	wire spad_protocol_error;
	wire spad_compute_read_valid;
	wire spad_compute_bank;
	wire [K_INDEX_W - 1:0] spad_compute_k;
	wire spad_compute_read_data_valid;
	wire signed [(ARRAY_ROWS * 16) - 1:0] spad_a_vector;
	wire signed [(ARRAY_COLS * 16) - 1:0] spad_b_vector;
	wire spad_write_valid;
	wire spad_write_is_b;
	wire spad_write_bank;
	wire [SPAD_LANE_W - 1:0] spad_write_lane;
	wire [K_INDEX_W - 1:0] spad_write_k;
	wire spad_write_input_int16;
	wire signed [(SPAD_LOAD_ELEMS * 16) - 1:0] spad_write_data;
	wire [(SPAD_LOAD_ELEMS > 1 ? $clog2(SPAD_LOAD_ELEMS + 1) : 1) - 1:0] spad_write_count;
	wire array_start_valid;
	wire array_start_ready;
	wire [15:0] array_k_len;
	wire [ARRAY_ROWS - 1:0] array_row_mask;
	wire [ARRAY_COLS - 1:0] array_col_mask;
	wire array_continue_acc;
	wire array_input_int16;
	wire array_feed_valid;
	wire array_feed_ready;
	wire array_done;
	wire signed [(ARRAY_ROWS * 16) - 1:0] array_feed_a;
	wire signed [(ARRAY_COLS * 16) - 1:0] array_feed_b;
	wire [ROW_INDEX_W - 1:0] array_acc_read_row;
	wire [COL_INDEX_W - 1:0] array_acc_read_col;
	wire signed [ACC_W - 1:0] array_acc_rdata;
	wire post_in_valid;
	wire post_in_ready;
	wire signed [ACC_W - 1:0] post_in_value;
	wire [1:0] post_output_fmt;
	wire [1:0] post_activation;
	wire post_rounding;
	wire [5:0] post_shift;
	wire signed [31:0] post_clamp_min;
	wire signed [31:0] post_clamp_max;
	wire post_out_valid;
	wire post_out_ready;
	wire signed [31:0] post_out_value;
	wire [2:0] post_out_bytes;
	reg resident_mode_q;
	wire res_committed_ready;
	wire [10:0] res_read_k;
	wire resident_command_eligible = (((((resident_enable === 1'b1) && !cmd_pop_data[203]) && (cmd_pop_data[251-:16] <= 16)) && (cmd_pop_data[235-:16] <= resident_b_columns)) && (cmd_pop_data[235-:16] <= 256)) && (cmd_pop_data[219-:16] <= 1152);
	reg [31:0] res_model;
	reg [31:0] res_frame;
	reg [31:0] res_task;
	reg [31:0] res_agen;
	reg [31:0] res_a_base;
	reg [31:0] res_b_base;
	reg [5:0] res_rows;
	reg [8:0] res_columns;
	reg [10:0] res_k;
	wire [10:0] res_k_base;
	reg [4:0] res_b_group;
	wire [4:0] res_scheduler_n_group;
	wire res_claim;
	wire res_poison;
	wire res_vector_valid;
	wire legacy_unpack_enable;
	wire result_array_read_enable;
	wire result_protocol_error;
	wire [ROW_INDEX_W - 1:0] result_array_read_row;
	wire [(ARRAY_COLS * ACC_W) - 1:0] result_array_row_data;
	wire [255:0] res_a_vector;
	wire [127:0] res_b_vector;
	wire sched_job_valid;
	wire sched_job_ready;
	wire sched_job_done;
	wire sched_job_error;
	wire [100:0] sched_job;
	wire [7:0] sched_error_code;
	wire legacy_read_valid;
	wire legacy_spad_error;
	wire unpack_ready;
	wire signed [(ARRAY_ROWS * 16) - 1:0] legacy_a_vector;
	wire signed [(ARRAY_COLS * 16) - 1:0] legacy_b_vector;
	wire [15:0] unpack_full_row;
	wire [15:0] unpack_full_col;
	reg [4:0] res_next_a_rows;
	wire order_ready;
	wire order_idle;
	wire order_poison;
	wire ordered_valid;
	wire ordered_ready;
	wire ordered_write;
	wire ordered_error;
	wire [MEM_ID_W - 1:0] ordered_id;
	wire [MEM_ID_W - 1:0] physical_id;
	wire [MEM_DATA_W - 1:0] ordered_data;
	wire [MEM_DATA_W - 1:0] physical_wdata;
	wire physical_req_valid;
	wire physical_req_ready;
	wire physical_write;
	wire [MEM_ADDR_W - 1:0] physical_addr;
	wire [(MEM_DATA_W / 8) - 1:0] physical_strobe;
	wire [OUTSTANDING_W - 1:0] ordered_owned;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [5:0] sv2v_cast_6;
		input reg [5:0] inp;
		sv2v_cast_6 = inp;
	endfunction
	function automatic [10:0] sv2v_cast_11;
		input reg [10:0] inp;
		sv2v_cast_11 = inp;
	endfunction
	always @(posedge clk)
		if (core_rst) begin
			resident_mode_q <= 0;
			res_next_a_rows <= 0;
			res_model <= 0;
			res_frame <= 0;
			res_task <= 0;
			res_agen <= 0;
			res_a_base <= 0;
			res_b_base <= 0;
			res_rows <= 0;
			res_columns <= 0;
			res_k <= 0;
			res_b_group <= 0;
		end
		else if (cmd_pop_valid && cmd_pop_ready) begin
			resident_mode_q <= resident_command_eligible;
			res_next_a_rows <= ((resident_command_eligible && (cmd_pop_data[251-:16] == 16)) && (cmd_pop_data[202-:32] == sv2v_cast_32(cmd_pop_data[219-:16])) ? resident_next_a_rows : 5'd0);
			res_model <= resident_model_epoch;
			res_frame <= resident_frame_epoch;
			res_task <= resident_task_generation;
			res_agen <= resident_a_generation;
			res_a_base <= cmd_pop_data[347-:32];
			res_b_base <= resident_b_base;
			res_rows <= sv2v_cast_6(cmd_pop_data[251-:16]);
			res_columns <= resident_b_columns;
			res_k <= sv2v_cast_11(cmd_pop_data[219-:16]);
			res_b_group <= resident_b_group;
		end
	assign spad_protocol_error = (legacy_spad_error || res_poison) || result_protocol_error;
	assign spad_compute_read_data_valid = (resident_mode_q ? res_vector_valid : legacy_read_valid);
	assign spad_a_vector = (resident_mode_q ? res_a_vector : legacy_a_vector);
	assign spad_b_vector = (resident_mode_q ? res_b_vector : legacy_b_vector);
	npu_response_order #(
		.DATA_W(MEM_DATA_W),
		.ID_W(MEM_ID_W),
		.SLOTS(MEM_OUTSTANDING),
		.IN_ORDER_TRANSPORT(IN_ORDER_TRANSPORT)
	) u_order(
		.clk(clk),
		.rst(region_reset_u_order),
		.issue_valid(physical_req_valid && dma_req_ready),
		.issue_ready(order_ready),
		.issue_id(physical_id),
		.issue_write(physical_write),
		.rsp_valid(dma_rsp_valid),
		.rsp_ready(dma_rsp_ready),
		.rsp_id(dma_rsp_id),
		.rsp_write(dma_rsp_write),
		.rsp_error(dma_rsp_error),
		.rsp_data(dma_rsp_rdata),
		.out_valid(ordered_valid),
		.out_ready(ordered_ready),
		.out_id(ordered_id),
		.out_write(ordered_write),
		.out_error(ordered_error),
		.out_data(ordered_data),
		.drained(),
		.idle(order_idle),
		.protocol_poison(order_poison),
		.owned(ordered_owned)
	);
	assign dma_req_valid = physical_req_valid && order_ready;
	assign physical_req_ready = dma_req_ready && order_ready;
	assign dma_req_write = physical_write;
	assign dma_req_addr = physical_addr;
	assign dma_req_wdata = physical_wdata;
	assign dma_req_wstrb = physical_strobe;
	assign dma_req_id = physical_id;
	npu_resident_operand_adapter #(
		.DRAM_BASE(DRAM_BASE),
		.DRAM_BYTES(DRAM_BYTES),
		.PIPELINED_FILL(RESIDENT_PACK_PIPELINED),
		.PREFETCH_A(RESIDENT_A_PREFETCH)
	) u_resident(
		.clk(clk),
		.rst(region_reset_u_resident),
		.mode_resident(resident_mode_q),
		.model_epoch(res_model),
		.frame_epoch(res_frame),
		.task_generation(res_task),
		.a_generation(res_agen),
		.next_a_rows(res_next_a_rows),
		.a_base(res_a_base),
		.b_page_base(res_b_base),
		.a_rows(res_rows),
		.b_columns(res_columns),
		.k_length(res_k),
		.b_group(res_b_group + res_scheduler_n_group),
		.sched_valid(sched_job_valid),
		.sched_ready(sched_job_ready),
		.sched_job(sched_job),
		.sched_done(sched_job_done),
		.sched_error(sched_job_error),
		.sched_error_code(sched_error_code),
		.physical_valid(dma_job_valid),
		.physical_ready(dma_job_ready),
		.physical_job(dma_job_data),
		.physical_done(dma_job_done),
		.physical_error(dma_job_error),
		.physical_error_code(dma_error_code),
		.outstanding(dma_outstanding),
		.order_idle(order_idle),
		.order_poison(order_poison),
		.unpack_valid(spad_write_valid),
		.unpack_ready(unpack_ready),
		.unpack_row(unpack_full_row),
		.unpack_col(unpack_full_col),
		.unpack_count(spad_write_count),
		.unpack_data(spad_write_data),
		.legacy_unpack_enable(legacy_unpack_enable),
		.claim(resident_mode_q && res_claim),
		.release_compute(((resident_mode_q && spad_owner_valid) && spad_owner_is_b) && (spad_owner_state == 0)),
		.read_valid(resident_mode_q && spad_compute_read_valid),
		.read_k(res_read_k),
		.committed_operands_ready(res_committed_ready),
		.vector_valid(res_vector_valid),
		.a_vector(res_a_vector),
		.b_vector(res_b_vector),
		.protocol_poison(res_poison)
	);
	assign exclusive_idle = ((cmd_empty && !completion_head_valid) && !scheduler_active) && (dma_outstanding == 0);
	assign completion_empty = !completion_head_valid;
	function automatic signed [COMP_COUNT_W - 1:0] sv2v_cast_5B47C_signed;
		input reg signed [COMP_COUNT_W - 1:0] inp;
		sv2v_cast_5B47C_signed = inp;
	endfunction
	localparam [COMP_COUNT_W - 1:0] COMPQ_DEPTH_COUNT = sv2v_cast_5B47C_signed(COMPQ_DEPTH);
	assign completion_full = completion_level == COMPQ_DEPTH_COUNT;
	assign completion_enqueued = completion_enqueue_valid && completion_enqueue_ready;
	assign completion_release_reservation = 1'b0;
	assign error_event_valid = completion_enqueued && (completion_enqueue_data[104-:8] != 8'd0);
	assign error_event_code = completion_enqueue_data[104-:8];
	assign soft_reset_accept = !scheduler_active && (dma_outstanding == {OUTSTANDING_W {1'sb0}});
	assign soft_reset_fire = soft_reset_req && soft_reset_accept_q;
	assign core_rst = rst || soft_reset_fire;
	always @(posedge clk)
		if (rst)
			soft_reset_accept_q <= 1'b0;
		else
			soft_reset_accept_q <= soft_reset_accept;
	initial begin
		if (((ARRAY_ROWS < 2) || (ARRAY_ROWS > 16)) || ((ARRAY_ROWS & (ARRAY_ROWS - 1)) != 0)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:289:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: ARRAY_ROWS must be a power of two from 2 to 16");
			$finish(1);
		end
		if (((ARRAY_COLS < 2) || (ARRAY_COLS > 16)) || ((ARRAY_COLS & (ARRAY_COLS - 1)) != 0)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:292:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: ARRAY_COLS must be a power of two from 2 to 16");
			$finish(1);
		end
		if (((K_TILE < 8) || (K_TILE > 256)) || ((K_TILE & (K_TILE - 1)) != 0)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:294:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: K_TILE must be a power of two from 8 to 256");
			$finish(1);
		end
		if ((ACC_W < 48) || (ACC_W > 64)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:296:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: ACC_W must be in [48,64]");
			$finish(1);
		end
		if ((MUL_PIPE_STAGES != 1) && (MUL_PIPE_STAGES != 2)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:298:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: MUL_PIPE_STAGES must be 1 or 2");
			$finish(1);
		end
		if (((MEM_DATA_W != 32) && (MEM_DATA_W != 64)) && (MEM_DATA_W != 128)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:300:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: MEM_DATA_W must be 32, 64, or 128");
			$finish(1);
		end
		if (MEM_ADDR_W != 32) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:302:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: v1 requires MEM_ADDR_W=32");
			$finish(1);
		end
		if ((MEM_ID_W < 1) || (MEM_ID_W > 30)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:304:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: MEM_ID_W must be in [1,30]");
			$finish(1);
		end
		if ((MEM_OUTSTANDING < 1) || (MEM_OUTSTANDING_U64 > DMA_ID_CAPACITY)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:306:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: MEM_OUTSTANDING must be in [1,2**MEM_ID_W]");
			$finish(1);
		end
		if (DMA_TIMEOUT_CYCLES < 0) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:308:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: DMA_TIMEOUT_CYCLES must be nonnegative");
			$finish(1);
		end
		if (((CMDQ_DEPTH < 2) || (CMDQ_DEPTH > 128)) || ((CMDQ_DEPTH & (CMDQ_DEPTH - 1)) != 0)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:311:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: CMDQ_DEPTH must be a power of two from 2 to 128");
			$finish(1);
		end
		if (((COMPQ_DEPTH < 2) || (COMPQ_DEPTH > 128)) || ((COMPQ_DEPTH & (COMPQ_DEPTH - 1)) != 0)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:314:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: COMPQ_DEPTH must be a power of two from 2 to 128");
			$finish(1);
		end
		if ((DRAM_BYTES == 0) || (DRAM_LIMIT > 65'h00000000100000000)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_accel_top.sv:316:7 - npu_accel_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_accel_top: DRAM aperture must be positive and end at or below 2**32");
			$finish(1);
		end
	end
	npu_mmio_overlay #(
		.ARRAY_ROWS(ARRAY_ROWS),
		.ARRAY_COLS(ARRAY_COLS),
		.K_TILE(K_TILE),
		.MEM_DATA_W(MEM_DATA_W),
		.CMDQ_DEPTH(CMDQ_DEPTH),
		.COMPQ_DEPTH(COMPQ_DEPTH)
	) u_mmio(
		.clk(clk),
		.rst(region_reset_u_mmio),
		.perip_addr(perip_addr),
		.perip_wdata(perip_wdata),
		.perip_wen(perip_wen),
		.perip_mask(perip_mask),
		.legacy_perip_rdata(legacy_perip_rdata),
		.combined_perip_rdata(combined_perip_rdata),
		.cmd_push_valid(cmd_push_valid),
		.cmd_push_ready(cmd_push_ready),
		.cmd_push_data(cmd_push_data),
		.cmd_level(cmd_level),
		.cmd_empty(cmd_empty),
		.cmd_full(cmd_full),
		.completion_head_valid(completion_head_valid),
		.completion_head_data(completion_head_data),
		.completion_enqueued(completion_enqueued),
		.completion_pop(completion_pop),
		.completion_level(completion_level),
		.completion_empty(completion_empty),
		.completion_full(completion_full),
		.active(scheduler_active),
		.error_event_valid(error_event_valid),
		.error_event_code(error_event_code),
		.error_event_tag(completion_enqueue_data[136-:32]),
		.soft_reset_req(soft_reset_req),
		.soft_reset_accept(soft_reset_accept),
		.irq_status(unused_irq_status),
		.error_status(unused_error_status),
		.error_tag(unused_error_tag),
		.reject_count(unused_reject_count),
		.irq(irq)
	);
	npu_cmd_queue #(.DEPTH(CMDQ_DEPTH)) u_cmdq(
		.clk(clk),
		.rst(region_reset_u_cmdq),
		.push_valid(cmd_push_valid),
		.push_ready(cmd_push_ready),
		.push_data(cmd_push_data),
		.pop_valid(cmd_pop_valid),
		.pop_ready(cmd_pop_ready),
		.pop_data(cmd_pop_data),
		.level(cmd_level),
		.full(cmd_full),
		.empty(cmd_empty)
	);
	npu_completion_queue #(.DEPTH(COMPQ_DEPTH)) u_compq(
		.clk(clk),
		.rst(region_reset_u_compq),
		.reserve_valid(completion_reserve_valid),
		.reserve_ready(completion_reserve_ready),
		.release_reservation(completion_release_reservation),
		.enqueue_valid(completion_enqueue_valid),
		.enqueue_ready(completion_enqueue_ready),
		.enqueue_data(completion_enqueue_data),
		.head_valid(completion_head_valid),
		.head_data(completion_head_data),
		.pop(completion_pop),
		.level(completion_level),
		.reserved(unused_completion_reserved)
	);
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	npu_scheduler #(
		.RESULT_CHUNK_COLUMNS(RESIDENT_RESULT_CHUNK_COLUMNS),
		.STORE_VECTOR4_ENABLE(RESIDENT_STORE_VECTOR4 && (MEM_DATA_W == 128)),
		.RESIDENT_GROUP_REUSE_ENABLE(RESIDENT_GROUP_REUSE_ENABLE),
		.ARRAY_ROWS(ARRAY_ROWS),
		.ARRAY_COLS(ARRAY_COLS),
		.K_TILE(K_TILE),
		.ACC_W(ACC_W),
		.DRAM_BASE(DRAM_BASE),
		.DRAM_BYTES(DRAM_BYTES),
		.RESULT_PAGE_STORE(((((ARRAY_ROWS == 16) && (ARRAY_COLS == 8)) && (ACC_W == 48)) && (MEM_DATA_W == 128)) && (MEM_OUTSTANDING <= 16)),
		.RESIDENT_FULL_K_ENABLE((RESIDENT_FULL_K_ENABLE && (ARRAY_ROWS == 16)) && (ARRAY_COLS == 8))
	) u_scheduler(
		.clk(clk),
		.rst(region_reset_u_scheduler),
		.cmd_valid(cmd_pop_valid),
		.cmd_ready(cmd_pop_ready),
		.result_page_enable(resident_command_eligible),
		.resident_compute_mode(resident_command_eligible),
		.resident_read_k(res_read_k),
		.resident_operands_ready(res_committed_ready),
		.result_context({resident_model_epoch, resident_frame_epoch, resident_task_generation, resident_a_generation}),
		.result_dma_outstanding(sv2v_cast_5(dma_outstanding)),
		.result_order_idle(order_idle),
		.result_order_poison(order_poison),
		.result_array_read_enable(result_array_read_enable),
		.result_array_read_row(result_array_read_row),
		.result_array_row_data(result_array_row_data),
		.result_protocol_error(result_protocol_error),
		.cmd_data(cmd_pop_data),
		.reserve_valid(completion_reserve_valid),
		.reserve_ready(completion_reserve_ready),
		.completion_valid(completion_enqueue_valid),
		.completion_ready(completion_enqueue_ready),
		.completion_data(completion_enqueue_data),
		.dma_job_valid(sched_job_valid),
		.dma_job_ready(sched_job_ready),
		.dma_job_data(sched_job),
		.dma_job_done(sched_job_done),
		.dma_job_error(sched_job_error),
		.dma_error_code(sched_error_code),
		.dma_partial_output(dma_partial_output),
		.spad_owner_valid(spad_owner_valid),
		.spad_owner_is_b(spad_owner_is_b),
		.spad_owner_bank(spad_owner_bank),
		.spad_owner_state(spad_owner_state),
		.spad_a_owner(spad_a_owner),
		.spad_b_owner(spad_b_owner),
		.spad_protocol_error(spad_protocol_error),
		.spad_compute_read_valid(spad_compute_read_valid),
		.spad_compute_bank(spad_compute_bank),
		.spad_compute_k(spad_compute_k),
		.spad_compute_read_data_valid(spad_compute_read_data_valid),
		.spad_a_vector(spad_a_vector),
		.spad_b_vector(spad_b_vector),
		.array_start_valid(array_start_valid),
		.array_start_ready(array_start_ready),
		.array_k_len(array_k_len),
		.array_row_mask(array_row_mask),
		.array_col_mask(array_col_mask),
		.array_continue_acc(array_continue_acc),
		.array_input_int16(array_input_int16),
		.array_feed_valid(array_feed_valid),
		.array_feed_ready(array_feed_ready),
		.array_feed_a(array_feed_a),
		.array_feed_b(array_feed_b),
		.array_done(array_done),
		.array_acc_read_row(array_acc_read_row),
		.array_acc_read_col(array_acc_read_col),
		.array_acc_rdata(array_acc_rdata),
		.post_in_valid(post_in_valid),
		.post_in_ready(post_in_ready),
		.post_in_value(post_in_value),
		.post_output_fmt(post_output_fmt),
		.post_activation(post_activation),
		.post_rounding(post_rounding),
		.post_shift(post_shift),
		.post_clamp_min(post_clamp_min),
		.post_clamp_max(post_clamp_max),
		.post_out_valid(post_out_valid),
		.post_out_ready(post_out_ready),
		.post_out_value(post_out_value),
		.post_out_bytes(post_out_bytes),
		.store_elem_vector4(store_elem_vector4),
		.store_elem_vector_data(store_elem_vector_data),
		.store_elem_valid(store_elem_valid),
		.store_elem_ready(store_elem_ready),
		.store_elem_data(store_elem_data),
		.store_elem_bytes(store_elem_bytes),
		.store_elem_row(store_elem_row),
		.store_elem_col(store_elem_col),
		.resident_k_base(res_k_base),
		.resident_claim(res_claim),
		.resident_n_group(res_scheduler_n_group),
		.active(scheduler_active)
	);
	npu_dma_engine #(
		.STORE_VECTOR4_ENABLE(RESIDENT_STORE_VECTOR4 && (MEM_DATA_W == 128)),
		.MEM_ADDR_W(MEM_ADDR_W),
		.MEM_DATA_W(MEM_DATA_W),
		.MEM_ID_W(MEM_ID_W),
		.MEM_OUTSTANDING(MEM_OUTSTANDING),
		.ARRAY_ROWS(ARRAY_ROWS),
		.ARRAY_COLS(ARRAY_COLS),
		.K_TILE(K_TILE),
		.READ_REQ_PIPELINE(DMA_READ_PIPELINE),
		.RSP_FIFO_DEPTH(DMA_RSP_DEPTH),
		.DMA_TIMEOUT_CYCLES(DMA_TIMEOUT_CYCLES),
		.SPAD_VECTOR_ELEMS(SPAD_LOAD_ELEMS),
		.A_PACKED_INT8_16(A_PACKED_INT8_16)
	) u_dma(
		.clk(clk),
		.rst(region_reset_u_dma),
		.job_valid(dma_job_valid),
		.job_ready(dma_job_ready),
		.job_data(dma_job_data),
		.dma_req_valid(physical_req_valid),
		.dma_req_ready(physical_req_ready),
		.dma_req_write(physical_write),
		.dma_req_addr(physical_addr),
		.dma_req_wdata(physical_wdata),
		.dma_req_wstrb(physical_strobe),
		.dma_req_id(physical_id),
		.dma_rsp_valid(ordered_valid),
		.dma_rsp_ready(ordered_ready),
		.dma_rsp_write(ordered_write),
		.dma_rsp_id(ordered_id),
		.dma_rsp_rdata(ordered_data),
		.dma_rsp_error(ordered_error),
		.store_elem_vector4(store_elem_vector4),
		.store_elem_vector_data(store_elem_vector_data),
		.store_elem_valid(store_elem_valid),
		.store_elem_ready(store_elem_ready),
		.store_elem_data(store_elem_data),
		.store_elem_bytes(store_elem_bytes),
		.store_elem_row(store_elem_row),
		.store_elem_col(store_elem_col),
		.spad_write_valid(spad_write_valid),
		.spad_write_ready(unpack_ready),
		.spad_write_is_b(spad_write_is_b),
		.spad_write_bank(spad_write_bank),
		.spad_write_lane(spad_write_lane),
		.spad_write_k(spad_write_k),
		.spad_write_input_int16(spad_write_input_int16),
		.spad_write_data(spad_write_data),
		.spad_write_count(spad_write_count),
		.spad_write_row_full(unpack_full_row),
		.spad_write_col_full(unpack_full_col),
		.job_done(dma_job_done),
		.job_error(dma_job_error),
		.error_code(dma_error_code),
		.partial_output(dma_partial_output),
		.outstanding(dma_outstanding)
	);
	npu_scratchpad #(
		.ARRAY_ROWS(ARRAY_ROWS),
		.ARRAY_COLS(ARRAY_COLS),
		.K_TILE(K_TILE),
		.MAX_ELEM_W(16),
		.DMA_VECTOR_ELEMS(SPAD_LOAD_ELEMS),
		.A_PACKED_INT8_16(A_PACKED_INT8_16)
	) u_spad(
		.clk(clk),
		.rst(region_reset_u_spad),
		.owner_req_valid(spad_owner_valid),
		.owner_req_is_b(spad_owner_is_b),
		.owner_req_bank(spad_owner_bank),
		.owner_req_state(spad_owner_state),
		.dma_write_valid(spad_write_valid && legacy_unpack_enable),
		.dma_is_b(spad_write_is_b),
		.dma_bank(spad_write_bank),
		.dma_lane(spad_write_lane),
		.dma_k(spad_write_k),
		.dma_input_int16(spad_write_input_int16),
		.dma_data(spad_write_data),
		.dma_count(spad_write_count),
		.compute_read_valid(spad_compute_read_valid && !resident_mode_q),
		.compute_bank(spad_compute_bank),
		.compute_k(spad_compute_k),
		.a_vector(legacy_a_vector),
		.b_vector(legacy_b_vector),
		.compute_read_data_valid(legacy_read_valid),
		.a_owner(spad_a_owner),
		.b_owner(spad_b_owner),
		.protocol_error(legacy_spad_error)
	);
	npu_systolic_array #(
		.ARRAY_ROWS(ARRAY_ROWS),
		.ARRAY_COLS(ARRAY_COLS),
		.ACC_W(ACC_W),
		.MUL_PIPE_STAGES(MUL_PIPE_STAGES)
	) u_array(
		.clk(clk),
		.rst(region_reset_u_array),
		.start_valid(array_start_valid),
		.start_ready(array_start_ready),
		.k_len(array_k_len),
		.row_mask(array_row_mask),
		.col_mask(array_col_mask),
		.continue_acc(array_continue_acc),
		.input_int16(array_input_int16),
		.feed_valid(array_feed_valid),
		.feed_ready(array_feed_ready),
		.feed_a(array_feed_a),
		.feed_b(array_feed_b),
		.tile_done(array_done),
		.acc_read_row((result_array_read_enable ? result_array_read_row : array_acc_read_row)),
		.acc_read_col(array_acc_read_col),
		.acc_rdata(array_acc_rdata),
		.acc_row_read_enable(result_array_read_enable),
		.acc_row_vector(result_array_row_data)
	);
	npu_postprocess #(.ACC_W(ACC_W)) u_postprocess(
		.clk(clk),
		.rst(region_reset_u_postprocess),
		.in_valid(post_in_valid),
		.in_ready(post_in_ready),
		.in_value(post_in_value),
		.output_fmt(post_output_fmt),
		.activation(post_activation),
		.rounding(post_rounding),
		.shift(post_shift),
		.clamp_min(post_clamp_min),
		.clamp_max(post_clamp_max),
		.out_valid(post_out_valid),
		.out_ready(post_out_ready),
		.out_value(post_out_value),
		.out_bytes(post_out_bytes)
	);
endmodule
module npu_cmd_queue (
	clk,
	rst,
	push_valid,
	push_ready,
	push_data,
	pop_valid,
	pop_ready,
	pop_data,
	level,
	full,
	empty
);
	parameter signed [31:0] DEPTH = 4;
	input wire clk;
	input wire rst;
	input wire push_valid;
	output wire push_ready;
	input wire [347:0] push_data;
	output wire pop_valid;
	input wire pop_ready;
	output wire [347:0] pop_data;
	output reg [$clog2(DEPTH + 1) - 1:0] level;
	output wire full;
	output wire empty;
	localparam signed [31:0] PTR_W = (DEPTH >= 2 ? $clog2(DEPTH) : 1);
	localparam signed [31:0] LEVEL_W = $clog2(DEPTH + 1);
	function automatic signed [LEVEL_W - 1:0] sv2v_cast_1494C_signed;
		input reg signed [LEVEL_W - 1:0] inp;
		sv2v_cast_1494C_signed = inp;
	endfunction
	localparam [LEVEL_W - 1:0] DEPTH_COUNT = sv2v_cast_1494C_signed(DEPTH);
	generate
		if ((DEPTH < 2) || ((DEPTH & (DEPTH - 1)) != 0)) begin : g_invalid_depth
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_cmd_queue.sv:16:15 - npu_cmd_queue.g_invalid_depth.<unnamed_block>\n msg: ", $time, "npu_cmd_queue: DEPTH must be a power of two and at least 2");
				$finish(1);
			end
		end
	endgenerate
	reg [347:0] mem [0:DEPTH - 1];
	reg [PTR_W - 1:0] rd_ptr;
	reg [PTR_W - 1:0] wr_ptr;
	wire push_fire;
	wire pop_fire;
	assign empty = level == {$clog2(DEPTH + 1) {1'sb0}};
	assign full = level == DEPTH_COUNT;
	assign pop_valid = !empty;
	assign pop_data = mem[rd_ptr];
	assign push_ready = !full || (pop_valid && pop_ready);
	assign push_fire = push_valid && push_ready;
	assign pop_fire = pop_valid && pop_ready;
	always @(posedge clk)
		if (rst) begin
			rd_ptr <= 1'sb0;
			wr_ptr <= 1'sb0;
			level <= 1'sb0;
		end
		else begin
			if (push_fire) begin
				mem[wr_ptr] <= push_data;
				wr_ptr <= wr_ptr + 1'b1;
			end
			if (pop_fire)
				rd_ptr <= rd_ptr + 1'b1;
			case ({push_fire, pop_fire})
				2'b10: level <= level + 1'b1;
				2'b01: level <= level - 1'b1;
				default: level <= level;
			endcase
		end
endmodule
module npu_completion_queue (
	clk,
	rst,
	reserve_valid,
	reserve_ready,
	release_reservation,
	enqueue_valid,
	enqueue_ready,
	enqueue_data,
	head_valid,
	head_data,
	pop,
	level,
	reserved
);
	parameter signed [31:0] DEPTH = 4;
	input wire clk;
	input wire rst;
	input wire reserve_valid;
	output wire reserve_ready;
	input wire release_reservation;
	input wire enqueue_valid;
	output wire enqueue_ready;
	input wire [136:0] enqueue_data;
	output wire head_valid;
	output wire [136:0] head_data;
	input wire pop;
	function automatic integer npu_completion_count_width;
		input integer depth;
		if (depth < 2)
			npu_completion_count_width = 1;
		else
			npu_completion_count_width = $clog2(depth + 1);
	endfunction
	output reg [npu_completion_count_width(DEPTH) - 1:0] level;
	output reg [npu_completion_count_width(DEPTH) - 1:0] reserved;
	localparam signed [31:0] COUNT_W = npu_completion_count_width(DEPTH);
	function automatic signed [COUNT_W - 1:0] sv2v_cast_D4579_signed;
		input reg signed [COUNT_W - 1:0] inp;
		sv2v_cast_D4579_signed = inp;
	endfunction
	localparam [COUNT_W - 1:0] DEPTH_COUNT = sv2v_cast_D4579_signed(DEPTH);
	function automatic signed [((COUNT_W + 0) >= 0 ? COUNT_W + 1 : 1 - (COUNT_W + 0)) - 1:0] sv2v_cast_AE0F9_signed;
		input reg signed [((COUNT_W + 0) >= 0 ? COUNT_W + 1 : 1 - (COUNT_W + 0)) - 1:0] inp;
		sv2v_cast_AE0F9_signed = inp;
	endfunction
	localparam [COUNT_W:0] DEPTH_CAPACITY = sv2v_cast_AE0F9_signed(DEPTH);
	generate
		if ((DEPTH < 2) || ((DEPTH & (DEPTH - 1)) != 0)) begin : g_invalid_depth
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_completion_queue.sv:30:15 - npu_completion_queue.g_invalid_depth.<unnamed_block>\n msg: ", $time, "npu_completion_queue: DEPTH must be a power of two and at least 2");
				$finish(1);
			end
			assign reserve_ready = 1'b0;
			assign enqueue_ready = 1'b0;
			assign head_valid = 1'b0;
			assign head_data = 1'sb0;
			wire [npu_completion_count_width(DEPTH):1] sv2v_tmp_8B624;
			assign sv2v_tmp_8B624 = 1'sb0;
			always @(*) level = sv2v_tmp_8B624;
			wire [npu_completion_count_width(DEPTH):1] sv2v_tmp_0E3BB;
			assign sv2v_tmp_0E3BB = 1'sb0;
			always @(*) reserved = sv2v_tmp_0E3BB;
		end
		else begin : g_valid_depth
			localparam signed [31:0] PTR_W = $clog2(DEPTH);
			reg [136:0] mem [0:DEPTH - 1];
			reg [PTR_W - 1:0] rd_ptr;
			reg [PTR_W - 1:0] wr_ptr;
			wire reserve_fire;
			wire enqueue_fire;
			wire release_fire;
			wire pop_fire;
			wire [COUNT_W:0] capacity_used;
			assign capacity_used = {1'b0, level} + {1'b0, reserved};
			assign head_valid = level != {npu_completion_count_width(DEPTH) {1'sb0}};
			assign head_data = mem[rd_ptr];
			assign pop_fire = head_valid && pop;
			assign reserve_ready = capacity_used < DEPTH_CAPACITY;
			assign reserve_fire = reserve_valid && reserve_ready;
			assign enqueue_ready = (reserved != {npu_completion_count_width(DEPTH) {1'sb0}}) && ((level != DEPTH_COUNT) || pop_fire);
			assign enqueue_fire = enqueue_valid && enqueue_ready;
			assign release_fire = (release_reservation && (reserved != {npu_completion_count_width(DEPTH) {1'sb0}})) && !enqueue_fire;
			always @(posedge clk)
				if (rst) begin
					rd_ptr <= 1'sb0;
					wr_ptr <= 1'sb0;
					level <= 1'sb0;
					reserved <= 1'sb0;
				end
				else begin
					if (enqueue_fire) begin
						mem[wr_ptr] <= enqueue_data;
						wr_ptr <= wr_ptr + 1'b1;
					end
					if (pop_fire)
						rd_ptr <= rd_ptr + 1'b1;
					case ({enqueue_fire, pop_fire})
						2'b10: level <= level + 1'b1;
						2'b01: level <= level - 1'b1;
						default: level <= level;
					endcase
					case ({reserve_fire, enqueue_fire || release_fire})
						2'b10: reserved <= reserved + 1'b1;
						2'b01: reserved <= reserved - 1'b1;
						default: reserved <= reserved;
					endcase
				end
		end
	endgenerate
endmodule
module npu_dma_engine (
	clk,
	rst,
	job_valid,
	job_ready,
	job_data,
	dma_req_valid,
	dma_req_ready,
	dma_req_write,
	dma_req_addr,
	dma_req_wdata,
	dma_req_wstrb,
	dma_req_id,
	dma_rsp_valid,
	dma_rsp_ready,
	dma_rsp_write,
	dma_rsp_id,
	dma_rsp_rdata,
	dma_rsp_error,
	store_elem_vector4,
	store_elem_vector_data,
	store_elem_valid,
	store_elem_ready,
	store_elem_data,
	store_elem_bytes,
	store_elem_row,
	store_elem_col,
	spad_write_valid,
	spad_write_ready,
	spad_write_is_b,
	spad_write_bank,
	spad_write_lane,
	spad_write_k,
	spad_write_input_int16,
	spad_write_data,
	spad_write_count,
	spad_write_row_full,
	spad_write_col_full,
	job_done,
	job_error,
	error_code,
	partial_output,
	outstanding
);
	parameter signed [31:0] MEM_ADDR_W = 32;
	parameter [0:0] STORE_VECTOR4_ENABLE = 1'b0;
	parameter signed [31:0] MEM_DATA_W = 32;
	parameter signed [31:0] MEM_ID_W = 2;
	parameter signed [31:0] MEM_OUTSTANDING = 4;
	parameter signed [31:0] ARRAY_ROWS = 4;
	parameter signed [31:0] ARRAY_COLS = 4;
	parameter signed [31:0] K_TILE = 32;
	parameter signed [31:0] SPAD_VECTOR_ELEMS = 1;
	parameter [0:0] A_PACKED_INT8_16 = 1'b0;
	parameter signed [31:0] READ_REQ_PIPELINE = 1;
	parameter signed [31:0] RSP_FIFO_DEPTH = 2;
	parameter signed [31:0] DMA_TIMEOUT_CYCLES = 4096;
	input wire clk;
	input wire rst;
	input wire job_valid;
	output wire job_ready;
	input wire [100:0] job_data;
	output wire dma_req_valid;
	input wire dma_req_ready;
	output wire dma_req_write;
	output wire [MEM_ADDR_W - 1:0] dma_req_addr;
	output wire [MEM_DATA_W - 1:0] dma_req_wdata;
	output wire [(MEM_DATA_W / 8) - 1:0] dma_req_wstrb;
	output wire [MEM_ID_W - 1:0] dma_req_id;
	input wire dma_rsp_valid;
	output wire dma_rsp_ready;
	input wire dma_rsp_write;
	input wire [MEM_ID_W - 1:0] dma_rsp_id;
	input wire [MEM_DATA_W - 1:0] dma_rsp_rdata;
	input wire dma_rsp_error;
	input wire store_elem_vector4;
	input wire [127:0] store_elem_vector_data;
	input wire store_elem_valid;
	output reg store_elem_ready;
	input wire signed [31:0] store_elem_data;
	input wire [2:0] store_elem_bytes;
	input wire [15:0] store_elem_row;
	input wire [15:0] store_elem_col;
	output wire spad_write_valid;
	input wire spad_write_ready;
	output wire spad_write_is_b;
	output wire spad_write_bank;
	output wire [(ARRAY_ROWS > ARRAY_COLS ? (ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1) : (ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1)) - 1:0] spad_write_lane;
	output wire [(K_TILE > 1 ? $clog2(K_TILE) : 1) - 1:0] spad_write_k;
	output wire spad_write_input_int16;
	output wire signed [(SPAD_VECTOR_ELEMS * 16) - 1:0] spad_write_data;
	output wire [(SPAD_VECTOR_ELEMS > 1 ? $clog2(SPAD_VECTOR_ELEMS + 1) : 1) - 1:0] spad_write_count;
	output wire [15:0] spad_write_row_full;
	output wire [15:0] spad_write_col_full;
	output reg job_done;
	output reg job_error;
	output reg [7:0] error_code;
	output reg partial_output;
	output reg [(MEM_OUTSTANDING > 0 ? $clog2(MEM_OUTSTANDING + 1) : 1) - 1:0] outstanding;
	localparam signed [31:0] MEM_BYTES = MEM_DATA_W / 8;
	localparam signed [31:0] RSP_PAYLOAD_W = (2 + MEM_ID_W) + MEM_DATA_W;
	localparam signed [31:0] SAFE_MEM_ID_W = ((MEM_ID_W >= 1) && (MEM_ID_W <= 30) ? MEM_ID_W : 1);
	localparam [63:0] ID_CAPACITY = 64'd1 << SAFE_MEM_ID_W;
	localparam signed [31:0] SLOT_COUNT = (MEM_OUTSTANDING > 0 ? MEM_OUTSTANDING : 1);
	localparam signed [31:0] SLOT_W = (SLOT_COUNT > 1 ? $clog2(SLOT_COUNT) : 1);
	function automatic signed [63:0] sv2v_cast_64_signed;
		input reg signed [63:0] inp;
		sv2v_cast_64_signed = inp;
	endfunction
	localparam [63:0] MEM_OUTSTANDING_U64 = (MEM_OUTSTANDING > 0 ? sv2v_cast_64_signed(MEM_OUTSTANDING) : 64'd0);
	localparam signed [31:0] OWNED_W = (MEM_OUTSTANDING > 0 ? $clog2(MEM_OUTSTANDING + 1) : 1);
	localparam signed [31:0] LANE_W = (ARRAY_ROWS > ARRAY_COLS ? (ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1) : (ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1));
	localparam signed [31:0] K_W = (K_TILE > 1 ? $clog2(K_TILE) : 1);
	localparam signed [31:0] BYTE_OFF_W = (MEM_BYTES > 1 ? $clog2(MEM_BYTES) : 1);
	localparam signed [31:0] SEG_COUNT_W = (MEM_BYTES > 1 ? $clog2(MEM_BYTES + 1) : 1);
	localparam signed [31:0] TIMEOUT_W = (DMA_TIMEOUT_CYCLES > 1 ? $clog2(sv2v_cast_64_signed(DMA_TIMEOUT_CYCLES) + 64'd1) : 1);
	function automatic signed [((BYTE_OFF_W + 0) >= 0 ? BYTE_OFF_W + 1 : 1 - (BYTE_OFF_W + 0)) - 1:0] sv2v_cast_D6D29_signed;
		input reg signed [((BYTE_OFF_W + 0) >= 0 ? BYTE_OFF_W + 1 : 1 - (BYTE_OFF_W + 0)) - 1:0] inp;
		sv2v_cast_D6D29_signed = inp;
	endfunction
	localparam [BYTE_OFF_W:0] MEM_BYTES_COUNT = sv2v_cast_D6D29_signed(MEM_BYTES);
	function automatic signed [TIMEOUT_W - 1:0] sv2v_cast_897CF_signed;
		input reg signed [TIMEOUT_W - 1:0] inp;
		sv2v_cast_897CF_signed = inp;
	endfunction
	localparam [TIMEOUT_W - 1:0] TIMEOUT_LIMIT = (DMA_TIMEOUT_CYCLES >= 0 ? sv2v_cast_897CF_signed(DMA_TIMEOUT_CYCLES) : {TIMEOUT_W {1'sb0}});
	reg meta_valid [0:SLOT_COUNT - 1];
	reg meta_accepted [0:SLOT_COUNT - 1];
	reg meta_write [0:SLOT_COUNT - 1];
	reg meta_is_b [0:SLOT_COUNT - 1];
	reg meta_bank [0:SLOT_COUNT - 1];
	reg [15:0] meta_row [0:SLOT_COUNT - 1];
	reg [15:0] meta_col [0:SLOT_COUNT - 1];
	reg [BYTE_OFF_W - 1:0] meta_byte_off [0:SLOT_COUNT - 1];
	reg [SEG_COUNT_W - 1:0] meta_count [0:SLOT_COUNT - 1];
	reg [1:0] meta_elem_bytes [0:SLOT_COUNT - 1];
	reg job_active;
	reg failing;
	reg all_issued;
	reg store_source_done;
	reg [OWNED_W - 1:0] owned_count;
	reg [68:0] job_q;
	reg [15:0] next_row;
	reg [15:0] next_col;
	reg [15:0] job_last_row_q;
	reg [15:0] job_last_col_q;
	reg [15:0] job_last_vec_col_q;
	reg store_vector_seen;
	wire store_vector = (STORE_VECTOR4_ENABLE && (MEM_DATA_W == 128)) && (store_elem_vector4 === 1'b1);
	wire [15:0] store_step = (store_vector ? 16'd4 : 16'd1);
	reg [31:0] row_base_q;
	reg [31:0] element_addr_q;
	wire [31:0] cp12_read_step_address;
	cp12_dma_read_step #(.MEM_BYTES(MEM_BYTES)) read_step(
		.address(element_addr_q),
		.element_bytes(job_q[2-:2]),
		.next_address(cp12_read_step_address)
	);
	reg req_hold_valid;
	reg dma_req_write_q;
	reg [MEM_ADDR_W - 1:0] dma_req_addr_q;
	reg [MEM_DATA_W - 1:0] dma_req_wdata_q;
	reg [MEM_BYTES - 1:0] dma_req_wstrb_q;
	reg [MEM_ID_W - 1:0] dma_req_id_q;
	reg [SLOT_W - 1:0] dma_req_slot_q;
	wire [SLOT_W - 1:0] allocated_slot;
	wire allocate_valid;
	wire allocator_protocol_error;
	wire [OWNED_W - 1:0] allocator_free_count;
	reg read_req_make;
	reg store_req_make;
	reg req_reserve;
	wire req_fire;
	reg [MEM_ADDR_W - 1:0] element_addr;
	reg [BYTE_OFF_W - 1:0] element_byte_off;
	reg [SEG_COUNT_W - 1:0] segment_count;
	reg [15:0] cols_left;
	wire read_row_last;
	integer bytes_left;
	integer elems_fit;
	function automatic signed [15:0] sv2v_cast_16_signed;
		input reg signed [15:0] inp;
		sv2v_cast_16_signed = inp;
	endfunction
	assign read_row_last = cols_left <= sv2v_cast_16_signed(elems_fit);
	reg store_pack_valid;
	reg store_pack_row_end;
	reg store_bytes_seen;
	reg [MEM_ADDR_W - 1:0] store_pack_addr;
	reg [MEM_DATA_W - 1:0] store_pack_data;
	reg [MEM_BYTES - 1:0] store_pack_strb;
	reg [2:0] store_bytes_q;
	reg store_bytes_valid;
	reg store_input_valid;
	reg store_input_malformed;
	reg store_post_done_fault;
	reg store_fault_event;
	reg [MEM_ADDR_W - 1:0] store_elem_addr;
	reg [MEM_ADDR_W - 1:0] store_elem_beat;
	reg [BYTE_OFF_W - 1:0] store_elem_byte_off;
	reg store_same_beat;
	reg store_row_last;
	reg store_job_last;
	reg store_flush_input;
	reg store_needs_request;
	reg store_can_make;
	reg store_fire;
	reg store_tail_make;
	reg [MEM_DATA_W - 1:0] store_merged_data;
	reg [MEM_BYTES - 1:0] store_merged_strb;
	reg rsp_id_known;
	reg rsp_owned;
	wire rsp_fire;
	wire rsp_owned_fire;
	wire rsp_fifo_in_valid;
	wire rsp_fifo_in_ready;
	wire rsp_fifo_out_valid;
	wire rsp_fifo_out_ready;
	wire [RSP_PAYLOAD_W - 1:0] rsp_fifo_in_data;
	wire [RSP_PAYLOAD_W - 1:0] rsp_fifo_out_data;
	localparam signed [31:0] RSP_COUNT_W = (RSP_FIFO_DEPTH > 0 ? $clog2(RSP_FIFO_DEPTH + 1) : 1);
	wire [RSP_COUNT_W - 1:0] rsp_fifo_occupancy;
	wire rsp_q_write;
	wire rsp_q_error;
	wire rsp_ingress_fire;
	wire [MEM_ID_W - 1:0] rsp_q_id;
	wire [MEM_DATA_W - 1:0] rsp_q_rdata;
	reg [SLOT_W - 1:0] rsp_slot;
	wire rsp_error_event;
	wire read_capture_fire;
	wire timeout_event;
	wire forward_progress;
	wire watchdog_pending;
	wire success_transition;
	wire failure_transition;
	wire [TIMEOUT_W - 1:0] timeout_count;
	reg unpack_valid;
	reg [MEM_DATA_W - 1:0] unpack_rdata;
	reg unpack_is_b;
	reg unpack_bank;
	reg [15:0] unpack_row;
	reg [15:0] unpack_col;
	reg [BYTE_OFF_W - 1:0] unpack_byte_off;
	reg [SEG_COUNT_W - 1:0] unpack_count;
	reg [1:0] unpack_elem_bytes;
	reg [SEG_COUNT_W - 1:0] unpack_index;
	wire spad_fire;
	wire unpack_last;
	wire unpack_can_exchange;
	localparam signed [31:0] VECTOR_COUNT_W = (SPAD_VECTOR_ELEMS > 1 ? $clog2(SPAD_VECTOR_ELEMS + 1) : 1);
	localparam signed [31:0] ALIGN_W = (MEM_DATA_W > (SPAD_VECTOR_ELEMS * 16) ? MEM_DATA_W : SPAD_VECTOR_ELEMS * 16);
	localparam signed [31:0] BATCH_W = (SEG_COUNT_W > VECTOR_COUNT_W ? SEG_COUNT_W : VECTOR_COUNT_W);
	wire [SEG_COUNT_W - 1:0] unpack_batch;
	reg [SEG_COUNT_W - 1:0] unpack_batch_q;
	reg unpack_last_q;
	wire [15:0] unpack_current_col;
	reg [15:0] unpack_current_col_q;
	reg [LANE_W - 1:0] unpack_spad_lane_q;
	reg [K_W - 1:0] unpack_spad_k_q;
	wire [BATCH_W - 1:0] unpack_remaining;
	wire [BATCH_W - 1:0] unpack_boundary;
	wire [BATCH_W - 1:0] unpack_limited;
	wire [BATCH_W - 1:0] unpack_group_elems;
	wire [BYTE_OFF_W:0] unpack_shift_bytes;
	reg [BYTE_OFF_W:0] unpack_shift_bytes_q;
	wire [ALIGN_W - 1:0] unpack_aligned;
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	function automatic [BATCH_W - 1:0] sv2v_cast_7ADC6;
		input reg [BATCH_W - 1:0] inp;
		sv2v_cast_7ADC6 = inp;
	endfunction
	function automatic signed [BATCH_W - 1:0] sv2v_cast_7ADC6_signed;
		input reg signed [BATCH_W - 1:0] inp;
		sv2v_cast_7ADC6_signed = inp;
	endfunction
	function automatic [SEG_COUNT_W - 1:0] sv2v_cast_78AFB;
		input reg [SEG_COUNT_W - 1:0] inp;
		sv2v_cast_78AFB = inp;
	endfunction
	function automatic [SEG_COUNT_W - 1:0] cp11_batch;
		input reg [SEG_COUNT_W - 1:0] count;
		input reg [SEG_COUNT_W - 1:0] index;
		input reg [15:0] col;
		input reg is_b;
		input reg [1:0] elem_bytes;
		reg [BATCH_W - 1:0] remaining;
		reg [BATCH_W - 1:0] boundary;
		reg [BATCH_W - 1:0] limited;
		reg [BATCH_W - 1:0] group_elems;
		reg [15:0] current;
		begin
			current = col + sv2v_cast_16(index);
			remaining = sv2v_cast_7ADC6(count) - sv2v_cast_7ADC6(index);
			group_elems = sv2v_cast_7ADC6_signed(((A_PACKED_INT8_16 && !is_b) && (elem_bytes == 2'd2) ? 8 : SPAD_VECTOR_ELEMS));
			boundary = group_elems - sv2v_cast_7ADC6(current & (sv2v_cast_16(group_elems) - 16'd1));
			limited = (remaining > group_elems ? group_elems : remaining);
			cp11_batch = sv2v_cast_78AFB((!is_b && (limited > boundary) ? boundary : limited));
		end
	endfunction
	assign unpack_current_col = unpack_current_col_q;
	assign unpack_batch = (unpack_valid ? unpack_batch_q : {SEG_COUNT_W {1'sb0}});
	assign unpack_last = unpack_valid && unpack_last_q;
	assign unpack_can_exchange = !unpack_valid || (unpack_last && (spad_write_ready === 1'b1));
	assign unpack_remaining = sv2v_cast_7ADC6(unpack_count) - sv2v_cast_7ADC6(unpack_index);
	assign unpack_group_elems = sv2v_cast_7ADC6_signed(((A_PACKED_INT8_16 && !unpack_is_b) && (unpack_elem_bytes == 2'd2) ? 8 : SPAD_VECTOR_ELEMS));
	assign unpack_boundary = unpack_group_elems - sv2v_cast_7ADC6((unpack_col + sv2v_cast_16(unpack_index)) & (sv2v_cast_16(unpack_group_elems) - 16'd1));
	assign unpack_limited = (unpack_remaining > unpack_group_elems ? unpack_group_elems : unpack_remaining);
	function automatic [((BYTE_OFF_W + 0) >= 0 ? BYTE_OFF_W + 1 : 1 - (BYTE_OFF_W + 0)) - 1:0] sv2v_cast_D6D29;
		input reg [((BYTE_OFF_W + 0) >= 0 ? BYTE_OFF_W + 1 : 1 - (BYTE_OFF_W + 0)) - 1:0] inp;
		sv2v_cast_D6D29 = inp;
	endfunction
	assign unpack_shift_bytes = sv2v_cast_D6D29(unpack_byte_off) + (sv2v_cast_D6D29(unpack_index) << (unpack_elem_bytes == 2'd2));
	function automatic [ALIGN_W - 1:0] sv2v_cast_07077;
		input reg [ALIGN_W - 1:0] inp;
		sv2v_cast_07077 = inp;
	endfunction
	assign unpack_aligned = sv2v_cast_07077(unpack_rdata) >> {unpack_shift_bytes_q, 3'b000};
	always @(posedge clk)
		if (rst)
			unpack_shift_bytes_q <= 1'sb0;
		else begin
			if (spad_fire && !unpack_last)
				unpack_shift_bytes_q <= unpack_shift_bytes_q + (sv2v_cast_D6D29(unpack_batch) << (unpack_elem_bytes == 2'd2));
			if ((((job_active === 1'b1) && (rsp_fifo_out_valid === 1'b1)) && unpack_can_exchange) && (spad_write_ready === 1'b1))
				unpack_shift_bytes_q <= sv2v_cast_D6D29(meta_byte_off[rsp_slot]);
		end
	function automatic [VECTOR_COUNT_W - 1:0] sv2v_cast_00316;
		input reg [VECTOR_COUNT_W - 1:0] inp;
		sv2v_cast_00316 = inp;
	endfunction
	assign spad_write_count = sv2v_cast_00316(unpack_batch);
	wire [15:0] segment_count_16;
	function automatic signed [15:0] read_element;
		input reg [MEM_DATA_W - 1:0] data;
		input reg [31:0] byte_offset;
		input reg [1:0] elem_bytes;
		reg [15:0] raw;
		begin
			raw = 1'sb0;
			if (elem_bytes == 2'd1)
				raw = {{8 {data[(byte_offset * 8) + 7]}}, data[byte_offset * 8+:8]};
			else if (elem_bytes == 2'd2)
				raw = data[byte_offset * 8+:16];
			read_element = raw;
		end
	endfunction
	function automatic [MEM_DATA_W - 1:0] merge_store_data;
		input reg [MEM_DATA_W - 1:0] old_data;
		input reg signed [31:0] element_data;
		input reg [BYTE_OFF_W - 1:0] byte_offset;
		input reg [2:0] element_bytes;
		reg [MEM_DATA_W - 1:0] mask;
		reg [MEM_DATA_W - 1:0] payload;
		begin
			mask = 1'sb0;
			case (element_bytes)
				3'd1: mask[7:0] = 8'hff;
				3'd2: mask[15:0] = 16'hffff;
				3'd4: mask[31:0] = 32'hffffffff;
				default: mask = 1'sb0;
			endcase
			mask = mask << {byte_offset, 3'b000};
			payload = {{MEM_DATA_W - 32 {1'b0}}, element_data};
			payload = payload << {byte_offset, 3'b000};
			merge_store_data = (old_data & ~mask) | (payload & mask);
		end
	endfunction
	function automatic [MEM_BYTES - 1:0] merge_store_strb;
		input reg [MEM_BYTES - 1:0] old_strb;
		input reg [BYTE_OFF_W - 1:0] byte_offset;
		input reg [2:0] element_bytes;
		reg [MEM_BYTES - 1:0] mask;
		begin
			mask = 1'sb0;
			case (element_bytes)
				3'd1: mask[0] = 1'b1;
				3'd2: mask[1:0] = 2'b11;
				3'd4: mask[3:0] = 4'b1111;
				default: mask = 1'sb0;
			endcase
			merge_store_strb = old_strb | (mask << byte_offset);
		end
	endfunction
	npu_free_slot_allocator #(.SLOT_COUNT(SLOT_COUNT)) free_slots(
		.clk(clk),
		.rst(rst),
		.allocate_take(req_reserve),
		.allocate_valid(allocate_valid),
		.allocate_slot(allocated_slot),
		.release_valid(rsp_owned_fire),
		.release_slot(rsp_slot),
		.free_count(allocator_free_count),
		.protocol_error(allocator_protocol_error)
	);
	function automatic [MEM_ADDR_W - 1:0] sv2v_cast_BD8CE;
		input reg [MEM_ADDR_W - 1:0] inp;
		sv2v_cast_BD8CE = inp;
	endfunction
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @(*) begin
		element_addr = sv2v_cast_BD8CE(element_addr_q);
		element_byte_off = element_addr[BYTE_OFF_W - 1:0];
		cols_left = job_q[18-:16] - next_col;
		bytes_left = MEM_BYTES - sv2v_cast_32_signed(element_byte_off);
		elems_fit = 0;
		segment_count = 1'sb0;
		if ((job_q[68-:2] === 2'd0) || (job_q[68-:2] === 2'd1)) begin
			case (job_q[2-:2])
				2'd1: elems_fit = bytes_left;
				2'd2: elems_fit = bytes_left >> 1;
				default: elems_fit = 0;
			endcase
			if (elems_fit > sv2v_cast_32_signed(cols_left))
				segment_count = cols_left[SEG_COUNT_W - 1:0];
			else
				segment_count = elems_fit[SEG_COUNT_W - 1:0];
			if (segment_count == {SEG_COUNT_W {1'sb0}})
				segment_count = 1;
		end
		read_req_make = (((((((((job_active && !failing) && !rsp_error_event) && !allocator_protocol_error) && ((job_q[68-:2] === 2'd0) || (job_q[68-:2] === 2'd1))) && !all_issued) && (!req_hold_valid || ((READ_REQ_PIPELINE != 0) && req_fire))) && (allocator_free_count != {OWNED_W {1'sb0}})) && allocate_valid) && ((job_q[2-:2] == 2'd1) || (job_q[2-:2] == 2'd2))) && (({1'b0, element_byte_off} + {{BYTE_OFF_W - 1 {1'b0}}, job_q[2-:2]}) <= MEM_BYTES_COUNT);
	end
	function automatic [MEM_DATA_W - 1:0] sv2v_cast_B89CD;
		input reg [MEM_DATA_W - 1:0] inp;
		sv2v_cast_B89CD = inp;
	endfunction
	always @(*) begin
		store_elem_addr = sv2v_cast_BD8CE(element_addr_q);
		store_elem_beat = store_elem_addr & ~(MEM_BYTES - 1);
		store_elem_byte_off = store_elem_addr[BYTE_OFF_W - 1:0];
		store_bytes_valid = ((store_elem_bytes === 3'd1) || (store_elem_bytes === 3'd2)) || (store_elem_bytes === 3'd4);
		store_input_valid = (((((store_bytes_valid && (!store_bytes_seen || ((store_elem_bytes === store_bytes_q) && (store_vector === store_vector_seen)))) && (!store_vector || ((((((store_elem_bytes == 4) && (store_elem_byte_off == 0)) && (job_q[4:3] == 0)) && (next_col[1:0] == 0)) && !store_pack_valid) && (({1'b0, next_col} + 17'd4) <= {1'b0, job_q[18-:16]})))) && (store_elem_row === next_row)) && (store_elem_col === next_col)) && (({1'b0, store_elem_byte_off} + {{BYTE_OFF_W - 2 {1'b0}}, store_elem_bytes}) <= MEM_BYTES_COUNT)) && (((store_elem_bytes === 3'd1) || ((store_elem_bytes === 3'd2) && (store_elem_byte_off[0] === 1'b0))) || ((store_elem_bytes === 3'd4) && (store_elem_byte_off[1:0] === 2'b00)));
		store_input_malformed = ((job_active && (job_q[68-:2] === 2'd2)) && (store_elem_valid === 1'b1)) && !store_input_valid;
		store_post_done_fault = ((job_active && (job_q[68-:2] === 2'd2)) && store_source_done) && (store_elem_valid === 1'b1);
		store_fault_event = store_input_malformed || store_post_done_fault;
		store_same_beat = store_pack_valid && (store_pack_addr === store_elem_beat);
		store_row_last = (store_vector ? next_col == job_last_vec_col_q : next_col == job_last_col_q);
		store_job_last = store_row_last && (next_row == job_last_row_q);
		store_flush_input = store_pack_valid && (!store_same_beat || store_row_last);
		store_needs_request = (store_vector || (!store_pack_valid && store_row_last)) || store_flush_input;
		store_can_make = ((!req_hold_valid || (store_vector && req_fire)) && (allocator_free_count != {OWNED_W {1'sb0}})) && allocate_valid;
		store_elem_ready = ((((((job_active && (job_q[68-:2] === 2'd2)) && !failing) && !rsp_error_event) && !allocator_protocol_error) && !store_source_done) && !store_pack_row_end) && ((store_input_malformed || !store_needs_request) || store_can_make);
		store_fire = store_elem_valid && store_elem_ready;
		store_req_make = (store_fire && store_input_valid) && store_needs_request;
		store_tail_make = (((((((job_active && (job_q[68-:2] === 2'd2)) && !failing) && !rsp_error_event) && !allocator_protocol_error) && !store_fault_event) && store_source_done) && store_pack_valid) && store_can_make;
		if (store_pack_row_end)
			store_tail_make = ((((((job_active && (job_q[68-:2] === 2'd2)) && !failing) && !rsp_error_event) && !allocator_protocol_error) && !store_fault_event) && store_pack_valid) && store_can_make;
		req_reserve = (read_req_make || store_req_make) || store_tail_make;
		store_merged_data = 1'sb0;
		store_merged_strb = 1'sb0;
		if (store_input_valid && store_vector) begin
			store_merged_data = sv2v_cast_B89CD(store_elem_vector_data);
			store_merged_strb = 1'sb1;
		end
		else if (store_input_valid) begin
			store_merged_data = merge_store_data((store_pack_valid ? store_pack_data : {MEM_DATA_W {1'sb0}}), store_elem_data, store_elem_byte_off, store_elem_bytes);
			store_merged_strb = merge_store_strb((store_pack_valid ? store_pack_strb : {MEM_BYTES {1'sb0}}), store_elem_byte_off, store_elem_bytes);
		end
	end
	assign rsp_fifo_in_valid = (job_active === 1'b1) && (dma_rsp_valid === 1'b1);
	assign rsp_fifo_in_data = {dma_rsp_write, dma_rsp_error, dma_rsp_id, dma_rsp_rdata};
	assign {rsp_q_write, rsp_q_error, rsp_q_id, rsp_q_rdata} = rsp_fifo_out_data;
	assign dma_rsp_ready = rsp_fifo_in_ready;
	assign rsp_ingress_fire = rsp_fifo_in_valid && (rsp_fifo_in_ready === 1'b1);
	npu_elastic_fifo #(
		.WIDTH(RSP_PAYLOAD_W),
		.DEPTH(RSP_FIFO_DEPTH)
	) response_ingress(
		.clk(clk),
		.rst(rst),
		.in_valid(rsp_fifo_in_valid),
		.in_ready(rsp_fifo_in_ready),
		.in_data(rsp_fifo_in_data),
		.out_valid(rsp_fifo_out_valid),
		.out_ready(rsp_fifo_out_ready),
		.out_data(rsp_fifo_out_data),
		.occupancy(rsp_fifo_occupancy)
	);
	function automatic [63:0] sv2v_cast_64;
		input reg [63:0] inp;
		sv2v_cast_64 = inp;
	endfunction
	function automatic [SLOT_W - 1:0] sv2v_cast_7C1AF;
		input reg [SLOT_W - 1:0] inp;
		sv2v_cast_7C1AF = inp;
	endfunction
	always @(*) begin
		rsp_id_known = ^rsp_q_id !== 1'bx;
		rsp_slot = 1'sb0;
		rsp_owned = 1'b0;
		if (rsp_id_known && (sv2v_cast_64($unsigned(rsp_q_id)) < MEM_OUTSTANDING_U64)) begin
			rsp_slot = sv2v_cast_7C1AF(rsp_q_id);
			rsp_owned = (meta_valid[rsp_slot] === 1'b1) && (meta_accepted[rsp_slot] === 1'b1);
		end
	end
	assign job_ready = !job_active;
	assign dma_req_valid = req_hold_valid;
	assign dma_req_write = dma_req_write_q;
	assign dma_req_addr = dma_req_addr_q;
	assign dma_req_id = dma_req_id_q;
	assign dma_req_wdata = dma_req_wdata_q;
	assign dma_req_wstrb = dma_req_wstrb_q;
	assign req_fire = dma_req_valid && dma_req_ready;
	assign rsp_fifo_out_ready = (job_active === 1'b1) && ((((failing === 1'b1) || !rsp_owned) || (meta_write[rsp_slot] === 1'b1)) || (unpack_can_exchange && (spad_write_ready === 1'b1)));
	assign rsp_fire = (rsp_fifo_out_valid === 1'b1) && (rsp_fifo_out_ready === 1'b1);
	assign rsp_owned_fire = rsp_fire && rsp_owned;
	assign rsp_error_event = rsp_fire && ((!rsp_owned || (rsp_q_error !== 1'b0)) || (rsp_owned && (rsp_q_write !== meta_write[rsp_slot])));
	assign read_capture_fire = ((((((((job_active === 1'b1) && (rsp_fifo_out_valid === 1'b1)) && (failing === 1'b0)) && rsp_owned) && (rsp_q_error === 1'b0)) && (rsp_q_write === 1'b0)) && (meta_write[rsp_slot] === 1'b0)) && unpack_can_exchange) && (spad_write_ready === 1'b1);
	assign spad_write_valid = unpack_valid;
	assign spad_write_is_b = unpack_is_b;
	assign spad_write_bank = unpack_bank;
	assign segment_count_16 = {{16 - SEG_COUNT_W {1'b0}}, segment_count};
	assign spad_write_row_full = unpack_row;
	assign spad_write_col_full = unpack_current_col_q;
	assign spad_write_lane = unpack_spad_lane_q;
	assign spad_write_k = unpack_spad_k_q;
	assign spad_write_input_int16 = unpack_elem_bytes == 2'd2;
	genvar _gv_e_1;
	generate
		for (_gv_e_1 = 0; _gv_e_1 < SPAD_VECTOR_ELEMS; _gv_e_1 = _gv_e_1 + 1) begin : g_unpack_vector
			localparam e = _gv_e_1;
			assign spad_write_data[e * 16+:16] = (unpack_elem_bytes == 2'd2 ? unpack_aligned[e * 16+:16] : {{8 {unpack_aligned[(e * 8) + 7]}}, unpack_aligned[e * 8+:8]});
		end
	endgenerate
	assign spad_fire = spad_write_valid && spad_write_ready;
	assign success_transition = (((((((((((job_active && !failing) && !rsp_error_event) && !allocator_protocol_error) && !store_fault_event) && (((job_q[68-:2] === 2'd2) && store_source_done) || ((job_q[68-:2] !== 2'd2) && all_issued))) && (outstanding == {(MEM_OUTSTANDING > 0 ? $clog2(MEM_OUTSTANDING + 1) : 1) {1'sb0}})) && (owned_count == {OWNED_W {1'sb0}})) && !req_hold_valid) && !unpack_valid) && !store_pack_valid) && (rsp_fifo_occupancy == {RSP_COUNT_W {1'sb0}})) && !rsp_ingress_fire;
	assign failure_transition = (((((((job_active && ((failing || rsp_error_event) || allocator_protocol_error)) && (outstanding == {(MEM_OUTSTANDING > 0 ? $clog2(MEM_OUTSTANDING + 1) : 1) {1'sb0}})) && (owned_count == {OWNED_W {1'sb0}})) && !req_hold_valid) && !unpack_valid) && !store_pack_valid) && (rsp_fifo_occupancy == {RSP_COUNT_W {1'sb0}})) && !rsp_ingress_fire;
	assign forward_progress = ((((((((req_reserve || req_fire) || rsp_ingress_fire) || rsp_fire) || store_fire) || spad_fire) || store_fault_event) || allocator_protocol_error) || success_transition) || failure_transition;
	assign watchdog_pending = (job_active && !failing) && (((((((((job_q[68-:2] === 2'd0) || (job_q[68-:2] === 2'd1)) && !all_issued) || req_hold_valid) || (owned_count != {OWNED_W {1'sb0}})) || (outstanding != {(MEM_OUTSTANDING > 0 ? $clog2(MEM_OUTSTANDING + 1) : 1) {1'sb0}})) || (rsp_fifo_occupancy != {RSP_COUNT_W {1'sb0}})) || unpack_valid) || ((job_q[68-:2] === 2'd2) && ((store_elem_valid || store_source_done) || store_pack_row_end)));
	cp9_progress_watchdog #(
		.LIMIT(DMA_TIMEOUT_CYCLES),
		.W(TIMEOUT_W)
	) watchdog_counter(
		.clk(clk),
		.rst(rst),
		.job_accept((job_valid === 1'b1) && (job_ready === 1'b1)),
		.active(job_active),
		.pending(watchdog_pending),
		.progress(forward_progress),
		.effective_count(timeout_count),
		.expired(timeout_event)
	);
	generate
		if ((RSP_FIFO_DEPTH < 2) || (RSP_FIFO_DEPTH > 16)) begin : g_bad_rsp_depth
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_dma_engine.sv:581:15 - npu_dma_engine.g_bad_rsp_depth.<unnamed_block>\n msg: ", $time, "CP6_RSP_DEPTH_RED");
				$finish(1);
			end
		end
		if ((((SPAD_VECTOR_ELEMS < 1) || (SPAD_VECTOR_ELEMS > (A_PACKED_INT8_16 ? 16 : 8))) || ((SPAD_VECTOR_ELEMS & (SPAD_VECTOR_ELEMS - 1)) != 0)) || (SPAD_VECTOR_ELEMS > K_TILE)) begin : g_bad_vector
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_dma_engine.sv:585:15 - npu_dma_engine.g_bad_vector.<unnamed_block>\n msg: ", $time, "CP5_DMA_VECTOR_PARAM_RED");
				$finish(1);
			end
		end
		if (A_PACKED_INT8_16 && (((SPAD_VECTOR_ELEMS != 16) || (MEM_DATA_W != 128)) || (K_TILE < 16))) begin : g_bad_packed16
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_dma_engine.sv:588:15 - npu_dma_engine.g_bad_packed16.<unnamed_block>\n msg: ", $time, "A_INT8PACKED16_DMA_CONFIGURATION_RED");
				$finish(1);
			end
		end
		if (((MEM_DATA_W != 32) && (MEM_DATA_W != 64)) && (MEM_DATA_W != 128)) begin : g_bad_data_width
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_dma_engine.sv:591:15 - npu_dma_engine.g_bad_data_width.<unnamed_block>\n msg: ", $time, "npu_dma_engine: MEM_DATA_W must be 32, 64, or 128");
				$finish(1);
			end
		end
		if (MEM_ID_W < 1) begin : g_bad_id_width
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_dma_engine.sv:594:15 - npu_dma_engine.g_bad_id_width.<unnamed_block>\n msg: ", $time, "npu_dma_engine: MEM_ID_W must be at least 1");
				$finish(1);
			end
		end
		if (MEM_ID_W > 30) begin : g_bad_id_width_high
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_dma_engine.sv:597:15 - npu_dma_engine.g_bad_id_width_high.<unnamed_block>\n msg: ", $time, "npu_dma_engine: MEM_ID_W must be at most 30");
				$finish(1);
			end
		end
		if ((MEM_OUTSTANDING < 1) || (MEM_OUTSTANDING_U64 > ID_CAPACITY)) begin : g_bad_outstanding
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_dma_engine.sv:600:15 - npu_dma_engine.g_bad_outstanding.<unnamed_block>\n msg: ", $time, "npu_dma_engine: MEM_OUTSTANDING must be 1..2**MEM_ID_W");
				$finish(1);
			end
		end
		if (((ARRAY_ROWS < 1) || (ARRAY_COLS < 1)) || (K_TILE < 1)) begin : g_bad_shape
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_dma_engine.sv:603:15 - npu_dma_engine.g_bad_shape.<unnamed_block>\n msg: ", $time, "npu_dma_engine: array and K dimensions must be positive");
				$finish(1);
			end
		end
		if (DMA_TIMEOUT_CYCLES < 0) begin : g_bad_timeout
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_dma_engine.sv:606:15 - npu_dma_engine.g_bad_timeout.<unnamed_block>\n msg: ", $time, "npu_dma_engine: DMA_TIMEOUT_CYCLES must be nonnegative");
				$finish(1);
			end
		end
	endgenerate
	function automatic [SAFE_MEM_ID_W - 1:0] sv2v_cast_EFA09;
		input reg [SAFE_MEM_ID_W - 1:0] inp;
		sv2v_cast_EFA09 = inp;
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [LANE_W - 1:0] sv2v_cast_3FA0D;
		input reg [LANE_W - 1:0] inp;
		sv2v_cast_3FA0D = inp;
	endfunction
	function automatic [K_W - 1:0] sv2v_cast_A1A65;
		input reg [K_W - 1:0] inp;
		sv2v_cast_A1A65 = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			job_active <= 1'b0;
			failing <= 1'b0;
			all_issued <= 1'b0;
			store_source_done <= 1'b0;
			store_pack_valid <= 1'b0;
			store_pack_row_end <= 1'b0;
			store_bytes_seen <= 1'b0;
			store_vector_seen <= 1'b0;
			store_pack_addr <= 1'sb0;
			store_pack_data <= 1'sb0;
			store_pack_strb <= 1'sb0;
			store_bytes_q <= 1'sb0;
			job_q <= 1'sb0;
			next_row <= 1'sb0;
			next_col <= 1'sb0;
			job_last_row_q <= 1'sb0;
			job_last_col_q <= 1'sb0;
			job_last_vec_col_q <= 1'sb0;
			row_base_q <= 1'sb0;
			element_addr_q <= 1'sb0;
			req_hold_valid <= 1'b0;
			dma_req_write_q <= 1'b0;
			dma_req_addr_q <= 1'sb0;
			dma_req_wdata_q <= 1'sb0;
			dma_req_wstrb_q <= 1'sb0;
			dma_req_id_q <= 1'sb0;
			dma_req_slot_q <= 1'sb0;
			unpack_valid <= 1'b0;
			unpack_rdata <= 1'sb0;
			unpack_is_b <= 1'b0;
			unpack_bank <= 1'b0;
			unpack_row <= 1'sb0;
			unpack_col <= 1'sb0;
			unpack_byte_off <= 1'sb0;
			unpack_count <= 1'sb0;
			unpack_elem_bytes <= 1'sb0;
			unpack_index <= 1'sb0;
			unpack_batch_q <= 1'sb0;
			unpack_last_q <= 1'b0;
			unpack_current_col_q <= 1'sb0;
			unpack_spad_lane_q <= 1'sb0;
			unpack_spad_k_q <= 1'sb0;
			job_done <= 1'b0;
			job_error <= 1'b0;
			error_code <= 8'd0;
			partial_output <= 1'b0;
			outstanding <= 1'sb0;
			owned_count <= 1'sb0;
			begin : sv2v_autoblock_1
				reg signed [31:0] i;
				for (i = 0; i < SLOT_COUNT; i = i + 1)
					begin
						meta_valid[i] <= 1'b0;
						meta_accepted[i] <= 1'b0;
						meta_write[i] <= 1'b0;
						meta_is_b[i] <= 1'b0;
						meta_bank[i] <= 1'b0;
						meta_row[i] <= 1'sb0;
						meta_col[i] <= 1'sb0;
						meta_byte_off[i] <= 1'sb0;
						meta_count[i] <= 1'sb0;
						meta_elem_bytes[i] <= 1'sb0;
					end
			end
		end
		else begin
			job_done <= 1'b0;
			job_error <= 1'b0;
			if ((job_valid === 1'b1) && (job_ready === 1'b1)) begin
				job_q <= {job_data[100-:2], job_data[66-:32], job_data[34-:16], job_data[18-:16], job_data[2-:2], job_data[0]};
				next_row <= 1'sb0;
				next_col <= 1'sb0;
				job_last_row_q <= job_data[34-:16] - 16'd1;
				job_last_col_q <= job_data[18-:16] - 16'd1;
				job_last_vec_col_q <= job_data[18-:16] - 16'd4;
				row_base_q <= job_data[98-:32];
				element_addr_q <= job_data[98-:32];
				all_issued <= 1'b0;
				store_source_done <= 1'b0;
				store_pack_valid <= 1'b0;
				store_pack_row_end <= 1'b0;
				store_bytes_seen <= 1'b0;
				store_vector_seen <= 1'b0;
				store_pack_addr <= 1'sb0;
				store_pack_data <= 1'sb0;
				store_pack_strb <= 1'sb0;
				store_bytes_q <= 1'sb0;
				req_hold_valid <= 1'b0;
				dma_req_write_q <= 1'b0;
				dma_req_wdata_q <= 1'sb0;
				dma_req_wstrb_q <= 1'sb0;
				unpack_valid <= 1'b0;
				outstanding <= 1'sb0;
				owned_count <= 1'sb0;
				failing <= 1'b0;
				error_code <= 8'd0;
				partial_output <= 1'b0;
				if ((((((job_data[100-:2] === 2'd0) || (job_data[100-:2] === 2'd1)) && ((job_data[2-:2] === 2'd1) || (job_data[2-:2] === 2'd2))) && (job_data[34-:16] != 0)) && (job_data[18-:16] != 0)) || (((job_data[100-:2] === 2'd2) && (job_data[34-:16] != 0)) && (job_data[18-:16] != 0)))
					job_active <= 1'b1;
				else begin
					job_active <= 1'b0;
					job_error <= 1'b1;
					error_code <= 8'd11;
				end
			end
			else if (job_active) begin
				if (read_req_make) begin
					req_hold_valid <= 1'b1;
					dma_req_write_q <= 1'b0;
					dma_req_addr_q <= element_addr & ~(MEM_BYTES - 1);
					dma_req_wdata_q <= 1'sb0;
					dma_req_wstrb_q <= 1'sb0;
					dma_req_id_q <= sv2v_cast_EFA09(allocated_slot);
					dma_req_slot_q <= allocated_slot;
					meta_valid[allocated_slot] <= 1'b1;
					meta_accepted[allocated_slot] <= 1'b0;
					meta_write[allocated_slot] <= 1'b0;
					meta_is_b[allocated_slot] <= job_q[68-:2] === 2'd1;
					meta_bank[allocated_slot] <= job_q[0];
					meta_row[allocated_slot] <= next_row;
					meta_col[allocated_slot] <= next_col;
					meta_byte_off[allocated_slot] <= element_byte_off;
					meta_count[allocated_slot] <= segment_count;
					meta_elem_bytes[allocated_slot] <= job_q[2-:2];
					if (read_row_last) begin
						next_col <= 1'sb0;
						row_base_q <= row_base_q + job_q[66-:32];
						element_addr_q <= row_base_q + job_q[66-:32];
						if ((next_row + 1'b1) >= job_q[34-:16])
							all_issued <= 1'b1;
						else
							next_row <= next_row + 1'b1;
					end
					else begin
						next_col <= next_col + segment_count_16;
						element_addr_q <= cp12_read_step_address;
					end
				end
				if (store_fire) begin
					if (!store_input_valid) begin
						failing <= 1'b1;
						error_code <= 8'd11;
					end
					else begin
						if (!store_bytes_seen) begin
							store_bytes_seen <= 1'b1;
							store_bytes_q <= store_elem_bytes;
							store_vector_seen <= store_vector;
						end
						if (store_req_make) begin
							req_hold_valid <= 1'b1;
							dma_req_write_q <= 1'b1;
							dma_req_id_q <= sv2v_cast_EFA09(allocated_slot);
							dma_req_slot_q <= allocated_slot;
							meta_valid[allocated_slot] <= 1'b1;
							meta_accepted[allocated_slot] <= 1'b0;
							meta_write[allocated_slot] <= 1'b1;
							meta_is_b[allocated_slot] <= 1'b0;
							meta_bank[allocated_slot] <= 1'b0;
							meta_row[allocated_slot] <= 1'sb0;
							meta_col[allocated_slot] <= 1'sb0;
							meta_byte_off[allocated_slot] <= 1'sb0;
							meta_count[allocated_slot] <= 1'sb0;
							meta_elem_bytes[allocated_slot] <= 1'sb0;
							if (store_pack_valid && !store_same_beat) begin
								dma_req_addr_q <= store_pack_addr;
								dma_req_wdata_q <= store_pack_data;
								dma_req_wstrb_q <= store_pack_strb;
								store_pack_valid <= 1'b1;
								store_pack_row_end <= store_row_last;
								store_pack_addr <= store_elem_beat;
								store_pack_data <= merge_store_data(1'sb0, store_elem_data, store_elem_byte_off, store_elem_bytes);
								store_pack_strb <= merge_store_strb(1'sb0, store_elem_byte_off, store_elem_bytes);
							end
							else begin
								dma_req_addr_q <= (store_pack_valid ? store_pack_addr : store_elem_beat);
								dma_req_wdata_q <= store_merged_data;
								dma_req_wstrb_q <= store_merged_strb;
								store_pack_valid <= 1'b0;
								store_pack_row_end <= 1'b0;
							end
						end
						else begin
							store_pack_valid <= 1'b1;
							store_pack_row_end <= 1'b0;
							store_pack_addr <= store_elem_beat;
							store_pack_data <= store_merged_data;
							store_pack_strb <= store_merged_strb;
						end
						if (store_row_last) begin
							next_col <= 1'sb0;
							row_base_q <= row_base_q + job_q[66-:32];
							element_addr_q <= row_base_q + job_q[66-:32];
							if (store_job_last)
								store_source_done <= 1'b1;
							else
								next_row <= next_row + 1'b1;
						end
						else begin
							next_col <= next_col + store_step;
							element_addr_q <= element_addr_q + (store_vector ? 32'd16 : sv2v_cast_32(store_elem_bytes));
						end
					end
				end
				if (store_tail_make) begin
					req_hold_valid <= 1'b1;
					dma_req_write_q <= 1'b1;
					dma_req_addr_q <= store_pack_addr;
					dma_req_wdata_q <= store_pack_data;
					dma_req_wstrb_q <= store_pack_strb;
					dma_req_id_q <= sv2v_cast_EFA09(allocated_slot);
					dma_req_slot_q <= allocated_slot;
					meta_valid[allocated_slot] <= 1'b1;
					meta_accepted[allocated_slot] <= 1'b0;
					meta_write[allocated_slot] <= 1'b1;
					meta_is_b[allocated_slot] <= 1'b0;
					meta_bank[allocated_slot] <= 1'b0;
					meta_row[allocated_slot] <= 1'sb0;
					meta_col[allocated_slot] <= 1'sb0;
					meta_byte_off[allocated_slot] <= 1'sb0;
					meta_count[allocated_slot] <= 1'sb0;
					meta_elem_bytes[allocated_slot] <= 1'sb0;
					store_pack_valid <= 1'b0;
					store_pack_row_end <= 1'b0;
				end
				if (req_fire) begin
					if ((!read_req_make && !store_req_make) && !store_tail_make)
						req_hold_valid <= 1'b0;
					meta_accepted[dma_req_slot_q] <= 1'b1;
					if (dma_req_write_q)
						partial_output <= 1'b1;
				end
				if (spad_fire) begin
					if (unpack_last)
						unpack_valid <= 1'b0;
					else begin
						unpack_index <= unpack_index + unpack_batch;
						unpack_batch_q <= cp11_batch(unpack_count, unpack_index + unpack_batch, unpack_col, unpack_is_b, unpack_elem_bytes);
						unpack_last_q <= (sv2v_cast_7ADC6(unpack_count) - sv2v_cast_7ADC6(unpack_index + unpack_batch)) == sv2v_cast_7ADC6(cp11_batch(unpack_count, unpack_index + unpack_batch, unpack_col, unpack_is_b, unpack_elem_bytes));
						unpack_current_col_q <= unpack_current_col_q + sv2v_cast_16(unpack_batch);
						if (unpack_is_b)
							unpack_spad_lane_q <= unpack_spad_lane_q + sv2v_cast_3FA0D(unpack_batch);
						else
							unpack_spad_k_q <= unpack_spad_k_q + sv2v_cast_A1A65(unpack_batch);
					end
				end
				if (rsp_fire) begin
					if (rsp_owned) begin
						meta_valid[rsp_slot] <= 1'b0;
						meta_accepted[rsp_slot] <= 1'b0;
					end
				end
				if (read_capture_fire) begin
					unpack_valid <= 1'b1;
					unpack_rdata <= rsp_q_rdata;
					unpack_is_b <= meta_is_b[rsp_slot];
					unpack_bank <= meta_bank[rsp_slot];
					unpack_row <= meta_row[rsp_slot];
					unpack_col <= meta_col[rsp_slot];
					unpack_byte_off <= meta_byte_off[rsp_slot];
					unpack_count <= meta_count[rsp_slot];
					unpack_elem_bytes <= meta_elem_bytes[rsp_slot];
					unpack_index <= 1'sb0;
					unpack_batch_q <= cp11_batch(meta_count[rsp_slot], 1'sb0, meta_col[rsp_slot], meta_is_b[rsp_slot], meta_elem_bytes[rsp_slot]);
					unpack_last_q <= meta_count[rsp_slot] == cp11_batch(meta_count[rsp_slot], 1'sb0, meta_col[rsp_slot], meta_is_b[rsp_slot], meta_elem_bytes[rsp_slot]);
					unpack_current_col_q <= meta_col[rsp_slot];
					unpack_spad_lane_q <= sv2v_cast_3FA0D((meta_is_b[rsp_slot] ? meta_col[rsp_slot] : meta_row[rsp_slot]));
					unpack_spad_k_q <= sv2v_cast_A1A65((meta_is_b[rsp_slot] ? meta_row[rsp_slot] : meta_col[rsp_slot]));
				end
				if (!failing && rsp_error_event) begin
					failing <= 1'b1;
					error_code <= (rsp_owned && (rsp_q_error === 1'b1) ? 8'd6 : 8'd11);
				end
				else if (!failing && allocator_protocol_error) begin
					failing <= 1'b1;
					error_code <= 8'd11;
				end
				else if (!failing && timeout_event) begin
					failing <= 1'b1;
					error_code <= 8'd7;
				end
				if ((((!failing && !rsp_error_event) && !allocator_protocol_error) && !timeout_event) && store_fault_event) begin
					failing <= 1'b1;
					error_code <= 8'd11;
				end
				if (((failing || rsp_error_event) || allocator_protocol_error) || timeout_event)
					store_pack_valid <= 1'b0;
				if (((failing || rsp_error_event) || allocator_protocol_error) || timeout_event)
					store_pack_row_end <= 1'b0;
				case ({req_fire, rsp_owned_fire})
					2'b10: outstanding <= outstanding + 1'b1;
					2'b01: outstanding <= outstanding - 1'b1;
					default: outstanding <= outstanding;
				endcase
				case ({req_reserve, rsp_owned_fire})
					2'b10: owned_count <= owned_count + 1'b1;
					2'b01: owned_count <= owned_count - 1'b1;
					default: owned_count <= owned_count;
				endcase
				if (failure_transition) begin
					job_active <= 1'b0;
					job_error <= 1'b1;
				end
				else if (success_transition && !timeout_event) begin
					job_active <= 1'b0;
					job_done <= 1'b1;
				end
			end
		end
endmodule
module npu_elastic_fifo (
	clk,
	rst,
	in_valid,
	in_ready,
	in_data,
	out_valid,
	out_ready,
	out_data,
	occupancy
);
	parameter signed [31:0] WIDTH = 8;
	parameter signed [31:0] DEPTH = 4;
	parameter signed [31:0] COUNT_W = (DEPTH >= 1 ? $clog2(DEPTH + 1) : 1);
	input wire clk;
	input wire rst;
	input wire in_valid;
	output wire in_ready;
	input wire [WIDTH - 1:0] in_data;
	output wire out_valid;
	input wire out_ready;
	output wire [WIDTH - 1:0] out_data;
	output wire [COUNT_W - 1:0] occupancy;
	localparam signed [31:0] BACKING_DEPTH = (DEPTH > 1 ? DEPTH - 1 : 1);
	localparam signed [31:0] PTR_W = (DEPTH > 2 ? $clog2(DEPTH - 1) : 1);
	reg [WIDTH - 1:0] backing [0:BACKING_DEPTH - 1];
	reg [PTR_W - 1:0] head_q;
	reg [PTR_W - 1:0] tail_q;
	reg [WIDTH - 1:0] out_data_q;
	reg out_valid_q;
	reg [COUNT_W - 1:0] occupancy_q;
	wire push;
	wire pop;
	function automatic signed [PTR_W - 1:0] sv2v_cast_E310E_signed;
		input reg signed [PTR_W - 1:0] inp;
		sv2v_cast_E310E_signed = inp;
	endfunction
	function automatic [PTR_W - 1:0] next_backing_ptr;
		input reg [PTR_W - 1:0] ptr;
		if (DEPTH <= 2)
			next_backing_ptr = 1'sb0;
		else if (ptr == sv2v_cast_E310E_signed(DEPTH - 2))
			next_backing_ptr = 1'sb0;
		else
			next_backing_ptr = ptr + sv2v_cast_E310E_signed(1);
	endfunction
	function automatic signed [COUNT_W - 1:0] sv2v_cast_D4579_signed;
		input reg signed [COUNT_W - 1:0] inp;
		sv2v_cast_D4579_signed = inp;
	endfunction
	assign in_ready = !rst && (occupancy_q < sv2v_cast_D4579_signed(DEPTH));
	assign out_valid = out_valid_q;
	assign out_data = out_data_q;
	assign occupancy = occupancy_q;
	assign push = (in_valid === 1'b1) && in_ready;
	assign pop = out_valid_q && (out_ready === 1'b1);
	always @(posedge clk)
		if (rst) begin
			head_q <= 1'sb0;
			tail_q <= 1'sb0;
			out_data_q <= 1'sb0;
			out_valid_q <= 1'b0;
			occupancy_q <= 1'sb0;
		end
		else
			case ({push, pop})
				2'b10: begin
					if (!out_valid_q) begin
						out_data_q <= in_data;
						out_valid_q <= 1'b1;
					end
					else begin
						backing[tail_q] <= in_data;
						tail_q <= next_backing_ptr(tail_q);
					end
					occupancy_q <= occupancy_q + sv2v_cast_D4579_signed(1);
				end
				2'b01:
					if (occupancy_q > sv2v_cast_D4579_signed(1)) begin
						out_data_q <= backing[head_q];
						head_q <= next_backing_ptr(head_q);
						occupancy_q <= occupancy_q - sv2v_cast_D4579_signed(1);
					end
					else begin
						out_valid_q <= 1'b0;
						occupancy_q <= 1'sb0;
					end
				2'b11:
					if (occupancy_q == sv2v_cast_D4579_signed(1))
						out_data_q <= in_data;
					else begin
						out_data_q <= backing[head_q];
						head_q <= next_backing_ptr(head_q);
						backing[tail_q] <= in_data;
						tail_q <= next_backing_ptr(tail_q);
					end
				default:
					;
			endcase
	generate
		if (WIDTH < 1) begin : g_bad_width
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_elastic_fifo.sv:90:15 - npu_elastic_fifo.g_bad_width.<unnamed_block>\n msg: ", $time, "npu_elastic_fifo: WIDTH must be at least 1");
				$finish(1);
			end
		end
		if (DEPTH < 1) begin : g_bad_depth
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_elastic_fifo.sv:93:15 - npu_elastic_fifo.g_bad_depth.<unnamed_block>\n msg: ", $time, "npu_elastic_fifo: DEPTH must be at least 1");
				$finish(1);
			end
		end
	endgenerate
endmodule
module npu_free_slot_allocator (
	clk,
	rst,
	allocate_take,
	allocate_valid,
	allocate_slot,
	release_valid,
	release_slot,
	free_count,
	protocol_error
);
	reg _sv2v_0;
	parameter signed [31:0] SLOT_COUNT = 4;
	input wire clk;
	input wire rst;
	input wire allocate_take;
	output wire allocate_valid;
	output wire [(SLOT_COUNT > 1 ? $clog2(SLOT_COUNT) : 1) - 1:0] allocate_slot;
	input wire release_valid;
	input wire [(SLOT_COUNT > 1 ? $clog2(SLOT_COUNT) : 1) - 1:0] release_slot;
	output wire [(SLOT_COUNT >= 1 ? $clog2(SLOT_COUNT + 1) : 1) - 1:0] free_count;
	output reg protocol_error;
	localparam signed [31:0] SLOT_W = (SLOT_COUNT > 1 ? $clog2(SLOT_COUNT) : 1);
	localparam signed [31:0] COUNT_W = (SLOT_COUNT >= 1 ? $clog2(SLOT_COUNT + 1) : 1);
	localparam signed [31:0] TREE_LEVELS = (SLOT_COUNT > 1 ? $clog2(SLOT_COUNT) : 0);
	localparam signed [31:0] TREE_LEAVES = 1 << TREE_LEVELS;
	function automatic signed [((SLOT_W + 0) >= 0 ? SLOT_W + 1 : 1 - (SLOT_W + 0)) - 1:0] sv2v_cast_A518B_signed;
		input reg signed [((SLOT_W + 0) >= 0 ? SLOT_W + 1 : 1 - (SLOT_W + 0)) - 1:0] inp;
		sv2v_cast_A518B_signed = inp;
	endfunction
	localparam [SLOT_W:0] SLOT_COUNT_EXT = sv2v_cast_A518B_signed(SLOT_COUNT);
	reg [SLOT_COUNT - 1:0] free_bitmap_q;
	wire [TREE_LEAVES - 1:0] tree_valid [0:TREE_LEVELS];
	wire [SLOT_W - 1:0] tree_slot [0:TREE_LEVELS][0:TREE_LEAVES - 1];
	wire allocate_fire;
	reg release_accept;
	reg release_error;
	reg [COUNT_W - 1:0] free_count_q;
	genvar _gv_leaf_1;
	function automatic signed [SLOT_W - 1:0] sv2v_cast_7C1AF_signed;
		input reg signed [SLOT_W - 1:0] inp;
		sv2v_cast_7C1AF_signed = inp;
	endfunction
	generate
		for (_gv_leaf_1 = 0; _gv_leaf_1 < TREE_LEAVES; _gv_leaf_1 = _gv_leaf_1 + 1) begin : g_tree_leaf
			localparam leaf = _gv_leaf_1;
			if (leaf < SLOT_COUNT) begin : g_physical_slot
				assign tree_valid[0][leaf] = free_bitmap_q[leaf];
			end
			else begin : g_padded_slot
				assign tree_valid[0][leaf] = 1'b0;
			end
			assign tree_slot[0][leaf] = sv2v_cast_7C1AF_signed(leaf);
		end
	endgenerate
	genvar _gv_level_1;
	generate
		for (_gv_level_1 = 1; _gv_level_1 <= TREE_LEVELS; _gv_level_1 = _gv_level_1 + 1) begin : g_tree_level
			localparam level = _gv_level_1;
			genvar _gv_node_1;
			for (_gv_node_1 = 0; _gv_node_1 < TREE_LEAVES; _gv_node_1 = _gv_node_1 + 1) begin : g_tree_node
				localparam node = _gv_node_1;
				if (node < (TREE_LEAVES >> level)) begin : g_parent
					assign tree_valid[level][node] = tree_valid[level - 1][2 * node] | tree_valid[level - 1][(2 * node) + 1];
					assign tree_slot[level][node] = (tree_valid[level - 1][2 * node] ? tree_slot[level - 1][2 * node] : tree_slot[level - 1][(2 * node) + 1]);
				end
				else begin : g_unused
					assign tree_valid[level][node] = 1'b0;
					assign tree_slot[level][node] = 1'sb0;
				end
			end
		end
	endgenerate
	assign allocate_valid = (rst === 1'b0) && tree_valid[TREE_LEVELS][0];
	assign allocate_slot = tree_slot[TREE_LEVELS][0];
	assign allocate_fire = (allocate_take === 1'b1) && allocate_valid;
	assign free_count = free_count_q;
	always @(*) begin
		if (_sv2v_0)
			;
		release_accept = 1'b0;
		release_error = 1'b0;
		if (release_valid === 1'b1) begin
			if (^release_slot === 1'bx)
				release_error = 1'b1;
			else if ({1'b0, release_slot} >= SLOT_COUNT_EXT)
				release_error = 1'b1;
			else if (free_bitmap_q[release_slot] !== 1'b0)
				release_error = 1'b1;
			else
				release_accept = 1'b1;
		end
	end
	function automatic signed [COUNT_W - 1:0] sv2v_cast_D4579_signed;
		input reg signed [COUNT_W - 1:0] inp;
		sv2v_cast_D4579_signed = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			free_bitmap_q <= {SLOT_COUNT {1'b1}};
			free_count_q <= sv2v_cast_D4579_signed(SLOT_COUNT);
			protocol_error <= 1'b0;
		end
		else begin
			if (allocate_fire)
				free_bitmap_q[allocate_slot] <= 1'b0;
			if (release_accept)
				free_bitmap_q[release_slot] <= 1'b1;
			case ({allocate_fire, release_accept})
				2'b10: free_count_q <= free_count_q - sv2v_cast_D4579_signed(1);
				2'b01: free_count_q <= free_count_q + sv2v_cast_D4579_signed(1);
				2'b11: free_count_q <= free_count_q;
				default: free_count_q <= free_count_q;
			endcase
			protocol_error <= release_error;
		end
	generate
		if (SLOT_COUNT < 1) begin : g_bad_slot_count
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_free_slot_allocator.sv:103:15 - npu_free_slot_allocator.g_bad_slot_count.<unnamed_block>\n msg: ", $time, "npu_free_slot_allocator: SLOT_COUNT must be at least 1");
				$finish(1);
			end
		end
	endgenerate
	initial _sv2v_0 = 0;
endmodule
module npu_mac_pe (
	clk,
	rst,
	clear_acc,
	input_int16,
	a_valid_in,
	b_valid_in,
	a_in,
	b_in,
	a_valid_out,
	b_valid_out,
	a_out,
	b_out,
	acc_value
);
	parameter signed [31:0] ACC_W = 48;
	parameter signed [31:0] MUL_PIPE_STAGES = 2;
	input wire clk;
	input wire rst;
	input wire clear_acc;
	input wire input_int16;
	input wire a_valid_in;
	input wire b_valid_in;
	input wire signed [15:0] a_in;
	input wire signed [15:0] b_in;
	output reg a_valid_out;
	output reg b_valid_out;
	output reg signed [15:0] a_out;
	output reg signed [15:0] b_out;
	output wire signed [ACC_W - 1:0] acc_value;
	localparam signed [31:0] INPUT_REG = (MUL_PIPE_STAGES == 2 ? 1 : 0);
	wire signed [15:0] a_signed;
	wire signed [15:0] b_signed;
	reg valid_pipe [0:MUL_PIPE_STAGES - 1];
	wire [47:0] native_p;
	assign a_signed = (input_int16 ? a_in : $signed({{8 {a_in[7]}}, a_in[7:0]}));
	assign b_signed = (input_int16 ? b_in : $signed({{8 {b_in[7]}}, b_in[7:0]}));
	assign acc_value = $signed(native_p);
	always @(posedge clk) begin
		a_out <= a_in;
		b_out <= b_in;
	end
	always @(posedge clk)
		if (rst) begin
			a_valid_out <= 0;
			b_valid_out <= 0;
			begin : sv2v_autoblock_1
				reg signed [31:0] p;
				for (p = 0; p < MUL_PIPE_STAGES; p = p + 1)
					valid_pipe[p] <= 0;
			end
		end
		else begin
			a_valid_out <= a_valid_in;
			b_valid_out <= b_valid_in;
			valid_pipe[0] <= a_valid_in && b_valid_in;
			begin : sv2v_autoblock_2
				reg signed [31:0] p;
				for (p = 1; p < MUL_PIPE_STAGES; p = p + 1)
					valid_pipe[p] <= valid_pipe[p - 1];
			end
		end
	GTP_APM_E2 #(
		.GRS_EN("TRUE"),
		.ASYNC_RST(0),
		.USE_MULT(1),
		.USE_POSTADD(1),
		.USE_PREADD(0),
		.USE_SIMD(0),
		.X_REG(INPUT_REG),
		.Y_REG(INPUT_REG),
		.MULT_REG(1),
		.P_REG(1),
		.Z_REG(0),
		.XB_REG(0),
		.PREADD_REG(0),
		.MODEY_REG(0),
		.MODEZ_REG(0),
		.MODEIN_REG(0),
		.X_SEL(0),
		.XB_SEL(0),
		.P_INIT0(48'd0),
		.P_INIT1(48'd0),
		.ROUNDMODE_SEL(0),
		.USE_ACCLOW(0),
		.CIN_SEL(0)
	) mac(
		.P(native_p),
		.CPO(),
		.COUT(),
		.CXO(),
		.CXBO(),
		.X({{14 {a_signed[15]}}, a_signed}),
		.Y({{2 {b_signed[15]}}, b_signed}),
		.XB(25'd0),
		.CXI(30'd0),
		.CXBI(25'd0),
		.Z(48'd0),
		.CPI(48'd0),
		.CIN(1'b0),
		.MODEIN(5'b00010),
		.MODEY(3'b001),
		.MODEZ(4'b0001),
		.CLK(clk),
		.CEX1(1'b1),
		.CEX2(1'b0),
		.CEX3(1'b0),
		.CEXB(1'b0),
		.CEY1(1'b1),
		.CEY2(1'b0),
		.CEZ(1'b0),
		.CEPRE(1'b0),
		.CEM(1'b1),
		.CEP(valid_pipe[MUL_PIPE_STAGES - 1]),
		.CEMODEY(1'b0),
		.CEMODEZ(1'b0),
		.CEMODEIN(1'b0),
		.RSTX(1'b0),
		.RSTY(1'b0),
		.RSTM(1'b0),
		.RSTP(rst || clear_acc),
		.RSTXB(1'b0),
		.RSTZ(1'b0),
		.RSTPRE(1'b0),
		.RSTMODEY(1'b0),
		.RSTMODEZ(1'b0),
		.RSTMODEIN(1'b0)
	);
	initial if ((ACC_W != 48) || ((MUL_PIPE_STAGES != 1) && (MUL_PIPE_STAGES != 2))) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_mac_pe.sv:59:4 - npu_mac_pe.<unnamed_block>.<unnamed_block>\n msg: ", $time, "APM_MAC48 experimentalconfigurationunsupported");
		$finish(1);
	end
endmodule
module npu_mmio_overlay (
	clk,
	rst,
	perip_addr,
	perip_wdata,
	perip_wen,
	perip_mask,
	legacy_perip_rdata,
	combined_perip_rdata,
	cmd_push_valid,
	cmd_push_ready,
	cmd_push_data,
	cmd_level,
	cmd_empty,
	cmd_full,
	completion_head_valid,
	completion_head_data,
	completion_enqueued,
	completion_pop,
	completion_level,
	completion_empty,
	completion_full,
	active,
	error_event_valid,
	error_event_code,
	error_event_tag,
	soft_reset_req,
	soft_reset_accept,
	irq_status,
	error_status,
	error_tag,
	reject_count,
	irq
);
	parameter signed [31:0] ARRAY_ROWS = 4;
	parameter signed [31:0] ARRAY_COLS = 4;
	parameter signed [31:0] K_TILE = 32;
	parameter signed [31:0] MEM_DATA_W = 32;
	parameter signed [31:0] CMDQ_DEPTH = 4;
	parameter signed [31:0] COMPQ_DEPTH = 4;
	input wire clk;
	input wire rst;
	input wire [31:0] perip_addr;
	input wire [31:0] perip_wdata;
	input wire perip_wen;
	input wire [1:0] perip_mask;
	input wire [31:0] legacy_perip_rdata;
	output wire [31:0] combined_perip_rdata;
	output wire cmd_push_valid;
	input wire cmd_push_ready;
	output wire [347:0] cmd_push_data;
	function automatic integer npu_mmio_count_width;
		input integer depth;
		npu_mmio_count_width = (depth < 2 ? 1 : $clog2(depth + 1));
	endfunction
	input wire [npu_mmio_count_width(CMDQ_DEPTH) - 1:0] cmd_level;
	input wire cmd_empty;
	input wire cmd_full;
	input wire completion_head_valid;
	input wire [136:0] completion_head_data;
	input wire completion_enqueued;
	output reg completion_pop;
	input wire [npu_mmio_count_width(COMPQ_DEPTH) - 1:0] completion_level;
	input wire completion_empty;
	input wire completion_full;
	input wire active;
	input wire error_event_valid;
	input wire [7:0] error_event_code;
	input wire [31:0] error_event_tag;
	output reg soft_reset_req;
	input wire soft_reset_accept;
	output reg [1:0] irq_status;
	output reg [11:0] error_status;
	output reg [31:0] error_tag;
	output reg [31:0] reject_count;
	output wire irq;
	localparam signed [31:0] CMD_LEVEL_W = npu_mmio_count_width(CMDQ_DEPTH);
	localparam signed [31:0] COMP_LEVEL_W = npu_mmio_count_width(COMPQ_DEPTH);
	localparam [31:0] NPU_BASE = 32'h80200200;
	localparam [31:0] CONTROL_WRITABLE = 32'h00000103;
	function automatic integer npu_mmio_log2;
		input integer value;
		npu_mmio_log2 = (value < 1 ? 0 : $clog2(value));
	endfunction
	localparam [31:0] CAP0_VALUE = (((ARRAY_ROWS & 32'h000000ff) | ((ARRAY_COLS & 32'h000000ff) << 8)) | ((npu_mmio_log2(K_TILE) & 32'h000000ff) << 16)) | 32'h01000000;
	localparam [31:0] CAP1_VALUE = (((CMDQ_DEPTH & 32'h000000ff) | ((COMPQ_DEPTH & 32'h000000ff) << 8)) | ((npu_mmio_log2(MEM_DATA_W) & 32'h0000001f) << 16)) | 32'h00e00000;
	wire hit_now;
	reg hit_q1;
	reg hit_q2;
	wire aligned_write;
	wire write_in_window;
	wire write_valid;
	wire [31:0] perip_word_addr;
	reg [31:0] read_data_now;
	reg [31:0] data_q1;
	reg [31:0] data_q2;
	reg completion_irq_enable;
	reg error_irq_enable;
	reg error_tag_valid;
	wire [31:0] action_write_word;
	wire [31:0] control_merged;
	wire [31:0] dim_k_flags_merged;
	wire [31:0] post_cfg_merged;
	reg protocol_error_write;
	wire doorbell_write;
	wire doorbell_admit;
	wire doorbell_reject;
	wire irq_clear_write;
	wire error_clear_write;
	wire completion_ack_write;
	wire soft_reset_write;
	wire reset_busy_error;
	wire external_error_valid;
	wire external_error_new;
	wire rejection_error_new;
	wire protocol_error_new;
	wire reset_busy_error_new;
	wire [3:0] external_error_index;
	reg [347:0] descriptor_shadow;
	function automatic [31:0] merge_store_lane;
		input reg [31:0] old_word;
		input reg [31:0] store_data;
		input reg [1:0] store_mask;
		input reg [1:0] addr_low;
		reg [31:0] merged;
		begin
			merged = old_word;
			case (store_mask)
				2'b10: merged = store_data;
				2'b01:
					if (addr_low[1])
						merged[31:16] = store_data[15:0];
					else
						merged[15:0] = store_data[15:0];
				2'b00:
					case (addr_low)
						2'd0: merged[7:0] = store_data[7:0];
						2'd1: merged[15:8] = store_data[7:0];
						2'd2: merged[23:16] = store_data[7:0];
						default: merged[31:24] = store_data[7:0];
					endcase
				default: merged = old_word;
			endcase
			merge_store_lane = merged;
		end
	endfunction
	function automatic legal_access;
		input reg [1:0] store_mask;
		input reg [1:0] addr_low;
		case (store_mask)
			2'b10: legal_access = addr_low == 2'd0;
			2'b01: legal_access = !addr_low[0];
			2'b00: legal_access = 1'b1;
			default: legal_access = 1'b0;
		endcase
	endfunction
	assign perip_word_addr = {perip_addr[31:2], 2'b00};
	assign hit_now = perip_addr[31:8] == NPU_BASE[31:8];
	assign aligned_write = legal_access(perip_mask, perip_addr[1:0]);
	assign write_in_window = perip_wen && hit_now;
	assign write_valid = write_in_window && aligned_write;
	assign action_write_word = merge_store_lane(32'd0, perip_wdata, perip_mask, perip_addr[1:0]);
	assign control_merged = merge_store_lane({30'h00000000, error_irq_enable, completion_irq_enable}, perip_wdata, perip_mask, perip_addr[1:0]);
	assign dim_k_flags_merged = merge_store_lane({15'd0, descriptor_shadow[203], descriptor_shadow[219-:16]}, perip_wdata, perip_mask, perip_addr[1:0]);
	assign post_cfg_merged = merge_store_lane({21'd0, descriptor_shadow[101-:6], descriptor_shadow[102], descriptor_shadow[104-:2], descriptor_shadow[106-:2]}, perip_wdata, perip_mask, perip_addr[1:0]);
	always @(*) begin
		protocol_error_write = 1'b0;
		if (write_in_window) begin
			if (!aligned_write)
				protocol_error_write = 1'b1;
			else
				case (perip_word_addr)
					NPU_BASE + 32'h00000010: protocol_error_write = |(control_merged & ~CONTROL_WRITABLE);
					NPU_BASE + 32'h00000014: protocol_error_write = |(action_write_word & ~32'h00000003);
					NPU_BASE + 32'h00000020, NPU_BASE + 32'h00000024, NPU_BASE + 32'h00000028, NPU_BASE + 32'h0000002c, NPU_BASE + 32'h00000034, NPU_BASE + 32'h00000038, NPU_BASE + 32'h0000003c, NPU_BASE + 32'h00000044, NPU_BASE + 32'h00000048, NPU_BASE + 32'h0000004c: protocol_error_write = 1'b0;
					NPU_BASE + 32'h00000030: protocol_error_write = |dim_k_flags_merged[31:17];
					NPU_BASE + 32'h00000040: protocol_error_write = ((|post_cfg_merged[31:11] || (post_cfg_merged[1:0] > 2'd2)) || (post_cfg_merged[3:2] > 2'd2)) || (post_cfg_merged[10:5] > 6'd47);
					NPU_BASE + 32'h00000050, NPU_BASE + 32'h00000074: protocol_error_write = |(action_write_word & ~32'h00000001);
					NPU_BASE + 32'h00000078: protocol_error_write = |action_write_word[31:12];
					default: protocol_error_write = 1'b1;
				endcase
		end
	end
	assign doorbell_write = ((write_valid && !protocol_error_write) && (perip_word_addr == (NPU_BASE + 32'h00000050))) && action_write_word[0];
	assign doorbell_admit = doorbell_write && cmd_push_ready;
	assign doorbell_reject = doorbell_write && !cmd_push_ready;
	assign irq_clear_write = (write_valid && !protocol_error_write) && (perip_word_addr == (NPU_BASE + 32'h00000014));
	assign error_clear_write = (write_valid && !protocol_error_write) && (perip_word_addr == (NPU_BASE + 32'h00000078));
	assign completion_ack_write = ((write_valid && !protocol_error_write) && (perip_word_addr == (NPU_BASE + 32'h00000074))) && action_write_word[0];
	assign soft_reset_write = ((write_valid && (perip_word_addr == (NPU_BASE + 32'h00000010))) && !(|(control_merged & ~CONTROL_WRITABLE))) && control_merged[8];
	assign reset_busy_error = soft_reset_write && !soft_reset_accept;
	assign external_error_valid = (error_event_valid && (error_event_code != 8'd0)) && (error_event_code <= 8'd12);
	assign external_error_index = error_event_code[3:0] - 1'b1;
	assign external_error_new = external_error_valid && !error_status[external_error_index];
	assign rejection_error_new = doorbell_reject && !error_status[7];
	assign protocol_error_new = protocol_error_write && !error_status[8];
	assign reset_busy_error_new = reset_busy_error && !error_status[9];
	always @(*) begin
		read_data_now = 32'd0;
		case (perip_word_addr)
			NPU_BASE + 32'h00000000: read_data_now = 32'h4e505531;
			NPU_BASE + 32'h00000004: read_data_now = CAP0_VALUE;
			NPU_BASE + 32'h00000008: read_data_now = CAP1_VALUE;
			NPU_BASE + 32'h0000000c: begin
				read_data_now[0] = !active;
				read_data_now[1] = active;
				read_data_now[2] = cmd_empty;
				read_data_now[3] = cmd_full;
				read_data_now[4] = completion_empty;
				read_data_now[5] = completion_full;
				read_data_now[6] = completion_head_valid;
				read_data_now[7] = |error_status;
			end
			NPU_BASE + 32'h00000010: read_data_now = {30'd0, error_irq_enable, completion_irq_enable};
			NPU_BASE + 32'h00000014: read_data_now = {30'd0, irq_status};
			NPU_BASE + 32'h00000018: begin
				read_data_now[CMD_LEVEL_W - 1:0] = cmd_level;
				read_data_now[8+:COMP_LEVEL_W] = completion_level;
			end
			NPU_BASE + 32'h00000020: read_data_now = descriptor_shadow[347-:32];
			NPU_BASE + 32'h00000024: read_data_now = descriptor_shadow[315-:32];
			NPU_BASE + 32'h00000028: read_data_now = descriptor_shadow[283-:32];
			NPU_BASE + 32'h0000002c: read_data_now = {descriptor_shadow[235-:16], descriptor_shadow[251-:16]};
			NPU_BASE + 32'h00000030: read_data_now = {15'd0, descriptor_shadow[203], descriptor_shadow[219-:16]};
			NPU_BASE + 32'h00000034: read_data_now = descriptor_shadow[202-:32];
			NPU_BASE + 32'h00000038: read_data_now = descriptor_shadow[170-:32];
			NPU_BASE + 32'h0000003c: read_data_now = descriptor_shadow[138-:32];
			NPU_BASE + 32'h00000040: read_data_now = {21'd0, descriptor_shadow[101-:6], descriptor_shadow[102], descriptor_shadow[104-:2], descriptor_shadow[106-:2]};
			NPU_BASE + 32'h00000044: read_data_now = $signed(descriptor_shadow[95-:32]);
			NPU_BASE + 32'h00000048: read_data_now = $signed(descriptor_shadow[63-:32]);
			NPU_BASE + 32'h0000004c: read_data_now = descriptor_shadow[31-:32];
			NPU_BASE + 32'h00000060:
				if (completion_head_valid)
					read_data_now = completion_head_data[136-:32];
			NPU_BASE + 32'h00000064:
				if (completion_head_valid)
					read_data_now = {23'd0, completion_head_data[96], completion_head_data[104-:8]};
			NPU_BASE + 32'h00000068:
				if (completion_head_valid)
					read_data_now = completion_head_data[95-:32];
			NPU_BASE + 32'h0000006c:
				if (completion_head_valid)
					read_data_now = completion_head_data[31:0];
			NPU_BASE + 32'h00000070:
				if (completion_head_valid)
					read_data_now = completion_head_data[63:32];
			NPU_BASE + 32'h00000078: read_data_now = {20'd0, error_status};
			NPU_BASE + 32'h0000007c:
				if (error_tag_valid)
					read_data_now = error_tag;
			NPU_BASE + 32'h00000080: read_data_now = reject_count;
			default: read_data_now = 32'd0;
		endcase
	end
	always @(posedge clk)
		if (rst) begin
			hit_q1 <= 1'b0;
			hit_q2 <= 1'b0;
			data_q1 <= 32'd0;
			data_q2 <= 32'd0;
		end
		else begin
			hit_q1 <= hit_now && !perip_wen;
			hit_q2 <= hit_q1;
			data_q1 <= read_data_now;
			data_q2 <= data_q1;
		end
	always @(posedge clk)
		if (rst) begin
			descriptor_shadow <= 1'sb0;
			completion_irq_enable <= 1'b0;
			error_irq_enable <= 1'b0;
			completion_pop <= 1'b0;
			soft_reset_req <= 1'b0;
			irq_status <= 1'sb0;
			error_status <= 1'sb0;
			error_tag <= 1'sb0;
			error_tag_valid <= 1'b0;
			reject_count <= 1'sb0;
		end
		else begin
			completion_pop <= 1'b0;
			soft_reset_req <= 1'b0;
			if (soft_reset_write && soft_reset_accept) begin
				descriptor_shadow <= 1'sb0;
				completion_irq_enable <= 1'b0;
				error_irq_enable <= 1'b0;
				irq_status <= 1'sb0;
				error_status <= 1'sb0;
				error_tag <= 1'sb0;
				error_tag_valid <= 1'b0;
				reject_count <= 1'sb0;
				soft_reset_req <= 1'b1;
			end
			else begin
				if (write_valid && !protocol_error_write)
					case (perip_word_addr)
						NPU_BASE + 32'h00000010:
							if (!soft_reset_write) begin
								completion_irq_enable <= control_merged[0];
								error_irq_enable <= control_merged[1];
							end
						NPU_BASE + 32'h00000020: descriptor_shadow[347-:32] <= merge_store_lane(descriptor_shadow[347-:32], perip_wdata, perip_mask, perip_addr[1:0]);
						NPU_BASE + 32'h00000024: descriptor_shadow[315-:32] <= merge_store_lane(descriptor_shadow[315-:32], perip_wdata, perip_mask, perip_addr[1:0]);
						NPU_BASE + 32'h00000028: descriptor_shadow[283-:32] <= merge_store_lane(descriptor_shadow[283-:32], perip_wdata, perip_mask, perip_addr[1:0]);
						NPU_BASE + 32'h0000002c: {descriptor_shadow[235-:16], descriptor_shadow[251-:16]} <= merge_store_lane({descriptor_shadow[235-:16], descriptor_shadow[251-:16]}, perip_wdata, perip_mask, perip_addr[1:0]);
						NPU_BASE + 32'h00000030: {descriptor_shadow[203], descriptor_shadow[219-:16]} <= dim_k_flags_merged[16:0];
						NPU_BASE + 32'h00000034: descriptor_shadow[202-:32] <= merge_store_lane(descriptor_shadow[202-:32], perip_wdata, perip_mask, perip_addr[1:0]);
						NPU_BASE + 32'h00000038: descriptor_shadow[170-:32] <= merge_store_lane(descriptor_shadow[170-:32], perip_wdata, perip_mask, perip_addr[1:0]);
						NPU_BASE + 32'h0000003c: descriptor_shadow[138-:32] <= merge_store_lane(descriptor_shadow[138-:32], perip_wdata, perip_mask, perip_addr[1:0]);
						NPU_BASE + 32'h00000040: begin
							descriptor_shadow[106-:2] <= post_cfg_merged[1:0];
							descriptor_shadow[104-:2] <= post_cfg_merged[3:2];
							descriptor_shadow[102] <= post_cfg_merged[4];
							descriptor_shadow[101-:6] <= post_cfg_merged[10:5];
						end
						NPU_BASE + 32'h00000044: descriptor_shadow[95-:32] <= merge_store_lane($signed(descriptor_shadow[95-:32]), perip_wdata, perip_mask, perip_addr[1:0]);
						NPU_BASE + 32'h00000048: descriptor_shadow[63-:32] <= merge_store_lane($signed(descriptor_shadow[63-:32]), perip_wdata, perip_mask, perip_addr[1:0]);
						NPU_BASE + 32'h0000004c: descriptor_shadow[31-:32] <= merge_store_lane(descriptor_shadow[31-:32], perip_wdata, perip_mask, perip_addr[1:0]);
						default:
							;
					endcase
				if (completion_ack_write)
					completion_pop <= 1'b1;
				if (soft_reset_write)
					soft_reset_req <= 1'b1;
				if (irq_clear_write)
					irq_status <= irq_status & ~action_write_word[1:0];
				if (completion_enqueued)
					irq_status[0] <= 1'b1;
				if (((external_error_new || rejection_error_new) || protocol_error_new) || reset_busy_error_new)
					irq_status[1] <= 1'b1;
				if (error_clear_write)
					error_status <= error_status & ~action_write_word[11:0];
				if (external_error_valid)
					error_status[external_error_index] <= 1'b1;
				if (doorbell_reject)
					error_status[7] <= 1'b1;
				if (protocol_error_write)
					error_status[8] <= 1'b1;
				if (reset_busy_error)
					error_status[9] <= 1'b1;
				if ((error_clear_write && action_write_word[7]) && !doorbell_reject) begin
					error_tag <= 1'sb0;
					error_tag_valid <= 1'b0;
				end
				if (doorbell_reject) begin
					if (!error_tag_valid) begin
						error_tag <= descriptor_shadow[31-:32];
						error_tag_valid <= 1'b1;
					end
					if (reject_count != 32'hffffffff)
						reject_count <= reject_count + 1'b1;
				end
			end
		end
	assign cmd_push_valid = doorbell_admit;
	assign cmd_push_data = descriptor_shadow;
	assign combined_perip_rdata = (hit_q2 ? data_q2 : legacy_perip_rdata);
	assign irq = (completion_irq_enable && irq_status[0]) || (error_irq_enable && irq_status[1]);
	generate
		if (!(((CMDQ_DEPTH >= 2) && (CMDQ_DEPTH <= 128)) && ((CMDQ_DEPTH & (CMDQ_DEPTH - 1)) == 0))) begin : g_invalid_cmdq_depth
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_mmio_overlay.sv:313:15 - npu_mmio_overlay.g_invalid_cmdq_depth.<unnamed_block>\n msg: ", $time, "npu_mmio_overlay: CMDQ_DEPTH must be a power of two from 2 through 128");
				$finish(1);
			end
		end
		if (!(((COMPQ_DEPTH >= 2) && (COMPQ_DEPTH <= 128)) && ((COMPQ_DEPTH & (COMPQ_DEPTH - 1)) == 0))) begin : g_invalid_compq_depth
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_mmio_overlay.sv:317:15 - npu_mmio_overlay.g_invalid_compq_depth.<unnamed_block>\n msg: ", $time, "npu_mmio_overlay: COMPQ_DEPTH must be a power of two from 2 through 128");
				$finish(1);
			end
		end
	endgenerate
endmodule
module npu_postprocess (
	clk,
	rst,
	in_valid,
	in_ready,
	in_value,
	output_fmt,
	activation,
	rounding,
	shift,
	clamp_min,
	clamp_max,
	out_valid,
	out_ready,
	out_value,
	out_bytes
);
	parameter signed [31:0] ACC_W = 48;
	input wire clk;
	input wire rst;
	input wire in_valid;
	output wire in_ready;
	input wire signed [ACC_W - 1:0] in_value;
	input wire [1:0] output_fmt;
	input wire [1:0] activation;
	input wire rounding;
	input wire [5:0] shift;
	input wire signed [31:0] clamp_min;
	input wire signed [31:0] clamp_max;
	output wire out_valid;
	input wire out_ready;
	output wire signed [31:0] out_value;
	output wire [2:0] out_bytes;
	localparam signed [ACC_W - 1:0] INT8_MIN = {{ACC_W - 8 {1'b1}}, 8'h80};
	localparam signed [ACC_W - 1:0] INT8_MAX = {{ACC_W - 8 {1'b0}}, 8'h7f};
	localparam signed [ACC_W - 1:0] INT16_MIN = {{ACC_W - 16 {1'b1}}, 16'h8000};
	localparam signed [ACC_W - 1:0] INT16_MAX = {{ACC_W - 16 {1'b0}}, 16'h7fff};
	localparam signed [ACC_W - 1:0] INT32_MIN = {{ACC_W - 32 {1'b1}}, 32'h80000000};
	localparam signed [ACC_W - 1:0] INT32_MAX = {{ACC_W - 32 {1'b0}}, 32'h7fffffff};
	reg s1_valid;
	reg s2_valid;
	reg s3_valid;
	wire s1_ready;
	wire s2_ready;
	wire s3_ready;
	reg signed [ACC_W - 1:0] s1_value;
	reg signed [ACC_W - 1:0] s2_value;
	reg [1:0] s1_output_fmt;
	reg [1:0] s1_activation;
	reg [1:0] s2_output_fmt;
	reg signed [31:0] s1_clamp_min;
	reg signed [31:0] s1_clamp_max;
	reg signed [31:0] s3_value;
	reg [2:0] s3_bytes;
	reg output_fmt_valid;
	reg activation_valid;
	reg rounding_valid;
	reg shift_valid;
	reg clamp_valid;
	reg config_valid;
	function automatic known_word32;
		input reg [31:0] value;
		begin
			known_word32 = 1'b1;
			begin : sv2v_autoblock_1
				reg [31:0] bit_index;
				for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
					case (value[bit_index])
						1'b0, 1'b1:
							;
						default: known_word32 = 1'b0;
					endcase
			end
		end
	endfunction
	function automatic signed [ACC_W - 1:0] sv2v_cast_60BB9_signed;
		input reg signed [ACC_W - 1:0] inp;
		sv2v_cast_60BB9_signed = inp;
	endfunction
	function automatic signed [ACC_W - 1:0] round_shift;
		input reg signed [ACC_W - 1:0] value;
		input reg round_en;
		input reg [5:0] shift_amount;
		reg signed [ACC_W:0] value_ext;
		reg signed [ACC_W:0] bias;
		reg signed [ACC_W:0] unit_value;
		begin
			value_ext = {value[ACC_W - 1], value};
			bias = 1'sb0;
			unit_value = {{ACC_W {1'b0}}, 1'b1};
			if (round_en && (shift_amount != 6'd0)) begin
				bias = unit_value <<< (shift_amount - 6'd1);
				if (value < 0)
					bias = bias - unit_value;
			end
			round_shift = sv2v_cast_60BB9_signed((value_ext + bias) >>> shift_amount);
		end
	endfunction
	function automatic signed [ACC_W - 1:0] apply_activation;
		input reg signed [ACC_W - 1:0] value;
		input reg [1:0] activation_mode;
		input reg signed [31:0] min_value;
		input reg signed [31:0] max_value;
		reg signed [ACC_W - 1:0] min_ext;
		reg signed [ACC_W - 1:0] max_ext;
		begin
			min_ext = {{ACC_W - 32 {min_value[31]}}, min_value};
			max_ext = {{ACC_W - 32 {max_value[31]}}, max_value};
			case (activation_mode)
				2'd1: apply_activation = (value < 0 ? {ACC_W {1'sb0}} : value);
				2'd2: apply_activation = (value < min_ext ? min_ext : (value > max_ext ? max_ext : value));
				default: apply_activation = value;
			endcase
		end
	endfunction
	function automatic signed [31:0] saturate_value;
		input reg signed [ACC_W - 1:0] value;
		input reg [1:0] format;
		case (format)
			2'd0:
				if (value > INT8_MAX)
					saturate_value = 32'sd127;
				else if (value < INT8_MIN)
					saturate_value = -32'sd128;
				else
					saturate_value = {{24 {value[7]}}, value[7:0]};
			2'd1:
				if (value > INT16_MAX)
					saturate_value = 32'sd32767;
				else if (value < INT16_MIN)
					saturate_value = -32'sd32768;
				else
					saturate_value = {{16 {value[15]}}, value[15:0]};
			2'd2:
				if (value > INT32_MAX)
					saturate_value = 32'sh7fffffff;
				else if (value < INT32_MIN)
					saturate_value = -32'sh80000000;
				else
					saturate_value = value[31:0];
			default: saturate_value = 1'sb0;
		endcase
	endfunction
	function automatic [2:0] format_bytes;
		input reg [1:0] format;
		case (format)
			2'd0: format_bytes = 3'd1;
			2'd1: format_bytes = 3'd2;
			2'd2: format_bytes = 3'd4;
			default: format_bytes = 3'd0;
		endcase
	endfunction
	function automatic signed [6:0] sv2v_cast_7_signed;
		input reg signed [6:0] inp;
		sv2v_cast_7_signed = inp;
	endfunction
	always @(*) begin
		output_fmt_valid = 1'b0;
		activation_valid = 1'b0;
		rounding_valid = 1'b0;
		shift_valid = 1'b0;
		case (output_fmt)
			2'd0, 2'd1, 2'd2: output_fmt_valid = 1'b1;
			default: output_fmt_valid = 1'b0;
		endcase
		case (activation)
			2'd0, 2'd1, 2'd2: activation_valid = 1'b1;
			default: activation_valid = 1'b0;
		endcase
		case (rounding)
			1'b0, 1'b1: rounding_valid = 1'b1;
			default: rounding_valid = 1'b0;
		endcase
		shift_valid = (^shift !== 1'bx) && ({1'b0, shift} < sv2v_cast_7_signed(ACC_W));
		clamp_valid = 1'b1;
		case (activation)
			2'd2:
				if (!known_word32(clamp_min) || !known_word32(clamp_max))
					clamp_valid = 1'b0;
				else if ($signed(clamp_min) > $signed(clamp_max))
					clamp_valid = 1'b0;
			default: clamp_valid = 1'b1;
		endcase
		config_valid = (((output_fmt_valid && activation_valid) && rounding_valid) && shift_valid) && clamp_valid;
	end
	assign s3_ready = !s3_valid || out_ready;
	assign s2_ready = !s2_valid || s3_ready;
	assign s1_ready = !s1_valid || s2_ready;
	assign in_ready = (!rst && config_valid) && s1_ready;
	assign out_valid = s3_valid;
	assign out_value = s3_value;
	assign out_bytes = s3_bytes;
	initial if ((ACC_W < 32) || (ACC_W > 64)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_postprocess.sv:175:7 - npu_postprocess.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_postprocess: ACC_W must be in [32,64]");
		$finish(1);
	end
	always @(posedge clk)
		if (rst) begin
			s1_valid <= 1'b0;
			s2_valid <= 1'b0;
			s3_valid <= 1'b0;
			s1_value <= 1'sb0;
			s2_value <= 1'sb0;
			s1_output_fmt <= 1'sb0;
			s2_output_fmt <= 1'sb0;
			s1_activation <= 1'sb0;
			s1_clamp_min <= 1'sb0;
			s1_clamp_max <= 1'sb0;
			s3_value <= 1'sb0;
			s3_bytes <= 1'sb0;
		end
		else begin
			if (s3_ready) begin
				s3_valid <= s2_valid;
				if (s2_valid) begin
					s3_value <= saturate_value(s2_value, s2_output_fmt);
					s3_bytes <= format_bytes(s2_output_fmt);
				end
			end
			if (s2_ready) begin
				s2_valid <= s1_valid;
				if (s1_valid) begin
					s2_value <= apply_activation(s1_value, s1_activation, s1_clamp_min, s1_clamp_max);
					s2_output_fmt <= s1_output_fmt;
				end
			end
			if (s1_ready) begin
				s1_valid <= in_valid && config_valid;
				if (in_valid && config_valid) begin
					s1_value <= round_shift(in_value, rounding, shift);
					s1_output_fmt <= output_fmt;
					s1_activation <= activation;
					s1_clamp_min <= clamp_min;
					s1_clamp_max <= clamp_max;
				end
			end
		end
endmodule
module npu_scheduler (
	clk,
	rst,
	result_page_enable,
	resident_compute_mode,
	resident_operands_ready,
	resident_read_k,
	result_context,
	result_dma_outstanding,
	result_order_idle,
	result_order_poison,
	result_array_read_enable,
	result_array_read_row,
	result_array_row_data,
	result_protocol_error,
	cmd_valid,
	cmd_ready,
	cmd_data,
	reserve_valid,
	reserve_ready,
	completion_valid,
	completion_ready,
	completion_data,
	dma_job_valid,
	dma_job_ready,
	dma_job_data,
	dma_job_done,
	dma_job_error,
	dma_error_code,
	dma_partial_output,
	spad_owner_valid,
	spad_owner_is_b,
	spad_owner_bank,
	spad_owner_state,
	spad_a_owner,
	spad_b_owner,
	spad_protocol_error,
	spad_compute_read_valid,
	spad_compute_bank,
	spad_compute_k,
	spad_compute_read_data_valid,
	spad_a_vector,
	spad_b_vector,
	array_start_valid,
	array_start_ready,
	array_k_len,
	array_row_mask,
	array_col_mask,
	array_continue_acc,
	array_input_int16,
	array_feed_valid,
	array_feed_ready,
	array_feed_a,
	array_feed_b,
	array_done,
	array_acc_read_row,
	array_acc_read_col,
	array_acc_rdata,
	post_in_valid,
	post_in_ready,
	post_in_value,
	post_output_fmt,
	post_activation,
	post_rounding,
	post_shift,
	post_clamp_min,
	post_clamp_max,
	post_out_valid,
	post_out_ready,
	post_out_value,
	post_out_bytes,
	store_elem_vector4,
	store_elem_vector_data,
	store_elem_valid,
	store_elem_ready,
	store_elem_data,
	store_elem_bytes,
	store_elem_row,
	store_elem_col,
	resident_k_base,
	resident_claim,
	resident_n_group,
	active
);
	reg _sv2v_0;
	parameter signed [31:0] ARRAY_ROWS = 4;
	parameter signed [31:0] ARRAY_COLS = 4;
	parameter signed [31:0] K_TILE = 32;
	parameter signed [31:0] ACC_W = 48;
	parameter [0:0] RESULT_PAGE_STORE = 1'b0;
	parameter [0:0] STORE_VECTOR4_ENABLE = 1'b0;
	parameter [0:0] RESIDENT_FULL_K_ENABLE = 1'b1;
	parameter [0:0] RESIDENT_GROUP_REUSE_ENABLE = 1'b1;
	parameter signed [31:0] RESULT_CHUNK_COLUMNS = 256;
	parameter [31:0] DRAM_BASE = 32'h80100000;
	parameter [32:0] DRAM_BYTES = 33'h000040000;
	input wire clk;
	input wire rst;
	input wire result_page_enable;
	input wire resident_compute_mode;
	input wire resident_operands_ready;
	output wire [10:0] resident_read_k;
	input wire [127:0] result_context;
	input wire [4:0] result_dma_outstanding;
	input wire result_order_idle;
	input wire result_order_poison;
	output wire result_array_read_enable;
	output wire [(ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1) - 1:0] result_array_read_row;
	input wire [(ARRAY_COLS * ACC_W) - 1:0] result_array_row_data;
	output wire result_protocol_error;
	input wire cmd_valid;
	output reg cmd_ready;
	input wire [347:0] cmd_data;
	output reg reserve_valid;
	input wire reserve_ready;
	output reg completion_valid;
	input wire completion_ready;
	output reg [136:0] completion_data;
	output reg dma_job_valid;
	input wire dma_job_ready;
	output reg [100:0] dma_job_data;
	input wire dma_job_done;
	input wire dma_job_error;
	input wire [7:0] dma_error_code;
	input wire dma_partial_output;
	output reg spad_owner_valid;
	output reg spad_owner_is_b;
	output reg spad_owner_bank;
	output reg [1:0] spad_owner_state;
	input wire [3:0] spad_a_owner;
	input wire [3:0] spad_b_owner;
	input wire spad_protocol_error;
	output reg spad_compute_read_valid;
	output reg spad_compute_bank;
	output reg [(K_TILE > 1 ? $clog2(K_TILE) : 1) - 1:0] spad_compute_k;
	input wire spad_compute_read_data_valid;
	input wire signed [(ARRAY_ROWS * 16) - 1:0] spad_a_vector;
	input wire signed [(ARRAY_COLS * 16) - 1:0] spad_b_vector;
	output reg array_start_valid;
	input wire array_start_ready;
	output reg [15:0] array_k_len;
	output reg [ARRAY_ROWS - 1:0] array_row_mask;
	output reg [ARRAY_COLS - 1:0] array_col_mask;
	output reg array_continue_acc;
	output reg array_input_int16;
	output reg array_feed_valid;
	input wire array_feed_ready;
	output reg signed [(ARRAY_ROWS * 16) - 1:0] array_feed_a;
	output reg signed [(ARRAY_COLS * 16) - 1:0] array_feed_b;
	input wire array_done;
	output reg [(ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1) - 1:0] array_acc_read_row;
	output reg [(ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1) - 1:0] array_acc_read_col;
	input wire signed [ACC_W - 1:0] array_acc_rdata;
	output reg post_in_valid;
	input wire post_in_ready;
	output reg signed [ACC_W - 1:0] post_in_value;
	output reg [1:0] post_output_fmt;
	output reg [1:0] post_activation;
	output reg post_rounding;
	output reg [5:0] post_shift;
	output reg signed [31:0] post_clamp_min;
	output reg signed [31:0] post_clamp_max;
	input wire post_out_valid;
	output reg post_out_ready;
	input wire signed [31:0] post_out_value;
	input wire [2:0] post_out_bytes;
	output reg store_elem_vector4;
	output reg [127:0] store_elem_vector_data;
	output reg store_elem_valid;
	input wire store_elem_ready;
	output reg signed [31:0] store_elem_data;
	output reg [2:0] store_elem_bytes;
	output reg [15:0] store_elem_row;
	output reg [15:0] store_elem_col;
	output wire [10:0] resident_k_base;
	output wire resident_claim;
	output wire [4:0] resident_n_group;
	output reg active;
	reg [15:0] k0;
	assign resident_k_base = k0[10:0];
	localparam signed [31:0] K_W = (K_TILE > 1 ? $clog2(K_TILE) : 1);
	localparam signed [31:0] EXEC_COUNT_W = (RESIDENT_FULL_K_ENABLE ? ((K_W + 1) > 11 ? K_W + 1 : 11) : K_W + 1);
	reg [EXEC_COUNT_W - 1:0] read_issue_count;
	function automatic [10:0] sv2v_cast_11;
		input reg [10:0] inp;
		sv2v_cast_11 = inp;
	endfunction
	assign resident_read_k = k0[10:0] + sv2v_cast_11(read_issue_count);
	reg [4:0] state;
	assign resident_claim = (state == 5'd8) && spad_owner_valid;
	reg [15:0] n0;
	assign resident_n_group = n0[7:3];
	localparam [1:0] OWNER_EMPTY = 2'd0;
	localparam [1:0] OWNER_FILLING = 2'd1;
	localparam [1:0] OWNER_READY = 2'd2;
	localparam [1:0] OWNER_COMPUTE = 2'd3;
	localparam signed [31:0] ROW_W = (ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1);
	localparam signed [31:0] COL_W = (ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1);
	localparam signed [31:0] CELL_W = $clog2((ARRAY_ROWS * ARRAY_COLS) + 1);
	function automatic signed [15:0] sv2v_cast_16_signed;
		input reg signed [15:0] inp;
		sv2v_cast_16_signed = inp;
	endfunction
	localparam [15:0] ARRAY_ROWS_COUNT = sv2v_cast_16_signed(ARRAY_ROWS);
	localparam [15:0] ARRAY_COLS_COUNT = sv2v_cast_16_signed(ARRAY_COLS);
	localparam [15:0] K_TILE_COUNT = sv2v_cast_16_signed(K_TILE);
	function automatic signed [6:0] sv2v_cast_7_signed;
		input reg signed [6:0] inp;
		sv2v_cast_7_signed = inp;
	endfunction
	localparam [6:0] ACC_W_COUNT = sv2v_cast_7_signed(ACC_W);
	reg [3:0] load_state;
	reg [347:0] cmd_q;
	reg [136:0] completion_q;
	reg [100:0] load_job_q;
	reg [100:0] store_job_q;
	reg [7:0] validation_error;
	reg [7:0] pending_error;
	reg [31:0] cycle_count;
	reg [2:0] input_bytes;
	reg [2:0] output_bytes;
	reg [64:0] a_row_bytes_q;
	reg [64:0] b_row_bytes_q;
	reg [64:0] c_row_bytes_q;
	reg [64:0] a_stride_product_q;
	reg [64:0] b_stride_product_q;
	reg [64:0] c_stride_product_q;
	reg [64:0] a_last_q;
	reg [64:0] b_last_q;
	reg [64:0] c_last_q;
	reg [64:0] dram_limit;
	reg descriptor_known_q;
	reg [63:0] mn_q;
	reg [63:0] macs_q;
	reg [15:0] m_prev_q;
	reg [15:0] k_prev_q;
	reg [31:0] a_lo_q;
	reg [31:0] a_hi_q;
	reg [31:0] b_lo_q;
	reg [31:0] b_hi_q;
	reg [31:0] c_lo_q;
	reg [31:0] c_hi_q;
	reg [31:0] mac_lo_q;
	reg [31:0] mac_hi_q;
	reg [31:0] load_a_lo_q;
	reg [31:0] load_a_hi_q;
	reg [31:0] load_b_lo_q;
	reg [31:0] load_b_hi_q;
	reg [31:0] load_a_offset_q;
	reg [31:0] load_b_offset_q;
	reg [31:0] load_a_col_q;
	reg [31:0] load_b_col_q;
	reg [31:0] store_c_lo_q;
	reg [31:0] store_c_hi_q;
	reg [31:0] store_c_offset_q;
	reg [31:0] store_c_col_q;
	function automatic [31:0] product16;
		input reg [15:0] x;
		input reg [15:0] y;
		product16 = x * y;
	endfunction
	function automatic [47:0] join_product;
		input reg [31:0] lo;
		input reg [31:0] hi;
		join_product = {16'd0, lo} + {hi, 16'd0};
	endfunction
	function automatic [17:0] element_bytes;
		input reg [15:0] elements;
		input reg [2:0] bytes_per_element;
		case (bytes_per_element)
			3'd1: element_bytes = {2'd0, elements};
			3'd2: element_bytes = {1'd0, elements, 1'd0};
			3'd4: element_bytes = {elements, 2'd0};
			default: element_bytes = 1'sb0;
		endcase
	endfunction
	reg [15:0] m0;
	reg [15:0] tile_m_len;
	reg [15:0] tile_n_len;
	wire [15:0] tile_k_len;
	wire [15:0] next_tile_k_len;
	wire [15:0] legacy_tile_k_len;
	reg resident_full_k_q;
	reg [16:0] m_after_tile;
	reg [16:0] n_after_tile;
	reg [16:0] k_after_tile;
	reg has_next_k;
	reg has_next_output;
	reg has_next_m;
	reg has_next_n;
	reg compute_bank;
	reg [EXEC_COUNT_W - 1:0] array_feed_accept_count;
	reg [EXEC_COUNT_W - 1:0] exec_k_len_q;
	reg [ARRAY_ROWS - 1:0] exec_row_mask_q;
	reg [ARRAY_COLS - 1:0] exec_col_mask_q;
	reg exec_continue_q;
	reg exec_int16_q;
	reg exec_has_next_k_q;
	reg feed_q0_valid;
	reg feed_q1_valid;
	reg signed [(ARRAY_ROWS * 16) - 1:0] feed_a_q0;
	reg signed [(ARRAY_ROWS * 16) - 1:0] feed_a_q1;
	reg signed [(ARRAY_COLS * 16) - 1:0] feed_b_q0;
	reg signed [(ARRAY_COLS * 16) - 1:0] feed_b_q1;
	reg feed_push;
	reg feed_pop;
	reg [2:0] feed_slots_after_edge;
	reg array_done_seen;
	reg runtime_error;
	reg after_release_next_k;
	reg error_after_release;
	reg load_launch;
	reg load_launch_ready;
	reg load_result_ack;
	reg load_bank_q;
	reg load_need_a;
	reg load_need_b;
	reg load_selected_b;
	reg load_last_grant_b;
	reg [15:0] load_m0;
	reg [15:0] load_n0;
	reg [15:0] load_k0;
	reg [15:0] load_m_len;
	reg [15:0] load_n_len;
	reg [15:0] load_k_len;
	reg [7:0] load_error_q;
	reg [15:0] drain_issue_row;
	reg [15:0] drain_issue_col;
	reg [15:0] store_out_row_q;
	reg [15:0] store_out_col_q;
	reg wb_q0_valid;
	reg wb_q1_valid;
	reg signed [31:0] wb_data_q0;
	reg signed [31:0] wb_data_q1;
	reg [2:0] wb_bytes_q0;
	reg [2:0] wb_bytes_q1;
	reg [15:0] wb_row_q0;
	reg [15:0] wb_row_q1;
	reg [15:0] wb_col_q0;
	reg [15:0] wb_col_q1;
	reg [31:0] post_in_count;
	reg [31:0] post_out_count;
	reg [31:0] tile_cell_count_q;
	reg [31:0] tile_cell_last_q;
	reg [ROW_W:0] tile_m_len_preq;
	reg [COL_W:0] tile_n_len_preq;
	wire [CELL_W - 1:0] tile_cell_count_calc;
	reg [CELL_W - 1:0] tile_cell_count_preq;
	reg acc_pending_valid;
	reg [31:0] discard_remaining;
	reg pending_partial_output;
	reg cleanup_all_empty;
	reg cleanup_owner_valid;
	reg cleanup_owner_is_b;
	reg cleanup_owner_bank;
	reg [1:0] cleanup_owner_state;
	wire post_in_fire;
	wire post_out_fire;
	wire store_elem_fire;
	reg page_mode_q;
	reg page_slot_q;
	reg page_chunked_q;
	reg page_warm_q;
	reg [8:0] page_columns_q;
	reg [15:0] page_end_q;
	reg [4:0] page_group_origin_q;
	reg [31:0] page_c_base_q;
	reg [7:0] page_failure_q;
	wire resident_candidate = (((((((RESIDENT_FULL_K_ENABLE && (resident_compute_mode === 1'b1)) && !cmd_data[203]) && (cmd_data[251-:16] > 0)) && (cmd_data[251-:16] <= 16)) && (cmd_data[235-:16] > 0)) && (cmd_data[235-:16] <= 256)) && (cmd_data[219-:16] > 0)) && (cmd_data[219-:16] <= 1152);
	wire chunk_candidate = ((RESULT_CHUNK_COLUMNS < 256) && RESIDENT_GROUP_REUSE_ENABLE) && resident_candidate;
	function automatic signed [8:0] sv2v_cast_9_signed;
		input reg signed [8:0] inp;
		sv2v_cast_9_signed = inp;
	endfunction
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	wire [8:0] initial_page_columns = (chunk_candidate && (cmd_data[235-:16] > sv2v_cast_16_signed(RESULT_CHUNK_COLUMNS)) ? sv2v_cast_9_signed(RESULT_CHUNK_COLUMNS) : sv2v_cast_9(cmd_data[235-:16]));
	wire [15:0] page_remaining = cmd_q[235-:16] - page_end_q;
	wire [8:0] next_page_columns = (page_remaining > sv2v_cast_16_signed(RESULT_CHUNK_COLUMNS) ? sv2v_cast_9_signed(RESULT_CHUNK_COLUMNS) : sv2v_cast_9(page_remaining));
	wire page_more = page_chunked_q && (page_end_q < cmd_q[235-:16]);
	reg [255:0] page_identity_q;
	wire page_bank_ready;
	wire page_bank_poison;
	wire page_capture_ready;
	wire page_capture_busy;
	wire page_capture_done;
	wire page_capture_cancelled;
	wire page_capture_bad;
	wire page_capture_valid;
	wire page_capture_write_ready;
	wire [4:0] page_capture_row;
	wire [4:0] page_capture_group;
	wire [3:0] page_read_row;
	wire [383:0] page_capture_values;
	wire [3:0] page_owners;
	wire page_claim;
	wire page_store_slot;
	wire page_claim_ready;
	wire page_bank_read;
	wire page_bank_read_ready;
	wire [255:0] page_bank_identity;
	wire [255:0] page_bank_output;
	wire [4:0] page_bank_row;
	wire [4:0] page_bank_group;
	wire [31:0] page_bank_strobe;
	wire page_bank_valid;
	wire page_bank_output_ready;
	wire page_release;
	wire page_retired;
	wire page_failed;
	wire page_store_ready;
	wire page_store_busy;
	wire page_store_done;
	wire page_store_cancelled;
	wire page_store_poison;
	wire page_dma_valid;
	wire page_dma_ready;
	wire page_stream_valid;
	wire [100:0] page_dma_job;
	wire [7:0] page_store_error;
	wire signed [31:0] page_stream_data;
	wire page_stream_vector4;
	wire [127:0] page_stream_vector_data;
	wire [2:0] page_stream_bytes;
	wire [15:0] page_stream_row;
	wire [15:0] page_stream_col;
	wire page_grant = (page_store_busy || (state == 5'd23)) || (state == 5'd24);
	wire page_abort = (((page_mode_q && (state == 5'd17)) && !page_capture_busy) && !page_capture_valid) && ((page_slot_q ? page_owners[3:2] : page_owners[1:0]) == 1);
	wire page_discard = (((page_mode_q && (state == 5'd17)) && !page_capture_busy) && !page_store_busy) && ((page_slot_q ? page_owners[3:2] : page_owners[1:0]) == 2);
	wire page_cleanup_idle = !page_mode_q || ((((page_owners == 0) && !page_capture_busy) && !page_store_busy) && !page_bank_valid);
	wire page_return_error = page_store_done && ((page_store_error != 8'd0) || page_store_cancelled);
	wire page_capture_cancel = (runtime_error || spad_protocol_error) || page_return_error;
	assign result_protocol_error = (page_bank_poison || page_store_poison) || page_capture_bad;
	function automatic [ROW_W - 1:0] sv2v_cast_8E462;
		input reg [ROW_W - 1:0] inp;
		sv2v_cast_8E462 = inp;
	endfunction
	assign result_array_read_row = sv2v_cast_8E462(page_read_row);
	assign page_dma_ready = page_grant && dma_job_ready;
	function automatic [5:0] sv2v_cast_6;
		input reg [5:0] inp;
		sv2v_cast_6 = inp;
	endfunction
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	generate
		if (RESULT_PAGE_STORE) begin : g_result_page
			npu_result_rows #(
				.BANK_ROWS(16),
				.BANK_COLUMNS(256)
			) bank(
				.clk(clk),
				.rst(rst),
				.write_begin((((state == 5'd19) && page_bank_ready) && !page_capture_cancel) && (!page_warm_q || resident_operands_ready)),
				.write_slot(page_slot_q),
				.write_identity(page_identity_q),
				.rows(sv2v_cast_6(cmd_q[251-:16])),
				.columns(page_columns_q),
				.write_begin_ready(page_bank_ready),
				.write_valid(page_capture_valid),
				.write_row(page_capture_row),
				.write_group(page_capture_group),
				.write_ACC48(page_capture_values),
				.write_ready(page_capture_write_ready),
				.write_commit((state == 5'd22) && !page_capture_cancel),
				.write_abort(page_abort),
				.store_claim(page_claim),
				.store_slot((page_discard ? page_slot_q : page_store_slot)),
				.expected_identity((page_discard ? page_identity_q : page_bank_identity)),
				.store_claim_ready(page_claim_ready),
				.read_valid(page_bank_read),
				.read_row(page_bank_row),
				.read_group(page_bank_group),
				.read_ready(page_bank_read_ready),
				.output_valid(page_bank_valid),
				.output_ready(page_bank_output_ready),
				.output_INT32(page_bank_output),
				.output_strobe(page_bank_strobe),
				.store_release(page_release),
				.real_B_retired(page_retired),
				.store_failed(page_failed),
				.discard_ready(page_discard),
				.owners(page_owners),
				.protocol_poison(page_bank_poison),
				.captured_rows(),
				.consumed_groups()
			);
			npu_row_result_capture capture(
				.clk(clk),
				.rst(rst),
				.start_valid((state == 5'd20) && !page_capture_cancel),
				.start_ready(page_capture_ready),
				.tile_rows(sv2v_cast_5(tile_m_len)),
				.row_base(5'd0),
				.channel_group(n0[7:3] - page_group_origin_q),
				.cancel(page_capture_cancel),
				.array_read_enable(result_array_read_enable),
				.array_read_row(page_read_row),
				.array_row_ACC48(result_array_row_data),
				.write_valid(page_capture_valid),
				.write_ready(page_capture_write_ready),
				.write_row(page_capture_row),
				.write_group(page_capture_group),
				.write_ACC48(page_capture_values),
				.busy(page_capture_busy),
				.done_pulse(page_capture_done),
				.cancelled(page_capture_cancelled),
				.bad_start(page_capture_bad),
				.rows_captured()
			);
			npu_result_store_bridge #(
				.MAX_COLUMNS(256),
				.VECTOR4_ENABLE(STORE_VECTOR4_ENABLE)
			) store_bridge(
				.clk(clk),
				.rst(rst),
				.start_valid((state == 5'd23) && !page_capture_cancel),
				.start_ready(page_store_ready),
				.start_slot(page_slot_q),
				.start_identity(page_identity_q),
				.start_rows(sv2v_cast_5(cmd_q[251-:16])),
				.start_columns(page_columns_q),
				.start_base(page_c_base_q),
				.start_stride(cmd_q[138-:32]),
				.cancel(1'b0),
				.DMA_exclusive_grant(page_grant),
				.bank_claim(page_claim),
				.bank_slot(page_store_slot),
				.bank_identity(page_bank_identity),
				.bank_claim_ready(page_claim_ready),
				.bank_read_valid(page_bank_read),
				.bank_read_row(page_bank_row),
				.bank_read_group(page_bank_group),
				.bank_read_ready(page_bank_read_ready),
				.bank_output_valid(page_bank_valid),
				.bank_output_ready(page_bank_output_ready),
				.bank_output_INT32(page_bank_output),
				.bank_output_strobe(page_bank_strobe),
				.bank_release(page_release),
				.bank_real_B_retired(page_retired),
				.bank_store_failed(page_failed),
				.bank_poison(page_bank_poison),
				.dma_job_valid(page_dma_valid),
				.dma_job_ready(page_dma_ready),
				.dma_job(page_dma_job),
				.dma_job_done(page_grant && dma_job_done),
				.dma_job_error(page_grant && dma_job_error),
				.dma_error_code(dma_error_code),
				.dma_outstanding(result_dma_outstanding),
				.response_order_idle(result_order_idle),
				.response_order_poison(result_order_poison),
				.store_elem_vector4(page_stream_vector4),
				.store_elem_vector_data(page_stream_vector_data),
				.store_elem_valid(page_stream_valid),
				.store_elem_ready(store_elem_ready && page_grant),
				.store_elem_data(page_stream_data),
				.store_elem_bytes(page_stream_bytes),
				.store_elem_row(page_stream_row),
				.store_elem_col(page_stream_col),
				.busy(page_store_busy),
				.done(page_store_done),
				.cancelled(page_store_cancelled),
				.protocol_poison(page_store_poison),
				.error_code(page_store_error),
				.streamed_elements(),
				.stream_stall_cycles(),
				.real_retire_wait_cycles()
			);
		end
		else begin : g_no_result_page
			assign page_bank_ready = 1'b0;
			assign page_bank_poison = 1'b0;
			assign page_owners = 0;
			assign page_capture_ready = 1'b0;
			assign page_capture_busy = 1'b0;
			assign page_capture_done = 1'b0;
			assign page_capture_cancelled = 1'b0;
			assign page_capture_bad = 1'b0;
			assign page_capture_valid = 1'b0;
			assign page_capture_row = 0;
			assign page_capture_group = 0;
			assign page_capture_values = 0;
			assign page_read_row = 0;
			assign result_array_read_enable = 1'b0;
			assign page_bank_valid = 1'b0;
			assign page_store_ready = 1'b0;
			assign page_store_busy = 1'b0;
			assign page_store_done = 1'b0;
			assign page_store_poison = 1'b0;
			assign page_store_cancelled = 1'b0;
			assign page_dma_valid = 1'b0;
			assign page_dma_job = 1'sb0;
			assign page_store_error = 8'd0;
			assign page_stream_valid = 1'b0;
			assign page_stream_data = 0;
			assign page_stream_vector4 = 1'b0;
			assign page_stream_vector_data = 1'sb0;
			assign page_stream_bytes = 0;
			assign page_stream_row = 0;
			assign page_stream_col = 0;
		end
	endgenerate
	function automatic [ARRAY_ROWS - 1:0] make_row_mask;
		input reg [15:0] length;
		begin
			make_row_mask = 1'sb0;
			begin : sv2v_autoblock_1
				reg signed [31:0] row_index;
				for (row_index = 0; row_index < ARRAY_ROWS; row_index = row_index + 1)
					if (row_index < length)
						make_row_mask[row_index] = 1'b1;
			end
		end
	endfunction
	function automatic [ARRAY_COLS - 1:0] make_col_mask;
		input reg [15:0] length;
		begin
			make_col_mask = 1'sb0;
			begin : sv2v_autoblock_2
				reg signed [31:0] col_index;
				for (col_index = 0; col_index < ARRAY_COLS; col_index = col_index + 1)
					if (col_index < length)
						make_col_mask[col_index] = 1'b1;
			end
		end
	endfunction
	function automatic known_word32;
		input reg [31:0] value;
		known_word32 = ^value !== 1'bx;
	endfunction
	function automatic [31:0] increment_saturating;
		input reg [31:0] value;
		increment_saturating = (&value ? value : value + 1'b1);
	endfunction
	always @(*) begin
		input_bytes = (cmd_q[203] ? 3'd2 : 3'd1);
		case (cmd_q[106-:2])
			2'd0: output_bytes = 3'd1;
			2'd1: output_bytes = 3'd2;
			2'd2: output_bytes = 3'd4;
			default: output_bytes = 3'd0;
		endcase
		dram_limit = {33'd0, DRAM_BASE} + {32'd0, DRAM_BYTES};
		validation_error = 8'd0;
		if ((((((^cmd_q[251-:16] === 1'bx) || (^cmd_q[235-:16] === 1'bx)) || (^cmd_q[219-:16] === 1'bx)) || (cmd_q[251-:16] == 0)) || (cmd_q[235-:16] == 0)) || (cmd_q[219-:16] == 0))
			validation_error = 8'd1;
		else if (((((((cmd_q[203] !== 1'b0) && (cmd_q[203] !== 1'b1)) || !(((cmd_q[106-:2] === 2'd0) || (cmd_q[106-:2] === 2'd1)) || (cmd_q[106-:2] === 2'd2))) || !(((cmd_q[104-:2] === 2'd0) || (cmd_q[104-:2] === 2'd1)) || (cmd_q[104-:2] === 2'd2))) || ((cmd_q[102] !== 1'b0) && (cmd_q[102] !== 1'b1))) || (^cmd_q[101-:6] === 1'bx)) || ({1'b0, cmd_q[101-:6]} >= ACC_W_COUNT))
			validation_error = 8'd2;
		else if (((cmd_q[203] && (((cmd_q[316] || cmd_q[284]) || cmd_q[171]) || cmd_q[139])) || ((output_bytes == 3'd2) && (cmd_q[252] || cmd_q[107]))) || ((output_bytes == 3'd4) && ((cmd_q[253:252] != 2'b00) || (cmd_q[108:107] != 2'b00))))
			validation_error = 8'd3;
		else if ((({33'd0, cmd_q[202-:32]} < a_row_bytes_q) || ({33'd0, cmd_q[170-:32]} < b_row_bytes_q)) || ({33'd0, cmd_q[138-:32]} < c_row_bytes_q))
			validation_error = 8'd4;
		else if ((cmd_q[104-:2] === 2'd2) && (((^$signed(cmd_q[95-:32]) === 1'bx) || (^$signed(cmd_q[63-:32]) === 1'bx)) || ($signed($signed(cmd_q[95-:32])) > $signed($signed(cmd_q[63-:32])))))
			validation_error = 8'd2;
		else if (((((((((!descriptor_known_q || ({33'd0, cmd_q[347-:32]} < {33'd0, DRAM_BASE})) || ({33'd0, cmd_q[315-:32]} < {33'd0, DRAM_BASE})) || ({33'd0, cmd_q[283-:32]} < {33'd0, DRAM_BASE})) || |a_last_q[64:32]) || |b_last_q[64:32]) || |c_last_q[64:32]) || (a_last_q >= dram_limit)) || (b_last_q >= dram_limit)) || (c_last_q >= dram_limit))
			validation_error = 8'd5;
		else if ((({33'd0, cmd_q[283-:32]} <= a_last_q) && ({33'd0, cmd_q[347-:32]} <= c_last_q)) || (({33'd0, cmd_q[283-:32]} <= b_last_q) && ({33'd0, cmd_q[315-:32]} <= c_last_q)))
			validation_error = 8'd12;
	end
	cp13_k_lengths #(.K_TILE(K_TILE)) cp13_lengths(
		.k(cmd_q[219-:16]),
		.k0(k0),
		.current_len(legacy_tile_k_len),
		.next_len(next_tile_k_len)
	);
	assign tile_k_len = (resident_full_k_q ? cmd_q[219-:16] : legacy_tile_k_len);
	function automatic [CELL_W - 1:0] sv2v_cast_CB91D;
		input reg [CELL_W - 1:0] inp;
		sv2v_cast_CB91D = inp;
	endfunction
	assign tile_cell_count_calc = sv2v_cast_CB91D(tile_m_len_preq) * sv2v_cast_CB91D(tile_n_len_preq);
	function automatic [((ROW_W + 0) >= 0 ? ROW_W + 1 : 1 - (ROW_W + 0)) - 1:0] sv2v_cast_AEB46;
		input reg [((ROW_W + 0) >= 0 ? ROW_W + 1 : 1 - (ROW_W + 0)) - 1:0] inp;
		sv2v_cast_AEB46 = inp;
	endfunction
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	function automatic [((COL_W + 0) >= 0 ? COL_W + 1 : 1 - (COL_W + 0)) - 1:0] sv2v_cast_AB00C;
		input reg [((COL_W + 0) >= 0 ? COL_W + 1 : 1 - (COL_W + 0)) - 1:0] inp;
		sv2v_cast_AB00C = inp;
	endfunction
	always @(*) begin
		tile_m_len = cmd_q[251-:16] - m0;
		if (tile_m_len > ARRAY_ROWS_COUNT)
			tile_m_len = ARRAY_ROWS_COUNT;
		tile_m_len = sv2v_cast_16(sv2v_cast_AEB46(tile_m_len));
		tile_n_len = cmd_q[235-:16] - n0;
		if (tile_n_len > ARRAY_COLS_COUNT)
			tile_n_len = ARRAY_COLS_COUNT;
		tile_n_len = sv2v_cast_16(sv2v_cast_AB00C(tile_n_len));
		m_after_tile = {1'b0, m0} + {1'b0, tile_m_len};
		n_after_tile = {1'b0, n0} + {1'b0, tile_n_len};
		k_after_tile = {1'b0, k0} + {1'b0, tile_k_len};
		has_next_m = ({1'b0, m0} + {1'b0, ARRAY_ROWS_COUNT}) < {1'b0, cmd_q[251-:16]};
		has_next_n = ({1'b0, n0} + {1'b0, ARRAY_COLS_COUNT}) < {1'b0, cmd_q[235-:16]};
		has_next_k = !resident_full_k_q && (({1'b0, k0} + {1'b0, K_TILE_COUNT}) < {1'b0, cmd_q[219-:16]});
		has_next_output = has_next_n || has_next_m;
		cleanup_owner_valid = 1'b0;
		cleanup_owner_is_b = 1'b0;
		cleanup_owner_bank = 1'b0;
		cleanup_owner_state = OWNER_EMPTY;
		if (spad_a_owner[1:0] != OWNER_EMPTY) begin
			cleanup_owner_valid = 1'b1;
			cleanup_owner_is_b = 1'b0;
			cleanup_owner_bank = 1'b0;
			case (spad_a_owner[1:0])
				OWNER_FILLING: cleanup_owner_state = OWNER_READY;
				OWNER_READY: cleanup_owner_state = OWNER_COMPUTE;
				default: cleanup_owner_state = OWNER_EMPTY;
			endcase
		end
		else if (spad_a_owner[3:2] != OWNER_EMPTY) begin
			cleanup_owner_valid = 1'b1;
			cleanup_owner_is_b = 1'b0;
			cleanup_owner_bank = 1'b1;
			case (spad_a_owner[3:2])
				OWNER_FILLING: cleanup_owner_state = OWNER_READY;
				OWNER_READY: cleanup_owner_state = OWNER_COMPUTE;
				default: cleanup_owner_state = OWNER_EMPTY;
			endcase
		end
		else if (spad_b_owner[1:0] != OWNER_EMPTY) begin
			cleanup_owner_valid = 1'b1;
			cleanup_owner_is_b = 1'b1;
			cleanup_owner_bank = 1'b0;
			case (spad_b_owner[1:0])
				OWNER_FILLING: cleanup_owner_state = OWNER_READY;
				OWNER_READY: cleanup_owner_state = OWNER_COMPUTE;
				default: cleanup_owner_state = OWNER_EMPTY;
			endcase
		end
		else if (spad_b_owner[3:2] != OWNER_EMPTY) begin
			cleanup_owner_valid = 1'b1;
			cleanup_owner_is_b = 1'b1;
			cleanup_owner_bank = 1'b1;
			case (spad_b_owner[3:2])
				OWNER_FILLING: cleanup_owner_state = OWNER_READY;
				OWNER_READY: cleanup_owner_state = OWNER_COMPUTE;
				default: cleanup_owner_state = OWNER_EMPTY;
			endcase
		end
		cleanup_all_empty = !cleanup_owner_valid;
		load_launch_ready = load_state == 4'd0;
		load_launch = (!runtime_error && !spad_protocol_error) && ((state == 5'd5) || ((((state == 5'd9) && array_start_ready) && exec_has_next_k_q) && load_launch_ready));
		load_result_ack = (((state == 5'd6) && ((load_state == 4'd7) || (load_state == 4'd8))) || ((((state == 5'd10) && (array_done_seen || array_done)) && has_next_k) && ((load_state == 4'd7) || (load_state == 4'd8)))) || ((state == 5'd17) && ((load_state == 4'd7) || (load_state == 4'd8)));
	end
	always @(*) begin
		cmd_ready = (!rst && (state == 5'd0)) && reserve_ready;
		reserve_valid = (!rst && (state == 5'd0)) && cmd_valid;
		completion_valid = state == 5'd18;
		completion_data = completion_q;
		dma_job_valid = 1'b0;
		dma_job_data = 1'sb0;
		if (((load_state == 4'd4) && !runtime_error) && !spad_protocol_error) begin
			dma_job_valid = 1'b1;
			dma_job_data = load_job_q;
		end
		else if (((state == 5'd14) && !runtime_error) && !spad_protocol_error) begin
			dma_job_valid = 1'b1;
			dma_job_data = store_job_q;
		end
		else if (page_grant) begin
			dma_job_valid = page_dma_valid;
			dma_job_data = page_dma_job;
		end
		spad_owner_valid = 1'b0;
		spad_owner_is_b = 1'b0;
		spad_owner_bank = 1'b0;
		spad_owner_state = OWNER_EMPTY;
		case (load_state)
			4'd1: begin
				spad_owner_valid = 1'b1;
				spad_owner_bank = load_bank_q;
				spad_owner_state = OWNER_FILLING;
			end
			4'd2: begin
				spad_owner_valid = 1'b1;
				spad_owner_is_b = 1'b1;
				spad_owner_bank = load_bank_q;
				spad_owner_state = OWNER_FILLING;
			end
			4'd6: begin
				spad_owner_valid = 1'b1;
				spad_owner_is_b = load_selected_b;
				spad_owner_bank = load_bank_q;
				spad_owner_state = OWNER_READY;
			end
			default:
				case (state)
					5'd25, 5'd26, 5'd27, 5'd28: begin
						spad_owner_valid = resident_operands_ready;
						spad_owner_bank = compute_bank;
						spad_owner_is_b = (state == 5'd26) || (state == 5'd28);
						spad_owner_state = ((state == 5'd25) || (state == 5'd26) ? OWNER_FILLING : OWNER_READY);
					end
					5'd7: begin
						spad_owner_valid = 1'b1;
						spad_owner_bank = compute_bank;
						spad_owner_state = OWNER_COMPUTE;
					end
					5'd8: begin
						spad_owner_valid = 1'b1;
						spad_owner_is_b = 1'b1;
						spad_owner_bank = compute_bank;
						spad_owner_state = OWNER_COMPUTE;
					end
					5'd11: begin
						spad_owner_valid = 1'b1;
						spad_owner_bank = compute_bank;
						spad_owner_state = OWNER_EMPTY;
					end
					5'd12: begin
						spad_owner_valid = 1'b1;
						spad_owner_is_b = 1'b1;
						spad_owner_bank = compute_bank;
						spad_owner_state = OWNER_EMPTY;
					end
					5'd17: begin
						spad_owner_valid = cleanup_owner_valid && (load_state == 4'd0);
						spad_owner_is_b = cleanup_owner_is_b;
						spad_owner_bank = cleanup_owner_bank;
						spad_owner_state = cleanup_owner_state;
					end
					default:
						;
				endcase
		endcase
		if (((state != 5'd17) && (state != 5'd16)) && (runtime_error || spad_protocol_error))
			spad_owner_valid = 1'b0;
		feed_push = (state == 5'd10) && spad_compute_read_data_valid;
		feed_pop = (((state == 5'd10) || (state == 5'd16)) && feed_q0_valid) && array_feed_ready;
		feed_slots_after_edge = (({2'd0, feed_q0_valid} + {2'd0, feed_q1_valid}) + {2'd0, feed_push}) - {2'd0, feed_pop};
		spad_compute_read_valid = ((((state == 5'd10) && !runtime_error) && !spad_protocol_error) && (read_issue_count < exec_k_len_q)) && (feed_slots_after_edge < 2);
		spad_compute_bank = compute_bank;
		spad_compute_k = read_issue_count[K_W - 1:0];
		array_start_valid = (((state == 5'd9) && !runtime_error) && !spad_protocol_error) && (!exec_has_next_k_q || load_launch_ready);
		array_k_len = sv2v_cast_16(exec_k_len_q);
		array_row_mask = exec_row_mask_q;
		array_col_mask = exec_col_mask_q;
		array_continue_acc = exec_continue_q;
		array_input_int16 = exec_int16_q;
		array_feed_valid = ((state == 5'd10) && feed_q0_valid) || ((state == 5'd16) && (array_feed_accept_count < exec_k_len_q));
		array_feed_a = ((state == 5'd16) && !feed_q0_valid ? {ARRAY_ROWS * 16 {1'sb0}} : feed_a_q0);
		array_feed_b = ((state == 5'd16) && !feed_q0_valid ? {ARRAY_COLS * 16 {1'sb0}} : feed_b_q0);
		array_acc_read_row = drain_issue_row[ROW_W - 1:0];
		array_acc_read_col = drain_issue_col[COL_W - 1:0];
		post_in_valid = ((state == 5'd15) && acc_pending_valid) && !dma_job_error;
		post_in_value = array_acc_rdata;
		post_output_fmt = cmd_q[106-:2];
		post_activation = cmd_q[104-:2];
		post_rounding = cmd_q[102];
		post_shift = cmd_q[101-:6];
		post_clamp_min = $signed(cmd_q[95-:32]);
		post_clamp_max = $signed(cmd_q[63-:32]);
		post_out_ready = 1'b0;
		if (state == 5'd15)
			post_out_ready = !wb_q1_valid && !dma_job_error;
		else if ((state == 5'd17) && (discard_remaining != 0))
			post_out_ready = 1'b1;
		store_elem_vector4 = 1'b0;
		store_elem_vector_data = 1'sb0;
		store_elem_valid = 1'b0;
		if ((state == 5'd15) && !dma_job_error)
			store_elem_valid = wb_q0_valid;
		store_elem_data = wb_data_q0;
		store_elem_bytes = wb_bytes_q0;
		store_elem_row = wb_row_q0;
		store_elem_col = wb_col_q0;
		if (page_grant) begin
			store_elem_vector4 = page_stream_vector4;
			store_elem_vector_data = page_stream_vector_data;
			store_elem_valid = page_stream_valid;
			store_elem_data = page_stream_data;
			store_elem_bytes = page_stream_bytes;
			store_elem_row = page_stream_row;
			store_elem_col = page_stream_col;
		end
		active = state != 5'd0;
	end
	assign post_in_fire = post_in_valid && post_in_ready;
	assign post_out_fire = post_out_valid && post_out_ready;
	wire post_out_fire_drain;
	assign post_out_fire_drain = (((state == 5'd15) && post_out_valid) && !wb_q1_valid) && !dma_job_error;
	wire post_count_complete;
	assign post_count_complete = (post_out_fire_drain ? post_out_count == tile_cell_last_q : post_out_count == tile_cell_count_q);
	wire [31:0] post_pending_base;
	reg [31:0] post_pending_after_fire;
	assign post_pending_base = post_in_count - post_out_count;
	always @(*) begin
		if (_sv2v_0)
			;
		case ({post_in_fire, post_out_fire_drain})
			2'b10: post_pending_after_fire = post_pending_base + 32'd1;
			2'b01: post_pending_after_fire = post_pending_base - 32'd1;
			default: post_pending_after_fire = post_pending_base;
		endcase
	end
	assign store_elem_fire = store_elem_valid && store_elem_ready;
	initial begin
		if (((ARRAY_ROWS < 2) || (ARRAY_ROWS > 16)) || ((ARRAY_ROWS & (ARRAY_ROWS - 1)) != 0)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_scheduler.sv:723:7 - npu_scheduler.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_scheduler: ARRAY_ROWS must be a power of two from 2 to 16");
			$finish(1);
		end
		if (((ARRAY_COLS < 2) || (ARRAY_COLS > 16)) || ((ARRAY_COLS & (ARRAY_COLS - 1)) != 0)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_scheduler.sv:726:7 - npu_scheduler.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_scheduler: ARRAY_COLS must be a power of two from 2 to 16");
			$finish(1);
		end
		if (((K_TILE < 8) || (K_TILE > 256)) || ((K_TILE & (K_TILE - 1)) != 0)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_scheduler.sv:728:7 - npu_scheduler.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_scheduler: K_TILE must be a power of two from 8 to 256");
			$finish(1);
		end
		if ((ACC_W < 48) || (ACC_W > 64)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_scheduler.sv:730:7 - npu_scheduler.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_scheduler: ACC_W must be in [48,64]");
			$finish(1);
		end
		if ((DRAM_BYTES == 0) || (({33'd0, DRAM_BASE} + {32'd0, DRAM_BYTES}) > 65'h00000000100000000)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/npu_scheduler.sv:733:7 - npu_scheduler.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_scheduler: DRAM aperture must fit the 32-bit address space");
			$finish(1);
		end
	end
	always @(posedge clk)
		if (rst) begin
			load_state <= 4'd0;
			load_job_q <= 1'sb0;
			load_bank_q <= 1'b0;
			load_need_a <= 1'b0;
			load_need_b <= 1'b0;
			load_selected_b <= 1'b0;
			load_last_grant_b <= 1'b1;
			load_m0 <= 1'sb0;
			load_n0 <= 1'sb0;
			load_k0 <= 1'sb0;
			load_m_len <= 1'sb0;
			load_n_len <= 1'sb0;
			load_k_len <= 1'sb0;
			load_error_q <= 8'd0;
			load_a_lo_q <= 1'sb0;
			load_a_hi_q <= 1'sb0;
			load_b_lo_q <= 1'sb0;
			load_b_hi_q <= 1'sb0;
			load_a_offset_q <= 1'sb0;
			load_b_offset_q <= 1'sb0;
			load_a_col_q <= 1'sb0;
			load_b_col_q <= 1'sb0;
		end
		else
			case (load_state)
				4'd0:
					if (load_launch && load_launch_ready) begin
						load_bank_q <= (state == 5'd9 ? ~compute_bank : compute_bank);
						load_need_a <= 1'b1;
						load_need_b <= 1'b1;
						load_m0 <= m0;
						load_n0 <= n0;
						load_m_len <= tile_m_len;
						load_n_len <= tile_n_len;
						if (state == 5'd9) begin
							load_k0 <= k_after_tile[15:0];
							load_k_len <= next_tile_k_len;
						end
						else begin
							load_k0 <= k0;
							load_k_len <= tile_k_len;
						end
						load_error_q <= 8'd0;
						load_state <= 4'd1;
					end
				4'd1: begin
					load_a_lo_q <= product16(load_m0, cmd_q[186:171]);
					load_a_hi_q <= product16(load_m0, cmd_q[202:187]);
					load_b_lo_q <= product16(load_k0, cmd_q[154:139]);
					load_b_hi_q <= product16(load_k0, cmd_q[170:155]);
					load_a_col_q <= {14'd0, element_bytes(load_k0, input_bytes)};
					load_b_col_q <= {14'd0, element_bytes(load_n0, input_bytes)};
					load_state <= 4'd2;
				end
				4'd2: begin
					load_a_offset_q <= load_a_lo_q + {load_a_hi_q[15:0], 16'd0};
					load_b_offset_q <= load_b_lo_q + {load_b_hi_q[15:0], 16'd0};
					if (runtime_error || spad_protocol_error) begin
						load_error_q <= 8'd11;
						load_state <= 4'd8;
					end
					else
						load_state <= 4'd3;
				end
				4'd3:
					if (runtime_error || spad_protocol_error) begin
						load_error_q <= 8'd11;
						load_state <= 4'd8;
					end
					else if (!load_need_a && !load_need_b)
						load_state <= 4'd7;
					else if (load_need_b && (!load_need_a || !load_last_grant_b)) begin
						load_selected_b <= 1'b1;
						load_job_q[100-:2] <= 2'd1;
						load_job_q[98-:32] <= (cmd_q[315-:32] + load_b_offset_q) + load_b_col_q;
						load_job_q[66-:32] <= cmd_q[170-:32];
						load_job_q[34-:16] <= load_k_len;
						load_job_q[18-:16] <= load_n_len;
						load_job_q[2-:2] <= input_bytes[1:0];
						load_job_q[0] <= load_bank_q;
						load_state <= 4'd4;
					end
					else begin
						load_selected_b <= 1'b0;
						load_job_q[100-:2] <= 2'd0;
						load_job_q[98-:32] <= (cmd_q[347-:32] + load_a_offset_q) + load_a_col_q;
						load_job_q[66-:32] <= cmd_q[202-:32];
						load_job_q[34-:16] <= load_m_len;
						load_job_q[18-:16] <= load_k_len;
						load_job_q[2-:2] <= input_bytes[1:0];
						load_job_q[0] <= load_bank_q;
						load_state <= 4'd4;
					end
				4'd4:
					if (runtime_error || spad_protocol_error) begin
						load_error_q <= 8'd11;
						load_state <= 4'd8;
					end
					else if (dma_job_valid && dma_job_ready)
						load_state <= 4'd5;
				4'd5:
					if (runtime_error || spad_protocol_error) begin
						if (dma_job_error || dma_job_done) begin
							load_error_q <= 8'd11;
							load_state <= 4'd8;
						end
					end
					else if (dma_job_error) begin
						load_error_q <= (dma_error_code == 8'd0 ? 8'd11 : dma_error_code);
						load_state <= 4'd8;
					end
					else if (dma_job_done)
						load_state <= 4'd6;
				4'd6:
					if (runtime_error || spad_protocol_error) begin
						load_error_q <= 8'd11;
						load_state <= 4'd8;
					end
					else begin
						if (load_selected_b)
							load_need_b <= 1'b0;
						else
							load_need_a <= 1'b0;
						load_last_grant_b <= load_selected_b;
						load_state <= 4'd3;
					end
				4'd7, 4'd8:
					if (load_result_ack)
						load_state <= 4'd0;
				default: load_state <= 4'd0;
			endcase
	function automatic signed [CELL_W - 1:0] sv2v_cast_CB91D_signed;
		input reg signed [CELL_W - 1:0] inp;
		sv2v_cast_CB91D_signed = inp;
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [EXEC_COUNT_W - 1:0] sv2v_cast_86116;
		input reg [EXEC_COUNT_W - 1:0] inp;
		sv2v_cast_86116 = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			state <= 5'd0;
			cmd_q <= 1'sb0;
			completion_q <= 1'sb0;
			store_job_q <= 1'sb0;
			cycle_count <= 1'sb0;
			a_stride_product_q <= 1'sb0;
			b_stride_product_q <= 1'sb0;
			c_stride_product_q <= 1'sb0;
			a_row_bytes_q <= 1'sb0;
			b_row_bytes_q <= 1'sb0;
			c_row_bytes_q <= 1'sb0;
			a_last_q <= 1'sb0;
			b_last_q <= 1'sb0;
			c_last_q <= 1'sb0;
			descriptor_known_q <= 1'b0;
			mn_q <= 1'sb0;
			macs_q <= 1'sb0;
			m_prev_q <= 1'sb0;
			k_prev_q <= 1'sb0;
			a_lo_q <= 1'sb0;
			a_hi_q <= 1'sb0;
			b_lo_q <= 1'sb0;
			b_hi_q <= 1'sb0;
			c_lo_q <= 1'sb0;
			c_hi_q <= 1'sb0;
			mac_lo_q <= 1'sb0;
			mac_hi_q <= 1'sb0;
			store_c_lo_q <= 1'sb0;
			store_c_hi_q <= 1'sb0;
			store_c_offset_q <= 1'sb0;
			store_c_col_q <= 1'sb0;
			tile_cell_count_q <= 1'sb0;
			tile_cell_last_q <= 32'hffffffff;
			tile_m_len_preq <= 1'sb0;
			tile_n_len_preq <= 1'sb0;
			tile_cell_count_preq <= 1'sb0;
			pending_error <= 8'd0;
			pending_partial_output <= 1'b0;
			m0 <= 1'sb0;
			n0 <= 1'sb0;
			k0 <= 1'sb0;
			compute_bank <= 1'b0;
			exec_k_len_q <= 1'sb0;
			exec_row_mask_q <= 1'sb0;
			exec_col_mask_q <= 1'sb0;
			exec_continue_q <= 1'b0;
			exec_int16_q <= 1'b0;
			exec_has_next_k_q <= 1'b0;
			read_issue_count <= 1'sb0;
			array_feed_accept_count <= 1'sb0;
			feed_q0_valid <= 1'b0;
			feed_q1_valid <= 1'b0;
			array_done_seen <= 1'b0;
			runtime_error <= 1'b0;
			after_release_next_k <= 1'b0;
			error_after_release <= 1'b0;
			drain_issue_row <= 1'sb0;
			drain_issue_col <= 1'sb0;
			store_out_row_q <= 1'sb0;
			store_out_col_q <= 1'sb0;
			wb_q0_valid <= 1'b0;
			wb_q1_valid <= 1'b0;
			post_in_count <= 1'sb0;
			post_out_count <= 1'sb0;
			acc_pending_valid <= 1'b0;
			discard_remaining <= 1'sb0;
			page_mode_q <= 0;
			page_slot_q <= 0;
			page_identity_q <= 0;
			resident_full_k_q <= 0;
			page_chunked_q <= 0;
			page_warm_q <= 0;
			page_columns_q <= 0;
			page_end_q <= 0;
			page_group_origin_q <= 0;
			page_c_base_q <= 0;
			page_failure_q <= 8'd0;
		end
		else begin
			if ((state != 5'd0) && (state != 5'd18))
				cycle_count <= increment_saturating(cycle_count);
			if ((state != 5'd0) && spad_protocol_error)
				runtime_error <= 1'b1;
			if (page_store_done) begin
				pending_partial_output <= pending_partial_output | dma_partial_output;
				if (page_return_error) begin
					runtime_error <= 1'b1;
					if (page_failure_q == 8'd0)
						page_failure_q <= (page_store_error == 8'd0 ? 8'd11 : page_store_error);
				end
			end
			case (state)
				5'd0:
					if (cmd_valid && cmd_ready) begin
						cmd_q <= cmd_data;
						resident_full_k_q <= resident_candidate;
						page_chunked_q <= chunk_candidate;
						page_warm_q <= 0;
						page_columns_q <= initial_page_columns;
						page_end_q <= sv2v_cast_16(initial_page_columns);
						page_group_origin_q <= 0;
						page_c_base_q <= cmd_data[283-:32];
						page_failure_q <= 8'd0;
						page_mode_q <= (((((((((((RESULT_PAGE_STORE && result_page_enable) && !cmd_data[203]) && (cmd_data[251-:16] > 0)) && (cmd_data[251-:16] <= 16)) && (cmd_data[235-:16] > 0)) && (cmd_data[235-:16] <= 256)) && (cmd_data[106-:2] == 2)) && (cmd_data[104-:2] == 0)) && !cmd_data[102]) && (cmd_data[101-:6] == 0)) && ($signed(cmd_data[95-:32]) == 32'sh80000000)) && ($signed(cmd_data[63-:32]) == 32'sh7fffffff);
						page_slot_q <= !page_slot_q;
						page_identity_q <= {result_context, cmd_data[31-:32], cmd_data[283-:32], cmd_data[251-:16], sv2v_cast_16(initial_page_columns), 16'd0, cmd_data[219-:16]};
						m_prev_q <= cmd_data[251-:16] - 16'd1;
						k_prev_q <= cmd_data[219-:16] - 16'd1;
						cycle_count <= 1'sb0;
						pending_error <= 8'd0;
						pending_partial_output <= 1'b0;
						m0 <= 1'sb0;
						n0 <= 1'sb0;
						k0 <= 1'sb0;
						compute_bank <= 1'b0;
						feed_q0_valid <= 1'b0;
						feed_q1_valid <= 1'b0;
						array_feed_accept_count <= 1'sb0;
						runtime_error <= 1'b0;
						discard_remaining <= 1'sb0;
						state <= 5'd1;
					end
				5'd1: begin
					a_lo_q <= product16(m_prev_q, cmd_q[186:171]);
					a_hi_q <= product16(m_prev_q, cmd_q[202:187]);
					b_lo_q <= product16(k_prev_q, cmd_q[154:139]);
					b_hi_q <= product16(k_prev_q, cmd_q[170:155]);
					c_lo_q <= product16(m_prev_q, cmd_q[122:107]);
					c_hi_q <= product16(m_prev_q, cmd_q[138:123]);
					a_row_bytes_q <= {47'd0, element_bytes(cmd_q[219-:16], input_bytes)};
					b_row_bytes_q <= {47'd0, element_bytes(cmd_q[235-:16], input_bytes)};
					c_row_bytes_q <= {47'd0, element_bytes(cmd_q[235-:16], output_bytes)};
					descriptor_known_q <= ((((known_word32(cmd_q[347-:32]) && known_word32(cmd_q[315-:32])) && known_word32(cmd_q[283-:32])) && known_word32(cmd_q[202-:32])) && known_word32(cmd_q[170-:32])) && known_word32(cmd_q[138-:32]);
					mn_q <= {32'd0, product16(cmd_q[251-:16], cmd_q[235-:16])};
					state <= 5'd2;
				end
				5'd2: begin
					a_stride_product_q <= {17'd0, join_product(a_lo_q, a_hi_q)};
					b_stride_product_q <= {17'd0, join_product(b_lo_q, b_hi_q)};
					c_stride_product_q <= {17'd0, join_product(c_lo_q, c_hi_q)};
					mac_lo_q <= product16(mn_q[15:0], cmd_q[219-:16]);
					mac_hi_q <= product16(mn_q[31:16], cmd_q[219-:16]);
					state <= 5'd3;
				end
				5'd3: begin
					a_last_q <= (({33'd0, cmd_q[347-:32]} + a_stride_product_q) + a_row_bytes_q) - 65'd1;
					b_last_q <= (({33'd0, cmd_q[315-:32]} + b_stride_product_q) + b_row_bytes_q) - 65'd1;
					c_last_q <= (({33'd0, cmd_q[283-:32]} + c_stride_product_q) + c_row_bytes_q) - 65'd1;
					macs_q <= {16'd0, join_product(mac_lo_q, mac_hi_q)};
					state <= 5'd4;
				end
				5'd4: begin
					completion_q[136-:32] <= cmd_q[31-:32];
					completion_q[96] <= 1'b0;
					pending_error <= (runtime_error || spad_protocol_error ? 8'd11 : 8'd0);
					if (validation_error != 8'd0) begin
						completion_q[104-:8] <= validation_error;
						completion_q[95-:32] <= increment_saturating(cycle_count);
						completion_q[63-:64] <= 1'sb0;
						state <= 5'd18;
					end
					else begin
						completion_q[104-:8] <= 8'd0;
						completion_q[63-:64] <= macs_q;
						if (runtime_error || spad_protocol_error)
							state <= 5'd17;
						else
							state <= (page_mode_q ? 5'd19 : 5'd5);
					end
				end
				5'd5:
					if (runtime_error || spad_protocol_error) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else if (load_launch && load_launch_ready)
						state <= 5'd6;
				5'd6:
					if ((runtime_error || spad_protocol_error) && ((load_state == 4'd8) || (load_state == 4'd7))) begin
						pending_error <= 8'd11;
						pending_partial_output <= pending_partial_output | dma_partial_output;
						state <= 5'd17;
					end
					else if (load_state == 4'd8) begin
						pending_error <= load_error_q;
						pending_partial_output <= pending_partial_output | dma_partial_output;
						state <= 5'd17;
					end
					else if (load_state == 4'd7) begin
						if (runtime_error) begin
							pending_error <= 8'd11;
							state <= 5'd17;
						end
						else begin
							tile_m_len_preq <= sv2v_cast_AEB46(tile_m_len);
							tile_n_len_preq <= sv2v_cast_AB00C(tile_n_len);
							state <= 5'd7;
						end
					end
				5'd7: begin
					tile_cell_count_preq <= tile_cell_count_calc;
					if (runtime_error || spad_protocol_error) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else
						state <= 5'd8;
				end
				5'd8: begin
					tile_cell_last_q <= sv2v_cast_32(tile_cell_count_preq - sv2v_cast_CB91D_signed(1));
					exec_k_len_q <= sv2v_cast_86116(tile_k_len);
					exec_row_mask_q <= make_row_mask(sv2v_cast_16(tile_m_len_preq));
					exec_col_mask_q <= make_col_mask(sv2v_cast_16(tile_n_len_preq));
					exec_continue_q <= k0 != 0;
					exec_int16_q <= cmd_q[203];
					exec_has_next_k_q <= has_next_k;
					if (runtime_error || spad_protocol_error) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else
						state <= 5'd9;
				end
				5'd9:
					if (runtime_error || spad_protocol_error) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else if (array_start_valid && array_start_ready) begin
						tile_cell_count_q <= sv2v_cast_32(tile_cell_count_preq);
						read_issue_count <= 1'sb0;
						array_feed_accept_count <= 1'sb0;
						feed_q0_valid <= 1'b0;
						feed_q1_valid <= 1'b0;
						array_done_seen <= 1'b0;
						state <= 5'd10;
					end
				5'd10: begin
					if (spad_compute_read_valid)
						read_issue_count <= read_issue_count + 1'b1;
					if (array_feed_valid && array_feed_ready)
						array_feed_accept_count <= array_feed_accept_count + 1'b1;
					case ({feed_push, feed_pop})
						2'b01:
							if (feed_q1_valid) begin
								feed_q0_valid <= 1'b1;
								feed_q1_valid <= 1'b0;
							end
							else
								feed_q0_valid <= 1'b0;
						2'b10:
							if (!feed_q0_valid)
								feed_q0_valid <= 1'b1;
							else if (!feed_q1_valid)
								feed_q1_valid <= 1'b1;
							else
								runtime_error <= 1'b1;
						2'b11:
							if (feed_q1_valid) begin
								feed_q0_valid <= 1'b1;
								feed_q1_valid <= 1'b1;
							end
							else begin
								feed_q0_valid <= 1'b1;
								feed_q1_valid <= 1'b0;
							end
						default:
							;
					endcase
					if (spad_protocol_error || runtime_error) begin
						pending_error <= 8'd11;
						pending_partial_output <= pending_partial_output | dma_partial_output;
						after_release_next_k <= 1'b0;
						error_after_release <= 1'b1;
						if (array_done_seen || array_done) begin
							feed_q0_valid <= 1'b0;
							feed_q1_valid <= 1'b0;
							state <= 5'd11;
						end
						else
							state <= 5'd16;
					end
					else begin
						if (array_done)
							array_done_seen <= 1'b1;
						if (array_done_seen || array_done) begin
							if (has_next_k) begin
								if (load_state == 4'd8) begin
									pending_error <= load_error_q;
									pending_partial_output <= pending_partial_output | dma_partial_output;
									after_release_next_k <= 1'b0;
									error_after_release <= 1'b1;
									state <= 5'd11;
								end
								else if (load_state == 4'd7) begin
									if ((runtime_error || spad_protocol_error) || (feed_push && (feed_slots_after_edge > 2))) begin
										pending_error <= 8'd11;
										after_release_next_k <= 1'b0;
										error_after_release <= 1'b1;
									end
									else begin
										after_release_next_k <= 1'b1;
										error_after_release <= 1'b0;
									end
									state <= 5'd11;
								end
							end
							else begin
								after_release_next_k <= 1'b0;
								if ((runtime_error || spad_protocol_error) || (feed_push && (feed_slots_after_edge > 2))) begin
									pending_error <= 8'd11;
									error_after_release <= 1'b1;
								end
								else
									error_after_release <= 1'b0;
								state <= 5'd11;
							end
						end
					end
				end
				5'd16: begin
					if (feed_pop) begin
						if (feed_q1_valid) begin
							feed_q0_valid <= 1'b1;
							feed_q1_valid <= 1'b0;
						end
						else
							feed_q0_valid <= 1'b0;
					end
					if (array_feed_valid && array_feed_ready)
						array_feed_accept_count <= array_feed_accept_count + 1'b1;
					if (array_done) begin
						feed_q0_valid <= 1'b0;
						feed_q1_valid <= 1'b0;
						state <= 5'd11;
					end
				end
				5'd11: begin
					store_c_lo_q <= product16(m0, cmd_q[122:107]);
					store_c_hi_q <= product16(m0, cmd_q[138:123]);
					store_c_col_q <= {14'd0, element_bytes(n0, output_bytes)};
					if (runtime_error || spad_protocol_error) begin
						pending_error <= 8'd11;
						error_after_release <= 1'b1;
						after_release_next_k <= 1'b0;
						state <= 5'd17;
					end
					else
						state <= 5'd12;
				end
				5'd12: begin
					store_c_offset_q <= store_c_lo_q + {store_c_hi_q[15:0], 16'd0};
					if (runtime_error || spad_protocol_error) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else if (error_after_release)
						state <= 5'd17;
					else if (after_release_next_k) begin
						compute_bank <= ~compute_bank;
						k0 <= k_after_tile[15:0];
						tile_m_len_preq <= sv2v_cast_AEB46(tile_m_len);
						tile_n_len_preq <= sv2v_cast_AB00C(tile_n_len);
						state <= 5'd7;
					end
					else
						state <= (page_mode_q ? 5'd20 : 5'd13);
				end
				5'd13:
					if (runtime_error || spad_protocol_error) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else begin
						store_job_q[100-:2] <= 2'd2;
						store_job_q[98-:32] <= (cmd_q[283-:32] + store_c_offset_q) + store_c_col_q;
						store_job_q[66-:32] <= cmd_q[138-:32];
						store_job_q[34-:16] <= tile_m_len;
						store_job_q[18-:16] <= tile_n_len;
						store_job_q[2-:2] <= output_bytes[1:0];
						store_job_q[0] <= 1'b0;
						state <= 5'd14;
					end
				5'd14:
					if (runtime_error || spad_protocol_error) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else if (dma_job_valid && dma_job_ready) begin
						drain_issue_row <= 1'sb0;
						drain_issue_col <= 1'sb0;
						store_out_row_q <= 1'sb0;
						store_out_col_q <= 1'sb0;
						wb_q0_valid <= 1'b0;
						wb_q1_valid <= 1'b0;
						post_in_count <= 1'sb0;
						post_out_count <= 1'sb0;
						acc_pending_valid <= 1'b0;
						discard_remaining <= 1'sb0;
						state <= 5'd15;
					end
				5'd15: begin
					case ({post_out_fire, store_elem_fire})
						2'b01:
							if (wb_q1_valid) begin
								wb_q0_valid <= 1'b1;
								wb_q1_valid <= 1'b0;
							end
							else
								wb_q0_valid <= 1'b0;
						2'b10:
							if (!wb_q0_valid)
								wb_q0_valid <= 1'b1;
							else
								wb_q1_valid <= 1'b1;
						2'b11:
							if (wb_q1_valid) begin
								wb_q0_valid <= 1'b1;
								wb_q1_valid <= 1'b1;
							end
							else begin
								wb_q0_valid <= 1'b1;
								wb_q1_valid <= 1'b0;
							end
						default:
							;
					endcase
					if (!acc_pending_valid && (post_in_count < tile_cell_count_q))
						acc_pending_valid <= 1'b1;
					if (post_in_fire) begin
						acc_pending_valid <= 1'b0;
						post_in_count <= post_in_count + 1'b1;
						if ((drain_issue_col + 1'b1) >= tile_n_len) begin
							drain_issue_col <= 1'sb0;
							drain_issue_row <= drain_issue_row + 1'b1;
						end
						else
							drain_issue_col <= drain_issue_col + 1'b1;
					end
					if (post_out_fire) begin
						post_out_count <= post_out_count + 1'b1;
						if ((store_out_col_q + 1'b1) >= tile_n_len) begin
							store_out_col_q <= 1'sb0;
							store_out_row_q <= store_out_row_q + 1'b1;
						end
						else
							store_out_col_q <= store_out_col_q + 1'b1;
					end
					if (dma_job_error) begin
						pending_error <= (runtime_error || spad_protocol_error ? 8'd11 : (dma_error_code == 8'd0 ? 8'd11 : dma_error_code));
						pending_partial_output <= pending_partial_output | dma_partial_output;
						discard_remaining <= post_pending_after_fire;
						acc_pending_valid <= 1'b0;
						wb_q0_valid <= 1'b0;
						wb_q1_valid <= 1'b0;
						state <= 5'd17;
					end
					else if (dma_job_done) begin
						if (runtime_error || spad_protocol_error) begin
							pending_error <= 8'd11;
							pending_partial_output <= pending_partial_output | dma_partial_output;
							discard_remaining <= post_pending_after_fire;
							acc_pending_valid <= 1'b0;
							wb_q0_valid <= 1'b0;
							wb_q1_valid <= 1'b0;
							state <= 5'd17;
						end
						else if ((!post_count_complete || wb_q0_valid) || wb_q1_valid) begin
							pending_error <= 8'd11;
							pending_partial_output <= pending_partial_output | dma_partial_output;
							discard_remaining <= post_pending_after_fire;
							acc_pending_valid <= 1'b0;
							wb_q0_valid <= 1'b0;
							wb_q1_valid <= 1'b0;
							state <= 5'd17;
						end
						else if (has_next_output) begin
							pending_partial_output <= pending_partial_output | dma_partial_output;
							if (has_next_n)
								n0 <= n_after_tile[15:0];
							else begin
								n0 <= 1'sb0;
								m0 <= m_after_tile[15:0];
							end
							k0 <= 1'sb0;
							compute_bank <= 1'b0;
							runtime_error <= 1'b0;
							state <= 5'd5;
						end
						else begin
							pending_partial_output <= pending_partial_output | dma_partial_output;
							completion_q[104-:8] <= 8'd0;
							completion_q[96] <= 1'b0;
							completion_q[95-:32] <= increment_saturating(cycle_count);
							state <= 5'd18;
						end
					end
				end
				5'd19:
					if (page_capture_cancel) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else if (page_bank_ready) begin
						if (!page_warm_q)
							state <= 5'd5;
						else if (resident_operands_ready)
							state <= 5'd25;
					end
				5'd20:
					if (runtime_error || spad_protocol_error) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else if (page_capture_ready)
						state <= 5'd21;
				5'd21:
					if (page_capture_done) begin
						if (page_capture_cancelled || page_capture_cancel) begin
							pending_error <= 8'd11;
							state <= 5'd17;
						end
						else if (has_next_n && (!page_chunked_q || (n_after_tile < {1'b0, page_end_q}))) begin
							n0 <= n_after_tile[15:0];
							k0 <= 0;
							compute_bank <= 0;
							state <= (((RESIDENT_GROUP_REUSE_ENABLE && resident_full_k_q) && resident_operands_ready) && (load_state == 4'd0) ? 5'd25 : 5'd5);
						end
						else
							state <= 5'd22;
					end
				5'd25, 5'd26, 5'd27, 5'd28:
					if (((runtime_error || spad_protocol_error) || !resident_operands_ready) || (load_state != 4'd0)) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else
						case (state)
							5'd25: state <= 5'd26;
							5'd26: state <= 5'd27;
							5'd27: state <= 5'd28;
							default: begin
								tile_m_len_preq <= sv2v_cast_AEB46(tile_m_len);
								tile_n_len_preq <= sv2v_cast_AB00C(tile_n_len);
								state <= 5'd7;
							end
						endcase
				5'd22:
					if (page_capture_cancel) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else
						state <= 5'd23;
				5'd23:
					if (page_capture_cancel) begin
						pending_error <= 8'd11;
						state <= 5'd17;
					end
					else if (page_store_ready) begin
						if (page_more) begin
							page_slot_q <= !page_slot_q;
							page_warm_q <= 1;
							n0 <= page_end_q;
							k0 <= 0;
							compute_bank <= 0;
							page_group_origin_q <= page_end_q[7:3];
							page_columns_q <= next_page_columns;
							page_end_q <= page_end_q + sv2v_cast_16(next_page_columns);
							page_c_base_q <= page_c_base_q + (sv2v_cast_32(page_columns_q) << 2);
							page_identity_q[95:64] <= page_c_base_q + (sv2v_cast_32(page_columns_q) << 2);
							page_identity_q[47:32] <= sv2v_cast_16(next_page_columns);
							state <= 5'd19;
						end
						else
							state <= 5'd24;
					end
				5'd24:
					if (page_store_done) begin
						pending_partial_output <= pending_partial_output | dma_partial_output;
						if ((((page_store_error != 8'd0) || page_store_cancelled) || runtime_error) || spad_protocol_error) begin
							pending_error <= ((runtime_error || spad_protocol_error) || page_store_cancelled ? 8'd11 : page_store_error);
							state <= 5'd17;
						end
						else begin
							completion_q[104-:8] <= 8'd0;
							completion_q[96] <= 0;
							completion_q[95-:32] <= increment_saturating(cycle_count);
							state <= 5'd18;
						end
					end
				5'd17: begin
					if ((discard_remaining != 0) && post_out_fire)
						discard_remaining <= discard_remaining - 1'b1;
					if (((cleanup_all_empty && page_cleanup_idle) && (discard_remaining == 0)) && (load_state == 4'd0)) begin
						completion_q[104-:8] <= (page_failure_q != 8'd0 ? page_failure_q : (pending_error == 8'd0 ? 8'd11 : pending_error));
						completion_q[96] <= pending_partial_output;
						completion_q[95-:32] <= increment_saturating(cycle_count);
						state <= 5'd18;
					end
				end
				5'd18:
					if (completion_valid && completion_ready)
						state <= 5'd0;
				default: state <= 5'd0;
			endcase
		end
	always @(posedge clk) begin
		if (state == 5'd10)
			case ({feed_push, feed_pop})
				2'b01:
					if (feed_q1_valid) begin
						feed_a_q0 <= feed_a_q1;
						feed_b_q0 <= feed_b_q1;
					end
				2'b10:
					if (!feed_q0_valid) begin
						feed_a_q0 <= spad_a_vector;
						feed_b_q0 <= spad_b_vector;
					end
					else if (!feed_q1_valid) begin
						feed_a_q1 <= spad_a_vector;
						feed_b_q1 <= spad_b_vector;
					end
				2'b11:
					if (feed_q1_valid) begin
						feed_a_q0 <= feed_a_q1;
						feed_b_q0 <= feed_b_q1;
						feed_a_q1 <= spad_a_vector;
						feed_b_q1 <= spad_b_vector;
					end
					else begin
						feed_a_q0 <= spad_a_vector;
						feed_b_q0 <= spad_b_vector;
					end
				default:
					;
			endcase
		else if (((state == 5'd16) && feed_pop) && feed_q1_valid) begin
			feed_a_q0 <= feed_a_q1;
			feed_b_q0 <= feed_b_q1;
		end
		if (state == 5'd15)
			case ({post_out_fire, store_elem_fire})
				2'b01:
					if (wb_q1_valid) begin
						wb_data_q0 <= wb_data_q1;
						wb_bytes_q0 <= wb_bytes_q1;
						wb_row_q0 <= wb_row_q1;
						wb_col_q0 <= wb_col_q1;
					end
				2'b10:
					if (!wb_q0_valid) begin
						wb_data_q0 <= post_out_value;
						wb_bytes_q0 <= post_out_bytes;
						wb_row_q0 <= store_out_row_q;
						wb_col_q0 <= store_out_col_q;
					end
					else begin
						wb_data_q1 <= post_out_value;
						wb_bytes_q1 <= post_out_bytes;
						wb_row_q1 <= store_out_row_q;
						wb_col_q1 <= store_out_col_q;
					end
				2'b11:
					if (wb_q1_valid) begin
						wb_data_q0 <= wb_data_q1;
						wb_bytes_q0 <= wb_bytes_q1;
						wb_row_q0 <= wb_row_q1;
						wb_col_q0 <= wb_col_q1;
						wb_data_q1 <= post_out_value;
						wb_bytes_q1 <= post_out_bytes;
						wb_row_q1 <= store_out_row_q;
						wb_col_q1 <= store_out_col_q;
					end
					else begin
						wb_data_q0 <= post_out_value;
						wb_bytes_q0 <= post_out_bytes;
						wb_row_q0 <= store_out_row_q;
						wb_col_q0 <= store_out_col_q;
					end
				default:
					;
			endcase
	end
	initial _sv2v_0 = 0;
endmodule
module cp13_k_lengths (
	k,
	k0,
	current_len,
	next_len
);
	parameter signed [31:0] K_TILE = 32;
	input wire [15:0] k;
	input wire [15:0] k0;
	output wire [15:0] current_len;
	output wire [15:0] next_len;
	localparam signed [31:0] KW = $clog2(K_TILE);
	wire [15:0] delta = k - k0;
	wire [15 - KW:0] whole = delta[15:KW];
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	wire [15:0] tail = sv2v_cast_16(delta[KW - 1:0]);
	initial if (((K_TILE < 8) || (K_TILE > 256)) || ((K_TILE & (K_TILE - 1)) != 0)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_scheduler.sv:1573:3 - cp13_k_lengths.<unnamed_block>\n msg: ", $time, "CP13_K_TILE_CONTRACT_RED");
		$finish(1);
	end
	function automatic signed [15:0] sv2v_cast_16_signed;
		input reg signed [15:0] inp;
		sv2v_cast_16_signed = inp;
	endfunction
	assign current_len = (whole == 0 ? tail : sv2v_cast_16_signed(K_TILE));
	assign next_len = (whole == 0 ? 16'd0 : (whole == 1 ? tail : sv2v_cast_16_signed(K_TILE)));
endmodule
module npu_scratchpad (
	clk,
	rst,
	owner_req_valid,
	owner_req_is_b,
	owner_req_bank,
	owner_req_state,
	dma_write_valid,
	dma_is_b,
	dma_bank,
	dma_lane,
	dma_k,
	dma_input_int16,
	dma_data,
	dma_count,
	compute_read_valid,
	compute_bank,
	compute_k,
	a_vector,
	b_vector,
	compute_read_data_valid,
	a_owner,
	b_owner,
	protocol_error
);
	parameter signed [31:0] ARRAY_ROWS = 4;
	parameter signed [31:0] ARRAY_COLS = 4;
	parameter signed [31:0] K_TILE = 32;
	parameter signed [31:0] MAX_ELEM_W = 16;
	parameter signed [31:0] DMA_VECTOR_ELEMS = 1;
	parameter [0:0] A_PACKED_INT8_16 = 1'b0;
	input wire clk;
	input wire rst;
	input wire owner_req_valid;
	input wire owner_req_is_b;
	input wire owner_req_bank;
	input wire [1:0] owner_req_state;
	input wire dma_write_valid;
	input wire dma_is_b;
	input wire dma_bank;
	input wire [(ARRAY_ROWS > ARRAY_COLS ? (ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1) : (ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1)) - 1:0] dma_lane;
	input wire [(K_TILE > 1 ? $clog2(K_TILE) : 1) - 1:0] dma_k;
	input wire dma_input_int16;
	input wire signed [(DMA_VECTOR_ELEMS * 16) - 1:0] dma_data;
	input wire [(DMA_VECTOR_ELEMS > 1 ? $clog2(DMA_VECTOR_ELEMS + 1) : 1) - 1:0] dma_count;
	input wire compute_read_valid;
	input wire compute_bank;
	input wire [(K_TILE > 1 ? $clog2(K_TILE) : 1) - 1:0] compute_k;
	output wire [(ARRAY_ROWS * MAX_ELEM_W) - 1:0] a_vector;
	output wire [(ARRAY_COLS * MAX_ELEM_W) - 1:0] b_vector;
	output wire compute_read_data_valid;
	output wire [3:0] a_owner;
	output wire [3:0] b_owner;
	output wire protocol_error;
	generate
		if (A_PACKED_INT8_16) begin : g_int8packed16
			npu_scratchpad_int8packed16 #(
				.ARRAY_ROWS(ARRAY_ROWS),
				.ARRAY_COLS(ARRAY_COLS),
				.K_TILE(K_TILE),
				.MAX_ELEM_W(MAX_ELEM_W),
				.DMA_VECTOR_ELEMS(DMA_VECTOR_ELEMS)
			) impl(
				.clk(clk),
				.rst(rst),
				.owner_req_valid(owner_req_valid),
				.owner_req_is_b(owner_req_is_b),
				.owner_req_bank(owner_req_bank),
				.owner_req_state(owner_req_state),
				.dma_write_valid(dma_write_valid),
				.dma_is_b(dma_is_b),
				.dma_bank(dma_bank),
				.dma_lane(dma_lane),
				.dma_k(dma_k),
				.dma_input_int16(dma_input_int16),
				.dma_data(dma_data),
				.dma_count(dma_count),
				.compute_read_valid(compute_read_valid),
				.compute_bank(compute_bank),
				.compute_k(compute_k),
				.a_vector(a_vector),
				.b_vector(b_vector),
				.compute_read_data_valid(compute_read_data_valid),
				.a_owner(a_owner),
				.b_owner(b_owner),
				.protocol_error(protocol_error)
			);
		end
		else begin : g_legacy
			npu_scratchpad_legacy #(
				.ARRAY_ROWS(ARRAY_ROWS),
				.ARRAY_COLS(ARRAY_COLS),
				.K_TILE(K_TILE),
				.MAX_ELEM_W(MAX_ELEM_W),
				.DMA_VECTOR_ELEMS(DMA_VECTOR_ELEMS)
			) impl(
				.clk(clk),
				.rst(rst),
				.owner_req_valid(owner_req_valid),
				.owner_req_is_b(owner_req_is_b),
				.owner_req_bank(owner_req_bank),
				.owner_req_state(owner_req_state),
				.dma_write_valid(dma_write_valid),
				.dma_is_b(dma_is_b),
				.dma_bank(dma_bank),
				.dma_lane(dma_lane),
				.dma_k(dma_k),
				.dma_input_int16(dma_input_int16),
				.dma_data(dma_data),
				.dma_count(dma_count),
				.compute_read_valid(compute_read_valid),
				.compute_bank(compute_bank),
				.compute_k(compute_k),
				.a_vector(a_vector),
				.b_vector(b_vector),
				.compute_read_data_valid(compute_read_data_valid),
				.a_owner(a_owner),
				.b_owner(b_owner),
				.protocol_error(protocol_error)
			);
		end
	endgenerate
endmodule
module npu_scratchpad_legacy (
	clk,
	rst,
	owner_req_valid,
	owner_req_is_b,
	owner_req_bank,
	owner_req_state,
	dma_write_valid,
	dma_is_b,
	dma_bank,
	dma_lane,
	dma_k,
	dma_input_int16,
	dma_data,
	dma_count,
	compute_read_valid,
	compute_bank,
	compute_k,
	a_vector,
	b_vector,
	compute_read_data_valid,
	a_owner,
	b_owner,
	protocol_error
);
	reg _sv2v_0;
	parameter signed [31:0] ARRAY_ROWS = 4;
	parameter signed [31:0] ARRAY_COLS = 4;
	parameter signed [31:0] K_TILE = 32;
	parameter signed [31:0] MAX_ELEM_W = 16;
	parameter signed [31:0] DMA_VECTOR_ELEMS = 1;
	input wire clk;
	input wire rst;
	input wire owner_req_valid;
	input wire owner_req_is_b;
	input wire owner_req_bank;
	input wire [1:0] owner_req_state;
	input wire dma_write_valid;
	input wire dma_is_b;
	input wire dma_bank;
	input wire [(ARRAY_ROWS > ARRAY_COLS ? (ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1) : (ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1)) - 1:0] dma_lane;
	input wire [(K_TILE > 1 ? $clog2(K_TILE) : 1) - 1:0] dma_k;
	input wire dma_input_int16;
	input wire signed [(DMA_VECTOR_ELEMS * 16) - 1:0] dma_data;
	input wire [(DMA_VECTOR_ELEMS > 1 ? $clog2(DMA_VECTOR_ELEMS + 1) : 1) - 1:0] dma_count;
	input wire compute_read_valid;
	input wire compute_bank;
	input wire [(K_TILE > 1 ? $clog2(K_TILE) : 1) - 1:0] compute_k;
	output wire [(ARRAY_ROWS * MAX_ELEM_W) - 1:0] a_vector;
	output wire [(ARRAY_COLS * MAX_ELEM_W) - 1:0] b_vector;
	output reg compute_read_data_valid;
	output reg [3:0] a_owner;
	output reg [3:0] b_owner;
	output reg protocol_error;
	localparam [1:0] OWNER_EMPTY = 2'd0;
	localparam [1:0] OWNER_FILLING = 2'd1;
	localparam [1:0] OWNER_READY = 2'd2;
	localparam [1:0] OWNER_COMPUTE = 2'd3;
	localparam signed [31:0] LANE_W = (ARRAY_ROWS > ARRAY_COLS ? (ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1) : (ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1));
	localparam signed [31:0] K_W = (K_TILE > 1 ? $clog2(K_TILE) : 1);
	localparam signed [31:0] B_DATA_W = ARRAY_COLS * 16;
	function automatic signed [((LANE_W + 0) >= 0 ? LANE_W + 1 : 1 - (LANE_W + 0)) - 1:0] sv2v_cast_2C889_signed;
		input reg signed [((LANE_W + 0) >= 0 ? LANE_W + 1 : 1 - (LANE_W + 0)) - 1:0] inp;
		sv2v_cast_2C889_signed = inp;
	endfunction
	localparam [LANE_W:0] ARRAY_ROWS_COUNT = sv2v_cast_2C889_signed(ARRAY_ROWS);
	localparam [LANE_W:0] ARRAY_COLS_COUNT = sv2v_cast_2C889_signed(ARRAY_COLS);
	function automatic signed [((K_W + 0) >= 0 ? K_W + 1 : 1 - (K_W + 0)) - 1:0] sv2v_cast_4161D_signed;
		input reg signed [((K_W + 0) >= 0 ? K_W + 1 : 1 - (K_W + 0)) - 1:0] inp;
		sv2v_cast_4161D_signed = inp;
	endfunction
	localparam [K_W:0] K_TILE_COUNT = sv2v_cast_4161D_signed(K_TILE);
	reg dma_legal;
	reg compute_legal;
	wire dma_fire;
	wire compute_fire;
	reg vector_zero_q;
	localparam signed [31:0] VLOG = (DMA_VECTOR_ELEMS > 1 ? $clog2(DMA_VECTOR_ELEMS) : 0);
	localparam signed [31:0] SUB_W = (VLOG > 0 ? VLOG : 1);
	localparam signed [31:0] PACK_ADDR_W = (K_W + 1) - VLOG;
	wire [(DMA_VECTOR_ELEMS * 16) - 1:0] normalized_dma_vector;
	wire [(DMA_VECTOR_ELEMS * 16) - 1:0] a_write_data;
	wire [DMA_VECTOR_ELEMS - 1:0] a_write_mask;
	wire [DMA_VECTOR_ELEMS - 1:0] count_mask;
	wire [ARRAY_COLS - 1:0] b_write_mask;
	wire [(ARRAY_COLS * 16) - 1:0] b_write_data;
	wire [SUB_W - 1:0] write_sub;
	reg [SUB_W - 1:0] read_sub_q;
	wire [PACK_ADDR_W - 1:0] packed_write_address;
	wire [PACK_ADDR_W - 1:0] packed_read_address;
	wire [K_W:0] write_address;
	wire [K_W:0] read_address;
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		dma_legal = !((((((((((((((((dma_is_b !== 1'b0) && (dma_is_b !== 1'b1)) || ((dma_bank !== 1'b0) && (dma_bank !== 1'b1))) || ((dma_input_int16 !== 1'b0) && (dma_input_int16 !== 1'b1))) || (^dma_lane === 1'bx)) || (^dma_k === 1'bx)) || (^dma_count === 1'bx)) || (dma_count == {(DMA_VECTOR_ELEMS > 1 ? $clog2(DMA_VECTOR_ELEMS + 1) : 1) {1'sb0}})) || (sv2v_cast_32_signed(dma_count) > DMA_VECTOR_ELEMS)) || (!dma_is_b && (((sv2v_cast_32_signed(dma_k) + sv2v_cast_32_signed(dma_count)) > K_TILE) || ((sv2v_cast_32_signed(write_sub) + sv2v_cast_32_signed(dma_count)) > DMA_VECTOR_ELEMS)))) || (dma_is_b && ((sv2v_cast_32_signed(dma_lane) + sv2v_cast_32_signed(dma_count)) > ARRAY_COLS))) || ({1'b0, dma_k} >= K_TILE_COUNT)) || ((dma_is_b === 1'b1) && ({1'b0, dma_lane} >= ARRAY_COLS_COUNT))) || ((dma_is_b === 1'b0) && ({1'b0, dma_lane} >= ARRAY_ROWS_COUNT))) || ((dma_is_b === 1'b1) && (b_owner[dma_bank * 2+:2] !== OWNER_FILLING))) || ((dma_is_b === 1'b0) && (a_owner[dma_bank * 2+:2] !== OWNER_FILLING)));
		compute_legal = !((((((compute_bank !== 1'b0) && (compute_bank !== 1'b1)) || (^compute_k === 1'bx)) || ({1'b0, compute_k} >= K_TILE_COUNT)) || (a_owner[compute_bank * 2+:2] !== OWNER_COMPUTE)) || (b_owner[compute_bank * 2+:2] !== OWNER_COMPUTE));
	end
	assign dma_fire = (!rst && (dma_write_valid === 1'b1)) && dma_legal;
	assign compute_fire = (!rst && (compute_read_valid === 1'b1)) && compute_legal;
	assign write_address = {dma_bank, dma_k};
	assign read_address = {compute_bank, compute_k};
	function automatic [PACK_ADDR_W - 1:0] sv2v_cast_31C23;
		input reg [PACK_ADDR_W - 1:0] inp;
		sv2v_cast_31C23 = inp;
	endfunction
	assign packed_write_address = sv2v_cast_31C23(write_address >> VLOG);
	assign packed_read_address = sv2v_cast_31C23(read_address >> VLOG);
	function automatic signed [SUB_W - 1:0] sv2v_cast_7704C_signed;
		input reg signed [SUB_W - 1:0] inp;
		sv2v_cast_7704C_signed = inp;
	endfunction
	assign write_sub = sv2v_cast_7704C_signed(sv2v_cast_32_signed(dma_k) & (DMA_VECTOR_ELEMS - 1));
	always @(posedge clk)
		if (rst)
			read_sub_q <= 1'sb0;
		else if (compute_fire)
			read_sub_q <= sv2v_cast_7704C_signed(sv2v_cast_32_signed(compute_k) & (DMA_VECTOR_ELEMS - 1));
	genvar _gv_e_2;
	function automatic signed [(DMA_VECTOR_ELEMS > 1 ? $clog2(DMA_VECTOR_ELEMS + 1) : 1) - 1:0] sv2v_cast_5F5CC_signed;
		input reg signed [(DMA_VECTOR_ELEMS > 1 ? $clog2(DMA_VECTOR_ELEMS + 1) : 1) - 1:0] inp;
		sv2v_cast_5F5CC_signed = inp;
	endfunction
	generate
		for (_gv_e_2 = 0; _gv_e_2 < DMA_VECTOR_ELEMS; _gv_e_2 = _gv_e_2 + 1) begin : g_norm
			localparam e = _gv_e_2;
			assign normalized_dma_vector[e * 16+:16] = (dma_input_int16 ? dma_data[e * 16+:16] : {{8 {dma_data[(e * 16) + 7]}}, dma_data[e * 16+:8]});
			assign count_mask[e] = dma_count > sv2v_cast_5F5CC_signed(e);
		end
	endgenerate
	assign a_write_mask = (count_mask << write_sub) & {DMA_VECTOR_ELEMS {dma_fire && !dma_is_b}};
	function automatic [ARRAY_COLS - 1:0] sv2v_cast_B69AA;
		input reg [ARRAY_COLS - 1:0] inp;
		sv2v_cast_B69AA = inp;
	endfunction
	assign b_write_mask = (sv2v_cast_B69AA(count_mask) << dma_lane) & {ARRAY_COLS {dma_fire && dma_is_b}};
	assign a_write_data = normalized_dma_vector << (sv2v_cast_32_signed(write_sub) * 16);
	function automatic [B_DATA_W - 1:0] sv2v_cast_A38B8;
		input reg [B_DATA_W - 1:0] inp;
		sv2v_cast_A38B8 = inp;
	endfunction
	assign b_write_data = sv2v_cast_A38B8(normalized_dma_vector) << {dma_lane, 4'b0000};
	genvar _gv_r_1;
	function automatic signed [LANE_W - 1:0] sv2v_cast_3FA0D_signed;
		input reg signed [LANE_W - 1:0] inp;
		sv2v_cast_3FA0D_signed = inp;
	endfunction
	generate
		for (_gv_r_1 = 0; _gv_r_1 < ARRAY_ROWS; _gv_r_1 = _gv_r_1 + 1) begin : g_a_lane
			localparam r = _gv_r_1;
			wire [(DMA_VECTOR_ELEMS * 16) - 1:0] packed_data;
			wire [DMA_VECTOR_ELEMS - 1:0] lane_mask = a_write_mask & {DMA_VECTOR_ELEMS {dma_lane == sv2v_cast_3FA0D_signed(r)}};
			npu_spad_packed_ram #(
				.ADDR_W(PACK_ADDR_W),
				.PACK_ELEMS(DMA_VECTOR_ELEMS)
			) mem(
				.clk(clk),
				.wr_mask(lane_mask),
				.wr_addr(packed_write_address),
				.wr_data(a_write_data),
				.rd_en(compute_fire),
				.rd_addr(packed_read_address),
				.rd_data(packed_data)
			);
			assign a_vector[r * MAX_ELEM_W+:MAX_ELEM_W] = (vector_zero_q ? {MAX_ELEM_W * 1 {1'sb0}} : packed_data[sv2v_cast_32_signed(read_sub_q) * 16+:16]);
		end
	endgenerate
	genvar _gv_c_1;
	generate
		for (_gv_c_1 = 0; _gv_c_1 < ARRAY_COLS; _gv_c_1 = _gv_c_1 + 1) begin : g_b_lane
			localparam c = _gv_c_1;
			wire [15:0] data;
			npu_spad_lane_ram #(.ADDR_W(K_W + 1)) mem(
				.clk(clk),
				.wr_en(b_write_mask[c]),
				.wr_addr(write_address),
				.wr_data(b_write_data[c * 16+:16]),
				.rd_en(compute_fire),
				.rd_addr(read_address),
				.rd_data(data)
			);
			assign b_vector[c * MAX_ELEM_W+:MAX_ELEM_W] = (vector_zero_q ? {MAX_ELEM_W * 1 {1'sb0}} : data);
		end
		if ((((DMA_VECTOR_ELEMS < 1) || (DMA_VECTOR_ELEMS > 8)) || ((DMA_VECTOR_ELEMS & (DMA_VECTOR_ELEMS - 1)) != 0)) || (DMA_VECTOR_ELEMS > K_TILE)) begin : g_bad_dma_vector
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_scratchpad.sv:171:15 - npu_scratchpad_legacy.g_bad_dma_vector.<unnamed_block>\n msg: ", $time, "CP5_SPAD_VECTOR_PARAM_RED");
				$finish(1);
			end
		end
		if (((ARRAY_ROWS < 2) || (ARRAY_ROWS > 16)) || ((ARRAY_ROWS & (ARRAY_ROWS - 1)) != 0)) begin : g_bad_array_rows
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_scratchpad.sv:175:15 - npu_scratchpad_legacy.g_bad_array_rows.<unnamed_block>\n msg: ", $time, "npu_scratchpad: ARRAY_ROWS must be a power of two from 2 to 16");
				$finish(1);
			end
		end
		if (((ARRAY_COLS < 2) || (ARRAY_COLS > 16)) || ((ARRAY_COLS & (ARRAY_COLS - 1)) != 0)) begin : g_bad_array_cols
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_scratchpad.sv:179:15 - npu_scratchpad_legacy.g_bad_array_cols.<unnamed_block>\n msg: ", $time, "npu_scratchpad: ARRAY_COLS must be a power of two from 2 to 16");
				$finish(1);
			end
		end
		if (((K_TILE < 8) || (K_TILE > 256)) || ((K_TILE & (K_TILE - 1)) != 0)) begin : g_bad_k_tile
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_scratchpad.sv:182:15 - npu_scratchpad_legacy.g_bad_k_tile.<unnamed_block>\n msg: ", $time, "npu_scratchpad: K_TILE must be a power of two from 8 to 256");
				$finish(1);
			end
		end
		if (MAX_ELEM_W != 16) begin : g_bad_element_width
			initial begin
				$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_scratchpad.sv:185:15 - npu_scratchpad_legacy.g_bad_element_width.<unnamed_block>\n msg: ", $time, "npu_scratchpad: MAX_ELEM_W must be 16");
				$finish(1);
			end
		end
	endgenerate
	function automatic legal_transition;
		input reg [1:0] current_state;
		input reg [1:0] requested_state;
		legal_transition = ((((current_state === OWNER_EMPTY) && (requested_state === OWNER_FILLING)) || ((current_state === OWNER_FILLING) && (requested_state === OWNER_READY))) || ((current_state === OWNER_READY) && (requested_state === OWNER_COMPUTE))) || ((current_state === OWNER_COMPUTE) && (requested_state === OWNER_EMPTY));
	endfunction
	always @(posedge clk)
		if (rst) begin
			a_owner <= 1'sb0;
			b_owner <= 1'sb0;
			vector_zero_q <= 1'b1;
			compute_read_data_valid <= 1'b0;
			protocol_error <= 1'b0;
		end
		else begin
			protocol_error <= 1'b0;
			compute_read_data_valid <= 1'b0;
			if (owner_req_valid === 1'b1) begin
				if ((((owner_req_is_b !== 1'b0) && (owner_req_is_b !== 1'b1)) || ((owner_req_bank !== 1'b0) && (owner_req_bank !== 1'b1))) || !((((owner_req_state === OWNER_EMPTY) || (owner_req_state === OWNER_FILLING)) || (owner_req_state === OWNER_READY)) || (owner_req_state === OWNER_COMPUTE)))
					protocol_error <= 1'b1;
				else if (owner_req_is_b === 1'b1) begin
					if (legal_transition(b_owner[owner_req_bank * 2+:2], owner_req_state))
						b_owner[owner_req_bank * 2+:2] <= owner_req_state;
					else
						protocol_error <= 1'b1;
				end
				else if (legal_transition(a_owner[owner_req_bank * 2+:2], owner_req_state))
					a_owner[owner_req_bank * 2+:2] <= owner_req_state;
				else
					protocol_error <= 1'b1;
			end
			if ((dma_write_valid === 1'b1) && !dma_legal)
				protocol_error <= 1'b1;
			if (compute_read_valid === 1'b1) begin
				if (!compute_legal) begin
					protocol_error <= 1'b1;
					vector_zero_q <= 1'b1;
				end
				else begin
					vector_zero_q <= 1'b0;
					compute_read_data_valid <= 1'b1;
				end
			end
		end
	initial _sv2v_0 = 0;
endmodule
module npu_systolic_array (
	clk,
	rst,
	start_valid,
	start_ready,
	k_len,
	row_mask,
	col_mask,
	continue_acc,
	input_int16,
	feed_valid,
	feed_ready,
	feed_a,
	feed_b,
	tile_done,
	acc_read_row,
	acc_read_col,
	acc_rdata,
	acc_row_read_enable,
	acc_row_vector
);
	parameter signed [31:0] ARRAY_ROWS = 4;
	parameter signed [31:0] ARRAY_COLS = 4;
	parameter signed [31:0] ACC_W = 48;
	parameter signed [31:0] MUL_PIPE_STAGES = 1;
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire [15:0] k_len;
	input wire [ARRAY_ROWS - 1:0] row_mask;
	input wire [ARRAY_COLS - 1:0] col_mask;
	input wire continue_acc;
	input wire input_int16;
	input wire feed_valid;
	output wire feed_ready;
	input wire signed [(ARRAY_ROWS * 16) - 1:0] feed_a;
	input wire signed [(ARRAY_COLS * 16) - 1:0] feed_b;
	output reg tile_done;
	input wire [(ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1) - 1:0] acc_read_row;
	input wire [(ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1) - 1:0] acc_read_col;
	output reg signed [ACC_W - 1:0] acc_rdata;
	input wire acc_row_read_enable;
	output reg signed [(ARRAY_COLS * ACC_W) - 1:0] acc_row_vector;
	localparam signed [31:0] ROW_IDX_W = (ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1);
	localparam signed [31:0] COL_IDX_W = (ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1);
	localparam signed [31:0] DRAIN_CYCLES = ((ARRAY_ROWS + ARRAY_COLS) - 2) + MUL_PIPE_STAGES;
	localparam signed [31:0] DRAIN_W = $clog2(DRAIN_CYCLES + 1);
	function automatic signed [((ROW_IDX_W + 0) >= 0 ? ROW_IDX_W + 1 : 1 - (ROW_IDX_W + 0)) - 1:0] sv2v_cast_A8A70_signed;
		input reg signed [((ROW_IDX_W + 0) >= 0 ? ROW_IDX_W + 1 : 1 - (ROW_IDX_W + 0)) - 1:0] inp;
		sv2v_cast_A8A70_signed = inp;
	endfunction
	localparam [ROW_IDX_W:0] ARRAY_ROWS_COUNT = sv2v_cast_A8A70_signed(ARRAY_ROWS);
	function automatic signed [((COL_IDX_W + 0) >= 0 ? COL_IDX_W + 1 : 1 - (COL_IDX_W + 0)) - 1:0] sv2v_cast_9D93A_signed;
		input reg signed [((COL_IDX_W + 0) >= 0 ? COL_IDX_W + 1 : 1 - (COL_IDX_W + 0)) - 1:0] inp;
		sv2v_cast_9D93A_signed = inp;
	endfunction
	localparam [COL_IDX_W:0] ARRAY_COLS_COUNT = sv2v_cast_9D93A_signed(ARRAY_COLS);
	function automatic signed [DRAIN_W - 1:0] sv2v_cast_AEB9A_signed;
		input reg signed [DRAIN_W - 1:0] inp;
		sv2v_cast_AEB9A_signed = inp;
	endfunction
	localparam [DRAIN_W - 1:0] DRAIN_COUNT_INIT = sv2v_cast_AEB9A_signed(DRAIN_CYCLES);
	initial begin
		if (((ARRAY_ROWS < 2) || (ARRAY_ROWS > 16)) || ((ARRAY_ROWS & (ARRAY_ROWS - 1)) != 0)) begin
			$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_systolic_array.sv:38:7 - npu_systolic_array.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_systolic_array: ARRAY_ROWS must be a power of two from 2 to 16");
			$finish(1);
		end
		if (((ARRAY_COLS < 2) || (ARRAY_COLS > 16)) || ((ARRAY_COLS & (ARRAY_COLS - 1)) != 0)) begin
			$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_systolic_array.sv:41:7 - npu_systolic_array.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_systolic_array: ARRAY_COLS must be a power of two from 2 to 16");
			$finish(1);
		end
		if (ACC_W < 48) begin
			$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_systolic_array.sv:43:7 - npu_systolic_array.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_systolic_array: ACC_W must be at least 48");
			$finish(1);
		end
		if ((MUL_PIPE_STAGES != 1) && (MUL_PIPE_STAGES != 2)) begin
			$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_systolic_array.sv:45:7 - npu_systolic_array.<unnamed_block>.<unnamed_block>\n msg: ", $time, "npu_systolic_array: MUL_PIPE_STAGES must be 1 or 2");
			$finish(1);
		end
	end
	reg active_q;
	reg draining_q;
	reg [15:0] k_len_q;
	reg [15:0] feed_count_q;
	reg [DRAIN_W - 1:0] drain_count_q;
	reg [ARRAY_ROWS - 1:0] row_mask_q;
	reg [ARRAY_COLS - 1:0] col_mask_q;
	reg mode_q;
	reg clear_pulse;
	wire feed_fire;
	wire signed [(ARRAY_ROWS * 16) - 1:0] feed_a_normalized;
	wire signed [(ARRAY_COLS * 16) - 1:0] feed_b_normalized;
	genvar _gv_n_1;
	generate
		for (_gv_n_1 = 0; _gv_n_1 < ARRAY_ROWS; _gv_n_1 = _gv_n_1 + 1) begin : g_normalize_a
			localparam n = _gv_n_1;
			assign feed_a_normalized[n * 16+:16] = (mode_q ? feed_a[n * 16+:16] : {{8 {feed_a[(n * 16) + 7]}}, feed_a[n * 16+:8]});
		end
	endgenerate
	genvar _gv_n_2;
	generate
		for (_gv_n_2 = 0; _gv_n_2 < ARRAY_COLS; _gv_n_2 = _gv_n_2 + 1) begin : g_normalize_b
			localparam n = _gv_n_2;
			assign feed_b_normalized[n * 16+:16] = (mode_q ? feed_b[n * 16+:16] : {{8 {feed_b[(n * 16) + 7]}}, feed_b[n * 16+:8]});
		end
	endgenerate
	reg signed [15:0] a_skew_data [0:ARRAY_ROWS - 1][0:ARRAY_ROWS - 1];
	reg signed [15:0] b_skew_data [0:ARRAY_COLS - 1][0:ARRAY_COLS - 1];
	reg a_skew_valid [0:ARRAY_ROWS - 1][0:ARRAY_ROWS - 1];
	reg b_skew_valid [0:ARRAY_COLS - 1][0:ARRAY_COLS - 1];
	wire signed [15:0] a_mesh [0:ARRAY_ROWS - 1][0:ARRAY_COLS];
	wire signed [15:0] b_mesh [0:ARRAY_ROWS][0:ARRAY_COLS - 1];
	wire a_valid_mesh [0:ARRAY_ROWS - 1][0:ARRAY_COLS];
	wire b_valid_mesh [0:ARRAY_ROWS][0:ARRAY_COLS - 1];
	wire signed [ACC_W - 1:0] acc [0:ARRAY_ROWS - 1][0:ARRAY_COLS - 1];
	wire [(ARRAY_COLS * ACC_W) - 1:0] selected_acc_row;
	genvar _gv_c_2;
	generate
		for (_gv_c_2 = 0; _gv_c_2 < ARRAY_COLS; _gv_c_2 = _gv_c_2 + 1) begin : g_shared_result_row
			localparam c = _gv_c_2;
			assign selected_acc_row[c * ACC_W+:ACC_W] = ({1'b0, acc_read_row} < ARRAY_ROWS_COUNT ? acc[acc_read_row][c] : {ACC_W * 1 {1'sb0}});
		end
	endgenerate
	assign start_ready = !active_q;
	assign feed_ready = (active_q && !draining_q) && (feed_count_q < k_len_q);
	assign feed_fire = feed_valid && feed_ready;
	genvar _gv_r_2;
	generate
		for (_gv_r_2 = 0; _gv_r_2 < ARRAY_ROWS; _gv_r_2 = _gv_r_2 + 1) begin : g_a_boundary
			localparam r = _gv_r_2;
			if (r == 0) begin : g_direct
				assign a_mesh[r][0] = feed_a_normalized[r * 16+:16];
				assign a_valid_mesh[r][0] = feed_fire;
			end
			else begin : g_skewed
				assign a_mesh[r][0] = a_skew_data[r][r - 1];
				assign a_valid_mesh[r][0] = a_skew_valid[r][r - 1];
			end
		end
	endgenerate
	genvar _gv_c_3;
	generate
		for (_gv_c_3 = 0; _gv_c_3 < ARRAY_COLS; _gv_c_3 = _gv_c_3 + 1) begin : g_b_boundary
			localparam c = _gv_c_3;
			if (c == 0) begin : g_direct
				assign b_mesh[0][c] = feed_b_normalized[c * 16+:16];
				assign b_valid_mesh[0][c] = feed_fire;
			end
			else begin : g_skewed
				assign b_mesh[0][c] = b_skew_data[c][c - 1];
				assign b_valid_mesh[0][c] = b_skew_valid[c][c - 1];
			end
		end
	endgenerate
	genvar _gv_r_3;
	generate
		for (_gv_r_3 = 0; _gv_r_3 < ARRAY_ROWS; _gv_r_3 = _gv_r_3 + 1) begin : g_pe_rows
			localparam r = _gv_r_3;
			genvar _gv_c_4;
			for (_gv_c_4 = 0; _gv_c_4 < ARRAY_COLS; _gv_c_4 = _gv_c_4 + 1) begin : g_pe_cols
				localparam c = _gv_c_4;
				npu_mac_pe #(
					.ACC_W(ACC_W),
					.MUL_PIPE_STAGES(MUL_PIPE_STAGES)
				) pe(
					.clk(clk),
					.rst(rst),
					.clear_acc(clear_pulse),
					.input_int16(1'b1),
					.a_valid_in(a_valid_mesh[r][c] && row_mask_q[r]),
					.b_valid_in(b_valid_mesh[r][c] && col_mask_q[c]),
					.a_in(a_mesh[r][c]),
					.b_in(b_mesh[r][c]),
					.a_valid_out(a_valid_mesh[r][c + 1]),
					.b_valid_out(b_valid_mesh[r + 1][c]),
					.a_out(a_mesh[r][c + 1]),
					.b_out(b_mesh[r + 1][c]),
					.acc_value(acc[r][c])
				);
			end
		end
	endgenerate
	always @(posedge clk) begin
		begin : sv2v_autoblock_1
			reg signed [31:0] r;
			for (r = 0; r < ARRAY_ROWS; r = r + 1)
				begin
					a_skew_data[r][0] <= feed_a_normalized[r * 16+:16];
					begin : sv2v_autoblock_2
						reg signed [31:0] d;
						for (d = 1; d < ARRAY_ROWS; d = d + 1)
							a_skew_data[r][d] <= a_skew_data[r][d - 1];
					end
				end
		end
		begin : sv2v_autoblock_3
			reg signed [31:0] c;
			for (c = 0; c < ARRAY_COLS; c = c + 1)
				begin
					b_skew_data[c][0] <= feed_b_normalized[c * 16+:16];
					begin : sv2v_autoblock_4
						reg signed [31:0] d;
						for (d = 1; d < ARRAY_COLS; d = d + 1)
							b_skew_data[c][d] <= b_skew_data[c][d - 1];
					end
				end
		end
	end
	always @(posedge clk)
		if (rst) begin
			active_q <= 1'b0;
			draining_q <= 1'b0;
			k_len_q <= 1'sb0;
			feed_count_q <= 1'sb0;
			drain_count_q <= 1'sb0;
			tile_done <= 1'b0;
			acc_rdata <= 1'sb0;
			acc_row_vector <= 1'sb0;
			row_mask_q <= 1'sb0;
			col_mask_q <= 1'sb0;
			mode_q <= 1'b0;
			clear_pulse <= 1'b0;
			begin : sv2v_autoblock_5
				reg signed [31:0] r;
				for (r = 0; r < ARRAY_ROWS; r = r + 1)
					begin : sv2v_autoblock_6
						reg signed [31:0] d;
						for (d = 0; d < ARRAY_ROWS; d = d + 1)
							a_skew_valid[r][d] <= 1'b0;
					end
			end
			begin : sv2v_autoblock_7
				reg signed [31:0] c;
				for (c = 0; c < ARRAY_COLS; c = c + 1)
					begin : sv2v_autoblock_8
						reg signed [31:0] d;
						for (d = 0; d < ARRAY_COLS; d = d + 1)
							b_skew_valid[c][d] <= 1'b0;
					end
			end
		end
		else begin
			tile_done <= 1'b0;
			clear_pulse <= 1'b0;
			if (acc_row_read_enable)
				acc_row_vector <= selected_acc_row;
			if (({1'b0, acc_read_row} < ARRAY_ROWS_COUNT) && ({1'b0, acc_read_col} < ARRAY_COLS_COUNT))
				acc_rdata <= $signed(selected_acc_row[ACC_W * acc_read_col+:ACC_W]);
			else
				acc_rdata <= 1'sb0;
			begin : sv2v_autoblock_9
				reg signed [31:0] r;
				for (r = 0; r < ARRAY_ROWS; r = r + 1)
					begin
						a_skew_valid[r][0] <= feed_fire;
						begin : sv2v_autoblock_10
							reg signed [31:0] d;
							for (d = 1; d < ARRAY_ROWS; d = d + 1)
								a_skew_valid[r][d] <= a_skew_valid[r][d - 1];
						end
					end
			end
			begin : sv2v_autoblock_11
				reg signed [31:0] c;
				for (c = 0; c < ARRAY_COLS; c = c + 1)
					begin
						b_skew_valid[c][0] <= feed_fire;
						begin : sv2v_autoblock_12
							reg signed [31:0] d;
							for (d = 1; d < ARRAY_COLS; d = d + 1)
								b_skew_valid[c][d] <= b_skew_valid[c][d - 1];
						end
					end
			end
			if (start_valid && start_ready) begin
				active_q <= 1'b1;
				draining_q <= 1'b0;
				k_len_q <= k_len;
				feed_count_q <= 1'sb0;
				row_mask_q <= row_mask;
				col_mask_q <= col_mask;
				mode_q <= input_int16;
				clear_pulse <= !continue_acc;
			end
			if (feed_fire) begin
				feed_count_q <= feed_count_q + 16'd1;
				if ((feed_count_q + 16'd1) == k_len_q) begin
					draining_q <= 1'b1;
					drain_count_q <= DRAIN_COUNT_INIT;
				end
			end
			else if (draining_q) begin
				if (drain_count_q == 1) begin
					tile_done <= 1'b1;
					active_q <= 1'b0;
					draining_q <= 1'b0;
					drain_count_q <= 1'sb0;
				end
				else
					drain_count_q <= drain_count_q - 1'b1;
			end
		end
endmodule
module soc_board_mmio_router (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_wdata,
	req_write,
	req_is_fetch,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	m_req_valid,
	m_req_ready,
	m_req_addr,
	m_req_wdata,
	m_req_write,
	m_req_is_fetch,
	m_req_wstrb,
	m_rsp_valid,
	m_rsp_ready,
	m_rsp_rdata,
	m_rsp_error
);
	parameter [31:0] BOARD_BASE = 32'h60001000;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire [31:0] req_wdata;
	input wire req_write;
	input wire req_is_fetch;
	input wire [3:0] req_wstrb;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	output wire [1:0] m_req_valid;
	input wire [1:0] m_req_ready;
	output wire [31:0] m_req_addr;
	output wire [31:0] m_req_wdata;
	output wire m_req_write;
	output wire m_req_is_fetch;
	output wire [3:0] m_req_wstrb;
	input wire [1:0] m_rsp_valid;
	output wire [1:0] m_rsp_ready;
	input wire [63:0] m_rsp_rdata;
	input wire [1:0] m_rsp_error;
	reg busy;
	reg owner;
	wire select_board = req_addr[31:12] == BOARD_BASE[31:12];
	assign m_req_addr = req_addr;
	assign m_req_wdata = req_wdata;
	assign m_req_write = req_write;
	assign m_req_is_fetch = req_is_fetch;
	assign m_req_wstrb = req_wstrb;
	assign m_req_valid = ((!rst && !busy) && req_valid ? (select_board ? 2'b10 : 2'b01) : 2'b00);
	assign req_ready = (!rst && !busy) && m_req_ready[select_board];
	assign rsp_valid = (!rst && busy) && m_rsp_valid[owner];
	assign rsp_rdata = m_rsp_rdata[owner * 32+:32];
	assign rsp_error = m_rsp_error[owner];
	assign m_rsp_ready = ((!rst && busy) && rsp_ready ? (owner ? 2'b10 : 2'b01) : 2'b00);
	always @(posedge clk)
		if (rst) begin
			busy <= 0;
			owner <= 0;
		end
		else begin
			if (req_valid && req_ready) begin
				busy <= 1;
				owner <= select_board;
			end
			if (rsp_valid && rsp_ready)
				busy <= 0;
		end
endmodule
module core0_system_fabric (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	req_is_fetch,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	uart_tx
);
	reg _sv2v_0;
	parameter [31:0] TIMER_BASE = 32'h30000000;
	parameter [31:0] TIMER_SPAN = 32'h00001000;
	parameter [31:0] UART_BASE = 32'h40000000;
	parameter [31:0] UART_SPAN = 32'h00001000;
	parameter [31:0] CLK_FREQ = 100000000;
	parameter [31:0] BAUD_RATE = 115200;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output reg req_ready;
	input wire [31:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	input wire req_is_fetch;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output wire uart_tx;
	localparam [1:0] OWNER_NONE = 2'd0;
	localparam [1:0] OWNER_TIMER = 2'd1;
	localparam [1:0] OWNER_UART = 2'd2;
	localparam [1:0] OWNER_ERROR = 2'd3;
	reg [1:0] owner_q;
	wire select_timer;
	wire select_uart;
	wire select_error;
	wire in_timer_window;
	wire in_uart_window;
	wire request_accept;
	wire response_accept;
	reg timer_req_valid;
	wire timer_req_ready;
	wire timer_rsp_valid;
	wire [31:0] timer_rsp_rdata;
	wire timer_rsp_error;
	reg uart_req_valid;
	wire uart_req_ready;
	wire uart_rsp_valid;
	wire [31:0] uart_rsp_rdata;
	wire uart_rsp_error;
	assign in_timer_window = (req_addr >= TIMER_BASE) && (req_addr < (TIMER_BASE + TIMER_SPAN));
	assign in_uart_window = (req_addr >= UART_BASE) && (req_addr < (UART_BASE + UART_SPAN));
	assign select_error = req_is_fetch || !(in_timer_window || in_uart_window);
	assign select_timer = in_timer_window && !select_error;
	assign select_uart = in_uart_window && !select_error;
	core0_cycle_timer #(
		.BASE_ADDR(TIMER_BASE),
		.SPAN_BYTES(TIMER_SPAN)
	) timer_unit(
		.clk(clk),
		.rst(rst),
		.req_valid(timer_req_valid),
		.req_ready(timer_req_ready),
		.req_addr(req_addr),
		.req_write(req_write),
		.req_wdata(req_wdata),
		.req_wstrb(req_wstrb),
		.rsp_valid(timer_rsp_valid),
		.rsp_ready(rsp_ready),
		.rsp_rdata(timer_rsp_rdata),
		.rsp_error(timer_rsp_error)
	);
	core0_uart_mmio #(
		.BASE_ADDR(UART_BASE),
		.SPAN_BYTES(UART_SPAN),
		.CLK_FREQ(CLK_FREQ),
		.BAUD_RATE(BAUD_RATE)
	) uart_unit(
		.clk(clk),
		.rst(rst),
		.req_valid(uart_req_valid),
		.req_ready(uart_req_ready),
		.req_addr(req_addr),
		.req_write(req_write),
		.req_wdata(req_wdata),
		.req_wstrb(req_wstrb),
		.rsp_valid(uart_rsp_valid),
		.rsp_ready(rsp_ready),
		.rsp_rdata(uart_rsp_rdata),
		.rsp_error(uart_rsp_error),
		.uart_tx(uart_tx)
	);
	always @(*) begin
		if (_sv2v_0)
			;
		timer_req_valid = 1'b0;
		uart_req_valid = 1'b0;
		req_ready = 1'b0;
		if (owner_q == OWNER_NONE) begin
			if (select_timer) begin
				timer_req_valid = req_valid;
				req_ready = timer_req_ready;
			end
			else if (select_uart) begin
				uart_req_valid = req_valid;
				req_ready = uart_req_ready;
			end
			else
				req_ready = 1'b1;
		end
	end
	always @(*) begin
		if (_sv2v_0)
			;
		rsp_valid = 1'b0;
		rsp_rdata = 32'd0;
		rsp_error = 1'b0;
		case (owner_q)
			OWNER_TIMER: begin
				rsp_valid = timer_rsp_valid;
				rsp_rdata = timer_rsp_rdata;
				rsp_error = timer_rsp_error;
			end
			OWNER_UART: begin
				rsp_valid = uart_rsp_valid;
				rsp_rdata = uart_rsp_rdata;
				rsp_error = uart_rsp_error;
			end
			OWNER_ERROR: begin
				rsp_valid = 1'b1;
				rsp_rdata = 32'd0;
				rsp_error = 1'b1;
			end
			default:
				;
		endcase
	end
	assign request_accept = req_valid && req_ready;
	assign response_accept = rsp_valid && rsp_ready;
	always @(posedge clk)
		if (rst)
			owner_q <= OWNER_NONE;
		else begin
			if (response_accept)
				owner_q <= OWNER_NONE;
			if ((owner_q == OWNER_NONE) && request_accept) begin
				if (select_timer)
					owner_q <= OWNER_TIMER;
				else if (select_uart)
					owner_q <= OWNER_UART;
				else if (select_error)
					owner_q <= OWNER_ERROR;
			end
		end
	initial _sv2v_0 = 0;
endmodule
module dc_realtime_core_npu_router (
	clk,
	rst,
	core_req_valid,
	core_req_ready,
	core_req_addr,
	core_req_write,
	core_req_wdata,
	core_req_wstrb,
	core_req_is_fetch,
	core_rsp_valid,
	core_rsp_ready,
	core_rsp_rdata,
	core_rsp_error,
	system_req_valid,
	system_req_ready,
	system_req_addr,
	system_req_write,
	system_req_wdata,
	system_req_wstrb,
	system_req_is_fetch,
	system_rsp_valid,
	system_rsp_ready,
	system_rsp_rdata,
	system_rsp_error,
	npu_req_valid,
	npu_req_ready,
	npu_req_addr,
	npu_req_write,
	npu_req_wdata,
	npu_req_wstrb,
	npu_rsp_valid,
	npu_rsp_ready,
	npu_rsp_rdata,
	npu_rsp_error
);
	reg _sv2v_0;
	parameter [0:0] NPU_ENABLE = 1'b1;
	input wire clk;
	input wire rst;
	input wire core_req_valid;
	output reg core_req_ready;
	input wire [31:0] core_req_addr;
	input wire core_req_write;
	input wire [31:0] core_req_wdata;
	input wire [3:0] core_req_wstrb;
	input wire core_req_is_fetch;
	output reg core_rsp_valid;
	input wire core_rsp_ready;
	output reg [31:0] core_rsp_rdata;
	output reg core_rsp_error;
	output reg system_req_valid;
	input wire system_req_ready;
	output reg [31:0] system_req_addr;
	output reg system_req_write;
	output reg [31:0] system_req_wdata;
	output reg [3:0] system_req_wstrb;
	output reg system_req_is_fetch;
	input wire system_rsp_valid;
	output reg system_rsp_ready;
	input wire [31:0] system_rsp_rdata;
	input wire system_rsp_error;
	output reg npu_req_valid;
	input wire npu_req_ready;
	output reg [15:0] npu_req_addr;
	output reg npu_req_write;
	output reg [31:0] npu_req_wdata;
	output reg [3:0] npu_req_wstrb;
	input wire npu_rsp_valid;
	output reg npu_rsp_ready;
	input wire [31:0] npu_rsp_rdata;
	input wire npu_rsp_error;
	localparam [31:0] DC_RT_NPU_BASE = 32'h70000000;
	localparam [31:0] DC_RT_NPU_END = 32'h70010000;
	reg [1:0] owner_q;
	wire npu_window_hit;
	wire select_npu;
	wire select_error;
	wire request_accept;
	wire response_accept;
	assign npu_window_hit = (core_req_addr >= DC_RT_NPU_BASE) && (core_req_addr < DC_RT_NPU_END);
	assign select_npu = (npu_window_hit && !core_req_is_fetch) && NPU_ENABLE;
	assign select_error = npu_window_hit && (core_req_is_fetch || !NPU_ENABLE);
	always @(*) begin
		if (_sv2v_0)
			;
		system_req_valid = 1'b0;
		system_req_addr = core_req_addr;
		system_req_write = core_req_write;
		system_req_wdata = core_req_wdata;
		system_req_wstrb = core_req_wstrb;
		system_req_is_fetch = core_req_is_fetch;
		npu_req_valid = 1'b0;
		npu_req_addr = core_req_addr[15:0];
		npu_req_write = core_req_write;
		npu_req_wdata = core_req_wdata;
		npu_req_wstrb = core_req_wstrb;
		core_req_ready = 1'b0;
		if (owner_q == 2'd0) begin
			if (select_npu) begin
				npu_req_valid = core_req_valid;
				core_req_ready = npu_req_ready;
			end
			else if (select_error)
				core_req_ready = 1'b1;
			else begin
				system_req_valid = core_req_valid;
				core_req_ready = system_req_ready;
			end
		end
	end
	always @(*) begin
		if (_sv2v_0)
			;
		core_rsp_valid = 1'b0;
		core_rsp_rdata = 32'd0;
		core_rsp_error = 1'b0;
		system_rsp_ready = 1'b0;
		npu_rsp_ready = 1'b0;
		case (owner_q)
			2'd1: begin
				core_rsp_valid = system_rsp_valid;
				core_rsp_rdata = system_rsp_rdata;
				core_rsp_error = system_rsp_error;
				system_rsp_ready = core_rsp_ready;
			end
			2'd2: begin
				core_rsp_valid = npu_rsp_valid;
				core_rsp_rdata = npu_rsp_rdata;
				core_rsp_error = npu_rsp_error;
				npu_rsp_ready = core_rsp_ready;
			end
			2'd3: begin
				core_rsp_valid = 1'b1;
				core_rsp_rdata = 32'd0;
				core_rsp_error = 1'b1;
			end
			default:
				;
		endcase
	end
	assign request_accept = core_req_valid && core_req_ready;
	assign response_accept = core_rsp_valid && core_rsp_ready;
	always @(posedge clk)
		if (rst)
			owner_q <= 2'd0;
		else begin
			if (response_accept)
				owner_q <= 2'd0;
			if ((owner_q == 2'd0) && request_accept) begin
				if (select_npu)
					owner_q <= 2'd2;
				else if (select_error)
					owner_q <= 2'd3;
				else
					owner_q <= 2'd1;
			end
		end
	initial _sv2v_0 = 0;
endmodule
module pg_ddr_burst_bridge (
	clk,
	rst,
	s_req_valid,
	s_req_ready,
	s_req_write,
	s_req_addr,
	s_req_wdata,
	s_req_wstrb,
	s_req_tag,
	s_rsp_valid,
	s_rsp_ready,
	s_rsp_write,
	s_rsp_rdata,
	s_rsp_tag,
	s_rsp_error,
	m_axi_awid,
	m_axi_awaddr,
	m_axi_awlen,
	m_axi_awsize,
	m_axi_awburst,
	m_axi_awlock,
	m_axi_awcache,
	m_axi_awprot,
	m_axi_awvalid,
	m_axi_awready,
	m_axi_wdata,
	m_axi_wstrb,
	m_axi_wlast,
	m_axi_wvalid,
	m_axi_wready,
	m_axi_bid,
	m_axi_bresp,
	m_axi_bvalid,
	m_axi_bready,
	m_axi_arid,
	m_axi_araddr,
	m_axi_arlen,
	m_axi_arsize,
	m_axi_arburst,
	m_axi_arlock,
	m_axi_arcache,
	m_axi_arprot,
	m_axi_arvalid,
	m_axi_arready,
	m_axi_rid,
	m_axi_rdata,
	m_axi_rresp,
	m_axi_rlast,
	m_axi_rvalid,
	m_axi_rready,
	protocol_fault,
	busy,
	accepted_count,
	completed_count,
	burst_count
);
	parameter signed [31:0] DATA_W = 128;
	parameter signed [31:0] TAG_W = 5;
	parameter signed [31:0] MAX_BEATS = 16;
	parameter signed [31:0] FLUSH_CYCLES = 5;
	parameter [0:0] PIPELINED_COLLECT = 1'b1;
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [32:0] DDR_BYTES = 33'h010000000;
	input wire clk;
	input wire rst;
	input wire s_req_valid;
	output wire s_req_ready;
	input wire s_req_write;
	input wire [31:0] s_req_addr;
	input wire [DATA_W - 1:0] s_req_wdata;
	input wire [(DATA_W / 8) - 1:0] s_req_wstrb;
	input wire [TAG_W - 1:0] s_req_tag;
	output wire s_rsp_valid;
	input wire s_rsp_ready;
	output wire s_rsp_write;
	output wire [DATA_W - 1:0] s_rsp_rdata;
	output wire [TAG_W - 1:0] s_rsp_tag;
	output wire s_rsp_error;
	output wire [3:0] m_axi_awid;
	output wire [31:0] m_axi_awaddr;
	output wire [7:0] m_axi_awlen;
	output wire [2:0] m_axi_awsize;
	output wire [1:0] m_axi_awburst;
	output wire m_axi_awlock;
	output wire [3:0] m_axi_awcache;
	output wire [2:0] m_axi_awprot;
	output wire m_axi_awvalid;
	input wire m_axi_awready;
	output wire [DATA_W - 1:0] m_axi_wdata;
	output wire [(DATA_W / 8) - 1:0] m_axi_wstrb;
	output wire m_axi_wlast;
	output wire m_axi_wvalid;
	input wire m_axi_wready;
	input wire [3:0] m_axi_bid;
	input wire [1:0] m_axi_bresp;
	input wire m_axi_bvalid;
	output wire m_axi_bready;
	output wire [3:0] m_axi_arid;
	output wire [31:0] m_axi_araddr;
	output wire [7:0] m_axi_arlen;
	output wire [2:0] m_axi_arsize;
	output wire [1:0] m_axi_arburst;
	output wire m_axi_arlock;
	output wire [3:0] m_axi_arcache;
	output wire [2:0] m_axi_arprot;
	output wire m_axi_arvalid;
	input wire m_axi_arready;
	input wire [3:0] m_axi_rid;
	input wire [DATA_W - 1:0] m_axi_rdata;
	input wire [1:0] m_axi_rresp;
	input wire m_axi_rlast;
	input wire m_axi_rvalid;
	output wire m_axi_rready;
	output wire protocol_fault;
	output wire busy;
	output wire [31:0] accepted_count;
	output wire [31:0] completed_count;
	output wire [31:0] burst_count;
	generate
		if (PIPELINED_COLLECT) begin : g_overlap
			pg_ddr_burst_bridge_overlap #(
				.DATA_W(DATA_W),
				.TAG_W(TAG_W),
				.MAX_BEATS(MAX_BEATS),
				.FLUSH_CYCLES(FLUSH_CYCLES),
				.DDR_BASE(DDR_BASE),
				.DDR_BYTES(DDR_BYTES)
			) impl(
				.clk(clk),
				.rst(rst),
				.s_req_valid(s_req_valid),
				.s_req_ready(s_req_ready),
				.s_req_write(s_req_write),
				.s_req_addr(s_req_addr),
				.s_req_wdata(s_req_wdata),
				.s_req_wstrb(s_req_wstrb),
				.s_req_tag(s_req_tag),
				.s_rsp_valid(s_rsp_valid),
				.s_rsp_ready(s_rsp_ready),
				.s_rsp_write(s_rsp_write),
				.s_rsp_rdata(s_rsp_rdata),
				.s_rsp_tag(s_rsp_tag),
				.s_rsp_error(s_rsp_error),
				.m_axi_awid(m_axi_awid),
				.m_axi_awaddr(m_axi_awaddr),
				.m_axi_awlen(m_axi_awlen),
				.m_axi_awsize(m_axi_awsize),
				.m_axi_awburst(m_axi_awburst),
				.m_axi_awlock(m_axi_awlock),
				.m_axi_awcache(m_axi_awcache),
				.m_axi_awprot(m_axi_awprot),
				.m_axi_awvalid(m_axi_awvalid),
				.m_axi_awready(m_axi_awready),
				.m_axi_wdata(m_axi_wdata),
				.m_axi_wstrb(m_axi_wstrb),
				.m_axi_wlast(m_axi_wlast),
				.m_axi_wvalid(m_axi_wvalid),
				.m_axi_wready(m_axi_wready),
				.m_axi_bid(m_axi_bid),
				.m_axi_bresp(m_axi_bresp),
				.m_axi_bvalid(m_axi_bvalid),
				.m_axi_bready(m_axi_bready),
				.m_axi_arid(m_axi_arid),
				.m_axi_araddr(m_axi_araddr),
				.m_axi_arlen(m_axi_arlen),
				.m_axi_arsize(m_axi_arsize),
				.m_axi_arburst(m_axi_arburst),
				.m_axi_arlock(m_axi_arlock),
				.m_axi_arcache(m_axi_arcache),
				.m_axi_arprot(m_axi_arprot),
				.m_axi_arvalid(m_axi_arvalid),
				.m_axi_arready(m_axi_arready),
				.m_axi_rid(m_axi_rid),
				.m_axi_rdata(m_axi_rdata),
				.m_axi_rresp(m_axi_rresp),
				.m_axi_rlast(m_axi_rlast),
				.m_axi_rvalid(m_axi_rvalid),
				.m_axi_rready(m_axi_rready),
				.protocol_fault(protocol_fault),
				.busy(busy),
				.accepted_count(accepted_count),
				.completed_count(completed_count),
				.burst_count(burst_count)
			);
		end
		else begin : g_serial
			pg_ddr_burst_bridge_serial #(
				.DATA_W(DATA_W),
				.TAG_W(TAG_W),
				.MAX_BEATS(MAX_BEATS),
				.FLUSH_CYCLES(FLUSH_CYCLES),
				.DDR_BASE(DDR_BASE),
				.DDR_BYTES(DDR_BYTES)
			) impl(
				.clk(clk),
				.rst(rst),
				.s_req_valid(s_req_valid),
				.s_req_ready(s_req_ready),
				.s_req_write(s_req_write),
				.s_req_addr(s_req_addr),
				.s_req_wdata(s_req_wdata),
				.s_req_wstrb(s_req_wstrb),
				.s_req_tag(s_req_tag),
				.s_rsp_valid(s_rsp_valid),
				.s_rsp_ready(s_rsp_ready),
				.s_rsp_write(s_rsp_write),
				.s_rsp_rdata(s_rsp_rdata),
				.s_rsp_tag(s_rsp_tag),
				.s_rsp_error(s_rsp_error),
				.m_axi_awid(m_axi_awid),
				.m_axi_awaddr(m_axi_awaddr),
				.m_axi_awlen(m_axi_awlen),
				.m_axi_awsize(m_axi_awsize),
				.m_axi_awburst(m_axi_awburst),
				.m_axi_awlock(m_axi_awlock),
				.m_axi_awcache(m_axi_awcache),
				.m_axi_awprot(m_axi_awprot),
				.m_axi_awvalid(m_axi_awvalid),
				.m_axi_awready(m_axi_awready),
				.m_axi_wdata(m_axi_wdata),
				.m_axi_wstrb(m_axi_wstrb),
				.m_axi_wlast(m_axi_wlast),
				.m_axi_wvalid(m_axi_wvalid),
				.m_axi_wready(m_axi_wready),
				.m_axi_bid(m_axi_bid),
				.m_axi_bresp(m_axi_bresp),
				.m_axi_bvalid(m_axi_bvalid),
				.m_axi_bready(m_axi_bready),
				.m_axi_arid(m_axi_arid),
				.m_axi_araddr(m_axi_araddr),
				.m_axi_arlen(m_axi_arlen),
				.m_axi_arsize(m_axi_arsize),
				.m_axi_arburst(m_axi_arburst),
				.m_axi_arlock(m_axi_arlock),
				.m_axi_arcache(m_axi_arcache),
				.m_axi_arprot(m_axi_arprot),
				.m_axi_arvalid(m_axi_arvalid),
				.m_axi_arready(m_axi_arready),
				.m_axi_rid(m_axi_rid),
				.m_axi_rdata(m_axi_rdata),
				.m_axi_rresp(m_axi_rresp),
				.m_axi_rlast(m_axi_rlast),
				.m_axi_rvalid(m_axi_rvalid),
				.m_axi_rready(m_axi_rready),
				.protocol_fault(protocol_fault),
				.busy(busy),
				.accepted_count(accepted_count),
				.completed_count(completed_count),
				.burst_count(burst_count)
			);
		end
	endgenerate
endmodule
module pg_ddr_burst_bridge_overlap (
	clk,
	rst,
	s_req_valid,
	s_req_ready,
	s_req_write,
	s_req_addr,
	s_req_wdata,
	s_req_wstrb,
	s_req_tag,
	s_rsp_valid,
	s_rsp_ready,
	s_rsp_write,
	s_rsp_rdata,
	s_rsp_tag,
	s_rsp_error,
	m_axi_awid,
	m_axi_awaddr,
	m_axi_awlen,
	m_axi_awsize,
	m_axi_awburst,
	m_axi_awlock,
	m_axi_awcache,
	m_axi_awprot,
	m_axi_awvalid,
	m_axi_awready,
	m_axi_wdata,
	m_axi_wstrb,
	m_axi_wlast,
	m_axi_wvalid,
	m_axi_wready,
	m_axi_bid,
	m_axi_bresp,
	m_axi_bvalid,
	m_axi_bready,
	m_axi_arid,
	m_axi_araddr,
	m_axi_arlen,
	m_axi_arsize,
	m_axi_arburst,
	m_axi_arlock,
	m_axi_arcache,
	m_axi_arprot,
	m_axi_arvalid,
	m_axi_arready,
	m_axi_rid,
	m_axi_rdata,
	m_axi_rresp,
	m_axi_rlast,
	m_axi_rvalid,
	m_axi_rready,
	protocol_fault,
	busy,
	accepted_count,
	completed_count,
	burst_count
);
	reg _sv2v_0;
	parameter signed [31:0] DATA_W = 128;
	parameter signed [31:0] TAG_W = 5;
	parameter signed [31:0] MAX_BEATS = 16;
	parameter signed [31:0] FLUSH_CYCLES = 5;
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [32:0] DDR_BYTES = 33'h010000000;
	input wire clk;
	input wire rst;
	input wire s_req_valid;
	output wire s_req_ready;
	input wire s_req_write;
	input wire [31:0] s_req_addr;
	input wire [DATA_W - 1:0] s_req_wdata;
	input wire [(DATA_W / 8) - 1:0] s_req_wstrb;
	input wire [TAG_W - 1:0] s_req_tag;
	output wire s_rsp_valid;
	input wire s_rsp_ready;
	output wire s_rsp_write;
	output wire [DATA_W - 1:0] s_rsp_rdata;
	output wire [TAG_W - 1:0] s_rsp_tag;
	output wire s_rsp_error;
	output wire [3:0] m_axi_awid;
	output wire [31:0] m_axi_awaddr;
	output wire [7:0] m_axi_awlen;
	output wire [2:0] m_axi_awsize;
	output wire [1:0] m_axi_awburst;
	output wire m_axi_awlock;
	output wire [3:0] m_axi_awcache;
	output wire [2:0] m_axi_awprot;
	output wire m_axi_awvalid;
	input wire m_axi_awready;
	output wire [DATA_W - 1:0] m_axi_wdata;
	output wire [(DATA_W / 8) - 1:0] m_axi_wstrb;
	output wire m_axi_wlast;
	output wire m_axi_wvalid;
	input wire m_axi_wready;
	input wire [3:0] m_axi_bid;
	input wire [1:0] m_axi_bresp;
	input wire m_axi_bvalid;
	output wire m_axi_bready;
	output wire [3:0] m_axi_arid;
	output wire [31:0] m_axi_araddr;
	output wire [7:0] m_axi_arlen;
	output wire [2:0] m_axi_arsize;
	output wire [1:0] m_axi_arburst;
	output wire m_axi_arlock;
	output wire [3:0] m_axi_arcache;
	output wire [2:0] m_axi_arprot;
	output wire m_axi_arvalid;
	input wire m_axi_arready;
	input wire [3:0] m_axi_rid;
	input wire [DATA_W - 1:0] m_axi_rdata;
	input wire [1:0] m_axi_rresp;
	input wire m_axi_rlast;
	input wire m_axi_rvalid;
	output wire m_axi_rready;
	output wire protocol_fault;
	output wire busy;
	output reg [31:0] accepted_count;
	output reg [31:0] completed_count;
	output reg [31:0] burst_count;
	localparam signed [31:0] BYTES = DATA_W / 8;
	localparam signed [31:0] LG = $clog2(BYTES);
	localparam signed [31:0] CW = $clog2(MAX_BEATS + 1);
	localparam signed [31:0] IW = (MAX_BEATS < 2 ? 1 : $clog2(MAX_BEATS));
	localparam signed [31:0] RW = (DATA_W + TAG_W) + 2;
	localparam signed [31:0] QW = ((33 + DATA_W) + BYTES) + TAG_W;
	localparam [32:0] LIMIT = {1'b0, DDR_BASE} + DDR_BYTES;
	reg [3:0] state;
	reg [31:0] base_q;
	reg write_q;
	reg aw_sent_q;
	reg b_error_q;
	reg [CW - 1:0] count_q;
	reg [CW - 1:0] read_index_q;
	reg [CW - 1:0] write_index_q;
	reg [CW - 1:0] ack_index_q;
	reg [7:0] gap_q;
	reg active_bank;
	reg fill_bank;
	reg fill_sealed;
	reg fill_legal;
	reg fill_write;
	reg ack_pending;
	reg ack_bank;
	reg [CW - 1:0] ack_count;
	reg [31:0] fill_base;
	reg [CW - 1:0] fill_count;
	reg [7:0] fill_gap;
	wire seal;
	wire dispatch = ((state == 4'd0) || (state == 4'd7)) && (fill_sealed || seal);
	reg [DATA_W - 1:0] data_q [0:1][0:MAX_BEATS - 1];
	reg [BYTES - 1:0] strb_q [0:1][0:MAX_BEATS - 1];
	reg [TAG_W - 1:0] tag_q [0:1][0:MAX_BEATS - 1];
	wire legal_req;
	wire joins_req;
	wire req_fire;
	wire collect_fire;
	wire aw_fire;
	wire w_fire;
	wire r_fire;
	wire b_fire;
	wire req_fifo_in_ready;
	wire req_fifo_out_valid;
	wire req_fifo_out_ready;
	wire [QW - 1:0] req_fifo_out_data;
	wire [CW - 1:0] req_fifo_level;
	wire collect_write;
	wire [31:0] collect_addr;
	wire [DATA_W - 1:0] collect_wdata;
	wire [BYTES - 1:0] collect_wstrb;
	wire [TAG_W - 1:0] collect_tag;
	wire r_malformed;
	reg fifo_in_valid;
	wire fifo_in_ready;
	reg [RW - 1:0] fifo_in_data;
	wire [RW - 1:0] fifo_out_data;
	wire [CW - 1:0] fifo_level;
	pg_sync_fifo #(
		.WIDTH(QW),
		.DEPTH(MAX_BEATS)
	) pending_requests(
		.clk(clk),
		.rst(rst),
		.in_valid(s_req_valid && !protocol_fault),
		.in_ready(req_fifo_in_ready),
		.in_data({s_req_write, s_req_addr, s_req_wdata, s_req_wstrb, s_req_tag}),
		.out_valid(req_fifo_out_valid),
		.out_ready(req_fifo_out_ready),
		.out_data(req_fifo_out_data),
		.level(req_fifo_level)
	);
	assign {collect_write, collect_addr, collect_wdata, collect_wstrb, collect_tag} = req_fifo_out_data;
	function automatic signed [32:0] sv2v_cast_33_signed;
		input reg signed [32:0] inp;
		sv2v_cast_33_signed = inp;
	endfunction
	assign legal_req = ((collect_addr[LG - 1:0] == {LG * 1 {1'sb0}}) && ({1'b0, collect_addr} >= {1'b0, DDR_BASE})) && (({1'b0, collect_addr} + sv2v_cast_33_signed(BYTES)) <= LIMIT);
	function automatic [32:0] sv2v_cast_33;
		input reg [32:0] inp;
		sv2v_cast_33 = inp;
	endfunction
	assign joins_req = (fill_count == 0) || (((legal_req && (collect_write == fill_write)) && ({1'b0, collect_addr} == ({1'b0, fill_base} + (sv2v_cast_33(fill_count) << LG)))) && (collect_addr[31:12] == fill_base[31:12]));
	function automatic signed [CW - 1:0] sv2v_cast_3D2D3_signed;
		input reg signed [CW - 1:0] inp;
		sv2v_cast_3D2D3_signed = inp;
	endfunction
	assign req_fifo_out_ready = ((((!rst && !protocol_fault) && !fill_sealed) && !(ack_pending && (fill_bank == ack_bank))) && (fill_count < sv2v_cast_3D2D3_signed(MAX_BEATS))) && joins_req;
	assign s_req_ready = (!rst && !protocol_fault) && req_fifo_in_ready;
	assign req_fire = s_req_valid && s_req_ready;
	assign collect_fire = req_fifo_out_valid && req_fifo_out_ready;
	function automatic signed [7:0] sv2v_cast_8_signed;
		input reg signed [7:0] inp;
		sv2v_cast_8_signed = inp;
	endfunction
	assign seal = ((!fill_sealed && (fill_count != 0)) && !collect_fire) && ((req_fifo_out_valid && !joins_req) || (((state == 4'd0) || (state == 4'd7)) && (fill_gap >= sv2v_cast_8_signed(FLUSH_CYCLES - 1))));
	assign protocol_fault = state == 4'd8;
	assign busy = ((((((state != 4'd0) || (count_q != 0)) || (req_fifo_level != 0)) || (fifo_level != 0)) || (fill_count != 0)) || fill_sealed) || ack_pending;
	assign m_axi_awid = 1'sb0;
	assign m_axi_awaddr = base_q;
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	assign m_axi_awlen = (count_q != 0 ? sv2v_cast_8(count_q - 1'b1) : 8'd0);
	function automatic signed [2:0] sv2v_cast_3_signed;
		input reg signed [2:0] inp;
		sv2v_cast_3_signed = inp;
	endfunction
	assign m_axi_awsize = sv2v_cast_3_signed(LG);
	assign m_axi_awburst = 2'b01;
	assign m_axi_awlock = 1'b0;
	assign m_axi_awcache = 4'b0000;
	assign m_axi_awprot = 3'b000;
	assign m_axi_awvalid = (!rst && (state == 4'd3)) && !aw_sent_q;
	assign m_axi_wvalid = (!rst && (state == 4'd3)) && (write_index_q < count_q);
	function automatic [IW - 1:0] sv2v_cast_83959;
		input reg [IW - 1:0] inp;
		sv2v_cast_83959 = inp;
	endfunction
	assign m_axi_wdata = (m_axi_wvalid ? data_q[active_bank][sv2v_cast_83959(write_index_q)] : {DATA_W {1'sb0}});
	assign m_axi_wstrb = (m_axi_wvalid ? strb_q[active_bank][sv2v_cast_83959(write_index_q)] : {DATA_W / 8 {1'sb0}});
	assign m_axi_wlast = (write_index_q + 1'b1) == count_q;
	assign m_axi_bready = (!rst && (state == 4'd4)) && !ack_pending;
	assign m_axi_arid = 1'sb0;
	assign m_axi_araddr = base_q;
	assign m_axi_arlen = m_axi_awlen;
	assign m_axi_arsize = sv2v_cast_3_signed(LG);
	assign m_axi_arburst = 2'b01;
	assign m_axi_arlock = 1'b0;
	assign m_axi_arcache = 4'b0000;
	assign m_axi_arprot = 3'b000;
	assign m_axi_arvalid = !rst && (state == 4'd1);
	assign m_axi_rready = ((!rst && (state == 4'd2)) && !ack_pending) && fifo_in_ready;
	assign aw_fire = m_axi_awvalid && m_axi_awready;
	assign w_fire = m_axi_wvalid && m_axi_wready;
	assign r_fire = m_axi_rvalid && m_axi_rready;
	assign b_fire = m_axi_bvalid && m_axi_bready;
	assign r_malformed = (m_axi_rid != 0) || (m_axi_rlast != ((read_index_q + 1'b1) == count_q));
	always @(*) begin
		if (_sv2v_0)
			;
		fifo_in_valid = 1'b0;
		fifo_in_data = 1'sb0;
		if (ack_pending) begin
			fifo_in_valid = 1'b1;
			fifo_in_data = {b_error_q, 1'b1, tag_q[ack_bank][sv2v_cast_83959(ack_index_q)], {DATA_W {1'b0}}};
		end
		else
			case (state)
				4'd2: begin
					fifo_in_valid = m_axi_rvalid;
					fifo_in_data = {(m_axi_rresp != 0) || r_malformed, 1'b0, tag_q[active_bank][sv2v_cast_83959(read_index_q)], ((m_axi_rresp != 0) || r_malformed ? {DATA_W {1'b0}} : m_axi_rdata)};
				end
				4'd6: begin
					fifo_in_valid = 1'b1;
					fifo_in_data = {1'b1, write_q, tag_q[active_bank][0], {DATA_W {1'b0}}};
				end
				default:
					;
			endcase
	end
	always @(posedge clk)
		if (rst) begin
			ack_pending <= 0;
			ack_bank <= 0;
			ack_count <= 0;
			ack_index_q <= 0;
			b_error_q <= 0;
		end
		else if (b_fire && (m_axi_bid == 0)) begin
			ack_pending <= 1;
			ack_bank <= active_bank;
			ack_count <= count_q;
			ack_index_q <= 0;
			b_error_q <= m_axi_bresp != 0;
		end
		else if (ack_pending && fifo_in_ready) begin
			ack_index_q <= ack_index_q + 1'b1;
			if ((ack_index_q + 1'b1) == ack_count)
				ack_pending <= 0;
		end
	pg_sync_fifo #(
		.WIDTH(RW),
		.DEPTH(MAX_BEATS)
	) responses(
		.clk(clk),
		.rst(rst),
		.in_valid(fifo_in_valid),
		.in_ready(fifo_in_ready),
		.in_data(fifo_in_data),
		.out_valid(s_rsp_valid),
		.out_ready(s_rsp_ready),
		.out_data(fifo_out_data),
		.level(fifo_level)
	);
	assign {s_rsp_error, s_rsp_write, s_rsp_tag, s_rsp_rdata} = fifo_out_data;
	initial begin
		if (((DATA_W != 32) && (DATA_W != 64)) && (DATA_W != 128)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/pg_ddr_burst_bridge.sv:229:48 - pg_ddr_burst_bridge_overlap.<unnamed_block>.<unnamed_block>\n msg: ", $time, "PG_DDR_DATA_WIDTH_RED");
			$finish(1);
		end
		if (((((TAG_W < 1) || (MAX_BEATS < 1)) || (MAX_BEATS > 16)) || (FLUSH_CYCLES < 1)) || (FLUSH_CYCLES > 255)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/pg_ddr_burst_bridge.sv:231:13 - pg_ddr_burst_bridge_overlap.<unnamed_block>.<unnamed_block>\n msg: ", $time, "PG_DDR_PARAMETER_RED");
			$finish(1);
		end
		if ((((DDR_BYTES == 0) || (LIMIT > 33'h100000000)) || ((DDR_BASE % BYTES) != 0)) || ((DDR_BYTES % sv2v_cast_33_signed(BYTES)) != 0)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/pg_ddr_burst_bridge.sv:233:13 - pg_ddr_burst_bridge_overlap.<unnamed_block>.<unnamed_block>\n msg: ", $time, "PG_DDR_APERTURE_RED");
			$finish(1);
		end
	end
	always @(posedge clk)
		if (rst) begin
			fill_bank <= 0;
			fill_sealed <= 0;
			fill_legal <= 1;
			fill_write <= 0;
			fill_base <= 0;
			fill_count <= 0;
			fill_gap <= 0;
		end
		else if (!protocol_fault) begin
			if (dispatch) begin
				fill_bank <= !fill_bank;
				fill_sealed <= 0;
				fill_count <= 0;
				fill_gap <= 0;
			end
			else if (!fill_sealed) begin
				if (collect_fire) begin
					tag_q[fill_bank][sv2v_cast_83959(fill_count)] <= collect_tag;
					data_q[fill_bank][sv2v_cast_83959(fill_count)] <= collect_wdata;
					strb_q[fill_bank][sv2v_cast_83959(fill_count)] <= collect_wstrb;
					fill_count <= fill_count + 1'b1;
					fill_gap <= 0;
					if (fill_count == 0) begin
						fill_base <= collect_addr;
						fill_write <= collect_write;
						fill_legal <= legal_req;
					end
					if (((fill_count == 0) && !legal_req) || (fill_count == sv2v_cast_3D2D3_signed(MAX_BEATS - 1)))
						fill_sealed <= 1;
				end
				else if (fill_count != 0) begin
					if (seal)
						fill_sealed <= 1;
					else if (fill_gap < sv2v_cast_8_signed(FLUSH_CYCLES))
						fill_gap <= fill_gap + 1'b1;
				end
			end
		end
	always @(posedge clk)
		if (rst) begin
			state <= 4'd0;
			base_q <= 1'sb0;
			write_q <= 0;
			aw_sent_q <= 0;
			active_bank <= 1;
			count_q <= 1'sb0;
			read_index_q <= 1'sb0;
			write_index_q <= 1'sb0;
			gap_q <= 0;
			accepted_count <= 0;
			completed_count <= 0;
			burst_count <= 0;
		end
		else begin
			if (req_fire)
				accepted_count <= accepted_count + 1'b1;
			if (s_rsp_valid && s_rsp_ready)
				completed_count <= completed_count + 1'b1;
			case (state)
				4'd0, 4'd7:
					if (dispatch) begin
						base_q <= fill_base;
						write_q <= fill_write;
						count_q <= fill_count;
						active_bank <= fill_bank;
						read_index_q <= 0;
						write_index_q <= 0;
						aw_sent_q <= 0;
						if (!fill_legal)
							state <= 4'd6;
						else begin
							state <= (fill_write ? 4'd3 : 4'd1);
							burst_count <= burst_count + 1'b1;
						end
					end
					else if (state == 4'd7) begin
						count_q <= 0;
						gap_q <= 0;
						state <= 4'd0;
					end
				4'd1:
					if (m_axi_arvalid && m_axi_arready)
						state <= 4'd2;
				4'd2:
					if (r_fire) begin
						read_index_q <= read_index_q + 1'b1;
						if (r_malformed)
							state <= 4'd8;
						else if ((read_index_q + 1'b1) == count_q)
							state <= 4'd7;
					end
				4'd3: begin
					if (aw_fire)
						aw_sent_q <= 1;
					if (w_fire)
						write_index_q <= write_index_q + 1'b1;
					if ((aw_sent_q || aw_fire) && ((write_index_q == count_q) || (w_fire && m_axi_wlast)))
						state <= 4'd4;
				end
				4'd4:
					if (b_fire) begin
						if (m_axi_bid != 0)
							state <= 4'd8;
						else
							state <= 4'd7;
					end
				4'd6:
					if (fifo_in_ready && !ack_pending)
						state <= 4'd7;
				4'd8:
					;
				default: state <= 4'd8;
			endcase
		end
	initial _sv2v_0 = 0;
endmodule
module pg_ddr_burst_bridge_serial (
	clk,
	rst,
	s_req_valid,
	s_req_ready,
	s_req_write,
	s_req_addr,
	s_req_wdata,
	s_req_wstrb,
	s_req_tag,
	s_rsp_valid,
	s_rsp_ready,
	s_rsp_write,
	s_rsp_rdata,
	s_rsp_tag,
	s_rsp_error,
	m_axi_awid,
	m_axi_awaddr,
	m_axi_awlen,
	m_axi_awsize,
	m_axi_awburst,
	m_axi_awlock,
	m_axi_awcache,
	m_axi_awprot,
	m_axi_awvalid,
	m_axi_awready,
	m_axi_wdata,
	m_axi_wstrb,
	m_axi_wlast,
	m_axi_wvalid,
	m_axi_wready,
	m_axi_bid,
	m_axi_bresp,
	m_axi_bvalid,
	m_axi_bready,
	m_axi_arid,
	m_axi_araddr,
	m_axi_arlen,
	m_axi_arsize,
	m_axi_arburst,
	m_axi_arlock,
	m_axi_arcache,
	m_axi_arprot,
	m_axi_arvalid,
	m_axi_arready,
	m_axi_rid,
	m_axi_rdata,
	m_axi_rresp,
	m_axi_rlast,
	m_axi_rvalid,
	m_axi_rready,
	protocol_fault,
	busy,
	accepted_count,
	completed_count,
	burst_count
);
	reg _sv2v_0;
	parameter signed [31:0] DATA_W = 128;
	parameter signed [31:0] TAG_W = 5;
	parameter signed [31:0] MAX_BEATS = 16;
	parameter signed [31:0] FLUSH_CYCLES = 5;
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [32:0] DDR_BYTES = 33'h010000000;
	input wire clk;
	input wire rst;
	input wire s_req_valid;
	output wire s_req_ready;
	input wire s_req_write;
	input wire [31:0] s_req_addr;
	input wire [DATA_W - 1:0] s_req_wdata;
	input wire [(DATA_W / 8) - 1:0] s_req_wstrb;
	input wire [TAG_W - 1:0] s_req_tag;
	output wire s_rsp_valid;
	input wire s_rsp_ready;
	output wire s_rsp_write;
	output wire [DATA_W - 1:0] s_rsp_rdata;
	output wire [TAG_W - 1:0] s_rsp_tag;
	output wire s_rsp_error;
	output wire [3:0] m_axi_awid;
	output wire [31:0] m_axi_awaddr;
	output wire [7:0] m_axi_awlen;
	output wire [2:0] m_axi_awsize;
	output wire [1:0] m_axi_awburst;
	output wire m_axi_awlock;
	output wire [3:0] m_axi_awcache;
	output wire [2:0] m_axi_awprot;
	output wire m_axi_awvalid;
	input wire m_axi_awready;
	output wire [DATA_W - 1:0] m_axi_wdata;
	output wire [(DATA_W / 8) - 1:0] m_axi_wstrb;
	output wire m_axi_wlast;
	output wire m_axi_wvalid;
	input wire m_axi_wready;
	input wire [3:0] m_axi_bid;
	input wire [1:0] m_axi_bresp;
	input wire m_axi_bvalid;
	output wire m_axi_bready;
	output wire [3:0] m_axi_arid;
	output wire [31:0] m_axi_araddr;
	output wire [7:0] m_axi_arlen;
	output wire [2:0] m_axi_arsize;
	output wire [1:0] m_axi_arburst;
	output wire m_axi_arlock;
	output wire [3:0] m_axi_arcache;
	output wire [2:0] m_axi_arprot;
	output wire m_axi_arvalid;
	input wire m_axi_arready;
	input wire [3:0] m_axi_rid;
	input wire [DATA_W - 1:0] m_axi_rdata;
	input wire [1:0] m_axi_rresp;
	input wire m_axi_rlast;
	input wire m_axi_rvalid;
	output wire m_axi_rready;
	output wire protocol_fault;
	output wire busy;
	output reg [31:0] accepted_count;
	output reg [31:0] completed_count;
	output reg [31:0] burst_count;
	localparam signed [31:0] BYTES = DATA_W / 8;
	localparam signed [31:0] LG = $clog2(BYTES);
	localparam signed [31:0] CW = $clog2(MAX_BEATS + 1);
	localparam signed [31:0] IW = (MAX_BEATS < 2 ? 1 : $clog2(MAX_BEATS));
	localparam signed [31:0] RW = (DATA_W + TAG_W) + 2;
	localparam signed [31:0] QW = ((33 + DATA_W) + BYTES) + TAG_W;
	localparam [32:0] LIMIT = {1'b0, DDR_BASE} + DDR_BYTES;
	reg [3:0] state;
	reg [31:0] base_q;
	reg write_q;
	reg aw_sent_q;
	reg b_error_q;
	reg [CW - 1:0] count_q;
	reg [CW - 1:0] read_index_q;
	reg [CW - 1:0] write_index_q;
	reg [CW - 1:0] ack_index_q;
	reg [7:0] gap_q;
	reg [DATA_W - 1:0] data_q [0:MAX_BEATS - 1];
	reg [BYTES - 1:0] strb_q [0:MAX_BEATS - 1];
	reg [TAG_W - 1:0] tag_q [0:MAX_BEATS - 1];
	wire legal_req;
	wire joins_req;
	wire req_fire;
	wire collect_fire;
	wire aw_fire;
	wire w_fire;
	wire r_fire;
	wire b_fire;
	wire seal;
	wire req_fifo_in_ready;
	wire req_fifo_out_valid;
	wire req_fifo_out_ready;
	wire [QW - 1:0] req_fifo_out_data;
	wire [CW - 1:0] req_fifo_level;
	wire collect_write;
	wire [31:0] collect_addr;
	wire [DATA_W - 1:0] collect_wdata;
	wire [BYTES - 1:0] collect_wstrb;
	wire [TAG_W - 1:0] collect_tag;
	wire r_malformed;
	reg fifo_in_valid;
	wire fifo_in_ready;
	reg [RW - 1:0] fifo_in_data;
	wire [RW - 1:0] fifo_out_data;
	wire [CW - 1:0] fifo_level;
	pg_sync_fifo #(
		.WIDTH(QW),
		.DEPTH(MAX_BEATS)
	) pending_requests(
		.clk(clk),
		.rst(rst),
		.in_valid(s_req_valid && !protocol_fault),
		.in_ready(req_fifo_in_ready),
		.in_data({s_req_write, s_req_addr, s_req_wdata, s_req_wstrb, s_req_tag}),
		.out_valid(req_fifo_out_valid),
		.out_ready(req_fifo_out_ready),
		.out_data(req_fifo_out_data),
		.level(req_fifo_level)
	);
	assign {collect_write, collect_addr, collect_wdata, collect_wstrb, collect_tag} = req_fifo_out_data;
	function automatic signed [32:0] sv2v_cast_33_signed;
		input reg signed [32:0] inp;
		sv2v_cast_33_signed = inp;
	endfunction
	assign legal_req = ((collect_addr[LG - 1:0] == {LG * 1 {1'sb0}}) && ({1'b0, collect_addr} >= {1'b0, DDR_BASE})) && (({1'b0, collect_addr} + sv2v_cast_33_signed(BYTES)) <= LIMIT);
	function automatic [32:0] sv2v_cast_33;
		input reg [32:0] inp;
		sv2v_cast_33 = inp;
	endfunction
	assign joins_req = (count_q == 0) || (((legal_req && (collect_write == write_q)) && ({1'b0, collect_addr} == ({1'b0, base_q} + (sv2v_cast_33(count_q) << LG)))) && (collect_addr[31:12] == base_q[31:12]));
	function automatic signed [CW - 1:0] sv2v_cast_3D2D3_signed;
		input reg signed [CW - 1:0] inp;
		sv2v_cast_3D2D3_signed = inp;
	endfunction
	assign req_fifo_out_ready = ((!rst && (state == 4'd0)) && (count_q < sv2v_cast_3D2D3_signed(MAX_BEATS))) && joins_req;
	assign s_req_ready = (!rst && !protocol_fault) && req_fifo_in_ready;
	assign req_fire = s_req_valid && s_req_ready;
	assign collect_fire = req_fifo_out_valid && req_fifo_out_ready;
	function automatic signed [7:0] sv2v_cast_8_signed;
		input reg signed [7:0] inp;
		sv2v_cast_8_signed = inp;
	endfunction
	assign seal = (((state == 4'd0) && (count_q != 0)) && !collect_fire) && ((req_fifo_out_valid && !joins_req) || (gap_q >= sv2v_cast_8_signed(FLUSH_CYCLES - 1)));
	assign protocol_fault = state == 4'd8;
	assign busy = (((state != 4'd0) || (count_q != 0)) || (req_fifo_level != 0)) || (fifo_level != 0);
	assign m_axi_awid = 1'sb0;
	assign m_axi_awaddr = base_q;
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	assign m_axi_awlen = (count_q != 0 ? sv2v_cast_8(count_q - 1'b1) : 8'd0);
	function automatic signed [2:0] sv2v_cast_3_signed;
		input reg signed [2:0] inp;
		sv2v_cast_3_signed = inp;
	endfunction
	assign m_axi_awsize = sv2v_cast_3_signed(LG);
	assign m_axi_awburst = 2'b01;
	assign m_axi_awlock = 1'b0;
	assign m_axi_awcache = 4'b0000;
	assign m_axi_awprot = 3'b000;
	assign m_axi_awvalid = (!rst && (state == 4'd3)) && !aw_sent_q;
	assign m_axi_wvalid = (!rst && (state == 4'd3)) && (write_index_q < count_q);
	function automatic [IW - 1:0] sv2v_cast_83959;
		input reg [IW - 1:0] inp;
		sv2v_cast_83959 = inp;
	endfunction
	assign m_axi_wdata = (m_axi_wvalid ? data_q[sv2v_cast_83959(write_index_q)] : {DATA_W {1'sb0}});
	assign m_axi_wstrb = (m_axi_wvalid ? strb_q[sv2v_cast_83959(write_index_q)] : {DATA_W / 8 {1'sb0}});
	assign m_axi_wlast = (write_index_q + 1'b1) == count_q;
	assign m_axi_bready = !rst && (state == 4'd4);
	assign m_axi_arid = 1'sb0;
	assign m_axi_araddr = base_q;
	assign m_axi_arlen = m_axi_awlen;
	assign m_axi_arsize = sv2v_cast_3_signed(LG);
	assign m_axi_arburst = 2'b01;
	assign m_axi_arlock = 1'b0;
	assign m_axi_arcache = 4'b0000;
	assign m_axi_arprot = 3'b000;
	assign m_axi_arvalid = !rst && (state == 4'd1);
	assign m_axi_rready = (!rst && (state == 4'd2)) && fifo_in_ready;
	assign aw_fire = m_axi_awvalid && m_axi_awready;
	assign w_fire = m_axi_wvalid && m_axi_wready;
	assign r_fire = m_axi_rvalid && m_axi_rready;
	assign b_fire = m_axi_bvalid && m_axi_bready;
	assign r_malformed = (m_axi_rid != 0) || (m_axi_rlast != ((read_index_q + 1'b1) == count_q));
	always @(*) begin
		if (_sv2v_0)
			;
		fifo_in_valid = 1'b0;
		fifo_in_data = 1'sb0;
		case (state)
			4'd2: begin
				fifo_in_valid = m_axi_rvalid;
				fifo_in_data = {(m_axi_rresp != 0) || r_malformed, 1'b0, tag_q[sv2v_cast_83959(read_index_q)], ((m_axi_rresp != 0) || r_malformed ? {DATA_W {1'b0}} : m_axi_rdata)};
			end
			4'd5: begin
				fifo_in_valid = 1'b1;
				fifo_in_data = {b_error_q, 1'b1, tag_q[sv2v_cast_83959(ack_index_q)], {DATA_W {1'b0}}};
			end
			4'd6: begin
				fifo_in_valid = 1'b1;
				fifo_in_data = {1'b1, write_q, tag_q[0], {DATA_W {1'b0}}};
			end
			default:
				;
		endcase
	end
	pg_sync_fifo #(
		.WIDTH(RW),
		.DEPTH(MAX_BEATS)
	) responses(
		.clk(clk),
		.rst(rst),
		.in_valid(fifo_in_valid),
		.in_ready(fifo_in_ready),
		.in_data(fifo_in_data),
		.out_valid(s_rsp_valid),
		.out_ready(s_rsp_ready),
		.out_data(fifo_out_data),
		.level(fifo_level)
	);
	assign {s_rsp_error, s_rsp_write, s_rsp_tag, s_rsp_rdata} = fifo_out_data;
	initial begin
		if (((DATA_W != 32) && (DATA_W != 64)) && (DATA_W != 128)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/pg_ddr_burst_bridge.sv:467:48 - pg_ddr_burst_bridge_serial.<unnamed_block>.<unnamed_block>\n msg: ", $time, "PG_DDR_DATA_WIDTH_RED");
			$finish(1);
		end
		if (((((TAG_W < 1) || (MAX_BEATS < 1)) || (MAX_BEATS > 16)) || (FLUSH_CYCLES < 1)) || (FLUSH_CYCLES > 255)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/pg_ddr_burst_bridge.sv:469:13 - pg_ddr_burst_bridge_serial.<unnamed_block>.<unnamed_block>\n msg: ", $time, "PG_DDR_PARAMETER_RED");
			$finish(1);
		end
		if ((((DDR_BYTES == 0) || (LIMIT > 33'h100000000)) || ((DDR_BASE % BYTES) != 0)) || ((DDR_BYTES % sv2v_cast_33_signed(BYTES)) != 0)) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/pg_ddr_burst_bridge.sv:471:13 - pg_ddr_burst_bridge_serial.<unnamed_block>.<unnamed_block>\n msg: ", $time, "PG_DDR_APERTURE_RED");
			$finish(1);
		end
	end
	always @(posedge clk)
		if (rst) begin
			state <= 4'd0;
			base_q <= 1'sb0;
			write_q <= 0;
			aw_sent_q <= 0;
			b_error_q <= 0;
			count_q <= 1'sb0;
			read_index_q <= 1'sb0;
			write_index_q <= 1'sb0;
			ack_index_q <= 1'sb0;
			gap_q <= 0;
			accepted_count <= 0;
			completed_count <= 0;
			burst_count <= 0;
		end
		else begin
			if (req_fire)
				accepted_count <= accepted_count + 1'b1;
			if (s_rsp_valid && s_rsp_ready)
				completed_count <= completed_count + 1'b1;
			case (state)
				4'd0:
					if (collect_fire) begin
						tag_q[sv2v_cast_83959(count_q)] <= collect_tag;
						data_q[sv2v_cast_83959(count_q)] <= collect_wdata;
						strb_q[sv2v_cast_83959(count_q)] <= collect_wstrb;
						count_q <= count_q + 1'b1;
						gap_q <= 0;
						if (count_q == 0) begin
							base_q <= collect_addr;
							write_q <= collect_write;
						end
						if ((count_q == 0) && !legal_req)
							state <= 4'd6;
						else if (count_q == sv2v_cast_3D2D3_signed(MAX_BEATS - 1)) begin
							state <= (collect_write ? 4'd3 : 4'd1);
							read_index_q <= 0;
							write_index_q <= 0;
							ack_index_q <= 0;
							aw_sent_q <= 0;
							burst_count <= burst_count + 1'b1;
						end
					end
					else if (count_q != 0) begin
						if (seal) begin
							state <= (write_q ? 4'd3 : 4'd1);
							read_index_q <= 0;
							write_index_q <= 0;
							ack_index_q <= 0;
							aw_sent_q <= 0;
							burst_count <= burst_count + 1'b1;
						end
						else
							gap_q <= gap_q + 1'b1;
					end
				4'd1:
					if (m_axi_arvalid && m_axi_arready)
						state <= 4'd2;
				4'd2:
					if (r_fire) begin
						read_index_q <= read_index_q + 1'b1;
						if (r_malformed)
							state <= 4'd8;
						else if ((read_index_q + 1'b1) == count_q)
							state <= 4'd7;
					end
				4'd3: begin
					if (aw_fire)
						aw_sent_q <= 1;
					if (w_fire)
						write_index_q <= write_index_q + 1'b1;
					if ((aw_sent_q || aw_fire) && ((write_index_q == count_q) || (w_fire && m_axi_wlast)))
						state <= 4'd4;
				end
				4'd4:
					if (b_fire) begin
						if (m_axi_bid != 0)
							state <= 4'd8;
						else begin
							b_error_q <= m_axi_bresp != 0;
							ack_index_q <= 0;
							state <= 4'd5;
						end
					end
				4'd5:
					if (fifo_in_ready) begin
						ack_index_q <= ack_index_q + 1'b1;
						if ((ack_index_q + 1'b1) == count_q)
							state <= 4'd7;
					end
				4'd6:
					if (fifo_in_ready)
						state <= 4'd7;
				4'd7: begin
					count_q <= 0;
					gap_q <= 0;
					state <= 4'd0;
				end
				4'd8:
					;
				default: state <= 4'd8;
			endcase
		end
	initial _sv2v_0 = 0;
endmodule
module pg_npu_mmio_bridge (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	legacy_addr,
	legacy_wdata,
	legacy_wen,
	legacy_mask,
	legacy_rdata
);
	reg _sv2v_0;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	output wire [31:0] legacy_addr;
	output wire [31:0] legacy_wdata;
	output wire legacy_wen;
	output wire [1:0] legacy_mask;
	input wire [31:0] legacy_rdata;
	reg [2:0] state;
	reg [31:0] addr_q;
	reg [31:0] data_q;
	reg [31:0] rdata_q;
	reg [1:0] mask_q;
	reg write_q;
	reg pulse_q;
	reg error_q;
	reg access_error;
	reg write_pulse;
	reg [31:0] converted_data;
	reg [1:0] converted_mask;
	always @(*) begin
		if (_sv2v_0)
			;
		access_error = req_addr[15:8] != 0;
		write_pulse = req_write && (req_wstrb != 0);
		converted_data = 0;
		converted_mask = 0;
		if (write_pulse) begin
			if (req_wstrb == (4'b0001 << req_addr[1:0])) begin
				converted_mask = 0;
				converted_data = req_wdata >> (8 * req_addr[1:0]);
			end
			else if (!req_addr[0] && (req_wstrb == (4'b0011 << req_addr[1:0]))) begin
				converted_mask = 1;
				converted_data = req_wdata >> (8 * req_addr[1:0]);
			end
			else if ((req_addr[1:0] == 0) && (req_wstrb == 4'b1111)) begin
				converted_mask = 2;
				converted_data = req_wdata;
			end
			else
				access_error = 1;
		end
	end
	assign req_ready = !rst && (state == 3'd0);
	assign rsp_valid = !rst && (state == 3'd4);
	assign rsp_rdata = rdata_q;
	assign rsp_error = error_q;
	assign legacy_addr = addr_q;
	assign legacy_wdata = data_q;
	assign legacy_mask = mask_q;
	assign legacy_wen = (!rst && (state == 3'd1)) && pulse_q;
	always @(posedge clk)
		if (rst) begin
			state <= 3'd0;
			addr_q <= 0;
			data_q <= 0;
			rdata_q <= 0;
			mask_q <= 0;
			write_q <= 0;
			pulse_q <= 0;
			error_q <= 0;
		end
		else
			case (state)
				3'd0:
					if (req_valid) begin
						addr_q <= 32'h80200200 + {24'd0, req_addr[7:0]};
						data_q <= converted_data;
						mask_q <= converted_mask;
						write_q <= req_write;
						pulse_q <= write_pulse && !access_error;
						error_q <= access_error;
						rdata_q <= 0;
						state <= (access_error ? 3'd4 : 3'd1);
					end
				3'd1: state <= 3'd2;
				3'd2: state <= 3'd3;
				3'd3: begin
					rdata_q <= (write_q ? 32'd0 : legacy_rdata);
					state <= 3'd4;
				end
				3'd4:
					if (rsp_ready)
						state <= 3'd0;
				default: begin
					state <= 3'd4;
					error_q <= 1;
					rdata_q <= 0;
					pulse_q <= 0;
				end
			endcase
	initial _sv2v_0 = 0;
endmodule
module pg_sync_fifo (
	clk,
	rst,
	in_valid,
	in_ready,
	in_data,
	out_valid,
	out_ready,
	out_data,
	level
);
	parameter signed [31:0] WIDTH = 32;
	parameter signed [31:0] DEPTH = 16;
	input wire clk;
	input wire rst;
	input wire in_valid;
	output wire in_ready;
	input wire [WIDTH - 1:0] in_data;
	output wire out_valid;
	input wire out_ready;
	output wire [WIDTH - 1:0] out_data;
	output reg [$clog2(DEPTH + 1) - 1:0] level;
	localparam signed [31:0] CW = $clog2(DEPTH + 1);
	localparam signed [31:0] PW = (DEPTH < 2 ? 1 : $clog2(DEPTH));
	reg [PW - 1:0] rp;
	reg [PW - 1:0] wp;
	reg [WIDTH - 1:0] data [0:DEPTH - 1];
	wire push;
	wire pop;
	function automatic signed [CW - 1:0] sv2v_cast_3D2D3_signed;
		input reg signed [CW - 1:0] inp;
		sv2v_cast_3D2D3_signed = inp;
	endfunction
	assign in_ready = !rst && (level < sv2v_cast_3D2D3_signed(DEPTH));
	assign out_valid = !rst && (level != 0);
	assign out_data = (out_valid ? data[rp] : {WIDTH {1'sb0}});
	assign push = in_valid && in_ready;
	assign pop = out_valid && out_ready;
	function automatic signed [PW - 1:0] sv2v_cast_D1740_signed;
		input reg signed [PW - 1:0] inp;
		sv2v_cast_D1740_signed = inp;
	endfunction
	function automatic [PW - 1:0] inc;
		input reg [PW - 1:0] p;
		inc = (p == sv2v_cast_D1740_signed(DEPTH - 1) ? {PW {1'sb0}} : p + 1'b1);
	endfunction
	initial if ((WIDTH < 1) || (DEPTH < 1)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/interconnect/pg_sync_fifo.sv:23:34 - pg_sync_fifo.<unnamed_block>\n msg: ", $time, "PG_FIFO_PARAMETER_RED");
		$finish(1);
	end
	always @(posedge clk)
		if (rst) begin
			rp <= 1'sb0;
			wp <= 1'sb0;
			level <= 1'sb0;
		end
		else begin
			case ({push, pop})
				2'b10: level <= level + 1'b1;
				2'b01: level <= level - 1'b1;
				default:
					;
			endcase
			if (push) begin
				data[wp] <= in_data;
				wp <= inc(wp);
			end
			if (pop)
				rp <= inc(rp);
		end
endmodule
module pg_three_request_mux (
	clk,
	rst,
	req_valid,
	req_ready,
	req_write,
	req_addr,
	req_wdata,
	req_wstrb,
	req_id,
	rsp_valid,
	rsp_ready,
	rsp_write,
	rsp_error,
	rsp_rdata,
	rsp_id,
	m_req_valid,
	m_req_ready,
	m_req_write,
	m_req_addr,
	m_req_wdata,
	m_req_wstrb,
	m_req_tag,
	m_rsp_valid,
	m_rsp_ready,
	m_rsp_write,
	m_rsp_error,
	m_rsp_rdata,
	m_rsp_tag,
	protocol_fault
);
	reg _sv2v_0;
	input wire clk;
	input wire rst;
	input wire [2:0] req_valid;
	output wire [2:0] req_ready;
	input wire [2:0] req_write;
	input wire [95:0] req_addr;
	input wire [383:0] req_wdata;
	input wire [47:0] req_wstrb;
	input wire [11:0] req_id;
	output wire [2:0] rsp_valid;
	input wire [2:0] rsp_ready;
	output wire [2:0] rsp_write;
	output wire [2:0] rsp_error;
	output wire [383:0] rsp_rdata;
	output wire [11:0] rsp_id;
	output wire m_req_valid;
	input wire m_req_ready;
	output wire m_req_write;
	output wire [31:0] m_req_addr;
	output wire [127:0] m_req_wdata;
	output wire [15:0] m_req_wstrb;
	output wire [5:0] m_req_tag;
	input wire m_rsp_valid;
	output reg m_rsp_ready;
	input wire m_rsp_write;
	input wire m_rsp_error;
	input wire [127:0] m_rsp_rdata;
	input wire [5:0] m_rsp_tag;
	output reg protocol_fault;
	localparam integer PW = 181;
	localparam integer RW = 134;
	wire [2:0] qi_ready;
	wire [2:0] qo_valid;
	reg [2:0] qo_ready;
	wire [2:0] ri_ready;
	wire [2:0] ro_valid;
	wire [(3 * PW) - 1:0] qo_data;
	wire [(3 * RW) - 1:0] ro_data;
	wire [5:0] unused_request_level;
	wire [14:0] unused_response_level;
	reg [47:0] live;
	reg [47:0] issued;
	reg [47:0] returned;
	reg [47:0] write_kind;
	reg [1:0] turn;
	reg [1:0] locked_owner;
	reg [1:0] selected;
	wire [1:0] response_owner;
	reg locked;
	reg found;
	reg response_legal;
	integer idx;
	assign response_owner = m_rsp_tag[5:4];
	always @(*) begin
		if (_sv2v_0)
			;
		response_legal = 0;
		if (response_owner < 3)
			response_legal = ((live[(response_owner * 16) + m_rsp_tag[3:0]] && issued[(response_owner * 16) + m_rsp_tag[3:0]]) && !returned[(response_owner * 16) + m_rsp_tag[3:0]]) && (write_kind[(response_owner * 16) + m_rsp_tag[3:0]] == m_rsp_write);
	end
	genvar _gv_g_1;
	function automatic signed [1:0] sv2v_cast_2_signed;
		input reg signed [1:0] inp;
		sv2v_cast_2_signed = inp;
	endfunction
	generate
		for (_gv_g_1 = 0; _gv_g_1 < 3; _gv_g_1 = _gv_g_1 + 1) begin : queues
			localparam g = _gv_g_1;
			assign req_ready[g] = (!protocol_fault && qi_ready[g]) && !live[(g * 16) + req_id[g * 4+:4]];
			pg_sync_fifo #(
				.WIDTH(PW),
				.DEPTH(2)
			) requests(
				.clk(clk),
				.rst(rst),
				.in_valid((req_valid[g] && !protocol_fault) && !live[(g * 16) + req_id[g * 4+:4]]),
				.in_ready(qi_ready[g]),
				.in_data({req_write[g], req_addr[g * 32+:32], req_wdata[g * 128+:128], req_wstrb[g * 16+:16], req_id[g * 4+:4]}),
				.out_valid(qo_valid[g]),
				.out_ready(qo_ready[g]),
				.out_data(qo_data[g * PW+:PW]),
				.level(unused_request_level[g * 2+:2])
			);
			pg_sync_fifo #(
				.WIDTH(RW),
				.DEPTH(16)
			) responses(
				.clk(clk),
				.rst(rst),
				.in_valid(((m_rsp_valid && response_legal) && !protocol_fault) && (response_owner == sv2v_cast_2_signed(g))),
				.in_ready(ri_ready[g]),
				.in_data({m_rsp_error, m_rsp_write, m_rsp_tag[3:0], m_rsp_rdata}),
				.out_valid(ro_valid[g]),
				.out_ready(rsp_ready[g] && !protocol_fault),
				.out_data(ro_data[g * RW+:RW]),
				.level(unused_response_level[g * 5+:5])
			);
			assign rsp_valid[g] = ro_valid[g] && !protocol_fault;
			assign {rsp_error[g], rsp_write[g], rsp_id[g * 4+:4], rsp_rdata[g * 128+:128]} = ro_data[g * RW+:RW];
		end
	endgenerate
	reg [2:0] cp9_rr_grant;
	wire [2:0] cp9_data_grant;
	always @(*) begin
		if (_sv2v_0)
			;
		case (turn)
			2'd1: cp9_rr_grant = {qo_valid[2] && !qo_valid[1], qo_valid[1], (qo_valid[0] && !qo_valid[1]) && !qo_valid[2]};
			2'd2: cp9_rr_grant = {qo_valid[2], (qo_valid[1] && !qo_valid[2]) && !qo_valid[0], qo_valid[0] && !qo_valid[2]};
			default: cp9_rr_grant = {(qo_valid[2] && !qo_valid[0]) && !qo_valid[1], qo_valid[1] && !qo_valid[0], qo_valid[0]};
		endcase
		selected = turn;
		found = |qo_valid;
		idx = 0;
		if (cp9_rr_grant[0])
			selected = 2'd0;
		else if (cp9_rr_grant[1])
			selected = 2'd1;
		else if (cp9_rr_grant[2])
			selected = 2'd2;
		if (locked)
			selected = locked_owner;
	end
	assign cp9_data_grant = (locked ? {locked_owner == 2'd2, locked_owner == 2'd1, locked_owner == 2'd0} : cp9_rr_grant);
	wire [PW - 1:0] cp9_selected_data;
	assign cp9_selected_data = (({PW {cp9_data_grant[0]}} & qo_data[0+:PW]) | ({PW {cp9_data_grant[1]}} & qo_data[PW+:PW])) | ({PW {cp9_data_grant[2]}} & qo_data[2 * PW+:PW]);
	assign m_req_valid = (!rst && !protocol_fault) && (locked ? qo_valid[locked_owner] : |qo_valid);
	assign {m_req_write, m_req_addr, m_req_wdata, m_req_wstrb, m_req_tag[3:0]} = cp9_selected_data;
	assign m_req_tag[5:4] = selected;
	always @(*) begin
		if (_sv2v_0)
			;
		qo_ready = 0;
		qo_ready[selected] = m_req_valid && m_req_ready;
		m_rsp_ready = !rst;
		if (!protocol_fault && response_legal)
			m_rsp_ready = !rst && ri_ready[response_owner];
	end
	always @(posedge clk)
		if (rst) begin
			turn <= 0;
			locked_owner <= 0;
			locked <= 0;
			protocol_fault <= 0;
			live <= 0;
			issued <= 0;
			returned <= 0;
			write_kind <= 0;
		end
		else begin
			if (m_req_valid) begin
				if (m_req_ready) begin
					turn <= (selected == 2 ? 2'd0 : selected + 1'b1);
					locked <= 0;
					issued[(selected * 16) + m_req_tag[3:0]] <= 1;
				end
				else begin
					locked <= 1;
					locked_owner <= selected;
				end
			end
			if ((m_rsp_valid && m_rsp_ready) && !protocol_fault) begin
				if (!response_legal)
					protocol_fault <= 1;
				else
					returned[(response_owner * 16) + m_rsp_tag[3:0]] <= 1;
			end
			begin : sv2v_autoblock_1
				integer g;
				for (g = 0; g < 3; g = g + 1)
					begin
						if (req_valid[g] && req_ready[g]) begin
							live[(g * 16) + req_id[g * 4+:4]] <= 1;
							write_kind[(g * 16) + req_id[g * 4+:4]] <= req_write[g];
						end
						if (rsp_valid[g] && rsp_ready[g]) begin
							live[(g * 16) + rsp_id[g * 4+:4]] <= 0;
							issued[(g * 16) + rsp_id[g * 4+:4]] <= 0;
							returned[(g * 16) + rsp_id[g * 4+:4]] <= 0;
						end
					end
			end
		end
	initial _sv2v_0 = 0;
endmodule
module soc_peripherals (
	clk,
	rst,
	req_valid,
	req_write,
	req_is_fetch,
	req_addr,
	req_wdata,
	req_wstrb,
	req_ready,
	rsp_valid,
	rsp_error,
	rsp_rdata,
	rsp_ready,
	gpio_in,
	gpio_out,
	diagnostic_mailbox,
	uart_tx,
	uart_rx,
	uart_aux_tx,
	timer_gray
);
	reg _sv2v_0;
	parameter integer CLK_FREQ = 170000000;
	parameter integer BAUD_RATE = 115200;
	input wire clk;
	input wire rst;
	input wire req_valid;
	input wire req_write;
	input wire req_is_fetch;
	input wire [31:0] req_addr;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output wire req_ready;
	output wire rsp_valid;
	output wire rsp_error;
	output wire [31:0] rsp_rdata;
	input wire rsp_ready;
	input wire [31:0] gpio_in;
	output wire [31:0] gpio_out;
	output wire [31:0] diagnostic_mailbox;
	output wire uart_tx;
	input wire uart_rx;
	output wire uart_aux_tx;
	output wire [63:0] timer_gray;
	wire legacy_ready;
	wire legacy_valid;
	wire legacy_error;
	wire pg_ready;
	wire pg_valid;
	wire pg_error;
	wire [31:0] legacy_data;
	wire [31:0] pg_data;
	reg [31:0] pg_addr;
	wire select_pg;
	wire alias_gpio;
	reg busy;
	assign alias_gpio = req_addr[31:12] == 20'h50000;
	assign select_pg = alias_gpio || (req_addr[31:12] == 20'h60000);
	always @(*) begin
		if (_sv2v_0)
			;
		pg_addr = {20'h30000, req_addr[11:0]};
		if (alias_gpio)
			case (req_addr[11:0])
				12'h000: pg_addr = 32'h30000010;
				12'h004: pg_addr = 32'h30000014;
				12'h0fc: pg_addr = 32'h300000fc;
				default: pg_addr = 32'h30000ffc;
			endcase
	end
	assign req_ready = (!rst && !busy) && (select_pg ? pg_ready : legacy_ready);
	assign rsp_valid = !rst && (pg_valid || legacy_valid);
	assign rsp_rdata = (pg_valid ? pg_data : legacy_data);
	assign rsp_error = (pg_valid ? pg_error : legacy_error);
	core0_system_fabric #(
		.CLK_FREQ(CLK_FREQ),
		.BAUD_RATE(BAUD_RATE)
	) legacy(
		.clk(clk),
		.rst(rst),
		.req_valid((req_valid && !busy) && !select_pg),
		.req_ready(legacy_ready),
		.req_addr(req_addr),
		.req_write(req_write),
		.req_wdata(req_wdata),
		.req_wstrb(req_wstrb),
		.req_is_fetch(req_is_fetch),
		.rsp_valid(legacy_valid),
		.rsp_ready(rsp_ready && !pg_valid),
		.rsp_rdata(legacy_data),
		.rsp_error(legacy_error),
		.uart_tx(uart_tx)
	);
	pg_cpu_peripherals #(
		.CLOCK_HZ(CLK_FREQ),
		.UART_CLKS_PER_BIT((CLK_FREQ + (BAUD_RATE / 2)) / BAUD_RATE),
		.UART_RX_DEPTH(128)
	) cp13(
		.clk(clk),
		.rst(rst),
		.req_valid((req_valid && !busy) && select_pg),
		.req_ready(pg_ready),
		.req_addr(pg_addr),
		.req_write(req_write),
		.req_wdata(req_wdata),
		.req_wstrb(req_wstrb),
		.req_is_fetch(req_is_fetch),
		.rsp_valid(pg_valid),
		.rsp_ready(rsp_ready && !legacy_valid),
		.rsp_rdata(pg_data),
		.rsp_error(pg_error),
		.gpio_in(gpio_in),
		.gpio_out(gpio_out),
		.diagnostic_mailbox(diagnostic_mailbox),
		.uart_rx(uart_rx),
		.uart_tx(uart_aux_tx),
		.timer_gray(timer_gray)
	);
	always @(posedge clk)
		if (rst)
			busy <= 0;
		else begin
			if (rsp_valid && rsp_ready)
				busy <= 0;
			if (req_valid && req_ready)
				busy <= 1;
		end
	initial _sv2v_0 = 0;
endmodule
module core0_cycle_timer (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error
);
	parameter [31:0] BASE_ADDR = 32'h30000000;
	parameter [31:0] SPAN_BYTES = 32'h00001000;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	reg [31:0] counter_q;
	reg [31:0] rsp_data_q;
	reg pending_q;
	reg rsp_valid_q;
	reg rsp_error_q;
	wire window_hit;
	wire req_accept;
	assign window_hit = (req_addr >= BASE_ADDR) && (req_addr < (BASE_ADDR + SPAN_BYTES));
	assign req_ready = (!rst && !pending_q) && !rsp_valid_q;
	assign req_accept = req_valid && req_ready;
	assign rsp_valid = !rst && rsp_valid_q;
	assign rsp_rdata = (rsp_valid && !rsp_error_q ? rsp_data_q : 32'd0);
	assign rsp_error = rsp_valid && rsp_error_q;
	always @(posedge clk)
		if (rst)
			counter_q <= 32'd0;
		else
			counter_q <= counter_q + 32'd1;
	always @(posedge clk)
		if (rst) begin
			pending_q <= 1'b0;
			rsp_valid_q <= 1'b0;
			rsp_error_q <= 1'b0;
			rsp_data_q <= 32'd0;
		end
		else begin
			if (rsp_valid_q && rsp_ready) begin
				rsp_valid_q <= 1'b0;
				rsp_error_q <= 1'b0;
			end
			if (pending_q) begin
				pending_q <= 1'b0;
				rsp_valid_q <= 1'b1;
			end
			if (req_accept) begin
				pending_q <= 1'b1;
				rsp_data_q <= counter_q;
				rsp_error_q <= !window_hit || req_write;
			end
		end
endmodule
module core0_uart_mmio (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	uart_tx
);
	reg _sv2v_0;
	parameter [31:0] BASE_ADDR = 32'h40000000;
	parameter [31:0] SPAN_BYTES = 32'h00001000;
	parameter [31:0] CLK_FREQ = 100000000;
	parameter [31:0] BAUD_RATE = 115200;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	output wire uart_tx;
	localparam [1:0] REG_TX = 2'd0;
	localparam [1:0] REG_STATUS = 2'd1;
	localparam [1:0] REG_RX = 2'd2;
	localparam [1:0] REG_CTRL = 2'd3;
	reg [31:0] rsp_data_q;
	reg [7:0] tx_byte;
	reg pending_q;
	reg rsp_valid_q;
	reg rsp_error_q;
	wire window_hit;
	wire select_tx;
	wire req_accept;
	wire tx_busy;
	wire tx_start;
	wire tx_write_waits;
	wire access_illegal;
	reg [31:0] read_data_mux;
	assign window_hit = (req_addr >= BASE_ADDR) && (req_addr < (BASE_ADDR + SPAN_BYTES));
	assign select_tx = window_hit && (req_addr[3:2] == REG_TX);
	assign tx_write_waits = (select_tx && req_write) && tx_busy;
	assign req_ready = ((!rst && !pending_q) && !rsp_valid_q) && !tx_write_waits;
	assign req_accept = req_valid && req_ready;
	assign rsp_valid = !rst && rsp_valid_q;
	assign rsp_rdata = (rsp_valid && !rsp_error_q ? rsp_data_q : 32'd0);
	assign rsp_error = rsp_valid && rsp_error_q;
	assign tx_start = (req_accept && !access_illegal) && select_tx;
	assign access_illegal = !window_hit || (req_write && (req_addr[3:2] != REG_TX));
	always @(*) begin
		if (_sv2v_0)
			;
		case (req_wstrb)
			4'b0001: tx_byte = req_wdata[7:0];
			4'b0010: tx_byte = req_wdata[15:8];
			4'b0100: tx_byte = req_wdata[23:16];
			4'b1000: tx_byte = req_wdata[31:24];
			default: tx_byte = req_wdata[7:0];
		endcase
	end
	always @(*) begin
		if (_sv2v_0)
			;
		case (req_addr[3:2])
			REG_STATUS: read_data_mux = {31'b0000000000000000000000000000000, tx_busy};
			REG_RX: read_data_mux = 32'd0;
			REG_CTRL: read_data_mux = 32'h00000001;
			default: read_data_mux = 32'd0;
		endcase
	end
	core0_uart_tx #(
		.CLK_FREQ(CLK_FREQ),
		.BAUD_RATE(BAUD_RATE)
	) tx_unit(
		.clk(clk),
		.rst(rst),
		.tx_data(tx_byte),
		.tx_start(tx_start),
		.tx_busy(tx_busy),
		.tx(uart_tx)
	);
	always @(posedge clk)
		if (rst) begin
			pending_q <= 1'b0;
			rsp_valid_q <= 1'b0;
			rsp_error_q <= 1'b0;
			rsp_data_q <= 32'd0;
		end
		else begin
			if (rsp_valid_q && rsp_ready) begin
				rsp_valid_q <= 1'b0;
				rsp_error_q <= 1'b0;
			end
			if (pending_q) begin
				pending_q <= 1'b0;
				rsp_valid_q <= 1'b1;
			end
			if (req_accept) begin
				pending_q <= 1'b1;
				rsp_data_q <= read_data_mux;
				rsp_error_q <= access_illegal;
			end
		end
	initial _sv2v_0 = 0;
endmodule
module core0_uart_tx (
	clk,
	rst,
	tx_data,
	tx_start,
	tx_busy,
	tx
);
	parameter [31:0] CLK_FREQ = 100000000;
	parameter [31:0] BAUD_RATE = 115200;
	input wire clk;
	input wire rst;
	input wire [7:0] tx_data;
	input wire tx_start;
	output reg tx_busy;
	output reg tx;
	localparam [31:0] BAUD_DIV = (CLK_FREQ + (BAUD_RATE / 2)) / BAUD_RATE;
	localparam [0:0] IDLE = 1'b0;
	localparam [0:0] SEND = 1'b1;
	reg state_q;
	reg [15:0] baud_count_q;
	reg [3:0] bit_index_q;
	reg [9:0] shift_q;
	wire baud_tick = baud_count_q == (BAUD_DIV - 1);
	always @(posedge clk)
		if (rst) begin
			state_q <= IDLE;
			baud_count_q <= 16'd0;
			bit_index_q <= 4'd0;
			shift_q <= 10'h3ff;
			tx_busy <= 1'b0;
			tx <= 1'b1;
		end
		else
			case (state_q)
				IDLE: begin
					tx_busy <= 1'b0;
					tx <= 1'b1;
					if (tx_start) begin
						shift_q <= {1'b1, tx_data, 1'b0};
						baud_count_q <= 16'd0;
						bit_index_q <= 4'd0;
						tx_busy <= 1'b1;
						state_q <= SEND;
					end
				end
				SEND:
					if (baud_tick) begin
						baud_count_q <= 16'd0;
						tx <= shift_q[0];
						shift_q <= {1'b1, shift_q[9:1]};
						if (bit_index_q == 4'd9)
							state_q <= IDLE;
						else
							bit_index_q <= bit_index_q + 4'd1;
					end
					else
						baud_count_q <= baud_count_q + 16'd1;
				default: state_q <= IDLE;
			endcase
endmodule
module soc_soc_top (
	cpu_clk,
	npu_clk,
	mem_clk,
	arst,
	mem_ready,
	cpu_reset,
	npu_reset,
	mem_reset,
	irq_nmi_fault,
	irq_fast_adc,
	irq_fast_pwm,
	irq_qei,
	irq_timer,
	irq_ipc,
	irq_platform,
	gpio_in,
	gpio_out,
	diagnostic_mailbox,
	uart_tx,
	uart_rx,
	uart_aux_tx,
	timer_gray,
	board_req_valid,
	board_req_ready,
	board_req_addr,
	board_req_wdata,
	board_req_write,
	board_req_is_fetch,
	board_req_wstrb,
	board_rsp_valid,
	board_rsp_ready,
	board_rsp_rdata,
	board_rsp_error,
	gex_win_req_valid,
	gex_win_req_ready,
	gex_win_req_addr,
	gex_win_req_write,
	gex_win_req_wdata,
	gex_win_req_wstrb,
	gex_win_rsp_valid,
	gex_win_rsp_ready,
	gex_win_rsp_rdata,
	gex_win_rsp_error,
	gex_locked_out,
	cache_hit_count,
	cache_miss_count,
	cache_bypass_count,
	maintenance_count,
	routing_protocol_fault,
	ddr_protocol_fault,
	ddr_accepted,
	ddr_completed,
	ddr_bursts,
	core_sleeping,
	retire_valid_diag,
	retire_pc_diag,
	irq_accept_diag,
	irq_vector_pc_diag,
	handler_entry_diag,
	fatal_state_diag,
	m_axi_awid,
	m_axi_awaddr,
	m_axi_awlen,
	m_axi_awsize,
	m_axi_awburst,
	m_axi_awlock,
	m_axi_awcache,
	m_axi_awprot,
	m_axi_awvalid,
	m_axi_awready,
	m_axi_wdata,
	m_axi_wstrb,
	m_axi_wlast,
	m_axi_wvalid,
	m_axi_wready,
	m_axi_bid,
	m_axi_bresp,
	m_axi_bvalid,
	m_axi_bready,
	m_axi_arid,
	m_axi_araddr,
	m_axi_arlen,
	m_axi_arsize,
	m_axi_arburst,
	m_axi_arlock,
	m_axi_arcache,
	m_axi_arprot,
	m_axi_arvalid,
	m_axi_arready,
	m_axi_rid,
	m_axi_rdata,
	m_axi_rresp,
	m_axi_rlast,
	m_axi_rvalid,
	m_axi_rready
);
	parameter integer CACHE_CAPACITY_BYTES = 16384;
	parameter integer CPU_CLOCK_HZ = 175000000;
	parameter integer UART_BAUD = 115200;
	parameter integer NPU_ROWS = 16;
	parameter integer NPU_COLS = 8;
	parameter integer NPU_K_TILE = 64;
	parameter integer NPU_OUTSTANDING = 16;
	parameter integer DMA_TIMEOUT_CYCLES = 65536;
	parameter integer CDC_ADDR_BITS = 4;
	parameter integer DDR_MAX_BEATS = 16;
	parameter [0:0] NPU_ORDERED_RETURN = 1'b1;
	parameter [0:0] NPU_A_PREFETCH = 1'b1;
	parameter integer NPU_RESULT_CHUNK_COLUMNS = 32;
	parameter [0:0] BOARD_MMIO_ENABLE = 0;
	parameter [0:0] GRAPH_EXECUTOR_ENABLE = BOARD_MMIO_ENABLE;
	parameter integer BTB_INDEX_BITS = 8;
	parameter integer DTCM_READ_LATENCY = 1;
	parameter [0:0] REGISTERED_AGU = 1;
	parameter [0:0] LOAD_BRANCH_BYPASS = 1;
	parameter [0:0] MDU_WB_ONLY = 1;
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [31:0] CACHE_BASE = 32'h84000000;
	parameter [32:0] DDR_BYTES = 33'h010000000;
	parameter [32:0] CACHE_BYTES = 33'h004000000;
	parameter ITCM_INIT_FILE = "coremark-itcm.mem";
	parameter DTCM_INIT_FILE = "coremark-dtcm.mem";
	input wire cpu_clk;
	input wire npu_clk;
	input wire mem_clk;
	input wire arst;
	input wire mem_ready;
	output wire cpu_reset;
	output wire npu_reset;
	output wire mem_reset;
	input wire irq_nmi_fault;
	input wire irq_fast_adc;
	input wire irq_fast_pwm;
	input wire irq_qei;
	input wire irq_timer;
	input wire irq_ipc;
	input wire [7:0] irq_platform;
	input wire [31:0] gpio_in;
	output wire [31:0] gpio_out;
	output wire [31:0] diagnostic_mailbox;
	output wire uart_tx;
	input wire uart_rx;
	output wire uart_aux_tx;
	output wire [63:0] timer_gray;
	output wire board_req_valid;
	input wire board_req_ready;
	output wire [31:0] board_req_addr;
	output wire [31:0] board_req_wdata;
	output wire board_req_write;
	output wire board_req_is_fetch;
	output wire [3:0] board_req_wstrb;
	input wire board_rsp_valid;
	output wire board_rsp_ready;
	input wire [31:0] board_rsp_rdata;
	input wire board_rsp_error;
	output wire gex_win_req_valid;
	input wire gex_win_req_ready;
	output wire [15:0] gex_win_req_addr;
	output wire gex_win_req_write;
	output wire [31:0] gex_win_req_wdata;
	output wire [3:0] gex_win_req_wstrb;
	input wire gex_win_rsp_valid;
	output wire gex_win_rsp_ready;
	input wire [31:0] gex_win_rsp_rdata;
	input wire gex_win_rsp_error;
	output wire gex_locked_out;
	output wire [63:0] cache_hit_count;
	output wire [63:0] cache_miss_count;
	output wire [63:0] cache_bypass_count;
	output wire [31:0] maintenance_count;
	output wire routing_protocol_fault;
	output wire ddr_protocol_fault;
	output wire [31:0] ddr_accepted;
	output wire [31:0] ddr_completed;
	output wire [31:0] ddr_bursts;
	output wire core_sleeping;
	output wire retire_valid_diag;
	output wire [31:0] retire_pc_diag;
	output wire irq_accept_diag;
	output wire [31:0] irq_vector_pc_diag;
	output wire handler_entry_diag;
	output wire fatal_state_diag;
	output wire [3:0] m_axi_awid;
	output wire [31:0] m_axi_awaddr;
	output wire [7:0] m_axi_awlen;
	output wire [2:0] m_axi_awsize;
	output wire [1:0] m_axi_awburst;
	output wire m_axi_awlock;
	output wire [3:0] m_axi_awcache;
	output wire [2:0] m_axi_awprot;
	output wire m_axi_awvalid;
	input wire m_axi_awready;
	output wire [127:0] m_axi_wdata;
	output wire [15:0] m_axi_wstrb;
	output wire m_axi_wlast;
	output wire m_axi_wvalid;
	input wire m_axi_wready;
	input wire [3:0] m_axi_bid;
	input wire [1:0] m_axi_bresp;
	input wire m_axi_bvalid;
	output wire m_axi_bready;
	output wire [3:0] m_axi_arid;
	output wire [31:0] m_axi_araddr;
	output wire [7:0] m_axi_arlen;
	output wire [2:0] m_axi_arsize;
	output wire [1:0] m_axi_arburst;
	output wire m_axi_arlock;
	output wire [3:0] m_axi_arcache;
	output wire [2:0] m_axi_arprot;
	output wire m_axi_arvalid;
	input wire m_axi_arready;
	input wire [3:0] m_axi_rid;
	input wire [127:0] m_axi_rdata;
	input wire [1:0] m_axi_rresp;
	input wire m_axi_rlast;
	input wire m_axi_rvalid;
	output wire m_axi_rready;
	wire cpu_rst;
	wire npu_rst;
	wire mem_rst;
	soc_reset_sync cpu_reset_sync(
		.clk(cpu_clk),
		.arst(arst),
		.rst(cpu_rst)
	);
	soc_reset_sync npu_reset_sync(
		.clk(npu_clk),
		.arst(arst),
		.rst(npu_rst)
	);
	soc_reset_sync mem_reset_sync(
		.clk(mem_clk),
		.arst(arst),
		.rst(mem_rst)
	);
	assign cpu_reset = cpu_rst;
	assign npu_reset = npu_rst;
	assign mem_reset = mem_rst;
	wire cpu_req_valid;
	wire cpu_req_ready;
	wire cpu_req_write;
	wire cpu_req_fetch;
	wire cpu_rsp_valid;
	wire cpu_rsp_ready;
	wire cpu_rsp_error;
	wire [31:0] cpu_req_addr;
	wire [31:0] cpu_req_wdata;
	wire [31:0] cpu_rsp_rdata;
	wire [3:0] cpu_req_wstrb;
	wire n_req_valid;
	wire n_req_ready;
	wire n_req_write;
	wire n_rsp_valid;
	wire n_rsp_ready;
	wire n_rsp_error;
	wire [15:0] n_req_addr;
	wire [31:0] n_req_wdata;
	wire [31:0] n_rsp_rdata;
	wire [3:0] n_req_wstrb;
	wire f_req_valid;
	wire f_req_ready;
	wire f_req_write;
	wire f_rsp_valid;
	wire f_rsp_ready;
	wire f_rsp_error;
	wire [15:0] f_req_addr;
	wire [31:0] f_req_wdata;
	wire [31:0] f_rsp_rdata;
	wire [3:0] f_req_wstrb;
	wire cb_req_valid;
	wire cb_req_ready;
	wire cb_req_write;
	wire cb_req_is_fetch;
	wire cb_rsp_valid;
	wire cb_rsp_ready;
	wire cb_rsp_error;
	wire [31:0] cb_req_addr;
	wire [31:0] cb_req_wdata;
	wire [31:0] cb_rsp_rdata;
	wire [3:0] cb_req_wstrb;
	wire graph_busy;
	wire graph_poison;
	wire graph_input_consumed;
	wire nn_req_valid;
	wire nn_req_ready;
	wire nn_req_write;
	wire nn_rsp_valid;
	wire nn_rsp_ready;
	wire nn_rsp_error;
	wire [15:0] nn_req_addr;
	wire [31:0] nn_req_wdata;
	wire [31:0] nn_rsp_rdata;
	wire [3:0] nn_req_wstrb;
	wire n_irq;
	wire n_irq_cpu;
	wire mem_fault_cpu;
	wire [31:0] legacy_addr;
	wire [31:0] legacy_data;
	wire [31:0] legacy_rdata;
	wire legacy_wen;
	wire [1:0] legacy_mask;
	wire [2:0] cv;
	wire [2:0] cr;
	wire [2:0] cw;
	wire [2:0] csv;
	wire [2:0] csr;
	wire [2:0] csw;
	wire [2:0] cse;
	wire [2:0] mv;
	wire [2:0] mr;
	wire [2:0] mw;
	wire [2:0] msv;
	wire [2:0] msr;
	wire [2:0] msw;
	wire [2:0] mse;
	wire [95:0] ca;
	wire [95:0] ma;
	wire [383:0] cd;
	wire [383:0] csd;
	wire [383:0] md;
	wire [383:0] msd;
	wire [47:0] cstrb;
	wire [47:0] mstrb;
	wire [11:0] ci;
	wire [11:0] csi;
	wire [11:0] mi;
	wire [11:0] msi;
	wire bv;
	wire br;
	wire bw;
	wire bsv;
	wire bsr;
	wire bsw;
	wire bse;
	wire [31:0] ba;
	wire [127:0] bd;
	wire [127:0] bsd;
	wire [15:0] bstrb;
	wire [5:0] bi;
	wire [5:0] bsi;
	wire cpu_protocol_fault;
	wire mux_protocol_fault;
	wire ddr_busy;
	wire n_irq_registered;
	wire mem_fault_registered;
	wire ddr_fault_registered;
	wire ddr_fault_local;
	wire gex_locked;
	pg_source_level_register irq_source(
		.clk(npu_clk),
		.rst(npu_rst),
		.level_in(n_irq && !gex_locked),
		.level_out(n_irq_registered)
	);
	pg_source_level_register memory_fault_source(
		.clk(mem_clk),
		.rst(mem_rst),
		.level_in(mux_protocol_fault),
		.level_out(mem_fault_registered)
	);
	pg_source_level_register ddr_fault_source(
		.clk(mem_clk),
		.rst(mem_rst),
		.level_in(ddr_fault_local),
		.level_out(ddr_fault_registered)
	);
	pg_level_sync irq_sync(
		.clk(cpu_clk),
		.rst(cpu_rst),
		.async_level(n_irq_registered),
		.level(n_irq_cpu)
	);
	pg_level_sync memory_fault_sync(
		.clk(cpu_clk),
		.rst(cpu_rst),
		.async_level(mem_fault_registered),
		.level(mem_fault_cpu)
	);
	pg_level_sync ddr_fault_sync(
		.clk(cpu_clk),
		.rst(cpu_rst),
		.async_level(ddr_fault_registered),
		.level(ddr_protocol_fault)
	);
	assign routing_protocol_fault = (cpu_protocol_fault | mem_fault_cpu) | ddr_protocol_fault;
	initial begin
		if ((CACHE_BASE <= DDR_BASE) || (({1'b0, CACHE_BASE} + CACHE_BYTES) > ({1'b0, DDR_BASE} + DDR_BYTES))) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/soc_soc_top.sv:110:4 - soc_soc_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "SOC_ADDRESS_RANGE");
			$finish(1);
		end
		if (CDC_ADDR_BITS < 2) begin
			$display("Fatal [%0t] F:/Codex/G25/optimization_store/after_conversion/soc_soc_top.sv:111:23 - soc_soc_top.<unnamed_block>.<unnamed_block>\n msg: ", $time, "SOC_CDC_DEPTH");
			$finish(1);
		end
	end
	soc_cpu_tile_v15 #(
		.BTB_INDEX_BITS(BTB_INDEX_BITS),
		.REGISTERED_AGU(REGISTERED_AGU),
		.LOAD_BRANCH_BYPASS(LOAD_BRANCH_BYPASS),
		.MDU_WB_ONLY(MDU_WB_ONLY),
		.DTCM_READ_LATENCY(DTCM_READ_LATENCY),
		.EARLY_STORE_ACK(1'b1),
		.CACHE_CAPACITY_BYTES(CACHE_CAPACITY_BYTES),
		.DDR_BASE(DDR_BASE),
		.DDR_BYTES(DDR_BYTES),
		.CACHE_BASE(CACHE_BASE),
		.CACHE_BYTES(CACHE_BYTES),
		.NPU_ENABLE(1'b1),
		.ITCM_INIT_FILE(ITCM_INIT_FILE),
		.DTCM_INIT_FILE(DTCM_INIT_FILE)
	) cpu(
		.clk(cpu_clk),
		.rst(cpu_rst),
		.system_req_valid(cpu_req_valid),
		.system_req_ready(cpu_req_ready),
		.system_req_addr(cpu_req_addr),
		.system_req_write(cpu_req_write),
		.system_req_wdata(cpu_req_wdata),
		.system_req_wstrb(cpu_req_wstrb),
		.system_req_is_fetch(cpu_req_fetch),
		.system_rsp_valid(cpu_rsp_valid),
		.system_rsp_ready(cpu_rsp_ready),
		.system_rsp_rdata(cpu_rsp_rdata),
		.system_rsp_error(cpu_rsp_error),
		.npu_req_valid(n_req_valid),
		.npu_req_ready(n_req_ready),
		.npu_req_addr(n_req_addr),
		.npu_req_write(n_req_write),
		.npu_req_wdata(n_req_wdata),
		.npu_req_wstrb(n_req_wstrb),
		.npu_rsp_valid(n_rsp_valid),
		.npu_rsp_ready(n_rsp_ready),
		.npu_rsp_rdata(n_rsp_rdata),
		.npu_rsp_error(n_rsp_error),
		.npu_irq(n_irq_cpu),
		.cache_mem_req_valid(cv[1:0]),
		.cache_mem_req_ready(cr[1:0]),
		.cache_mem_req_write(cw[1:0]),
		.cache_mem_req_addr(ca[0+:64]),
		.cache_mem_req_wdata(cd[0+:256]),
		.cache_mem_req_wstrb(cstrb[0+:32]),
		.cache_mem_req_tag(ci[0+:8]),
		.cache_mem_rsp_valid(csv[1:0]),
		.cache_mem_rsp_ready(csr[1:0]),
		.cache_mem_rsp_write(csw[1:0]),
		.cache_mem_rsp_rdata(csd[0+:256]),
		.cache_mem_rsp_tag(csi[0+:8]),
		.cache_mem_rsp_error(cse[1:0]),
		.cache_protocol_fault(cpu_protocol_fault),
		.cache_hit_count(cache_hit_count),
		.cache_miss_count(cache_miss_count),
		.cache_bypass_count(cache_bypass_count),
		.maintenance_count(maintenance_count),
		.irq_nmi_fault(irq_nmi_fault | routing_protocol_fault),
		.irq_fast_adc(irq_fast_adc),
		.irq_fast_pwm(irq_fast_pwm),
		.irq_qei(irq_qei),
		.irq_timer(irq_timer),
		.irq_ipc(irq_ipc),
		.irq_platform(irq_platform),
		.core_sleeping(core_sleeping),
		.retire_valid_diag(retire_valid_diag),
		.retire_pc_diag(retire_pc_diag),
		.irq_accept_diag(irq_accept_diag),
		.irq_vector_pc_diag(irq_vector_pc_diag),
		.handler_entry_diag(handler_entry_diag),
		.fatal_state_diag(fatal_state_diag)
	);
	wire p_req_valid;
	wire p_req_ready;
	wire p_rsp_valid;
	wire p_rsp_ready;
	wire p_rsp_error;
	wire [31:0] p_rsp_rdata;
	generate
		if (BOARD_MMIO_ENABLE) begin : board_window
			wire [1:0] rv;
			wire [1:0] rr;
			wire [1:0] sv;
			wire [1:0] sr;
			wire [1:0] se;
			wire [63:0] sd;
			assign {cb_req_valid, p_req_valid} = rv;
			assign rr = {cb_req_ready, p_req_ready};
			assign sv = {cb_rsp_valid, p_rsp_valid};
			assign {cb_rsp_ready, p_rsp_ready} = sr;
			assign sd = {cb_rsp_rdata, p_rsp_rdata};
			assign se = {cb_rsp_error, p_rsp_error};
			soc_board_mmio_router router(
				.clk(cpu_clk),
				.rst(cpu_rst),
				.req_valid(cpu_req_valid),
				.req_ready(cpu_req_ready),
				.req_addr(cpu_req_addr),
				.req_write(cpu_req_write),
				.req_is_fetch(cpu_req_fetch),
				.req_wdata(cpu_req_wdata),
				.req_wstrb(cpu_req_wstrb),
				.rsp_valid(cpu_rsp_valid),
				.rsp_ready(cpu_rsp_ready),
				.rsp_rdata(cpu_rsp_rdata),
				.rsp_error(cpu_rsp_error),
				.m_req_valid(rv),
				.m_req_ready(rr),
				.m_req_addr(cb_req_addr),
				.m_req_wdata(cb_req_wdata),
				.m_req_write(cb_req_write),
				.m_req_is_fetch(cb_req_is_fetch),
				.m_req_wstrb(cb_req_wstrb),
				.m_rsp_valid(sv),
				.m_rsp_ready(sr),
				.m_rsp_rdata(sd),
				.m_rsp_error(se)
			);
		end
		else begin : no_board_window
			assign p_req_valid = cpu_req_valid;
			assign cpu_req_ready = p_req_ready;
			assign cpu_rsp_valid = p_rsp_valid;
			assign p_rsp_ready = cpu_rsp_ready;
			assign cpu_rsp_rdata = p_rsp_rdata;
			assign cpu_rsp_error = p_rsp_error;
			assign cb_req_valid = 0;
			assign cb_req_addr = 0;
			assign cb_req_wdata = 0;
			assign cb_req_write = 0;
			assign cb_req_is_fetch = 0;
			assign cb_req_wstrb = 0;
			assign cb_rsp_ready = 0;
		end
	endgenerate
	soc_peripherals #(
		.CLK_FREQ(CPU_CLOCK_HZ),
		.BAUD_RATE(UART_BAUD)
	) peripherals(
		.clk(cpu_clk),
		.rst(cpu_rst),
		.req_valid(p_req_valid),
		.req_ready(p_req_ready),
		.req_addr(cpu_req_addr),
		.req_write(cpu_req_write),
		.req_is_fetch(cpu_req_fetch),
		.req_wdata(cpu_req_wdata),
		.req_wstrb(cpu_req_wstrb),
		.rsp_valid(p_rsp_valid),
		.rsp_ready(p_rsp_ready),
		.rsp_rdata(p_rsp_rdata),
		.rsp_error(p_rsp_error),
		.gpio_in(gpio_in),
		.gpio_out(gpio_out),
		.diagnostic_mailbox(diagnostic_mailbox),
		.uart_tx(uart_tx),
		.uart_rx(uart_rx),
		.uart_aux_tx(uart_aux_tx),
		.timer_gray(timer_gray)
	);
	generate
		if (GRAPH_EXECUTOR_ENABLE) begin : graph_fabric
			soc_graph_mmio_fabric fabric(
				.clk(cpu_clk),
				.rst(cpu_rst),
				.cn_req_valid(n_req_valid),
				.cn_req_ready(n_req_ready),
				.cn_req_addr(n_req_addr),
				.cn_req_write(n_req_write),
				.cn_req_wdata(n_req_wdata),
				.cn_req_wstrb(n_req_wstrb),
				.cn_rsp_valid(n_rsp_valid),
				.cn_rsp_ready(n_rsp_ready),
				.cn_rsp_rdata(n_rsp_rdata),
				.cn_rsp_error(n_rsp_error),
				.n_req_valid(f_req_valid),
				.n_req_ready(f_req_ready),
				.n_req_addr(f_req_addr),
				.n_req_write(f_req_write),
				.n_req_wdata(f_req_wdata),
				.n_req_wstrb(f_req_wstrb),
				.n_rsp_valid(f_rsp_valid),
				.n_rsp_ready(f_rsp_ready),
				.n_rsp_rdata(f_rsp_rdata),
				.n_rsp_error(f_rsp_error),
				.cb_req_valid(cb_req_valid),
				.cb_req_ready(cb_req_ready),
				.cb_req_addr(cb_req_addr),
				.cb_req_wdata(cb_req_wdata),
				.cb_req_write(cb_req_write),
				.cb_req_fetch(cb_req_is_fetch),
				.cb_req_wstrb(cb_req_wstrb),
				.cb_rsp_valid(cb_rsp_valid),
				.cb_rsp_ready(cb_rsp_ready),
				.cb_rsp_rdata(cb_rsp_rdata),
				.cb_rsp_error(cb_rsp_error),
				.b_req_valid(board_req_valid),
				.b_req_ready(board_req_ready),
				.b_req_addr(board_req_addr),
				.b_req_wdata(board_req_wdata),
				.b_req_write(board_req_write),
				.b_req_fetch(board_req_is_fetch),
				.b_req_wstrb(board_req_wstrb),
				.b_rsp_valid(board_rsp_valid),
				.b_rsp_ready(board_rsp_ready),
				.b_rsp_rdata(board_rsp_rdata),
				.b_rsp_error(board_rsp_error),
				.graph_busy(graph_busy),
				.graph_poison(graph_poison),
				.graph_input_consumed(graph_input_consumed)
			);
		end
		else begin : no_graph_fabric
			assign f_req_valid = n_req_valid;
			assign n_req_ready = f_req_ready;
			assign f_req_addr = n_req_addr;
			assign f_req_write = n_req_write;
			assign f_req_wdata = n_req_wdata;
			assign f_req_wstrb = n_req_wstrb;
			assign n_rsp_valid = f_rsp_valid;
			assign f_rsp_ready = n_rsp_ready;
			assign n_rsp_rdata = f_rsp_rdata;
			assign n_rsp_error = f_rsp_error;
			assign board_req_valid = cb_req_valid;
			assign cb_req_ready = board_req_ready;
			assign board_req_addr = cb_req_addr;
			assign board_req_write = cb_req_write;
			assign board_req_wdata = cb_req_wdata;
			assign board_req_wstrb = cb_req_wstrb;
			assign board_req_is_fetch = cb_req_is_fetch;
			assign cb_rsp_valid = board_rsp_valid;
			assign board_rsp_ready = cb_rsp_ready;
			assign cb_rsp_rdata = board_rsp_rdata;
			assign cb_rsp_error = board_rsp_error;
			assign graph_busy = 0;
			assign graph_poison = 0;
			assign graph_input_consumed = 0;
		end
	endgenerate
	pg_mmio_cdc npu_mmio_cdc(
		.src_clk(cpu_clk),
		.dst_clk(npu_clk),
		.arst(arst),
		.s_req_valid(f_req_valid),
		.s_req_ready(f_req_ready),
		.s_req_write(f_req_write),
		.s_req_addr(f_req_addr),
		.s_req_wdata(f_req_wdata),
		.s_req_wstrb(f_req_wstrb),
		.s_rsp_valid(f_rsp_valid),
		.s_rsp_ready(f_rsp_ready),
		.s_rsp_rdata(f_rsp_rdata),
		.s_rsp_error(f_rsp_error),
		.m_req_valid(nn_req_valid),
		.m_req_ready(nn_req_ready),
		.m_req_write(nn_req_write),
		.m_req_addr(nn_req_addr),
		.m_req_wdata(nn_req_wdata),
		.m_req_wstrb(nn_req_wstrb),
		.m_rsp_valid(nn_rsp_valid),
		.m_rsp_ready(nn_rsp_ready),
		.m_rsp_rdata(nn_rsp_rdata),
		.m_rsp_error(nn_rsp_error)
	);
	wire old_req_ready;
	wire old_rsp_valid;
	wire old_rsp_error;
	wire service_req_ready;
	wire service_rsp_valid;
	wire service_rsp_error;
	wire [31:0] old_rsp_data;
	wire [31:0] service_rsp_data;
	wire [31:0] cpu_legacy_addr;
	wire [31:0] cpu_legacy_data;
	wire [31:0] gex_legacy_addr;
	wire [31:0] gex_legacy_data;
	wire cpu_legacy_wen;
	wire gex_legacy_wen;
	wire [1:0] cpu_legacy_mask;
	wire [1:0] gex_legacy_mask;
	wire gex_poison;
	wire npu_exclusive_idle;
	reg busy_reject_valid;
	reg [1:0] npu_response_owner;
	wire select_service = nn_req_addr[15:8] == 8'h01;
	assign nn_req_ready = (select_service ? service_req_ready : (gex_locked ? !busy_reject_valid : old_req_ready));
	assign nn_rsp_valid = (npu_response_owner == 1 ? service_rsp_valid : (npu_response_owner == 2 ? busy_reject_valid : old_rsp_valid));
	assign nn_rsp_rdata = (npu_response_owner == 1 ? service_rsp_data : (npu_response_owner == 2 ? 32'd0 : old_rsp_data));
	assign nn_rsp_error = (npu_response_owner == 1 ? service_rsp_error : (npu_response_owner == 2 ? 1'b1 : old_rsp_error));
	assign legacy_addr = (gex_locked ? gex_legacy_addr : cpu_legacy_addr);
	assign legacy_data = (gex_locked ? gex_legacy_data : cpu_legacy_data);
	assign legacy_wen = (gex_locked ? gex_legacy_wen : cpu_legacy_wen);
	assign legacy_mask = (gex_locked ? gex_legacy_mask : cpu_legacy_mask);
	assign gex_locked_out = gex_locked;
	always @(posedge npu_clk)
		if (npu_rst) begin
			npu_response_owner <= 0;
			busy_reject_valid <= 0;
		end
		else begin
			if ((busy_reject_valid && nn_rsp_ready) && (npu_response_owner == 2))
				busy_reject_valid <= 0;
			if (nn_req_valid && nn_req_ready) begin
				npu_response_owner <= (select_service ? 2'd1 : (gex_locked ? 2'd2 : 2'd0));
				if (!select_service && gex_locked)
					busy_reject_valid <= 1;
			end
		end
	wire resident_enable;
	wire [31:0] resident_model_epoch;
	wire [31:0] resident_frame_epoch;
	wire [31:0] resident_task_generation;
	wire [31:0] resident_a_generation;
	wire [31:0] resident_b_base;
	wire [4:0] resident_next_a_rows;
	wire [8:0] resident_b_columns;
	wire [4:0] resident_b_group;
	soc_conv_service conv_service(
		.clk(npu_clk),
		.rst(npu_rst),
		.can_start((npu_exclusive_idle && old_req_ready) && !cpu_legacy_wen),
		.req_valid(nn_req_valid && select_service),
		.req_ready(service_req_ready),
		.req_addr(nn_req_addr),
		.req_write(nn_req_write),
		.req_wdata(nn_req_wdata),
		.req_wstrb(nn_req_wstrb),
		.rsp_valid(service_rsp_valid),
		.rsp_ready(nn_rsp_ready && (npu_response_owner == 1)),
		.rsp_rdata(service_rsp_data),
		.rsp_error(service_rsp_error),
		.locked(gex_locked),
		.protocol_poison(gex_poison),
		.resident_enable(resident_enable),
		.resident_model_epoch(resident_model_epoch),
		.resident_frame_epoch(resident_frame_epoch),
		.resident_task_generation(resident_task_generation),
		.resident_a_generation(resident_a_generation),
		.resident_b_base(resident_b_base),
		.resident_b_columns(resident_b_columns),
		.resident_b_group(resident_b_group),
		.resident_next_a_rows(resident_next_a_rows),
		.legacy_addr(gex_legacy_addr),
		.legacy_wdata(gex_legacy_data),
		.legacy_wen(gex_legacy_wen),
		.legacy_mask(gex_legacy_mask),
		.legacy_rdata(legacy_rdata),
		.Window_req_valid(gex_win_req_valid),
		.Window_req_ready(gex_win_req_ready),
		.Window_req_addr(gex_win_req_addr),
		.Window_req_write(gex_win_req_write),
		.Window_req_wdata(gex_win_req_wdata),
		.Window_req_wstrb(gex_win_req_wstrb),
		.Window_rsp_valid(gex_win_rsp_valid),
		.Window_rsp_ready(gex_win_rsp_ready),
		.Window_rsp_rdata(gex_win_rsp_rdata),
		.Window_rsp_error(gex_win_rsp_error)
	);
	pg_npu_mmio_bridge npu_mmio(
		.clk(npu_clk),
		.rst(npu_rst),
		.req_valid((nn_req_valid && !select_service) && !gex_locked),
		.req_ready(old_req_ready),
		.req_addr(nn_req_addr),
		.req_write(nn_req_write),
		.req_wdata(nn_req_wdata),
		.req_wstrb(nn_req_wstrb),
		.rsp_valid(old_rsp_valid),
		.rsp_ready(nn_rsp_ready && (npu_response_owner == 0)),
		.rsp_rdata(old_rsp_data),
		.rsp_error(old_rsp_error),
		.legacy_addr(cpu_legacy_addr),
		.legacy_wdata(cpu_legacy_data),
		.legacy_wen(cpu_legacy_wen),
		.legacy_mask(cpu_legacy_mask),
		.legacy_rdata(legacy_rdata)
	);
	npu_accel_top #(
		.ARRAY_ROWS(NPU_ROWS),
		.ARRAY_COLS(NPU_COLS),
		.K_TILE(NPU_K_TILE),
		.ACC_W(48),
		.RESIDENT_RESULT_CHUNK_COLUMNS(NPU_RESULT_CHUNK_COLUMNS),
		.RESIDENT_A_PREFETCH(NPU_A_PREFETCH),
		.IN_ORDER_TRANSPORT(NPU_ORDERED_RETURN),
		.MEM_DATA_W(128),
		.MEM_ID_W(4),
		.MEM_OUTSTANDING(NPU_OUTSTANDING),
		.DMA_TIMEOUT_CYCLES(DMA_TIMEOUT_CYCLES),
		.MUL_PIPE_STAGES(2),
		.SPAD_LOAD_ELEMS(16),
		.A_PACKED_INT8_16(1'b1),
		.DRAM_BASE(DDR_BASE),
		.DRAM_BYTES({1'b0, CACHE_BASE} - {1'b0, DDR_BASE})
	) npu(
		.clk(npu_clk),
		.rst(npu_rst),
		.perip_addr(legacy_addr),
		.perip_wdata(legacy_data),
		.perip_wen(legacy_wen),
		.perip_mask(legacy_mask),
		.legacy_perip_rdata(32'd0),
		.combined_perip_rdata(legacy_rdata),
		.irq(n_irq),
		.exclusive_idle(npu_exclusive_idle),
		.resident_enable(resident_enable),
		.resident_model_epoch(resident_model_epoch),
		.resident_frame_epoch(resident_frame_epoch),
		.resident_task_generation(resident_task_generation),
		.resident_a_generation(resident_a_generation),
		.resident_b_base(resident_b_base),
		.resident_b_columns(resident_b_columns),
		.resident_b_group(resident_b_group),
		.resident_next_a_rows(resident_next_a_rows),
		.dma_req_valid(cv[2]),
		.dma_req_ready(cr[2]),
		.dma_req_write(cw[2]),
		.dma_req_addr(ca[64+:32]),
		.dma_req_wdata(cd[256+:128]),
		.dma_req_wstrb(cstrb[32+:16]),
		.dma_req_id(ci[8+:4]),
		.dma_rsp_valid(csv[2]),
		.dma_rsp_ready(csr[2]),
		.dma_rsp_write(csw[2]),
		.dma_rsp_id(csi[8+:4]),
		.dma_rsp_rdata(csd[256+:128]),
		.dma_rsp_error(cse[2])
	);
	genvar _gv_g_1;
	generate
		for (_gv_g_1 = 0; _gv_g_1 < 3; _gv_g_1 = _gv_g_1 + 1) begin : memory_cdc
			localparam g = _gv_g_1;
			wire source_clk = (g == 2 ? npu_clk : cpu_clk);
			wire source_rst = (g == 2 ? npu_rst : cpu_rst);
			pg_memory_cdc #(
				.DEPTH(1 << CDC_ADDR_BITS),
				.REGISTER_RSP_OUTPUT(g < 2)
			) channel(
				.src_clk(source_clk),
				.dst_clk(mem_clk),
				.arst(arst),
				.s_req_valid(cv[g]),
				.s_req_ready(cr[g]),
				.s_req_write(cw[g]),
				.s_req_addr(ca[g * 32+:32]),
				.s_req_wdata(cd[g * 128+:128]),
				.s_req_wstrb(cstrb[g * 16+:16]),
				.s_req_id(ci[g * 4+:4]),
				.s_rsp_valid(csv[g]),
				.s_rsp_ready(csr[g]),
				.s_rsp_write(csw[g]),
				.s_rsp_rdata(csd[g * 128+:128]),
				.s_rsp_id(csi[g * 4+:4]),
				.s_rsp_error(cse[g]),
				.m_req_valid(mv[g]),
				.m_req_ready(mr[g]),
				.m_req_write(mw[g]),
				.m_req_addr(ma[g * 32+:32]),
				.m_req_wdata(md[g * 128+:128]),
				.m_req_wstrb(mstrb[g * 16+:16]),
				.m_req_id(mi[g * 4+:4]),
				.m_rsp_valid(msv[g]),
				.m_rsp_ready(msr[g]),
				.m_rsp_write(msw[g]),
				.m_rsp_rdata(msd[g * 128+:128]),
				.m_rsp_id(msi[g * 4+:4]),
				.m_rsp_error(mse[g])
			);
		end
	endgenerate
	wire [2:0] mux_ready;
	assign mr = mux_ready & {3 {mem_ready}};
	pg_three_request_mux mux(
		.clk(mem_clk),
		.rst(mem_rst),
		.req_valid(mv & {3 {mem_ready}}),
		.req_ready(mux_ready),
		.req_write(mw),
		.req_addr(ma),
		.req_wdata(md),
		.req_wstrb(mstrb),
		.req_id(mi),
		.rsp_valid(msv),
		.rsp_ready(msr),
		.rsp_write(msw),
		.rsp_rdata(msd),
		.rsp_id(msi),
		.rsp_error(mse),
		.m_req_valid(bv),
		.m_req_ready(br),
		.m_req_write(bw),
		.m_req_addr(ba),
		.m_req_wdata(bd),
		.m_req_wstrb(bstrb),
		.m_req_tag(bi),
		.m_rsp_valid(bsv),
		.m_rsp_ready(bsr),
		.m_rsp_write(bsw),
		.m_rsp_rdata(bsd),
		.m_rsp_tag(bsi),
		.m_rsp_error(bse),
		.protocol_fault(mux_protocol_fault)
	);
	pg_ddr_burst_bridge #(
		.MAX_BEATS(DDR_MAX_BEATS),
		.TAG_W(6),
		.DDR_BASE(DDR_BASE),
		.DDR_BYTES(DDR_BYTES)
	) ddr_user_bridge(
		.clk(mem_clk),
		.rst(mem_rst),
		.s_req_valid(bv),
		.s_req_ready(br),
		.s_req_write(bw),
		.s_req_addr(ba),
		.s_req_wdata(bd),
		.s_req_wstrb(bstrb),
		.s_req_tag(bi),
		.s_rsp_valid(bsv),
		.s_rsp_ready(bsr),
		.s_rsp_write(bsw),
		.s_rsp_rdata(bsd),
		.s_rsp_tag(bsi),
		.s_rsp_error(bse),
		.protocol_fault(ddr_fault_local),
		.busy(ddr_busy),
		.accepted_count(ddr_accepted),
		.completed_count(ddr_completed),
		.burst_count(ddr_bursts),
		.m_axi_awid(m_axi_awid),
		.m_axi_awaddr(m_axi_awaddr),
		.m_axi_awlen(m_axi_awlen),
		.m_axi_awsize(m_axi_awsize),
		.m_axi_awburst(m_axi_awburst),
		.m_axi_awlock(m_axi_awlock),
		.m_axi_awcache(m_axi_awcache),
		.m_axi_awprot(m_axi_awprot),
		.m_axi_awvalid(m_axi_awvalid),
		.m_axi_awready(m_axi_awready),
		.m_axi_wdata(m_axi_wdata),
		.m_axi_wstrb(m_axi_wstrb),
		.m_axi_wlast(m_axi_wlast),
		.m_axi_wvalid(m_axi_wvalid),
		.m_axi_wready(m_axi_wready),
		.m_axi_bid(m_axi_bid),
		.m_axi_bresp(m_axi_bresp),
		.m_axi_bvalid(m_axi_bvalid),
		.m_axi_bready(m_axi_bready),
		.m_axi_arid(m_axi_arid),
		.m_axi_araddr(m_axi_araddr),
		.m_axi_arlen(m_axi_arlen),
		.m_axi_arsize(m_axi_arsize),
		.m_axi_arburst(m_axi_arburst),
		.m_axi_arlock(m_axi_arlock),
		.m_axi_arcache(m_axi_arcache),
		.m_axi_arprot(m_axi_arprot),
		.m_axi_arvalid(m_axi_arvalid),
		.m_axi_arready(m_axi_arready),
		.m_axi_rid(m_axi_rid),
		.m_axi_rdata(m_axi_rdata),
		.m_axi_rresp(m_axi_rresp),
		.m_axi_rlast(m_axi_rlast),
		.m_axi_rvalid(m_axi_rvalid),
		.m_axi_rready(m_axi_rready)
	);
endmodule
(* KEEP_HIERARCHY = "yes" *) module pg_async_fifo_dc (
	wr_clk,
	rd_clk,
	arst,
	in_valid,
	in_ready,
	in_data,
	out_valid,
	out_ready,
	out_data
);
	parameter signed [31:0] WIDTH = 8;
	parameter signed [31:0] DEPTH = 8;
	input wire wr_clk;
	input wire rd_clk;
	input wire arst;
	input wire in_valid;
	output wire in_ready;
	input wire [WIDTH - 1:0] in_data;
	output wire out_valid;
	input wire out_ready;
	output wire [WIDTH - 1:0] out_data;
	localparam signed [31:0] AW = (DEPTH > 1 ? $clog2(DEPTH) : 1);
	localparam signed [31:0] PW = AW + 1;
	wire wr_rst;
	wire rd_rst;
	pg_reset_sync wr_release(
		.clk(wr_clk),
		.arst(arst),
		.rst(wr_rst)
	);
	pg_reset_sync rd_release(
		.clk(rd_clk),
		.arst(arst),
		.rst(rd_rst)
	);
	reg [PW - 1:0] wbin_q;
	reg [PW - 1:0] rbin_q;
	reg [PW - 1:0] wgray_q;
	reg [PW - 1:0] rgray_q;
	wire [PW - 1:0] wbin_next;
	wire [PW - 1:0] rbin_next;
	wire [PW - 1:0] wgray_next;
	wire [PW - 1:0] rgray_next;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] rgray_wmeta_q;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] rgray_wsync_q;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] wgray_rmeta_q;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] wgray_rsync_q;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg rup_wmeta_q;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg rup_wsync_q;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg wup_rmeta_q;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg wup_rsync_q;
	reg wfull_q;
	reg rempty_q;
	wire wpush;
	wire rload;
	reg rvalid_q;
	reg [WIDTH - 1:0] rdata_q;
	(* ram_style = "distributed" *) reg [WIDTH - 1:0] memory [0:DEPTH - 1];
	wire [PW - 1:0] full_target;
	assign in_ready = (!wr_rst && rup_wsync_q) && !wfull_q;
	assign out_valid = (!rd_rst && wup_rsync_q) && rvalid_q;
	assign out_data = rdata_q;
	assign wpush = in_valid && in_ready;
	assign rload = ((!rd_rst && wup_rsync_q) && !rempty_q) && (!rvalid_q || out_ready);
	function automatic [PW - 1:0] sv2v_cast_D1740;
		input reg [PW - 1:0] inp;
		sv2v_cast_D1740 = inp;
	endfunction
	assign wbin_next = wbin_q + sv2v_cast_D1740(wpush);
	assign rbin_next = rbin_q + sv2v_cast_D1740(rload);
	assign wgray_next = (wbin_next >> 1) ^ wbin_next;
	assign rgray_next = (rbin_next >> 1) ^ rbin_next;
	function automatic signed [PW - 1:0] sv2v_cast_D1740_signed;
		input reg signed [PW - 1:0] inp;
		sv2v_cast_D1740_signed = inp;
	endfunction
	assign full_target = rgray_wsync_q ^ (sv2v_cast_D1740_signed(3) << (PW - 2));
	always @(posedge wr_clk or posedge wr_rst)
		if (wr_rst) begin
			wbin_q <= 0;
			wgray_q <= 0;
			wfull_q <= 0;
			rgray_wmeta_q <= 0;
			rgray_wsync_q <= 0;
			rup_wmeta_q <= 0;
			rup_wsync_q <= 0;
		end
		else begin
			rgray_wmeta_q <= rgray_q;
			rgray_wsync_q <= rgray_wmeta_q;
			rup_wmeta_q <= !rd_rst;
			rup_wsync_q <= rup_wmeta_q;
			wbin_q <= wbin_next;
			wgray_q <= wgray_next;
			wfull_q <= wgray_next == full_target;
		end
	always @(posedge rd_clk or posedge rd_rst)
		if (rd_rst) begin
			rbin_q <= 0;
			rgray_q <= 0;
			rempty_q <= 1;
			rvalid_q <= 0;
			wgray_rmeta_q <= 0;
			wgray_rsync_q <= 0;
			wup_rmeta_q <= 0;
			wup_rsync_q <= 0;
		end
		else begin
			wgray_rmeta_q <= wgray_q;
			wgray_rsync_q <= wgray_rmeta_q;
			wup_rmeta_q <= !wr_rst;
			wup_rsync_q <= wup_rmeta_q;
			rbin_q <= rbin_next;
			rgray_q <= rgray_next;
			rempty_q <= rgray_next == wgray_rsync_q;
			if (rload)
				rvalid_q <= 1;
			else if (out_valid && out_ready)
				rvalid_q <= 0;
		end
	always @(posedge wr_clk)
		if (wpush)
			memory[wbin_q[AW - 1:0]] <= in_data;
	always @(posedge rd_clk)
		if (rload)
			rdata_q <= memory[rbin_q[AW - 1:0]];
	initial if (((WIDTH < 1) || (DEPTH < 2)) || ((DEPTH & (DEPTH - 1)) != 0)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/cdc/pg_async_fifo_dc.sv:65:45 - pg_async_fifo_dc.<unnamed_block>.<unnamed_block>\n msg: ", $time, "CP6_ASYNC_FIFO_PARAMETER_RED");
		$finish(1);
	end
endmodule
module pg_level_sync (
	clk,
	rst,
	async_level,
	level
);
	input wire clk;
	input wire rst;
	input wire async_level;
	output wire level;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg meta_q;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg sync_q;
	always @(posedge clk or posedge rst)
		if (rst) begin
			meta_q <= 0;
			sync_q <= 0;
		end
		else begin
			meta_q <= async_level;
			sync_q <= meta_q;
		end
	assign level = sync_q;
endmodule
module pg_memory_cdc (
	src_clk,
	dst_clk,
	arst,
	s_req_valid,
	s_req_ready,
	s_req_write,
	s_req_addr,
	s_req_wdata,
	s_req_wstrb,
	s_req_id,
	s_rsp_valid,
	s_rsp_ready,
	s_rsp_write,
	s_rsp_error,
	s_rsp_rdata,
	s_rsp_id,
	m_req_valid,
	m_req_ready,
	m_req_write,
	m_req_addr,
	m_req_wdata,
	m_req_wstrb,
	m_req_id,
	m_rsp_valid,
	m_rsp_ready,
	m_rsp_write,
	m_rsp_error,
	m_rsp_rdata,
	m_rsp_id
);
	parameter signed [31:0] DATA_W = 128;
	parameter signed [31:0] ID_W = 4;
	parameter signed [31:0] DEPTH = 8;
	parameter [0:0] REGISTER_RSP_OUTPUT = 1'b0;
	input wire src_clk;
	input wire dst_clk;
	input wire arst;
	input wire s_req_valid;
	output wire s_req_ready;
	input wire s_req_write;
	input wire [31:0] s_req_addr;
	input wire [DATA_W - 1:0] s_req_wdata;
	input wire [(DATA_W / 8) - 1:0] s_req_wstrb;
	input wire [ID_W - 1:0] s_req_id;
	output wire s_rsp_valid;
	input wire s_rsp_ready;
	output wire s_rsp_write;
	output wire s_rsp_error;
	output wire [DATA_W - 1:0] s_rsp_rdata;
	output wire [ID_W - 1:0] s_rsp_id;
	output wire m_req_valid;
	input wire m_req_ready;
	output wire m_req_write;
	output wire [31:0] m_req_addr;
	output wire [DATA_W - 1:0] m_req_wdata;
	output wire [(DATA_W / 8) - 1:0] m_req_wstrb;
	output wire [ID_W - 1:0] m_req_id;
	input wire m_rsp_valid;
	output wire m_rsp_ready;
	input wire m_rsp_write;
	input wire m_rsp_error;
	input wire [DATA_W - 1:0] m_rsp_rdata;
	input wire [ID_W - 1:0] m_rsp_id;
	localparam signed [31:0] REQ_W = ((33 + DATA_W) + (DATA_W / 8)) + ID_W;
	localparam signed [31:0] RSP_W = (2 + DATA_W) + ID_W;
	wire rsp_fifo_valid;
	wire rsp_fifo_ready;
	wire [RSP_W - 1:0] rsp_fifo_data;
	pg_async_fifo_dc #(
		.WIDTH(REQ_W),
		.DEPTH(DEPTH)
	) req_fifo(
		.wr_clk(src_clk),
		.rd_clk(dst_clk),
		.arst(arst),
		.in_valid(s_req_valid),
		.in_ready(s_req_ready),
		.in_data({s_req_write, s_req_addr, s_req_wdata, s_req_wstrb, s_req_id}),
		.out_valid(m_req_valid),
		.out_ready(m_req_ready),
		.out_data({m_req_write, m_req_addr, m_req_wdata, m_req_wstrb, m_req_id})
	);
	pg_async_fifo_dc #(
		.WIDTH(RSP_W),
		.DEPTH(DEPTH)
	) rsp_fifo(
		.wr_clk(dst_clk),
		.rd_clk(src_clk),
		.arst(arst),
		.in_valid(m_rsp_valid),
		.in_ready(m_rsp_ready),
		.in_data({m_rsp_write, m_rsp_error, m_rsp_rdata, m_rsp_id}),
		.out_valid(rsp_fifo_valid),
		.out_ready(rsp_fifo_ready),
		.out_data(rsp_fifo_data)
	);
	generate
		if (REGISTER_RSP_OUTPUT) begin : g_registered_rsp
			reg pipe_valid_q;
			reg [RSP_W - 1:0] pipe_data_q;
			assign rsp_fifo_ready = !pipe_valid_q || s_rsp_ready;
			assign s_rsp_valid = pipe_valid_q;
			assign {s_rsp_write, s_rsp_error, s_rsp_rdata, s_rsp_id} = pipe_data_q;
			always @(posedge src_clk or posedge arst)
				if (arst) begin
					pipe_valid_q <= 1'b0;
					pipe_data_q <= 1'sb0;
				end
				else if (rsp_fifo_ready) begin
					pipe_valid_q <= rsp_fifo_valid;
					if (rsp_fifo_valid)
						pipe_data_q <= rsp_fifo_data;
				end
		end
		else begin : g_direct_rsp
			assign rsp_fifo_ready = s_rsp_ready;
			assign s_rsp_valid = rsp_fifo_valid;
			assign {s_rsp_write, s_rsp_error, s_rsp_rdata, s_rsp_id} = rsp_fifo_data;
		end
	endgenerate
	initial if (((DATA_W < 8) || ((DATA_W % 8) != 0)) || (ID_W < 1)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/cdc/pg_memory_cdc.sv:52:43 - pg_memory_cdc.<unnamed_block>\n msg: ", $time, "CP6_MEMORY_CDC_PARAM_RED");
		$finish(1);
	end
endmodule
module pg_mmio_cdc (
	src_clk,
	dst_clk,
	arst,
	s_req_valid,
	s_req_ready,
	s_req_addr,
	s_req_write,
	s_req_wdata,
	s_req_wstrb,
	s_rsp_valid,
	s_rsp_ready,
	s_rsp_rdata,
	s_rsp_error,
	m_req_valid,
	m_req_ready,
	m_req_addr,
	m_req_write,
	m_req_wdata,
	m_req_wstrb,
	m_rsp_valid,
	m_rsp_ready,
	m_rsp_rdata,
	m_rsp_error
);
	input wire src_clk;
	input wire dst_clk;
	input wire arst;
	input wire s_req_valid;
	output wire s_req_ready;
	input wire [15:0] s_req_addr;
	input wire s_req_write;
	input wire [31:0] s_req_wdata;
	input wire [3:0] s_req_wstrb;
	output wire s_rsp_valid;
	input wire s_rsp_ready;
	output wire [31:0] s_rsp_rdata;
	output wire s_rsp_error;
	output wire m_req_valid;
	input wire m_req_ready;
	output wire [15:0] m_req_addr;
	output wire m_req_write;
	output wire [31:0] m_req_wdata;
	output wire [3:0] m_req_wstrb;
	input wire m_rsp_valid;
	output wire m_rsp_ready;
	input wire [31:0] m_rsp_rdata;
	input wire m_rsp_error;
	wire src_rst;
	reg busy_q;
	wire req_ready_local;
	wire rsp_valid_local;
	reg rsp_hold_valid_q;
	reg rsp_hold_error_q;
	reg [31:0] rsp_hold_rdata_q;
	wire [31:0] rsp_rdata_local;
	wire rsp_error_local;
	pg_reset_sync release_src(
		.clk(src_clk),
		.arst(arst),
		.rst(src_rst)
	);
	assign s_req_ready = (!src_rst && !busy_q) && req_ready_local;
	assign s_rsp_valid = rsp_hold_valid_q;
	assign s_rsp_rdata = rsp_hold_rdata_q;
	assign s_rsp_error = rsp_hold_error_q;
	always @(posedge src_clk or posedge src_rst)
		if (src_rst) begin
			busy_q <= 0;
			rsp_hold_valid_q <= 0;
			rsp_hold_rdata_q <= 0;
			rsp_hold_error_q <= 0;
		end
		else begin
			if (s_req_valid && s_req_ready)
				busy_q <= 1;
			if (s_rsp_valid && s_rsp_ready)
				busy_q <= 0;
			if ((rsp_valid_local && !rsp_hold_valid_q) && busy_q) begin
				rsp_hold_valid_q <= 1;
				rsp_hold_rdata_q <= rsp_rdata_local;
				rsp_hold_error_q <= rsp_error_local;
			end
			else if (s_rsp_valid && s_rsp_ready)
				rsp_hold_valid_q <= 0;
		end
	pg_async_fifo_dc #(
		.WIDTH(53),
		.DEPTH(2)
	) req_fifo(
		.wr_clk(src_clk),
		.rd_clk(dst_clk),
		.arst(arst),
		.in_valid((s_req_valid && !busy_q) && !src_rst),
		.in_ready(req_ready_local),
		.in_data({s_req_addr, s_req_write, s_req_wdata, s_req_wstrb}),
		.out_valid(m_req_valid),
		.out_ready(m_req_ready),
		.out_data({m_req_addr, m_req_write, m_req_wdata, m_req_wstrb})
	);
	pg_async_fifo_dc #(
		.WIDTH(33),
		.DEPTH(2)
	) rsp_fifo(
		.wr_clk(dst_clk),
		.rd_clk(src_clk),
		.arst(arst),
		.in_valid(m_rsp_valid),
		.in_ready(m_rsp_ready),
		.in_data({m_rsp_error, m_rsp_rdata}),
		.out_valid(rsp_valid_local),
		.out_ready((!rsp_hold_valid_q && busy_q) && !src_rst),
		.out_data({rsp_error_local, rsp_rdata_local})
	);
endmodule
module pg_reset_sync (
	clk,
	arst,
	rst
);
	input wire clk;
	input wire arst;
	output wire rst;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] release_q;
	always @(posedge clk or posedge arst)
		if (arst)
			release_q <= 2'b11;
		else
			release_q <= {release_q[0], 1'b0};
	assign rst = release_q[1];
endmodule
module pg_source_level_register (
	clk,
	rst,
	level_in,
	level_out
);
	input wire clk;
	input wire rst;
	input wire level_in;
	output wire level_out;
	(* KEEP = "TRUE" *) reg source_q;
	always @(posedge clk or posedge rst)
		if (rst)
			source_q <= 1'b0;
		else
			source_q <= level_in;
	assign level_out = source_q;
endmodule
module cp12_dma_read_step (
	address,
	element_bytes,
	next_address
);
	parameter signed [31:0] MEM_BYTES = 16;
	input wire [31:0] address;
	input wire [1:0] element_bytes;
	output wire [31:0] next_address;
	localparam signed [31:0] OFF_W = $clog2(MEM_BYTES);
	initial if (((MEM_BYTES < 4) || ((MEM_BYTES & (MEM_BYTES - 1)) != 0)) || (OFF_W >= 32)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/cp12_dma_read_step.sv:10:3 - cp12_dma_read_step.<unnamed_block>\n msg: ", $time, "CP12_READ_STEP_PARAMETER");
		$finish(1);
	end
	wire [31 - OFF_W:0] next_beat;
	assign next_beat = address[31:OFF_W] + 1'b1;
	assign next_address = ((element_bytes == 2'd2) && address[0] ? {address[31:OFF_W], {OFF_W {1'b1}}} : {next_beat, {OFF_W {1'b0}}});
endmodule
module cp9_progress_watchdog (
	clk,
	rst,
	job_accept,
	active,
	pending,
	progress,
	effective_count,
	expired
);
	parameter integer LIMIT = 4096;
	function automatic signed [63:0] sv2v_cast_64_signed;
		input reg signed [63:0] inp;
		sv2v_cast_64_signed = inp;
	endfunction
	parameter integer W = (LIMIT > 1 ? $clog2(sv2v_cast_64_signed(LIMIT) + 64'd1) : 1);
	input wire clk;
	input wire rst;
	input wire job_accept;
	input wire active;
	input wire pending;
	input wire progress;
	output wire [W - 1:0] effective_count;
	output wire expired;
	function automatic signed [W - 1:0] sv2v_cast_E16C3_signed;
		input reg signed [W - 1:0] inp;
		sv2v_cast_E16C3_signed = inp;
	endfunction
	generate
		if (LIMIT == 0) begin : g_disabled
			assign effective_count = 1'sb0;
			assign expired = 1'b0;
		end
		else begin : g_enabled
			localparam [W - 1:0] L = sv2v_cast_E16C3_signed(LIMIT);
			reg zero_q;
			reg [W - 1:0] count_q;
			assign effective_count = (zero_q ? {W {1'sb0}} : count_q);
			if (LIMIT == 1) begin : g_one
				assign expired = (pending && !progress) && (zero_q || (count_q == {W {1'sb0}}));
			end
			else begin : g_more
				assign expired = ((pending && !progress) && !zero_q) && (count_q == (L - 1'b1));
			end
			always @(posedge clk)
				if (rst)
					zero_q <= 1'b1;
				else if (job_accept)
					zero_q <= 1'b1;
				else if (active)
					zero_q <= progress || !pending;
			always @(posedge clk)
				if (active) begin
					if (zero_q)
						count_q <= sv2v_cast_E16C3_signed(1);
					else if (count_q < L)
						count_q <= count_q + 1'b1;
				end
		end
	endgenerate
endmodule
module npu_spad_lane_ram (
	clk,
	wr_en,
	rd_en,
	wr_addr,
	rd_addr,
	wr_data,
	rd_data
);
	parameter signed [31:0] ADDR_W = 7;
	input wire clk;
	input wire wr_en;
	input wire rd_en;
	input wire [ADDR_W - 1:0] wr_addr;
	input wire [ADDR_W - 1:0] rd_addr;
	input wire [15:0] wr_data;
	output reg [15:0] rd_data;
	(* ram_style = "block" *) reg [15:0] mem [0:(1 << ADDR_W) - 1];
	always @(posedge clk) begin
		if (wr_en)
			mem[wr_addr] <= wr_data;
		if (rd_en)
			rd_data <= mem[rd_addr];
	end
	initial if ((ADDR_W < 4) || (ADDR_W > 9)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_spad_lane_ram.sv:18:5 - npu_spad_lane_ram.<unnamed_block>\n msg: ", $time, "TC_SPAD_ADDR_W");
		$finish(1);
	end
endmodule
module npu_spad_packed_ram (
	clk,
	wr_mask,
	wr_addr,
	wr_data,
	rd_en,
	rd_addr,
	rd_data
);
	parameter signed [31:0] ADDR_W = 4;
	parameter signed [31:0] PACK_ELEMS = 8;
	input wire clk;
	input wire [PACK_ELEMS - 1:0] wr_mask;
	input wire [ADDR_W - 1:0] wr_addr;
	input wire [(PACK_ELEMS * 16) - 1:0] wr_data;
	input wire rd_en;
	input wire [ADDR_W - 1:0] rd_addr;
	output reg [(PACK_ELEMS * 16) - 1:0] rd_data;
	(* ram_style = "block" *) reg [(PACK_ELEMS * 16) - 1:0] memory [0:(1 << ADDR_W) - 1];
	always @(posedge clk) begin
		begin : sv2v_autoblock_1
			integer b;
			for (b = 0; b < PACK_ELEMS; b = b + 1)
				if (wr_mask[b])
					memory[wr_addr][b * 16+:16] <= wr_data[b * 16+:16];
		end
		if (rd_en)
			rd_data <= memory[rd_addr];
	end
endmodule
module pg_cpu_peripherals (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_wdata,
	req_write,
	req_is_fetch,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	uart_rx,
	uart_tx,
	gpio_in,
	gpio_out,
	diagnostic_mailbox,
	timer_gray
);
	parameter [31:0] CLOCK_HZ = 32'd100000000;
	parameter signed [31:0] UART_CLKS_PER_BIT = 868;
	parameter signed [31:0] UART_RX_DEPTH = 1;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output wire req_ready;
	input wire [31:0] req_addr;
	input wire [31:0] req_wdata;
	input wire req_write;
	input wire req_is_fetch;
	input wire [3:0] req_wstrb;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	input wire uart_rx;
	output wire uart_tx;
	input wire [31:0] gpio_in;
	output wire [31:0] gpio_out;
	output reg [31:0] diagnostic_mailbox;
	output reg [63:0] timer_gray;
	reg pending;
	reg tx_valid;
	wire tx_ready;
	wire rx_valid;
	wire rx_ready;
	wire frame_error;
	wire overrun;
	reg frame_sticky;
	reg overrun_sticky;
	reg [7:0] tx_data;
	wire [7:0] rx_data;
	wire rx_byte_valid;
	wire rx_byte_ready;
	wire [7:0] rx_byte_data;
	reg [31:0] gpio_value;
	wire [31:0] gpio_sample;
	reg [31:0] high_q;
	reg [31:0] data_q;
	reg [63:0] ticks_q;
	reg error_q;
	wire tx_write;
	wire accept;
	initial if (CLOCK_HZ == 0) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/peripheral/pg_cpu_peripherals.sv:27:29 - pg_cpu_peripherals.<unnamed_block>\n msg: ", $time, "PG_CLOCK_FREQUENCY_RED");
		$finish(1);
	end
	wire [31:0] addr_word = {req_addr[31:2], 2'b00};
	function automatic [31:0] merge_bytes;
		input reg [31:0] oldword;
		input reg [31:0] newword;
		input reg [3:0] strobe;
		reg [31:0] v;
		begin
			v = oldword;
			begin : sv2v_autoblock_1
				reg signed [31:0] i;
				for (i = 0; i < 4; i = i + 1)
					if (strobe[i])
						v[i * 8+:8] = newword[i * 8+:8];
			end
			merge_bytes = v;
		end
	endfunction
	assign tx_write = ((!req_is_fetch && req_write) && req_wstrb[0]) && (addr_word == 32'h30000020);
	assign req_ready = (!rst && !pending) && (!tx_write || !tx_valid);
	assign accept = req_valid && req_ready;
	assign rsp_valid = !rst && pending;
	assign rsp_rdata = data_q;
	assign rsp_error = error_q;
	assign rx_ready = ((accept && !req_is_fetch) && !req_write) && (addr_word == 32'h30000028);
	pg_uart #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) uart(
		.clk(clk),
		.rst(rst),
		.tx_valid(tx_valid),
		.tx_ready(tx_ready),
		.tx_data(tx_data),
		.tx_pin(uart_tx),
		.rx_pin(uart_rx),
		.rx_valid(rx_byte_valid),
		.rx_ready(rx_byte_ready),
		.rx_data(rx_byte_data),
		.rx_frame_error(frame_error),
		.rx_overrun(overrun)
	);
	generate
		if (UART_RX_DEPTH == 1) begin : g_rx_legacy
			assign rx_valid = rx_byte_valid;
			assign rx_data = rx_byte_data;
			assign rx_byte_ready = rx_ready;
		end
		else begin : g_rx_buffered
			pg_sync_fifo #(
				.WIDTH(8),
				.DEPTH(UART_RX_DEPTH)
			) rx_fifo(
				.clk(clk),
				.rst(rst),
				.in_valid(rx_byte_valid),
				.in_ready(rx_byte_ready),
				.in_data(rx_byte_data),
				.out_valid(rx_valid),
				.out_ready(rx_ready),
				.out_data(rx_data),
				.level()
			);
		end
	endgenerate
	pg_gpio gpio(
		.clk(clk),
		.rst(rst),
		.pins_in(gpio_in),
		.value_out(gpio_value),
		.pins_out(gpio_out),
		.sampled_in(gpio_sample)
	);
	always @(posedge clk)
		if (rst) begin
			pending <= 0;
			data_q <= 0;
			error_q <= 0;
			ticks_q <= 0;
			high_q <= 0;
			timer_gray <= 0;
			gpio_value <= 0;
			diagnostic_mailbox <= 0;
			tx_valid <= 0;
			tx_data <= 0;
			frame_sticky <= 0;
			overrun_sticky <= 0;
		end
		else begin
			ticks_q <= ticks_q + 1'b1;
			timer_gray <= (ticks_q >> 1) ^ ticks_q;
			if (tx_valid && tx_ready)
				tx_valid <= 0;
			if (pending && rsp_ready)
				pending <= 0;
			if (accept) begin
				pending <= 1;
				data_q <= 0;
				error_q <= req_is_fetch;
				if (!req_is_fetch)
					case (addr_word)
						32'h30000000:
							if (req_write)
								error_q <= 1;
							else begin
								data_q <= ticks_q[31:0];
								high_q <= ticks_q[63:32];
							end
						32'h30000004: begin
							data_q <= high_q;
							if (req_write)
								error_q <= 1;
						end
						32'h30000008: begin
							data_q <= CLOCK_HZ;
							if (req_write)
								error_q <= 1;
						end
						32'h30000010: begin
							data_q <= gpio_value;
							if (req_write)
								gpio_value <= merge_bytes(gpio_value, req_wdata, req_wstrb);
						end
						32'h30000014: begin
							data_q <= gpio_sample;
							if (req_write)
								error_q <= 1;
						end
						32'h30000020: begin
							data_q <= {31'd0, !tx_valid};
							if (tx_write) begin
								tx_data <= req_wdata[7:0];
								tx_valid <= 1;
							end
						end
						32'h30000024: begin
							data_q <= {28'd0, overrun_sticky, frame_sticky, !tx_valid, rx_valid};
							if (req_write)
								error_q <= 1;
						end
						32'h30000028: begin
							data_q <= (rx_valid ? {24'd0, rx_data} : 32'd0);
							if (req_write)
								error_q <= 1;
						end
						32'h3000002c: begin
							data_q <= {30'd0, overrun_sticky, frame_sticky};
							if (req_write && req_wstrb[0]) begin
								if (req_wdata[0])
									frame_sticky <= 0;
								if (req_wdata[1])
									overrun_sticky <= 0;
							end
						end
						32'h300000fc: begin
							data_q <= diagnostic_mailbox;
							if (req_write)
								diagnostic_mailbox <= merge_bytes(diagnostic_mailbox, req_wdata, req_wstrb);
						end
						default: error_q <= 1;
					endcase
			end
			if (frame_error)
				frame_sticky <= 1;
			if (overrun)
				overrun_sticky <= 1;
		end
endmodule
module pg_gpio (
	clk,
	rst,
	pins_in,
	value_out,
	pins_out,
	sampled_in
);
	parameter signed [31:0] WIDTH = 32;
	input wire clk;
	input wire rst;
	input wire [WIDTH - 1:0] pins_in;
	input wire [WIDTH - 1:0] value_out;
	output wire [WIDTH - 1:0] pins_out;
	output reg [WIDTH - 1:0] sampled_in;
	reg [WIDTH - 1:0] meta_q;
	assign pins_out = value_out;
	always @(posedge clk)
		if (rst) begin
			meta_q <= 1'sb0;
			sampled_in <= 1'sb0;
		end
		else begin
			meta_q <= pins_in;
			sampled_in <= meta_q;
		end
endmodule
module pg_uart (
	clk,
	rst,
	tx_valid,
	tx_ready,
	tx_data,
	tx_pin,
	rx_pin,
	rx_valid,
	rx_ready,
	rx_data,
	rx_frame_error,
	rx_overrun
);
	parameter signed [31:0] CLKS_PER_BIT = 16;
	input wire clk;
	input wire rst;
	input wire tx_valid;
	output wire tx_ready;
	input wire [7:0] tx_data;
	output wire tx_pin;
	input wire rx_pin;
	output reg rx_valid;
	input wire rx_ready;
	output reg [7:0] rx_data;
	output reg rx_frame_error;
	output reg rx_overrun;
	localparam signed [31:0] COUNT_W = (CLKS_PER_BIT > 1 ? $clog2(CLKS_PER_BIT) : 1);
	reg tx_busy;
	reg [9:0] tx_shift;
	reg [3:0] tx_bits;
	reg [COUNT_W - 1:0] tx_count;
	reg [COUNT_W - 1:0] rx_count;
	reg rx_meta;
	reg rx_sync;
	reg [2:0] rx_bit;
	reg [7:0] rx_shift;
	reg [2:0] rx_state;
	initial if (CLKS_PER_BIT < 4) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/peripheral/pg_uart.sv:27:35 - pg_uart.<unnamed_block>\n msg: ", $time, "PG_UART_DIVISOR_RED");
		$finish(1);
	end
	assign tx_ready = !rst && !tx_busy;
	assign tx_pin = (tx_busy ? tx_shift[0] : 1'b1);
	function automatic signed [COUNT_W - 1:0] sv2v_cast_D4579_signed;
		input reg signed [COUNT_W - 1:0] inp;
		sv2v_cast_D4579_signed = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			tx_busy <= 0;
			tx_shift <= 1'sb1;
			tx_bits <= 0;
			tx_count <= 0;
		end
		else if (tx_busy) begin
			if (tx_count == 0) begin
				tx_shift <= {1'b1, tx_shift[9:1]};
				tx_count <= sv2v_cast_D4579_signed(CLKS_PER_BIT - 1);
				tx_bits <= tx_bits - 1'b1;
				if (tx_bits == 1)
					tx_busy <= 0;
			end
			else
				tx_count <= tx_count - 1'b1;
		end
		else if (tx_valid && tx_ready) begin
			tx_shift <= {1'b1, tx_data, 1'b0};
			tx_bits <= 10;
			tx_count <= sv2v_cast_D4579_signed(CLKS_PER_BIT - 1);
			tx_busy <= 1;
		end
	always @(posedge clk)
		if (rst) begin
			rx_meta <= 1;
			rx_sync <= 1;
		end
		else begin
			rx_meta <= rx_pin;
			rx_sync <= rx_meta;
		end
	always @(posedge clk)
		if (rst) begin
			rx_state <= 3'd0;
			rx_count <= 0;
			rx_bit <= 0;
			rx_shift <= 0;
			rx_valid <= 0;
			rx_data <= 0;
			rx_frame_error <= 0;
			rx_overrun <= 0;
		end
		else begin
			rx_frame_error <= 0;
			rx_overrun <= 0;
			if (rx_valid && rx_ready)
				rx_valid <= 0;
			case (rx_state)
				3'd0:
					if (!rx_sync) begin
						rx_count <= sv2v_cast_D4579_signed((CLKS_PER_BIT / 2) - 1);
						rx_state <= 3'd1;
					end
				3'd1:
					if (rx_count != 0)
						rx_count <= rx_count - 1'b1;
					else if (rx_sync)
						rx_state <= 3'd0;
					else begin
						rx_bit <= 0;
						rx_count <= sv2v_cast_D4579_signed(CLKS_PER_BIT - 1);
						rx_state <= 3'd2;
					end
				3'd2:
					if (rx_count != 0)
						rx_count <= rx_count - 1'b1;
					else begin
						rx_shift[rx_bit] <= rx_sync;
						rx_count <= sv2v_cast_D4579_signed(CLKS_PER_BIT - 1);
						if (rx_bit == 7)
							rx_state <= 3'd3;
						else
							rx_bit <= rx_bit + 1'b1;
					end
				3'd3:
					if (rx_count != 0)
						rx_count <= rx_count - 1'b1;
					else if (!rx_sync) begin
						rx_frame_error <= 1;
						rx_state <= 3'd4;
					end
					else begin
						if (rx_valid && !rx_ready)
							rx_overrun <= 1;
						else begin
							rx_valid <= 1;
							rx_data <= rx_shift;
						end
						rx_state <= 3'd0;
					end
				3'd4:
					if (rx_sync)
						rx_state <= 3'd0;
				default: rx_state <= 3'd0;
			endcase
		end
endmodule
module DSP48E1 (
	ACOUT,
	BCOUT,
	CARRYCASCOUT,
	CARRYOUT,
	MULTSIGNOUT,
	OVERFLOW,
	P,
	PATTERNBDETECT,
	PATTERNDETECT,
	PCOUT,
	UNDERFLOW,
	A,
	ACIN,
	ALUMODE,
	B,
	BCIN,
	C,
	CARRYCASCIN,
	CARRYIN,
	CARRYINSEL,
	CEA1,
	CEA2,
	CEAD,
	CEALUMODE,
	CEB1,
	CEB2,
	CEC,
	CECARRYIN,
	CECTRL,
	CED,
	CEINMODE,
	CEM,
	CEP,
	CLK,
	D,
	INMODE,
	MULTSIGNIN,
	OPMODE,
	PCIN,
	RSTA,
	RSTALLCARRYIN,
	RSTALUMODE,
	RSTB,
	RSTC,
	RSTCTRL,
	RSTD,
	RSTINMODE,
	RSTM,
	RSTP
);
	parameter integer ACASCREG = 1;
	parameter integer AREG = 1;
	parameter integer BCASCREG = 1;
	parameter integer BREG = 1;
	parameter integer ADREG = 0;
	parameter integer ALUMODEREG = 0;
	parameter integer CARRYINREG = 0;
	parameter integer CARRYINSELREG = 0;
	parameter integer CREG = 0;
	parameter integer DREG = 0;
	parameter integer INMODEREG = 0;
	parameter integer MREG = 0;
	parameter integer OPMODEREG = 0;
	parameter integer PREG = 1;
	parameter USE_DPORT = "FALSE";
	parameter USE_MULT = "MULTIPLY";
	parameter USE_SIMD = "ONE48";
	output wire [29:0] ACOUT;
	output wire [17:0] BCOUT;
	output wire CARRYCASCOUT;
	output wire [3:0] CARRYOUT;
	output wire MULTSIGNOUT;
	output wire OVERFLOW;
	output wire [47:0] P;
	output wire PATTERNBDETECT;
	output wire PATTERNDETECT;
	output wire [47:0] PCOUT;
	output wire UNDERFLOW;
	input wire [29:0] A;
	input wire [29:0] ACIN;
	input wire [3:0] ALUMODE;
	input wire [17:0] B;
	input wire [17:0] BCIN;
	input wire [47:0] C;
	input wire CARRYCASCIN;
	input wire CARRYIN;
	input wire [2:0] CARRYINSEL;
	input wire CEA1;
	input wire CEA2;
	input wire CEAD;
	input wire CEALUMODE;
	input wire CEB1;
	input wire CEB2;
	input wire CEC;
	input wire CECARRYIN;
	input wire CECTRL;
	input wire CED;
	input wire CEINMODE;
	input wire CEM;
	input wire CEP;
	input wire CLK;
	input wire [24:0] D;
	input wire [4:0] INMODE;
	input wire MULTSIGNIN;
	input wire [6:0] OPMODE;
	input wire [47:0] PCIN;
	input wire RSTA;
	input wire RSTALLCARRYIN;
	input wire RSTALUMODE;
	input wire RSTB;
	input wire RSTC;
	input wire RSTCTRL;
	input wire RSTD;
	input wire RSTINMODE;
	input wire RSTM;
	input wire RSTP;
	wire [47:0] pango_product;
	GTP_APM_E2 #(
		.GRS_EN("TRUE"),
		.ASYNC_RST(0),
		.X_REG(AREG),
		.XB_REG(0),
		.Y_REG(BREG),
		.Z_REG(0),
		.MULT_REG(1),
		.P_REG(0),
		.PREADD_REG(0),
		.MODEIN_REG(0),
		.MODEY_REG(0),
		.MODEZ_REG(0),
		.USE_MULT(1),
		.USE_PREADD(0),
		.USE_POSTADD(0),
		.USE_SIMD(0),
		.X_SEL(0),
		.XB_SEL(0),
		.P_INIT0(48'd0),
		.P_INIT1(48'd0)
	) u_pango_apm(
		.COUT(),
		.CPO(),
		.CXO(),
		.CXBO(),
		.P(pango_product),
		.CIN(1'b0),
		.CPI(48'd0),
		.CXI(30'd0),
		.CXBI(25'd0),
		.X(A),
		.XB(25'd0),
		.Y(B),
		.Z(48'd0),
		.MODEIN(5'b00010),
		.MODEY(3'b001),
		.MODEZ(4'b0000),
		.CLK(CLK),
		.CEX1(CEA2),
		.CEX2(1'b0),
		.CEX3(1'b0),
		.CEXB(1'b0),
		.CEY1(CEB2),
		.CEY2(1'b0),
		.CEZ(1'b0),
		.CEM(CEP),
		.CEP(1'b0),
		.CEPRE(1'b0),
		.CEMODEIN(1'b0),
		.CEMODEY(1'b0),
		.CEMODEZ(1'b0),
		.RSTX(RSTA),
		.RSTXB(RSTA),
		.RSTY(RSTB),
		.RSTZ(RSTC),
		.RSTM(RSTM | RSTP),
		.RSTP(RSTP),
		.RSTPRE(RSTD),
		.RSTMODEIN(RSTINMODE),
		.RSTMODEY(RSTCTRL),
		.RSTMODEZ(RSTCTRL)
	);
	assign P = pango_product;
	assign ACOUT = 30'd0;
	assign BCOUT = 18'd0;
	assign CARRYCASCOUT = 1'b0;
	assign CARRYOUT = 4'd0;
	assign MULTSIGNOUT = 1'b0;
	assign OVERFLOW = 1'b0;
	assign PATTERNBDETECT = 1'b0;
	assign PATTERNDETECT = 1'b0;
	assign PCOUT = 48'd0;
	assign UNDERFLOW = 1'b0;
endmodule
module npu_scratchpad_int8packed16 (
	clk,
	rst,
	owner_req_valid,
	owner_req_is_b,
	owner_req_bank,
	owner_req_state,
	dma_write_valid,
	dma_is_b,
	dma_bank,
	dma_lane,
	dma_k,
	dma_input_int16,
	dma_data,
	dma_count,
	compute_read_valid,
	compute_bank,
	compute_k,
	a_vector,
	b_vector,
	compute_read_data_valid,
	a_owner,
	b_owner,
	protocol_error
);
	reg _sv2v_0;
	parameter signed [31:0] ARRAY_ROWS = 16;
	parameter signed [31:0] ARRAY_COLS = 8;
	parameter signed [31:0] K_TILE = 64;
	parameter signed [31:0] MAX_ELEM_W = 16;
	parameter signed [31:0] DMA_VECTOR_ELEMS = 16;
	input wire clk;
	input wire rst;
	input wire owner_req_valid;
	input wire owner_req_is_b;
	input wire owner_req_bank;
	input wire [1:0] owner_req_state;
	input wire dma_write_valid;
	input wire dma_is_b;
	input wire dma_bank;
	input wire [(ARRAY_ROWS > ARRAY_COLS ? (ARRAY_ROWS > 1 ? $clog2(ARRAY_ROWS) : 1) : (ARRAY_COLS > 1 ? $clog2(ARRAY_COLS) : 1)) - 1:0] dma_lane;
	input wire [(K_TILE > 1 ? $clog2(K_TILE) : 1) - 1:0] dma_k;
	input wire dma_input_int16;
	input wire signed [(DMA_VECTOR_ELEMS * 16) - 1:0] dma_data;
	input wire [(DMA_VECTOR_ELEMS > 1 ? $clog2(DMA_VECTOR_ELEMS + 1) : 1) - 1:0] dma_count;
	input wire compute_read_valid;
	input wire compute_bank;
	input wire [(K_TILE > 1 ? $clog2(K_TILE) : 1) - 1:0] compute_k;
	output wire [(ARRAY_ROWS * MAX_ELEM_W) - 1:0] a_vector;
	output wire [(ARRAY_COLS * MAX_ELEM_W) - 1:0] b_vector;
	output reg compute_read_data_valid;
	output reg [3:0] a_owner;
	output reg [3:0] b_owner;
	output reg protocol_error;
	localparam [1:0] OWNER_EMPTY = 0;
	localparam [1:0] OWNER_FILLING = 1;
	localparam [1:0] OWNER_READY = 2;
	localparam [1:0] OWNER_COMPUTE = 3;
	localparam signed [31:0] LANE_W = $clog2((ARRAY_ROWS > ARRAY_COLS ? ARRAY_ROWS : ARRAY_COLS));
	localparam signed [31:0] K_W = $clog2(K_TILE);
	localparam signed [31:0] A_ADDR_W = K_W - 2;
	localparam signed [31:0] A_BANK_WORD_W = K_W - 3;
	reg [1:0] a_mode_valid;
	reg [1:0] b_mode_valid;
	reg [1:0] a_mode_int16;
	reg [1:0] b_mode_int16;
	reg dma_legal;
	reg compute_legal;
	wire dma_fire;
	wire compute_fire;
	reg owner_legal;
	reg vector_zero_q;
	reg read_mode_q;
	wire [3:0] write_byte_offset;
	wire [3:0] read_byte_offset;
	reg [3:0] read_byte_offset_q;
	wire [4:0] a_byte_count;
	wire [15:0] a_count_mask;
	wire [15:0] a_write_mask;
	wire [127:0] a_unshifted_bytes;
	wire [127:0] a_write_data;
	wire [A_BANK_WORD_W - 1:0] a_write_word;
	wire [A_BANK_WORD_W - 1:0] a_read_word;
	wire [A_ADDR_W - 1:0] a_write_address;
	wire [A_ADDR_W - 1:0] a_read_address;
	wire [ARRAY_COLS - 1:0] b_count_mask;
	wire [ARRAY_COLS - 1:0] b_write_mask;
	wire [(ARRAY_COLS * 16) - 1:0] b_unshifted_data;
	wire [(ARRAY_COLS * 16) - 1:0] b_write_data;
	wire [K_W:0] b_write_address;
	wire [K_W:0] b_read_address;
	function automatic legal_transition;
		input reg [1:0] current_state;
		input reg [1:0] requested_state;
		legal_transition = ((((current_state === OWNER_EMPTY) && (requested_state === OWNER_FILLING)) || ((current_state === OWNER_FILLING) && (requested_state === OWNER_READY))) || ((current_state === OWNER_READY) && (requested_state === OWNER_COMPUTE))) || ((current_state === OWNER_COMPUTE) && (requested_state === OWNER_EMPTY));
	endfunction
	assign write_byte_offset = (dma_input_int16 ? {dma_k[2:0], 1'b0} : dma_k[3:0]);
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	assign a_byte_count = (dma_input_int16 ? sv2v_cast_5(dma_count) << 1 : sv2v_cast_5(dma_count));
	function automatic [A_BANK_WORD_W - 1:0] sv2v_cast_DD689;
		input reg [A_BANK_WORD_W - 1:0] inp;
		sv2v_cast_DD689 = inp;
	endfunction
	assign a_write_word = sv2v_cast_DD689(dma_k >> (dma_input_int16 ? 3 : 4));
	assign a_read_word = sv2v_cast_DD689(compute_k >> (a_mode_int16[compute_bank] ? 3 : 4));
	assign a_write_address = {dma_bank, a_write_word};
	assign a_read_address = {compute_bank, a_read_word};
	assign read_byte_offset = (a_mode_int16[compute_bank] ? {compute_k[2:0], 1'b0} : compute_k[3:0]);
	assign b_write_address = {dma_bank, dma_k};
	assign b_read_address = {compute_bank, compute_k};
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		owner_legal = !(((owner_req_is_b !== 1'b0) && (owner_req_is_b !== 1'b1)) || ((owner_req_bank !== 1'b0) && (owner_req_bank !== 1'b1))) && legal_transition((owner_req_is_b ? b_owner[owner_req_bank * 2+:2] : a_owner[owner_req_bank * 2+:2]), owner_req_state);
		dma_legal = !((((((((((((dma_is_b !== 1'b0) && (dma_is_b !== 1'b1)) || ((dma_bank !== 1'b0) && (dma_bank !== 1'b1))) || ((dma_input_int16 !== 1'b0) && (dma_input_int16 !== 1'b1))) || (^dma_lane === 1'bx)) || (^dma_k === 1'bx)) || (^dma_count === 1'bx)) || (dma_count == 0)) || (sv2v_cast_32_signed(dma_count) > 16)) || (sv2v_cast_32_signed(dma_k) >= K_TILE)) || (!dma_is_b && ((((((sv2v_cast_32_signed(dma_lane) >= ARRAY_ROWS) || ((sv2v_cast_32_signed(dma_k) + sv2v_cast_32_signed(dma_count)) > K_TILE)) || (dma_input_int16 && (sv2v_cast_32_signed(dma_count) > 8))) || ((sv2v_cast_32_signed(write_byte_offset) + sv2v_cast_32_signed(a_byte_count)) > 16)) || (a_owner[dma_bank * 2+:2] !== OWNER_FILLING)) || (a_mode_valid[dma_bank] && (a_mode_int16[dma_bank] !== dma_input_int16))))) || (dma_is_b && ((((sv2v_cast_32_signed(dma_lane) >= ARRAY_COLS) || ((sv2v_cast_32_signed(dma_lane) + sv2v_cast_32_signed(dma_count)) > ARRAY_COLS)) || (b_owner[dma_bank * 2+:2] !== OWNER_FILLING)) || (b_mode_valid[dma_bank] && (b_mode_int16[dma_bank] !== dma_input_int16)))));
		compute_legal = !(((((((((compute_bank !== 1'b0) && (compute_bank !== 1'b1)) || (^compute_k === 1'bx)) || (sv2v_cast_32_signed(compute_k) >= K_TILE)) || (a_owner[compute_bank * 2+:2] !== OWNER_COMPUTE)) || (b_owner[compute_bank * 2+:2] !== OWNER_COMPUTE)) || (a_mode_valid[compute_bank] !== 1'b1)) || (b_mode_valid[compute_bank] !== 1'b1)) || (a_mode_int16[compute_bank] !== b_mode_int16[compute_bank]));
	end
	assign dma_fire = (!rst && (dma_write_valid === 1'b1)) && dma_legal;
	assign compute_fire = (!rst && (compute_read_valid === 1'b1)) && compute_legal;
	genvar _gv_e_3;
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	generate
		for (_gv_e_3 = 0; _gv_e_3 < 16; _gv_e_3 = _gv_e_3 + 1) begin : g_a_bytes
			localparam e = _gv_e_3;
			assign a_unshifted_bytes[e * 8+:8] = (dma_input_int16 ? dma_data[((e / 2) * 16) + ((e % 2) * 8)+:8] : dma_data[e * 16+:8]);
			assign a_count_mask[e] = a_byte_count > sv2v_cast_5_signed(e);
		end
	endgenerate
	assign a_write_data = a_unshifted_bytes << {write_byte_offset, 3'b000};
	assign a_write_mask = (a_count_mask << write_byte_offset) & {16 {dma_fire && !dma_is_b}};
	genvar _gv_e_4;
	function automatic signed [(DMA_VECTOR_ELEMS > 1 ? $clog2(DMA_VECTOR_ELEMS + 1) : 1) - 1:0] sv2v_cast_5F5CC_signed;
		input reg signed [(DMA_VECTOR_ELEMS > 1 ? $clog2(DMA_VECTOR_ELEMS + 1) : 1) - 1:0] inp;
		sv2v_cast_5F5CC_signed = inp;
	endfunction
	generate
		for (_gv_e_4 = 0; _gv_e_4 < ARRAY_COLS; _gv_e_4 = _gv_e_4 + 1) begin : g_b_normalize
			localparam e = _gv_e_4;
			assign b_unshifted_data[e * 16+:16] = (dma_input_int16 ? dma_data[e * 16+:16] : {{8 {dma_data[(e * 16) + 7]}}, dma_data[e * 16+:8]});
			assign b_count_mask[e] = dma_count > sv2v_cast_5F5CC_signed(e);
		end
	endgenerate
	assign b_write_data = b_unshifted_data << {dma_lane, 4'b0000};
	assign b_write_mask = (b_count_mask << dma_lane) & {ARRAY_COLS {dma_fire && dma_is_b}};
	localparam signed [31:0] A_READ_GROUPS = (ARRAY_ROWS + 3) / 4;
	(* syn_keep = 1 *) wire [A_READ_GROUPS - 1:0] group_read_enable;
	genvar _gv_g_3;
	generate
		for (_gv_g_3 = 0; _gv_g_3 < A_READ_GROUPS; _gv_g_3 = _gv_g_3 + 1) begin : g_a_read_group
			localparam g = _gv_g_3;
			(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) local_read_driver(
				.I0(compute_fire),
				.Z(group_read_enable[g])
			);
		end
	endgenerate
	genvar _gv_r_4;
	function automatic signed [LANE_W - 1:0] sv2v_cast_3FA0D_signed;
		input reg signed [LANE_W - 1:0] inp;
		sv2v_cast_3FA0D_signed = inp;
	endfunction
	generate
		for (_gv_r_4 = 0; _gv_r_4 < ARRAY_ROWS; _gv_r_4 = _gv_r_4 + 1) begin : g_a_lane
			localparam r = _gv_r_4;
			wire [15:0] held_data;
			wire [15:0] lane_mask = a_write_mask & {16 {dma_lane == sv2v_cast_3FA0D_signed(r)}};
			npu_spad_byte_read16_ram #(.ADDR_W(A_ADDR_W)) mem(
				.clk(clk),
				.wr_mask(lane_mask),
				.wr_addr(a_write_address),
				.wr_data(a_write_data),
				.rd_en(group_read_enable[r / 4]),
				.rd_addr(a_read_address),
				.rd_byte_offset(read_byte_offset),
				.rd_int16(a_mode_int16[compute_bank]),
				.rd_data(held_data)
			);
			assign a_vector[r * 16+:16] = (vector_zero_q ? 16'd0 : held_data);
		end
	endgenerate
	genvar _gv_c_5;
	generate
		for (_gv_c_5 = 0; _gv_c_5 < ARRAY_COLS; _gv_c_5 = _gv_c_5 + 1) begin : g_b_lane
			localparam c = _gv_c_5;
			wire [15:0] data;
			npu_spad_lane_ram #(.ADDR_W(K_W + 1)) mem(
				.clk(clk),
				.wr_en(b_write_mask[c]),
				.wr_addr(b_write_address),
				.wr_data(b_write_data[c * 16+:16]),
				.rd_en(compute_fire),
				.rd_addr(b_read_address),
				.rd_data(data)
			);
			assign b_vector[c * 16+:16] = (vector_zero_q ? 16'd0 : data);
		end
	endgenerate
	always @(posedge clk)
		if (rst) begin
			a_owner <= 1'sb0;
			b_owner <= 1'sb0;
			a_mode_valid <= 1'sb0;
			b_mode_valid <= 1'sb0;
			a_mode_int16 <= 1'sb0;
			b_mode_int16 <= 1'sb0;
			vector_zero_q <= 1'b1;
			read_mode_q <= 1'b0;
			read_byte_offset_q <= 1'sb0;
			compute_read_data_valid <= 1'b0;
			protocol_error <= 1'b0;
		end
		else begin
			compute_read_data_valid <= 1'b0;
			protocol_error <= 1'b0;
			if (owner_req_valid === 1'b1) begin
				if (!owner_legal)
					protocol_error <= 1'b1;
				else if (owner_req_is_b) begin
					b_owner[owner_req_bank * 2+:2] <= owner_req_state;
					if ((owner_req_state == OWNER_EMPTY) || (owner_req_state == OWNER_FILLING))
						b_mode_valid[owner_req_bank] <= 1'b0;
				end
				else begin
					a_owner[owner_req_bank * 2+:2] <= owner_req_state;
					if ((owner_req_state == OWNER_EMPTY) || (owner_req_state == OWNER_FILLING))
						a_mode_valid[owner_req_bank] <= 1'b0;
				end
			end
			if (dma_write_valid === 1'b1) begin
				if (!dma_legal)
					protocol_error <= 1'b1;
				else if (dma_is_b) begin
					b_mode_valid[dma_bank] <= 1'b1;
					b_mode_int16[dma_bank] <= dma_input_int16;
				end
				else begin
					a_mode_valid[dma_bank] <= 1'b1;
					a_mode_int16[dma_bank] <= dma_input_int16;
				end
			end
			if (compute_read_valid === 1'b1) begin
				if (!compute_legal) begin
					protocol_error <= 1'b1;
					vector_zero_q <= 1'b1;
				end
				else begin
					vector_zero_q <= 1'b0;
					compute_read_data_valid <= 1'b1;
					read_mode_q <= a_mode_int16[compute_bank];
					read_byte_offset_q <= read_byte_offset;
				end
			end
		end
	initial if (((((((((((DMA_VECTOR_ELEMS != 16) || (MAX_ELEM_W != 16)) || (K_TILE < 16)) || (K_TILE > 256)) || ((K_TILE & (K_TILE - 1)) != 0)) || (ARRAY_ROWS < 2)) || (ARRAY_ROWS > 16)) || ((ARRAY_ROWS & (ARRAY_ROWS - 1)) != 0)) || (ARRAY_COLS < 2)) || (ARRAY_COLS > 16)) || ((ARRAY_COLS & (ARRAY_COLS - 1)) != 0)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_scratchpad_int8packed16.sv:182:7 - npu_scratchpad_int8packed16.<unnamed_block>.<unnamed_block>\n msg: ", $time, "A_INT8PACKED16_CONFIGURATION_RED");
		$finish(1);
	end
	initial _sv2v_0 = 0;
endmodule
module npu_spad_byte_packed_ram (
	clk,
	wr_mask,
	wr_addr,
	wr_data,
	rd_en,
	rd_addr,
	rd_data
);
	parameter signed [31:0] ADDR_W = 4;
	input wire clk;
	input wire [15:0] wr_mask;
	input wire [ADDR_W - 1:0] wr_addr;
	input wire [127:0] wr_data;
	input wire rd_en;
	input wire [ADDR_W - 1:0] rd_addr;
	output reg [127:0] rd_data;
	(* ram_style = "block" *) reg [127:0] memory [0:(1 << ADDR_W) - 1];
	always @(posedge clk) begin
		begin : sv2v_autoblock_1
			integer b;
			for (b = 0; b < 16; b = b + 1)
				if (wr_mask[b])
					memory[wr_addr][b * 8+:8] <= wr_data[b * 8+:8];
		end
		if (rd_en)
			rd_data <= memory[rd_addr];
	end
endmodule
module npu_spad_byte_read16_ram (
	clk,
	wr_mask,
	wr_addr,
	wr_data,
	rd_en,
	rd_addr,
	rd_byte_offset,
	rd_int16,
	rd_data
);
	reg _sv2v_0;
	parameter signed [31:0] ADDR_W = 4;
	input wire clk;
	input wire [15:0] wr_mask;
	input wire [ADDR_W - 1:0] wr_addr;
	input wire [127:0] wr_data;
	input wire rd_en;
	input wire [ADDR_W - 1:0] rd_addr;
	input wire [3:0] rd_byte_offset;
	input wire rd_int16;
	output reg [15:0] rd_data;
	(* ram_style = "block" *) reg [127:0] memory [0:(1 << ADDR_W) - 1];
	wire [127:0] read_word = memory[rd_addr];
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	wire [15:0] read_halfword = read_word[sv2v_cast_32_signed(rd_byte_offset[3:1]) * 16+:16];
	reg [7:0] read_byte;
	always @(*) begin
		if (_sv2v_0)
			;
		case (rd_byte_offset[0])
			1'b0: read_byte = read_halfword[7:0];
			1'b1: read_byte = read_halfword[15:8];
			default: read_byte = 1'sbx;
		endcase
	end
	always @(posedge clk) begin
		begin : sv2v_autoblock_1
			integer b;
			for (b = 0; b < 16; b = b + 1)
				if (wr_mask[b])
					memory[wr_addr][b * 8+:8] <= wr_data[b * 8+:8];
		end
		if (rd_en)
			rd_data <= (rd_int16 ? read_halfword : {{8 {read_byte[7]}}, read_byte});
	end
	initial _sv2v_0 = 0;
endmodule
module soc_tensor_lane_alu (
	add_mode,
	a,
	b,
	result
);
	input wire add_mode;
	input wire [127:0] a;
	input wire [127:0] b;
	output wire [127:0] result;
	function automatic [7:0] calculate;
		input reg do_add;
		input reg signed [7:0] av;
		input reg signed [7:0] bv;
		reg signed [8:0] sum;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			sum = $signed({av[7], av}) + $signed({bv[7], bv});
			if (!do_add) begin
				calculate = (av > bv ? av : bv);
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				if (sum > 9'sd127) begin
					calculate = 8'h7f;
					_sv2v_jump = 2'b11;
				end
				if (_sv2v_jump == 2'b00) begin
					if (sum < -9'sd128) begin
						calculate = 8'h80;
						_sv2v_jump = 2'b11;
					end
					if (_sv2v_jump == 2'b00) begin
						calculate = sum[7:0];
						_sv2v_jump = 2'b11;
					end
				end
			end
		end
	endfunction
	genvar _gv_lane_1;
	generate
		for (_gv_lane_1 = 0; _gv_lane_1 < 16; _gv_lane_1 = _gv_lane_1 + 1) begin : g_lane
			localparam lane = _gv_lane_1;
			assign result[lane * 8+:8] = calculate(add_mode, $signed(a[lane * 8+:8]), $signed(b[lane * 8+:8]));
		end
	endgenerate
endmodule
module soc_tensor_row_ram (
	clk,
	wr_en,
	rd_en,
	wr_addr,
	rd_addr,
	wr_data,
	rd_data
);
	input wire clk;
	input wire wr_en;
	input wire rd_en;
	input wire [8:0] wr_addr;
	input wire [8:0] rd_addr;
	input wire [127:0] wr_data;
	output reg [127:0] rd_data;
	(* ram_style = "block" *) reg [127:0] payload [0:511];
	always @(posedge clk) begin
		if (wr_en)
			payload[wr_addr] <= wr_data;
		if (rd_en)
			rd_data <= payload[rd_addr];
	end
endmodule
module soc_conv_microsequencer (
	clk,
	rst,
	start,
	cancel,
	model_epoch,
	frame_epoch,
	total_rows,
	columns,
	k_length,
	output_width,
	use_window,
	input_int16,
	a_base,
	b_base,
	c_base,
	a_stride,
	c_stride,
	a_block_step,
	c_block_step,
	b_group_step,
	scratch_base,
	scratch_stride,
	window_template,
	resident_a_generation,
	resident_b_base,
	resident_next_a_rows,
	resident_b_columns,
	resident_b_group,
	ready,
	busy,
	done_pulse,
	partial_output,
	protocol_poison,
	rejected_busy,
	error_code,
	error_source,
	completed_MACs,
	command_count,
	Window_count,
	npu_cmd_valid,
	npu_cmd_ready,
	npu_cmd,
	npu_comp_valid,
	npu_comp_ready,
	npu_comp,
	Window_req_valid,
	Window_req_ready,
	Window_req_data,
	Window_req_cookie,
	Window_rsp_valid,
	Window_rsp_ready,
	Window_rsp_cookie,
	Window_rsp_error,
	Window_rsp_partial
);
	reg _sv2v_0;
	parameter integer WINDOW_BATCH_ROWS = 64;
	input wire clk;
	input wire rst;
	input wire start;
	input wire cancel;
	input wire [31:0] model_epoch;
	input wire [31:0] frame_epoch;
	input wire [31:0] total_rows;
	input wire [15:0] columns;
	input wire [15:0] k_length;
	input wire [15:0] output_width;
	input wire use_window;
	input wire input_int16;
	input wire [31:0] a_base;
	input wire [31:0] b_base;
	input wire [31:0] c_base;
	input wire [31:0] a_stride;
	input wire [31:0] c_stride;
	input wire [31:0] a_block_step;
	input wire [31:0] c_block_step;
	input wire [31:0] b_group_step;
	input wire [31:0] scratch_base;
	input wire [31:0] scratch_stride;
	input wire [351:0] window_template;
	output wire [31:0] resident_a_generation;
	output wire [31:0] resident_b_base;
	output wire [4:0] resident_next_a_rows;
	output wire [8:0] resident_b_columns;
	output wire [4:0] resident_b_group;
	output wire ready;
	output wire busy;
	output reg done_pulse;
	output reg partial_output;
	output reg protocol_poison;
	output reg rejected_busy;
	output reg [7:0] error_code;
	output reg [2:0] error_source;
	output reg [63:0] completed_MACs;
	output reg [31:0] command_count;
	output reg [31:0] Window_count;
	output wire npu_cmd_valid;
	input wire npu_cmd_ready;
	output reg [347:0] npu_cmd;
	input wire npu_comp_valid;
	output wire npu_comp_ready;
	input wire [136:0] npu_comp;
	output reg Window_req_valid;
	input wire Window_req_ready;
	output reg [351:0] Window_req_data;
	output reg [31:0] Window_req_cookie;
	input wire Window_rsp_valid;
	output wire Window_rsp_ready;
	input wire [31:0] Window_rsp_cookie;
	input wire [7:0] Window_rsp_error;
	input wire Window_rsp_partial;
	reg [3:0] state;
	reg [31:0] model_q;
	reg [31:0] frame_q;
	reg [31:0] rows_q;
	reg [31:0] first_q;
	reg [31:0] next_first_q;
	reg [15:0] page_first;
	reg [15:0] page_columns;
	reg [31:0] page_b;
	reg [31:0] page_c;
	reg [31:0] initial_a;
	reg [31:0] initial_c;
	function automatic [15:0] page_limit;
		input reg [15:0] k;
		input reg [15:0] n;
		reg [15:0] cap;
		begin
			if (k <= 512)
				cap = 256;
			else if (k <= 576)
				cap = 224;
			else if (k <= 682)
				cap = 192;
			else if (k <= 818)
				cap = 160;
			else if (k <= 1024)
				cap = 128;
			else
				cap = 112;
			page_limit = (n < cap ? n : cap);
		end
	endfunction
	assign resident_a_generation = first_q + 1;
	assign resident_b_base = page_b;
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	assign resident_b_columns = sv2v_cast_9(page_columns);
	reg [15:0] col_q;
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	assign resident_b_group = sv2v_cast_5((col_q - page_first) >> 3);
	reg [15:0] n_q;
	reg [15:0] k_q;
	reg [15:0] ow_q;
	reg [15:0] count_q;
	reg [15:0] next_count_q;
	reg [15:0] oy_q;
	reg [15:0] ox_q;
	reg [15:0] next_oy_q;
	reg [31:0] next_ox_q;
	reg window_q;
	reg int16_q;
	reg slot_q;
	reg abort_q;
	reg current_ready;
	reg next_ready;
	reg [31:0] a_q;
	reg [31:0] b_q;
	reg [31:0] c_q;
	reg [31:0] as_q;
	reg [31:0] cs_q;
	reg [31:0] ab_step_q;
	reg [31:0] cb_step_q;
	reg [31:0] bg_step_q;
	reg [31:0] scratch_q;
	reg [31:0] scratch_step_q;
	reg [31:0] group_b_q;
	reg [31:0] group_c_q;
	reg [351:0] template_q;
	reg batch_q;
	reg [15:0] batch_rows_q;
	reg [15:0] batch_offset_q;
	reg [15:0] next_batch_rows_q;
	reg [31:0] batch_byte_offset_q;
	reg [31:0] next_batch_first_q;
	wire batch_last = !batch_q || ((batch_offset_q + count_q) >= batch_rows_q);
	wire [15:0] rows_in_batch_after = (batch_rows_q - batch_offset_q) - count_q;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	assign resident_next_a_rows = ((((((batch_q && !batch_last) && (count_q == 16)) && !int16_q) && !abort_q) && !cancel) && (as_q == sv2v_cast_32(k_q)) ? (rows_in_batch_after > 16 ? 5'd16 : sv2v_cast_5(rows_in_batch_after)) : 5'd0);
	wire has_next = next_first_q < rows_q;
	wire producer_has_next = (batch_q ? next_batch_first_q < rows_q : has_next);
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	function automatic [15:0] limit64;
		input reg [31:0] count;
		limit64 = (count > (int16_q ? 64 : 16) ? (int16_q ? 16'd64 : 16'd16) : sv2v_cast_16(count));
	endfunction
	function automatic [15:0] window_rows;
		input reg [31:0] left_rows;
		window_rows = (batch_q ? (left_rows > 64 ? 16'd64 : sv2v_cast_16(left_rows)) : limit64(left_rows));
	endfunction
	reg npu_live;
	reg Window_live;
	reg Window_is_next;
	reg cmd_presented;
	reg [31:0] npu_expected_cookie;
	reg [31:0] Window_expected_cookie;
	reg [31:0] npu_sequence;
	reg [31:0] Window_sequence;
	reg any_output_written;
	wire [15:0] group_n = (int16_q ? ((n_q - col_q) > 16'd8 ? 16'd8 : n_q - col_q) : page_columns);
	wire cmd_fire = npu_cmd_valid && npu_cmd_ready;
	wire comp_fire = npu_comp_valid && npu_comp_ready;
	wire Window_response = Window_rsp_valid && Window_rsp_ready;
	wire known_comp = npu_comp[136-:32] == npu_expected_cookie;
	function automatic [351:0] make_window;
		input reg [351:0] template_data;
		input reg [31:0] scratch;
		input reg [31:0] first;
		input reg [15:0] count;
		input reg [15:0] oy;
		input reg [15:0] ox;
		input reg flush;
		reg [351:0] result;
		begin
			result = template_data;
			result[32+:32] = scratch;
			result[64+:32] = first;
			result[176+:16] = oy;
			result[192+:32] = {count, ox};
			result[320+:32] = {31'd0, flush};
			make_window = result;
		end
	endfunction
	assign ready = (((!rst && (state == 4'd0)) && !protocol_poison) && !npu_comp_valid) && !Window_rsp_valid;
	assign busy = (state != 4'd0) || protocol_poison;
	assign npu_cmd_valid = (state == 4'd5) && (!abort_q || cmd_presented);
	assign npu_comp_ready = npu_live && !protocol_poison;
	assign Window_rsp_ready = Window_live && !protocol_poison;
	always @(*) begin
		if (_sv2v_0)
			;
		npu_cmd = 1'sb0;
		npu_cmd[347-:32] = (window_q ? (scratch_q + (slot_q ? scratch_step_q : 32'd0)) + batch_byte_offset_q : a_q);
		npu_cmd[315-:32] = group_b_q;
		npu_cmd[283-:32] = group_c_q;
		npu_cmd[251-:16] = count_q;
		npu_cmd[235-:16] = group_n;
		npu_cmd[219-:16] = k_q;
		npu_cmd[203] = int16_q;
		npu_cmd[202-:32] = as_q;
		npu_cmd[170-:32] = sv2v_cast_32(group_n) << (int16_q ? 1 : 0);
		npu_cmd[138-:32] = cs_q;
		npu_cmd[106-:2] = 2;
		npu_cmd[95-:32] = 32'sh80000000;
		npu_cmd[63-:32] = 32'sh7fffffff;
		npu_cmd[31-:32] = npu_sequence;
	end
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	always @(posedge clk) begin
		done_pulse <= 0;
		if (rst) begin
			batch_q <= 0;
			batch_rows_q <= 0;
			batch_offset_q <= 0;
			next_batch_rows_q <= 0;
			batch_byte_offset_q <= 0;
			next_batch_first_q <= 0;
			page_first <= 0;
			page_columns <= 0;
			page_b <= 0;
			page_c <= 0;
			initial_a <= 0;
			initial_c <= 0;
			state <= 4'd0;
			partial_output <= 0;
			protocol_poison <= 0;
			rejected_busy <= 0;
			error_code <= 0;
			error_source <= 0;
			completed_MACs <= 0;
			command_count <= 0;
			Window_count <= 0;
			model_q <= 0;
			frame_q <= 0;
			rows_q <= 0;
			first_q <= 0;
			next_first_q <= 0;
			n_q <= 0;
			k_q <= 0;
			ow_q <= 0;
			count_q <= 0;
			next_count_q <= 0;
			col_q <= 0;
			oy_q <= 0;
			ox_q <= 0;
			next_oy_q <= 0;
			next_ox_q <= 0;
			window_q <= 0;
			int16_q <= 0;
			slot_q <= 0;
			abort_q <= 0;
			current_ready <= 0;
			next_ready <= 0;
			a_q <= 0;
			b_q <= 0;
			c_q <= 0;
			as_q <= 0;
			cs_q <= 0;
			ab_step_q <= 0;
			cb_step_q <= 0;
			bg_step_q <= 0;
			scratch_q <= 0;
			scratch_step_q <= 0;
			group_b_q <= 0;
			group_c_q <= 0;
			template_q <= 0;
			npu_live <= 0;
			Window_live <= 0;
			Window_is_next <= 0;
			cmd_presented <= 0;
			npu_expected_cookie <= 0;
			Window_expected_cookie <= 0;
			npu_sequence <= 1;
			Window_sequence <= 1;
			Window_req_valid <= 0;
			Window_req_data <= 0;
			Window_req_cookie <= 0;
			any_output_written <= 0;
		end
		else begin
			if (start && !ready)
				rejected_busy <= 1;
			if ((cancel && busy) && !abort_q) begin
				abort_q <= 1;
				if (error_source == 0) begin
					error_source <= 3;
					error_code <= 8'he0;
				end
			end
			if (state != 4'd5)
				cmd_presented <= 0;
			else if (npu_cmd_valid)
				cmd_presented <= 1;
			if (Window_req_valid && Window_req_ready) begin
				if (Window_live) begin
					protocol_poison <= 1;
					state <= 4'd12;
					error_source <= 5;
					error_code <= 8'he1;
				end
				Window_req_valid <= 0;
				Window_live <= 1;
				Window_expected_cookie <= Window_req_cookie;
				Window_count <= Window_count + 1'b1;
			end
			if (Window_response) begin
				if (Window_rsp_cookie != Window_expected_cookie) begin
					protocol_poison <= 1;
					state <= 4'd12;
					error_source <= 5;
					error_code <= 8'he2;
				end
				else begin
					Window_live <= 0;
					if (Window_is_next)
						next_ready <= 1;
					else
						current_ready <= 1;
					if (Window_rsp_error != 0) begin
						error_source <= 2;
						error_code <= Window_rsp_error;
						abort_q <= 1;
					end
				end
			end
			if (comp_fire) begin
				if (!known_comp) begin
					protocol_poison <= 1;
					state <= 4'd12;
					error_source <= 5;
					error_code <= 8'he3;
				end
				else begin
					npu_live <= 0;
					if (npu_comp[104-:8] == 8'd0) begin
						completed_MACs <= completed_MACs + npu_comp[63-:64];
						any_output_written <= 1;
					end
					else begin
						error_source <= 1;
						error_code <= sv2v_cast_8(npu_comp[104-:8]);
						abort_q <= 1;
						any_output_written <= any_output_written | npu_comp[96];
					end
				end
			end
			case (state)
				4'd0:
					if (start && ready) begin
						model_q <= model_epoch;
						frame_q <= frame_epoch;
						rows_q <= total_rows;
						batch_q <= (((WINDOW_BATCH_ROWS == 64) && use_window) && !input_int16) && (scratch_stride >= (sv2v_cast_32(k_length) << 6));
						n_q <= columns;
						k_q <= k_length;
						ow_q <= output_width;
						window_q <= use_window;
						int16_q <= input_int16;
						initial_a <= a_base;
						initial_c <= c_base;
						a_q <= a_base;
						b_q <= b_base;
						c_q <= c_base;
						as_q <= a_stride;
						cs_q <= c_stride;
						ab_step_q <= a_block_step;
						cb_step_q <= c_block_step;
						bg_step_q <= b_group_step;
						scratch_q <= scratch_base;
						scratch_step_q <= scratch_stride;
						template_q <= window_template;
						abort_q <= 0;
						partial_output <= 0;
						error_code <= 0;
						error_source <= 0;
						rejected_busy <= 0;
						completed_MACs <= 0;
						command_count <= 0;
						Window_count <= 0;
						any_output_written <= 0;
						state <= 4'd1;
					end
				4'd1:
					if (((((((((((rows_q == 0) || (rows_q > 65535)) || (n_q == 0)) || (k_q == 0)) || (k_q > 1152)) || (as_q != (sv2v_cast_32(k_q) << (int16_q ? 1 : 0)))) || (cs_q != (sv2v_cast_32(n_q) << 2))) || (ab_step_q != (as_q << 6))) || (cb_step_q != (cs_q << 6))) || (bg_step_q != (sv2v_cast_32(k_q) << (int16_q ? 4 : 3)))) || (window_q && (((((ow_q == 0) || int16_q) || (scratch_q[5:0] != 0)) || (scratch_step_q[5:0] != 0)) || (scratch_step_q < (sv2v_cast_32(k_q) << 4))))) begin
						error_source <= 4;
						error_code <= 8'he4;
						state <= 4'd11;
					end
					else if (abort_q || cancel)
						state <= 4'd10;
					else begin
						batch_rows_q <= window_rows(rows_q);
						batch_offset_q <= 0;
						batch_byte_offset_q <= 0;
						first_q <= 0;
						count_q <= limit64(rows_q);
						col_q <= 0;
						oy_q <= 0;
						ox_q <= 0;
						slot_q <= 0;
						page_first <= 0;
						page_columns <= (int16_q ? n_q : page_limit(k_q, n_q));
						page_b <= b_q;
						page_c <= c_q;
						group_b_q <= b_q;
						group_c_q <= c_q;
						next_ready <= 0;
						current_ready <= !window_q;
						if (window_q) begin
							Window_req_valid <= 1;
							Window_req_data <= make_window(template_q, scratch_q, 0, window_rows(rows_q), 0, 0, 1);
							Window_req_cookie <= Window_sequence;
							Window_sequence <= Window_sequence + 1'b1;
							Window_is_next <= 0;
							state <= 4'd2;
						end
						else
							state <= 4'd3;
					end
				4'd2:
					if (abort_q || cancel)
						state <= 4'd10;
					else if (current_ready)
						state <= 4'd3;
				4'd3:
					if (abort_q || cancel)
						state <= 4'd10;
					else begin
						next_first_q <= first_q + sv2v_cast_32(count_q);
						next_count_q <= limit64((rows_q - first_q) - sv2v_cast_32(count_q));
						if (!batch_q || (batch_offset_q == 0)) begin
							next_batch_first_q <= first_q + sv2v_cast_32(batch_rows_q);
							next_batch_rows_q <= window_rows((rows_q - first_q) - sv2v_cast_32(batch_rows_q));
							next_oy_q <= oy_q;
							next_ox_q <= sv2v_cast_32(ox_q) + (batch_q ? sv2v_cast_32(batch_rows_q) : sv2v_cast_32(count_q));
							state <= 4'd4;
						end
						else
							state <= 4'd5;
					end
				4'd4:
					if (abort_q || cancel)
						state <= 4'd10;
					else if (window_q && (next_ox_q >= sv2v_cast_32(ow_q))) begin
						next_ox_q <= next_ox_q - sv2v_cast_32(ow_q);
						next_oy_q <= next_oy_q + 1'b1;
					end
					else
						state <= 4'd5;
				4'd5:
					if (abort_q && !cmd_presented)
						state <= 4'd10;
					else if (cmd_fire) begin
						npu_live <= 1;
						npu_expected_cookie <= npu_sequence;
						npu_sequence <= npu_sequence + 1'b1;
						command_count <= command_count + 1'b1;
						state <= (abort_q || cancel ? 4'd10 : 4'd6);
						if (((((((window_q && producer_has_next) && (!batch_q || (batch_offset_q == 0))) && !next_ready) && !Window_live) && !Window_req_valid) && !abort_q) && !cancel) begin
							Window_req_valid <= 1;
							Window_req_data <= make_window(template_q, scratch_q + (slot_q ? 32'd0 : scratch_step_q), (batch_q ? next_batch_first_q : next_first_q), (batch_q ? next_batch_rows_q : next_count_q), next_oy_q, sv2v_cast_16(next_ox_q), 0);
							Window_req_cookie <= Window_sequence;
							Window_sequence <= Window_sequence + 1'b1;
							Window_is_next <= 1;
						end
					end
				4'd6:
					if (abort_q || cancel)
						state <= 4'd10;
					else if (comp_fire && known_comp) begin
						if (npu_comp[104-:8] != 8'd0)
							state <= 4'd10;
						else if ((col_q + group_n) < (page_first + page_columns)) begin
							col_q <= col_q + group_n;
							group_b_q <= group_b_q + bg_step_q;
							group_c_q <= group_c_q + 32'd32;
							state <= 4'd5;
						end
						else if (has_next)
							state <= ((window_q && batch_last) && !next_ready ? 4'd7 : 4'd8);
						else if ((page_first + page_columns) < n_q)
							state <= 4'd9;
						else
							state <= 4'd11;
					end
				4'd7:
					if (abort_q || cancel)
						state <= 4'd10;
					else if (next_ready)
						state <= 4'd8;
				4'd8:
					if (abort_q || cancel)
						state <= 4'd10;
					else begin
						first_q <= next_first_q;
						count_q <= next_count_q;
						if (batch_q && !batch_last) begin
							batch_offset_q <= batch_offset_q + count_q;
							batch_byte_offset_q <= batch_byte_offset_q + (as_q << 4);
						end
						else begin
							oy_q <= next_oy_q;
							ox_q <= sv2v_cast_16(next_ox_q);
							slot_q <= !slot_q;
							batch_offset_q <= 0;
							batch_byte_offset_q <= 0;
							batch_rows_q <= next_batch_rows_q;
							next_ready <= 0;
						end
						a_q <= a_q + (int16_q ? ab_step_q : ab_step_q >> 2);
						c_q <= c_q + (int16_q ? cb_step_q : cb_step_q >> 2);
						group_c_q <= (c_q + (int16_q ? cb_step_q : cb_step_q >> 2)) + (sv2v_cast_32(page_first) << 2);
						group_b_q <= page_b;
						col_q <= page_first;
						state <= 4'd3;
					end
				4'd9:
					if (abort_q || cancel)
						state <= 4'd10;
					else begin
						page_first <= page_first + page_columns;
						page_columns <= page_limit(k_q, (n_q - page_first) - page_columns);
						page_b <= page_b + (sv2v_cast_32(page_columns) * sv2v_cast_32(k_q));
						page_c <= page_c + (sv2v_cast_32(page_columns) << 2);
						group_b_q <= page_b + (sv2v_cast_32(page_columns) * sv2v_cast_32(k_q));
						group_c_q <= page_c + (sv2v_cast_32(page_columns) << 2);
						a_q <= initial_a;
						c_q <= initial_c;
						first_q <= 0;
						count_q <= limit64(rows_q);
						batch_rows_q <= window_rows(rows_q);
						batch_offset_q <= 0;
						batch_byte_offset_q <= 0;
						col_q <= page_first + page_columns;
						oy_q <= 0;
						ox_q <= 0;
						slot_q <= 0;
						next_ready <= 0;
						current_ready <= !window_q;
						if (window_q) begin
							Window_req_valid <= 1;
							Window_req_data <= make_window(template_q, scratch_q, 0, window_rows(rows_q), 0, 0, 1);
							Window_req_cookie <= Window_sequence;
							Window_sequence <= Window_sequence + 1'b1;
							Window_is_next <= 0;
							state <= 4'd2;
						end
						else
							state <= 4'd3;
					end
				4'd10:
					if ((!npu_live && !Window_live) && !Window_req_valid) begin
						partial_output <= any_output_written;
						state <= 4'd11;
					end
				4'd11:
					if ((((npu_live || Window_live) || Window_req_valid) || npu_comp_valid) || Window_rsp_valid) begin
						protocol_poison <= 1;
						state <= 4'd12;
						error_source <= 5;
						error_code <= 8'he5;
					end
					else begin
						done_pulse <= 1;
						partial_output <= (error_source != 0) && any_output_written;
						state <= 4'd0;
					end
				4'd12:
					;
				default: begin
					protocol_poison <= 1;
					error_source <= 5;
					error_code <= 8'he6;
					state <= 4'd12;
				end
			endcase
			if ((Window_response && (Window_rsp_cookie != Window_expected_cookie)) || (comp_fire && !known_comp)) begin
				state <= 4'd12;
				done_pulse <= 0;
			end
			if ((busy && (state != 4'd12)) && (((npu_comp_valid && !npu_live) && !cmd_fire) || ((Window_rsp_valid && !Window_live) && !(Window_req_valid && Window_req_ready)))) begin
				protocol_poison <= 1;
				state <= 4'd12;
				done_pulse <= 0;
				error_source <= 5;
				error_code <= 8'he7;
			end
		end
	end
	initial _sv2v_0 = 0;
endmodule
module soc_conv_service (
	clk,
	rst,
	can_start,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	locked,
	protocol_poison,
	resident_enable,
	resident_model_epoch,
	resident_frame_epoch,
	resident_task_generation,
	resident_a_generation,
	resident_b_base,
	resident_next_a_rows,
	resident_b_columns,
	resident_b_group,
	legacy_addr,
	legacy_wdata,
	legacy_wen,
	legacy_mask,
	legacy_rdata,
	Window_req_valid,
	Window_req_ready,
	Window_req_addr,
	Window_req_write,
	Window_req_wdata,
	Window_req_wstrb,
	Window_rsp_valid,
	Window_rsp_ready,
	Window_rsp_rdata,
	Window_rsp_error
);
	reg _sv2v_0;
	parameter integer WINDOW_BATCH_ROWS = 64;
	input wire clk;
	input wire rst;
	input wire can_start;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output wire locked;
	output wire protocol_poison;
	output wire resident_enable;
	output wire [31:0] resident_model_epoch;
	output wire [31:0] resident_frame_epoch;
	output reg [31:0] resident_task_generation;
	output wire [31:0] resident_a_generation;
	output wire [31:0] resident_b_base;
	output wire [4:0] resident_next_a_rows;
	output wire [8:0] resident_b_columns;
	output wire [4:0] resident_b_group;
	output wire [31:0] legacy_addr;
	output wire [31:0] legacy_wdata;
	output wire legacy_wen;
	output wire [1:0] legacy_mask;
	input wire [31:0] legacy_rdata;
	output wire Window_req_valid;
	input wire Window_req_ready;
	output wire [15:0] Window_req_addr;
	output wire Window_req_write;
	output wire [31:0] Window_req_wdata;
	output wire [3:0] Window_req_wstrb;
	input wire Window_rsp_valid;
	output wire Window_rsp_ready;
	input wire [31:0] Window_rsp_rdata;
	input wire Window_rsp_error;
	(* syn_keep = 1 *) wire region_reset_control;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_control(
		.I0(rst),
		.Z(region_reset_control)
	);
	(* syn_keep = 1 *) wire region_reset_npu_client;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_npu_client(
		.I0(rst),
		.Z(region_reset_npu_client)
	);
	(* syn_keep = 1 *) wire region_reset_Window_client;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_Window_client(
		.I0(rst),
		.Z(region_reset_Window_client)
	);
	wire [31:0] cfg [0:30];
	reg [31:0] cfg_payload [0:30];
	reg [30:0] cfg_initialized;
	reg cfg_write_accepted;
	genvar _gv_cfg_word_1;
	generate
		for (_gv_cfg_word_1 = 0; _gv_cfg_word_1 < 31; _gv_cfg_word_1 = _gv_cfg_word_1 + 1) begin : g_cfg_visible
			localparam cfg_word = _gv_cfg_word_1;
			assign cfg[cfg_word] = (cfg_initialized[cfg_word] ? cfg_payload[cfg_word] : 32'd0);
		end
	endgenerate
	wire cfg_hit = (req_addr >= 16'h0140) && (req_addr <= 16'h01b8);
	wire hit = (req_addr[15:8] == 8'h01) && (req_addr[1:0] == 0);
	always @(*) begin
		if (_sv2v_0)
			;
		cfg_write_accepted = 1'b0;
		if (req_valid && req_ready) begin
			if (!hit || (req_write && (req_wstrb != 4'hf)))
				;
			else if (req_write) begin
				if (req_addr == 16'h0100)
					;
				else if (cfg_hit && !locked)
					cfg_write_accepted = 1'b1;
			end
		end
	end
	wire [5:0] cfg_index = req_addr[7:2] - 6'd16;
	always @(posedge clk) begin
		if (cfg_write_accepted)
			cfg_payload[cfg_index] <= req_wdata;
		if (rst)
			cfg_initialized <= 1'sb0;
		else if (cfg_write_accepted)
			cfg_initialized[cfg_index] <= 1'b1;
	end
	reg start_q;
	reg cancel_q;
	reg done_q;
	reg busy_q;
	reg rejected_q;
	wire g_ready;
	wire g_busy;
	wire g_done;
	wire g_partial;
	wire g_poison;
	wire g_rejected;
	wire [7:0] g_error;
	wire [2:0] g_source;
	wire [63:0] g_MACs;
	wire [31:0] g_commands;
	wire [31:0] g_Windows;
	wire n_cmd_valid;
	wire n_cmd_ready;
	wire n_comp_valid;
	wire n_comp_ready;
	wire n_busy;
	wire n_poison;
	wire [347:0] n_cmd;
	wire [136:0] n_comp;
	wire w_valid;
	wire w_ready;
	wire w_done_valid;
	wire w_done_ready;
	wire w_partial;
	wire w_busy;
	wire w_poison;
	wire [351:0] w_data;
	wire [31:0] w_cookie;
	wire [31:0] w_done_cookie;
	wire [7:0] w_error;
	wire [31:0] n_service_cycles;
	wire [31:0] n_command_ticks;
	wire [31:0] w_command_ticks;
	wire [31:0] w_read;
	wire [31:0] w_write;
	wire [31:0] w_active;
	wire [31:0] w_stall;
	wire [31:0] w_hits;
	wire [31:0] w_misses;
	wire reserved_ok = (((((cfg[4][31:16] == 0) && (cfg[5][31:2] == 0)) && (cfg[16] == 0)) && (cfg[17] == 0)) && (cfg[18] == 0)) && (cfg[19] == 0);
	assign resident_enable = locked && !cfg[5][1];
	assign resident_model_epoch = cfg[0];
	assign resident_frame_epoch = cfg[1];
	assign req_ready = !rst && !rsp_valid;
	assign protocol_poison = (g_poison || n_poison) || w_poison;
	assign locked = busy_q || protocol_poison;
	soc_conv_microsequencer #(.WINDOW_BATCH_ROWS(WINDOW_BATCH_ROWS)) control(
		.clk(clk),
		.rst(region_reset_control),
		.start(start_q),
		.cancel(cancel_q),
		.model_epoch(cfg[0]),
		.frame_epoch(cfg[1]),
		.total_rows(cfg[2]),
		.columns(cfg[3][15:0]),
		.k_length(cfg[3][31:16]),
		.output_width(cfg[4][15:0]),
		.use_window(cfg[5][0]),
		.input_int16(cfg[5][1]),
		.a_base(cfg[6]),
		.b_base(cfg[7]),
		.c_base(cfg[8]),
		.a_stride(cfg[9]),
		.c_stride(cfg[10]),
		.a_block_step(cfg[11]),
		.c_block_step(cfg[12]),
		.b_group_step(cfg[13]),
		.scratch_base(cfg[14]),
		.scratch_stride(cfg[15]),
		.window_template({cfg[30], cfg[29], cfg[28], cfg[27], cfg[26], cfg[25], cfg[24], cfg[23], cfg[22], cfg[21], cfg[20]}),
		.resident_a_generation(resident_a_generation),
		.resident_b_base(resident_b_base),
		.resident_b_columns(resident_b_columns),
		.resident_b_group(resident_b_group),
		.resident_next_a_rows(resident_next_a_rows),
		.ready(g_ready),
		.busy(g_busy),
		.done_pulse(g_done),
		.partial_output(g_partial),
		.protocol_poison(g_poison),
		.rejected_busy(g_rejected),
		.error_code(g_error),
		.error_source(g_source),
		.completed_MACs(g_MACs),
		.command_count(g_commands),
		.Window_count(g_Windows),
		.npu_cmd_valid(n_cmd_valid),
		.npu_cmd_ready(n_cmd_ready),
		.npu_cmd(n_cmd),
		.npu_comp_valid(n_comp_valid),
		.npu_comp_ready(n_comp_ready),
		.npu_comp(n_comp),
		.Window_req_valid(w_valid),
		.Window_req_ready(w_ready),
		.Window_req_data(w_data),
		.Window_req_cookie(w_cookie),
		.Window_rsp_valid(w_done_valid),
		.Window_rsp_ready(w_done_ready),
		.Window_rsp_cookie(w_done_cookie),
		.Window_rsp_error(w_error),
		.Window_rsp_partial(w_partial)
	);
	soc_npu_legacy_descriptor_port npu_client(
		.clk(clk),
		.rst(region_reset_npu_client),
		.enable(locked),
		.clear_counters(start_q),
		.cmd_valid(n_cmd_valid),
		.cmd_ready(n_cmd_ready),
		.cmd(n_cmd),
		.comp_valid(n_comp_valid),
		.comp_ready(n_comp_ready),
		.comp(n_comp),
		.legacy_addr(legacy_addr),
		.legacy_wdata(legacy_wdata),
		.legacy_wen(legacy_wen),
		.legacy_mask(legacy_mask),
		.legacy_rdata(legacy_rdata),
		.busy(n_busy),
		.protocol_poison(n_poison),
		.completed_service_cycles(n_service_cycles),
		.total_command_ticks(n_command_ticks)
	);
	soc_window_descriptor_port Window_client(
		.clk(clk),
		.rst(region_reset_Window_client),
		.clear_counters(start_q),
		.job_valid(w_valid),
		.job_ready(w_ready),
		.job_data(w_data),
		.job_cookie(w_cookie),
		.expected_K(cfg[3][31:16]),
		.done_valid(w_done_valid),
		.done_ready(w_done_ready),
		.done_cookie(w_done_cookie),
		.done_error(w_error),
		.done_partial(w_partial),
		.req_valid(Window_req_valid),
		.req_ready(Window_req_ready),
		.req_addr(Window_req_addr),
		.req_write(Window_req_write),
		.req_wdata(Window_req_wdata),
		.req_wstrb(Window_req_wstrb),
		.rsp_valid(Window_rsp_valid),
		.rsp_ready(Window_rsp_ready),
		.rsp_rdata(Window_rsp_rdata),
		.rsp_error(Window_rsp_error),
		.busy(w_busy),
		.protocol_poison(w_poison),
		.total_read_bytes(w_read),
		.total_write_bytes(w_write),
		.total_active_UI(w_active),
		.total_stall_UI(w_stall),
		.total_hits(w_hits),
		.total_misses(w_misses),
		.total_command_ticks(w_command_ticks)
	);
	always @(posedge clk) begin
		start_q <= 0;
		cancel_q <= 0;
		if (rst) begin
			resident_task_generation <= 0;
			rsp_valid <= 0;
			rsp_rdata <= 0;
			rsp_error <= 0;
			busy_q <= 0;
			done_q <= 0;
			rejected_q <= 0;
		end
		else begin
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			if (g_done) begin
				if ((n_busy || w_busy) || g_busy)
					rejected_q <= 1;
				else begin
					busy_q <= 0;
					done_q <= 1;
				end
			end
			if (req_valid && req_ready) begin
				rsp_valid <= 1;
				rsp_rdata <= 0;
				rsp_error <= 0;
				if (!hit || (req_write && (req_wstrb != 4'hf))) begin
					rsp_error <= 1;
					rejected_q <= 1;
				end
				else if (req_write) begin
					if (req_addr == 16'h0100) begin
						if ((((((((req_wdata == 1) && !locked) && can_start) && g_ready) && !n_busy) && !w_busy) && reserved_ok) && (resident_task_generation != 32'hffffffff)) begin
							resident_task_generation <= resident_task_generation + 1'b1;
							start_q <= 1;
							busy_q <= 1;
							done_q <= 0;
							rejected_q <= 0;
						end
						else if (((req_wdata == 2) && busy_q) && !protocol_poison)
							cancel_q <= 1;
						else begin
							rsp_error <= 1;
							rejected_q <= 1;
						end
					end
					else if (cfg_hit && !locked)
						;
					else begin
						rsp_error <= 1;
						rejected_q <= 1;
					end
				end
				else if (cfg_hit)
					rsp_rdata <= cfg[cfg_index];
				else
					case (req_addr)
						16'h0100: rsp_rdata <= 0;
						16'h0104: rsp_rdata <= {16'd0, protocol_poison, rejected_q, g_source, g_error, g_partial, done_q, busy_q};
						16'h0108: rsp_rdata <= 32'h32584547;
						16'h010c: rsp_rdata <= g_MACs[31:0];
						16'h0110: rsp_rdata <= g_MACs[63:32];
						16'h0114: rsp_rdata <= g_commands;
						16'h0118: rsp_rdata <= g_Windows;
						16'h011c: rsp_rdata <= n_service_cycles;
						16'h0120: rsp_rdata <= w_read;
						16'h0124: rsp_rdata <= w_write;
						16'h0128: rsp_rdata <= w_active;
						16'h012c: rsp_rdata <= w_stall;
						16'h0130: rsp_rdata <= w_hits;
						16'h0134: rsp_rdata <= w_misses;
						16'h0138: rsp_rdata <= w_command_ticks;
						16'h013c: rsp_rdata <= n_command_ticks;
						16'h01bc: rsp_rdata <= WINDOW_BATCH_ROWS;
						default: begin
							rsp_error <= 1;
							rejected_q <= 1;
						end
					endcase
			end
		end
	end
	initial _sv2v_0 = 0;
endmodule
module soc_npu_legacy_descriptor_port (
	clk,
	rst,
	enable,
	clear_counters,
	cmd_valid,
	cmd_ready,
	cmd,
	comp_valid,
	comp_ready,
	comp,
	legacy_addr,
	legacy_wdata,
	legacy_wen,
	legacy_mask,
	legacy_rdata,
	busy,
	protocol_poison,
	completed_service_cycles,
	total_command_ticks
);
	reg _sv2v_0;
	input wire clk;
	input wire rst;
	input wire enable;
	input wire clear_counters;
	input wire cmd_valid;
	output wire cmd_ready;
	input wire [347:0] cmd;
	output wire comp_valid;
	input wire comp_ready;
	output wire [136:0] comp;
	output reg [31:0] legacy_addr;
	output reg [31:0] legacy_wdata;
	output reg legacy_wen;
	output wire [1:0] legacy_mask;
	input wire [31:0] legacy_rdata;
	output wire busy;
	output reg protocol_poison;
	output reg [31:0] completed_service_cycles;
	output reg [31:0] total_command_ticks;
	reg [3:0] state;
	reg [347:0] cmd_q;
	reg [136:0] comp_q;
	reg [4:0] word_q;
	reg [2:0] result_q;
	reg [31:0] error_status_q;
	reg [31:0] job_ticks;
	localparam [31:0] BASE = 32'h80200200;
	assign cmd_ready = ((!rst && enable) && (state == 4'd0)) && !protocol_poison;
	assign comp_valid = (!rst && (state == 4'd13)) && !protocol_poison;
	assign comp = comp_q;
	assign busy = state != 4'd0;
	assign legacy_mask = 2;
	always @(*) begin
		if (_sv2v_0)
			;
		legacy_addr = BASE + 32'h0000000c;
		legacy_wdata = 0;
		legacy_wen = 0;
		if (state == 4'd4) begin
			legacy_wen = 1;
			case (word_q)
				0: begin
					legacy_addr = BASE + 32'h00000014;
					legacy_wdata = 3;
				end
				1: begin
					legacy_addr = BASE + 32'h00000078;
					legacy_wdata = 32'h00000fff;
				end
				2: begin
					legacy_addr = BASE + 32'h00000010;
					legacy_wdata = 3;
				end
				3: begin
					legacy_addr = BASE + 32'h00000020;
					legacy_wdata = cmd_q[347-:32];
				end
				4: begin
					legacy_addr = BASE + 32'h00000024;
					legacy_wdata = cmd_q[315-:32];
				end
				5: begin
					legacy_addr = BASE + 32'h00000028;
					legacy_wdata = cmd_q[283-:32];
				end
				6: begin
					legacy_addr = BASE + 32'h0000002c;
					legacy_wdata = {cmd_q[235-:16], cmd_q[251-:16]};
				end
				7: begin
					legacy_addr = BASE + 32'h00000030;
					legacy_wdata = {15'd0, cmd_q[203], cmd_q[219-:16]};
				end
				8: begin
					legacy_addr = BASE + 32'h00000034;
					legacy_wdata = cmd_q[202-:32];
				end
				9: begin
					legacy_addr = BASE + 32'h00000038;
					legacy_wdata = cmd_q[170-:32];
				end
				10: begin
					legacy_addr = BASE + 32'h0000003c;
					legacy_wdata = cmd_q[138-:32];
				end
				11: begin
					legacy_addr = BASE + 32'h00000040;
					legacy_wdata = {21'd0, cmd_q[101-:6], cmd_q[102], cmd_q[104-:2], cmd_q[106-:2]};
				end
				12: begin
					legacy_addr = BASE + 32'h00000044;
					legacy_wdata = $signed(cmd_q[95-:32]);
				end
				13: begin
					legacy_addr = BASE + 32'h00000048;
					legacy_wdata = $signed(cmd_q[63-:32]);
				end
				14: begin
					legacy_addr = BASE + 32'h0000004c;
					legacy_wdata = cmd_q[31-:32];
				end
				15: begin
					legacy_addr = BASE + 32'h00000050;
					legacy_wdata = 1;
				end
				default: legacy_wen = 0;
			endcase
		end
		if (((state == 4'd8) || (state == 4'd9)) || (state == 4'd10))
			legacy_addr = (result_q == 5 ? BASE + 32'h00000078 : (BASE + 32'h00000060) + {27'd0, result_q, 2'd0});
		if (state == 4'd11) begin
			legacy_addr = BASE + 32'h00000074;
			legacy_wdata = 1;
			legacy_wen = 1;
		end
		if (state == 4'd12) begin
			legacy_addr = BASE + 32'h00000014;
			legacy_wdata = 3;
			legacy_wen = 1;
		end
		if ((!enable || rst) || protocol_poison)
			legacy_wen = 0;
	end
	always @(posedge clk)
		if (rst) begin
			state <= 4'd0;
			cmd_q <= 1'sb0;
			comp_q <= 1'sb0;
			word_q <= 0;
			result_q <= 0;
			error_status_q <= 0;
			protocol_poison <= 0;
			completed_service_cycles <= 0;
			total_command_ticks <= 0;
			job_ticks <= 0;
		end
		else begin
			if (((state != 4'd0) && (state != 4'd13)) && (state != 4'd14))
				job_ticks <= job_ticks + 1'b1;
			if (!enable && (state != 4'd0)) begin
				protocol_poison <= 1;
				state <= 4'd14;
			end
			else
				case (state)
					4'd0:
						if (cmd_valid && cmd_ready) begin
							cmd_q <= cmd;
							comp_q <= 1'sb0;
							error_status_q <= 0;
							job_ticks <= 0;
							state <= 4'd1;
						end
					4'd1: state <= 4'd2;
					4'd2: state <= 4'd3;
					4'd3:
						if ((legacy_rdata & 32'h00000047) != 5) begin
							protocol_poison <= 1;
							state <= 4'd14;
						end
						else begin
							word_q <= 0;
							state <= 4'd4;
						end
					4'd4:
						if (word_q == 15)
							state <= 4'd5;
						else
							word_q <= word_q + 1'b1;
					4'd5: state <= 4'd6;
					4'd6: state <= 4'd7;
					4'd7:
						if (legacy_rdata[6]) begin
							result_q <= 0;
							state <= 4'd8;
						end
						else
							state <= 4'd5;
					4'd8: state <= 4'd9;
					4'd9: state <= 4'd10;
					4'd10: begin
						case (result_q)
							0: comp_q[136-:32] <= legacy_rdata;
							1: begin
								comp_q[104-:8] <= legacy_rdata[7:0];
								comp_q[96] <= legacy_rdata[8];
								if ((legacy_rdata[8] && (legacy_rdata[7:0] == 0)) || (legacy_rdata[31:9] != 0))
									comp_q[104-:8] <= 8'd11;
							end
							2: comp_q[95-:32] <= legacy_rdata;
							3: comp_q[31:0] <= legacy_rdata;
							4: comp_q[63:32] <= legacy_rdata;
							5: begin
								error_status_q <= legacy_rdata;
								if ((legacy_rdata != 0) && (comp_q[104-:8] == 8'd0))
									comp_q[104-:8] <= 8'd11;
							end
							default: begin
								protocol_poison <= 1;
								state <= 4'd14;
							end
						endcase
						if (result_q == 5)
							state <= 4'd11;
						else begin
							result_q <= result_q + 1'b1;
							state <= 4'd8;
						end
					end
					4'd11: state <= 4'd12;
					4'd12: begin
						completed_service_cycles <= completed_service_cycles + comp_q[95-:32];
						state <= 4'd13;
					end
					4'd13:
						if (comp_ready) begin
							state <= 4'd0;
							total_command_ticks <= total_command_ticks + job_ticks;
						end
					4'd14:
						;
					default: begin
						protocol_poison <= 1;
						state <= 4'd14;
					end
				endcase
			if (clear_counters) begin
				if (state != 4'd0) begin
					protocol_poison <= 1;
					state <= 4'd14;
				end
				else begin
					completed_service_cycles <= 0;
					total_command_ticks <= 0;
					job_ticks <= 0;
				end
			end
		end
	initial _sv2v_0 = 0;
endmodule
module soc_window_descriptor_port (
	clk,
	rst,
	clear_counters,
	job_valid,
	job_ready,
	job_data,
	job_cookie,
	expected_K,
	done_valid,
	done_ready,
	done_cookie,
	done_error,
	done_partial,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	busy,
	protocol_poison,
	total_read_bytes,
	total_write_bytes,
	total_active_UI,
	total_stall_UI,
	total_hits,
	total_misses,
	total_command_ticks
);
	reg _sv2v_0;
	input wire clk;
	input wire rst;
	input wire clear_counters;
	input wire job_valid;
	output wire job_ready;
	input wire [351:0] job_data;
	input wire [31:0] job_cookie;
	input wire [15:0] expected_K;
	output wire done_valid;
	input wire done_ready;
	output wire [31:0] done_cookie;
	output wire [7:0] done_error;
	output wire done_partial;
	output wire req_valid;
	input wire req_ready;
	output reg [15:0] req_addr;
	output reg req_write;
	output reg [31:0] req_wdata;
	output wire [3:0] req_wstrb;
	input wire rsp_valid;
	output wire rsp_ready;
	input wire [31:0] rsp_rdata;
	input wire rsp_error;
	output wire busy;
	output reg protocol_poison;
	output reg [31:0] total_read_bytes;
	output reg [31:0] total_write_bytes;
	output reg [31:0] total_active_UI;
	output reg [31:0] total_stall_UI;
	output reg [31:0] total_hits;
	output reg [31:0] total_misses;
	output reg [31:0] total_command_ticks;
	reg [2:0] state;
	reg [351:0] words_q;
	reg [31:0] cookie_q;
	reg [31:0] expected_bytes_q;
	reg [31:0] status_q;
	reg [4:0] operation_q;
	reg [7:0] error_q;
	reg partial_q;
	reg started_q;
	reg [31:0] job_ticks;
	assign job_ready = (!rst && (state == 3'd0)) && !protocol_poison;
	assign done_valid = (!rst && (state == 3'd3)) && !protocol_poison;
	assign done_cookie = cookie_q;
	assign done_error = error_q;
	assign done_partial = partial_q;
	assign busy = state != 3'd0;
	assign req_valid = (!rst && (state == 3'd1)) && !protocol_poison;
	assign rsp_ready = (!rst && (state == 3'd2)) && !protocol_poison;
	assign req_wstrb = 4'hf;
	always @(*) begin
		if (_sv2v_0)
			;
		req_addr = 16'h0330;
		req_write = 0;
		req_wdata = 0;
		if ((operation_q >= 1) && (operation_q <= 11)) begin
			req_addr = 16'h0300 + {9'd0, operation_q, 2'd0};
			req_write = 1;
			req_wdata = words_q[32 * (operation_q[3:0] - 4'd1)+:32];
		end
		if (operation_q == 12) begin
			req_addr = 16'h0300;
			req_write = 1;
			req_wdata = 1;
		end
		if (operation_q >= 14)
			req_addr = 16'h0334 + {9'd0, operation_q - 5'd14, 2'd0};
	end
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			state <= 3'd0;
			words_q <= 0;
			cookie_q <= 0;
			expected_bytes_q <= 0;
			status_q <= 0;
			operation_q <= 0;
			error_q <= 0;
			partial_q <= 0;
			started_q <= 0;
			protocol_poison <= 0;
			total_read_bytes <= 0;
			total_write_bytes <= 0;
			total_active_UI <= 0;
			total_stall_UI <= 0;
			total_hits <= 0;
			total_misses <= 0;
			total_command_ticks <= 0;
			job_ticks <= 0;
		end
		else begin
			if (((state != 3'd0) && (state != 3'd3)) && (state != 3'd4))
				job_ticks <= job_ticks + 1'b1;
			case (state)
				3'd0:
					if (job_valid && job_ready) begin
						words_q <= job_data;
						cookie_q <= job_cookie;
						expected_bytes_q <= sv2v_cast_32(job_data[208+:16]) * sv2v_cast_32(expected_K);
						error_q <= 0;
						partial_q <= 0;
						started_q <= 0;
						job_ticks <= 0;
						operation_q <= 0;
						state <= 3'd1;
					end
				3'd1:
					if (req_ready)
						state <= 3'd2;
				3'd2:
					if (rsp_valid) begin
						if (rsp_error) begin
							if (started_q) begin
								protocol_poison <= 1;
								state <= 3'd4;
							end
							else begin
								error_q <= 8'he8;
								state <= 3'd3;
							end
						end
						else if (operation_q == 0) begin
							if (rsp_rdata[16] || !rsp_rdata[15]) begin
								error_q <= 8'he9;
								state <= 3'd3;
							end
							else if (!rsp_rdata[17])
								state <= 3'd1;
							else begin
								operation_q <= 1;
								state <= 3'd1;
							end
						end
						else if (operation_q <= 11) begin
							operation_q <= operation_q + 1'b1;
							state <= 3'd1;
						end
						else if (operation_q == 12) begin
							started_q <= 1;
							operation_q <= 13;
							state <= 3'd1;
						end
						else if (operation_q == 13) begin
							if (!rsp_rdata[1])
								state <= 3'd1;
							else begin
								status_q <= rsp_rdata;
								partial_q <= rsp_rdata[13];
								if (rsp_rdata[12:5] != 0)
									error_q <= rsp_rdata[12:5];
								else if (((rsp_rdata[14] || rsp_rdata[16]) || !rsp_rdata[13]) || rsp_rdata[0])
									error_q <= 8'hea;
								operation_q <= 14;
								state <= 3'd1;
							end
						end
						else begin
							case (operation_q)
								14: begin
									total_read_bytes <= total_read_bytes + rsp_rdata;
									if ((rsp_rdata[3:0] != 0) && (error_q == 0))
										error_q <= 8'heb;
								end
								15: begin
									total_write_bytes <= total_write_bytes + rsp_rdata;
									if ((rsp_rdata != expected_bytes_q) && (error_q == 0))
										error_q <= 8'hec;
								end
								16: total_hits <= total_hits + rsp_rdata;
								17: total_misses <= total_misses + rsp_rdata;
								18: total_active_UI <= total_active_UI + rsp_rdata;
								19: total_stall_UI <= total_stall_UI + rsp_rdata;
								default:
									;
							endcase
							if (operation_q == 19)
								state <= 3'd3;
							else begin
								operation_q <= operation_q + 1'b1;
								state <= 3'd1;
							end
						end
					end
				3'd3:
					if (done_ready) begin
						state <= 3'd0;
						started_q <= 0;
						total_command_ticks <= total_command_ticks + job_ticks;
					end
				3'd4:
					;
				default: begin
					protocol_poison <= 1;
					state <= 3'd4;
				end
			endcase
			if (clear_counters) begin
				if (state != 3'd0) begin
					protocol_poison <= 1;
					state <= 3'd4;
				end
				else begin
					total_read_bytes <= 0;
					total_write_bytes <= 0;
					total_active_UI <= 0;
					total_stall_UI <= 0;
					total_hits <= 0;
					total_misses <= 0;
					total_command_ticks <= 0;
					job_ticks <= 0;
				end
			end
		end
	initial _sv2v_0 = 0;
endmodule
module npu_resident_ab (
	clk,
	rst,
	a_begin,
	a_slot,
	a_identity,
	a_rows,
	a_k_length,
	a_begin_ready,
	a_reuse_hit,
	a_write_valid,
	a_write_row,
	a_write_k,
	a_write_word,
	a_write_ready,
	a_commit,
	a_real_responses_retired,
	a_abort,
	b_begin,
	b_identity,
	b_columns,
	b_k_length,
	b_begin_ready,
	b_reuse_hit,
	b_write_valid,
	b_write_group,
	b_write_k,
	b_write_pair,
	b_write_ready,
	b_commit,
	b_real_responses_retired,
	b_abort,
	invalidate_a,
	invalidate_a_slot,
	invalidate_b,
	claim,
	claim_a_slot,
	claim_m16,
	claim_n8,
	expected_a_identity,
	expected_b_identity,
	claim_ready,
	release_compute,
	read_valid,
	read_k,
	read_ready,
	vector_valid,
	a_vector,
	b_vector,
	compute_active,
	protocol_poison,
	a_owners,
	b_owner,
	a_words_written,
	b_words_written,
	a_reuse_count,
	b_reuse_count
);
	parameter signed [31:0] A_ROWS_PER_SLOT = 16;
	parameter signed [31:0] B_PAIR_ADDR_W = 13;
	input wire clk;
	input wire rst;
	input wire a_begin;
	input wire a_slot;
	input wire [255:0] a_identity;
	input wire [5:0] a_rows;
	input wire [10:0] a_k_length;
	output wire a_begin_ready;
	output reg a_reuse_hit;
	input wire a_write_valid;
	input wire [4:0] a_write_row;
	input wire [10:0] a_write_k;
	input wire [127:0] a_write_word;
	output wire a_write_ready;
	input wire a_commit;
	input wire a_real_responses_retired;
	input wire a_abort;
	input wire b_begin;
	input wire [255:0] b_identity;
	input wire [8:0] b_columns;
	input wire [10:0] b_k_length;
	output wire b_begin_ready;
	output reg b_reuse_hit;
	input wire b_write_valid;
	input wire [4:0] b_write_group;
	input wire [10:0] b_write_k;
	input wire [127:0] b_write_pair;
	output wire b_write_ready;
	input wire b_commit;
	input wire b_real_responses_retired;
	input wire b_abort;
	input wire invalidate_a;
	input wire invalidate_a_slot;
	input wire invalidate_b;
	input wire claim;
	input wire claim_a_slot;
	input wire claim_m16;
	input wire [4:0] claim_n8;
	input wire [255:0] expected_a_identity;
	input wire [255:0] expected_b_identity;
	output wire claim_ready;
	input wire release_compute;
	input wire read_valid;
	input wire [10:0] read_k;
	output wire read_ready;
	output reg vector_valid;
	output wire [255:0] a_vector;
	output wire [127:0] b_vector;
	output wire compute_active;
	output reg protocol_poison;
	output wire [3:0] a_owners;
	output wire [1:0] b_owner;
	output reg [31:0] a_words_written;
	output reg [31:0] b_words_written;
	output reg [31:0] a_reuse_count;
	output reg [31:0] b_reuse_count;
	localparam [1:0] EMPTY = 0;
	localparam [1:0] FILLING = 1;
	localparam [1:0] READY = 2;
	localparam [1:0] COMPUTE = 3;
	localparam signed [31:0] A_ADDR_W = (A_ROWS_PER_SLOT == 32 ? 9 : 8);
	initial if (((A_ROWS_PER_SLOT != 16) && (A_ROWS_PER_SLOT != 32)) || ((B_PAIR_ADDR_W != 13) && (B_PAIR_ADDR_W != 14))) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_resident_ab.sv:56:4 - npu_resident_ab.<unnamed_block>.<unnamed_block>\n msg: ", $time, "RESIDENT_FIXED_BANK_CAPACITY_UNSUPPORTED");
		$finish(1);
	end
	reg [1:0] ast [0:1];
	reg [1:0] bst;
	reg [255:0] ak [0:1];
	reg [255:0] bk;
	reg [5:0] ar [0:1];
	reg [10:0] alen [0:1];
	reg [10:0] blen;
	reg [8:0] bc;
	reg [4:0] next_arow [0:1];
	reg [10:0] next_ak [0:1];
	reg [10:0] next_bk;
	reg [4:0] next_bg;
	reg [B_PAIR_ADDR_W - 1:0] b_linear_q;
	reg [B_PAIR_ADDR_W - 1:0] active_b_base;
	reg [B_PAIR_ADDR_W - 1:0] b_group_base [0:31];
	function automatic [16:0] sv2v_cast_17;
		input reg [16:0] inp;
		sv2v_cast_17 = inp;
	endfunction
	wire [16:0] b_required_words = sv2v_cast_17(({1'b0, b_columns} + 10'd7) >> 3) * sv2v_cast_17(({1'b0, b_k_length} + 12'd1) >> 1);
	reg afull [0:1];
	reg bfull;
	reg active_slot;
	reg active_m16;
	reg [4:0] active_rows;
	reg [3:0] active_cols;
	reg [10:0] active_k;
	reg [3:0] a_sub_q;
	reg b_sub_q;
	wire a_shape_ok = (((a_rows != 0) && (a_rows <= A_ROWS_PER_SLOT)) && (a_k_length != 0)) && (a_k_length <= 1152);
	wire b_shape_ok = ((((b_columns != 0) && (b_columns <= 256)) && (b_k_length != 0)) && (b_k_length <= 1152)) && (b_required_words <= (17'sd1 << B_PAIR_ADDR_W));
	wire a_hit = (((ast[a_slot] == READY) && (ak[a_slot] == a_identity)) && (ar[a_slot] == a_rows)) && (alen[a_slot] == a_k_length);
	wire b_hit = (((bst == READY) && (bk == b_identity)) && (bc == b_columns)) && (blen == b_k_length);
	assign a_begin_ready = ((!rst && !protocol_poison) && (ast[a_slot] != COMPUTE)) && (ast[a_slot] != FILLING);
	assign b_begin_ready = ((!rst && !protocol_poison) && (bst != COMPUTE)) && (bst != FILLING);
	assign a_write_ready = (((((!rst && !protocol_poison) && (ast[a_slot] == FILLING)) && !afull[a_slot]) && (a_write_row == next_arow[a_slot])) && (a_write_k == next_ak[a_slot])) && (a_write_k[3:0] == 0);
	assign b_write_ready = (((((!rst && !protocol_poison) && (bst == FILLING)) && !bfull) && (b_write_group == next_bg)) && (b_write_k == next_bk)) && (b_write_k[0] == 0);
	wire aw = a_write_valid && a_write_ready;
	wire bw = b_write_valid && b_write_ready;
	wire [8:0] claim_col_first = {claim_n8, 3'b000};
	wire [5:0] claim_row_first = (claim_m16 ? 6'd16 : 6'd0);
	assign compute_active = bst == COMPUTE;
	assign claim_ready = (((((((((!rst && !protocol_poison) && !compute_active) && (ast[claim_a_slot] == READY)) && (bst == READY)) && (ak[claim_a_slot] == expected_a_identity)) && (bk == expected_b_identity)) && (alen[claim_a_slot] == blen)) && (ar[claim_a_slot] > claim_row_first)) && (bc > claim_col_first)) && ((A_ROWS_PER_SLOT == 32) || !claim_m16);
	assign read_ready = ((!rst && !protocol_poison) && compute_active) && (read_k < active_k);
	wire rf = read_valid && read_ready;
	wire [A_ADDR_W - 1:0] a_wa;
	wire [A_ADDR_W - 1:0] a_ra;
	generate
		if (A_ROWS_PER_SLOT == 32) begin : g_a32_address
			assign a_wa = {a_slot, a_write_row[4], a_write_k[10:4]};
			assign a_ra = {active_slot, active_m16, read_k[10:4]};
		end
		else begin : g_a16_address
			assign a_wa = {a_slot, a_write_k[10:4]};
			assign a_ra = {active_slot, read_k[10:4]};
		end
	endgenerate
	wire [B_PAIR_ADDR_W - 1:0] b_wa = b_linear_q;
	function automatic [B_PAIR_ADDR_W - 1:0] sv2v_cast_BC16B;
		input reg [B_PAIR_ADDR_W - 1:0] inp;
		sv2v_cast_BC16B = inp;
	endfunction
	wire [B_PAIR_ADDR_W - 1:0] b_ra = active_b_base + sv2v_cast_BC16B(read_k[10:1]);
	assign a_owners = {ast[1], ast[0]};
	assign b_owner = bst;
	genvar _gv_row_1;
	function automatic signed [3:0] sv2v_cast_4_signed;
		input reg signed [3:0] inp;
		sv2v_cast_4_signed = inp;
	endfunction
	generate
		for (_gv_row_1 = 0; _gv_row_1 < 16; _gv_row_1 = _gv_row_1 + 1) begin : g_a
			localparam row = _gv_row_1;
			wire [127:0] word_q;
			npu_resident_word_ram #(
				.WIDTH(128),
				.ADDR_W(A_ADDR_W)
			) ram(
				.clk(clk),
				.wr_en(aw && (a_write_row[3:0] == sv2v_cast_4_signed(row))),
				.wr_addr(a_wa),
				.wr_data(a_write_word),
				.rd_en(rf),
				.rd_addr(a_ra),
				.rd_data(word_q)
			);
			wire [7:0] byte_q = word_q[8 * a_sub_q+:8];
			assign a_vector[row * 16+:16] = (vector_valid && (active_rows > row) ? {{8 {byte_q[7]}}, byte_q} : 16'd0);
		end
	endgenerate
	genvar _gv_col_1;
	generate
		for (_gv_col_1 = 0; _gv_col_1 < 8; _gv_col_1 = _gv_col_1 + 1) begin : g_b
			localparam col = _gv_col_1;
			wire [15:0] pair_q;
			npu_resident_word_ram #(
				.WIDTH(16),
				.ADDR_W(B_PAIR_ADDR_W)
			) ram(
				.clk(clk),
				.wr_en(bw),
				.wr_addr(b_wa),
				.wr_data({b_write_pair[64 + (col * 8)+:8], b_write_pair[col * 8+:8]}),
				.rd_en(rf),
				.rd_addr(b_ra),
				.rd_data(pair_q)
			);
			wire [7:0] byte_q = (b_sub_q ? pair_q[15:8] : pair_q[7:0]);
			assign b_vector[col * 16+:16] = (vector_valid && (active_cols > col) ? {{8 {byte_q[7]}}, byte_q} : 16'd0);
		end
	endgenerate
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	always @(posedge clk) begin
		a_reuse_hit <= 0;
		b_reuse_hit <= 0;
		vector_valid <= 0;
		if (rst) begin
			begin : sv2v_autoblock_1
				integer s;
				for (s = 0; s < 2; s = s + 1)
					begin
						ast[s] <= EMPTY;
						ak[s] <= 0;
						ar[s] <= 0;
						alen[s] <= 0;
						next_arow[s] <= 0;
						next_ak[s] <= 0;
						afull[s] <= 0;
					end
			end
			bst <= EMPTY;
			bk <= 0;
			bc <= 0;
			blen <= 0;
			next_bg <= 0;
			next_bk <= 0;
			bfull <= 0;
			active_slot <= 0;
			active_m16 <= 0;
			active_b_base <= 0;
			b_linear_q <= 0;
			active_rows <= 0;
			active_cols <= 0;
			active_k <= 0;
			a_sub_q <= 0;
			b_sub_q <= 0;
			protocol_poison <= 0;
			a_words_written <= 0;
			b_words_written <= 0;
			a_reuse_count <= 0;
			b_reuse_count <= 0;
		end
		else if (!protocol_poison) begin
			if (a_begin) begin
				if (!a_begin_ready || !a_shape_ok)
					protocol_poison <= 1;
				else if (a_hit) begin
					a_reuse_hit <= 1;
					a_reuse_count <= a_reuse_count + 1'b1;
				end
				else begin
					ast[a_slot] <= FILLING;
					ak[a_slot] <= a_identity;
					ar[a_slot] <= a_rows;
					alen[a_slot] <= a_k_length;
					next_arow[a_slot] <= 0;
					next_ak[a_slot] <= 0;
					afull[a_slot] <= 0;
				end
			end
			if (b_begin) begin
				if (!b_begin_ready || !b_shape_ok)
					protocol_poison <= 1;
				else if (b_hit) begin
					b_reuse_hit <= 1;
					b_reuse_count <= b_reuse_count + 1'b1;
				end
				else begin
					bst <= FILLING;
					bk <= b_identity;
					bc <= b_columns;
					blen <= b_k_length;
					next_bg <= 0;
					next_bk <= 0;
					bfull <= 0;
					b_linear_q <= 0;
				end
			end
			if (a_write_valid) begin
				if (!a_write_ready)
					protocol_poison <= 1;
				else begin
					a_words_written <= a_words_written + 1'b1;
					if (({1'b0, next_ak[a_slot]} + 12'd16) >= {1'b0, alen[a_slot]}) begin
						next_ak[a_slot] <= 0;
						if (({1'b0, next_arow[a_slot]} + 6'd1) >= ar[a_slot])
							afull[a_slot] <= 1;
						else
							next_arow[a_slot] <= next_arow[a_slot] + 1'b1;
					end
					else
						next_ak[a_slot] <= next_ak[a_slot] + 11'd16;
				end
			end
			if (b_write_valid) begin
				if (!b_write_ready)
					protocol_poison <= 1;
				else begin
					b_words_written <= b_words_written + 1'b1;
					b_linear_q <= b_linear_q + 1'b1;
					if (next_bk == 0)
						b_group_base[next_bg] <= b_linear_q;
					if (({1'b0, next_bk} + 12'd2) >= {1'b0, blen}) begin
						next_bk <= 0;
						if (({1'b0, next_bg, 3'b000} + 9'd8) >= bc)
							bfull <= 1;
						else
							next_bg <= next_bg + 1'b1;
					end
					else
						next_bk <= next_bk + 11'd2;
				end
			end
			if (a_commit) begin
				if (((((ast[a_slot] != FILLING) || !afull[a_slot]) || !a_real_responses_retired) || aw) || a_abort)
					protocol_poison <= 1;
				else
					ast[a_slot] <= READY;
			end
			if (b_commit) begin
				if (((((bst != FILLING) || !bfull) || !b_real_responses_retired) || bw) || b_abort)
					protocol_poison <= 1;
				else
					bst <= READY;
			end
			if (a_abort) begin
				if (((ast[a_slot] != FILLING) || a_write_valid) || a_begin)
					protocol_poison <= 1;
				else begin
					ast[a_slot] <= EMPTY;
					afull[a_slot] <= 0;
				end
			end
			if (b_abort) begin
				if (((bst != FILLING) || b_write_valid) || b_begin)
					protocol_poison <= 1;
				else begin
					bst <= EMPTY;
					bfull <= 0;
				end
			end
			if (claim) begin
				if (((!claim_ready || release_compute) || (a_begin && (a_slot == claim_a_slot))) || b_begin)
					protocol_poison <= 1;
				else begin
					active_slot <= claim_a_slot;
					active_m16 <= claim_m16;
					active_b_base <= b_group_base[claim_n8];
					active_rows <= ((ar[claim_a_slot] - claim_row_first) > 16 ? 5'd16 : sv2v_cast_5(ar[claim_a_slot] - claim_row_first));
					active_cols <= ((bc - claim_col_first) > 8 ? 4'd8 : sv2v_cast_4(bc - claim_col_first));
					active_k <= blen;
					ast[claim_a_slot] <= COMPUTE;
					bst <= COMPUTE;
				end
			end
			if (rf) begin
				vector_valid <= 1;
				a_sub_q <= read_k[3:0];
				b_sub_q <= read_k[0];
			end
			if (read_valid && !read_ready)
				protocol_poison <= 1;
			if (release_compute) begin
				if ((!compute_active || read_valid) || vector_valid)
					protocol_poison <= 1;
				else begin
					ast[active_slot] <= READY;
					bst <= READY;
				end
			end
			if (invalidate_a) begin
				if ((((((ast[invalidate_a_slot] == COMPUTE) || (ast[invalidate_a_slot] == FILLING)) || a_begin) || a_commit) || aw) || claim)
					protocol_poison <= 1;
				else begin
					ast[invalidate_a_slot] <= EMPTY;
					afull[invalidate_a_slot] <= 0;
				end
			end
			if (invalidate_b) begin
				if ((((((bst == COMPUTE) || (bst == FILLING)) || b_begin) || b_commit) || bw) || claim)
					protocol_poison <= 1;
				else begin
					bst <= EMPTY;
					bfull <= 0;
				end
			end
		end
	end
endmodule
module npu_resident_word_ram (
	clk,
	wr_en,
	wr_addr,
	wr_data,
	rd_en,
	rd_addr,
	rd_data
);
	parameter signed [31:0] WIDTH = 128;
	parameter signed [31:0] ADDR_W = 9;
	input wire clk;
	input wire wr_en;
	input wire [ADDR_W - 1:0] wr_addr;
	input wire [WIDTH - 1:0] wr_data;
	input wire rd_en;
	input wire [ADDR_W - 1:0] rd_addr;
	output reg [WIDTH - 1:0] rd_data;
	(* ram_style = "block", syn_ramstyle = "block_ram" *) reg [WIDTH - 1:0] mem [0:(1 << ADDR_W) - 1];
	always @(posedge clk) begin
		if (wr_en)
			mem[wr_addr] <= wr_data;
		if (rd_en)
			rd_data <= mem[rd_addr];
	end
endmodule
module npu_resident_fill_owner (
	clk,
	rst,
	start_valid,
	start_ready,
	start_is_b,
	start_a_slot,
	start_base,
	start_model_epoch,
	start_frame_epoch,
	start_tensor,
	start_generation,
	start_A_rows,
	start_B_columns,
	start_K,
	cancel,
	DMA_exclusive_grant,
	dma_job_valid,
	dma_job_ready,
	dma_job,
	dma_job_done,
	dma_job_error,
	dma_error_code,
	dma_outstanding,
	response_order_idle,
	response_order_poison,
	pack_start,
	pack_start_ready,
	pack_is_b,
	pack_A_rows,
	pack_B_columns,
	pack_K,
	pack_abort_request,
	pack_abort_retire,
	pack_real_retired,
	pack_active,
	pack_done,
	pack_aborted,
	pack_poison,
	bank_a_begin,
	bank_b_begin,
	bank_a_slot,
	bank_identity,
	bank_A_rows,
	bank_B_columns,
	bank_K,
	bank_a_begin_ready,
	bank_b_begin_ready,
	bank_a_reuse_hit,
	bank_b_reuse_hit,
	bank_a_commit,
	bank_b_commit,
	bank_real_retired,
	bank_a_abort,
	bank_b_abort,
	bank_poison,
	busy,
	done,
	reused,
	cancelled,
	protocol_poison,
	error_code
);
	reg _sv2v_0;
	parameter [31:0] DRAM_BASE = 32'h80000000;
	parameter [32:0] DRAM_BYTES = 33'h004000000;
	parameter signed [31:0] B_PAIR_WORDS = 8192;
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire start_is_b;
	input wire start_a_slot;
	input wire [31:0] start_base;
	input wire [31:0] start_model_epoch;
	input wire [31:0] start_frame_epoch;
	input wire [31:0] start_tensor;
	input wire [31:0] start_generation;
	input wire [5:0] start_A_rows;
	input wire [8:0] start_B_columns;
	input wire [10:0] start_K;
	input wire cancel;
	input wire DMA_exclusive_grant;
	output wire dma_job_valid;
	input wire dma_job_ready;
	output reg [100:0] dma_job;
	input wire dma_job_done;
	input wire dma_job_error;
	input wire [7:0] dma_error_code;
	input wire [4:0] dma_outstanding;
	input wire response_order_idle;
	input wire response_order_poison;
	output wire pack_start;
	input wire pack_start_ready;
	output wire pack_is_b;
	output wire [5:0] pack_A_rows;
	output wire [8:0] pack_B_columns;
	output wire [10:0] pack_K;
	output wire pack_abort_request;
	output wire pack_abort_retire;
	output wire pack_real_retired;
	input wire pack_active;
	input wire pack_done;
	input wire pack_aborted;
	input wire pack_poison;
	output wire bank_a_begin;
	output wire bank_b_begin;
	output wire bank_a_slot;
	output reg [255:0] bank_identity;
	output wire [5:0] bank_A_rows;
	output wire [8:0] bank_B_columns;
	output wire [10:0] bank_K;
	input wire bank_a_begin_ready;
	input wire bank_b_begin_ready;
	input wire bank_a_reuse_hit;
	input wire bank_b_reuse_hit;
	output wire bank_a_commit;
	output wire bank_b_commit;
	output wire bank_real_retired;
	output wire bank_a_abort;
	output wire bank_b_abort;
	input wire bank_poison;
	output wire busy;
	output reg done;
	output reg reused;
	output reg cancelled;
	output reg protocol_poison;
	output reg [7:0] error_code;
	reg [3:0] state;
	reg is_b;
	reg slot;
	reg cancel_q;
	reg dma_seen;
	reg pack_seen;
	reg pack_abort_seen;
	reg work_started;
	reg [31:0] base;
	reg [5:0] nr;
	reg [8:0] nc;
	reg [10:0] kl;
	reg [18:0] B_bytes;
	function automatic [18:0] sv2v_cast_19;
		input reg [18:0] inp;
		sv2v_cast_19 = inp;
	endfunction
	wire [18:0] start_payload = (start_is_b ? sv2v_cast_19(start_B_columns) * sv2v_cast_19(start_K) : sv2v_cast_19(start_A_rows) * sv2v_cast_19(start_K));
	function automatic [32:0] sv2v_cast_33;
		input reg [32:0] inp;
		sv2v_cast_33 = inp;
	endfunction
	wire [32:0] start_end = (({1'b0, start_base} + sv2v_cast_33(start_payload)) + 33'd15) & ~33'd15;
	function automatic [16:0] sv2v_cast_17;
		input reg [16:0] inp;
		sv2v_cast_17 = inp;
	endfunction
	wire [16:0] start_B_pairwords = sv2v_cast_17(({1'b0, start_B_columns} + 10'd7) >> 3) * sv2v_cast_17(({1'b0, start_K} + 12'd1) >> 1);
	wire start_shape = ((start_K != 0) && (start_K <= 1152)) && (start_is_b ? ((start_B_columns != 0) && (start_B_columns <= 256)) && (start_B_pairwords <= B_PAIR_WORDS) : (start_A_rows != 0) && (start_A_rows <= 16));
	wire start_address = ((({1'b0, start_base} >= {1'b0, DRAM_BASE}) && (start_end <= ({1'b0, DRAM_BASE} + DRAM_BYTES))) && (start_end >= {1'b0, start_base})) && (!start_is_b || (start_base[3:0] == 0));
	wire bank_ready = (is_b ? bank_b_begin_ready : bank_a_begin_ready);
	wire bank_hit = (is_b ? bank_b_reuse_hit : bank_a_reuse_hit);
	wire real_retired = ((dma_seen && dma_job_ready) && (dma_outstanding == 0)) && response_order_idle;
	wire aborting = (cancel_q || cancel) || (error_code != 8'd0);
	assign busy = state != 4'd0;
	assign start_ready = ((((!rst && (state == 4'd0)) && !protocol_poison) && DMA_exclusive_grant) && dma_job_ready) && response_order_idle;
	assign bank_a_slot = slot;
	assign bank_A_rows = nr;
	assign bank_B_columns = nc;
	assign bank_K = kl;
	assign bank_a_begin = ((((state == 4'd1) && !is_b) && !cancel_q) && !cancel) && bank_a_begin_ready;
	assign bank_b_begin = ((((state == 4'd1) && is_b) && !cancel_q) && !cancel) && bank_b_begin_ready;
	assign pack_is_b = is_b;
	assign pack_A_rows = nr;
	assign pack_B_columns = nc;
	assign pack_K = kl;
	assign pack_start = (((state == 4'd3) && !aborting) && DMA_exclusive_grant) && dma_job_ready;
	assign dma_job_valid = (((state == 4'd3) && !aborting) && DMA_exclusive_grant) && pack_start_ready;
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		dma_job = 1'sb0;
		dma_job[100-:2] = 2'd0;
		dma_job[98-:32] = base;
		dma_job[2-:2] = 1;
		dma_job[0] = slot;
		if (is_b) begin
			dma_job[34-:16] = sv2v_cast_16((B_bytes + 19'd15) >> 4);
			dma_job[18-:16] = 16;
			dma_job[66-:32] = 16;
		end
		else begin
			dma_job[34-:16] = sv2v_cast_16(nr);
			dma_job[18-:16] = sv2v_cast_16(kl);
			dma_job[66-:32] = sv2v_cast_32(kl);
		end
	end
	assign pack_abort_request = (state == 4'd5) || (state == 4'd10);
	assign pack_real_retired = real_retired;
	assign pack_abort_retire = (((state == 4'd5) && real_retired) && pack_active) && !pack_abort_seen;
	assign bank_real_retired = real_retired;
	assign bank_a_commit = (state == 4'd7) && !is_b;
	assign bank_b_commit = (state == 4'd7) && is_b;
	assign bank_a_abort = (state == 4'd6) && !is_b;
	assign bank_b_abort = (state == 4'd6) && is_b;
	always @(posedge clk) begin
		done <= 0;
		if (rst) begin
			state <= 4'd0;
			is_b <= 0;
			slot <= 0;
			cancel_q <= 0;
			dma_seen <= 0;
			pack_seen <= 0;
			pack_abort_seen <= 0;
			work_started <= 0;
			base <= 0;
			nr <= 0;
			nc <= 0;
			kl <= 0;
			B_bytes <= 0;
			bank_identity <= 0;
			reused <= 0;
			cancelled <= 0;
			protocol_poison <= 0;
			error_code <= 8'd0;
		end
		else begin
			if (busy && cancel)
				cancel_q <= 1;
			if ((dma_job_done || dma_job_error) && work_started) begin
				dma_seen <= 1;
				if (dma_job_error)
					error_code <= (dma_error_code == 8'd0 ? 8'd11 : dma_error_code);
			end
			if (pack_done && work_started)
				pack_seen <= 1;
			if (pack_aborted && work_started)
				pack_abort_seen <= 1;
			if (busy && (((!DMA_exclusive_grant || response_order_poison) || pack_poison) || bank_poison)) begin
				state <= 4'd10;
				protocol_poison <= 1;
				error_code <= 8'd11;
			end
			else
				case (state)
					4'd0:
						if (start_valid && start_ready) begin
							is_b <= start_is_b;
							slot <= start_a_slot;
							base <= start_base;
							nr <= (start_is_b ? 0 : start_A_rows);
							nc <= (start_is_b ? start_B_columns : 0);
							kl <= start_K;
							B_bytes <= sv2v_cast_19(start_B_columns) * sv2v_cast_19(start_K);
							bank_identity <= {start_model_epoch, start_frame_epoch, start_tensor, start_generation, start_base, sv2v_cast_32(start_K), sv2v_cast_32((start_is_b ? start_B_columns : 9'd0)), sv2v_cast_32((start_is_b ? 6'd0 : start_A_rows))};
							cancel_q <= cancel;
							cancelled <= 0;
							reused <= 0;
							error_code <= 8'd0;
							dma_seen <= 0;
							pack_seen <= 0;
							pack_abort_seen <= 0;
							work_started <= 0;
							if ((!start_shape || (start_model_epoch == 0)) || (start_generation == 0)) begin
								error_code <= 8'd1;
								state <= 4'd9;
							end
							else if (!start_address) begin
								error_code <= (start_is_b && (start_base[3:0] != 0) ? 8'd3 : 8'd5);
								state <= 4'd9;
							end
							else if (cancel) begin
								cancelled <= 1;
								state <= 4'd9;
							end
							else
								state <= 4'd1;
						end
					4'd1:
						if (cancel_q || cancel) begin
							cancelled <= 1;
							state <= 4'd9;
						end
						else if (bank_ready)
							state <= 4'd2;
					4'd2:
						if (bank_hit) begin
							reused <= 1;
							cancelled <= cancel_q || cancel;
							state <= 4'd9;
						end
						else if (cancel_q || cancel) begin
							cancelled <= 1;
							state <= 4'd6;
						end
						else
							state <= 4'd3;
					4'd3:
						if (cancel_q || cancel) begin
							cancelled <= 1;
							state <= 4'd6;
						end
						else if ((dma_job_ready && pack_start_ready) && DMA_exclusive_grant) begin
							state <= 4'd4;
							work_started <= 1;
						end
					4'd4:
						if (aborting || dma_job_error) begin
							cancelled <= cancel_q || cancel;
							state <= 4'd5;
						end
						else if ((real_retired && pack_seen) && !pack_active)
							state <= 4'd7;
					4'd5:
						if (real_retired && (pack_abort_seen || !pack_active))
							state <= 4'd6;
					4'd6: state <= 4'd8;
					4'd7: state <= 4'd8;
					4'd8: state <= 4'd9;
					4'd9: begin
						done <= 1;
						cancelled <= (cancelled || cancel_q) || cancel;
						state <= 4'd0;
						work_started <= 0;
					end
					4'd10:
						;
					default: begin
						state <= 4'd10;
						protocol_poison <= 1;
						error_code <= 8'd11;
					end
				endcase
		end
	end
	initial _sv2v_0 = 0;
endmodule
module npu_resident_fill_pack (
	clk,
	rst,
	start_valid,
	start_ready,
	start_is_b,
	start_A_rows,
	start_B_columns,
	start_K,
	input_valid,
	input_ready,
	input_row,
	input_col,
	input_count,
	input_bytes,
	a_valid,
	a_ready,
	a_row,
	a_k,
	a_word,
	b_valid,
	b_ready,
	b_group,
	b_k,
	b_pair,
	abort_request,
	abort_retire,
	real_DMA_responses_retired,
	active,
	pack_done,
	aborted,
	protocol_poison
);
	reg _sv2v_0;
	parameter [0:0] PIPELINED_FILL = 1'b1;
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire start_is_b;
	input wire [5:0] start_A_rows;
	input wire [8:0] start_B_columns;
	input wire [10:0] start_K;
	input wire input_valid;
	output wire input_ready;
	input wire [15:0] input_row;
	input wire [15:0] input_col;
	input wire [4:0] input_count;
	input wire [127:0] input_bytes;
	output wire a_valid;
	input wire a_ready;
	output wire [4:0] a_row;
	output wire [10:0] a_k;
	output wire [127:0] a_word;
	output wire b_valid;
	input wire b_ready;
	output wire [4:0] b_group;
	output wire [10:0] b_k;
	output wire [127:0] b_pair;
	input wire abort_request;
	input wire abort_retire;
	input wire real_DMA_responses_retired;
	output reg active;
	output reg pack_done;
	output reg aborted;
	output reg protocol_poison;
	reg mode_b;
	reg cancel_q;
	reg out_valid;
	reg out_final;
	reg [5:0] nr;
	reg [8:0] nc;
	reg [10:0] kl;
	reg [15:0] expected_row;
	reg [15:0] expected_col;
	reg [127:0] a_partial;
	reg [127:0] raw;
	reg [127:0] pair_partial;
	reg [127:0] out_word;
	reg [4:0] raw_count;
	reg [10:0] bk_row;
	reg [4:0] bg;
	reg [4:0] out_row_or_group;
	reg [3:0] bc;
	reg [10:0] out_k;
	wire output_ready = (mode_b ? b_ready : a_ready);
	wire output_fire = out_valid && output_ready;
	wire draining = (cancel_q || abort_request) || protocol_poison;
	assign start_ready = ((!rst && !active) && !out_valid) && !protocol_poison;
	wire output_space = !out_valid || ((PIPELINED_FILL && output_ready) && !out_final);
	assign input_ready = ((!rst && active) && output_space) && ((draining || !mode_b) || (raw_count == 0));
	wire input_fire = input_valid && input_ready;
	assign a_valid = (!rst && out_valid) && !mode_b;
	assign b_valid = (!rst && out_valid) && mode_b;
	assign a_row = out_row_or_group;
	assign b_group = out_row_or_group;
	assign a_k = out_k;
	assign b_k = out_k;
	assign a_word = out_word;
	assign b_pair = out_word;
	wire [5:0] a_end_in_word = {2'd0, input_col[3:0]} + {1'b0, input_count};
	function automatic [16:0] sv2v_cast_17;
		input reg [16:0] inp;
		sv2v_cast_17 = inp;
	endfunction
	wire [16:0] a_next_col = {1'b0, input_col} + sv2v_cast_17(input_count);
	wire [8:0] b_remaining_columns = nc - {bg, 3'd0};
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	wire [3:0] b_group_columns = (b_remaining_columns > 8 ? 4'd8 : sv2v_cast_4(b_remaining_columns));
	wire b_last_group = b_remaining_columns <= 8;
	wire b_fast = (b_group_columns == 8) && !kl[0];
	wire [127:0] a_shifted = input_bytes << {input_col[3:0], 3'd0};
	reg [127:0] a_merged;
	reg [127:0] pair_merged;
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		a_merged = a_partial;
		begin : sv2v_autoblock_1
			integer lane;
			for (lane = 0; lane < 16; lane = lane + 1)
				if ((lane >= sv2v_cast_32_signed(input_col[3:0])) && (lane < sv2v_cast_32_signed(a_end_in_word)))
					a_merged[lane * 8+:8] = a_shifted[lane * 8+:8];
		end
		pair_merged = pair_partial;
		pair_merged[{bk_row[0], bc[2:0], 3'b000}+:8] = raw[7:0];
	end
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	always @(posedge clk) begin
		pack_done <= 0;
		aborted <= 0;
		if (rst) begin
			active <= 0;
			mode_b <= 0;
			cancel_q <= 0;
			out_valid <= 0;
			out_final <= 0;
			nr <= 0;
			nc <= 0;
			kl <= 0;
			expected_row <= 0;
			expected_col <= 0;
			a_partial <= 0;
			raw <= 0;
			pair_partial <= 0;
			raw_count <= 0;
			bk_row <= 0;
			bg <= 0;
			bc <= 0;
			out_word <= 0;
			out_row_or_group <= 0;
			out_k <= 0;
			protocol_poison <= 0;
		end
		else begin
			if (start_valid && start_ready) begin
				if ((((start_K == 0) || (start_K > 1152)) || (!start_is_b && ((start_A_rows == 0) || (start_A_rows > 16)))) || (start_is_b && ((start_B_columns == 0) || (start_B_columns > 256))))
					protocol_poison <= 1;
				else begin
					active <= 1;
					mode_b <= start_is_b;
					nr <= start_A_rows;
					nc <= start_B_columns;
					kl <= start_K;
					cancel_q <= 0;
					expected_row <= 0;
					expected_col <= 0;
					a_partial <= 0;
					pair_partial <= 0;
					raw_count <= 0;
					bk_row <= 0;
					bg <= 0;
					bc <= 0;
					out_final <= 0;
				end
			end
			if (active && abort_request)
				cancel_q <= 1;
			if (output_fire) begin
				out_valid <= 0;
				if (out_final && !draining) begin
					active <= 0;
					raw_count <= 0;
					pack_done <= 1;
				end
			end
			if (input_fire) begin
				if (draining)
					raw_count <= 0;
				else if (mode_b) begin
					if (((input_col != 0) || (input_row != expected_row)) || (input_count != 16)) begin
						protocol_poison <= 1;
						cancel_q <= 1;
					end
					else begin
						expected_row <= expected_row + 1'b1;
						if (PIPELINED_FILL && b_fast) begin
							if (bk_row[0] || (bc != 0)) begin
								protocol_poison <= 1;
								cancel_q <= 1;
							end
							else begin
								out_word <= input_bytes;
								out_row_or_group <= bg;
								out_k <= bk_row;
								out_valid <= 1;
								out_final <= ((bk_row + 12'd2) >= {1'b0, kl}) && b_last_group;
								raw_count <= 0;
								if ((bk_row + 12'd2) >= {1'b0, kl}) begin
									bk_row <= 0;
									bg <= bg + 1'b1;
								end
								else
									bk_row <= bk_row + 11'd2;
							end
						end
						else begin
							raw <= input_bytes;
							raw_count <= 16;
						end
					end
				end
				else if ((((((input_row != expected_row) || (input_col != expected_col)) || (input_count == 0)) || (input_count > 16)) || (a_end_in_word > 16)) || (a_next_col > {6'd0, kl})) begin
					protocol_poison <= 1;
					cancel_q <= 1;
				end
				else begin
					a_partial <= a_merged;
					if ((a_end_in_word == 16) || (a_next_col == {6'd0, kl})) begin
						out_word <= a_merged;
						out_row_or_group <= input_row[4:0];
						out_k <= {input_col[10:4], 4'd0};
						out_valid <= 1;
						out_final <= (a_next_col == {6'd0, kl}) && ((input_row + 1'b1) == nr);
						a_partial <= 0;
					end
					if (a_next_col == {6'd0, kl}) begin
						expected_col <= 0;
						expected_row <= expected_row + 1'b1;
					end
					else
						expected_col <= sv2v_cast_16(a_next_col);
				end
			end
			if ((((active && mode_b) && output_space) && (raw_count != 0)) && !draining) begin
				if (b_fast) begin
					if (((raw_count != 16) || bk_row[0]) || (bc != 0)) begin
						protocol_poison <= 1;
						cancel_q <= 1;
					end
					else begin
						out_word <= raw;
						out_row_or_group <= bg;
						out_k <= bk_row;
						out_valid <= 1;
						out_final <= ((bk_row + 12'd2) >= {1'b0, kl}) && b_last_group;
						raw_count <= 0;
						if ((bk_row + 12'd2) >= {1'b0, kl}) begin
							bk_row <= 0;
							bg <= bg + 1'b1;
						end
						else
							bk_row <= bk_row + 11'd2;
					end
				end
				else begin
					raw <= {8'd0, raw[127:8]};
					raw_count <= raw_count - 1'b1;
					pair_partial <= pair_merged;
					if ((bc + 1'b1) >= b_group_columns) begin
						bc <= 0;
						if (bk_row[0] || ((bk_row + 12'd1) >= {1'b0, kl})) begin
							out_word <= pair_merged;
							out_row_or_group <= bg;
							out_k <= {bk_row[10:1], 1'b0};
							out_valid <= 1;
							out_final <= ((bk_row + 12'd1) >= {1'b0, kl}) && b_last_group;
							pair_partial <= 0;
						end
						if ((bk_row + 12'd1) >= {1'b0, kl}) begin
							bk_row <= 0;
							bg <= bg + 1'b1;
						end
						else
							bk_row <= bk_row + 1'b1;
					end
					else
						bc <= bc + 1'b1;
				end
			end
			if (abort_retire) begin
				if (((!active || !draining) || !real_DMA_responses_retired) || (out_valid && !output_ready))
					protocol_poison <= 1;
				else begin
					active <= 0;
					out_valid <= 0;
					raw_count <= 0;
					aborted <= 1;
				end
			end
		end
	end
	initial _sv2v_0 = 0;
endmodule
module npu_response_order (
	clk,
	rst,
	issue_valid,
	issue_ready,
	issue_id,
	issue_write,
	rsp_valid,
	rsp_ready,
	rsp_id,
	rsp_write,
	rsp_error,
	rsp_data,
	out_valid,
	out_ready,
	out_id,
	out_write,
	out_error,
	out_data,
	drained,
	idle,
	protocol_poison,
	owned
);
	parameter signed [31:0] DATA_W = 128;
	parameter signed [31:0] ID_W = 4;
	parameter signed [31:0] SLOTS = 16;
	parameter [0:0] IN_ORDER_TRANSPORT = 1'b0;
	input wire clk;
	input wire rst;
	input wire issue_valid;
	output wire issue_ready;
	input wire [ID_W - 1:0] issue_id;
	input wire issue_write;
	input wire rsp_valid;
	output wire rsp_ready;
	input wire [ID_W - 1:0] rsp_id;
	input wire rsp_write;
	input wire rsp_error;
	input wire [DATA_W - 1:0] rsp_data;
	output wire out_valid;
	input wire out_ready;
	output wire [ID_W - 1:0] out_id;
	output wire out_write;
	output wire out_error;
	output wire [DATA_W - 1:0] out_data;
	output wire drained;
	output wire idle;
	output wire protocol_poison;
	output wire [$clog2(SLOTS + 1) - 1:0] owned;
	generate
		if (IN_ORDER_TRANSPORT) begin : ordered_link
			npu_response_order_inorder #(
				.DATA_W(DATA_W),
				.ID_W(ID_W),
				.SLOTS(SLOTS)
			) impl(
				.clk(clk),
				.rst(rst),
				.issue_valid(issue_valid),
				.issue_ready(issue_ready),
				.issue_id(issue_id),
				.issue_write(issue_write),
				.rsp_valid(rsp_valid),
				.rsp_ready(rsp_ready),
				.rsp_id(rsp_id),
				.rsp_write(rsp_write),
				.rsp_error(rsp_error),
				.rsp_data(rsp_data),
				.out_valid(out_valid),
				.out_ready(out_ready),
				.out_id(out_id),
				.out_write(out_write),
				.out_error(out_error),
				.out_data(out_data),
				.drained(drained),
				.idle(idle),
				.protocol_poison(protocol_poison),
				.owned(owned)
			);
		end
		else begin : reorder_link
			npu_response_order_reorder #(
				.DATA_W(DATA_W),
				.ID_W(ID_W),
				.SLOTS(SLOTS)
			) impl(
				.clk(clk),
				.rst(rst),
				.issue_valid(issue_valid),
				.issue_ready(issue_ready),
				.issue_id(issue_id),
				.issue_write(issue_write),
				.rsp_valid(rsp_valid),
				.rsp_ready(rsp_ready),
				.rsp_id(rsp_id),
				.rsp_write(rsp_write),
				.rsp_error(rsp_error),
				.rsp_data(rsp_data),
				.out_valid(out_valid),
				.out_ready(out_ready),
				.out_id(out_id),
				.out_write(out_write),
				.out_error(out_error),
				.out_data(out_data),
				.drained(drained),
				.idle(idle),
				.protocol_poison(protocol_poison),
				.owned(owned)
			);
		end
	endgenerate
endmodule
module npu_order_word_ram (
	clk,
	wr_en,
	wr_addr,
	wr_data,
	rd_en,
	rd_addr,
	rd_data
);
	parameter signed [31:0] WIDTH = 130;
	parameter signed [31:0] ADDR_W = 4;
	input wire clk;
	input wire wr_en;
	input wire [ADDR_W - 1:0] wr_addr;
	input wire [WIDTH - 1:0] wr_data;
	input wire rd_en;
	input wire [ADDR_W - 1:0] rd_addr;
	output reg [WIDTH - 1:0] rd_data;
	(* ram_style = "block", syn_ramstyle = "block_ram" *) reg [WIDTH - 1:0] memory [0:(1 << ADDR_W) - 1];
	always @(posedge clk) begin
		if (wr_en)
			memory[wr_addr] <= wr_data;
		if (rd_en)
			rd_data <= memory[rd_addr];
	end
endmodule
module npu_resident_operand_adapter (
	clk,
	rst,
	mode_resident,
	next_a_rows,
	model_epoch,
	frame_epoch,
	task_generation,
	a_generation,
	a_base,
	b_page_base,
	a_rows,
	b_columns,
	k_length,
	b_group,
	sched_valid,
	sched_ready,
	sched_job,
	sched_done,
	sched_error,
	sched_error_code,
	physical_valid,
	physical_ready,
	physical_job,
	physical_done,
	physical_error,
	physical_error_code,
	outstanding,
	order_idle,
	order_poison,
	unpack_valid,
	unpack_ready,
	unpack_row,
	unpack_col,
	unpack_count,
	unpack_data,
	legacy_unpack_enable,
	claim,
	release_compute,
	read_valid,
	read_k,
	committed_operands_ready,
	vector_valid,
	a_vector,
	b_vector,
	protocol_poison
);
	parameter [0:0] PIPELINED_FILL = 1'b1;
	parameter [0:0] PREFETCH_A = 1'b0;
	parameter [31:0] DRAM_BASE = 32'h80000000;
	parameter [32:0] DRAM_BYTES = 33'h004000000;
	input wire clk;
	input wire rst;
	input wire mode_resident;
	input wire [4:0] next_a_rows;
	input wire [31:0] model_epoch;
	input wire [31:0] frame_epoch;
	input wire [31:0] task_generation;
	input wire [31:0] a_generation;
	input wire [31:0] a_base;
	input wire [31:0] b_page_base;
	input wire [5:0] a_rows;
	input wire [8:0] b_columns;
	input wire [10:0] k_length;
	input wire [4:0] b_group;
	input wire sched_valid;
	output wire sched_ready;
	input wire [100:0] sched_job;
	output wire sched_done;
	output wire sched_error;
	output wire [7:0] sched_error_code;
	output wire physical_valid;
	input wire physical_ready;
	output wire [100:0] physical_job;
	input wire physical_done;
	input wire physical_error;
	input wire [7:0] physical_error_code;
	input wire [4:0] outstanding;
	input wire order_idle;
	input wire order_poison;
	input wire unpack_valid;
	output wire unpack_ready;
	input wire [15:0] unpack_row;
	input wire [15:0] unpack_col;
	input wire [4:0] unpack_count;
	input wire [255:0] unpack_data;
	output wire legacy_unpack_enable;
	input wire claim;
	input wire release_compute;
	input wire read_valid;
	input wire [10:0] read_k;
	output wire committed_operands_ready;
	output wire vector_valid;
	output wire [255:0] a_vector;
	output wire [127:0] b_vector;
	output wire protocol_poison;
	reg [2:0] state;
	reg selected_b;
	reg b_valid_q;
	reg [1:0] a_valid_q;
	reg [255:0] a_key_q [0:1];
	reg [255:0] b_key_q;
	reg background;
	reg fill_slot;
	reg raw_is_store;
	reg [31:0] fill_a_base;
	reg [31:0] fill_a_generation;
	reg [5:0] fill_a_rows;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	wire [255:0] a_key = {model_epoch, frame_epoch, a_generation, task_generation, a_base, sv2v_cast_32(k_length), 32'd0, sv2v_cast_32(a_rows)};
	wire [255:0] b_key = {model_epoch, frame_epoch, b_page_base, task_generation, b_page_base, sv2v_cast_32(k_length), sv2v_cast_32(b_columns), 32'd0};
	wire a_hit0 = a_valid_q[0] && (a_key_q[0] == a_key);
	wire a_hit1 = a_valid_q[1] && (a_key_q[1] == a_key);
	wire current_a_slot = !a_hit0 && a_hit1;
	wire hit = (selected_b ? b_valid_q && (b_key_q == b_key) : a_hit0 || a_hit1);
	wire [31:0] next_a_base = a_base + (sv2v_cast_32(k_length) << 4);
	wire [255:0] next_a_key = {model_epoch, frame_epoch, a_generation + 32'd16, task_generation, next_a_base, sv2v_cast_32(k_length), 32'd0, sv2v_cast_32(next_a_rows)};
	wire next_a_cached = (a_valid_q[0] && (a_key_q[0] == next_a_key)) || (a_valid_q[1] && (a_key_q[1] == next_a_key));
	wire prefetch_launch = (((((((((((PREFETCH_A && mode_resident) && claim) && (next_a_rows != 0)) && (next_a_rows <= 16)) && (a_rows == 16)) && !next_a_cached) && !sched_valid) && (state == 3'd0)) && physical_ready) && order_idle) && (outstanding == 0)) && !protocol_poison;
	wire read_job = mode_resident && (sched_job[100-:2] != 2'd2);
	reg result_error;
	reg [7:0] result_code;
	wire fill_start;
	wire fill_ready;
	wire fill_busy;
	wire fill_done;
	wire fill_reused;
	wire fill_cancelled;
	wire fill_poison;
	wire [7:0] fill_error;
	wire fill_job_valid;
	wire [100:0] fill_job;
	wire a_begin;
	wire b_begin;
	wire a_slot;
	wire a_begin_ready;
	wire b_begin_ready;
	wire a_reuse_hit;
	wire b_reuse_hit;
	wire [255:0] bank_identity;
	wire [5:0] bank_rows;
	wire [8:0] bank_columns;
	wire [10:0] bank_k;
	wire a_commit;
	wire b_commit;
	wire real_retired;
	wire a_abort;
	wire b_abort;
	wire bank_poison;
	wire pack_start;
	wire pack_ready;
	wire pack_is_b;
	wire pack_abort;
	wire pack_abort_retire;
	wire pack_retired;
	wire [5:0] pack_rows;
	wire [8:0] pack_columns;
	wire [10:0] pack_k;
	wire pack_active;
	wire pack_done;
	wire pack_aborted;
	wire pack_poison;
	wire aw;
	wire awr;
	wire bw;
	wire bwr;
	wire [4:0] awrow;
	wire [4:0] bwgroup;
	wire [10:0] awk;
	wire [10:0] bwk;
	wire [127:0] awdata;
	wire [127:0] bwdata;
	wire [127:0] unpack_bytes;
	wire claim_ready;
	wire read_ready;
	wire compute_active;
	wire [3:0] a_owners;
	wire [1:0] b_owner;
	genvar _gv_lane_1;
	generate
		for (_gv_lane_1 = 0; _gv_lane_1 < 16; _gv_lane_1 = _gv_lane_1 + 1) begin : genblk1
			localparam lane = _gv_lane_1;
			assign unpack_bytes[8 * lane+:8] = unpack_data[16 * lane+:8];
		end
	endgenerate
	assign committed_operands_ready = ((((((mode_resident && !rst) && ((((((state == 3'd0) && physical_ready) && order_idle) && (outstanding == 0)) || background) || ((state == 3'd5) && raw_is_store))) && !protocol_poison) && (a_hit0 || a_hit1)) && b_valid_q) && (b_key_q == b_key)) && claim_ready;
	assign sched_ready = (((!rst && (state == 3'd0)) && physical_ready) && order_idle) && !protocol_poison;
	assign physical_valid = (((((state == 3'd0) && sched_valid) && !read_job) && order_idle) && !protocol_poison) || fill_job_valid;
	assign physical_job = (fill_job_valid ? fill_job : sched_job);
	assign sched_done = ((state == 3'd4) && !result_error) || ((state == 3'd5) && physical_done);
	assign sched_error = ((state == 3'd4) && result_error) || ((state == 3'd5) && physical_error);
	assign sched_error_code = (state == 3'd4 ? result_code : physical_error_code);
	assign fill_start = state == 3'd2;
	assign legacy_unpack_enable = state == 3'd5;
	wire pack_input_ready;
	assign unpack_ready = (state == 3'd5 ? 1'b1 : pack_input_ready);
	assign protocol_poison = (((fill_poison || pack_poison) || bank_poison) || order_poison) || (state == 3'd6);
	npu_resident_fill_owner #(
		.DRAM_BASE(DRAM_BASE),
		.DRAM_BYTES(DRAM_BYTES)
	) owner(
		.clk(clk),
		.rst(rst),
		.start_valid(fill_start),
		.start_ready(fill_ready),
		.start_is_b(selected_b),
		.start_a_slot(fill_slot),
		.start_base((selected_b ? b_page_base : fill_a_base)),
		.start_model_epoch(model_epoch),
		.start_frame_epoch(frame_epoch),
		.start_tensor((selected_b ? b_page_base : fill_a_generation)),
		.start_generation(task_generation),
		.start_A_rows(fill_a_rows),
		.start_B_columns(b_columns),
		.start_K(k_length),
		.cancel(1'b0),
		.DMA_exclusive_grant(1'b1),
		.dma_job_valid(fill_job_valid),
		.dma_job_ready(physical_ready),
		.dma_job(fill_job),
		.dma_job_done(physical_done),
		.dma_job_error(physical_error),
		.dma_error_code(physical_error_code),
		.dma_outstanding(outstanding),
		.response_order_idle(order_idle),
		.response_order_poison(order_poison),
		.pack_start(pack_start),
		.pack_start_ready(pack_ready),
		.pack_is_b(pack_is_b),
		.pack_A_rows(pack_rows),
		.pack_B_columns(pack_columns),
		.pack_K(pack_k),
		.pack_abort_request(pack_abort),
		.pack_abort_retire(pack_abort_retire),
		.pack_real_retired(pack_retired),
		.pack_active(pack_active),
		.pack_done(pack_done),
		.pack_aborted(pack_aborted),
		.pack_poison(pack_poison),
		.bank_a_begin(a_begin),
		.bank_b_begin(b_begin),
		.bank_a_slot(a_slot),
		.bank_identity(bank_identity),
		.bank_A_rows(bank_rows),
		.bank_B_columns(bank_columns),
		.bank_K(bank_k),
		.bank_a_begin_ready(a_begin_ready),
		.bank_b_begin_ready(b_begin_ready),
		.bank_a_reuse_hit(a_reuse_hit),
		.bank_b_reuse_hit(b_reuse_hit),
		.bank_a_commit(a_commit),
		.bank_b_commit(b_commit),
		.bank_real_retired(real_retired),
		.bank_a_abort(a_abort),
		.bank_b_abort(b_abort),
		.bank_poison(bank_poison),
		.busy(fill_busy),
		.done(fill_done),
		.reused(fill_reused),
		.cancelled(fill_cancelled),
		.protocol_poison(fill_poison),
		.error_code(fill_error)
	);
	npu_resident_fill_pack #(.PIPELINED_FILL(PIPELINED_FILL)) packer(
		.clk(clk),
		.rst(rst),
		.start_valid(pack_start),
		.start_ready(pack_ready),
		.start_is_b(pack_is_b),
		.start_A_rows(pack_rows),
		.start_B_columns(pack_columns),
		.start_K(pack_k),
		.input_valid(unpack_valid && (state == 3'd3)),
		.input_ready(pack_input_ready),
		.input_row(unpack_row),
		.input_col(unpack_col),
		.input_count(unpack_count),
		.input_bytes(unpack_bytes),
		.a_valid(aw),
		.a_ready(awr),
		.a_row(awrow),
		.a_k(awk),
		.a_word(awdata),
		.b_valid(bw),
		.b_ready(bwr),
		.b_group(bwgroup),
		.b_k(bwk),
		.b_pair(bwdata),
		.abort_request(pack_abort),
		.abort_retire(pack_abort_retire),
		.real_DMA_responses_retired(pack_retired),
		.active(pack_active),
		.pack_done(pack_done),
		.aborted(pack_aborted),
		.protocol_poison(pack_poison)
	);
	npu_resident_ab #(
		.A_ROWS_PER_SLOT(16),
		.B_PAIR_ADDR_W(13)
	) operands(
		.clk(clk),
		.rst(rst),
		.a_begin(a_begin),
		.a_slot(a_slot),
		.a_identity(bank_identity),
		.a_rows(bank_rows),
		.a_k_length(bank_k),
		.a_begin_ready(a_begin_ready),
		.a_reuse_hit(a_reuse_hit),
		.a_write_valid(aw),
		.a_write_row(awrow),
		.a_write_k(awk),
		.a_write_word(awdata),
		.a_write_ready(awr),
		.a_commit(a_commit),
		.a_real_responses_retired(real_retired),
		.a_abort(a_abort),
		.b_begin(b_begin),
		.b_identity(bank_identity),
		.b_columns(bank_columns),
		.b_k_length(bank_k),
		.b_begin_ready(b_begin_ready),
		.b_reuse_hit(b_reuse_hit),
		.b_write_valid(bw),
		.b_write_group(bwgroup),
		.b_write_k(bwk),
		.b_write_pair(bwdata),
		.b_write_ready(bwr),
		.b_commit(b_commit),
		.b_real_responses_retired(real_retired),
		.b_abort(b_abort),
		.invalidate_a(1'b0),
		.invalidate_a_slot(1'b0),
		.invalidate_b(1'b0),
		.claim(claim),
		.claim_a_slot(current_a_slot),
		.claim_m16(1'b0),
		.claim_n8(b_group),
		.expected_a_identity(a_key),
		.expected_b_identity(b_key),
		.claim_ready(claim_ready),
		.release_compute(release_compute && compute_active),
		.read_valid(read_valid),
		.read_k(read_k),
		.read_ready(read_ready),
		.vector_valid(vector_valid),
		.a_vector(a_vector),
		.b_vector(b_vector),
		.compute_active(compute_active),
		.protocol_poison(bank_poison),
		.a_owners(a_owners),
		.b_owner(b_owner),
		.a_words_written(),
		.b_words_written(),
		.a_reuse_count(),
		.b_reuse_count()
	);
	always @(posedge clk)
		if (rst) begin
			state <= 3'd0;
			selected_b <= 0;
			a_valid_q <= 0;
			b_valid_q <= 0;
			a_key_q[0] <= 0;
			a_key_q[1] <= 0;
			b_key_q <= 0;
			background <= 0;
			fill_slot <= 0;
			raw_is_store <= 0;
			fill_a_base <= 0;
			fill_a_generation <= 0;
			fill_a_rows <= 0;
			result_error <= 0;
			result_code <= 8'd0;
		end
		else if (protocol_poison)
			state <= 3'd6;
		else
			case (state)
				3'd0:
					if (sched_valid && sched_ready) begin
						background <= 0;
						result_error <= 0;
						result_code <= 8'd0;
						raw_is_store <= sched_job[100-:2] == 2'd2;
						if (read_job) begin
							selected_b <= sched_job[100-:2] == 2'd1;
							state <= 3'd1;
						end
						else
							state <= 3'd5;
					end
					else if (prefetch_launch) begin
						background <= 1;
						selected_b <= 0;
						fill_slot <= ~current_a_slot;
						fill_a_base <= next_a_base;
						fill_a_generation <= a_generation + 32'd16;
						fill_a_rows <= {1'b0, next_a_rows};
						state <= 3'd2;
					end
				3'd1:
					if (hit)
						state <= 3'd4;
					else begin
						fill_slot <= current_a_slot;
						fill_a_base <= a_base;
						fill_a_generation <= a_generation;
						fill_a_rows <= a_rows;
						state <= 3'd2;
					end
				3'd2:
					if (fill_start && fill_ready) begin
						if (selected_b)
							b_valid_q <= 0;
						else
							a_valid_q[fill_slot] <= 0;
						state <= 3'd3;
					end
				3'd3:
					if (fill_done) begin
						result_error <= (fill_error != 8'd0) || fill_cancelled;
						result_code <= fill_error;
						if ((fill_error == 8'd0) && !fill_cancelled) begin
							if (selected_b) begin
								b_valid_q <= 1;
								b_key_q <= b_key;
							end
							else begin
								a_valid_q[fill_slot] <= 1;
								a_key_q[fill_slot] <= bank_identity;
							end
						end
						if (background) begin
							background <= 0;
							state <= ((fill_error != 8'd0) || fill_cancelled ? 3'd6 : 3'd0);
						end
						else
							state <= 3'd4;
					end
				3'd4: state <= 3'd0;
				3'd5:
					if (physical_done || physical_error)
						state <= 3'd0;
				default: state <= 3'd6;
			endcase
endmodule
module npu_result_rows (
	clk,
	rst,
	write_begin,
	write_slot,
	write_identity,
	rows,
	columns,
	write_begin_ready,
	write_valid,
	write_row,
	write_group,
	write_ACC48,
	write_ready,
	write_commit,
	write_abort,
	store_claim,
	store_slot,
	expected_identity,
	store_claim_ready,
	read_valid,
	read_row,
	read_group,
	read_ready,
	output_valid,
	output_ready,
	output_INT32,
	output_strobe,
	store_release,
	real_B_retired,
	store_failed,
	discard_ready,
	owners,
	protocol_poison,
	captured_rows,
	consumed_groups
);
	parameter signed [31:0] BANK_ROWS = 32;
	parameter signed [31:0] BANK_COLUMNS = 256;
	input wire clk;
	input wire rst;
	input wire write_begin;
	input wire write_slot;
	input wire [255:0] write_identity;
	input wire [5:0] rows;
	input wire [8:0] columns;
	output wire write_begin_ready;
	input wire write_valid;
	input wire [4:0] write_row;
	input wire [4:0] write_group;
	input wire [383:0] write_ACC48;
	output wire write_ready;
	input wire write_commit;
	input wire write_abort;
	input wire store_claim;
	input wire store_slot;
	input wire [255:0] expected_identity;
	output wire store_claim_ready;
	input wire read_valid;
	input wire [4:0] read_row;
	input wire [4:0] read_group;
	output wire read_ready;
	output reg output_valid;
	input wire output_ready;
	output wire [255:0] output_INT32;
	output wire [31:0] output_strobe;
	input wire store_release;
	input wire real_B_retired;
	input wire store_failed;
	input wire discard_ready;
	output wire [3:0] owners;
	output reg protocol_poison;
	output reg [31:0] captured_rows;
	output reg [31:0] consumed_groups;
	localparam signed [31:0] ROW_ADDR_W = (BANK_ROWS == 16 ? 4 : 5);
	localparam signed [31:0] RESULT_ADDR_W = (1 + ROW_ADDR_W) + (BANK_COLUMNS == 8 ? 0 : 5);
	initial if (((BANK_ROWS != 16) && (BANK_ROWS != 32)) || ((BANK_COLUMNS != 8) && (BANK_COLUMNS != 256))) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_result_rows.sv:33:4 - npu_result_rows.<unnamed_block>.<unnamed_block>\n msg: ", $time, "RESULT_FIXED_BANK_CAPACITY_UNSUPPORTED");
		$finish(1);
	end
	localparam [1:0] EMPTY = 0;
	localparam [1:0] FILL = 1;
	localparam [1:0] READY = 2;
	localparam [1:0] STORE = 3;
	reg [1:0] owner [0:1];
	reg [255:0] identity [0:1];
	reg [5:0] nr [0:1];
	reg [8:0] nc [0:1];
	reg [4:0] last_group [0:1];
	reg [4:0] next_row [0:1];
	reg [4:0] next_group [0:1];
	reg half [0:1];
	reg complete [0:1];
	reg active_slot;
	reg read_complete;
	reg [4:0] expected_read_row;
	reg [4:0] expected_read_group;
	reg [3:0] response_columns;
	wire [255:0] selected_identity = identity[store_slot];
	wire [7:0] identity_equal32;
	genvar _gv_keypart_1;
	generate
		for (_gv_keypart_1 = 0; _gv_keypart_1 < 8; _gv_keypart_1 = _gv_keypart_1 + 1) begin : g_identity_equal32
			localparam keypart = _gv_keypart_1;
			assign identity_equal32[keypart] = selected_identity[keypart * 32+:32] == expected_identity[keypart * 32+:32];
		end
	endgenerate
	wire identity_match = &identity_equal32;
	wire shape_ok = (((rows > 0) && (rows <= BANK_ROWS)) && (columns > 0)) && (columns <= BANK_COLUMNS);
	assign owners = {owner[1], owner[0]};
	assign write_begin_ready = (!rst && !protocol_poison) && (owner[write_slot] == EMPTY);
	assign write_ready = ((((!rst && !protocol_poison) && (owner[write_slot] == FILL)) && !complete[write_slot]) && (write_row == next_row[write_slot])) && (write_group == next_group[write_slot]);
	wire wf = write_valid && write_ready;
	assign store_claim_ready = ((((!rst && !protocol_poison) && (owner[store_slot] == READY)) && identity_match) && (owner[!store_slot] != STORE)) && !output_valid;
	assign read_ready = (((((!rst && !protocol_poison) && (owner[active_slot] == STORE)) && !read_complete) && (!output_valid || output_ready)) && (read_row == expected_read_row)) && (read_group == expected_read_group);
	wire rf = read_valid && read_ready;
	wire [RESULT_ADDR_W - 1:0] write_address;
	wire [RESULT_ADDR_W - 1:0] read_address;
	generate
		if (BANK_COLUMNS == 8) begin : g_one_group
			assign write_address = {write_slot, write_row[ROW_ADDR_W - 1:0]};
			assign read_address = {active_slot, read_row[ROW_ADDR_W - 1:0]};
		end
		else begin : g_channel_page
			assign write_address = {write_slot, write_row[ROW_ADDR_W - 1:0], write_group};
			assign read_address = {active_slot, read_row[ROW_ADDR_W - 1:0], read_group};
		end
	endgenerate
	function automatic [31:0] original_INT32;
		input reg signed [47:0] value;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			if (value[47:32] == {16 {value[31]}}) begin
				original_INT32 = value[31:0];
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				original_INT32 = (value[47] ? 32'h80000000 : 32'h7fffffff);
				_sv2v_jump = 2'b11;
			end
		end
	endfunction
	genvar _gv_lane_3;
	function automatic signed [8:0] sv2v_cast_9_signed;
		input reg signed [8:0] inp;
		sv2v_cast_9_signed = inp;
	endfunction
	generate
		for (_gv_lane_3 = 0; _gv_lane_3 < 8; _gv_lane_3 = _gv_lane_3 + 1) begin : g_lane
			localparam lane = _gv_lane_3;
			wire [31:0] ram_data;
			wire [8:0] absolute_column = {write_group, 3'd0} + sv2v_cast_9_signed(lane);
			wire [31:0] value = (absolute_column < nc[write_slot] ? original_INT32($signed(write_ACC48[lane * 48+:48])) : 32'd0);
			npu_result_word_ram #(
				.WIDTH(32),
				.ADDR_W(RESULT_ADDR_W)
			) ram(
				.clk(clk),
				.wr_en(wf),
				.wr_addr(write_address),
				.wr_data(value),
				.rd_en(rf),
				.rd_addr(read_address),
				.rd_data(ram_data)
			);
			assign output_INT32[lane * 32+:32] = ram_data;
			assign output_strobe[lane * 4+:4] = (output_valid && (lane < response_columns) ? 4'hf : 4'h0);
		end
	endgenerate
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			begin : sv2v_autoblock_1
				integer s;
				for (s = 0; s < 2; s = s + 1)
					begin
						owner[s] <= EMPTY;
						identity[s] <= 0;
						nr[s] <= 0;
						nc[s] <= 0;
						last_group[s] <= 0;
						next_row[s] <= 0;
						next_group[s] <= 0;
						half[s] <= 0;
						complete[s] <= 0;
					end
			end
			active_slot <= 0;
			read_complete <= 0;
			expected_read_row <= 0;
			expected_read_group <= 0;
			response_columns <= 0;
			output_valid <= 0;
			protocol_poison <= 0;
			captured_rows <= 0;
			consumed_groups <= 0;
		end
		else if (!protocol_poison) begin
			if (output_valid && output_ready) begin
				output_valid <= 0;
				consumed_groups <= consumed_groups + 1'b1;
			end
			if (write_begin) begin
				if ((((!write_begin_ready || !shape_ok) || write_valid) || write_commit) || write_abort)
					protocol_poison <= 1;
				else begin
					owner[write_slot] <= FILL;
					identity[write_slot] <= write_identity;
					nr[write_slot] <= rows;
					nc[write_slot] <= columns;
					last_group[write_slot] <= (BANK_COLUMNS == 8 ? 5'd0 : sv2v_cast_5((columns - 1'b1) >> 3));
					next_row[write_slot] <= 0;
					next_group[write_slot] <= 0;
					half[write_slot] <= 0;
					complete[write_slot] <= 0;
				end
			end
			if (write_valid) begin
				if (!write_ready)
					protocol_poison <= 1;
				else begin
					captured_rows <= captured_rows + 1'b1;
					if ((({1'b0, write_row} + 6'd1) >= nr[write_slot]) || (write_row[3:0] == 15)) begin
						if (write_group == last_group[write_slot]) begin
							if (({1'b0, write_row} + 6'd1) >= nr[write_slot])
								complete[write_slot] <= 1;
							else begin
								half[write_slot] <= 1;
								next_row[write_slot] <= 16;
								next_group[write_slot] <= 0;
							end
						end
						else begin
							next_group[write_slot] <= write_group + 1'b1;
							next_row[write_slot] <= (half[write_slot] ? 5'd16 : 5'd0);
						end
					end
					else
						next_row[write_slot] <= write_row + 1'b1;
				end
			end
			if (write_commit) begin
				if ((((owner[write_slot] != FILL) || !complete[write_slot]) || write_valid) || write_abort)
					protocol_poison <= 1;
				else
					owner[write_slot] <= READY;
			end
			if (write_abort) begin
				if ((((owner[write_slot] != FILL) || write_valid) || write_commit) || write_begin)
					protocol_poison <= 1;
				else begin
					owner[write_slot] <= EMPTY;
					complete[write_slot] <= 0;
				end
			end
			if (store_claim) begin
				if (!store_claim_ready || store_release)
					protocol_poison <= 1;
				else begin
					owner[store_slot] <= STORE;
					active_slot <= store_slot;
					read_complete <= 0;
					expected_read_row <= 0;
					expected_read_group <= 0;
				end
			end
			if (read_valid) begin
				if ((((owner[active_slot] != STORE) || read_complete) || (read_row != expected_read_row)) || (read_group != expected_read_group))
					protocol_poison <= 1;
				else if (rf) begin
					output_valid <= 1;
					response_columns <= ((nc[active_slot] - {read_group, 3'd0}) > 8 ? 4'd8 : sv2v_cast_4(nc[active_slot] - {read_group, 3'd0}));
					if (read_group == last_group[active_slot]) begin
						expected_read_group <= 0;
						if (({1'b0, read_row} + 6'd1) >= nr[active_slot])
							read_complete <= 1;
						else
							expected_read_row <= read_row + 1'b1;
					end
					else
						expected_read_group <= read_group + 1'b1;
				end
			end
			if (store_release) begin
				if (((((owner[active_slot] != STORE) || !real_B_retired) || output_valid) || read_valid) || (!read_complete && !store_failed))
					protocol_poison <= 1;
				else
					owner[active_slot] <= EMPTY;
			end
			if (discard_ready) begin
				if ((((((((((owner[store_slot] != READY) || !identity_match) || store_claim) || store_release) || write_begin) || write_valid) || write_commit) || write_abort) || read_valid) || output_valid)
					protocol_poison <= 1;
				else
					owner[store_slot] <= EMPTY;
			end
		end
endmodule
module npu_result_word_ram (
	clk,
	wr_en,
	wr_addr,
	wr_data,
	rd_en,
	rd_addr,
	rd_data
);
	parameter signed [31:0] WIDTH = 32;
	parameter signed [31:0] ADDR_W = 11;
	input wire clk;
	input wire wr_en;
	input wire [ADDR_W - 1:0] wr_addr;
	input wire [WIDTH - 1:0] wr_data;
	input wire rd_en;
	input wire [ADDR_W - 1:0] rd_addr;
	output reg [WIDTH - 1:0] rd_data;
	(* ram_style = "block", syn_ramstyle = "block_ram" *) reg [WIDTH - 1:0] memory [0:(1 << ADDR_W) - 1];
	always @(posedge clk) begin
		if (wr_en)
			memory[wr_addr] <= wr_data;
		if (rd_en)
			rd_data <= memory[rd_addr];
	end
endmodule
module npu_row_result_capture (
	clk,
	rst,
	start_valid,
	start_ready,
	tile_rows,
	row_base,
	channel_group,
	cancel,
	array_read_enable,
	array_read_row,
	array_row_ACC48,
	write_valid,
	write_ready,
	write_row,
	write_group,
	write_ACC48,
	busy,
	done_pulse,
	cancelled,
	bad_start,
	rows_captured
);
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire [4:0] tile_rows;
	input wire [4:0] row_base;
	input wire [4:0] channel_group;
	input wire cancel;
	output wire array_read_enable;
	output wire [3:0] array_read_row;
	input wire [383:0] array_row_ACC48;
	output wire write_valid;
	input wire write_ready;
	output wire [4:0] write_row;
	output wire [4:0] write_group;
	output wire [383:0] write_ACC48;
	output wire busy;
	output reg done_pulse;
	output reg cancelled;
	output reg bad_start;
	output reg [31:0] rows_captured;
	reg active;
	reg pending;
	reg cancel_q;
	reg [4:0] nr;
	reg [4:0] base;
	reg [4:0] group_q;
	reg [4:0] issued;
	reg [4:0] pending_row;
	assign start_ready = (!rst && !active) && !pending;
	assign busy = active || pending;
	assign array_read_enable = ((((!rst && active) && !cancel_q) && !cancel) && (issued < nr)) && (!pending || write_ready);
	assign array_read_row = issued[3:0];
	assign write_valid = !rst && pending;
	assign write_row = pending_row;
	assign write_group = group_q;
	assign write_ACC48 = array_row_ACC48;
	always @(posedge clk) begin
		done_pulse <= 0;
		bad_start <= 0;
		if (rst) begin
			active <= 0;
			pending <= 0;
			cancel_q <= 0;
			cancelled <= 0;
			nr <= 0;
			base <= 0;
			group_q <= 0;
			issued <= 0;
			pending_row <= 0;
			rows_captured <= 0;
		end
		else begin
			if (write_valid && write_ready) begin
				pending <= 0;
				rows_captured <= rows_captured + 1'b1;
			end
			if (array_read_enable) begin
				pending <= 1;
				pending_row <= base + issued;
				issued <= issued + 1'b1;
			end
			if (start_valid && start_ready) begin
				if ((((tile_rows == 0) || (tile_rows > 16)) || (({1'b0, row_base} + {1'b0, tile_rows}) > 32)) || ((row_base != 0) && (row_base != 16)))
					bad_start <= 1;
				else begin
					active <= 1;
					nr <= tile_rows;
					base <= row_base;
					group_q <= channel_group;
					issued <= 0;
					cancel_q <= cancel;
					cancelled <= 0;
				end
			end
			if (active && cancel)
				cancel_q <= 1;
			if (((active && (cancel_q || (issued == nr))) && (!pending || (write_valid && write_ready))) && !array_read_enable) begin
				active <= 0;
				done_pulse <= 1;
				cancelled <= cancel_q;
			end
		end
	end
endmodule
module npu_result_store_bridge (
	clk,
	rst,
	start_valid,
	start_ready,
	start_slot,
	start_identity,
	start_rows,
	start_columns,
	start_base,
	start_stride,
	cancel,
	DMA_exclusive_grant,
	bank_claim,
	bank_slot,
	bank_identity,
	bank_claim_ready,
	bank_read_valid,
	bank_read_row,
	bank_read_group,
	bank_read_ready,
	bank_output_valid,
	bank_output_ready,
	bank_output_INT32,
	bank_output_strobe,
	bank_release,
	bank_real_B_retired,
	bank_store_failed,
	bank_poison,
	dma_job_valid,
	dma_job_ready,
	dma_job,
	dma_job_done,
	dma_job_error,
	dma_error_code,
	dma_outstanding,
	response_order_idle,
	response_order_poison,
	store_elem_vector4,
	store_elem_vector_data,
	store_elem_valid,
	store_elem_ready,
	store_elem_data,
	store_elem_bytes,
	store_elem_row,
	store_elem_col,
	busy,
	done,
	cancelled,
	protocol_poison,
	error_code,
	streamed_elements,
	stream_stall_cycles,
	real_retire_wait_cycles
);
	reg _sv2v_0;
	parameter signed [31:0] MAX_COLUMNS = 256;
	parameter [0:0] VECTOR4_ENABLE = 1'b0;
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire start_slot;
	input wire [255:0] start_identity;
	input wire [4:0] start_rows;
	input wire [8:0] start_columns;
	input wire [31:0] start_base;
	input wire [31:0] start_stride;
	input wire cancel;
	input wire DMA_exclusive_grant;
	output wire bank_claim;
	output reg bank_slot;
	output reg [255:0] bank_identity;
	input wire bank_claim_ready;
	output wire bank_read_valid;
	output wire [4:0] bank_read_row;
	output wire [4:0] bank_read_group;
	input wire bank_read_ready;
	input wire bank_output_valid;
	output wire bank_output_ready;
	input wire [255:0] bank_output_INT32;
	input wire [31:0] bank_output_strobe;
	output wire bank_release;
	output wire bank_real_B_retired;
	output wire bank_store_failed;
	input wire bank_poison;
	output wire dma_job_valid;
	input wire dma_job_ready;
	output reg [100:0] dma_job;
	input wire dma_job_done;
	input wire dma_job_error;
	input wire [7:0] dma_error_code;
	input wire [4:0] dma_outstanding;
	input wire response_order_idle;
	input wire response_order_poison;
	output wire store_elem_vector4;
	output wire [127:0] store_elem_vector_data;
	output wire store_elem_valid;
	input wire store_elem_ready;
	output wire signed [31:0] store_elem_data;
	output wire [2:0] store_elem_bytes;
	output wire [15:0] store_elem_row;
	output wire [15:0] store_elem_col;
	output wire busy;
	output reg done;
	output reg cancelled;
	output reg protocol_poison;
	output reg [7:0] error_code;
	output reg [31:0] streamed_elements;
	output reg [31:0] stream_stall_cycles;
	output reg [31:0] real_retire_wait_cycles;
	reg [2:0] state;
	localparam signed [31:0] COLUMN_W = (MAX_COLUMNS <= 8 ? 4 : 9);
	reg [4:0] rows_q;
	reg [4:0] next_read;
	reg [4:0] row_q;
	reg [4:0] next_group;
	reg [4:0] group_q;
	reg [COLUMN_W - 1:0] columns_q;
	reg [2:0] col_q;
	reg vector4_q;
	wire [3:0] stream_step = (vector4_q ? 4'd4 : 4'd1);
	assign store_elem_vector4 = vector4_q;
	assign store_elem_vector_data = bank_output_INT32[col_q[2] * 128+:128];
	reg [31:0] base_q;
	reg [31:0] stride_q;
	reg pending_row;
	reg all_requested;
	reg cancel_q;
	reg terminal_seen;
	reg terminal_failed;
	wire terminal = dma_job_done || dma_job_error;
	wire lease = (((state == 3'd1) || (state == 3'd2)) || (state == 3'd3)) || (state == 3'd4);
	wire retired = ((terminal_seen && dma_job_ready) && (dma_outstanding == 0)) && response_order_idle;
	assign start_ready = (((!rst && !cancel) && DMA_exclusive_grant) && !protocol_poison) && (state == 3'd0);
	assign busy = state != 3'd0;
	assign dma_job_valid = ((!rst && (state == 3'd1)) && bank_claim_ready) && DMA_exclusive_grant;
	assign bank_claim = ((!rst && (state == 3'd1)) && dma_job_ready) && DMA_exclusive_grant;
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		dma_job = 1'sb0;
		dma_job[100-:2] = 2'd2;
		dma_job[98-:32] = base_q;
		dma_job[66-:32] = stride_q;
		dma_job[34-:16] = sv2v_cast_16(rows_q);
		dma_job[18-:16] = sv2v_cast_16(columns_q);
		dma_job[2-:2] = 2'd0;
		dma_job[0] = bank_slot;
	end
	wire sf = store_elem_valid && store_elem_ready;
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	wire [8:0] remaining_columns = sv2v_cast_9(columns_q) - {group_q, 3'd0};
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	wire [3:0] vector_columns = (remaining_columns > 8 ? 4'd8 : sv2v_cast_4(remaining_columns));
	wire row_done = sf && (({1'b0, col_q} + stream_step) >= vector_columns);
	assign bank_read_valid = ((((!rst && (state == 3'd2)) && !terminal_failed) && !terminal) && (!pending_row || row_done)) && !all_requested;
	assign bank_read_row = next_read;
	assign bank_read_group = next_group;
	assign store_elem_valid = ((((!rst && (state == 3'd2)) && pending_row) && bank_output_valid) && !terminal_failed) && !terminal;
	assign store_elem_data = $signed(bank_output_INT32[32 * col_q+:32]);
	assign store_elem_bytes = 3'd4;
	assign store_elem_row = sv2v_cast_16(row_q);
	assign store_elem_col = sv2v_cast_16({group_q, 3'd0}) + sv2v_cast_16(col_q);
	assign bank_output_ready = ((state == 3'd2) && row_done) || ((state == 3'd3) && terminal_failed);
	assign bank_release = !rst && (state == 3'd4);
	assign bank_real_B_retired = retired;
	assign bank_store_failed = terminal_failed;
	function automatic [COLUMN_W - 1:0] sv2v_cast_7E793;
		input reg [COLUMN_W - 1:0] inp;
		sv2v_cast_7E793 = inp;
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [2:0] sv2v_cast_3;
		input reg [2:0] inp;
		sv2v_cast_3 = inp;
	endfunction
	always @(posedge clk) begin
		done <= 0;
		if (rst) begin
			state <= 3'd0;
			vector4_q <= 0;
			rows_q <= 0;
			columns_q <= 0;
			next_read <= 0;
			row_q <= 0;
			col_q <= 0;
			next_group <= 0;
			group_q <= 0;
			base_q <= 0;
			stride_q <= 0;
			bank_slot <= 0;
			bank_identity <= 0;
			pending_row <= 0;
			all_requested <= 0;
			cancel_q <= 0;
			terminal_seen <= 0;
			terminal_failed <= 0;
			cancelled <= 0;
			protocol_poison <= 0;
			error_code <= 8'd0;
			streamed_elements <= 0;
			stream_stall_cycles <= 0;
			real_retire_wait_cycles <= 0;
		end
		else if (!protocol_poison) begin
			if (busy && cancel)
				cancel_q <= 1;
			if (store_elem_valid && !store_elem_ready)
				stream_stall_cycles <= stream_stall_cycles + 1'b1;
			if ((state == 3'd3) && !retired)
				real_retire_wait_cycles <= real_retire_wait_cycles + 1'b1;
			if (lease && ((!DMA_exclusive_grant || response_order_poison) || bank_poison)) begin
				protocol_poison <= 1;
				error_code <= 8'd11;
				state <= 3'd7;
			end
			else if ((terminal && (state != 3'd2)) && (state != 3'd3)) begin
				protocol_poison <= 1;
				error_code <= 8'd11;
				state <= 3'd7;
			end
			else if (dma_job_done && dma_job_error) begin
				protocol_poison <= 1;
				error_code <= 8'd11;
				state <= 3'd7;
			end
			else begin
				if (terminal) begin
					terminal_seen <= 1;
					if (dma_job_error) begin
						terminal_failed <= 1;
						error_code <= (dma_error_code == 8'd0 ? 8'd11 : dma_error_code);
					end
				end
				case (state)
					3'd0:
						if (start_valid && start_ready) begin
							vector4_q <= ((VECTOR4_ENABLE && (start_columns[1:0] == 0)) && (start_base[3:0] == 0)) && (start_stride[3:0] == 0);
							rows_q <= start_rows;
							columns_q <= sv2v_cast_7E793(start_columns);
							base_q <= start_base;
							stride_q <= start_stride;
							bank_slot <= start_slot;
							bank_identity <= start_identity;
							next_read <= 0;
							row_q <= 0;
							col_q <= 0;
							next_group <= 0;
							group_q <= 0;
							pending_row <= 0;
							all_requested <= 0;
							terminal_seen <= 0;
							terminal_failed <= 0;
							cancel_q <= cancel;
							cancelled <= 0;
							error_code <= 8'd0;
							if ((((start_rows == 0) || (start_rows > 16)) || (start_columns == 0)) || (start_columns > MAX_COLUMNS)) begin
								error_code <= 8'd1;
								state <= 3'd6;
							end
							else if (cancel) begin
								cancelled <= 1;
								state <= 3'd6;
							end
							else
								state <= 3'd1;
						end
					3'd1:
						if (((dma_job_valid && dma_job_ready) && bank_claim) && bank_claim_ready)
							state <= 3'd2;
					3'd2: begin
						if (bank_read_valid && bank_read_ready) begin
							pending_row <= 1;
							row_q <= next_read;
							group_q <= next_group;
							col_q <= 0;
							if ((MAX_COLUMNS == 8) || (({1'b0, next_group, 3'd0} + 9'd8) >= sv2v_cast_9(columns_q))) begin
								next_group <= 0;
								if ((next_read + 5'd1) >= rows_q)
									all_requested <= 1;
								else
									next_read <= next_read + 1'b1;
							end
							else
								next_group <= next_group + 1'b1;
						end
						if (sf) begin
							streamed_elements <= streamed_elements + sv2v_cast_32(stream_step);
							if ((vector4_q ? bank_output_strobe[16 * col_q[2]+:16] != 16'hffff : bank_output_strobe[4 * col_q+:4] != 4'hf)) begin
								protocol_poison <= 1;
								error_code <= 8'd11;
								state <= 3'd7;
							end
							if (row_done) begin
								pending_row <= bank_read_valid && bank_read_ready;
								col_q <= 0;
							end
							else
								col_q <= col_q + sv2v_cast_3(stream_step);
						end
						if (terminal) begin
							if (dma_job_done && (!all_requested || pending_row)) begin
								protocol_poison <= 1;
								error_code <= 8'd11;
								state <= 3'd7;
							end
							else
								state <= 3'd3;
						end
					end
					3'd3: begin
						if (terminal_failed && bank_output_valid)
							pending_row <= 0;
						if (retired && !bank_output_valid)
							state <= 3'd4;
					end
					3'd4:
						if ((retired && !bank_output_valid) && !bank_read_valid)
							state <= 3'd5;
						else begin
							protocol_poison <= 1;
							error_code <= 8'd11;
							state <= 3'd7;
						end
					3'd5: state <= 3'd6;
					3'd6: begin
						done <= 1;
						cancelled <= cancel_q || cancel;
						state <= 3'd0;
					end
					3'd7:
						;
					default: begin
						protocol_poison <= 1;
						error_code <= 8'd11;
						state <= 3'd7;
					end
				endcase
			end
		end
	end
	initial if ((MAX_COLUMNS != 8) && (MAX_COLUMNS != 256)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/rtl/npu/npu_result_store_bridge.sv:166:46 - npu_result_store_bridge.<unnamed_block>\n msg: ", $time, "RESULT_STORE_FIXED_PAGE_CAPACITY_RED");
		$finish(1);
	end
	initial _sv2v_0 = 0;
endmodule
module soc_mini_hdmi_clock (
	sys_clk,
	reset_n,
	pixel_clk,
	serial_clk,
	pll_locked,
	pixel_reset_n
);
	input wire sys_clk;
	input wire reset_n;
	output wire pixel_clk;
	output wire serial_clk;
	output wire pll_locked;
	output wire pixel_reset_n;
	clk_hdmi u_pll(
		.clkin1(sys_clk),
		.clkout0(pixel_clk),
		.clkout1(serial_clk),
		.lock(pll_locked)
	);
	wire reset_release = reset_n && pll_locked;
	(* ASYNC_REG = "TRUE" *) reg [2:0] release_q;
	always @(posedge pixel_clk or negedge reset_release)
		if (!reset_release)
			release_q <= 3'b000;
		else
			release_q <= {release_q[1:0], 1'b1};
	assign pixel_reset_n = release_q[2];
endmodule
module soc_mini_hdmi_tx (
	pixel_clk,
	serial_clk,
	reset_n,
	serial_reset_n,
	rgb888,
	de,
	hsync,
	vsync,
	tmds_data_p,
	tmds_data_n,
	tmds_clk_p,
	tmds_clk_n
);
	input wire pixel_clk;
	input wire serial_clk;
	input wire reset_n;
	input wire serial_reset_n;
	input wire [23:0] rgb888;
	input wire de;
	input wire hsync;
	input wire vsync;
	output wire [2:0] tmds_data_p;
	output wire [2:0] tmds_data_n;
	output wire tmds_clk_p;
	output wire tmds_clk_n;
	soc_rgb2tmds_reset_split u_tx(
		.pixelclk(pixel_clk),
		.serialclk(serial_clk),
		.rstn(reset_n),
		.serial_rstn(serial_reset_n),
		.vid_pdata(rgb888),
		.vid_pvde(de),
		.vid_phsync(hsync),
		.vid_pvsync(vsync),
		.tmds_data_p(tmds_data_p),
		.tmds_data_n(tmds_data_n),
		.tmds_clk_p(tmds_clk_p),
		.tmds_clk_n(tmds_clk_n)
	);
endmodule
module soc_rgb2tmds_reset_split (
	pixelclk,
	serialclk,
	rstn,
	serial_rstn,
	vid_pdata,
	vid_pvde,
	vid_phsync,
	vid_pvsync,
	tmds_data_p,
	tmds_data_n,
	tmds_clk_p,
	tmds_clk_n
);
	input wire pixelclk;
	input wire serialclk;
	input wire rstn;
	input wire serial_rstn;
	input wire [23:0] vid_pdata;
	input wire vid_pvde;
	input wire vid_phsync;
	input wire vid_pvsync;
	output wire [2:0] tmds_data_p;
	output wire [2:0] tmds_data_n;
	output wire tmds_clk_p;
	output wire tmds_clk_n;
	wire [9:0] pdataoutraw [2:0];
	reg pixel_toggle;
	always @(posedge pixelclk or negedge rstn)
		if (!rstn)
			pixel_toggle <= 0;
		else
			pixel_toggle <= !pixel_toggle;
	reg sampled_toggle;
	reg seen_toggle;
	wire load_word = sampled_toggle != seen_toggle;
	always @(posedge serialclk)
		if (!serial_rstn) begin
			sampled_toggle <= 0;
			seen_toggle <= 0;
		end
		else begin
			sampled_toggle <= pixel_toggle;
			seen_toggle <= sampled_toggle;
		end
	genvar _gv_i_1;
	generate
		for (_gv_i_1 = 0; _gv_i_1 < 3; _gv_i_1 = _gv_i_1 + 1) begin : encoder
			localparam i = _gv_i_1;
			tmds_encoder dataencoder(
				.pix_clk(pixelclk),
				.rstn(rstn),
				.din(vid_pdata[i * 8+:8]),
				.de(vid_pvde),
				.c0((i == 0 ? vid_phsync : 1'b0)),
				.c1((i == 0 ? vid_pvsync : 1'b0)),
				.dout(pdataoutraw[i])
			);
		end
	endgenerate
	genvar _gv_lane_4;
	generate
		for (_gv_lane_4 = 0; _gv_lane_4 < 4; _gv_lane_4 = _gv_lane_4 + 1) begin : serializer
			localparam lane = _gv_lane_4;
			wire [9:0] encoded_word;
			if (lane == 3) begin : genblk1
				assign encoded_word = 10'b1111100000;
			end
			else begin : genblk1
				assign encoded_word = pdataoutraw[lane];
			end
			reg [7:0] remaining;
			reg bit_even;
			reg bit_odd;
			always @(posedge serialclk)
				if (!serial_rstn) begin
					remaining <= 0;
					bit_even <= 0;
					bit_odd <= 0;
				end
				else if (load_word) begin
					bit_even <= encoded_word[0];
					bit_odd <= encoded_word[1];
					remaining <= encoded_word[9:2];
				end
				else begin
					bit_even <= remaining[0];
					bit_odd <= remaining[1];
					remaining <= {2'b00, remaining[7:2]};
				end
			wire serial_bit;
			GTP_ODDR_E1 #(
				.ODDR_MODE("SAME_EDGE"),
				.GRS_EN("TRUE"),
				.RS_TYPE("ASYNC_RESET")
			) u_oddr(
				.Q(serial_bit),
				.D0(bit_even),
				.D1(bit_odd),
				.CE(1'b1),
				.CLK(serialclk),
				.RS(1'b0)
			);
			if (lane == 3) begin : genblk2
				GTP_OUTBUFDS #(.IOSTANDARD("TMDS")) u_buf(
					.O(tmds_clk_p),
					.OB(tmds_clk_n),
					.I(serial_bit)
				);
			end
			else begin : genblk2
				GTP_OUTBUFDS #(.IOSTANDARD("TMDS")) u_buf(
					.O(tmds_data_p[lane]),
					.OB(tmds_data_n[lane]),
					.I(serial_bit)
				);
			end
		end
	endgenerate
endmodule
module soc_hmic_axi_adapter (
	clk,
	rst,
	ddr_ready,
	protocol_fault,
	s_awid,
	s_awaddr,
	s_awlen,
	s_awsize,
	s_awburst,
	s_awvalid,
	s_awready,
	s_wdata,
	s_wstrb,
	s_wlast,
	s_wvalid,
	s_wready,
	s_bid,
	s_bresp,
	s_bvalid,
	s_bready,
	s_arid,
	s_araddr,
	s_arlen,
	s_arsize,
	s_arburst,
	s_arvalid,
	s_arready,
	s_rid,
	s_rdata,
	s_rresp,
	s_rlast,
	s_rvalid,
	s_rready,
	m_awid,
	m_awaddr,
	m_awlen,
	m_awsize,
	m_awburst,
	m_awvalid,
	m_awready,
	m_wdata,
	m_wstrb,
	m_wlast,
	m_wvalid,
	m_wready,
	m_bid,
	m_bresp,
	m_bvalid,
	m_bready,
	m_arid,
	m_araddr,
	m_arlen,
	m_arsize,
	m_arburst,
	m_arvalid,
	m_arready,
	m_rid,
	m_rdata,
	m_rresp,
	m_rlast,
	m_rvalid,
	m_rready
);
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [32:0] DDR_BYTES = 33'h010000000;
	parameter signed [31:0] WATCHDOG_CYCLES = 65536;
	parameter [0:0] STREAM_READ = 1'b1;
	parameter [0:0] STREAM_WRITE = 1'b1;
	parameter [0:0] DISJOINT_RW_OVERLAP = 1'b1;
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	output wire protocol_fault;
	input wire [3:0] s_awid;
	input wire [31:0] s_awaddr;
	input wire [7:0] s_awlen;
	input wire [2:0] s_awsize;
	input wire [1:0] s_awburst;
	input wire s_awvalid;
	output wire s_awready;
	input wire [127:0] s_wdata;
	input wire [15:0] s_wstrb;
	input wire s_wlast;
	input wire s_wvalid;
	output wire s_wready;
	output wire [3:0] s_bid;
	output wire [1:0] s_bresp;
	output wire s_bvalid;
	input wire s_bready;
	input wire [3:0] s_arid;
	input wire [31:0] s_araddr;
	input wire [7:0] s_arlen;
	input wire [2:0] s_arsize;
	input wire [1:0] s_arburst;
	input wire s_arvalid;
	output wire s_arready;
	output wire [3:0] s_rid;
	output wire [127:0] s_rdata;
	output wire [1:0] s_rresp;
	output wire s_rlast;
	output wire s_rvalid;
	input wire s_rready;
	output wire [7:0] m_awid;
	output wire [29:0] m_awaddr;
	output wire [7:0] m_awlen;
	output wire [2:0] m_awsize;
	output wire [1:0] m_awburst;
	output wire m_awvalid;
	input wire m_awready;
	output wire [255:0] m_wdata;
	output wire [31:0] m_wstrb;
	output wire m_wlast;
	output wire m_wvalid;
	input wire m_wready;
	input wire [7:0] m_bid;
	input wire [1:0] m_bresp;
	input wire m_bvalid;
	output wire m_bready;
	output wire [7:0] m_arid;
	output wire [29:0] m_araddr;
	output wire [7:0] m_arlen;
	output wire [2:0] m_arsize;
	output wire [1:0] m_arburst;
	output wire m_arvalid;
	input wire m_arready;
	input wire [7:0] m_rid;
	input wire [255:0] m_rdata;
	input wire [1:0] m_rresp;
	input wire m_rlast;
	input wire m_rvalid;
	output wire m_rready;
	localparam signed [31:0] WATCHDOG_W = $clog2(WATCHDOG_CYCLES);
	reg [3:0] state;
	reg [2:0] prefetch_state;
	(* syn_ramstyle = "distributed_ram" *) reg [127:0] wdata_low [0:15];
	(* syn_ramstyle = "distributed_ram" *) reg [127:0] wdata_high [0:15];
	(* syn_ramstyle = "distributed_ram" *) reg [255:0] rdata_memory [0:31];
	reg [31:0] mask_q [0:8];
	reg [1:0] resp_q [0:1][0:8];
	reg [29:0] addr_q;
	reg [3:0] id_q;
	reg [8:0] logical_count_q;
	reg [8:0] logical_index_q;
	reg [3:0] physical_count_q;
	reg [3:0] physical_index_q;
	reg first_half_q;
	reg prefer_read_q;
	reg [1:0] bresp_q;
	reg active_aw_sent;
	reg prefetch_aw_sent;
	wire active_collect = (state == 4'd1) && (logical_index_q < logical_count_q);
	wire stream_active = STREAM_WRITE && (state == 4'd1);
	reg prefetch_bad;
	wire stream_prefetch = (STREAM_WRITE && (prefetch_state == 3'd3)) && !prefetch_bad;
	function automatic [9:0] sv2v_cast_10;
		input reg [9:0] inp;
		sv2v_cast_10 = inp;
	endfunction
	wire active_word_ready = (physical_index_q < physical_count_q) && ((sv2v_cast_10(physical_index_q) < (({1'b0, logical_index_q} + sv2v_cast_10(first_half_q)) >> 1)) || (logical_index_q == logical_count_q));
	reg prefetch_first_half;
	reg [8:0] prefetch_logical_count;
	reg [8:0] prefetch_logical_index;
	reg [3:0] prefetch_physical_count;
	reg [3:0] prefetch_physical_index;
	wire prefetch_word_ready = (prefetch_physical_index < prefetch_physical_count) && ((sv2v_cast_10(prefetch_physical_index) < (({1'b0, prefetch_logical_index} + sv2v_cast_10(prefetch_first_half)) >> 1)) || (prefetch_logical_index == prefetch_logical_count));
	wire stream_write_valid = (stream_active && active_aw_sent) && active_word_ready;
	wire stream_prefetch_write_valid = (stream_prefetch && prefetch_aw_sent) && prefetch_word_ready;
	wire [9:0] half_index = {1'b0, logical_index_q} + sv2v_cast_10(first_half_q);
	wire stream_read_valid = (STREAM_READ && (state == 4'd7)) && (half_index[4:1] < physical_index_q);
	wire active_aw_phase = (state == 4'd2) || stream_active;
	wire prefetch_aw_phase = (prefetch_state == 3'd4) || stream_prefetch;
	wire active_w_phase = (state == 4'd3) || stream_active;
	wire prefetch_w_phase = (prefetch_state == 3'd5) || (stream_prefetch && prefetch_aw_sent);
	reg [WATCHDOG_W - 1:0] watchdog_q;
	reg active_bank;
	reg prefetch_valid;
	reg prefetch_write;
	reg [3:0] prefetch_id;
	reg [29:0] prefetch_addr;
	reg [1:0] prefetch_bresp;
	wire [9:0] prefetch_half_index = {1'b0, prefetch_logical_index} + sv2v_cast_10(prefetch_first_half);
	wire [3:0] data_read_index = ((state == 4'd8) || (STREAM_READ && (state == 4'd7)) ? half_index[4:1] : physical_index_q);
	wire [255:0] selected_data = rdata_memory[{active_bank, data_read_index}];
	wire write_fill_active = (active_collect && s_wvalid) && s_wready;
	wire write_fill_prefetch = ((((prefetch_state == 3'd3) && !active_collect) && s_wvalid) && s_wready) && !prefetch_bad;
	wire [9:0] write_fill_half = (write_fill_active ? half_index : prefetch_half_index);
	wire clear_active_mask = ((state == 4'd0) && s_awvalid) && s_awready;
	wire read_fill_active = state == 4'd7;
	wire read_fill_prefetch = prefetch_state == 3'd2;
	wire read_fill_bank = (read_fill_active ? active_bank : ~active_bank);
	wire [3:0] read_fill_index = (read_fill_active ? physical_index_q : prefetch_physical_index);
	wire choose_read = s_arvalid && (!s_awvalid || prefer_read_q);
	wire final_read_fire = (((state == 4'd8) && s_rvalid) && s_rready) && s_rlast;
	wire final_write_fire = ((state == 4'd5) && s_bvalid) && s_bready;
	wire offer_prefetch = ((((((((((state == 4'd2) || (state == 4'd3)) || (state == 4'd4)) || (state == 4'd6)) || (state == 4'd7)) || (state == 4'd8)) || (state == 4'd5)) || (stream_active && (logical_index_q == logical_count_q))) && !prefetch_valid) && !final_read_fire) && !final_write_fire;
	wire prefetch_issue_safe = ((state == 4'd8) || (state == 4'd5)) || (state == 4'd12);
	wire [30:0] active_end = {1'b0, addr_q} + ({27'd0, physical_count_q} << 5);
	wire [30:0] pending_end = {1'b0, prefetch_addr} + ({27'd0, prefetch_physical_count} << 5);
	wire disjoint_physical = (active_end <= {1'b0, prefetch_addr}) || (pending_end <= {1'b0, addr_q});
	wire active_read_inflight = state == 4'd7;
	wire active_write_inflight = ((state == 4'd3) || (state == 4'd4)) || (stream_active && active_aw_sent);
	wire pending_read_issue_safe = prefetch_issue_safe || (((DISJOINT_RW_OVERLAP && disjoint_physical) && !prefetch_write) && active_write_inflight);
	wire pending_write_issue_safe = prefetch_issue_safe || (((DISJOINT_RW_OVERLAP && disjoint_physical) && prefetch_write) && active_read_inflight);
	wire write_slot_available = (((((((state == 4'd6) || (state == 4'd7)) || (state == 4'd8)) || (state == 4'd4)) || (state == 4'd5)) || (state == 4'd12)) || ((state == 4'd3) && (prefetch_half_index[4:1] < physical_index_q))) || ((stream_active && (logical_index_q == logical_count_q)) && (prefetch_half_index[4:1] < physical_index_q));
	wire wait_controller = (((((((((((state == 4'd2) || (state == 4'd3)) || (state == 4'd4)) || (state == 4'd6)) || (state == 4'd7)) || (prefetch_state == 3'd1)) || (prefetch_state == 3'd2)) || (prefetch_state == 3'd4)) || (prefetch_state == 3'd5)) || (prefetch_state == 3'd6)) || (stream_active && (!active_aw_sent || stream_write_valid))) || ((stream_prefetch && pending_write_issue_safe) && ((!prefetch_aw_sent && (prefetch_logical_index != 0)) || stream_prefetch_write_valid));
	wire controller_progress = ((((m_awvalid && m_awready) || (m_wvalid && m_wready)) || (m_bvalid && m_bready)) || (m_arvalid && m_arready)) || (m_rvalid && ((state == 4'd7) || (prefetch_state == 3'd2)));
	function automatic [32:0] sv2v_cast_33;
		input reg [32:0] inp;
		sv2v_cast_33 = inp;
	endfunction
	function automatic legal;
		input reg [31:0] a;
		input reg [7:0] len;
		input reg [2:0] size;
		input reg [1:0] burst;
		reg [32:0] limit;
		begin
			limit = {1'b0, a} + ((sv2v_cast_33(len) + 1) << 4);
			legal = ((((((len < 16) && (size == 4)) && (burst == 1)) && (a[3:0] == 0)) && ({1'b0, a} >= {1'b0, DDR_BASE})) && (limit <= ({1'b0, DDR_BASE} + DDR_BYTES))) && ((sv2v_cast_33(a[11:0]) + ((sv2v_cast_33(len) + 1) << 4)) <= 4096);
		end
	endfunction
	assign protocol_fault = state == 4'd11;
	assign s_awready = (!rst && ddr_ready) && (((state == 4'd0) && !choose_read) || ((offer_prefetch && s_awvalid) && !choose_read));
	assign s_arready = (!rst && ddr_ready) && (((state == 4'd0) && choose_read) || (offer_prefetch && choose_read));
	assign s_wready = (!rst && !protocol_fault) && ((active_collect || (state == 4'd9)) || (((prefetch_state == 3'd3) && (prefetch_logical_index < prefetch_logical_count)) && (prefetch_bad || write_slot_available)));
	assign s_bid = id_q;
	assign s_bresp = bresp_q;
	assign s_bvalid = !rst && (state == 4'd5);
	assign s_rid = id_q;
	assign s_rdata = selected_data[128 * half_index[0]+:128];
	assign s_rresp = ((state == 4'd8) || stream_read_valid ? resp_q[active_bank][half_index[4:1]] : 2'b11);
	assign s_rvalid = !rst && (((state == 4'd8) || (state == 4'd10)) || stream_read_valid);
	assign s_rlast = (logical_index_q + 1) == logical_count_q;
	assign m_awid = (!active_aw_phase && prefetch_aw_phase ? {4'b0000, prefetch_id} : {4'b0000, id_q});
	assign m_arid = ((state != 4'd6) && (prefetch_state == 3'd1) ? {4'b0000, prefetch_id} : {4'b0000, id_q});
	assign m_awaddr = (!active_aw_phase && prefetch_aw_phase ? prefetch_addr : addr_q);
	assign m_araddr = ((state != 4'd6) && (prefetch_state == 3'd1) ? prefetch_addr : addr_q);
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	assign m_awlen = (!active_aw_phase && prefetch_aw_phase ? sv2v_cast_8(prefetch_physical_count) - 1 : sv2v_cast_8(physical_count_q) - 1);
	assign m_arlen = ((state != 4'd6) && (prefetch_state == 3'd1) ? sv2v_cast_8(prefetch_physical_count) - 1 : sv2v_cast_8(physical_count_q) - 1);
	assign m_awsize = 5;
	assign m_arsize = 5;
	assign m_awburst = 1;
	assign m_arburst = 1;
	assign m_awvalid = (!rst && ddr_ready) && (((state == 4'd2) || (stream_active && !active_aw_sent)) || (((prefetch_state == 3'd4) || ((stream_prefetch && !prefetch_aw_sent) && (prefetch_logical_index != 0))) && pending_write_issue_safe));
	assign m_arvalid = (!rst && ddr_ready) && ((state == 4'd6) || ((prefetch_state == 3'd1) && pending_read_issue_safe));
	wire [3:0] write_data_read_index = (prefetch_w_phase ? prefetch_physical_index : physical_index_q);
	assign m_wdata = {wdata_high[write_data_read_index], wdata_low[write_data_read_index]};
	assign m_wstrb = (prefetch_w_phase ? mask_q[prefetch_physical_index] : (active_w_phase ? mask_q[physical_index_q] : {32 {1'sb0}}));
	assign m_wlast = (prefetch_w_phase ? (prefetch_physical_index + 1) == prefetch_physical_count : (physical_index_q + 1) == physical_count_q);
	assign m_wvalid = ((!rst && ddr_ready) && !protocol_fault) && ((((state == 4'd3) || (prefetch_state == 3'd5)) || stream_write_valid) || stream_prefetch_write_valid);
	assign m_bready = (!rst && !protocol_fault) && ((state == 4'd4) || (prefetch_state == 3'd6));
	assign m_rready = 1'b1;
	initial if ((((((DDR_BASE[4:0] != 0) || (DDR_BYTES[4:0] != 0)) || (DDR_BYTES == 0)) || (DDR_BYTES > 33'h040000000)) || (({1'b0, DDR_BASE} + DDR_BYTES) > 33'h100000000)) || (WATCHDOG_CYCLES < 2)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_hmic_axi_adapter.sv:256:13 - soc_hmic_axi_adapter.<unnamed_block>.<unnamed_block>\n msg: ", $time, "HMIC_ADAPTER_CONFIGURATION");
		$finish(1);
	end
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	function automatic [29:0] sv2v_cast_30;
		input reg [29:0] inp;
		sv2v_cast_30 = inp;
	endfunction
	function automatic signed [WATCHDOG_W - 1:0] sv2v_cast_39612_signed;
		input reg signed [WATCHDOG_W - 1:0] inp;
		sv2v_cast_39612_signed = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			state <= 4'd0;
			addr_q <= 0;
			id_q <= 0;
			logical_count_q <= 0;
			logical_index_q <= 0;
			physical_count_q <= 0;
			physical_index_q <= 0;
			first_half_q <= 0;
			bresp_q <= 0;
			watchdog_q <= 0;
			prefer_read_q <= 0;
			active_aw_sent <= 0;
			prefetch_aw_sent <= 0;
			active_bank <= 0;
			prefetch_state <= 3'd0;
			prefetch_valid <= 0;
			prefetch_bad <= 0;
			prefetch_write <= 0;
			prefetch_logical_index <= 0;
			prefetch_bresp <= 0;
			prefetch_id <= 0;
			prefetch_addr <= 0;
			prefetch_logical_count <= 0;
			prefetch_physical_count <= 0;
			prefetch_physical_index <= 0;
			prefetch_first_half <= 0;
		end
		else begin
			if (!wait_controller || controller_progress)
				watchdog_q <= 0;
			else
				watchdog_q <= watchdog_q + 1'b1;
			case (state)
				4'd0: begin
					logical_index_q <= 0;
					physical_index_q <= 0;
					active_aw_sent <= 0;
					if (s_awvalid && s_awready) begin
						id_q <= s_awid;
						logical_count_q <= sv2v_cast_9(s_awlen) + 1;
						first_half_q <= s_awaddr[4];
						physical_count_q <= sv2v_cast_4(((sv2v_cast_10(s_awlen) + 10'd2) + sv2v_cast_10(s_awaddr[4])) >> 1);
						addr_q <= sv2v_cast_30((s_awaddr - DDR_BASE) & 32'hffffffe0);
						bresp_q <= 0;
						prefer_read_q <= 1;
						state <= (legal(s_awaddr, s_awlen, s_awsize, s_awburst) ? 4'd1 : 4'd9);
					end
					else if (s_arvalid && s_arready) begin
						id_q <= s_arid;
						logical_count_q <= sv2v_cast_9(s_arlen) + 1;
						first_half_q <= s_araddr[4];
						physical_count_q <= sv2v_cast_4(((sv2v_cast_10(s_arlen) + 10'd2) + sv2v_cast_10(s_araddr[4])) >> 1);
						addr_q <= sv2v_cast_30((s_araddr - DDR_BASE) & 32'hffffffe0);
						prefer_read_q <= 0;
						state <= (legal(s_araddr, s_arlen, s_arsize, s_arburst) ? 4'd6 : 4'd10);
					end
				end
				4'd1:
					if (STREAM_WRITE) begin
						if (m_awvalid && m_awready)
							active_aw_sent <= 1'b1;
						if ((s_wvalid && s_wready) && active_collect)
							logical_index_q <= logical_index_q + 1'b1;
						if (stream_write_valid && m_wready) begin
							physical_index_q <= physical_index_q + 1'b1;
							if (m_wlast)
								state <= 4'd4;
						end
						if (((s_wvalid && s_wready) && active_collect) && (s_wlast != ((logical_index_q + 1) == logical_count_q)))
							state <= 4'd11;
					end
					else if (s_wvalid && s_wready) begin
						logical_index_q <= logical_index_q + 1'b1;
						if (s_wlast != ((logical_index_q + 1) == logical_count_q))
							state <= 4'd11;
						else if (s_wlast)
							state <= 4'd2;
					end
				4'd9:
					if (s_wvalid && s_wready) begin
						logical_index_q <= logical_index_q + 1'b1;
						if (s_wlast != ((logical_index_q + 1) == logical_count_q))
							state <= 4'd11;
						else if (s_wlast) begin
							state <= 4'd5;
							bresp_q <= 2'b11;
						end
					end
				4'd2:
					if (m_awvalid && m_awready)
						state <= 4'd3;
				4'd3:
					if (m_wvalid && m_wready) begin
						physical_index_q <= physical_index_q + 1'b1;
						if (m_wlast)
							state <= 4'd4;
					end
				4'd4:
					if (m_bvalid && m_bready) begin
						bresp_q <= m_bresp;
						state <= (m_bid == {4'b0000, id_q} ? 4'd5 : 4'd11);
					end
				4'd5:
					if (s_bvalid && s_bready)
						state <= (prefetch_valid ? 4'd12 : 4'd0);
				4'd6:
					if (m_arvalid && m_arready)
						state <= 4'd7;
				4'd7: begin
					if (s_rvalid && s_rready)
						logical_index_q <= logical_index_q + 1'b1;
					if (m_rvalid) begin
						physical_index_q <= physical_index_q + 1'b1;
						if ((m_rid != {4'b0000, id_q}) || (m_rlast != ((physical_index_q + 1) == physical_count_q)))
							state <= 4'd11;
						else if (m_rlast)
							state <= 4'd8;
					end
				end
				4'd8, 4'd10:
					if (s_rvalid && s_rready) begin
						logical_index_q <= logical_index_q + 1'b1;
						if (s_rlast)
							state <= ((state == 4'd8) && prefetch_valid ? 4'd12 : 4'd0);
					end
				4'd12:
					if (prefetch_state == 3'd7) begin
						id_q <= prefetch_id;
						logical_count_q <= prefetch_logical_count;
						logical_index_q <= 0;
						physical_index_q <= 0;
						physical_count_q <= prefetch_physical_count;
						first_half_q <= prefetch_first_half;
						addr_q <= prefetch_addr;
						active_bank <= ~active_bank;
						if (prefetch_write) begin
							bresp_q <= prefetch_bresp;
							state <= 4'd5;
						end
						else
							state <= (prefetch_bad ? 4'd10 : 4'd8);
						prefetch_valid <= 0;
						prefetch_state <= 3'd0;
					end
				default: state <= 4'd11;
			endcase
			if (offer_prefetch && ((s_arvalid && s_arready) || (s_awvalid && s_awready))) begin
				prefetch_valid <= 1;
				prefetch_id <= s_arid;
				prefetch_aw_sent <= 0;
				prefetch_write <= s_awvalid && s_awready;
				prefetch_id <= (s_awvalid && s_awready ? s_awid : s_arid);
				prefetch_logical_count <= (s_awvalid && s_awready ? sv2v_cast_9(s_awlen) + 1 : sv2v_cast_9(s_arlen) + 1);
				prefetch_logical_index <= 0;
				prefetch_first_half <= (s_awvalid && s_awready ? s_awaddr[4] : s_araddr[4]);
				prefetch_physical_count <= (s_awvalid && s_awready ? sv2v_cast_4(((sv2v_cast_10(s_awlen) + 10'd2) + sv2v_cast_10(s_awaddr[4])) >> 1) : sv2v_cast_4(((sv2v_cast_10(s_arlen) + 10'd2) + sv2v_cast_10(s_araddr[4])) >> 1));
				prefetch_physical_index <= 0;
				prefetch_addr <= (s_awvalid && s_awready ? sv2v_cast_30((s_awaddr - DDR_BASE) & 32'hffffffe0) : sv2v_cast_30((s_araddr - DDR_BASE) & 32'hffffffe0));
				prefetch_bad <= (s_awvalid && s_awready ? !legal(s_awaddr, s_awlen, s_awsize, s_awburst) : !legal(s_araddr, s_arlen, s_arsize, s_arburst));
				if (s_awvalid && s_awready) begin
					prefetch_bresp <= 0;
					prefetch_state <= 3'd3;
				end
				else
					prefetch_state <= (legal(s_araddr, s_arlen, s_arsize, s_arburst) ? 3'd1 : 3'd7);
			end
			else
				case (prefetch_state)
					3'd1:
						if ((m_arvalid && m_arready) && pending_read_issue_safe)
							prefetch_state <= 3'd2;
					3'd2:
						if (m_rvalid) begin
							prefetch_physical_index <= prefetch_physical_index + 1'b1;
							if ((m_rid != {4'b0000, prefetch_id}) || (m_rlast != ((prefetch_physical_index + 1) == prefetch_physical_count)))
								state <= 4'd11;
							else if (m_rlast)
								prefetch_state <= 3'd7;
						end
					3'd3:
						if (STREAM_WRITE && !prefetch_bad) begin
							if ((m_awvalid && m_awready) && pending_write_issue_safe)
								prefetch_aw_sent <= 1'b1;
							if ((s_wvalid && s_wready) && !active_collect)
								prefetch_logical_index <= prefetch_logical_index + 1'b1;
							if (stream_prefetch_write_valid && m_wready) begin
								prefetch_physical_index <= prefetch_physical_index + 1'b1;
								if (m_wlast)
									prefetch_state <= 3'd6;
							end
							if (((s_wvalid && s_wready) && !active_collect) && (s_wlast != ((prefetch_logical_index + 1) == prefetch_logical_count)))
								state <= 4'd11;
						end
						else if ((s_wvalid && s_wready) && !active_collect) begin
							prefetch_logical_index <= prefetch_logical_index + 1'b1;
							if (s_wlast != ((prefetch_logical_index + 1) == prefetch_logical_count))
								state <= 4'd11;
							else if (s_wlast) begin
								if (prefetch_bad) begin
									prefetch_bresp <= 2'b11;
									prefetch_state <= 3'd7;
								end
								else
									prefetch_state <= 3'd4;
							end
						end
					3'd4:
						if ((m_awvalid && m_awready) && pending_write_issue_safe)
							prefetch_state <= 3'd5;
					3'd5:
						if (m_wvalid && m_wready) begin
							prefetch_physical_index <= prefetch_physical_index + 1'b1;
							if (m_wlast)
								prefetch_state <= 3'd6;
						end
					3'd6:
						if (m_bvalid && m_bready) begin
							prefetch_bresp <= m_bresp;
							if (m_bid != {4'b0000, prefetch_id})
								state <= 4'd11;
							else
								prefetch_state <= 3'd7;
						end
					default:
						;
				endcase
			if ((((state != 4'd0) && !ddr_ready) || ((wait_controller && !controller_progress) && (watchdog_q == sv2v_cast_39612_signed(WATCHDOG_CYCLES - 1)))) || ((m_rvalid && (state != 4'd7)) && (prefetch_state != 3'd2)))
				state <= 4'd11;
		end
	always @(posedge clk)
		if (((!rst && !clear_active_mask) && (write_fill_active || write_fill_prefetch)) && (write_fill_half[4:1] < 4'd9)) begin
			if (write_fill_half[0] == 1'b0)
				wdata_low[write_fill_half[4:1]] <= s_wdata;
			if (write_fill_half[0] == 1'b1)
				wdata_high[write_fill_half[4:1]] <= s_wdata;
		end
	always @(posedge clk)
		if (((!rst && m_rvalid) && (read_fill_active || read_fill_prefetch)) && (read_fill_index < 4'd9))
			rdata_memory[{read_fill_bank, read_fill_index}] <= m_rdata;
	genvar _gv_beat_1;
	generate
		for (_gv_beat_1 = 0; _gv_beat_1 < 9; _gv_beat_1 = _gv_beat_1 + 1) begin : GEN_WRITE_BEAT
			localparam beat = _gv_beat_1;
			always @(posedge clk)
				if (!rst) begin
					if (clear_active_mask)
						mask_q[beat] <= 0;
					else if ((write_fill_active || write_fill_prefetch) && (write_fill_half[4:1] == beat[3:0])) begin
						if (write_fill_prefetch && ((prefetch_logical_index == 0) || !prefetch_half_index[0]))
							mask_q[beat] <= (write_fill_half[0] ? {s_wstrb, 16'b0000000000000000} : {16'b0000000000000000, s_wstrb});
						else
							mask_q[beat][16 * write_fill_half[0]+:16] <= s_wstrb;
					end
				end
		end
	endgenerate
	genvar _gv_bank_1;
	generate
		for (_gv_bank_1 = 0; _gv_bank_1 < 2; _gv_bank_1 = _gv_bank_1 + 1) begin : GEN_BANK
			localparam bank = _gv_bank_1;
			genvar _gv_beat_2;
			for (_gv_beat_2 = 0; _gv_beat_2 < 9; _gv_beat_2 = _gv_beat_2 + 1) begin : GEN_BEAT
				localparam beat = _gv_beat_2;
				always @(posedge clk)
					if (!rst) begin
						if (((m_rvalid && (read_fill_active || read_fill_prefetch)) && (read_fill_bank == bank[0])) && (read_fill_index == beat[3:0]))
							resp_q[bank][beat] <= m_rresp;
					end
			end
		end
	endgenerate
endmodule
module soc_axi_2m_arbiter (
	clk,
	rst,
	busy,
	s_awid,
	s_awaddr,
	s_awlen,
	s_awsize,
	s_awburst,
	s_awvalid,
	s_awready,
	s_wdata,
	s_wstrb,
	s_wlast,
	s_wvalid,
	s_wready,
	s_bid,
	s_bresp,
	s_bvalid,
	s_bready,
	s_arid,
	s_araddr,
	s_arlen,
	s_arsize,
	s_arburst,
	s_arvalid,
	s_arready,
	s_rid,
	s_rdata,
	s_rresp,
	s_rlast,
	s_rvalid,
	s_rready,
	m_awid,
	m_awaddr,
	m_awlen,
	m_awsize,
	m_awburst,
	m_awvalid,
	m_awready,
	m_wdata,
	m_wstrb,
	m_wlast,
	m_wvalid,
	m_wready,
	m_bid,
	m_bresp,
	m_bvalid,
	m_bready,
	m_arid,
	m_araddr,
	m_arlen,
	m_arsize,
	m_arburst,
	m_arvalid,
	m_arready,
	m_rid,
	m_rdata,
	m_rresp,
	m_rlast,
	m_rvalid,
	m_rready
);
	reg _sv2v_0;
	parameter signed [31:0] DATA_W = 128;
	parameter signed [31:0] ADDR_W = 32;
	parameter signed [31:0] ID_W = 4;
	parameter [0:0] ENABLE_PENDING_QUEUE = 1;
	parameter [0:0] DIRECT_ACCEPT = 1'b1;
	parameter [0:0] SAME_MASTER_QUEUE = 1'b1;
	input wire clk;
	input wire rst;
	output wire busy;
	input wire [(2 * ID_W) - 1:0] s_awid;
	input wire [(2 * ADDR_W) - 1:0] s_awaddr;
	input wire [15:0] s_awlen;
	input wire [5:0] s_awsize;
	input wire [3:0] s_awburst;
	input wire [1:0] s_awvalid;
	output reg [1:0] s_awready;
	input wire [(2 * DATA_W) - 1:0] s_wdata;
	input wire [(2 * (DATA_W / 8)) - 1:0] s_wstrb;
	input wire [1:0] s_wlast;
	input wire [1:0] s_wvalid;
	output reg [1:0] s_wready;
	output reg [(2 * ID_W) - 1:0] s_bid;
	output reg [3:0] s_bresp;
	output reg [1:0] s_bvalid;
	input wire [1:0] s_bready;
	input wire [(2 * ID_W) - 1:0] s_arid;
	input wire [(2 * ADDR_W) - 1:0] s_araddr;
	input wire [15:0] s_arlen;
	input wire [5:0] s_arsize;
	input wire [3:0] s_arburst;
	input wire [1:0] s_arvalid;
	output reg [1:0] s_arready;
	output reg [(2 * ID_W) - 1:0] s_rid;
	output reg [(2 * DATA_W) - 1:0] s_rdata;
	output reg [3:0] s_rresp;
	output reg [1:0] s_rlast;
	output reg [1:0] s_rvalid;
	input wire [1:0] s_rready;
	output reg [ID_W - 1:0] m_awid;
	output reg [ADDR_W - 1:0] m_awaddr;
	output reg [7:0] m_awlen;
	output reg [2:0] m_awsize;
	output reg [1:0] m_awburst;
	output reg m_awvalid;
	input wire m_awready;
	output wire [DATA_W - 1:0] m_wdata;
	output wire [(DATA_W / 8) - 1:0] m_wstrb;
	output wire m_wlast;
	output wire m_wvalid;
	input wire m_wready;
	input wire [ID_W - 1:0] m_bid;
	input wire [1:0] m_bresp;
	input wire m_bvalid;
	output reg m_bready;
	output reg [ID_W - 1:0] m_arid;
	output reg [ADDR_W - 1:0] m_araddr;
	output reg [7:0] m_arlen;
	output reg [2:0] m_arsize;
	output reg [1:0] m_arburst;
	output reg m_arvalid;
	input wire m_arready;
	input wire [ID_W - 1:0] m_rid;
	input wire [DATA_W - 1:0] m_rdata;
	input wire [1:0] m_rresp;
	input wire m_rlast;
	input wire m_rvalid;
	output reg m_rready;
	reg [2:0] state;
	reg owner;
	reg next_owner;
	reg [1:0] prefer_read;
	wire [1:0] requesting;
	wire selected_owner;
	wire selected_read;
	reg [ID_W - 1:0] command_id;
	reg [ADDR_W - 1:0] command_addr;
	reg [7:0] command_len;
	reg [2:0] command_size;
	reg [1:0] command_burst;
	reg pending_valid;
	reg pending_read;
	reg pending_owner;
	reg pending_sent;
	reg pending_w_done;
	reg [ID_W - 1:0] pending_id;
	reg [ADDR_W - 1:0] pending_addr;
	reg [7:0] pending_len;
	reg [2:0] pending_size;
	reg [1:0] pending_burst;
	wire other_owner;
	wire queue_owner;
	wire queue_read;
	wire queue_offer;
	wire queue_accept;
	wire active_complete;
	wire early_pending_ar;
	wire early_pending_aw;
	wire early_pending_w;
	wire early_pending_w_done;
	wire pending_address_fire = (early_pending_ar && m_arready) || (early_pending_aw && m_awready);
	assign requesting = s_awvalid | s_arvalid;
	wire choose_next_owner = (DIRECT_ACCEPT && active_complete ? ~owner : next_owner);
	wire direct_window = DIRECT_ACCEPT && ((state == 3'd0) || (active_complete && !pending_valid));
	assign selected_owner = (requesting[choose_next_owner] ? choose_next_owner : ~choose_next_owner);
	assign selected_read = s_arvalid[selected_owner] && (!s_awvalid[selected_owner] || ((DIRECT_ACCEPT && active_complete) && (selected_owner == owner) ? state == 3'd4 : prefer_read[selected_owner]));
	assign other_owner = ~owner;
	assign queue_owner = (requesting[other_owner] || !SAME_MASTER_QUEUE ? other_owner : owner);
	assign queue_read = s_arvalid[queue_owner] && (!s_awvalid[queue_owner] || (SAME_MASTER_QUEUE && (queue_owner == owner) ? ((state == 3'd2) || (state == 3'd3)) || (state == 3'd4) : prefer_read[queue_owner]));
	assign active_complete = (((state == 3'd4) && m_bvalid) && m_bready) || ((((state == 3'd7) && m_rvalid) && m_rready) && m_rlast);
	assign queue_offer = (((ENABLE_PENDING_QUEUE && !rst) && !pending_valid) && !active_complete) && (((((state == 3'd2) || (state == 3'd3)) || (state == 3'd4)) || (state == 3'd6)) || (state == 3'd7));
	assign queue_accept = queue_offer && (s_awvalid[queue_owner] || s_arvalid[queue_owner]);
	assign early_pending_ar = ((pending_valid && pending_read) && !pending_sent) && ((state == 3'd7) || (state == 3'd4));
	assign early_pending_aw = ((pending_valid && !pending_read) && !pending_sent) && ((state == 3'd7) || (state == 3'd4));
	assign early_pending_w = (((pending_valid && !pending_read) && pending_sent) && !pending_w_done) && ((state == 3'd7) || (state == 3'd4));
	assign early_pending_w_done = ((early_pending_w && m_wvalid) && m_wready) && m_wlast;
	assign busy = !rst && (state != 3'd0);
	reg write_route_enable;
	reg write_route_owner;
	always @(*) begin
		if (_sv2v_0)
			;
		write_route_enable = 1'b0;
		write_route_owner = owner;
		if (!rst) begin
			case (state)
				3'd3: write_route_enable = 1'b1;
				default:
					;
			endcase
			if (early_pending_w) begin
				write_route_enable = 1'b1;
				write_route_owner = pending_owner;
			end
		end
	end
	assign m_wdata = (write_route_enable ? s_wdata[write_route_owner * DATA_W+:DATA_W] : {DATA_W {1'sb0}});
	assign m_wstrb = (write_route_enable ? s_wstrb[write_route_owner * (DATA_W / 8)+:DATA_W / 8] : {DATA_W / 8 {1'sb0}});
	assign m_wlast = (write_route_enable ? s_wlast[write_route_owner] : 1'b0);
	assign m_wvalid = (write_route_enable ? s_wvalid[write_route_owner] : 1'b0);
	always @(*) begin
		if (_sv2v_0)
			;
		s_awready = 1'sb0;
		s_wready = 1'sb0;
		s_arready = 1'sb0;
		s_bid = 1'sb0;
		s_bresp = 1'sb0;
		s_bvalid = 1'sb0;
		s_rid = 1'sb0;
		s_rdata = 1'sb0;
		s_rresp = 1'sb0;
		s_rlast = 1'sb0;
		s_rvalid = 1'sb0;
		m_awid = command_id;
		m_awaddr = command_addr;
		m_awlen = command_len;
		m_awsize = command_size;
		m_awburst = command_burst;
		m_arid = command_id;
		m_araddr = command_addr;
		m_arlen = command_len;
		m_arsize = command_size;
		m_arburst = command_burst;
		m_awvalid = 1'b0;
		m_arvalid = 1'b0;
		m_bready = 1'b0;
		m_rready = 1'b0;
		if (!rst) begin
			case (state)
				3'd0:
					if (DIRECT_ACCEPT && |requesting) begin
						if (selected_read)
							s_arready[selected_owner] = 1'b1;
						else
							s_awready[selected_owner] = 1'b1;
					end
				3'd1: s_awready[owner] = 1'b1;
				3'd2: m_awvalid = 1'b1;
				3'd3: s_wready[owner] = m_wready;
				3'd4: begin
					s_bid[owner * ID_W+:ID_W] = m_bid;
					s_bresp[owner * 2+:2] = m_bresp;
					s_bvalid[owner] = m_bvalid;
					m_bready = s_bready[owner];
				end
				3'd5: s_arready[owner] = 1'b1;
				3'd6: m_arvalid = 1'b1;
				3'd7: begin
					s_rid[owner * ID_W+:ID_W] = m_rid;
					s_rdata[owner * DATA_W+:DATA_W] = m_rdata;
					s_rresp[owner * 2+:2] = m_rresp;
					s_rlast[owner] = m_rlast;
					s_rvalid[owner] = m_rvalid;
					m_rready = s_rready[owner];
				end
				default:
					;
			endcase
			if (direct_window && |requesting) begin
				if (selected_read)
					s_arready[selected_owner] = 1'b1;
				else
					s_awready[selected_owner] = 1'b1;
			end
			if (queue_offer) begin
				if (queue_read)
					s_arready[queue_owner] = 1'b1;
				else
					s_awready[queue_owner] = 1'b1;
			end
			if (early_pending_ar) begin
				m_arid = pending_id;
				m_araddr = pending_addr;
				m_arlen = pending_len;
				m_arsize = pending_size;
				m_arburst = pending_burst;
				m_arvalid = 1'b1;
			end
			if (early_pending_aw) begin
				m_awid = pending_id;
				m_awaddr = pending_addr;
				m_awlen = pending_len;
				m_awsize = pending_size;
				m_awburst = pending_burst;
				m_awvalid = 1'b1;
			end
			if (early_pending_w)
				s_wready[pending_owner] = m_wready;
		end
	end
	always @(posedge clk)
		if (rst) begin
			state <= 3'd0;
			owner <= 1'b0;
			next_owner <= 1'b0;
			prefer_read <= 1'sb0;
			command_id <= 1'sb0;
			command_addr <= 1'sb0;
			command_len <= 1'sb0;
			command_size <= 1'sb0;
			command_burst <= 1'sb0;
			pending_valid <= 0;
			pending_read <= 0;
			pending_owner <= 0;
			pending_sent <= 0;
			pending_w_done <= 0;
			pending_id <= 1'sb0;
			pending_addr <= 1'sb0;
			pending_len <= 1'sb0;
			pending_size <= 1'sb0;
			pending_burst <= 1'sb0;
		end
		else begin
			if (queue_accept) begin
				pending_valid <= 1'b1;
				pending_sent <= 0;
				pending_w_done <= 0;
				pending_read <= queue_read;
				pending_owner <= queue_owner;
				if (queue_read) begin
					pending_id <= s_arid[queue_owner * ID_W+:ID_W];
					pending_addr <= s_araddr[queue_owner * ADDR_W+:ADDR_W];
					pending_len <= s_arlen[queue_owner * 8+:8];
					pending_size <= s_arsize[queue_owner * 3+:3];
					pending_burst <= s_arburst[queue_owner * 2+:2];
				end
				else begin
					pending_id <= s_awid[queue_owner * ID_W+:ID_W];
					pending_addr <= s_awaddr[queue_owner * ADDR_W+:ADDR_W];
					pending_len <= s_awlen[queue_owner * 8+:8];
					pending_size <= s_awsize[queue_owner * 3+:3];
					pending_burst <= s_awburst[queue_owner * 2+:2];
				end
			end
			if ((early_pending_ar && m_arready) || (early_pending_aw && m_awready))
				pending_sent <= 1;
			if (early_pending_w_done)
				pending_w_done <= 1;
			case (state)
				3'd0:
					if (|requesting) begin
						owner <= selected_owner;
						if (DIRECT_ACCEPT) begin
							if (selected_read) begin
								command_id <= s_arid[selected_owner * ID_W+:ID_W];
								command_addr <= s_araddr[selected_owner * ADDR_W+:ADDR_W];
								command_len <= s_arlen[selected_owner * 8+:8];
								command_size <= s_arsize[selected_owner * 3+:3];
								command_burst <= s_arburst[selected_owner * 2+:2];
								state <= 3'd6;
							end
							else begin
								command_id <= s_awid[selected_owner * ID_W+:ID_W];
								command_addr <= s_awaddr[selected_owner * ADDR_W+:ADDR_W];
								command_len <= s_awlen[selected_owner * 8+:8];
								command_size <= s_awsize[selected_owner * 3+:3];
								command_burst <= s_awburst[selected_owner * 2+:2];
								state <= 3'd2;
							end
						end
						else
							state <= (selected_read ? 3'd5 : 3'd1);
					end
				3'd1:
					if (s_awvalid[owner]) begin
						command_id <= s_awid[owner * ID_W+:ID_W];
						command_addr <= s_awaddr[owner * ADDR_W+:ADDR_W];
						command_len <= s_awlen[owner * 8+:8];
						command_size <= s_awsize[owner * 3+:3];
						command_burst <= s_awburst[owner * 2+:2];
						state <= 3'd2;
					end
				3'd2:
					if (m_awready)
						state <= 3'd3;
				3'd3:
					if ((m_wvalid && m_wready) && m_wlast)
						state <= 3'd4;
				3'd4:
					if (m_bvalid && m_bready) begin
						next_owner <= ~owner;
						prefer_read[owner] <= 1'b1;
						if (pending_valid) begin
							owner <= pending_owner;
							command_id <= pending_id;
							command_addr <= pending_addr;
							command_len <= pending_len;
							command_size <= pending_size;
							command_burst <= pending_burst;
							state <= (pending_read ? (pending_sent || pending_address_fire ? 3'd7 : 3'd6) : (pending_sent || pending_address_fire ? (pending_w_done || early_pending_w_done ? 3'd4 : 3'd3) : 3'd2));
							pending_valid <= 0;
							pending_sent <= 0;
							pending_w_done <= 0;
						end
						else
							state <= 3'd0;
					end
				3'd5:
					if (s_arvalid[owner]) begin
						command_id <= s_arid[owner * ID_W+:ID_W];
						command_addr <= s_araddr[owner * ADDR_W+:ADDR_W];
						command_len <= s_arlen[owner * 8+:8];
						command_size <= s_arsize[owner * 3+:3];
						command_burst <= s_arburst[owner * 2+:2];
						state <= 3'd6;
					end
				3'd6:
					if (m_arready)
						state <= 3'd7;
				3'd7:
					if ((m_rvalid && m_rready) && m_rlast) begin
						next_owner <= ~owner;
						prefer_read[owner] <= 1'b0;
						if (pending_valid) begin
							owner <= pending_owner;
							command_id <= pending_id;
							command_addr <= pending_addr;
							command_len <= pending_len;
							command_size <= pending_size;
							command_burst <= pending_burst;
							state <= (pending_read ? (pending_sent || pending_address_fire ? 3'd7 : 3'd6) : (pending_sent || pending_address_fire ? (pending_w_done || early_pending_w_done ? 3'd4 : 3'd3) : 3'd2));
							pending_valid <= 0;
							pending_sent <= 0;
							pending_w_done <= 0;
						end
						else
							state <= 3'd0;
					end
				default: state <= 3'd0;
			endcase
			if (((DIRECT_ACCEPT && active_complete) && !pending_valid) && |requesting) begin
				owner <= selected_owner;
				if (selected_read) begin
					command_id <= s_arid[selected_owner * ID_W+:ID_W];
					command_addr <= s_araddr[selected_owner * ADDR_W+:ADDR_W];
					command_len <= s_arlen[selected_owner * 8+:8];
					command_size <= s_arsize[selected_owner * 3+:3];
					command_burst <= s_arburst[selected_owner * 2+:2];
					state <= 3'd6;
				end
				else begin
					command_id <= s_awid[selected_owner * ID_W+:ID_W];
					command_addr <= s_awaddr[selected_owner * ADDR_W+:ADDR_W];
					command_len <= s_awlen[selected_owner * 8+:8];
					command_size <= s_awsize[selected_owner * 3+:3];
					command_burst <= s_awburst[selected_owner * 2+:2];
					state <= 3'd2;
				end
			end
		end
	initial if ((((DATA_W < 8) || ((DATA_W % 8) != 0)) || (ADDR_W < 1)) || (ID_W < 1)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_axi_2m_arbiter.sv:335:13 - soc_axi_2m_arbiter.<unnamed_block>.<unnamed_block>\n msg: ", $time, "AXI_2M_INVALID_WIDTH");
		$finish(1);
	end
	initial _sv2v_0 = 0;
endmodule
module soc_camera_dvp_capture (
	pclk,
	arst,
	arm,
	vsync,
	href,
	byte_data,
	pixel_valid,
	pixel_ready,
	pixel_data,
	done_toggle,
	bad_hold,
	pixels_hold
);
	parameter signed [31:0] WIDTH = 1280;
	parameter signed [31:0] HEIGHT = 720;
	input wire pclk;
	input wire arst;
	input wire arm;
	input wire vsync;
	input wire href;
	input wire [7:0] byte_data;
	output wire pixel_valid;
	input wire pixel_ready;
	output wire [15:0] pixel_data;
	output reg done_toggle;
	output reg bad_hold;
	output reg [31:0] pixels_hold;
	wire rst;
	wire armed;
	reg seen_vsync;
	reg vsync_q;
	reg href_q;
	pg_reset_sync u_reset(
		.clk(pclk),
		.arst(arst),
		.rst(rst)
	);
	pg_level_sync u_arm(
		.clk(pclk),
		.rst(rst),
		.async_level(arm),
		.level(armed)
	);
	reg [1:0] state;
	reg half_byte;
	reg bad;
	reg [7:0] first_byte;
	reg [15:0] col;
	reg [15:0] row;
	reg [31:0] pixels;
	assign pixel_valid = ((((((!rst && (state == 2'd2)) && !vsync) && href) && half_byte) && (row < HEIGHT)) && (col < WIDTH)) && pixel_ready;
	assign pixel_data = {first_byte, byte_data};
	always @(posedge pclk)
		if (rst) begin
			state <= 2'd0;
			seen_vsync <= 0;
			vsync_q <= 1;
			href_q <= 0;
			half_byte <= 0;
			first_byte <= 0;
			col <= 0;
			row <= 0;
			pixels <= 0;
			done_toggle <= 0;
			bad_hold <= 0;
			pixels_hold <= 0;
			bad <= 0;
		end
		else begin
			vsync_q <= vsync;
			href_q <= href;
			if (vsync)
				seen_vsync <= 1;
			case (state)
				2'd0:
					if (armed && seen_vsync)
						state <= 2'd1;
				2'd1:
					if (!armed)
						state <= 2'd0;
					else if (vsync_q && !vsync) begin
						state <= 2'd2;
						half_byte <= href;
						if (href)
							first_byte <= byte_data;
						col <= 0;
						row <= 0;
						pixels <= 0;
						bad <= 0;
					end
				2'd2:
					if (!vsync_q && vsync) begin
						bad_hold <= ((((bad || href) || href_q) || half_byte) || (col != 0)) || (row != HEIGHT);
						pixels_hold <= pixels;
						done_toggle <= !done_toggle;
						state <= 2'd3;
					end
					else if (vsync)
						bad <= 1;
					else if (href) begin
						if (row >= HEIGHT)
							bad <= 1;
						if (!half_byte) begin
							first_byte <= byte_data;
							half_byte <= 1;
						end
						else begin
							half_byte <= 0;
							if ((col >= WIDTH) || !pixel_ready)
								bad <= 1;
							if (col < WIDTH)
								col <= col + 1'b1;
							if ((row < HEIGHT) && (col < WIDTH))
								pixels <= pixels + 1'b1;
						end
					end
					else if (href_q) begin
						if ((half_byte || (col != WIDTH)) || (row >= HEIGHT))
							bad <= 1;
						half_byte <= 0;
						col <= 0;
						row <= row + 1'b1;
					end
				2'd3:
					if (!armed)
						state <= 2'd0;
				default: state <= 2'd0;
			endcase
		end
	initial if ((((WIDTH < 8) || (HEIGHT < 1)) || (WIDTH > 65535)) || (HEIGHT > 65535)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_camera_dvp_capture.sv:76:3 - soc_camera_dvp_capture.<unnamed_block>\n msg: ", $time, "CAMERA_DVP_DIMENSION");
		$finish(1);
	end
endmodule
module soc_camera_async_fifo (
	wr_clk,
	rd_clk,
	arst,
	in_valid,
	in_ready,
	in_data,
	out_valid,
	out_ready,
	out_data
);
	parameter signed [31:0] WIDTH = 16;
	parameter signed [31:0] DEPTH = 1024;
	input wire wr_clk;
	input wire rd_clk;
	input wire arst;
	input wire in_valid;
	output wire in_ready;
	input wire [WIDTH - 1:0] in_data;
	output wire out_valid;
	input wire out_ready;
	output wire [WIDTH - 1:0] out_data;
	localparam signed [31:0] AW = $clog2(DEPTH);
	localparam signed [31:0] PW = AW + 1;
	wire wr_rst;
	wire rd_rst;
	pg_reset_sync wr_release(
		.clk(wr_clk),
		.arst(arst),
		.rst(wr_rst)
	);
	pg_reset_sync rd_release(
		.clk(rd_clk),
		.arst(arst),
		.rst(rd_rst)
	);
	reg [PW - 1:0] wbin;
	reg [PW - 1:0] rbin;
	reg [PW - 1:0] wgray;
	reg [PW - 1:0] rgray;
	wire [PW - 1:0] wnext;
	wire [PW - 1:0] rnext;
	wire [PW - 1:0] wgnext;
	wire [PW - 1:0] rgnext;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] rg1;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] rg2;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] wg1;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] wg2;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg ru1;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg ru2;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg wu1;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg wu2;
	(* ram_style = "block", syn_ramstyle = "block_ram" *) reg [WIDTH - 1:0] memory [0:DEPTH - 1];
	reg full;
	reg empty;
	reg read_valid;
	reg [WIDTH - 1:0] read_data;
	wire push = in_valid && in_ready;
	wire load = ((!rd_rst && wu2) && !empty) && (!read_valid || out_ready);
	assign in_ready = (!wr_rst && ru2) && !full;
	assign out_valid = (!rd_rst && wu2) && read_valid;
	assign out_data = read_data;
	function automatic [PW - 1:0] sv2v_cast_D1740;
		input reg [PW - 1:0] inp;
		sv2v_cast_D1740 = inp;
	endfunction
	assign wnext = wbin + sv2v_cast_D1740(push);
	assign rnext = rbin + sv2v_cast_D1740(load);
	assign wgnext = (wnext >> 1) ^ wnext;
	assign rgnext = (rnext >> 1) ^ rnext;
	function automatic signed [PW - 1:0] sv2v_cast_D1740_signed;
		input reg signed [PW - 1:0] inp;
		sv2v_cast_D1740_signed = inp;
	endfunction
	always @(posedge wr_clk or posedge wr_rst)
		if (wr_rst) begin
			wbin <= 0;
			wgray <= 0;
			full <= 0;
			rg1 <= 0;
			rg2 <= 0;
			ru1 <= 0;
			ru2 <= 0;
		end
		else begin
			rg1 <= rgray;
			rg2 <= rg1;
			ru1 <= !rd_rst;
			ru2 <= ru1;
			wbin <= wnext;
			wgray <= wgnext;
			full <= wgnext == (rg2 ^ (sv2v_cast_D1740_signed(3) << (PW - 2)));
		end
	always @(posedge rd_clk or posedge rd_rst)
		if (rd_rst) begin
			rbin <= 0;
			rgray <= 0;
			empty <= 1;
			read_valid <= 0;
			wg1 <= 0;
			wg2 <= 0;
			wu1 <= 0;
			wu2 <= 0;
		end
		else begin
			wg1 <= wgray;
			wg2 <= wg1;
			wu1 <= !wr_rst;
			wu2 <= wu1;
			rbin <= rnext;
			rgray <= rgnext;
			empty <= rgnext == wg2;
			if (load)
				read_valid <= 1;
			else if (out_valid && out_ready)
				read_valid <= 0;
		end
	always @(posedge wr_clk)
		if (push)
			memory[wbin[AW - 1:0]] <= in_data;
	always @(posedge rd_clk)
		if (load)
			read_data <= memory[rbin[AW - 1:0]];
	initial if (((WIDTH < 1) || (DEPTH < 2)) || ((DEPTH & (DEPTH - 1)) != 0)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_camera_async_fifo.sv:56:56 - soc_camera_async_fifo.<unnamed_block>\n msg: ", $time, "CAMERA_FIFO_PARAMETER");
		$finish(1);
	end
endmodule
module soc_camera_axi_writer (
	clk,
	rst,
	start,
	frame_base,
	frame_pixels,
	sensor_done,
	sensor_bad,
	pixel_valid,
	pixel_ready,
	pixel_data,
	busy,
	done_pulse,
	frame_valid,
	error_sticky,
	pixels_written,
	m_awid,
	m_awaddr,
	m_awlen,
	m_awsize,
	m_awburst,
	m_awvalid,
	m_awready,
	m_wdata,
	m_wstrb,
	m_wlast,
	m_wvalid,
	m_wready,
	m_bid,
	m_bresp,
	m_bvalid,
	m_bready
);
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [31:0] DDR_BYTES = 32'h04000000;
	parameter signed [31:0] MAX_PIXELS = 921600;
	input wire clk;
	input wire rst;
	input wire start;
	input wire [31:0] frame_base;
	input wire [31:0] frame_pixels;
	input wire sensor_done;
	input wire sensor_bad;
	input wire pixel_valid;
	output wire pixel_ready;
	input wire [15:0] pixel_data;
	output wire busy;
	output reg done_pulse;
	output reg frame_valid;
	output wire [7:0] error_sticky;
	output reg [31:0] pixels_written;
	output wire [3:0] m_awid;
	output wire [31:0] m_awaddr;
	output wire [7:0] m_awlen;
	output wire [2:0] m_awsize;
	output wire [1:0] m_awburst;
	output wire m_awvalid;
	input wire m_awready;
	output wire [127:0] m_wdata;
	output wire [15:0] m_wstrb;
	output wire m_wlast;
	output wire m_wvalid;
	input wire m_wready;
	input wire [3:0] m_bid;
	input wire [1:0] m_bresp;
	input wire m_bvalid;
	output wire m_bready;
	reg [2:0] state;
	reg [127:0] stage [0:15];
	reg [31:0] base_q;
	reg [31:0] target_q;
	reg [31:0] accepted_q;
	reg [31:0] write_addr_q;
	reg [7:0] fill_pixels_q;
	reg [7:0] chunk_pixels_q;
	reg [4:0] beats_q;
	reg [4:0] beat_index_q;
	reg [15:0] last_strb_q;
	reg [7:0] faults_q;
	wire [33:0] frame_end;
	wire valid_config;
	wire [7:0] filled_beats;
	wire [2:0] tail_pixels;
	assign frame_end = {2'b00, frame_base} + {1'b0, frame_pixels, 1'b0};
	assign valid_config = ((((frame_base[7:0] == 0) && (frame_pixels != 0)) && (frame_pixels <= MAX_PIXELS)) && (frame_base >= DDR_BASE)) && (frame_end <= ({2'b00, DDR_BASE} + {2'b00, DDR_BYTES}));
	assign busy = state != 3'd0;
	assign pixel_ready = ((state == 3'd1) && (accepted_q < target_q)) && (fill_pixels_q < 8'd128);
	assign m_awid = 4'hc;
	assign m_awaddr = write_addr_q;
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	assign m_awlen = sv2v_cast_8(beats_q - 1'b1);
	assign m_awsize = 3'd4;
	assign m_awburst = 2'b01;
	assign m_awvalid = state == 3'd2;
	assign m_wdata = stage[beat_index_q[3:0]];
	assign m_wstrb = (beat_index_q == (beats_q - 1'b1) ? last_strb_q : 16'hffff);
	assign m_wlast = beat_index_q == (beats_q - 1'b1);
	assign m_wvalid = state == 3'd3;
	assign m_bready = state == 3'd4;
	assign error_sticky = faults_q;
	assign filled_beats = (fill_pixels_q + 8'd7) >> 3;
	assign tail_pixels = fill_pixels_q[2:0];
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(posedge clk) begin
		done_pulse <= 0;
		if (rst) begin
			state <= 3'd0;
			base_q <= 0;
			target_q <= 0;
			accepted_q <= 0;
			write_addr_q <= 0;
			fill_pixels_q <= 0;
			chunk_pixels_q <= 0;
			beats_q <= 0;
			beat_index_q <= 0;
			last_strb_q <= 0;
			faults_q <= 0;
			pixels_written <= 0;
			frame_valid <= 0;
		end
		else
			case (state)
				3'd0:
					if (start) begin
						base_q <= frame_base;
						target_q <= frame_pixels;
						accepted_q <= 0;
						pixels_written <= 0;
						write_addr_q <= frame_base;
						fill_pixels_q <= 0;
						chunk_pixels_q <= 0;
						beats_q <= 0;
						beat_index_q <= 0;
						faults_q <= 0;
						frame_valid <= 0;
						if (valid_config)
							state <= 3'd1;
						else begin
							faults_q[2] <= 1;
							done_pulse <= 1;
						end
					end
				3'd1:
					if (pixel_valid && pixel_ready) begin
						stage[fill_pixels_q[6:3]][16 * fill_pixels_q[2:0]+:16] <= pixel_data;
						fill_pixels_q <= fill_pixels_q + 1'b1;
						accepted_q <= accepted_q + 1'b1;
					end
					else if ((fill_pixels_q == 8'd128) || ((fill_pixels_q != 0) && ((accepted_q == target_q) || (sensor_done && !pixel_valid)))) begin
						chunk_pixels_q <= fill_pixels_q;
						beats_q <= sv2v_cast_5(filled_beats);
						last_strb_q <= (tail_pixels == 0 ? 16'hffff : (16'h0001 << (2 * tail_pixels)) - 16'h0001);
						beat_index_q <= 0;
						state <= 3'd2;
					end
					else if (sensor_done && ((accepted_q == target_q) || !pixel_valid)) begin
						if (accepted_q != target_q)
							faults_q[0] <= 1;
						if (pixel_valid)
							faults_q[3] <= 1;
						if (sensor_bad)
							faults_q[4] <= 1;
						frame_valid <= (((accepted_q == target_q) && !pixel_valid) && !sensor_bad) && (faults_q == 0);
						done_pulse <= 1;
						state <= 3'd0;
					end
				3'd2:
					if (m_awready)
						state <= 3'd3;
				3'd3:
					if (m_wready) begin
						if (m_wlast)
							state <= 3'd4;
						else
							beat_index_q <= beat_index_q + 1'b1;
					end
				3'd4:
					if (m_bvalid) begin
						if ((m_bid != 4'hc) || (m_bresp != 2'b00))
							faults_q[1] <= 1;
						pixels_written <= pixels_written + sv2v_cast_32(chunk_pixels_q);
						write_addr_q <= write_addr_q + {23'b00000000000000000000000, beats_q, 4'b0000};
						fill_pixels_q <= 0;
						state <= 3'd1;
					end
				default: state <= 3'd0;
			endcase
	end
	initial if (((MAX_PIXELS < 1) || (DDR_BYTES < 256)) || (DDR_BASE[7:0] != 0)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_camera_axi_writer.sv:134:13 - soc_camera_axi_writer.<unnamed_block>.<unnamed_block>\n msg: ", $time, "CAMERA_AXI_WRITER_PARAMETER");
		$finish(1);
	end
endmodule
module soc_camera_frame_pipeline (
	pclk,
	mem_clk,
	arst,
	start,
	frame_base,
	vsync,
	href,
	byte_data,
	ready,
	busy,
	done_pulse,
	frame_valid,
	error_sticky,
	pixels_written,
	sensor_pixels,
	m_awid,
	m_awaddr,
	m_awlen,
	m_awsize,
	m_awburst,
	m_awvalid,
	m_awready,
	m_wdata,
	m_wstrb,
	m_wlast,
	m_wvalid,
	m_wready,
	m_bid,
	m_bresp,
	m_bvalid,
	m_bready
);
	parameter signed [31:0] WIDTH = 1280;
	parameter signed [31:0] HEIGHT = 720;
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [31:0] DDR_BYTES = 32'h04000000;
	input wire pclk;
	input wire mem_clk;
	input wire arst;
	input wire start;
	input wire [31:0] frame_base;
	input wire vsync;
	input wire href;
	input wire [7:0] byte_data;
	output wire ready;
	output wire busy;
	output reg done_pulse;
	output wire frame_valid;
	output wire [7:0] error_sticky;
	output wire [31:0] pixels_written;
	output reg [31:0] sensor_pixels;
	output wire [3:0] m_awid;
	output wire [31:0] m_awaddr;
	output wire [7:0] m_awlen;
	output wire [2:0] m_awsize;
	output wire [1:0] m_awburst;
	output wire m_awvalid;
	input wire m_awready;
	output wire [127:0] m_wdata;
	output wire [15:0] m_wstrb;
	output wire m_wlast;
	output wire m_wvalid;
	input wire m_wready;
	input wire [3:0] m_bid;
	input wire [1:0] m_bresp;
	input wire m_bvalid;
	output wire m_bready;
	reg [1:0] state;
	wire mem_rst;
	wire pclk_rst;
	reg arm_q;
	wire arm_seen_pclk;
	wire arm_seen_mem;
	wire capture_valid;
	wire capture_ready;
	wire capture_done_toggle;
	wire capture_bad_hold;
	wire [15:0] capture_data;
	wire [15:0] fifo_data;
	reg vsync_sample;
	reg href_sample;
	reg [7:0] byte_sample;
	wire [31:0] capture_pixels_hold;
	wire fifo_valid;
	wire fifo_ready;
	wire writer_ready;
	wire writer_busy;
	wire writer_done;
	wire writer_frame_valid;
	reg writer_sensor_done;
	reg sensor_bad_q;
	wire [7:0] writer_error;
	wire done_sync;
	reg done_at_start;
	wire bad_sync;
	wire launch = start && ready;
	pg_reset_sync u_mem_reset(
		.clk(mem_clk),
		.arst(arst),
		.rst(mem_rst)
	);
	pg_reset_sync u_pclk_reset(
		.clk(pclk),
		.arst(arst),
		.rst(pclk_rst)
	);
	pg_level_sync u_done_sync(
		.clk(mem_clk),
		.rst(mem_rst),
		.async_level(capture_done_toggle),
		.level(done_sync)
	);
	pg_level_sync u_bad_sync(
		.clk(mem_clk),
		.rst(mem_rst),
		.async_level(capture_bad_hold),
		.level(bad_sync)
	);
	pg_level_sync u_arm_to_pclk(
		.clk(pclk),
		.rst(pclk_rst),
		.async_level(arm_q),
		.level(arm_seen_pclk)
	);
	pg_level_sync u_arm_to_mem(
		.clk(mem_clk),
		.rst(mem_rst),
		.async_level(arm_seen_pclk),
		.level(arm_seen_mem)
	);
	always @(posedge pclk) begin
		vsync_sample <= vsync;
		href_sample <= href;
		byte_sample <= byte_data;
	end
	soc_camera_dvp_capture #(
		.WIDTH(WIDTH),
		.HEIGHT(HEIGHT)
	) capture(
		.pclk(pclk),
		.arst(arst),
		.arm(arm_q),
		.vsync(vsync_sample),
		.href(href_sample),
		.byte_data(byte_sample),
		.pixel_valid(capture_valid),
		.pixel_ready(capture_ready),
		.pixel_data(capture_data),
		.done_toggle(capture_done_toggle),
		.bad_hold(capture_bad_hold),
		.pixels_hold(capture_pixels_hold)
	);
	soc_camera_async_fifo #(
		.WIDTH(16),
		.DEPTH(1024)
	) fifo(
		.wr_clk(pclk),
		.rd_clk(mem_clk),
		.arst(arst),
		.in_valid(capture_valid),
		.in_ready(capture_ready),
		.in_data(capture_data),
		.out_valid(fifo_valid),
		.out_ready(fifo_ready),
		.out_data(fifo_data)
	);
	assign fifo_ready = writer_ready || (state == 2'd2);
	soc_camera_axi_writer #(
		.DDR_BASE(DDR_BASE),
		.DDR_BYTES(DDR_BYTES),
		.MAX_PIXELS(WIDTH * HEIGHT)
	) writer(
		.clk(mem_clk),
		.rst(mem_rst),
		.start(launch),
		.frame_base(frame_base),
		.frame_pixels(WIDTH * HEIGHT),
		.sensor_done(writer_sensor_done),
		.sensor_bad(sensor_bad_q),
		.pixel_valid(fifo_valid && (state == 2'd1)),
		.pixel_ready(writer_ready),
		.pixel_data(fifo_data),
		.busy(writer_busy),
		.done_pulse(writer_done),
		.frame_valid(writer_frame_valid),
		.error_sticky(writer_error),
		.pixels_written(pixels_written),
		.m_awid(m_awid),
		.m_awaddr(m_awaddr),
		.m_awlen(m_awlen),
		.m_awsize(m_awsize),
		.m_awburst(m_awburst),
		.m_awvalid(m_awvalid),
		.m_awready(m_awready),
		.m_wdata(m_wdata),
		.m_wstrb(m_wstrb),
		.m_wlast(m_wlast),
		.m_wvalid(m_wvalid),
		.m_wready(m_wready),
		.m_bid(m_bid),
		.m_bresp(m_bresp),
		.m_bvalid(m_bvalid),
		.m_bready(m_bready)
	);
	assign ready = (state == 2'd0) && !mem_rst;
	assign busy = state != 2'd0;
	assign frame_valid = writer_frame_valid;
	assign error_sticky = writer_error;
	always @(posedge mem_clk) begin
		done_pulse <= 0;
		if (mem_rst) begin
			state <= 2'd0;
			arm_q <= 0;
			done_at_start <= 0;
			writer_sensor_done <= 0;
			sensor_bad_q <= 0;
			sensor_pixels <= 0;
		end
		else
			case (state)
				2'd0:
					if (launch) begin
						state <= 2'd1;
						arm_q <= 1;
						done_at_start <= done_sync;
						writer_sensor_done <= 0;
						sensor_bad_q <= 0;
						sensor_pixels <= 0;
					end
				2'd1: begin
					if ((done_sync != done_at_start) && !writer_sensor_done) begin
						writer_sensor_done <= 1;
						sensor_bad_q <= bad_sync;
						sensor_pixels <= capture_pixels_hold;
					end
					if (writer_done) begin
						done_pulse <= 1;
						arm_q <= 0;
						state <= 2'd2;
					end
				end
				2'd2:
					if ((!arm_seen_mem && !fifo_valid) && !writer_busy)
						state <= 2'd0;
				default: state <= 2'd0;
			endcase
	end
	initial if (((WIDTH < 8) || (HEIGHT < 1)) || ((WIDTH * HEIGHT) > 32'h7fffffff)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_camera_frame_pipeline.sv:120:9 - soc_camera_frame_pipeline.<unnamed_block>\n msg: ", $time, "CAMERA_FRAME_PIPELINE_DIMENSION");
		$finish(1);
	end
endmodule
module soc_camera_mmio_mem (
	clk,
	rst,
	ddr_ready,
	camera_init_done,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	start,
	frame_base,
	camera_ready,
	camera_busy,
	camera_done,
	camera_valid,
	camera_errors,
	pixels_written,
	sensor_pixels,
	diag_words,
	diag_snapshot,
	camera_init_done_1,
	diag_words_1,
	diag_snapshot_1,
	sccb_control,
	camera_io_levels
);
	parameter signed [31:0] WIDTH = 1280;
	parameter signed [31:0] HEIGHT = 720;
	parameter [0:0] CAPTURE_CHANNEL = 0;
	parameter [0:0] IMAGE_ACCEL_PRESENT = 0;
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	input wire camera_init_done;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output reg start;
	output reg [31:0] frame_base;
	input wire camera_ready;
	input wire camera_busy;
	input wire camera_done;
	input wire camera_valid;
	input wire [7:0] camera_errors;
	input wire [31:0] pixels_written;
	input wire [31:0] sensor_pixels;
	input wire [511:0] diag_words;
	output reg diag_snapshot;
	input wire camera_init_done_1;
	input wire [511:0] diag_words_1;
	output reg diag_snapshot_1;
	output reg [5:0] sccb_control;
	input wire [31:0] camera_io_levels;
	reg done_hold;
	wire [31:0] status_word;
	wire capture_initialized = (CAPTURE_CHANNEL ? camera_init_done_1 : camera_init_done);
	wire capture_manual = (CAPTURE_CHANNEL ? sccb_control[1] : sccb_control[0]);
	assign req_ready = !rst && !rsp_valid;
	assign status_word = {25'b0000000000000000000000000, capture_initialized, |camera_errors, ddr_ready, camera_valid, done_hold, camera_busy, camera_ready};
	function automatic signed [15:0] sv2v_cast_16_signed;
		input reg signed [15:0] inp;
		sv2v_cast_16_signed = inp;
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(posedge clk) begin
		start <= 0;
		diag_snapshot <= 0;
		diag_snapshot_1 <= 0;
		if (rst) begin
			rsp_valid <= 0;
			rsp_rdata <= 0;
			rsp_error <= 0;
			frame_base <= 32'h80010000;
			done_hold <= 0;
			sccb_control <= 0;
		end
		else begin
			if (camera_done)
				done_hold <= 1;
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			if (req_valid && req_ready) begin
				rsp_valid <= 1;
				rsp_error <= 0;
				rsp_rdata <= 0;
				if ((req_addr[1:0] != 0) || (req_addr[11:8] != 0))
					rsp_error <= 1;
				else if (req_write)
					case (req_addr[7:2])
						5'd0:
							if ((req_wstrb != 4'hf) || (req_wdata[31:1] != 0))
								rsp_error <= 1;
							else if (req_wdata[0]) begin
								if (((camera_ready && ddr_ready) && capture_initialized) && !capture_manual) begin
									start <= 1;
									done_hold <= 0;
								end
								else
									rsp_error <= 1;
							end
						5'd1:
							if ((req_wstrb == 4'hf) && camera_ready)
								frame_base <= req_wdata;
							else
								rsp_error <= 1;
						5'd8:
							if ((req_wstrb == 4'hf) && (req_wdata == 1))
								diag_snapshot <= 1;
							else
								rsp_error <= 1;
						6'd24:
							if ((((((req_wstrb == 4'hf) && (req_wdata[31:6] == 0)) && !camera_busy) && camera_ready) && camera_init_done) && camera_init_done_1)
								sccb_control <= req_wdata[5:0];
							else
								rsp_error <= 1;
						6'd32:
							if ((req_wstrb == 4'hf) && (req_wdata == 1))
								diag_snapshot_1 <= 1;
							else
								rsp_error <= 1;
						default: rsp_error <= 1;
					endcase
				else
					case (req_addr[7:2])
						5'd0: rsp_rdata <= 0;
						5'd1: rsp_rdata <= frame_base;
						5'd2: rsp_rdata <= status_word;
						5'd3: rsp_rdata <= pixels_written;
						5'd4: rsp_rdata <= sensor_pixels;
						5'd5: rsp_rdata <= {24'b000000000000000000000000, camera_errors};
						5'd6: rsp_rdata <= {sv2v_cast_16_signed(HEIGHT), sv2v_cast_16_signed(WIDTH)};
						5'd7: rsp_rdata <= 32'h43414d31;
						6'd24: rsp_rdata <= {IMAGE_ACCEL_PRESENT, 25'b0000000000000000000000000, sccb_control};
						6'd25: rsp_rdata <= {29'b00000000000000000000000000000, camera_busy, camera_init_done_1, camera_init_done};
						6'd26: rsp_rdata <= camera_io_levels;
						6'd27: rsp_rdata <= 32'h31424353;
						6'd28: rsp_rdata <= sv2v_cast_32(CAPTURE_CHANNEL);
						default:
							if ((req_addr[7:2] >= 8) && (req_addr[7:2] <= 23))
								rsp_rdata <= diag_words[32 * (req_addr[7:2] - 8)+:32];
							else if ((req_addr[7:2] >= 32) && (req_addr[7:2] <= 47))
								rsp_rdata <= diag_words_1[32 * (req_addr[7:2] - 32)+:32];
							else
								rsp_error <= 1;
					endcase
			end
		end
	end
endmodule
module soc_camera_dvp_diag (
	pclk,
	mem_clk,
	arst,
	vsync,
	href,
	snapshot_req,
	snapshot_words
);
	parameter signed [31:0] WIDTH = 1280;
	parameter signed [31:0] HEIGHT = 720;
	parameter signed [31:0] MEASURE_TICKS = 937500;
	input wire pclk;
	input wire mem_clk;
	input wire arst;
	input wire vsync;
	input wire href;
	input wire snapshot_req;
	output reg [511:0] snapshot_words;
	wire pclk_rst;
	wire mem_rst;
	pg_reset_sync p_reset(
		.clk(pclk),
		.arst(arst),
		.rst(pclk_rst)
	);
	pg_reset_sync m_reset(
		.clk(mem_clk),
		.arst(arst),
		.rst(mem_rst)
	);
	reg vs_sample;
	reg href_sample;
	reg vs_prev;
	reg href_prev;
	reg running;
	reg [31:0] frame_seq;
	reg [31:0] frame_cycles;
	reg [31:0] total_bytes;
	reg [31:0] line_bytes;
	reg [31:0] lines;
	reg [31:0] min_line;
	reg [31:0] max_line;
	reg [31:0] short_lines;
	reg [31:0] long_lines;
	reg [31:0] odd_lines;
	reg overflow_hold;
	reg [351:0] frame_hold;
	reg [351:0] frame_mem;
	reg frame_toggle;
	reg ack_toggle;
	wire ack_pclk;
	wire frame_toggle_mem;
	reg frame_seen_mem;
	reg frame_pending;
	reg frame_available;
	reg [31:0] dropped_frames;
	pg_level_sync ack_sync(
		.clk(pclk),
		.rst(pclk_rst),
		.async_level(ack_toggle),
		.level(ack_pclk)
	);
	pg_level_sync frame_sync(
		.clk(mem_clk),
		.rst(mem_rst),
		.async_level(frame_toggle),
		.level(frame_toggle_mem)
	);
	wire [31:0] finish_flags = {25'b0000000000000000000000000, overflow_hold, long_lines != 0, short_lines != 0, odd_lines != 0, lines != HEIGHT, lines == 0, (href_sample || href_prev) || (line_bytes != 0)};
	reg [23:0] edge_counter;
	reg [23:0] edge_gray;
	always @(posedge pclk or posedge pclk_rst)
		if (pclk_rst) begin
			edge_counter <= 0;
			edge_gray <= 0;
		end
		else begin
			edge_counter <= edge_counter + 24'd1;
			edge_gray <= ((edge_counter + 24'd1) >> 1) ^ (edge_counter + 24'd1);
		end
	always @(posedge pclk or posedge pclk_rst)
		if (pclk_rst) begin
			vs_sample <= 1;
			href_sample <= 0;
			vs_prev <= 1;
			href_prev <= 0;
			running <= 0;
			frame_seq <= 0;
			frame_cycles <= 0;
			total_bytes <= 0;
			line_bytes <= 0;
			lines <= 0;
			min_line <= 32'hffffffff;
			max_line <= 0;
			short_lines <= 0;
			long_lines <= 0;
			odd_lines <= 0;
			overflow_hold <= 0;
			frame_hold <= 0;
			frame_toggle <= 0;
			dropped_frames <= 0;
		end
		else begin
			vs_sample <= vsync;
			href_sample <= href;
			vs_prev <= vs_sample;
			href_prev <= href_sample;
			if (vs_prev && !vs_sample) begin
				running <= 1;
				frame_cycles <= 0;
				lines <= 0;
				total_bytes <= (href_sample ? 32'd1 : 32'd0);
				line_bytes <= (href_sample ? 32'd1 : 32'd0);
				min_line <= 32'hffffffff;
				max_line <= 0;
				short_lines <= 0;
				long_lines <= 0;
				odd_lines <= 0;
				overflow_hold <= 0;
			end
			else if (running) begin
				if (!vs_prev && vs_sample) begin
					running <= 0;
					frame_seq <= frame_seq + 1'b1;
					if (frame_toggle == ack_pclk) begin
						frame_hold <= {dropped_frames, finish_flags, odd_lines, long_lines, short_lines, max_line, (lines == 0 ? 32'd0 : min_line), lines, total_bytes, frame_cycles, frame_seq + 32'd1};
						frame_toggle <= !frame_toggle;
					end
					else
						dropped_frames <= dropped_frames + 1'b1;
				end
				else begin
					if (frame_cycles == 32'hffffffff)
						overflow_hold <= 1;
					else
						frame_cycles <= frame_cycles + 1'b1;
					if (href_sample && !vs_sample) begin
						if ((total_bytes == 32'hffffffff) || (line_bytes == 32'hffffffff))
							overflow_hold <= 1;
						else begin
							total_bytes <= total_bytes + 1'b1;
							line_bytes <= line_bytes + 1'b1;
						end
					end
					else if (href_prev && !href_sample) begin
						if (lines == 32'hffffffff)
							overflow_hold <= 1;
						else
							lines <= lines + 1'b1;
						if (line_bytes < min_line)
							min_line <= line_bytes;
						if (line_bytes > max_line)
							max_line <= line_bytes;
						if (line_bytes < (2 * WIDTH))
							short_lines <= short_lines + 1'b1;
						if (line_bytes > (2 * WIDTH))
							long_lines <= long_lines + 1'b1;
						if (line_bytes[0])
							odd_lines <= odd_lines + 1'b1;
						line_bytes <= 0;
					end
				end
			end
		end
	(* ASYNC_REG = "TRUE" *) reg [23:0] edge_gray_sync1;
	(* ASYNC_REG = "TRUE" *) reg [23:0] edge_gray_sync2;
	reg [23:0] edge_binary_sync;
	reg [23:0] edge_at_window;
	reg [23:0] measured_edges;
	reg [$clog2(MEASURE_TICKS) - 1:0] measure_count;
	reg frequency_available;
	reg window_primed;
	reg [31:0] snapshot_seq;
	function automatic [23:0] gray_binary;
		input reg [23:0] value;
		reg signed [31:0] i;
		for (i = 0; i < 24; i = i + 1)
			gray_binary[i] = ^(value >> i);
	endfunction
	always @(posedge mem_clk)
		if (mem_rst) begin
			edge_gray_sync1 <= 0;
			edge_gray_sync2 <= 0;
			edge_binary_sync <= 0;
			edge_at_window <= 0;
			measured_edges <= 0;
			measure_count <= 0;
			frequency_available <= 0;
			window_primed <= 0;
			frame_seen_mem <= 0;
			frame_pending <= 0;
			frame_mem <= 0;
			frame_available <= 0;
			ack_toggle <= 0;
			snapshot_seq <= 0;
			snapshot_words <= 0;
			snapshot_words[31:0] <= 32'h31474443;
		end
		else begin
			edge_gray_sync1 <= edge_gray;
			edge_gray_sync2 <= edge_gray_sync1;
			edge_binary_sync <= gray_binary(edge_gray_sync2);
			if (measure_count == (MEASURE_TICKS - 1)) begin
				measure_count <= 0;
				if (window_primed) begin
					measured_edges <= edge_binary_sync - edge_at_window;
					frequency_available <= 1;
				end
				edge_at_window <= edge_binary_sync;
				window_primed <= 1;
			end
			else
				measure_count <= measure_count + 1'b1;
			if ((frame_toggle_mem != frame_seen_mem) && !frame_pending)
				frame_pending <= 1;
			else if (frame_pending) begin
				frame_mem <= frame_hold;
				frame_seen_mem <= frame_toggle_mem;
				ack_toggle <= frame_toggle_mem;
				frame_pending <= 0;
				frame_available <= 1;
			end
			if (snapshot_req) begin
				snapshot_seq <= snapshot_seq + 1'b1;
				snapshot_words[31:0] <= 32'h31474443;
				snapshot_words[63:32] <= {30'h00004000, frequency_available, frame_available};
				snapshot_words[95:64] <= snapshot_seq + 1'b1;
				snapshot_words[127:96] <= {8'd0, measured_edges};
				snapshot_words[159:128] <= MEASURE_TICKS;
				begin : sv2v_autoblock_1
					reg signed [31:0] i;
					for (i = 0; i < 11; i = i + 1)
						snapshot_words[32 * (i + 5)+:32] <= frame_mem[32 * i+:32];
				end
			end
		end
	initial if (((WIDTH < 1) || (HEIGHT < 1)) || (MEASURE_TICKS < 8)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_camera_dvp_diag.sv:133:3 - soc_camera_dvp_diag.<unnamed_block>\n msg: ", $time, "CAMERA_DIAG_PARAMETERS");
		$finish(1);
	end
endmodule
module soc_ov5640_config (
	clk_27m,
	rst_n,
	SCL,
	SDA,
	cam_rst_n,
	init_done
);
	input wire clk_27m;
	input wire rst_n;
	output wire SCL;
	output wire SDA;
	output wire cam_rst_n;
	output wire init_done;
	reg [20:0] power_count;
	wire config_release;
	wire cfg_start;
	wire cfg_end;
	wire [23:0] cfg_data;
	always @(posedge clk_27m or negedge rst_n)
		if (!rst_n)
			power_count <= 0;
		else if (power_count < 21'd1500000)
			power_count <= power_count + 1'b1;
	assign cam_rst_n = rst_n && (power_count >= 21'd400000);
	assign config_release = rst_n && (power_count == 21'd1500000);
	data_init #(.REG_NUM(8'd248)) u_register_table(
		.sys_clk(clk_27m),
		.sys_rst_n(config_release),
		.cfg_end(cfg_end),
		.cfg_start(cfg_start),
		.cfg_data(cfg_data),
		.cfg_done(init_done)
	);
	SCCB #(
		.SYS_CLK(27000000),
		.SCCB_CLK(250000)
	) bus(
		.clk(clk_27m),
		.rst_n(config_release),
		.sccb_start(cfg_start),
		.data_in(cfg_data),
		.SCL(SCL),
		.SDA(SDA),
		.sccb_done(cfg_end)
	);
endmodule
module soc_requant_pipeline (
	clk,
	rst,
	in_valid,
	in_ready,
	in_acc,
	in_bias,
	in_multiplier,
	in_shift,
	in_mode,
	in_zero,
	in_clamp_min,
	in_clamp_max,
	out_valid,
	out_ready,
	out_value,
	out_overflow
);
	reg _sv2v_0;
	input wire clk;
	input wire rst;
	input wire in_valid;
	output wire in_ready;
	input wire signed [31:0] in_acc;
	input wire signed [31:0] in_bias;
	input wire signed [31:0] in_multiplier;
	input wire [5:0] in_shift;
	input wire [1:0] in_mode;
	input wire signed [31:0] in_zero;
	input wire signed [31:0] in_clamp_min;
	input wire signed [31:0] in_clamp_max;
	output wire out_valid;
	input wire out_ready;
	output wire signed [7:0] out_value;
	output wire out_overflow;
	reg [4:0] valid_q;
	wire ready_0;
	wire ready_1;
	wire ready_2;
	wire ready_3;
	wire ready_4;
	wire signed [32:0] sum_ext;
	reg signed [31:0] sum_q;
	reg signed [31:0] multiplier_q;
	reg [5:0] shift_1;
	reg [5:0] shift_2;
	reg [1:0] mode_1;
	reg [1:0] mode_2;
	reg [1:0] mode_3;
	reg signed [31:0] zero_1;
	reg signed [31:0] zero_2;
	reg signed [31:0] zero_3;
	reg signed [31:0] zero_4;
	reg signed [31:0] minimum_1;
	reg signed [31:0] minimum_2;
	reg signed [31:0] minimum_3;
	reg signed [31:0] minimum_4;
	reg signed [31:0] maximum_1;
	reg signed [31:0] maximum_2;
	reg signed [31:0] maximum_3;
	reg signed [31:0] maximum_4;
	reg overflow_1;
	reg overflow_2;
	reg overflow_3;
	reg overflow_4;
	reg overflow_5;
	reg signed [63:0] product_q;
	reg negative_q;
	reg [63:0] quotient_q;
	reg [63:0] remainder_q;
	reg [63:0] half_q;
	reg signed [63:0] shifted_q;
	reg signed [7:0] value_q;
	wire valid_configuration;
	assign valid_configuration = (((((((in_multiplier >= 0) && (in_shift <= 6'd62)) && (in_mode <= 2'd2)) && (in_zero >= -32'sd128)) && (in_zero <= 32'sd127)) && (in_clamp_min >= -32'sd128)) && (in_clamp_max <= 32'sd127)) && (in_clamp_min <= in_clamp_max);
	assign sum_ext = {in_acc[31], in_acc} + {in_bias[31], in_bias};
	assign ready_4 = !valid_q[4] || out_ready;
	assign ready_3 = !valid_q[3] || ready_4;
	assign ready_2 = !valid_q[2] || ready_3;
	assign ready_1 = !valid_q[1] || ready_2;
	assign ready_0 = !valid_q[0] || ready_1;
	assign in_ready = (!rst && valid_configuration) && ready_0;
	assign out_valid = valid_q[4];
	assign out_value = value_q;
	assign out_overflow = overflow_5;
	function automatic round_up;
		input reg negative;
		input reg [1:0] mode;
		input reg quotient_lsb;
		input reg [63:0] remainder;
		input reg [63:0] half;
		case (mode)
			2'd0: round_up = negative && (remainder != 0);
			2'd1: round_up = remainder >= half;
			default: round_up = (remainder > half) || ((remainder == half) && quotient_lsb);
		endcase
	endfunction
	reg [63:0] product_magnitude;
	reg [63:0] rounded_magnitude;
	reg signed [63:0] signed_rounded;
	reg signed [63:0] zero_added;
	reg signed [63:0] minimum_extended;
	reg signed [63:0] maximum_extended;
	function automatic [63:0] sv2v_cast_64;
		input reg [63:0] inp;
		sv2v_cast_64 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		product_magnitude = (product_q < 0 ? $unsigned(-product_q) : $unsigned(product_q));
		rounded_magnitude = quotient_q + sv2v_cast_64(round_up(negative_q, mode_3, quotient_q[0], remainder_q, half_q));
		signed_rounded = (negative_q ? -$signed(rounded_magnitude) : $signed(rounded_magnitude));
		zero_added = shifted_q + {{32 {zero_4[31]}}, zero_4};
		minimum_extended = {{32 {minimum_4[31]}}, minimum_4};
		maximum_extended = {{32 {maximum_4[31]}}, maximum_4};
	end
	always @(posedge clk)
		if (rst) begin
			valid_q <= 1'sb0;
			sum_q <= 1'sb0;
			multiplier_q <= 1'sb0;
			shift_1 <= 1'sb0;
			shift_2 <= 1'sb0;
			mode_1 <= 1'sb0;
			mode_2 <= 1'sb0;
			mode_3 <= 1'sb0;
			zero_1 <= 1'sb0;
			zero_2 <= 1'sb0;
			zero_3 <= 1'sb0;
			zero_4 <= 1'sb0;
			minimum_1 <= 1'sb0;
			minimum_2 <= 1'sb0;
			minimum_3 <= 1'sb0;
			minimum_4 <= 1'sb0;
			maximum_1 <= 1'sb0;
			maximum_2 <= 1'sb0;
			maximum_3 <= 1'sb0;
			maximum_4 <= 1'sb0;
			overflow_1 <= 1'b0;
			overflow_2 <= 1'b0;
			overflow_3 <= 1'b0;
			overflow_4 <= 1'b0;
			overflow_5 <= 1'b0;
			product_q <= 1'sb0;
			negative_q <= 1'b0;
			quotient_q <= 1'sb0;
			remainder_q <= 1'sb0;
			half_q <= 1'sb0;
			shifted_q <= 1'sb0;
			value_q <= 1'sb0;
		end
		else begin
			if (ready_0) begin
				valid_q[0] <= in_valid && valid_configuration;
				if (in_valid && valid_configuration) begin
					sum_q <= sum_ext[31:0];
					multiplier_q <= in_multiplier;
					shift_1 <= in_shift;
					mode_1 <= in_mode;
					zero_1 <= in_zero;
					minimum_1 <= in_clamp_min;
					maximum_1 <= in_clamp_max;
					overflow_1 <= (sum_ext > 33'sh07fffffff) || (sum_ext < -33'sh080000000);
				end
			end
			if (ready_1) begin
				valid_q[1] <= valid_q[0];
				if (valid_q[0]) begin
					product_q <= $signed(sum_q) * $signed(multiplier_q);
					shift_2 <= shift_1;
					mode_2 <= mode_1;
					zero_2 <= zero_1;
					minimum_2 <= minimum_1;
					maximum_2 <= maximum_1;
					overflow_2 <= overflow_1;
				end
			end
			if (ready_2) begin
				valid_q[2] <= valid_q[1];
				if (valid_q[1]) begin
					negative_q <= product_q < 0;
					quotient_q <= product_magnitude >> shift_2;
					remainder_q <= (shift_2 == 0 ? 64'd0 : product_magnitude & ((64'd1 << shift_2) - 64'd1));
					half_q <= (shift_2 == 0 ? 64'd1 : 64'd1 << (shift_2 - 6'd1));
					mode_3 <= mode_2;
					zero_3 <= zero_2;
					minimum_3 <= minimum_2;
					maximum_3 <= maximum_2;
					overflow_3 <= overflow_2;
				end
			end
			if (ready_3) begin
				valid_q[3] <= valid_q[2];
				if (valid_q[2]) begin
					shifted_q <= signed_rounded;
					zero_4 <= zero_3;
					minimum_4 <= minimum_3;
					maximum_4 <= maximum_3;
					overflow_4 <= overflow_3;
				end
			end
			if (ready_4) begin
				valid_q[4] <= valid_q[3];
				if (valid_q[3]) begin
					if (zero_added < minimum_extended)
						value_q <= minimum_4[7:0];
					else if (zero_added > maximum_extended)
						value_q <= maximum_4[7:0];
					else
						value_q <= zero_added[7:0];
					overflow_5 <= overflow_4;
				end
			end
		end
	initial _sv2v_0 = 0;
endmodule
module soc_requant_lut_dma (
	clk,
	rst,
	start_valid,
	start_ready,
	source_addr,
	output_addr,
	bias_addr,
	multiplier_addr,
	shift_addr,
	lut_addr,
	use_lut,
	pixels,
	channels,
	acc_abs_bound,
	rounding_mode,
	output_zero,
	clamp_min,
	clamp_max,
	done_valid,
	done_ready,
	error_code,
	partial_output,
	read_bytes,
	write_bytes,
	stall_cycles,
	active_cycles,
	dma_req_valid,
	dma_req_ready,
	dma_req_write,
	dma_req_addr,
	dma_req_wdata,
	dma_req_wstrb,
	dma_req_id,
	dma_req_len,
	dma_rsp_last,
	dma_rsp_valid,
	dma_rsp_ready,
	dma_rsp_write,
	dma_rsp_id,
	dma_rsp_rdata,
	dma_rsp_error
);
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [32:0] DDR_BYTES = 33'h004000000;
	parameter [0:0] INPUT_PREFETCH = 1'b1;
	parameter [0:0] READ_BURST_ENABLE = 1'b0;
	parameter [0:0] TILE_PIPELINE_ENABLE = 1'b1;
	parameter signed [31:0] TILE_ELEMS = 256;
	parameter [0:0] WRITE_ACK_OVERLAP = 1'b1;
	parameter signed [31:0] QUANT_LANES = 4;
	parameter [0:0] PARAM_BURST_ENABLE = 1'b1;
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire [31:0] source_addr;
	input wire [31:0] output_addr;
	input wire [31:0] bias_addr;
	input wire [31:0] multiplier_addr;
	input wire [31:0] shift_addr;
	input wire [31:0] lut_addr;
	input wire use_lut;
	input wire [31:0] pixels;
	input wire [8:0] channels;
	input wire [31:0] acc_abs_bound;
	input wire [1:0] rounding_mode;
	input wire signed [31:0] output_zero;
	input wire signed [31:0] clamp_min;
	input wire signed [31:0] clamp_max;
	output wire done_valid;
	input wire done_ready;
	output wire [3:0] error_code;
	output wire partial_output;
	output wire [31:0] read_bytes;
	output wire [31:0] write_bytes;
	output wire [31:0] stall_cycles;
	output wire [31:0] active_cycles;
	output wire dma_req_valid;
	input wire dma_req_ready;
	output wire dma_req_write;
	output wire [31:0] dma_req_addr;
	output wire [127:0] dma_req_wdata;
	output wire [15:0] dma_req_wstrb;
	output wire [3:0] dma_req_id;
	output wire [3:0] dma_req_len;
	input wire dma_rsp_last;
	input wire dma_rsp_valid;
	output wire dma_rsp_ready;
	input wire dma_rsp_write;
	input wire [3:0] dma_rsp_id;
	input wire [127:0] dma_rsp_rdata;
	input wire dma_rsp_error;
	generate
		if (TILE_PIPELINE_ENABLE && READ_BURST_ENABLE) begin : tiled
			soc_requant_lut_dma_tiled #(
				.DDR_BASE(DDR_BASE),
				.DDR_BYTES(DDR_BYTES),
				.INPUT_PREFETCH(INPUT_PREFETCH),
				.READ_BURST_ENABLE(1'b1),
				.TILE_ELEMS(TILE_ELEMS),
				.LANES(QUANT_LANES),
				.PARAM_BURST_ENABLE(PARAM_BURST_ENABLE),
				.WRITE_ACK_OVERLAP(WRITE_ACK_OVERLAP)
			) impl(
				.clk(clk),
				.rst(rst),
				.start_valid(start_valid),
				.start_ready(start_ready),
				.source_addr(source_addr),
				.output_addr(output_addr),
				.bias_addr(bias_addr),
				.multiplier_addr(multiplier_addr),
				.shift_addr(shift_addr),
				.lut_addr(lut_addr),
				.use_lut(use_lut),
				.pixels(pixels),
				.channels(channels),
				.acc_abs_bound(acc_abs_bound),
				.rounding_mode(rounding_mode),
				.output_zero(output_zero),
				.clamp_min(clamp_min),
				.clamp_max(clamp_max),
				.done_valid(done_valid),
				.done_ready(done_ready),
				.error_code(error_code),
				.partial_output(partial_output),
				.read_bytes(read_bytes),
				.write_bytes(write_bytes),
				.stall_cycles(stall_cycles),
				.active_cycles(active_cycles),
				.dma_req_valid(dma_req_valid),
				.dma_req_ready(dma_req_ready),
				.dma_req_write(dma_req_write),
				.dma_req_addr(dma_req_addr),
				.dma_req_wdata(dma_req_wdata),
				.dma_req_wstrb(dma_req_wstrb),
				.dma_req_id(dma_req_id),
				.dma_req_len(dma_req_len),
				.dma_rsp_last(dma_rsp_last),
				.dma_rsp_valid(dma_rsp_valid),
				.dma_rsp_ready(dma_rsp_ready),
				.dma_rsp_write(dma_rsp_write),
				.dma_rsp_id(dma_rsp_id),
				.dma_rsp_rdata(dma_rsp_rdata),
				.dma_rsp_error(dma_rsp_error)
			);
		end
		else begin : serial
			soc_requant_lut_dma_serial #(
				.DDR_BASE(DDR_BASE),
				.DDR_BYTES(DDR_BYTES),
				.INPUT_PREFETCH(INPUT_PREFETCH),
				.READ_BURST_ENABLE(READ_BURST_ENABLE)
			) impl(
				.clk(clk),
				.rst(rst),
				.start_valid(start_valid),
				.start_ready(start_ready),
				.source_addr(source_addr),
				.output_addr(output_addr),
				.bias_addr(bias_addr),
				.multiplier_addr(multiplier_addr),
				.shift_addr(shift_addr),
				.lut_addr(lut_addr),
				.use_lut(use_lut),
				.pixels(pixels),
				.channels(channels),
				.acc_abs_bound(acc_abs_bound),
				.rounding_mode(rounding_mode),
				.output_zero(output_zero),
				.clamp_min(clamp_min),
				.clamp_max(clamp_max),
				.done_valid(done_valid),
				.done_ready(done_ready),
				.error_code(error_code),
				.partial_output(partial_output),
				.read_bytes(read_bytes),
				.write_bytes(write_bytes),
				.stall_cycles(stall_cycles),
				.active_cycles(active_cycles),
				.dma_req_valid(dma_req_valid),
				.dma_req_ready(dma_req_ready),
				.dma_req_write(dma_req_write),
				.dma_req_addr(dma_req_addr),
				.dma_req_wdata(dma_req_wdata),
				.dma_req_wstrb(dma_req_wstrb),
				.dma_req_id(dma_req_id),
				.dma_req_len(dma_req_len),
				.dma_rsp_last(dma_rsp_last),
				.dma_rsp_valid(dma_rsp_valid),
				.dma_rsp_ready(dma_rsp_ready),
				.dma_rsp_write(dma_rsp_write),
				.dma_rsp_id(dma_rsp_id),
				.dma_rsp_rdata(dma_rsp_rdata),
				.dma_rsp_error(dma_rsp_error)
			);
		end
	endgenerate
endmodule
module soc_requant_lut_dma_serial (
	clk,
	rst,
	start_valid,
	start_ready,
	source_addr,
	output_addr,
	bias_addr,
	multiplier_addr,
	shift_addr,
	lut_addr,
	use_lut,
	pixels,
	channels,
	acc_abs_bound,
	rounding_mode,
	output_zero,
	clamp_min,
	clamp_max,
	done_valid,
	done_ready,
	error_code,
	partial_output,
	read_bytes,
	write_bytes,
	stall_cycles,
	active_cycles,
	dma_req_valid,
	dma_req_ready,
	dma_req_write,
	dma_req_addr,
	dma_req_wdata,
	dma_req_wstrb,
	dma_req_id,
	dma_req_len,
	dma_rsp_last,
	dma_rsp_valid,
	dma_rsp_ready,
	dma_rsp_write,
	dma_rsp_id,
	dma_rsp_rdata,
	dma_rsp_error
);
	reg _sv2v_0;
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [32:0] DDR_BYTES = 33'h004000000;
	parameter [0:0] INPUT_PREFETCH = 1'b1;
	parameter [0:0] READ_BURST_ENABLE = 1'b0;
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire [31:0] source_addr;
	input wire [31:0] output_addr;
	input wire [31:0] bias_addr;
	input wire [31:0] multiplier_addr;
	input wire [31:0] shift_addr;
	input wire [31:0] lut_addr;
	input wire use_lut;
	input wire [31:0] pixels;
	input wire [8:0] channels;
	input wire [31:0] acc_abs_bound;
	input wire [1:0] rounding_mode;
	input wire signed [31:0] output_zero;
	input wire signed [31:0] clamp_min;
	input wire signed [31:0] clamp_max;
	output wire done_valid;
	input wire done_ready;
	output reg [3:0] error_code;
	output reg partial_output;
	output reg [31:0] read_bytes;
	output reg [31:0] write_bytes;
	output reg [31:0] stall_cycles;
	output reg [31:0] active_cycles;
	output wire dma_req_valid;
	input wire dma_req_ready;
	output wire dma_req_write;
	output wire [31:0] dma_req_addr;
	output wire [127:0] dma_req_wdata;
	output wire [15:0] dma_req_wstrb;
	output wire [3:0] dma_req_id;
	output reg [3:0] dma_req_len;
	input wire dma_rsp_last;
	input wire dma_rsp_valid;
	output wire dma_rsp_ready;
	input wire dma_rsp_write;
	input wire [3:0] dma_rsp_id;
	input wire [127:0] dma_rsp_rdata;
	input wire dma_rsp_error;
	reg [3:0] state;
	reg [31:0] source_q;
	reg [31:0] output_q;
	reg [31:0] elements_q;
	reg [31:0] bound_q;
	reg [31:0] param_base_q [0:2];
	reg [31:0] lut_base_q;
	reg use_lut_q;
	reg [3:0] lut_beat;
	reg [8:0] channels_q;
	reg [8:0] channel_index;
	reg [1:0] mode_q;
	reg [1:0] param_kind;
	reg signed [31:0] zero_q;
	reg signed [31:0] minimum_q;
	reg signed [31:0] maximum_q;
	reg [8:0] param_beat;
	reg [31:0] completed;
	reg [4:0] block_count;
	reg [4:0] feed_count;
	reg [4:0] collect_count;
	reg [2:0] input_beat;
	reg param_issued;
	reg [1:0] pf_state;
	reg input_bank;
	reg [1:0] pf_beat;
	reg [4:0] pf_count;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	wire [31:0] next_first = completed + sv2v_cast_32(block_count);
	wire [31:0] next_remaining = elements_q - next_first;
	wire pf_request = INPUT_PREFETCH && (pf_state == 2'd1);
	wire pf_response = INPUT_PREFETCH && (pf_state == 2'd2);
	wire pf_rsp_fire = pf_response && dma_rsp_valid;
	wire pf_rsp_bad = pf_rsp_fire && ((dma_rsp_error || dma_rsp_write) || (dma_rsp_id != 4'd0));
	wire pipe_out_overflow;
	wire pipe_out_valid;
	wire arithmetic_fault = ((state == 4'd10) && pipe_out_valid) && pipe_out_overflow;
	wire signed [31:0] acc_word_q;
	wire [127:0] bias_beat_q;
	wire [127:0] multiplier_beat_q;
	wire [127:0] input_beat_q;
	wire [127:0] lut_beat_q;
	wire [23:0] shift_beat_q;
	reg [1:0] lane_q;
	reg [1:0] input_lane_q;
	reg result_pending;
	reg [7:0] result_value_q;
	wire signed [31:0] bias_word;
	wire signed [31:0] multiplier_word;
	wire [5:0] shift_word;
	reg [7:0] output_block [0:15];
	wire pipe_in_valid;
	wire pipe_in_ready;
	wire pipe_out_ready;
	wire signed [7:0] pipe_out_value;
	wire [127:0] output_packed;
	wire [15:0] output_strobes;
	wire [63:0] element_count_wide;
	reg [63:0] element_count_q_wide;
	wire [63:0] source_bytes_wide;
	wire [63:0] parameter_bytes_wide;
	wire [63:0] output_bytes_wide;
	reg shape_valid;
	reg addresses_valid;
	reg overlaps_valid;
	reg param_rsp_bad;
	wire [191:0] range_base;
	wire [383:0] range_bytes;
	reg [63:0] range_end_q [0:5];
	wire [32:0] ddr_end;
	localparam [3:0] ERR_NONE = 0;
	localparam [3:0] ERR_DESCRIPTOR = 1;
	localparam [3:0] ERR_DMA = 2;
	localparam [3:0] ERR_PARAMETER = 3;
	localparam [3:0] ERR_OVERFLOW = 4;
	assign ddr_end = {1'b0, DDR_BASE} + DDR_BYTES;
	function automatic [63:0] sv2v_cast_64;
		input reg [63:0] inp;
		sv2v_cast_64 = inp;
	endfunction
	assign element_count_wide = sv2v_cast_64(pixels) * sv2v_cast_64(channels);
	assign source_bytes_wide = ((element_count_q_wide + 64'd3) >> 2) << 4;
	assign output_bytes_wide = ((element_count_q_wide + 64'd15) >> 4) << 4;
	assign parameter_bytes_wide = ((sv2v_cast_64(channels_q) + 64'd3) >> 2) << 4;
	assign range_base[0+:32] = source_q;
	assign range_base[32+:32] = output_q;
	assign range_base[64+:32] = param_base_q[0];
	assign range_base[96+:32] = param_base_q[1];
	assign range_base[128+:32] = param_base_q[2];
	assign range_base[160+:32] = lut_base_q;
	assign range_bytes[0+:64] = source_bytes_wide;
	assign range_bytes[64+:64] = output_bytes_wide;
	assign range_bytes[128+:64] = parameter_bytes_wide;
	assign range_bytes[192+:64] = parameter_bytes_wide;
	assign range_bytes[256+:64] = parameter_bytes_wide;
	assign range_bytes[320+:64] = 64'd256;
	always @(*) begin
		if (_sv2v_0)
			;
		shape_valid = (((((((((((element_count_q_wide != 0) && (channels_q != 0)) && (channels_q <= 9'd256)) && (element_count_q_wide <= 64'h00000000ffffffff)) && (bound_q != 0)) && (bound_q <= 32'h7fffffff)) && (mode_q <= 2'd2)) && (zero_q >= -32'sd128)) && (zero_q <= 32'sd127)) && (minimum_q >= -32'sd128)) && (maximum_q <= 32'sd127)) && (minimum_q <= maximum_q);
		addresses_valid = 1;
		overlaps_valid = 1;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < 6; i = i + 1)
				if ((i < 5) || use_lut_q) begin
					if (((range_base[(i * 32) + 3-:4] != 0) || (range_base[i * 32+:32] < DDR_BASE)) || (range_end_q[i] > {31'd0, ddr_end}))
						addresses_valid = 0;
					begin : sv2v_autoblock_2
						reg signed [31:0] j;
						for (j = 0; j < i; j = j + 1)
							if ((((j < 5) || use_lut_q) && ({32'd0, range_base[i * 32+:32]} < range_end_q[j])) && ({32'd0, range_base[j * 32+:32]} < range_end_q[i]))
								overlaps_valid = 0;
					end
				end
		end
	end
	function automatic [32:0] absolute_bias;
		input reg [31:0] word;
		reg signed [32:0] extended;
		begin
			extended = $signed({word[31], word});
			absolute_bias = (extended < 0 ? $unsigned(-extended) : $unsigned(extended));
		end
	endfunction
	function automatic signed [8:0] sv2v_cast_9_signed;
		input reg signed [8:0] inp;
		sv2v_cast_9_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		param_rsp_bad = 0;
		begin : sv2v_autoblock_3
			reg signed [31:0] lane;
			for (lane = 0; lane < 4; lane = lane + 1)
				if (((param_beat * 9'd4) + sv2v_cast_9_signed(lane)) < channels_q)
					case (param_kind)
						2'd0:
							if (({1'b0, bound_q} + {1'b0, absolute_bias(dma_rsp_rdata[lane * 32+:32])}) > 34'h07fffffff)
								param_rsp_bad = 1;
						2'd1:
							if (dma_rsp_rdata[(lane * 32) + 31])
								param_rsp_bad = 1;
						default:
							if (dma_rsp_rdata[lane * 32+:32] > 32'd62)
								param_rsp_bad = 1;
					endcase
		end
	end
	assign start_ready = state == 4'd0;
	assign done_valid = (state == 4'd13) || (state == 4'd14);
	assign dma_req_valid = ((((state == 4'd4) || (state == 4'd6)) || (state == 4'd8)) || (state == 4'd11)) || pf_request;
	assign dma_req_write = state == 4'd11;
	assign dma_req_id = 4'd0;
	assign dma_req_addr = (pf_request ? (source_q + (next_first << 2)) + {26'd0, pf_beat, 4'd0} : (state == 4'd4 ? param_base_q[param_kind] + {19'd0, param_beat, 4'd0} : (state == 4'd6 ? lut_base_q + {24'd0, lut_beat, 4'd0} : (state == 4'd8 ? (source_q + (completed << 2)) + {25'd0, input_beat, 4'd0} : output_q + completed))));
	reg [8:0] burst_words;
	reg [8:0] boundary_words;
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		burst_words = 1;
		if (READ_BURST_ENABLE) begin
			if (pf_request)
				burst_words = ((sv2v_cast_9(pf_count) + 9'd3) >> 2) - sv2v_cast_9(pf_beat);
			else if (state == 4'd8)
				burst_words = ((sv2v_cast_9(block_count) + 9'd3) >> 2) - sv2v_cast_9(input_beat);
			else if (state == 4'd6)
				burst_words = 9'd16 - sv2v_cast_9(lut_beat);
		end
		boundary_words = 9'd256 - {1'b0, dma_req_addr[11:4]};
		if (burst_words > boundary_words)
			burst_words = boundary_words;
		dma_req_len = sv2v_cast_4(burst_words - 1'b1);
	end
	wire response_last = !READ_BURST_ENABLE || dma_rsp_last;
	assign dma_req_wdata = output_packed;
	assign dma_req_wstrb = (state == 4'd11 ? output_strobes : 16'd0);
	assign dma_rsp_ready = ((((state == 4'd5) || (state == 4'd7)) || (state == 4'd9)) || (state == 4'd12)) || pf_response;
	assign pipe_in_valid = (state == 4'd10) && param_issued;
	assign pipe_out_ready = state == 4'd10;
	assign bias_word = $signed(bias_beat_q[32 * lane_q+:32]);
	assign multiplier_word = $signed(multiplier_beat_q[32 * lane_q+:32]);
	assign shift_word = shift_beat_q[6 * lane_q+:6];
	assign acc_word_q = $signed(input_beat_q[32 * input_lane_q+:32]);
	wire response_ok = ((((!rst && dma_rsp_valid) && dma_rsp_ready) && !dma_rsp_error) && !dma_rsp_write) && (dma_rsp_id == 0);
	wire parameter_write = (response_ok && (state == 4'd5)) && !param_rsp_bad;
	wire operand_read = ((!rst && (state == 4'd10)) && (feed_count < block_count)) && (!param_issued || pipe_in_ready);
	wire result_read = ((!rst && (state == 4'd10)) && pipe_out_valid) && !pipe_out_overflow;
	wire input_write = response_ok && ((state == 4'd9) || (pf_response && (error_code == ERR_NONE)));
	wire [2:0] input_write_addr = (pf_response ? {~input_bank, pf_beat} : {input_bank, input_beat[1:0]});
	wire lut_write = response_ok && (state == 4'd7);
	wire arithmetic_reset = rst || (state == 4'd0);
	soc_rq_sync_words #(
		.WIDTH(128),
		.ADDR_W(6)
	) bias_storage(
		.clk(clk),
		.wr_en(parameter_write && (param_kind == 0)),
		.wr_addr(param_beat[5:0]),
		.wr_data(dma_rsp_rdata),
		.rd_en(operand_read),
		.rd_addr(channel_index[7:2]),
		.rd_data(bias_beat_q)
	);
	soc_rq_sync_words #(
		.WIDTH(128),
		.ADDR_W(6)
	) multiplier_storage(
		.clk(clk),
		.wr_en(parameter_write && (param_kind == 1)),
		.wr_addr(param_beat[5:0]),
		.wr_data(dma_rsp_rdata),
		.rd_en(operand_read),
		.rd_addr(channel_index[7:2]),
		.rd_data(multiplier_beat_q)
	);
	soc_rq_sync_words #(
		.WIDTH(24),
		.ADDR_W(6)
	) shift_storage(
		.clk(clk),
		.wr_en(parameter_write && (param_kind == 2)),
		.wr_addr(param_beat[5:0]),
		.wr_data({dma_rsp_rdata[101:96], dma_rsp_rdata[69:64], dma_rsp_rdata[37:32], dma_rsp_rdata[5:0]}),
		.rd_en(operand_read),
		.rd_addr(channel_index[7:2]),
		.rd_data(shift_beat_q)
	);
	soc_rq_sync_words #(
		.WIDTH(128),
		.ADDR_W(3)
	) input_storage(
		.clk(clk),
		.wr_en(input_write),
		.wr_addr(input_write_addr),
		.wr_data(dma_rsp_rdata),
		.rd_en(operand_read),
		.rd_addr({input_bank, feed_count[3:2]}),
		.rd_data(input_beat_q)
	);
	soc_rq_sync_words #(
		.WIDTH(128),
		.ADDR_W(4)
	) lut_storage(
		.clk(clk),
		.wr_en(lut_write),
		.wr_addr(lut_beat),
		.wr_data(dma_rsp_rdata),
		.rd_en(result_read && use_lut_q),
		.rd_addr(pipe_out_value[7:4]),
		.rd_data(lut_beat_q)
	);
	genvar _gv_g_1;
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	generate
		for (_gv_g_1 = 0; _gv_g_1 < 16; _gv_g_1 = _gv_g_1 + 1) begin : pack_output
			localparam g = _gv_g_1;
			assign output_packed[g * 8+:8] = output_block[g];
			assign output_strobes[g] = sv2v_cast_5_signed(g) < block_count;
		end
	endgenerate
	soc_requant_pipeline arithmetic(
		.clk(clk),
		.rst(arithmetic_reset),
		.in_valid(pipe_in_valid),
		.in_ready(pipe_in_ready),
		.in_acc(acc_word_q),
		.in_bias(bias_word),
		.in_multiplier(multiplier_word),
		.in_shift(shift_word),
		.in_mode(mode_q),
		.in_zero(zero_q),
		.in_clamp_min(minimum_q),
		.in_clamp_max(maximum_q),
		.out_valid(pipe_out_valid),
		.out_ready(pipe_out_ready),
		.out_value(pipe_out_value),
		.out_overflow(pipe_out_overflow)
	);
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			state <= 4'd0;
			source_q <= 0;
			output_q <= 0;
			elements_q <= 0;
			bound_q <= 0;
			element_count_q_wide <= 0;
			begin : sv2v_autoblock_4
				reg signed [31:0] r;
				for (r = 0; r < 6; r = r + 1)
					range_end_q[r] <= 0;
			end
			param_base_q[0] <= 0;
			param_base_q[1] <= 0;
			param_base_q[2] <= 0;
			lut_base_q <= 0;
			use_lut_q <= 0;
			lut_beat <= 0;
			channels_q <= 0;
			channel_index <= 0;
			mode_q <= 0;
			zero_q <= 0;
			minimum_q <= 0;
			maximum_q <= 0;
			param_beat <= 0;
			param_kind <= 0;
			completed <= 0;
			block_count <= 0;
			feed_count <= 0;
			collect_count <= 0;
			input_beat <= 0;
			param_issued <= 0;
			lane_q <= 0;
			input_lane_q <= 0;
			pf_state <= 2'd0;
			pf_beat <= 0;
			pf_count <= 0;
			input_bank <= 0;
			result_pending <= 0;
			result_value_q <= 0;
			error_code <= ERR_NONE;
			partial_output <= 0;
			read_bytes <= 0;
			write_bytes <= 0;
			stall_cycles <= 0;
			active_cycles <= 0;
		end
		else begin
			result_pending <= result_read;
			if (result_read)
				result_value_q <= pipe_out_value;
			if (((state != 4'd0) && (state != 4'd13)) && (state != 4'd14))
				active_cycles <= active_cycles + 1'b1;
			if ((dma_req_valid && !dma_req_ready) || (dma_rsp_ready && !dma_rsp_valid))
				stall_cycles <= stall_cycles + 1'b1;
			if (INPUT_PREFETCH)
				case (pf_state)
					2'd0:
						if ((((state == 4'd10) && (error_code == ERR_NONE)) && !arithmetic_fault) && (next_first < elements_q)) begin
							pf_count <= (next_remaining >= 32'd16 ? 5'd16 : sv2v_cast_5(next_remaining));
							pf_beat <= 0;
							pf_state <= 2'd1;
						end
					2'd1:
						if (dma_req_ready)
							pf_state <= 2'd2;
					2'd2:
						if (dma_rsp_valid) begin
							if ((pf_rsp_bad || (error_code != ERR_NONE)) || arithmetic_fault)
								pf_state <= (response_last ? 2'd3 : 2'd2);
							else if ((({3'd0, pf_beat} + 5'd1) << 2) >= pf_count)
								pf_state <= 2'd3;
							else begin
								pf_beat <= pf_beat + 1'b1;
								pf_state <= (response_last ? 2'd1 : 2'd2);
							end
							if (!pf_rsp_bad)
								read_bytes <= read_bytes + 32'd16;
						end
					default:
						;
				endcase
			case (state)
				4'd0:
					if (start_valid) begin
						pf_state <= 2'd0;
						pf_beat <= 0;
						pf_count <= 0;
						input_bank <= 0;
						param_issued <= 0;
						error_code <= ERR_NONE;
						partial_output <= 0;
						read_bytes <= 0;
						write_bytes <= 0;
						stall_cycles <= 0;
						active_cycles <= 0;
						source_q <= source_addr;
						output_q <= output_addr;
						elements_q <= element_count_wide[31:0];
						element_count_q_wide <= element_count_wide;
						bound_q <= acc_abs_bound;
						param_base_q[0] <= bias_addr;
						param_base_q[1] <= multiplier_addr;
						param_base_q[2] <= shift_addr;
						lut_base_q <= lut_addr;
						use_lut_q <= use_lut;
						lut_beat <= 0;
						channels_q <= channels;
						channel_index <= 0;
						mode_q <= rounding_mode;
						zero_q <= output_zero;
						minimum_q <= clamp_min;
						maximum_q <= clamp_max;
						param_kind <= 0;
						param_beat <= 0;
						completed <= 0;
						state <= 4'd1;
					end
				4'd1:
					if (!shape_valid) begin
						error_code <= ERR_DESCRIPTOR;
						state <= 4'd14;
					end
					else begin
						begin : sv2v_autoblock_5
							reg signed [31:0] r;
							for (r = 0; r < 6; r = r + 1)
								range_end_q[r] <= {32'd0, range_base[r * 32+:32]} + range_bytes[r * 64+:64];
						end
						state <= 4'd2;
					end
				4'd2:
					if (!addresses_valid) begin
						error_code <= ERR_DESCRIPTOR;
						state <= 4'd14;
					end
					else
						state <= 4'd3;
				4'd3:
					if (!overlaps_valid) begin
						error_code <= ERR_DESCRIPTOR;
						state <= 4'd14;
					end
					else
						state <= 4'd4;
				4'd4:
					if (dma_req_ready)
						state <= 4'd5;
				4'd5:
					if (dma_rsp_valid) begin
						if ((dma_rsp_error || dma_rsp_write) || (dma_rsp_id != 4'd0)) begin
							error_code <= ERR_DMA;
							state <= 4'd14;
						end
						else if (param_rsp_bad) begin
							error_code <= ERR_PARAMETER;
							state <= 4'd14;
						end
						else begin
							read_bytes <= read_bytes + 32'd16;
							if (((param_beat + 9'd1) * 9'd4) >= channels_q) begin
								param_beat <= 0;
								if (param_kind == 2'd2) begin
									block_count <= (elements_q >= 32'd16 ? 5'd16 : sv2v_cast_5(elements_q));
									input_beat <= 0;
									state <= (use_lut_q ? 4'd6 : 4'd8);
								end
								else begin
									param_kind <= param_kind + 1'b1;
									state <= 4'd4;
								end
							end
							else begin
								param_beat <= param_beat + 1'b1;
								state <= 4'd4;
							end
						end
					end
				4'd6:
					if (dma_req_ready)
						state <= 4'd7;
				4'd7:
					if (dma_rsp_valid) begin
						if ((dma_rsp_error || dma_rsp_write) || (dma_rsp_id != 4'd0)) begin
							error_code <= ERR_DMA;
							state <= 4'd14;
						end
						else begin
							read_bytes <= read_bytes + 32'd16;
							if (lut_beat == 4'd15) begin
								input_beat <= 0;
								state <= 4'd8;
							end
							else begin
								lut_beat <= lut_beat + 1'b1;
								state <= (response_last ? 4'd6 : 4'd7);
							end
						end
					end
				4'd8:
					if (dma_req_ready)
						state <= 4'd9;
				4'd9:
					if (dma_rsp_valid) begin
						if ((dma_rsp_error || dma_rsp_write) || (dma_rsp_id != 4'd0)) begin
							error_code <= ERR_DMA;
							partial_output <= completed != 0;
							state <= 4'd14;
						end
						else begin
							read_bytes <= read_bytes + 32'd16;
							if (((sv2v_cast_5(input_beat) + 5'd1) * 5'd4) >= block_count) begin
								feed_count <= 0;
								collect_count <= 0;
								param_issued <= 0;
								state <= 4'd10;
							end
							else begin
								input_beat <= input_beat + 1'b1;
								state <= (response_last ? 4'd8 : 4'd9);
							end
						end
					end
				4'd10: begin
					if (result_pending) begin
						output_block[collect_count[3:0]] <= (use_lut_q ? lut_beat_q[8 * result_value_q[3:0]+:8] : result_value_q);
						collect_count <= collect_count + 1'b1;
						if ((collect_count + 5'd1) == block_count)
							state <= ((INPUT_PREFETCH && (pf_state != 2'd3)) && (next_first < elements_q) ? 4'd15 : 4'd11);
					end
					if (param_issued && pipe_in_ready)
						param_issued <= 0;
					if (operand_read) begin
						lane_q <= channel_index[1:0];
						input_lane_q <= feed_count[1:0];
						param_issued <= 1;
						feed_count <= feed_count + 1'b1;
						channel_index <= ((channel_index + 9'd1) == channels_q ? 9'd0 : channel_index + 1'b1);
					end
					if (pipe_out_valid && pipe_out_overflow) begin
						error_code <= ERR_OVERFLOW;
						partial_output <= completed != 0;
						param_issued <= 0;
						state <= (INPUT_PREFETCH ? 4'd15 : 4'd14);
					end
				end
				4'd15:
					if ((pf_state == 2'd3) || (pf_state == 2'd0))
						state <= (error_code != ERR_NONE ? 4'd14 : 4'd11);
				4'd11:
					if (dma_req_ready)
						state <= 4'd12;
				4'd12:
					if (dma_rsp_valid) begin
						if ((dma_rsp_error || !dma_rsp_write) || (dma_rsp_id != 4'd0)) begin
							error_code <= ERR_DMA;
							partial_output <= 1'b1;
							state <= 4'd14;
						end
						else begin
							write_bytes <= write_bytes + sv2v_cast_32(block_count);
							completed <= completed + sv2v_cast_32(block_count);
							if ((completed + sv2v_cast_32(block_count)) == elements_q)
								state <= 4'd13;
							else begin
								block_count <= (((elements_q - completed) - sv2v_cast_32(block_count)) >= 32'd16 ? 5'd16 : sv2v_cast_5((elements_q - completed) - sv2v_cast_32(block_count)));
								input_beat <= 0;
								if (INPUT_PREFETCH) begin
									input_bank <= ~input_bank;
									pf_state <= 2'd0;
									feed_count <= 0;
									collect_count <= 0;
									param_issued <= 0;
									state <= 4'd10;
								end
								else
									state <= 4'd8;
							end
						end
					end
				4'd13, 4'd14:
					if (done_ready)
						state <= 4'd0;
				default: state <= 4'd14;
			endcase
			if (pf_rsp_bad) begin
				error_code <= ERR_DMA;
				partial_output <= completed != 0;
				param_issued <= 0;
				state <= 4'd15;
			end
		end
	initial _sv2v_0 = 0;
endmodule
module soc_requant_lut_dma_tiled (
	clk,
	rst,
	start_valid,
	start_ready,
	source_addr,
	output_addr,
	bias_addr,
	multiplier_addr,
	shift_addr,
	lut_addr,
	use_lut,
	pixels,
	channels,
	acc_abs_bound,
	rounding_mode,
	output_zero,
	clamp_min,
	clamp_max,
	done_valid,
	done_ready,
	error_code,
	partial_output,
	read_bytes,
	write_bytes,
	stall_cycles,
	active_cycles,
	dma_req_valid,
	dma_req_ready,
	dma_req_write,
	dma_req_addr,
	dma_req_wdata,
	dma_req_wstrb,
	dma_req_id,
	dma_req_len,
	dma_rsp_last,
	dma_rsp_valid,
	dma_rsp_ready,
	dma_rsp_write,
	dma_rsp_id,
	dma_rsp_rdata,
	dma_rsp_error
);
	reg _sv2v_0;
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [32:0] DDR_BYTES = 33'h004000000;
	parameter [0:0] INPUT_PREFETCH = 1'b1;
	parameter [0:0] READ_BURST_ENABLE = 1'b1;
	parameter [0:0] WRITE_ACK_OVERLAP = 1'b1;
	parameter signed [31:0] TILE_ELEMS = 256;
	parameter signed [31:0] LANES = 4;
	parameter [0:0] PARAM_BURST_ENABLE = 1'b1;
	input wire clk;
	input wire rst;
	input wire start_valid;
	output wire start_ready;
	input wire [31:0] source_addr;
	input wire [31:0] output_addr;
	input wire [31:0] bias_addr;
	input wire [31:0] multiplier_addr;
	input wire [31:0] shift_addr;
	input wire [31:0] lut_addr;
	input wire use_lut;
	input wire [31:0] pixels;
	input wire [8:0] channels;
	input wire [31:0] acc_abs_bound;
	input wire [1:0] rounding_mode;
	input wire signed [31:0] output_zero;
	input wire signed [31:0] clamp_min;
	input wire signed [31:0] clamp_max;
	output wire done_valid;
	input wire done_ready;
	output reg [3:0] error_code;
	output reg partial_output;
	output reg [31:0] read_bytes;
	output reg [31:0] write_bytes;
	output reg [31:0] stall_cycles;
	output reg [31:0] active_cycles;
	output wire dma_req_valid;
	input wire dma_req_ready;
	output wire dma_req_write;
	output wire [31:0] dma_req_addr;
	output wire [127:0] dma_req_wdata;
	output wire [15:0] dma_req_wstrb;
	output wire [3:0] dma_req_id;
	output reg [3:0] dma_req_len;
	input wire dma_rsp_last;
	input wire dma_rsp_valid;
	output wire dma_rsp_ready;
	input wire dma_rsp_write;
	input wire [3:0] dma_rsp_id;
	input wire [127:0] dma_rsp_rdata;
	input wire dma_rsp_error;
	localparam signed [31:0] COUNT_W = $clog2(TILE_ELEMS + 1);
	localparam signed [31:0] WORD_W = $clog2(TILE_ELEMS / 4);
	localparam signed [31:0] OUT_W = $clog2((TILE_ELEMS / 16) + 1);
	reg vector_q;
	wire [2:0] step_elements = (vector_q ? 3'd4 : 3'd1);
	reg [OUT_W - 1:0] output_word;
	reg [4:0] output_left;
	reg output_packet;
	reg write_pending;
	reg [COUNT_W - 1:0] pending_write_bytes;
	reg [COUNT_W - 1:0] output_packet_bytes;
	function automatic [COUNT_W - 1:0] sv2v_cast_D4579;
		input reg [COUNT_W - 1:0] inp;
		sv2v_cast_D4579 = inp;
	endfunction
	wire [COUNT_W - 1:0] output_first = sv2v_cast_D4579(output_word) << 4;
	reg [COUNT_W - 1:0] block_count;
	wire [COUNT_W - 1:0] output_remaining = block_count - output_first;
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	wire [4:0] output_valid_bytes = (output_remaining >= 16 ? 5'd16 : sv2v_cast_5(output_remaining));
	reg [3:0] state;
	reg [31:0] source_q;
	reg [31:0] output_q;
	reg [31:0] elements_q;
	reg [31:0] bound_q;
	reg [31:0] param_base_q [0:2];
	reg [31:0] lut_base_q;
	reg use_lut_q;
	reg [3:0] lut_beat;
	reg [8:0] channels_q;
	reg [8:0] channel_index;
	reg [1:0] mode_q;
	reg [1:0] param_kind;
	reg signed [31:0] zero_q;
	reg signed [31:0] minimum_q;
	reg signed [31:0] maximum_q;
	reg [8:0] param_beat;
	reg [31:0] completed;
	reg [COUNT_W - 1:0] feed_count;
	reg [COUNT_W - 1:0] collect_count;
	reg [WORD_W - 1:0] input_beat;
	reg param_issued;
	reg [1:0] pf_state;
	reg input_bank;
	reg [WORD_W - 1:0] pf_beat;
	reg [COUNT_W - 1:0] pf_count;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	wire [31:0] next_first = completed + sv2v_cast_32(block_count);
	wire [31:0] next_remaining = elements_q - next_first;
	wire pf_request = INPUT_PREFETCH && (pf_state == 2'd1);
	wire pf_response = INPUT_PREFETCH && (pf_state == 2'd2);
	wire pf_rsp_fire = pf_response && dma_rsp_valid;
	wire pf_rsp_bad = pf_rsp_fire && ((dma_rsp_error || dma_rsp_write) || (dma_rsp_id != 4'd0));
	wire pipe_out_overflow;
	wire pipe_out_valid;
	wire arithmetic_fault = ((state == 4'd10) && pipe_out_valid) && pipe_out_overflow;
	wire [127:0] bias_beat_q;
	wire [127:0] multiplier_beat_q;
	wire [127:0] input_beat_q;
	wire [23:0] shift_beat_q;
	reg [1:0] lane_q;
	reg [1:0] input_lane_q;
	reg result_pending;
	reg [7:0] result_value_q [0:LANES - 1];
	wire [127:0] lut_beat_q [0:LANES - 1];
	wire [LANES - 1:0] lane_ready;
	wire [LANES - 1:0] lane_valid;
	wire [LANES - 1:0] lane_overflow;
	wire [7:0] lane_value [0:LANES - 1];
	reg [7:0] output_block [0:TILE_ELEMS - 1];
	wire pipe_in_valid;
	wire pipe_in_ready;
	wire pipe_out_ready;
	wire [127:0] output_packed;
	wire [15:0] output_strobes;
	wire [63:0] element_count_wide;
	reg [63:0] element_count_q_wide;
	wire [63:0] source_bytes_wide;
	wire [63:0] parameter_bytes_wide;
	wire [63:0] output_bytes_wide;
	reg shape_valid;
	reg addresses_valid;
	reg overlaps_valid;
	reg param_rsp_bad;
	wire [191:0] range_base;
	wire [383:0] range_bytes;
	reg [63:0] range_end_q [0:5];
	wire [32:0] ddr_end;
	localparam [3:0] ERR_NONE = 0;
	localparam [3:0] ERR_DESCRIPTOR = 1;
	localparam [3:0] ERR_DMA = 2;
	localparam [3:0] ERR_PARAMETER = 3;
	localparam [3:0] ERR_OVERFLOW = 4;
	assign ddr_end = {1'b0, DDR_BASE} + DDR_BYTES;
	function automatic [63:0] sv2v_cast_64;
		input reg [63:0] inp;
		sv2v_cast_64 = inp;
	endfunction
	assign element_count_wide = sv2v_cast_64(pixels) * sv2v_cast_64(channels);
	assign source_bytes_wide = ((element_count_q_wide + 64'd3) >> 2) << 4;
	assign output_bytes_wide = ((element_count_q_wide + 64'd15) >> 4) << 4;
	assign parameter_bytes_wide = ((sv2v_cast_64(channels_q) + 64'd3) >> 2) << 4;
	assign range_base[0+:32] = source_q;
	assign range_base[32+:32] = output_q;
	assign range_base[64+:32] = param_base_q[0];
	assign range_base[96+:32] = param_base_q[1];
	assign range_base[128+:32] = param_base_q[2];
	assign range_base[160+:32] = lut_base_q;
	assign range_bytes[0+:64] = source_bytes_wide;
	assign range_bytes[64+:64] = output_bytes_wide;
	assign range_bytes[128+:64] = parameter_bytes_wide;
	assign range_bytes[192+:64] = parameter_bytes_wide;
	assign range_bytes[256+:64] = parameter_bytes_wide;
	assign range_bytes[320+:64] = 64'd256;
	always @(*) begin
		if (_sv2v_0)
			;
		shape_valid = (((((((((((element_count_q_wide != 0) && (channels_q != 0)) && (channels_q <= 9'd256)) && (element_count_q_wide <= 64'h00000000ffffffff)) && (bound_q != 0)) && (bound_q <= 32'h7fffffff)) && (mode_q <= 2'd2)) && (zero_q >= -32'sd128)) && (zero_q <= 32'sd127)) && (minimum_q >= -32'sd128)) && (maximum_q <= 32'sd127)) && (minimum_q <= maximum_q);
		addresses_valid = 1;
		overlaps_valid = 1;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < 6; i = i + 1)
				if ((i < 5) || use_lut_q) begin
					if (((range_base[(i * 32) + 3-:4] != 0) || (range_base[i * 32+:32] < DDR_BASE)) || (range_end_q[i] > {31'd0, ddr_end}))
						addresses_valid = 0;
					begin : sv2v_autoblock_2
						reg signed [31:0] j;
						for (j = 0; j < i; j = j + 1)
							if ((((j < 5) || use_lut_q) && ({32'd0, range_base[i * 32+:32]} < range_end_q[j])) && ({32'd0, range_base[j * 32+:32]} < range_end_q[i]))
								overlaps_valid = 0;
					end
				end
		end
	end
	function automatic [32:0] absolute_bias;
		input reg [31:0] word;
		reg signed [32:0] extended;
		begin
			extended = $signed({word[31], word});
			absolute_bias = (extended < 0 ? $unsigned(-extended) : $unsigned(extended));
		end
	endfunction
	function automatic signed [8:0] sv2v_cast_9_signed;
		input reg signed [8:0] inp;
		sv2v_cast_9_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		param_rsp_bad = 0;
		begin : sv2v_autoblock_3
			reg signed [31:0] lane;
			for (lane = 0; lane < 4; lane = lane + 1)
				if (((param_beat * 9'd4) + sv2v_cast_9_signed(lane)) < channels_q)
					case (param_kind)
						2'd0:
							if (({1'b0, bound_q} + {1'b0, absolute_bias(dma_rsp_rdata[lane * 32+:32])}) > 34'h07fffffff)
								param_rsp_bad = 1;
						2'd1:
							if (dma_rsp_rdata[(lane * 32) + 31])
								param_rsp_bad = 1;
						default:
							if (dma_rsp_rdata[lane * 32+:32] > 32'd62)
								param_rsp_bad = 1;
					endcase
		end
	end
	assign start_ready = state == 4'd0;
	assign done_valid = (state == 4'd13) || (state == 4'd14);
	assign dma_req_valid = ((((state == 4'd4) || (state == 4'd6)) || (state == 4'd8)) || (state == 4'd11)) || pf_request;
	assign dma_req_write = state == 4'd11;
	assign dma_req_id = 4'd0;
	assign dma_req_addr = (pf_request ? (source_q + (next_first << 2)) + (sv2v_cast_32(pf_beat) << 4) : (state == 4'd4 ? param_base_q[param_kind] + {19'd0, param_beat, 4'd0} : (state == 4'd6 ? lut_base_q + {24'd0, lut_beat, 4'd0} : (state == 4'd8 ? (source_q + (completed << 2)) + (sv2v_cast_32(input_beat) << 4) : (output_q + completed) + (sv2v_cast_32(output_word) << 4)))));
	reg [8:0] burst_words;
	reg [8:0] boundary_words;
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		burst_words = 1;
		if (READ_BURST_ENABLE) begin
			if (pf_request)
				burst_words = ((sv2v_cast_9(pf_count) + 9'd3) >> 2) - sv2v_cast_9(pf_beat);
			else if (state == 4'd8)
				burst_words = ((sv2v_cast_9(block_count) + 9'd3) >> 2) - sv2v_cast_9(input_beat);
			else if (state == 4'd6)
				burst_words = 9'd16 - sv2v_cast_9(lut_beat);
			else if ((state == 4'd4) && PARAM_BURST_ENABLE)
				burst_words = ((channels_q + 9'd3) >> 2) - param_beat;
			else if ((state == 4'd11) && !output_packet)
				burst_words = ((sv2v_cast_9(block_count) + 9'd15) >> 4) - sv2v_cast_9(output_word);
		end
		if (burst_words > 16)
			burst_words = 16;
		boundary_words = 9'd256 - {1'b0, dma_req_addr[11:4]};
		if (burst_words > boundary_words)
			burst_words = boundary_words;
		dma_req_len = sv2v_cast_4(burst_words - 1'b1);
	end
	wire response_last = !READ_BURST_ENABLE || dma_rsp_last;
	assign dma_req_wdata = output_packed;
	assign dma_req_wstrb = (state == 4'd11 ? output_strobes : 16'd0);
	assign dma_rsp_ready = (((((state == 4'd5) || (state == 4'd7)) || (state == 4'd9)) || (state == 4'd12)) || pf_response) || write_pending;
	assign pipe_in_valid = (state == 4'd10) && param_issued;
	assign pipe_out_ready = state == 4'd10;
	assign pipe_in_ready = &lane_ready;
	assign pipe_out_valid = &lane_valid;
	assign pipe_out_overflow = (vector_q ? |lane_overflow : lane_overflow[0]);
	wire response_ok = (((((!rst && dma_rsp_valid) && dma_rsp_ready) && !write_pending) && !dma_rsp_error) && !dma_rsp_write) && (dma_rsp_id == 0);
	wire parameter_write = ((response_ok && (state == 4'd5)) && !param_rsp_bad) && (error_code == ERR_NONE);
	wire operand_read = ((!rst && (state == 4'd10)) && (feed_count < block_count)) && (!param_issued || pipe_in_ready);
	wire result_read = ((!rst && (state == 4'd10)) && pipe_out_valid) && !pipe_out_overflow;
	wire input_write = response_ok && ((state == 4'd9) || (pf_response && (error_code == ERR_NONE)));
	wire [WORD_W:0] input_write_addr = (pf_response ? {~input_bank, pf_beat} : {input_bank, input_beat});
	wire lut_write = response_ok && (state == 4'd7);
	wire arithmetic_reset = rst || (state == 4'd0);
	soc_rq_sync_words #(
		.WIDTH(128),
		.ADDR_W(6)
	) bias_storage(
		.clk(clk),
		.wr_en(parameter_write && (param_kind == 0)),
		.wr_addr(param_beat[5:0]),
		.wr_data(dma_rsp_rdata),
		.rd_en(operand_read),
		.rd_addr(channel_index[7:2]),
		.rd_data(bias_beat_q)
	);
	soc_rq_sync_words #(
		.WIDTH(128),
		.ADDR_W(6)
	) multiplier_storage(
		.clk(clk),
		.wr_en(parameter_write && (param_kind == 1)),
		.wr_addr(param_beat[5:0]),
		.wr_data(dma_rsp_rdata),
		.rd_en(operand_read),
		.rd_addr(channel_index[7:2]),
		.rd_data(multiplier_beat_q)
	);
	soc_rq_sync_words #(
		.WIDTH(24),
		.ADDR_W(6)
	) shift_storage(
		.clk(clk),
		.wr_en(parameter_write && (param_kind == 2)),
		.wr_addr(param_beat[5:0]),
		.wr_data({dma_rsp_rdata[101:96], dma_rsp_rdata[69:64], dma_rsp_rdata[37:32], dma_rsp_rdata[5:0]}),
		.rd_en(operand_read),
		.rd_addr(channel_index[7:2]),
		.rd_data(shift_beat_q)
	);
	soc_rq_sync_words #(
		.WIDTH(128),
		.ADDR_W(WORD_W + 1)
	) input_storage(
		.clk(clk),
		.wr_en(input_write),
		.wr_addr(input_write_addr),
		.wr_data(dma_rsp_rdata),
		.rd_en(operand_read),
		.rd_addr({input_bank, feed_count[WORD_W + 1:2]}),
		.rd_data(input_beat_q)
	);
	genvar _gv_g_2;
	function automatic signed [1:0] sv2v_cast_2_signed;
		input reg signed [1:0] inp;
		sv2v_cast_2_signed = inp;
	endfunction
	generate
		for (_gv_g_2 = 0; _gv_g_2 < LANES; _gv_g_2 = _gv_g_2 + 1) begin : lanes
			localparam g = _gv_g_2;
			wire active_lane = (g == 0) || vector_q;
			wire [1:0] selected_lane = (vector_q ? sv2v_cast_2_signed(g) : lane_q);
			wire [1:0] selected_input = (vector_q ? sv2v_cast_2_signed(g) : input_lane_q);
			soc_rq_sync_words #(
				.WIDTH(128),
				.ADDR_W(4)
			) lut_storage(
				.clk(clk),
				.wr_en(lut_write),
				.wr_addr(lut_beat),
				.wr_data(dma_rsp_rdata),
				.rd_en(result_read && use_lut_q),
				.rd_addr(lane_value[g][7:4]),
				.rd_data(lut_beat_q[g])
			);
			soc_requant_pipeline arithmetic(
				.clk(clk),
				.rst(arithmetic_reset),
				.in_valid(pipe_in_valid),
				.in_ready(lane_ready[g]),
				.in_acc((active_lane ? $signed(input_beat_q[32 * selected_input+:32]) : 32'sd0)),
				.in_bias((active_lane ? $signed(bias_beat_q[32 * selected_lane+:32]) : 32'sd0)),
				.in_multiplier((active_lane ? $signed(multiplier_beat_q[32 * selected_lane+:32]) : 32'sd0)),
				.in_shift((active_lane ? shift_beat_q[6 * selected_lane+:6] : 6'd0)),
				.in_mode(mode_q),
				.in_zero(zero_q),
				.in_clamp_min(minimum_q),
				.in_clamp_max(maximum_q),
				.out_valid(lane_valid[g]),
				.out_ready(pipe_out_ready),
				.out_value(lane_value[g]),
				.out_overflow(lane_overflow[g])
			);
		end
	endgenerate
	genvar _gv_g_3;
	function automatic [$clog2(TILE_ELEMS) - 1:0] sv2v_cast_2A93E;
		input reg [$clog2(TILE_ELEMS) - 1:0] inp;
		sv2v_cast_2A93E = inp;
	endfunction
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	generate
		for (_gv_g_3 = 0; _gv_g_3 < 16; _gv_g_3 = _gv_g_3 + 1) begin : pack_output
			localparam g = _gv_g_3;
			assign output_packed[g * 8+:8] = output_block[sv2v_cast_2A93E(output_first + sv2v_cast_D4579(g))];
			assign output_strobes[g] = sv2v_cast_5_signed(g) < output_valid_bytes;
		end
	endgenerate
	always @(posedge clk)
		if (rst) begin
			state <= 4'd0;
			source_q <= 0;
			output_q <= 0;
			elements_q <= 0;
			bound_q <= 0;
			element_count_q_wide <= 0;
			begin : sv2v_autoblock_4
				reg signed [31:0] r;
				for (r = 0; r < 6; r = r + 1)
					range_end_q[r] <= 0;
			end
			param_base_q[0] <= 0;
			param_base_q[1] <= 0;
			param_base_q[2] <= 0;
			lut_base_q <= 0;
			use_lut_q <= 0;
			lut_beat <= 0;
			channels_q <= 0;
			channel_index <= 0;
			mode_q <= 0;
			zero_q <= 0;
			minimum_q <= 0;
			maximum_q <= 0;
			param_beat <= 0;
			param_kind <= 0;
			completed <= 0;
			block_count <= 0;
			feed_count <= 0;
			collect_count <= 0;
			input_beat <= 0;
			param_issued <= 0;
			lane_q <= 0;
			input_lane_q <= 0;
			pf_state <= 2'd0;
			pf_beat <= 0;
			pf_count <= 0;
			input_bank <= 0;
			result_pending <= 0;
			write_pending <= 0;
			pending_write_bytes <= 0;
			begin : sv2v_autoblock_5
				reg signed [31:0] g;
				for (g = 0; g < LANES; g = g + 1)
					result_value_q[g] <= 0;
			end
			vector_q <= 0;
			output_word <= 0;
			output_left <= 0;
			output_packet <= 0;
			output_packet_bytes <= 0;
			error_code <= ERR_NONE;
			partial_output <= 0;
			read_bytes <= 0;
			write_bytes <= 0;
			stall_cycles <= 0;
			active_cycles <= 0;
		end
		else begin
			result_pending <= result_read;
			if (result_read) begin : sv2v_autoblock_6
				reg signed [31:0] g;
				for (g = 0; g < LANES; g = g + 1)
					result_value_q[g] <= lane_value[g];
			end
			if (((state != 4'd0) && (state != 4'd13)) && (state != 4'd14))
				active_cycles <= active_cycles + 1'b1;
			if ((dma_req_valid && !dma_req_ready) || (dma_rsp_ready && !dma_rsp_valid))
				stall_cycles <= stall_cycles + 1'b1;
			if (INPUT_PREFETCH)
				case (pf_state)
					2'd0:
						if ((((((state == 4'd10) || (state == 4'd15)) && !write_pending) && (error_code == ERR_NONE)) && !arithmetic_fault) && (next_first < elements_q)) begin
							pf_count <= (next_remaining >= TILE_ELEMS ? sv2v_cast_D4579(TILE_ELEMS) : sv2v_cast_D4579(next_remaining));
							pf_beat <= 0;
							pf_state <= 2'd1;
						end
					2'd1:
						if (dma_req_ready)
							pf_state <= 2'd2;
					2'd2:
						if (dma_rsp_valid) begin
							if ((pf_rsp_bad || (error_code != ERR_NONE)) || arithmetic_fault)
								pf_state <= (response_last ? 2'd3 : 2'd2);
							else if (((sv2v_cast_D4579(pf_beat) + sv2v_cast_D4579(1)) << 2) >= pf_count)
								pf_state <= 2'd3;
							else begin
								pf_beat <= pf_beat + 1'b1;
								pf_state <= (response_last ? 2'd1 : 2'd2);
							end
							if (!pf_rsp_bad)
								read_bytes <= read_bytes + 32'd16;
						end
					default:
						;
				endcase
			case (state)
				4'd0:
					if (start_valid) begin
						write_pending <= 0;
						pending_write_bytes <= 0;
						pf_state <= 2'd0;
						pf_beat <= 0;
						pf_count <= 0;
						input_bank <= 0;
						param_issued <= 0;
						vector_q <= (LANES == 4) && (channels[1:0] == 0);
						output_word <= 0;
						output_left <= 0;
						output_packet <= 0;
						output_packet_bytes <= 0;
						error_code <= ERR_NONE;
						partial_output <= 0;
						read_bytes <= 0;
						write_bytes <= 0;
						stall_cycles <= 0;
						active_cycles <= 0;
						source_q <= source_addr;
						output_q <= output_addr;
						elements_q <= element_count_wide[31:0];
						element_count_q_wide <= element_count_wide;
						bound_q <= acc_abs_bound;
						param_base_q[0] <= bias_addr;
						param_base_q[1] <= multiplier_addr;
						param_base_q[2] <= shift_addr;
						lut_base_q <= lut_addr;
						use_lut_q <= use_lut;
						lut_beat <= 0;
						channels_q <= channels;
						channel_index <= 0;
						mode_q <= rounding_mode;
						zero_q <= output_zero;
						minimum_q <= clamp_min;
						maximum_q <= clamp_max;
						param_kind <= 0;
						param_beat <= 0;
						completed <= 0;
						state <= 4'd1;
					end
				4'd1:
					if (!shape_valid) begin
						error_code <= ERR_DESCRIPTOR;
						state <= 4'd14;
					end
					else begin
						begin : sv2v_autoblock_7
							reg signed [31:0] r;
							for (r = 0; r < 6; r = r + 1)
								range_end_q[r] <= {32'd0, range_base[r * 32+:32]} + range_bytes[r * 64+:64];
						end
						state <= 4'd2;
					end
				4'd2:
					if (!addresses_valid) begin
						error_code <= ERR_DESCRIPTOR;
						state <= 4'd14;
					end
					else
						state <= 4'd3;
				4'd3:
					if (!overlaps_valid) begin
						error_code <= ERR_DESCRIPTOR;
						state <= 4'd14;
					end
					else
						state <= 4'd4;
				4'd4:
					if (dma_req_ready)
						state <= 4'd5;
				4'd5:
					if (dma_rsp_valid) begin
						if (((((error_code != ERR_NONE) || dma_rsp_error) || dma_rsp_write) || (dma_rsp_id != 4'd0)) || param_rsp_bad) begin
							if (error_code == ERR_NONE)
								error_code <= ((dma_rsp_error || dma_rsp_write) || (dma_rsp_id != 4'd0) ? ERR_DMA : ERR_PARAMETER);
							if (response_last)
								state <= 4'd14;
						end
						else begin
							read_bytes <= read_bytes + 32'd16;
							if (((param_beat + 9'd1) * 9'd4) >= channels_q) begin
								param_beat <= 0;
								if (param_kind == 2'd2) begin
									block_count <= (elements_q >= TILE_ELEMS ? sv2v_cast_D4579(TILE_ELEMS) : sv2v_cast_D4579(elements_q));
									input_beat <= 0;
									state <= (use_lut_q ? 4'd6 : 4'd8);
								end
								else begin
									param_kind <= param_kind + 1'b1;
									state <= 4'd4;
								end
							end
							else begin
								param_beat <= param_beat + 1'b1;
								state <= (response_last ? 4'd4 : 4'd5);
							end
						end
					end
				4'd6:
					if (dma_req_ready)
						state <= 4'd7;
				4'd7:
					if (dma_rsp_valid) begin
						if ((dma_rsp_error || dma_rsp_write) || (dma_rsp_id != 4'd0)) begin
							error_code <= ERR_DMA;
							state <= 4'd14;
						end
						else begin
							read_bytes <= read_bytes + 32'd16;
							if (lut_beat == 4'd15) begin
								input_beat <= 0;
								state <= 4'd8;
							end
							else begin
								lut_beat <= lut_beat + 1'b1;
								state <= (response_last ? 4'd6 : 4'd7);
							end
						end
					end
				4'd8:
					if (dma_req_ready)
						state <= 4'd9;
				4'd9:
					if (dma_rsp_valid) begin
						if ((dma_rsp_error || dma_rsp_write) || (dma_rsp_id != 4'd0)) begin
							error_code <= ERR_DMA;
							partial_output <= write_bytes != 0;
							state <= 4'd14;
						end
						else begin
							read_bytes <= read_bytes + 32'd16;
							if (((sv2v_cast_D4579(input_beat) + sv2v_cast_D4579(1)) * sv2v_cast_D4579(4)) >= block_count) begin
								feed_count <= 0;
								collect_count <= 0;
								param_issued <= 0;
								state <= 4'd10;
							end
							else begin
								input_beat <= input_beat + 1'b1;
								state <= (response_last ? 4'd8 : 4'd9);
							end
						end
					end
				4'd10: begin
					if (result_pending) begin
						begin : sv2v_autoblock_8
							reg signed [31:0] g;
							for (g = 0; g < LANES; g = g + 1)
								if ((g == 0) || vector_q)
									output_block[sv2v_cast_2A93E(collect_count + sv2v_cast_D4579(g))] <= (use_lut_q ? lut_beat_q[g][8 * result_value_q[g][3:0]+:8] : result_value_q[g]);
						end
						collect_count <= collect_count + sv2v_cast_D4579(step_elements);
						if ((collect_count + sv2v_cast_D4579(step_elements)) == block_count) begin
							output_word <= 0;
							output_packet <= 0;
							output_packet_bytes <= 0;
							state <= (write_pending || ((INPUT_PREFETCH && (pf_state != 2'd3)) && (next_first < elements_q)) ? 4'd15 : 4'd11);
						end
					end
					if (param_issued && pipe_in_ready)
						param_issued <= 0;
					if (operand_read) begin
						lane_q <= channel_index[1:0];
						input_lane_q <= feed_count[1:0];
						param_issued <= 1;
						feed_count <= feed_count + sv2v_cast_D4579(step_elements);
						channel_index <= ((channel_index + sv2v_cast_9(step_elements)) == channels_q ? 9'd0 : channel_index + sv2v_cast_9(step_elements));
					end
					if (pipe_out_valid && pipe_out_overflow) begin
						error_code <= ERR_OVERFLOW;
						partial_output <= (write_bytes != 0) || write_pending;
						param_issued <= 0;
						state <= (INPUT_PREFETCH ? 4'd15 : 4'd14);
					end
				end
				4'd15:
					if (!write_pending && ((pf_state == 2'd3) || ((pf_state == 2'd0) && (((error_code != ERR_NONE) || (next_first >= elements_q)) || !INPUT_PREFETCH))))
						state <= (error_code != ERR_NONE ? 4'd14 : 4'd11);
				4'd11:
					if (dma_req_ready) begin
						output_word <= output_word + 1'b1;
						output_packet_bytes <= output_packet_bytes + sv2v_cast_D4579(output_valid_bytes);
						if (!output_packet) begin
							output_packet <= 1;
							output_left <= sv2v_cast_5(burst_words) - 5'd1;
							if (burst_words == 1)
								state <= 4'd12;
						end
						else begin
							output_left <= output_left - 1'b1;
							if (output_left == 1)
								state <= 4'd12;
						end
						if (((((WRITE_ACK_OVERLAP && INPUT_PREFETCH) && ((output_first + sv2v_cast_D4579(16)) >= block_count)) && (next_first < elements_q)) && (pf_state == 2'd3)) && ((!output_packet && (burst_words == 1)) || (output_packet && (output_left == 1)))) begin
							write_pending <= 1;
							pending_write_bytes <= output_packet_bytes + sv2v_cast_D4579(output_valid_bytes);
							completed <= next_first;
							block_count <= pf_count;
							input_bank <= ~input_bank;
							pf_state <= 2'd0;
							feed_count <= 0;
							collect_count <= 0;
							param_issued <= 0;
							output_word <= 0;
							output_packet <= 0;
							output_packet_bytes <= 0;
							state <= 4'd10;
						end
					end
				4'd12:
					if (dma_rsp_valid) begin
						if ((dma_rsp_error || !dma_rsp_write) || (dma_rsp_id != 4'd0)) begin
							error_code <= ERR_DMA;
							partial_output <= 1;
							state <= 4'd14;
						end
						else begin
							write_bytes <= write_bytes + sv2v_cast_32(output_packet_bytes);
							output_packet <= 0;
							output_packet_bytes <= 0;
							if ((sv2v_cast_D4579(output_word) << 4) < block_count)
								state <= 4'd11;
							else begin
								completed <= completed + sv2v_cast_32(block_count);
								if ((completed + sv2v_cast_32(block_count)) == elements_q)
									state <= 4'd13;
								else begin
									block_count <= (((elements_q - completed) - sv2v_cast_32(block_count)) >= TILE_ELEMS ? sv2v_cast_D4579(TILE_ELEMS) : sv2v_cast_D4579((elements_q - completed) - sv2v_cast_32(block_count)));
									input_beat <= 0;
									if (INPUT_PREFETCH) begin
										input_bank <= ~input_bank;
										pf_state <= 2'd0;
										feed_count <= 0;
										collect_count <= 0;
										param_issued <= 0;
										state <= 4'd10;
									end
									else
										state <= 4'd8;
								end
							end
						end
					end
				4'd13, 4'd14:
					if (done_ready)
						state <= 4'd0;
				default: state <= 4'd14;
			endcase
			if (write_pending && dma_rsp_valid) begin
				write_pending <= 0;
				pending_write_bytes <= 0;
				if ((dma_rsp_error || !dma_rsp_write) || (dma_rsp_id != 4'd0)) begin
					error_code <= ERR_DMA;
					partial_output <= 1;
					param_issued <= 0;
					state <= 4'd14;
				end
				else
					write_bytes <= write_bytes + sv2v_cast_32(pending_write_bytes);
			end
			if (pf_rsp_bad) begin
				error_code <= ERR_DMA;
				partial_output <= write_bytes != 0;
				param_issued <= 0;
				state <= 4'd15;
			end
		end
	initial if ((((TILE_ELEMS < 16) || (TILE_ELEMS > 256)) || ((TILE_ELEMS & (TILE_ELEMS - 1)) != 0)) || ((LANES != 1) && (LANES != 4))) begin
		$display("Fatal [%0t] F:/Codex/G26/optimization_tensor/after_conversion/soc_requant_lut_dma.sv:1207:35 - soc_requant_lut_dma_tiled.<unnamed_block>.<unnamed_block>\n msg: ", $time, "RQ_TILED_PARAMETER");
		$finish(1);
	end
	initial _sv2v_0 = 0;
endmodule
module soc_rq_sync_words (
	clk,
	wr_en,
	wr_addr,
	wr_data,
	rd_en,
	rd_addr,
	rd_data
);
	parameter signed [31:0] WIDTH = 128;
	parameter signed [31:0] ADDR_W = 6;
	input wire clk;
	input wire wr_en;
	input wire [ADDR_W - 1:0] wr_addr;
	input wire [WIDTH - 1:0] wr_data;
	input wire rd_en;
	input wire [ADDR_W - 1:0] rd_addr;
	output reg [WIDTH - 1:0] rd_data;
	(* ram_style = "block", syn_ramstyle = "block_ram" *) reg [WIDTH - 1:0] words [0:(1 << ADDR_W) - 1];
	always @(posedge clk) begin
		if (wr_en)
			words[wr_addr] <= wr_data;
		if (rd_en)
			rd_data <= words[rd_addr];
	end
endmodule
module soc_s3_mmio_mem (
	clk,
	rst,
	ddr_ready,
	axi_poisoned,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	start_valid,
	start_ready,
	done_valid,
	done_ready,
	engine_error,
	engine_partial,
	engine_read_bytes,
	engine_write_bytes,
	engine_stall_cycles,
	engine_active_cycles,
	source_addr,
	output_addr,
	bias_addr,
	multiplier_addr,
	shift_addr,
	lut_addr,
	use_lut,
	pixels,
	channels,
	acc_abs_bound,
	rounding_mode,
	output_zero,
	clamp_min,
	clamp_max
);
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	input wire axi_poisoned;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output reg start_valid;
	input wire start_ready;
	input wire done_valid;
	output wire done_ready;
	input wire [3:0] engine_error;
	input wire engine_partial;
	input wire [31:0] engine_read_bytes;
	input wire [31:0] engine_write_bytes;
	input wire [31:0] engine_stall_cycles;
	input wire [31:0] engine_active_cycles;
	output reg [31:0] source_addr;
	output reg [31:0] output_addr;
	output reg [31:0] bias_addr;
	output reg [31:0] multiplier_addr;
	output reg [31:0] shift_addr;
	output reg [31:0] lut_addr;
	output wire use_lut;
	output reg [31:0] pixels;
	output reg [8:0] channels;
	output reg [31:0] acc_abs_bound;
	output wire [1:0] rounding_mode;
	output wire signed [31:0] output_zero;
	output wire signed [31:0] clamp_min;
	output wire signed [31:0] clamp_max;
	reg busy;
	reg done_hold;
	reg rejected_hold;
	reg partial_hold;
	reg [3:0] error_hold;
	reg [31:0] config_q;
	wire hit = ((req_addr >= 16'h0100) && (req_addr <= 16'h0140)) && (req_addr[1:0] == 0);
	assign req_ready = !rst && !rsp_valid;
	assign done_ready = 1'b1;
	assign rounding_mode = config_q[1:0];
	assign use_lut = config_q[2];
	assign output_zero = {{24 {config_q[15]}}, config_q[15:8]};
	assign clamp_min = {{24 {config_q[23]}}, config_q[23:16]};
	assign clamp_max = {{24 {config_q[31]}}, config_q[31:24]};
	always @(posedge clk) begin
		start_valid <= 0;
		if (rst) begin
			rsp_valid <= 0;
			rsp_rdata <= 0;
			rsp_error <= 0;
			busy <= 0;
			done_hold <= 0;
			rejected_hold <= 0;
			partial_hold <= 0;
			error_hold <= 0;
			source_addr <= 0;
			output_addr <= 0;
			bias_addr <= 0;
			multiplier_addr <= 0;
			shift_addr <= 0;
			lut_addr <= 0;
			pixels <= 0;
			channels <= 0;
			acc_abs_bound <= 0;
			config_q <= 0;
		end
		else begin
			if (done_valid) begin
				busy <= 0;
				done_hold <= 1;
				partial_hold <= engine_partial;
				error_hold <= engine_error;
			end
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			if (req_valid && req_ready) begin
				rsp_valid <= 1;
				rsp_error <= 0;
				rsp_rdata <= 0;
				if (!hit || (req_write && (req_wstrb != 4'hf))) begin
					rsp_error <= 1;
					rejected_hold <= 1;
				end
				else if (req_write) begin
					if (busy && (req_addr != 16'h012c)) begin
						rsp_error <= 1;
						rejected_hold <= 1;
					end
					else
						case (req_addr)
							16'h0100:
								if (((((req_wdata != 32'd1) || !start_ready) || !ddr_ready) || axi_poisoned) || busy) begin
									rsp_error <= 1;
									rejected_hold <= 1;
								end
								else begin
									start_valid <= 1;
									busy <= 1;
									done_hold <= 0;
									rejected_hold <= 0;
									partial_hold <= 0;
									error_hold <= 0;
								end
							16'h0104: source_addr <= req_wdata;
							16'h0108: output_addr <= req_wdata;
							16'h010c: bias_addr <= req_wdata;
							16'h0110: multiplier_addr <= req_wdata;
							16'h0114: shift_addr <= req_wdata;
							16'h0118: lut_addr <= req_wdata;
							16'h011c: pixels <= req_wdata;
							16'h0120:
								if (req_wdata[31:9] != 0) begin
									rsp_error <= 1;
									rejected_hold <= 1;
								end
								else
									channels <= req_wdata[8:0];
							16'h0124: acc_abs_bound <= req_wdata;
							16'h0128: config_q <= req_wdata;
							16'h012c:
								if ((req_wdata == 32'd1) && !busy) begin
									done_hold <= 0;
									rejected_hold <= 0;
									partial_hold <= 0;
									error_hold <= 0;
								end
								else begin
									rsp_error <= 1;
									rejected_hold <= 1;
								end
							default: begin
								rsp_error <= 1;
								rejected_hold <= 1;
							end
						endcase
				end
				else
					case (req_addr)
						16'h0100: rsp_rdata <= 0;
						16'h0104: rsp_rdata <= source_addr;
						16'h0108: rsp_rdata <= output_addr;
						16'h010c: rsp_rdata <= bias_addr;
						16'h0110: rsp_rdata <= multiplier_addr;
						16'h0114: rsp_rdata <= shift_addr;
						16'h0118: rsp_rdata <= lut_addr;
						16'h011c: rsp_rdata <= pixels;
						16'h0120: rsp_rdata <= {23'd0, channels};
						16'h0124: rsp_rdata <= acc_abs_bound;
						16'h0128: rsp_rdata <= config_q;
						16'h012c: rsp_rdata <= {20'd0, axi_poisoned, ddr_ready, rejected_hold, partial_hold, error_hold, 2'd0, done_hold, busy};
						16'h0130: rsp_rdata <= engine_read_bytes;
						16'h0134: rsp_rdata <= engine_write_bytes;
						16'h0138: rsp_rdata <= engine_stall_cycles;
						16'h013c: rsp_rdata <= engine_active_cycles;
						16'h0140: rsp_rdata <= 32'h33515253;
						default: begin
							rsp_error <= 1;
							rejected_hold <= 1;
						end
					endcase
			end
		end
	end
endmodule
module soc_rq_to_axi (
	clk,
	rst,
	ddr_ready,
	req_valid,
	req_ready,
	req_write,
	req_addr,
	req_wdata,
	req_wstrb,
	req_id,
	req_len,
	rsp_valid,
	rsp_ready,
	rsp_last,
	rsp_write,
	rsp_id,
	rsp_rdata,
	rsp_error,
	poisoned,
	m_awid,
	m_awaddr,
	m_awlen,
	m_awsize,
	m_awburst,
	m_awvalid,
	m_awready,
	m_wdata,
	m_wstrb,
	m_wlast,
	m_wvalid,
	m_wready,
	m_bid,
	m_bresp,
	m_bvalid,
	m_bready,
	m_arid,
	m_araddr,
	m_arlen,
	m_arsize,
	m_arburst,
	m_arvalid,
	m_arready,
	m_rid,
	m_rdata,
	m_rresp,
	m_rlast,
	m_rvalid,
	m_rready
);
	parameter [31:0] TIMEOUT_CYCLES = 100000000;
	parameter [0:0] BURST_ENABLE = 1'b0;
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	input wire req_valid;
	output wire req_ready;
	input wire req_write;
	input wire [31:0] req_addr;
	input wire [127:0] req_wdata;
	input wire [15:0] req_wstrb;
	input wire [3:0] req_id;
	input wire [3:0] req_len;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire rsp_last;
	output reg rsp_write;
	output reg [3:0] rsp_id;
	output reg [127:0] rsp_rdata;
	output reg rsp_error;
	output wire poisoned;
	output wire [3:0] m_awid;
	output wire [31:0] m_awaddr;
	output wire [7:0] m_awlen;
	output wire [2:0] m_awsize;
	output wire [1:0] m_awburst;
	output wire m_awvalid;
	input wire m_awready;
	output wire [127:0] m_wdata;
	output wire [15:0] m_wstrb;
	output wire m_wlast;
	output wire m_wvalid;
	input wire m_wready;
	input wire [3:0] m_bid;
	input wire [1:0] m_bresp;
	input wire m_bvalid;
	output wire m_bready;
	output wire [3:0] m_arid;
	output wire [31:0] m_araddr;
	output wire [7:0] m_arlen;
	output wire [2:0] m_arsize;
	output wire [1:0] m_arburst;
	output wire m_arvalid;
	input wire m_arready;
	input wire [3:0] m_rid;
	input wire [127:0] m_rdata;
	input wire [1:0] m_rresp;
	input wire m_rlast;
	input wire m_rvalid;
	output wire m_rready;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	generate
		if (!BURST_ENABLE) begin : legacy
			assign rsp_last = 1'b1;
			wire [1:1] sv2v_tmp_reference_path_rsp_write;
			always @(*) rsp_write = sv2v_tmp_reference_path_rsp_write;
			wire [4:1] sv2v_tmp_reference_path_rsp_id;
			always @(*) rsp_id = sv2v_tmp_reference_path_rsp_id;
			wire [128:1] sv2v_tmp_reference_path_rsp_rdata;
			always @(*) rsp_rdata = sv2v_tmp_reference_path_rsp_rdata;
			wire [1:1] sv2v_tmp_reference_path_rsp_error;
			always @(*) rsp_error = sv2v_tmp_reference_path_rsp_error;
			soc_rq_to_axi_single #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) reference_path(
				.clk(clk),
				.rst(rst),
				.ddr_ready(ddr_ready),
				.req_valid(req_valid),
				.req_ready(req_ready),
				.req_write(req_write),
				.req_addr(req_addr),
				.req_wdata(req_wdata),
				.req_wstrb(req_wstrb),
				.req_id(req_id),
				.rsp_valid(rsp_valid),
				.rsp_ready(rsp_ready),
				.rsp_write(sv2v_tmp_reference_path_rsp_write),
				.rsp_id(sv2v_tmp_reference_path_rsp_id),
				.rsp_rdata(sv2v_tmp_reference_path_rsp_rdata),
				.rsp_error(sv2v_tmp_reference_path_rsp_error),
				.poisoned(poisoned),
				.m_awid(m_awid),
				.m_awaddr(m_awaddr),
				.m_awlen(m_awlen),
				.m_awsize(m_awsize),
				.m_awburst(m_awburst),
				.m_awvalid(m_awvalid),
				.m_awready(m_awready),
				.m_wdata(m_wdata),
				.m_wstrb(m_wstrb),
				.m_wlast(m_wlast),
				.m_wvalid(m_wvalid),
				.m_wready(m_wready),
				.m_bid(m_bid),
				.m_bresp(m_bresp),
				.m_bvalid(m_bvalid),
				.m_bready(m_bready),
				.m_arid(m_arid),
				.m_araddr(m_araddr),
				.m_arlen(m_arlen),
				.m_arsize(m_arsize),
				.m_arburst(m_arburst),
				.m_arvalid(m_arvalid),
				.m_arready(m_arready),
				.m_rid(m_rid),
				.m_rdata(m_rdata),
				.m_rresp(m_rresp),
				.m_rlast(m_rlast),
				.m_rvalid(m_rvalid),
				.m_rready(m_rready)
			);
		end
		else begin : burst
			reg [3:0] state;
			reg [31:0] addr_q;
			reg [31:0] wait_cycles;
			reg [127:0] wdata_q;
			reg [15:0] wstrb_q;
			reg [3:0] id_q;
			reg [3:0] len_q;
			reg [3:0] send_index;
			reg write_q;
			reg fault_q;
			reg poison_q;
			reg [8:0] received;
			reg [15:0] write_masks [0:15];
			reg [127:0] read_buffer [0:15];
			wire waiting = (((((state == 4'd1) || (state == 4'd2)) || (state == 4'd3)) || (state == 4'd4)) || (state == 4'd5)) || (state == 4'd9);
			wire step = ((((((state == 4'd1) && m_awready) || ((state == 4'd2) && m_wready)) || ((state == 4'd3) && m_bvalid)) || ((state == 4'd4) && m_arready)) || ((state == 4'd5) && m_rvalid)) || ((state == 4'd9) && req_valid);
			wire timeout_now = (waiting && !step) && (wait_cycles == (TIMEOUT_CYCLES - 1));
			wire read_bad = ((m_rresp != 0) || (m_rid != id_q)) || (m_rlast != (received == {5'd0, len_q}));
			wire terminal_bad = fault_q || read_bad;
			assign req_ready = !rst && ((((state == 4'd0) && ddr_ready) && !poison_q) || (state == 4'd9));
			assign rsp_valid = (state == 4'd7) && !rst;
			assign rsp_last = (write_q || rsp_error) || (send_index == len_q);
			assign poisoned = poison_q || (state == 4'd8);
			assign m_awid = id_q;
			assign m_awaddr = addr_q;
			assign m_awlen = {4'd0, len_q};
			assign m_awsize = 3'd4;
			assign m_awburst = 2'b01;
			assign m_awvalid = (state == 4'd1) && !rst;
			assign m_wdata = wdata_q;
			assign m_wstrb = wstrb_q;
			assign m_wlast = send_index == len_q;
			assign m_wvalid = (state == 4'd2) && !rst;
			assign m_bready = (state == 4'd3) && !rst;
			assign m_arid = id_q;
			assign m_araddr = addr_q;
			assign m_arlen = {4'd0, len_q};
			assign m_arsize = 3'd4;
			assign m_arburst = 2'b01;
			assign m_arvalid = (state == 4'd4) && !rst;
			assign m_rready = (state == 4'd5) && !rst;
			always @(posedge clk)
				if (rst) begin
					state <= 4'd0;
					addr_q <= 0;
					wait_cycles <= 0;
					wdata_q <= 0;
					wstrb_q <= 0;
					id_q <= 0;
					len_q <= 0;
					send_index <= 0;
					write_q <= 0;
					fault_q <= 0;
					poison_q <= 0;
					received <= 0;
					rsp_write <= 0;
					rsp_id <= 0;
					rsp_rdata <= 0;
					rsp_error <= 0;
				end
				else begin
					if (!waiting || step)
						wait_cycles <= 0;
					else if (!timeout_now && !poison_q)
						wait_cycles <= wait_cycles + 1'b1;
					if (timeout_now) begin
						poison_q <= 1;
						fault_q <= 1;
					end
					case (state)
						4'd0:
							if (req_valid && req_ready) begin
								addr_q <= req_addr;
								wdata_q <= req_wdata;
								wstrb_q <= req_wstrb;
								id_q <= req_id;
								len_q <= req_len;
								write_q <= req_write;
								send_index <= 0;
								received <= 0;
								rsp_write <= req_write;
								rsp_id <= req_id;
								rsp_rdata <= 0;
								rsp_error <= 0;
								fault_q <= 0;
								if (req_write) begin
									read_buffer[0] <= req_wdata;
									write_masks[0] <= req_wstrb;
									received <= 1;
								end
								if (((req_addr[3:0] != 0) || (req_write && (req_wstrb == 0))) || (({1'b0, req_addr[11:0]} + (({9'd0, req_len} + 13'd1) << 4)) > 13'd4096)) begin
									fault_q <= 1;
									if (req_write && (req_len != 0))
										state <= 4'd9;
									else begin
										rsp_error <= 1;
										state <= 4'd7;
									end
								end
								else
									state <= (req_write ? (req_len == 0 ? 4'd1 : 4'd9) : 4'd4);
							end
						4'd9:
							if (req_valid) begin
								read_buffer[received[3:0]] <= req_wdata;
								write_masks[received[3:0]] <= req_wstrb;
								received <= received + 1'b1;
								if ((((!req_write || (req_addr != (addr_q + (sv2v_cast_32(received) << 4)))) || (req_id != id_q)) || (req_len != 0)) || (req_wstrb == 0)) begin
									fault_q <= 1;
									poison_q <= 1;
								end
								if (received == {5'd0, len_q}) begin
									if (((((fault_q || !req_write) || (req_addr != (addr_q + (sv2v_cast_32(received) << 4)))) || (req_id != id_q)) || (req_len != 0)) || (req_wstrb == 0)) begin
										rsp_error <= 1;
										state <= 4'd7;
									end
									else
										state <= 4'd1;
								end
							end
						4'd1:
							if (m_awready)
								state <= 4'd2;
						4'd2:
							if (m_wready) begin
								if (send_index == len_q)
									state <= 4'd3;
								else begin
									send_index <= send_index + 1'b1;
									wdata_q <= read_buffer[send_index + 4'd1];
									wstrb_q <= write_masks[send_index + 4'd1];
								end
							end
						4'd3:
							if (m_bvalid) begin
								rsp_write <= 1;
								rsp_id <= m_bid;
								rsp_error <= (fault_q || (m_bresp != 0)) || (m_bid != id_q);
								if (m_bid != id_q)
									poison_q <= 1;
								state <= 4'd7;
							end
						4'd4:
							if (m_arready)
								state <= 4'd5;
						4'd5:
							if (m_rvalid) begin
								if (received < 16)
									read_buffer[received[3:0]] <= m_rdata;
								if (received != 9'h1ff)
									received <= received + 1'b1;
								if (read_bad)
									fault_q <= 1;
								if ((m_rid != id_q) || (m_rlast != (received == {5'd0, len_q})))
									poison_q <= 1;
								if (m_rlast) begin
									rsp_error <= terminal_bad;
									rsp_write <= 0;
									rsp_id <= id_q;
									send_index <= 0;
									if (terminal_bad) begin
										rsp_rdata <= 0;
										state <= 4'd7;
									end
									else if (len_q == 0) begin
										rsp_rdata <= m_rdata;
										state <= 4'd7;
									end
									else
										state <= 4'd6;
								end
							end
						4'd6: begin
							rsp_rdata <= read_buffer[0];
							state <= 4'd7;
						end
						4'd7:
							if (rsp_ready) begin
								if (rsp_last)
									state <= (poison_q ? 4'd8 : 4'd0);
								else begin
									send_index <= send_index + 1'b1;
									rsp_rdata <= read_buffer[send_index + 4'd1];
								end
							end
						default: state <= 4'd8;
					endcase
				end
		end
	endgenerate
endmodule
module soc_rq_to_axi_single (
	clk,
	rst,
	ddr_ready,
	req_valid,
	req_ready,
	req_write,
	req_addr,
	req_wdata,
	req_wstrb,
	req_id,
	rsp_valid,
	rsp_ready,
	rsp_write,
	rsp_id,
	rsp_rdata,
	rsp_error,
	poisoned,
	m_awid,
	m_awaddr,
	m_awlen,
	m_awsize,
	m_awburst,
	m_awvalid,
	m_awready,
	m_wdata,
	m_wstrb,
	m_wlast,
	m_wvalid,
	m_wready,
	m_bid,
	m_bresp,
	m_bvalid,
	m_bready,
	m_arid,
	m_araddr,
	m_arlen,
	m_arsize,
	m_arburst,
	m_arvalid,
	m_arready,
	m_rid,
	m_rdata,
	m_rresp,
	m_rlast,
	m_rvalid,
	m_rready
);
	parameter [31:0] TIMEOUT_CYCLES = 100000000;
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	input wire req_valid;
	output wire req_ready;
	input wire req_write;
	input wire [31:0] req_addr;
	input wire [127:0] req_wdata;
	input wire [15:0] req_wstrb;
	input wire [3:0] req_id;
	output wire rsp_valid;
	input wire rsp_ready;
	output reg rsp_write;
	output reg [3:0] rsp_id;
	output reg [127:0] rsp_rdata;
	output reg rsp_error;
	output wire poisoned;
	output wire [3:0] m_awid;
	output wire [31:0] m_awaddr;
	output wire [7:0] m_awlen;
	output wire [2:0] m_awsize;
	output wire [1:0] m_awburst;
	output wire m_awvalid;
	input wire m_awready;
	output wire [127:0] m_wdata;
	output wire [15:0] m_wstrb;
	output wire m_wlast;
	output wire m_wvalid;
	input wire m_wready;
	input wire [3:0] m_bid;
	input wire [1:0] m_bresp;
	input wire m_bvalid;
	output wire m_bready;
	output wire [3:0] m_arid;
	output wire [31:0] m_araddr;
	output wire [7:0] m_arlen;
	output wire [2:0] m_arsize;
	output wire [1:0] m_arburst;
	output wire m_arvalid;
	input wire m_arready;
	input wire [3:0] m_rid;
	input wire [127:0] m_rdata;
	input wire [1:0] m_rresp;
	input wire m_rlast;
	input wire m_rvalid;
	output wire m_rready;
	reg [2:0] state;
	reg [31:0] addr_q;
	reg [127:0] wdata_q;
	reg [15:0] wstrb_q;
	reg [3:0] id_q;
	reg write_q;
	reg poison_after_rsp;
	reg [31:0] wait_cycles;
	wire waiting = ((((state == 3'd1) || (state == 3'd2)) || (state == 3'd3)) || (state == 3'd4)) || (state == 3'd5);
	wire step = (((((state == 3'd1) && m_awready) || ((state == 3'd2) && m_wready)) || ((state == 3'd3) && m_bvalid)) || ((state == 3'd4) && m_arready)) || ((state == 3'd5) && m_rvalid);
	assign req_ready = ((state == 3'd0) && ddr_ready) && !rst;
	assign rsp_valid = state == 3'd6;
	assign poisoned = (state == 3'd7) || poison_after_rsp;
	assign m_awid = id_q;
	assign m_awaddr = addr_q;
	assign m_awlen = 0;
	assign m_awsize = 3'd4;
	assign m_awburst = 2'b01;
	assign m_awvalid = state == 3'd1;
	assign m_wdata = wdata_q;
	assign m_wstrb = wstrb_q;
	assign m_wlast = 1'b1;
	assign m_wvalid = state == 3'd2;
	assign m_bready = state == 3'd3;
	assign m_arid = id_q;
	assign m_araddr = addr_q;
	assign m_arlen = 0;
	assign m_arsize = 3'd4;
	assign m_arburst = 2'b01;
	assign m_arvalid = state == 3'd4;
	assign m_rready = state == 3'd5;
	always @(posedge clk)
		if (rst) begin
			state <= 3'd0;
			addr_q <= 0;
			wdata_q <= 0;
			wstrb_q <= 0;
			id_q <= 0;
			write_q <= 0;
			rsp_write <= 0;
			rsp_id <= 0;
			rsp_rdata <= 0;
			rsp_error <= 0;
			poison_after_rsp <= 0;
			wait_cycles <= 0;
		end
		else begin
			if (waiting) begin
				if (step)
					wait_cycles <= 0;
				else if (wait_cycles == (TIMEOUT_CYCLES - 1)) begin
					rsp_write <= write_q;
					rsp_id <= id_q;
					rsp_rdata <= 0;
					rsp_error <= 1;
					poison_after_rsp <= 1;
					state <= 3'd6;
				end
				else
					wait_cycles <= wait_cycles + 1'b1;
			end
			else
				wait_cycles <= 0;
			case (state)
				3'd0:
					if (req_valid && req_ready) begin
						addr_q <= req_addr;
						wdata_q <= req_wdata;
						wstrb_q <= req_wstrb;
						id_q <= req_id;
						write_q <= req_write;
						rsp_write <= req_write;
						rsp_id <= req_id;
						rsp_rdata <= 0;
						rsp_error <= 0;
						poison_after_rsp <= 0;
						if ((req_addr[3:0] != 0) || (req_write && (req_wstrb == 0))) begin
							rsp_error <= 1;
							state <= 3'd6;
						end
						else
							state <= (req_write ? 3'd1 : 3'd4);
					end
				3'd1:
					if (m_awready)
						state <= 3'd2;
				3'd2:
					if (m_wready)
						state <= 3'd3;
				3'd3:
					if (m_bvalid) begin
						rsp_write <= 1;
						rsp_id <= m_bid;
						rsp_error <= (m_bresp != 0) || (m_bid != id_q);
						if (m_bid != id_q)
							poison_after_rsp <= 1;
						state <= 3'd6;
					end
				3'd4:
					if (m_arready)
						state <= 3'd5;
				3'd5:
					if (m_rvalid) begin
						rsp_write <= 0;
						rsp_id <= m_rid;
						rsp_rdata <= m_rdata;
						rsp_error <= ((m_rresp != 0) || (m_rid != id_q)) || !m_rlast;
						if ((m_rid != id_q) || !m_rlast)
							poison_after_rsp <= 1;
						state <= 3'd6;
					end
				3'd6:
					if (rsp_ready)
						state <= (poison_after_rsp ? 3'd7 : 3'd0);
				default: state <= 3'd7;
			endcase
			if ((waiting && !step) && (wait_cycles == (TIMEOUT_CYCLES - 1)))
				state <= 3'd6;
		end
endmodule
module soc_window_address_gen (
	clk,
	rst,
	start,
	input_base,
	scratch_base,
	first_row,
	input_h,
	input_w,
	input_c,
	output_h,
	output_w,
	first_oy,
	first_ox,
	kernel_h,
	kernel_w,
	stride_h,
	stride_w,
	dilation_h,
	dilation_w,
	pad_top,
	pad_left,
	pad_bottom,
	pad_right,
	row_count,
	ready,
	busy,
	done_pulse,
	error_sticky,
	out_valid,
	out_ready,
	out_zero,
	out_source_addr,
	out_scratch_addr,
	out_bytes,
	out_last
);
	reg _sv2v_0;
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [31:0] DDR_BYTES = 32'h04000000;
	parameter [0:0] VECTOR16_ENABLE = 1'b1;
	parameter [0:0] RGB6_SPAN_ENABLE = 1'b1;
	parameter [0:0] INCREMENTAL_PIXEL_INDEX = 1'b1;
	input wire clk;
	input wire rst;
	input wire start;
	input wire [31:0] input_base;
	input wire [31:0] scratch_base;
	input wire [31:0] first_row;
	input wire [15:0] input_h;
	input wire [15:0] input_w;
	input wire [15:0] input_c;
	input wire [15:0] output_h;
	input wire [15:0] output_w;
	input wire [15:0] first_oy;
	input wire [15:0] first_ox;
	input wire [7:0] kernel_h;
	input wire [7:0] kernel_w;
	input wire [7:0] stride_h;
	input wire [7:0] stride_w;
	input wire [7:0] dilation_h;
	input wire [7:0] dilation_w;
	input wire [7:0] pad_top;
	input wire [7:0] pad_left;
	input wire [7:0] pad_bottom;
	input wire [7:0] pad_right;
	input wire [15:0] row_count;
	output wire ready;
	output wire busy;
	output reg done_pulse;
	output reg [7:0] error_sticky;
	output wire out_valid;
	input wire out_ready;
	output wire out_zero;
	output wire [31:0] out_source_addr;
	output wire [31:0] out_scratch_addr;
	output wire [4:0] out_bytes;
	output wire out_last;
	wire vector16 = (VECTOR16_ENABLE && (input_c[3:0] == 0)) && (input_base[3:0] == 0);
	wire rgb_span = ((((((((((((((RGB6_SPAN_ENABLE && (input_c == 3)) && (kernel_h == 6)) && (kernel_w == 6)) && (stride_h == 2)) && (stride_w == 2)) && (dilation_h == 1)) && (dilation_w == 1)) && (pad_top == 2)) && (pad_left == 2)) && (pad_bottom == 2)) && (pad_right == 2)) && (input_w[0] == 0)) && (input_h[0] == 0)) && (input_base[3:0] == 0)) && (scratch_base[3:0] == 0);
	reg [4:0] token_bytes;
	reg rgb_channel_end;
	wire signed [32:0] rgb_x_bytes;
	wire [31:0] rgb_row_bytes;
	wire rgb_y_zero;
	function automatic signed [32:0] px_bytes_of;
		input reg [31:0] x;
		reg signed [32:0] d;
		begin
			d = $signed({1'b0, x}) - $signed({25'd0, pad_left});
			px_bytes_of = d + (d <<< 1);
		end
	endfunction
	(* keep = "true" *) reg signed [32:0] px_bytes_q;
	(* keep = "true" *) reg [31:0] rgb_row_bytes_q;
	wire signed [32:0] dilation_w_x3 = ($signed({25'd0, dilation_w}) <<< 1) + $signed({25'd0, dilation_w});
	assign rgb_row_bytes = rgb_row_bytes_q;
	reg [15:0] c_q;
	assign rgb_x_bytes = px_bytes_q + $signed({17'd0, c_q});
	reg [31:0] py_q;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	assign rgb_y_zero = (py_q < pad_top) || ((py_q - sv2v_cast_32(pad_top)) >= sv2v_cast_32(input_h));
	assign out_bytes = token_bytes;
	function automatic [4:0] sat5;
		input reg [31:0] v;
		sat5 = (v[31:5] == 27'd0 ? v[4:0] : 5'd31);
	endfunction
	function automatic [4:0] min5;
		input reg [4:0] a;
		input reg [4:0] b;
		min5 = (a < b ? a : b);
	endfunction
	reg [31:0] emitted_q;
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_1
		reg [4:0] a_cap;
		reg [4:0] a_chan;
		reg [4:0] a_pad;
		reg [4:0] a_row;
		reg [4:0] a_align;
		reg [4:0] a_kernel;
		reg [4:0] m_head;
		reg [4:0] m_tail;
		reg in_row;
		if (_sv2v_0)
			;
		a_cap = (vector16 ? 5'd16 : 5'd1);
		a_chan = 5'd16 - {1'b0, emitted_q[3:0]};
		in_row = (rgb_x_bytes >= 0) && (rgb_x_bytes < $signed({1'b0, rgb_row_bytes}));
		a_align = ((rgb_span && !rgb_y_zero) && in_row ? sat5(32'd16 - {28'd0, out_source_addr[3:0]}) : 5'd31);
		a_row = ((rgb_span && !rgb_y_zero) && in_row ? sat5(rgb_row_bytes - sv2v_cast_32_signed(rgb_x_bytes)) : 5'd31);
		a_pad = ((rgb_span && !rgb_y_zero) && (rgb_x_bytes < 0) ? sat5(sv2v_cast_32_signed(-rgb_x_bytes)) : 5'd31);
		a_kernel = sat5(32'd18 - sv2v_cast_32(c_q));
		m_head = min5(a_chan, a_kernel);
		m_tail = min5(min5(a_pad, a_row), a_align);
		token_bytes = (rgb_span ? min5(m_head, m_tail) : a_cap);
		rgb_channel_end = (((a_kernel <= a_chan) && (a_kernel <= a_pad)) && (a_kernel <= a_row)) && (a_kernel <= a_align);
	end
	reg running;
	reg [15:0] oy_q;
	reg [15:0] ox_q;
	reg [15:0] ky_q;
	reg [15:0] kx_q;
	reg [31:0] oy_base_q;
	reg [31:0] ox_base_q;
	reg [31:0] px_q;
	reg [31:0] total_q;
	reg [31:0] k_count;
	reg [31:0] output_pixels;
	reg [31:0] kernel_extent_h;
	reg [31:0] kernel_extent_w;
	reg [31:0] padded_h;
	reg [31:0] padded_w;
	reg dimension_h_ok;
	reg dimension_w_ok;
	reg [63:0] input_bytes;
	reg [63:0] scratch_bytes;
	reg [63:0] src_end;
	reg [63:0] dst_end;
	wire valid_config;
	wire [31:0] src_y;
	wire [31:0] src_x;
	reg [31:0] pixel_index_q;
	reg [31:0] origin_index_q;
	reg [31:0] kernel_row_step_q;
	reg [31:0] kernel_x_span_q;
	reg [31:0] output_row_step_q;
	reg [31:0] output_x_span_q;
	reg [31:0] ky_delta_q;
	reg [31:0] oy_delta_q;
	reg address_ready_q;
	reg [2:0] validation_q;
	(* keep = "true" *) reg [31:0] input_pixels_q;
	(* keep = "true" *) reg [15:0] kernel_pixels_q;
	(* keep = "true" *) reg valid_config_q;
	(* keep = "true" *) reg [15:0] kernel_h_dilation_q;
	(* keep = "true" *) reg [15:0] kernel_w_dilation_q;
	(* keep = "true" *) reg [63:0] output_h_stride_q;
	(* keep = "true" *) reg [63:0] output_w_stride_q;
	(* keep = "true" *) reg [63:0] last_h_stride_q;
	(* keep = "true" *) reg [63:0] last_w_stride_q;
	(* keep = "true" *) reg [63:0] dimension_h_min_q;
	(* keep = "true" *) reg [63:0] dimension_h_max_q;
	(* keep = "true" *) reg [63:0] dimension_w_min_q;
	(* keep = "true" *) reg [63:0] dimension_w_max_q;
	(* keep = "true" *) reg [31:0] first_row_product_q;
	(* keep = "true" *) reg [31:0] first_row_expected_q;
	(* keep = "true" *) reg [63:0] first_row_limit_q;
	function automatic [63:0] sv2v_cast_64;
		input reg [63:0] inp;
		sv2v_cast_64 = inp;
	endfunction
	assign valid_config = (((((((((((((((((((((((((((input_h != 0) && (input_w != 0)) && (input_c != 0)) && (output_h != 0)) && (output_w != 0)) && (kernel_h != 0)) && (kernel_w != 0)) && (stride_h != 0)) && (stride_w != 0)) && (dilation_h != 0)) && (dilation_w != 0)) && (row_count != 0)) && (row_count <= 16'd64)) && (k_count != 0)) && (k_count <= 32'd65535)) && dimension_h_ok) && dimension_w_ok) && (first_oy < output_h)) && (first_ox < output_w)) && (first_row_expected_q == first_row)) && (first_row < output_pixels)) && (first_row_limit_q <= sv2v_cast_64(output_pixels))) && (input_base >= DDR_BASE)) && (scratch_base >= DDR_BASE)) && (scratch_base[5:0] == 0)) && (src_end <= (sv2v_cast_64(DDR_BASE) + sv2v_cast_64(DDR_BYTES)))) && (dst_end <= (sv2v_cast_64(DDR_BASE) + sv2v_cast_64(DDR_BYTES)))) && ((src_end <= sv2v_cast_64(scratch_base)) || (dst_end <= sv2v_cast_64(input_base)));
	assign ready = (!rst && !running) && (validation_q == 0);
	assign busy = running || (validation_q != 0);
	assign out_valid = running && address_ready_q;
	assign out_zero = (rgb_span ? (rgb_y_zero || (rgb_x_bytes < 0)) || (rgb_x_bytes >= $signed({1'b0, rgb_row_bytes})) : (((py_q < pad_top) || (px_q < pad_left)) || ((py_q - sv2v_cast_32(pad_top)) >= sv2v_cast_32(input_h))) || ((px_q - sv2v_cast_32(pad_left)) >= sv2v_cast_32(input_w)));
	assign src_y = py_q - sv2v_cast_32(pad_top);
	assign src_x = px_q - sv2v_cast_32(pad_left);
	assign out_source_addr = (out_zero ? 32'd0 : (input_base + (pixel_index_q * sv2v_cast_32(input_c))) + sv2v_cast_32(c_q));
	assign out_scratch_addr = scratch_base + emitted_q;
	wire [5:0] last_low_sum = {1'b0, emitted_q[4:0]} + {1'b0, token_bytes};
	wire [26:0] last_high_inc = emitted_q[31:5] + 27'd1;
	wire last_high_match = (last_low_sum[5] ? last_high_inc == total_q[31:5] : emitted_q[31:5] == total_q[31:5]);
	wire last_arithmetic_unknown = ^{emitted_q, token_bytes} ^ ^{emitted_q, token_bytes};
	assign out_last = running && (((last_low_sum[4:0] == total_q[4:0]) && last_high_match) ^ last_arithmetic_unknown);
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	always @(posedge clk) begin
		done_pulse <= 0;
		if (rst) begin
			running <= 0;
			error_sticky <= 0;
			oy_q <= 0;
			ox_q <= 0;
			ky_q <= 0;
			kx_q <= 0;
			c_q <= 0;
			oy_base_q <= 0;
			ox_base_q <= 0;
			py_q <= 0;
			px_q <= 0;
			px_bytes_q <= 0;
			rgb_row_bytes_q <= 0;
			emitted_q <= 0;
			total_q <= 0;
			pixel_index_q <= 0;
			address_ready_q <= 0;
			origin_index_q <= 0;
			kernel_row_step_q <= 0;
			kernel_x_span_q <= 0;
			output_row_step_q <= 0;
			output_x_span_q <= 0;
			ky_delta_q <= 0;
			oy_delta_q <= 0;
			validation_q <= 0;
			input_pixels_q <= 0;
			kernel_pixels_q <= 0;
			input_bytes <= 0;
			k_count <= 0;
			scratch_bytes <= 0;
			valid_config_q <= 0;
			output_pixels <= 0;
			kernel_extent_h <= 0;
			kernel_extent_w <= 0;
			padded_h <= 0;
			padded_w <= 0;
			dimension_h_ok <= 0;
			dimension_w_ok <= 0;
			src_end <= 0;
			dst_end <= 0;
			kernel_h_dilation_q <= 0;
			kernel_w_dilation_q <= 0;
			output_h_stride_q <= 0;
			output_w_stride_q <= 0;
			last_h_stride_q <= 0;
			last_w_stride_q <= 0;
			dimension_h_min_q <= 0;
			dimension_h_max_q <= 0;
			dimension_w_min_q <= 0;
			dimension_w_max_q <= 0;
			first_row_product_q <= 0;
			first_row_expected_q <= 0;
			first_row_limit_q <= 0;
		end
		else begin
			if (running && (!INCREMENTAL_PIXEL_INDEX || !address_ready_q)) begin
				pixel_index_q <= (src_y * sv2v_cast_32(input_w)) + src_x;
				origin_index_q <= (src_y * sv2v_cast_32(input_w)) + src_x;
				address_ready_q <= 1'b1;
			end
			if (start && busy)
				error_sticky[1] <= 1;
			if (start && ready) begin
				error_sticky <= 0;
				validation_q <= 1;
				input_pixels_q <= sv2v_cast_32(input_h) * sv2v_cast_32(input_w);
				kernel_pixels_q <= sv2v_cast_16(kernel_h) * sv2v_cast_16(kernel_w);
				output_pixels <= sv2v_cast_32(output_h) * sv2v_cast_32(output_w);
				padded_h <= (sv2v_cast_32(input_h) + sv2v_cast_32(pad_top)) + sv2v_cast_32(pad_bottom);
				padded_w <= (sv2v_cast_32(input_w) + sv2v_cast_32(pad_left)) + sv2v_cast_32(pad_right);
				kernel_h_dilation_q <= sv2v_cast_16(kernel_h) * sv2v_cast_16(dilation_h);
				kernel_w_dilation_q <= sv2v_cast_16(kernel_w) * sv2v_cast_16(dilation_w);
				output_h_stride_q <= sv2v_cast_64(output_h) * sv2v_cast_64(stride_h);
				output_w_stride_q <= sv2v_cast_64(output_w) * sv2v_cast_64(stride_w);
				first_row_product_q <= sv2v_cast_32(first_oy) * sv2v_cast_32(output_w);
				first_row_limit_q <= sv2v_cast_64(first_row) + sv2v_cast_64(row_count);
				address_ready_q <= 0;
			end
			else if (validation_q != 0)
				case (validation_q)
					1: begin
						kernel_row_step_q <= sv2v_cast_32(input_w) * sv2v_cast_32(dilation_h);
						kernel_x_span_q <= (sv2v_cast_32(kernel_w) - 1) * sv2v_cast_32(dilation_w);
						output_row_step_q <= sv2v_cast_32(input_w) * sv2v_cast_32(stride_h);
						output_x_span_q <= (sv2v_cast_32(output_w) - 1) * sv2v_cast_32(stride_w);
						input_bytes <= sv2v_cast_64(input_pixels_q) * sv2v_cast_64(input_c);
						k_count <= sv2v_cast_32(kernel_pixels_q) * sv2v_cast_32(input_c);
						kernel_extent_h <= (sv2v_cast_32(kernel_h_dilation_q) - sv2v_cast_32(dilation_h)) + 1;
						kernel_extent_w <= (sv2v_cast_32(kernel_w_dilation_q) - sv2v_cast_32(dilation_w)) + 1;
						last_h_stride_q <= output_h_stride_q - sv2v_cast_64(stride_h);
						last_w_stride_q <= output_w_stride_q - sv2v_cast_64(stride_w);
						first_row_expected_q <= first_row_product_q + sv2v_cast_32(first_ox);
						validation_q <= 2;
					end
					2: begin
						ky_delta_q <= kernel_row_step_q - kernel_x_span_q;
						oy_delta_q <= output_row_step_q - output_x_span_q;
						scratch_bytes <= sv2v_cast_64(row_count) * sv2v_cast_64(k_count);
						dimension_h_min_q <= last_h_stride_q + sv2v_cast_64(kernel_extent_h);
						dimension_h_max_q <= output_h_stride_q + sv2v_cast_64(kernel_extent_h);
						dimension_w_min_q <= last_w_stride_q + sv2v_cast_64(kernel_extent_w);
						dimension_w_max_q <= output_w_stride_q + sv2v_cast_64(kernel_extent_w);
						validation_q <= 3;
					end
					3: begin
						src_end <= sv2v_cast_64(input_base) + input_bytes;
						dst_end <= sv2v_cast_64(scratch_base) + scratch_bytes;
						dimension_h_ok <= ((((padded_h >= kernel_extent_h) && (stride_h != 0)) && (output_h != 0)) && (dimension_h_min_q <= sv2v_cast_64(padded_h))) && (dimension_h_max_q > sv2v_cast_64(padded_h));
						dimension_w_ok <= ((((padded_w >= kernel_extent_w) && (stride_w != 0)) && (output_w != 0)) && (dimension_w_min_q <= sv2v_cast_64(padded_w))) && (dimension_w_max_q > sv2v_cast_64(padded_w));
						validation_q <= 4;
					end
					4: begin
						valid_config_q <= valid_config;
						validation_q <= 5;
					end
					5: begin
						validation_q <= 0;
						if (!valid_config_q) begin
							error_sticky[0] <= 1;
							done_pulse <= 1;
						end
						else begin
							running <= 1;
							address_ready_q <= 0;
							oy_q <= first_oy;
							ox_q <= first_ox;
							oy_base_q <= sv2v_cast_32(first_oy) * sv2v_cast_32(stride_h);
							ox_base_q <= sv2v_cast_32(first_ox) * sv2v_cast_32(stride_w);
							py_q <= sv2v_cast_32(first_oy) * sv2v_cast_32(stride_h);
							px_q <= sv2v_cast_32(first_ox) * sv2v_cast_32(stride_w);
							px_bytes_q <= px_bytes_of(sv2v_cast_32(first_ox) * sv2v_cast_32(stride_w));
							rgb_row_bytes_q <= sv2v_cast_32(input_w) * 32'd3;
							ky_q <= 0;
							kx_q <= 0;
							c_q <= 0;
							emitted_q <= 0;
							total_q <= sv2v_cast_32(scratch_bytes);
						end
					end
					default: begin
						validation_q <= 0;
						error_sticky[0] <= 1;
						done_pulse <= 1;
					end
				endcase
			else if (out_valid && out_ready) begin
				emitted_q <= emitted_q + sv2v_cast_32(token_bytes);
				if (out_last) begin
					running <= 0;
					done_pulse <= 1;
				end
				else if ((rgb_span ? !rgb_channel_end : (c_q + (vector16 ? 16'd16 : 16'd1)) < input_c))
					c_q <= c_q + sv2v_cast_16(token_bytes);
				else begin
					c_q <= 0;
					address_ready_q <= INCREMENTAL_PIXEL_INDEX;
					if (!rgb_span && ((kx_q + 1) < kernel_w)) begin
						if (INCREMENTAL_PIXEL_INDEX)
							pixel_index_q <= pixel_index_q + sv2v_cast_32(dilation_w);
						kx_q <= kx_q + 1;
						px_q <= px_q + sv2v_cast_32(dilation_w);
						px_bytes_q <= px_bytes_q + dilation_w_x3;
					end
					else begin
						kx_q <= 0;
						px_q <= ox_base_q;
						px_bytes_q <= px_bytes_of(ox_base_q);
						if ((ky_q + 1) < kernel_h) begin
							if (INCREMENTAL_PIXEL_INDEX)
								pixel_index_q <= pixel_index_q + (rgb_span ? kernel_row_step_q : ky_delta_q);
							ky_q <= ky_q + 1;
							py_q <= py_q + sv2v_cast_32(dilation_h);
						end
						else begin
							ky_q <= 0;
							if ((ox_q + 1) < output_w) begin
								if (INCREMENTAL_PIXEL_INDEX) begin
									pixel_index_q <= origin_index_q + sv2v_cast_32(stride_w);
									origin_index_q <= origin_index_q + sv2v_cast_32(stride_w);
								end
								ox_q <= ox_q + 1;
								ox_base_q <= ox_base_q + sv2v_cast_32(stride_w);
								px_q <= ox_base_q + sv2v_cast_32(stride_w);
								px_bytes_q <= px_bytes_of(ox_base_q + sv2v_cast_32(stride_w));
								py_q <= oy_base_q;
							end
							else begin
								if (INCREMENTAL_PIXEL_INDEX) begin
									pixel_index_q <= origin_index_q + oy_delta_q;
									origin_index_q <= origin_index_q + oy_delta_q;
								end
								ox_q <= 0;
								oy_q <= oy_q + 1;
								ox_base_q <= 0;
								px_q <= 0;
								px_bytes_q <= px_bytes_of(32'd0);
								oy_base_q <= oy_base_q + sv2v_cast_32(stride_h);
								py_q <= oy_base_q + sv2v_cast_32(stride_h);
							end
						end
					end
				end
			end
		end
	end
	initial if ((DDR_BYTES < 256) || (DDR_BASE[5:0] != 0)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_window_address_gen.sv:333:9 - soc_window_address_gen.<unnamed_block>\n msg: ", $time, "WINDOW_GEN_REGION_PARAMETER");
		$finish(1);
	end
	initial _sv2v_0 = 0;
endmodule
module soc_window_gather_dma (
	clk,
	rst,
	start,
	flush_cache,
	input_base,
	scratch_base,
	first_row,
	input_h,
	input_w,
	input_c,
	output_h,
	output_w,
	first_oy,
	first_ox,
	kernel_h,
	kernel_w,
	stride_h,
	stride_w,
	dilation_h,
	dilation_w,
	pad_top,
	pad_left,
	pad_bottom,
	pad_right,
	row_count,
	ready,
	busy,
	done_pulse,
	partial_output,
	error_sticky,
	source_read_bytes,
	scratch_write_bytes,
	cache_hits,
	cache_misses,
	active_cycles,
	stall_cycles,
	dma_req_valid,
	dma_req_ready,
	dma_req_write,
	dma_req_addr,
	dma_req_wdata,
	dma_req_wstrb,
	dma_req_id,
	dma_req_len,
	dma_rsp_last,
	dma_rsp_valid,
	dma_rsp_ready,
	dma_rsp_write,
	dma_rsp_id,
	dma_rsp_rdata,
	dma_rsp_error
);
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [31:0] DDR_BYTES = 32'h04000000;
	parameter [0:0] VECTOR16_ENABLE = 1'b1;
	parameter [0:0] RGB6_SPAN_ENABLE = 1'b1;
	parameter [0:0] EARLY_CACHE_LOOKUP = 1'b1;
	parameter [0:0] WRITE_BURST_ENABLE = 1'b0;
	parameter [0:0] CACHE_FILL_BURST_ENABLE = 1'b1;
	parameter [0:0] VECTOR_DIRECT_ENABLE = 1'b1;
	parameter [0:0] RGB_SPAN_PACK_ENABLE = 1'b1;
	parameter [0:0] INCREMENTAL_ADDR_ENABLE = 1'b1;
	input wire clk;
	input wire rst;
	input wire start;
	input wire flush_cache;
	input wire [31:0] input_base;
	input wire [31:0] scratch_base;
	input wire [31:0] first_row;
	input wire [15:0] input_h;
	input wire [15:0] input_w;
	input wire [15:0] input_c;
	input wire [15:0] output_h;
	input wire [15:0] output_w;
	input wire [15:0] first_oy;
	input wire [15:0] first_ox;
	input wire [7:0] kernel_h;
	input wire [7:0] kernel_w;
	input wire [7:0] stride_h;
	input wire [7:0] stride_w;
	input wire [7:0] dilation_h;
	input wire [7:0] dilation_w;
	input wire [7:0] pad_top;
	input wire [7:0] pad_left;
	input wire [7:0] pad_bottom;
	input wire [7:0] pad_right;
	input wire [15:0] row_count;
	output wire ready;
	output wire busy;
	output reg done_pulse;
	output reg partial_output;
	output reg [7:0] error_sticky;
	output reg [31:0] source_read_bytes;
	output reg [31:0] scratch_write_bytes;
	output reg [31:0] cache_hits;
	output reg [31:0] cache_misses;
	output reg [31:0] active_cycles;
	output reg [31:0] stall_cycles;
	output wire dma_req_valid;
	input wire dma_req_ready;
	output wire dma_req_write;
	output wire [31:0] dma_req_addr;
	output wire [127:0] dma_req_wdata;
	output wire [15:0] dma_req_wstrb;
	output wire [3:0] dma_req_id;
	output wire [3:0] dma_req_len;
	input wire dma_rsp_last;
	input wire dma_rsp_valid;
	output wire dma_rsp_ready;
	input wire dma_rsp_write;
	input wire [3:0] dma_rsp_id;
	input wire [127:0] dma_rsp_rdata;
	input wire dma_rsp_error;
	wire line_fill = WRITE_BURST_ENABLE && CACHE_FILL_BURST_ENABLE;
	wire vector16 = (VECTOR16_ENABLE && (input_c[3:0] == 0)) && (input_base[3:0] == 0);
	wire direct_vector = (WRITE_BURST_ENABLE && VECTOR_DIRECT_ENABLE) && vector16;
	reg [31:0] source_low_q;
	reg [31:0] source_high_q;
	reg [31:0] fill_base_q;
	reg [31:0] fill_addr_q;
	reg [2:0] fill_words_q;
	reg [31:0] source_addr_q;
	wire [31:0] line64_start = {source_addr_q[31:6], 6'b000000};
	wire [31:0] refill_start = (line64_start < source_low_q ? source_low_q : line64_start);
	wire [31:0] refill_end = ((line64_start + 32'd64) > source_high_q ? source_high_q : line64_start + 32'd64);
	reg [17:0] cache_tag_q;
	reg cache_valid_q;
	wire [17:0] source_tag;
	wire cache_hit = cache_valid_q && (cache_tag_q == source_tag);
	localparam [3:0] TAG = 4'h1;
	wire read_ok = ((dma_rsp_valid && !dma_rsp_write) && (dma_rsp_id == TAG)) && !dma_rsp_error;
	wire read_last = !line_fill || dma_rsp_last;
	wire [31:0] cache_line_addr;
	reg [127:0] cache_word_q;
	wire [127:0] fetched_word = (fill_addr_q == cache_line_addr ? dma_rsp_rdata : cache_word_q);
	reg [31:0] emitted_q;
	reg [31:0] gen_scratch;
	reg gen_valid;
	reg gen_zero;
	reg [3:0] state;
	wire vector_commit = (direct_vector && gen_valid) && (((((state == 4'd3) && gen_zero) && (gen_scratch == (scratch_base + emitted_q))) || ((state == 4'd5) && cache_hit)) || (((state == 4'd7) && read_ok) && read_last));
	wire rgb_span = ((((((((((((((RGB6_SPAN_ENABLE && (input_c == 3)) && (kernel_h == 6)) && (kernel_w == 6)) && (stride_h == 2)) && (stride_w == 2)) && (dilation_h == 1)) && (dilation_w == 1)) && (pad_top == 2)) && (pad_left == 2)) && (pad_bottom == 2)) && (pad_right == 2)) && (input_w[0] == 0)) && (input_h[0] == 0)) && (input_base[3:0] == 0)) && (scratch_base[3:0] == 0);
	wire span_active = vector16 || rgb_span;
	wire rgb_direct = (WRITE_BURST_ENABLE && RGB_SPAN_PACK_ENABLE) && rgb_span;
	wire rgb_commit = (rgb_direct && gen_valid) && (((((state == 4'd3) && gen_zero) && (gen_scratch == (scratch_base + emitted_q))) || ((state == 4'd5) && cache_hit)) || (((state == 4'd7) && read_ok) && read_last));
	reg [4:0] gen_bytes;
	reg [3:0] write_lane;
	wire [4:0] next_write_count = {1'b0, write_lane} + gen_bytes;
	wire [2:0] rotate_pairs = source_addr_q[3:1] - write_lane[3:1];
	wire [255:0] doubled_cache_word = {cache_word_q, cache_word_q};
	reg [127:0] rotated_word_q;
	localparam signed [31:0] CACHE_LINES = 1024;
	(* ram_style = "block", syn_ramstyle = "block_ram" *) reg [127:0] cache_data [0:1023];
	(* ram_style = "block", syn_ramstyle = "block_ram" *) reg [17:0] cache_tag [0:1023];
	reg cache_valid [0:1023];
	reg [9:0] clear_index;
	reg clear_launch_q;
	reg cache_layer_ok_q;
	reg [31:0] write_addr_q;
	reg [7:0] byte_q;
	reg [127:0] write_buffer;
	reg [15:0] write_strobe_q;
	reg [4:0] write_count_q;
	reg write_last_q;
	reg [127:0] burst_words [0:15];
	reg [15:0] burst_masks [0:15];
	reg [3:0] queued_words;
	reg [3:0] send_word;
	reg [4:0] burst_count;
	reg [8:0] queued_bytes;
	reg [8:0] burst_bytes;
	reg [31:0] burst_base;
	reg burst_last;
	reg [127:0] burst_data_q;
	reg [15:0] burst_mask_q;
	wire gen_ready;
	wire gen_busy;
	wire gen_done;
	reg gen_last;
	wire agen_valid;
	wire agen_ready;
	wire agen_zero;
	wire agen_last;
	wire [31:0] agen_source;
	wire [31:0] agen_scratch;
	wire [4:0] agen_bytes;
	reg gen_reset_q;
	wire [7:0] gen_error;
	reg [31:0] gen_source;
	wire gen_out_ready;
	wire [9:0] cache_index;
	assign ready = (!rst && (state == 4'd0)) && gen_ready;
	assign busy = state != 4'd0;
	assign cache_line_addr = {source_addr_q[31:4], 4'b0000};
	assign cache_index = source_addr_q[13:4];
	assign source_tag = source_addr_q[31:14];
	assign gen_out_ready = ((state == 4'd8) || vector_commit) || rgb_commit;
	assign dma_req_valid = ((state == 4'd6) || (state == 4'd9)) || (state == 4'd14);
	assign dma_req_write = (state == 4'd9) || (state == 4'd14);
	assign dma_req_addr = (state == 4'd14 ? burst_base + {24'd0, send_word, 4'd0} : (state == 4'd9 ? write_addr_q : (line_fill ? fill_base_q : cache_line_addr)));
	assign dma_req_wdata = (state == 4'd14 ? burst_data_q : write_buffer);
	assign dma_req_wstrb = (state == 4'd14 ? burst_mask_q : (state == 4'd9 ? write_strobe_q : 16'd0));
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	assign dma_req_len = ((state == 4'd6) && line_fill ? sv2v_cast_4(fill_words_q - 1'b1) : ((state == 4'd14) && (send_word == 0) ? sv2v_cast_4(burst_count - 1'b1) : 4'd0));
	assign dma_req_id = TAG;
	assign dma_rsp_ready = (state == 4'd7) || (state == 4'd10);
	soc_window_address_gen #(
		.DDR_BASE(DDR_BASE),
		.DDR_BYTES(DDR_BYTES),
		.VECTOR16_ENABLE(VECTOR16_ENABLE),
		.RGB6_SPAN_ENABLE(RGB6_SPAN_ENABLE),
		.INCREMENTAL_PIXEL_INDEX(INCREMENTAL_ADDR_ENABLE)
	) address_gen(
		.clk(clk),
		.rst(rst || gen_reset_q),
		.start(state == 4'd2),
		.input_base(input_base),
		.scratch_base(scratch_base),
		.first_row(first_row),
		.input_h(input_h),
		.input_w(input_w),
		.input_c(input_c),
		.output_h(output_h),
		.output_w(output_w),
		.first_oy(first_oy),
		.first_ox(first_ox),
		.kernel_h(kernel_h),
		.kernel_w(kernel_w),
		.stride_h(stride_h),
		.stride_w(stride_w),
		.dilation_h(dilation_h),
		.dilation_w(dilation_w),
		.pad_top(pad_top),
		.pad_left(pad_left),
		.pad_bottom(pad_bottom),
		.pad_right(pad_right),
		.row_count(row_count),
		.ready(gen_ready),
		.busy(gen_busy),
		.done_pulse(gen_done),
		.error_sticky(gen_error),
		.out_valid(agen_valid),
		.out_ready(agen_ready),
		.out_zero(agen_zero),
		.out_source_addr(agen_source),
		.out_scratch_addr(agen_scratch),
		.out_bytes(agen_bytes),
		.out_last(agen_last)
	);
	assign agen_ready = !gen_valid || gen_out_ready;
	always @(posedge clk)
		if (rst || gen_reset_q) begin
			gen_valid <= 1'b0;
			gen_zero <= 1'b0;
			gen_last <= 1'b0;
			gen_source <= 0;
			gen_scratch <= 0;
			gen_bytes <= 0;
		end
		else if (agen_ready) begin
			gen_valid <= agen_valid;
			if (agen_valid) begin
				gen_zero <= agen_zero;
				gen_last <= agen_last;
				gen_source <= agen_source;
				gen_scratch <= agen_scratch;
				gen_bytes <= agen_bytes;
			end
		end
	task automatic enqueue_vector;
		input reg [127:0] data;
		begin
			burst_words[queued_words] <= data;
			burst_masks[queued_words] <= 16'hffff;
			if (queued_words == 0)
				burst_base <= gen_scratch;
			queued_bytes <= queued_bytes + 9'd16;
			emitted_q <= emitted_q + 32'd16;
			if (((queued_words == 15) || gen_last) || (gen_scratch[11:4] == 8'hff)) begin
				burst_count <= {1'b0, queued_words} + 5'd1;
				burst_bytes <= queued_bytes + 9'd16;
				burst_last <= gen_last;
				send_word <= 0;
				state <= 4'd13;
			end
			else begin
				queued_words <= queued_words + 1'b1;
				state <= 4'd3;
			end
		end
	endtask
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	task automatic collect_rgb;
		input reg [127:0] data;
		input reg zero;
		reg [255:0] doubled;
		reg [127:0] rotated;
		reg [127:0] merged;
		reg [15:0] mask;
		begin
			doubled = {data, data};
			rotated = doubled[16 * rotate_pairs+:128];
			merged = write_buffer;
			begin : sv2v_autoblock_1
				integer lane;
				for (lane = 0; lane < 8; lane = lane + 1)
					if ((sv2v_cast_5_signed(lane * 2) >= {1'b0, write_lane}) && (sv2v_cast_5_signed(lane * 2) < next_write_count))
						merged[lane * 16+:16] = (zero ? 16'd0 : rotated[lane * 16+:16]);
			end
			emitted_q <= emitted_q + sv2v_cast_32(gen_bytes);
			if ((next_write_count == 16) || gen_last) begin
				mask = 16'hffff >> (5'd16 - next_write_count);
				burst_words[queued_words] <= merged;
				burst_masks[queued_words] <= mask;
				if (queued_words == 0)
					burst_base <= {gen_scratch[31:4], 4'b0000};
				queued_bytes <= queued_bytes + sv2v_cast_9(next_write_count);
				write_buffer <= 0;
				write_lane <= 0;
				if (((queued_words == 15) || gen_last) || (gen_scratch[11:4] == 8'hff)) begin
					burst_count <= {1'b0, queued_words} + 5'd1;
					burst_bytes <= queued_bytes + sv2v_cast_9(next_write_count);
					burst_last <= gen_last;
					send_word <= 0;
					state <= 4'd13;
				end
				else begin
					queued_words <= queued_words + 1'b1;
					state <= 4'd3;
				end
			end
			else begin
				write_buffer <= merged;
				write_lane <= next_write_count[3:0];
				state <= 4'd3;
			end
		end
	endtask
	function automatic [2:0] sv2v_cast_3;
		input reg [2:0] inp;
		sv2v_cast_3 = inp;
	endfunction
	always @(posedge clk) begin
		done_pulse <= 1'b0;
		if (rst) begin
			state <= 4'd1;
			clear_index <= 0;
			clear_launch_q <= 0;
			source_low_q <= 0;
			source_high_q <= 0;
			fill_base_q <= 0;
			fill_addr_q <= 0;
			fill_words_q <= 1;
			cache_layer_ok_q <= 0;
			gen_reset_q <= 0;
			error_sticky <= 0;
			partial_output <= 0;
			source_read_bytes <= 0;
			scratch_write_bytes <= 0;
			cache_hits <= 0;
			cache_misses <= 0;
			active_cycles <= 0;
			stall_cycles <= 0;
			cache_word_q <= 0;
			cache_tag_q <= 0;
			cache_valid_q <= 0;
			source_addr_q <= 0;
			write_addr_q <= 0;
			emitted_q <= 0;
			byte_q <= 0;
			write_buffer <= 0;
			write_strobe_q <= 0;
			write_count_q <= 0;
			write_lane <= 0;
			write_last_q <= 0;
			queued_words <= 0;
			send_word <= 0;
			burst_count <= 0;
			queued_bytes <= 0;
			burst_bytes <= 0;
			burst_base <= 0;
			burst_last <= 0;
			burst_data_q <= 0;
			burst_mask_q <= 0;
		end
		else begin
			gen_reset_q <= 0;
			if (start && !ready)
				error_sticky[4] <= 1'b1;
			if ((state != 4'd0) && (state != 4'd1))
				active_cycles <= active_cycles + 1'b1;
			if (((((state == 4'd6) || (state == 4'd9)) || (state == 4'd14)) && !dma_req_ready) || (((state == 4'd7) || (state == 4'd10)) && !dma_rsp_valid))
				stall_cycles <= stall_cycles + 1'b1;
			case (state)
				4'd0:
					if (start && ready) begin
						source_low_q <= {input_base[31:4], 4'b0000};
						source_high_q <= ((input_base + ((sv2v_cast_32(input_h) * sv2v_cast_32(input_w)) * sv2v_cast_32(input_c))) + 32'd15) & 32'hfffffff0;
						error_sticky <= 0;
						partial_output <= 0;
						source_read_bytes <= 0;
						scratch_write_bytes <= 0;
						cache_hits <= 0;
						cache_misses <= 0;
						active_cycles <= 0;
						stall_cycles <= 0;
						source_addr_q <= 0;
						write_addr_q <= 0;
						emitted_q <= 0;
						write_buffer <= 0;
						write_strobe_q <= 0;
						write_count_q <= 0;
						write_lane <= 0;
						write_last_q <= 0;
						queued_words <= 0;
						send_word <= 0;
						burst_count <= 0;
						queued_bytes <= 0;
						burst_bytes <= 0;
						burst_base <= 0;
						burst_last <= 0;
						burst_data_q <= 0;
						burst_mask_q <= 0;
						if (!flush_cache && !cache_layer_ok_q) begin
							error_sticky[5] <= 1'b1;
							done_pulse <= 1'b1;
						end
						else if (flush_cache) begin
							clear_index <= 0;
							clear_launch_q <= 1'b1;
							state <= 4'd1;
							cache_layer_ok_q <= 1'b1;
						end
						else
							state <= 4'd2;
					end
				4'd1: begin
					cache_valid[clear_index] <= 1'b0;
					clear_index <= clear_index + 1'b1;
					if (clear_index == 10'd1023)
						state <= (clear_launch_q ? 4'd2 : 4'd0);
				end
				4'd2: state <= 4'd3;
				4'd3:
					if (gen_done && (gen_error != 0)) begin
						error_sticky[0] <= 1'b1;
						done_pulse <= 1'b1;
						cache_layer_ok_q <= 0;
						state <= 4'd0;
					end
					else if (gen_valid) begin
						if (gen_scratch != (scratch_base + emitted_q)) begin
							error_sticky[3] <= 1'b1;
							done_pulse <= 1'b1;
							cache_layer_ok_q <= 0;
							gen_reset_q <= 1'b1;
							state <= 4'd0;
						end
						else if (gen_zero) begin
							byte_q <= 0;
							if (span_active)
								cache_word_q <= 0;
							if (direct_vector)
								enqueue_vector(128'd0);
							else if (rgb_direct)
								collect_rgb(128'd0, 1'b1);
							else
								state <= 4'd8;
						end
						else begin
							source_addr_q <= gen_source;
							if (EARLY_CACHE_LOOKUP) begin
								cache_word_q <= cache_data[gen_source[13:4]];
								cache_tag_q <= cache_tag[gen_source[13:4]];
								cache_valid_q <= cache_valid[gen_source[13:4]];
								state <= 4'd5;
							end
							else
								state <= 4'd4;
						end
					end
				4'd4: begin
					cache_word_q <= cache_data[cache_index];
					cache_tag_q <= cache_tag[cache_index];
					cache_valid_q <= cache_valid[cache_index];
					state <= 4'd5;
				end
				4'd5:
					if (cache_valid_q && (cache_tag_q == source_tag)) begin
						byte_q <= cache_word_q[8 * source_addr_q[3:0]+:8];
						cache_hits <= cache_hits + 1'b1;
						if (direct_vector)
							enqueue_vector(cache_word_q);
						else if (rgb_direct)
							collect_rgb(cache_word_q, 1'b0);
						else
							state <= (rgb_span ? 4'd11 : 4'd8);
					end
					else begin
						fill_base_q <= (line_fill ? refill_start : cache_line_addr);
						fill_addr_q <= (line_fill ? refill_start : cache_line_addr);
						fill_words_q <= (line_fill ? sv2v_cast_3((refill_end - refill_start) >> 4) : 3'd1);
						cache_misses <= cache_misses + 1'b1;
						state <= 4'd6;
					end
				4'd6:
					if (dma_req_ready)
						state <= 4'd7;
				4'd7:
					if (dma_rsp_valid) begin
						if ((dma_rsp_write || (dma_rsp_id != TAG)) || dma_rsp_error) begin
							error_sticky[1] <= 1'b1;
							done_pulse <= 1'b1;
							cache_layer_ok_q <= 0;
							gen_reset_q <= 1'b1;
							state <= 4'd0;
						end
						else begin
							cache_data[fill_addr_q[13:4]] <= dma_rsp_rdata;
							cache_tag[fill_addr_q[13:4]] <= fill_addr_q[31:14];
							cache_valid[fill_addr_q[13:4]] <= 1'b1;
							if (fill_addr_q == cache_line_addr) begin
								byte_q <= dma_rsp_rdata[8 * source_addr_q[3:0]+:8];
								if (span_active)
									cache_word_q <= dma_rsp_rdata;
							end
							source_read_bytes <= source_read_bytes + 32'd16;
							fill_addr_q <= fill_addr_q + 32'd16;
							if (read_last) begin
								if (direct_vector)
									enqueue_vector(fetched_word);
								else if (rgb_direct)
									collect_rgb(fetched_word, 1'b0);
								else
									state <= (rgb_span ? 4'd11 : 4'd8);
							end
						end
					end
				4'd11: begin
					rotated_word_q <= doubled_cache_word[16 * rotate_pairs+:128];
					state <= 4'd8;
				end
				4'd8:
					if (gen_valid) begin
						if (span_active) begin
							begin : sv2v_autoblock_2
								integer lane;
								for (lane = 0; lane < 8; lane = lane + 1)
									if ((sv2v_cast_5_signed(lane * 2) >= {1'b0, write_lane}) && (sv2v_cast_5_signed(lane * 2) < next_write_count))
										write_buffer[lane * 16+:16] <= (gen_zero ? 16'd0 : (vector16 ? cache_word_q[lane * 16+:16] : rotated_word_q[lane * 16+:16]));
							end
							emitted_q <= emitted_q + sv2v_cast_32(gen_bytes);
							if ((next_write_count == 16) || gen_last) begin
								write_addr_q <= {gen_scratch[31:4], 4'b0000};
								write_strobe_q <= 16'hffff >> (5'd16 - next_write_count);
								write_count_q <= next_write_count;
								write_last_q <= gen_last;
								state <= (WRITE_BURST_ENABLE ? 4'd12 : 4'd9);
							end
							else begin
								write_lane <= next_write_count[3:0];
								state <= 4'd3;
							end
						end
						else begin
							write_buffer[8 * write_lane+:8] <= byte_q;
							emitted_q <= emitted_q + 1'b1;
							if ((write_lane == 4'd15) || gen_last) begin
								write_addr_q <= {gen_scratch[31:4], 4'b0000};
								write_strobe_q <= 16'hffff >> (15 - write_lane);
								write_count_q <= {1'b0, write_lane} + 5'd1;
								write_last_q <= gen_last;
								state <= (WRITE_BURST_ENABLE ? 4'd12 : 4'd9);
							end
							else begin
								write_lane <= write_lane + 1'b1;
								state <= 4'd3;
							end
						end
					end
				4'd12: begin
					burst_words[queued_words] <= write_buffer;
					burst_masks[queued_words] <= write_strobe_q;
					if (queued_words == 0)
						burst_base <= write_addr_q;
					queued_bytes <= queued_bytes + sv2v_cast_9(write_count_q);
					if (((queued_words == 15) || write_last_q) || (write_addr_q[11:4] == 8'hff)) begin
						burst_count <= {1'b0, queued_words} + 5'd1;
						burst_bytes <= queued_bytes + sv2v_cast_9(write_count_q);
						burst_last <= write_last_q;
						send_word <= 0;
						state <= 4'd13;
					end
					else begin
						queued_words <= queued_words + 1'b1;
						write_buffer <= 0;
						write_lane <= 0;
						state <= 4'd3;
					end
				end
				4'd13: begin
					burst_data_q <= burst_words[0];
					burst_mask_q <= burst_masks[0];
					state <= 4'd14;
				end
				4'd14:
					if (dma_req_ready) begin
						partial_output <= 1'b1;
						if (({1'b0, send_word} + 5'd1) == burst_count)
							state <= 4'd10;
						else begin
							send_word <= send_word + 1'b1;
							burst_data_q <= burst_words[send_word + 4'd1];
							burst_mask_q <= burst_masks[send_word + 4'd1];
						end
					end
				4'd9:
					if (dma_req_ready) begin
						partial_output <= 1'b1;
						state <= 4'd10;
					end
				4'd10:
					if (dma_rsp_valid) begin
						if ((!dma_rsp_write || (dma_rsp_id != TAG)) || dma_rsp_error) begin
							error_sticky[2] <= 1'b1;
							done_pulse <= 1'b1;
							cache_layer_ok_q <= 0;
							gen_reset_q <= 1'b1;
							state <= 4'd0;
						end
						else begin
							scratch_write_bytes <= scratch_write_bytes + (WRITE_BURST_ENABLE ? {23'd0, burst_bytes} : {27'd0, write_count_q});
							queued_words <= 0;
							queued_bytes <= 0;
							write_buffer <= 0;
							write_lane <= 0;
							if ((WRITE_BURST_ENABLE ? burst_last : write_last_q)) begin
								done_pulse <= 1'b1;
								state <= 4'd0;
							end
							else
								state <= 4'd3;
						end
					end
				default: begin
					error_sticky[7] <= 1'b1;
					done_pulse <= 1'b1;
					cache_layer_ok_q <= 0;
					gen_reset_q <= 1'b1;
					state <= 4'd0;
				end
			endcase
		end
	end
endmodule
module soc_window_mmio_mem (
	clk,
	rst,
	ddr_ready,
	axi_poisoned,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	engine_start,
	engine_ready,
	engine_done,
	engine_error,
	engine_partial,
	engine_read_bytes,
	engine_write_bytes,
	engine_cache_hits,
	engine_cache_misses,
	engine_active_cycles,
	engine_stall_cycles,
	input_base,
	scratch_base,
	first_row,
	input_h,
	input_w,
	input_c,
	output_h,
	output_w,
	first_oy,
	first_ox,
	row_count,
	kernel_h,
	kernel_w,
	stride_h,
	stride_w,
	dilation_h,
	dilation_w,
	pad_top,
	pad_left,
	pad_bottom,
	pad_right,
	flush_cache
);
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	input wire axi_poisoned;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output reg engine_start;
	input wire engine_ready;
	input wire engine_done;
	input wire [7:0] engine_error;
	input wire engine_partial;
	input wire [31:0] engine_read_bytes;
	input wire [31:0] engine_write_bytes;
	input wire [31:0] engine_cache_hits;
	input wire [31:0] engine_cache_misses;
	input wire [31:0] engine_active_cycles;
	input wire [31:0] engine_stall_cycles;
	output reg [31:0] input_base;
	output reg [31:0] scratch_base;
	output reg [31:0] first_row;
	output reg [15:0] input_h;
	output reg [15:0] input_w;
	output reg [15:0] input_c;
	output reg [15:0] output_h;
	output reg [15:0] output_w;
	output reg [15:0] first_oy;
	output reg [15:0] first_ox;
	output reg [15:0] row_count;
	output reg [7:0] kernel_h;
	output reg [7:0] kernel_w;
	output reg [7:0] stride_h;
	output reg [7:0] stride_w;
	output reg [7:0] dilation_h;
	output reg [7:0] dilation_w;
	output reg [7:0] pad_top;
	output reg [7:0] pad_left;
	output reg [7:0] pad_bottom;
	output reg [7:0] pad_right;
	output wire flush_cache;
	localparam [31:0] ID = 32'h314e4957;
	reg busy_q;
	reg done_q;
	reg rejected_q;
	reg partial_q;
	reg [7:0] error_q;
	reg [31:0] flags_q;
	wire hit = ((req_addr >= 16'h0300) && (req_addr <= 16'h034c)) && (req_addr[1:0] == 0);
	assign req_ready = !rst && !rsp_valid;
	assign flush_cache = flags_q[0];
	always @(posedge clk) begin
		engine_start <= 0;
		if (rst) begin
			rsp_valid <= 0;
			rsp_rdata <= 0;
			rsp_error <= 0;
			busy_q <= 0;
			done_q <= 0;
			rejected_q <= 0;
			partial_q <= 0;
			error_q <= 0;
			input_base <= 0;
			scratch_base <= 0;
			first_row <= 0;
			input_h <= 0;
			input_w <= 0;
			input_c <= 0;
			output_h <= 0;
			output_w <= 0;
			first_oy <= 0;
			first_ox <= 0;
			row_count <= 0;
			kernel_h <= 0;
			kernel_w <= 0;
			stride_h <= 0;
			stride_w <= 0;
			dilation_h <= 0;
			dilation_w <= 0;
			pad_top <= 0;
			pad_left <= 0;
			pad_bottom <= 0;
			pad_right <= 0;
			flags_q <= 0;
		end
		else begin
			if (engine_done) begin
				busy_q <= 0;
				done_q <= 1;
				error_q <= engine_error;
				partial_q <= engine_partial;
			end
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			if (req_valid && req_ready) begin
				rsp_valid <= 1;
				rsp_rdata <= 0;
				rsp_error <= 0;
				if (!hit || (req_write && (req_wstrb != 4'hf))) begin
					rsp_error <= 1;
					rejected_q <= 1;
				end
				else if (req_write) begin
					if (busy_q) begin
						rsp_error <= 1;
						rejected_q <= 1;
					end
					else
						case (req_addr)
							16'h0300:
								if ((((req_wdata != 1) || !engine_ready) || !ddr_ready) || axi_poisoned) begin
									rsp_error <= 1;
									rejected_q <= 1;
								end
								else begin
									engine_start <= 1;
									busy_q <= 1;
									done_q <= 0;
									rejected_q <= 0;
									partial_q <= 0;
									error_q <= 0;
								end
							16'h0304: input_base <= req_wdata;
							16'h0308: scratch_base <= req_wdata;
							16'h030c: first_row <= req_wdata;
							16'h0310: {input_w, input_h} <= req_wdata;
							16'h0314: {output_h, input_c} <= req_wdata;
							16'h0318: {first_oy, output_w} <= req_wdata;
							16'h031c: {row_count, first_ox} <= req_wdata;
							16'h0320: {stride_w, stride_h, kernel_w, kernel_h} <= req_wdata;
							16'h0324: {pad_left, pad_top, dilation_w, dilation_h} <= req_wdata;
							16'h0328:
								if (req_wdata[31:16] != 0) begin
									rsp_error <= 1;
									rejected_q <= 1;
								end
								else
									{pad_right, pad_bottom} <= req_wdata[15:0];
							16'h032c:
								if (req_wdata[31:1] != 0) begin
									rsp_error <= 1;
									rejected_q <= 1;
								end
								else
									flags_q <= req_wdata;
							16'h0330:
								if (req_wdata == 1) begin
									done_q <= 0;
									rejected_q <= 0;
									partial_q <= 0;
									error_q <= 0;
								end
								else begin
									rsp_error <= 1;
									rejected_q <= 1;
								end
							default: begin
								rsp_error <= 1;
								rejected_q <= 1;
							end
						endcase
				end
				else
					case (req_addr)
						16'h0300: rsp_rdata <= 0;
						16'h0304: rsp_rdata <= input_base;
						16'h0308: rsp_rdata <= scratch_base;
						16'h030c: rsp_rdata <= first_row;
						16'h0310: rsp_rdata <= {input_w, input_h};
						16'h0314: rsp_rdata <= {output_h, input_c};
						16'h0318: rsp_rdata <= {first_oy, output_w};
						16'h031c: rsp_rdata <= {row_count, first_ox};
						16'h0320: rsp_rdata <= {stride_w, stride_h, kernel_w, kernel_h};
						16'h0324: rsp_rdata <= {pad_left, pad_top, dilation_w, dilation_h};
						16'h0328: rsp_rdata <= {16'd0, pad_right, pad_bottom};
						16'h032c: rsp_rdata <= flags_q;
						16'h0330: rsp_rdata <= {14'd0, engine_ready, axi_poisoned, ddr_ready, rejected_q, partial_q, error_q, 3'd0, done_q, busy_q};
						16'h0334: rsp_rdata <= engine_read_bytes;
						16'h0338: rsp_rdata <= engine_write_bytes;
						16'h033c: rsp_rdata <= engine_cache_hits;
						16'h0340: rsp_rdata <= engine_cache_misses;
						16'h0344: rsp_rdata <= engine_active_cycles;
						16'h0348: rsp_rdata <= engine_stall_cycles;
						16'h034c: rsp_rdata <= ID;
						default: begin
							rsp_error <= 1;
							rejected_q <= 1;
						end
					endcase
			end
		end
	end
endmodule
module soc_native_2m_arbiter (
	clk,
	rst,
	s_req_valid,
	s_req_ready,
	s_req_write,
	s_req_addr,
	s_req_wdata,
	s_req_wstrb,
	s_req_id,
	s_req_len,
	s_rsp_valid,
	s_rsp_ready,
	s_rsp_write,
	s_rsp_id,
	s_rsp_rdata,
	s_rsp_error,
	m_req_valid,
	m_req_ready,
	m_req_write,
	m_req_addr,
	m_req_wdata,
	m_req_wstrb,
	m_req_id,
	m_req_len,
	m_rsp_valid,
	m_rsp_last,
	m_rsp_ready,
	s_rsp_last,
	m_rsp_write,
	m_rsp_id,
	m_rsp_rdata,
	m_rsp_error
);
	reg _sv2v_0;
	parameter [0:0] BURST_ENABLE = 1'b0;
	input wire clk;
	input wire rst;
	input wire [1:0] s_req_valid;
	output reg [1:0] s_req_ready;
	input wire [1:0] s_req_write;
	input wire [63:0] s_req_addr;
	input wire [255:0] s_req_wdata;
	input wire [31:0] s_req_wstrb;
	input wire [7:0] s_req_id;
	input wire [7:0] s_req_len;
	output reg [1:0] s_rsp_valid;
	input wire [1:0] s_rsp_ready;
	output reg [1:0] s_rsp_write;
	output reg [7:0] s_rsp_id;
	output reg [255:0] s_rsp_rdata;
	output reg [1:0] s_rsp_error;
	output reg m_req_valid;
	input wire m_req_ready;
	output reg m_req_write;
	output reg [31:0] m_req_addr;
	output reg [127:0] m_req_wdata;
	output reg [15:0] m_req_wstrb;
	output reg [3:0] m_req_id;
	output reg [3:0] m_req_len;
	input wire m_rsp_valid;
	input wire m_rsp_last;
	output reg m_rsp_ready;
	output reg [1:0] s_rsp_last;
	input wire m_rsp_write;
	input wire [3:0] m_rsp_id;
	input wire [127:0] m_rsp_rdata;
	input wire m_rsp_error;
	reg waiting_q;
	reg owner_q;
	reg prefer_q;
	reg chosen;
	reg [3:0] write_remaining;
	reg request_locked_q;
	reg request_owner_q;
	always @(*) begin
		if (_sv2v_0)
			;
		chosen = (request_locked_q ? request_owner_q : prefer_q);
		if ((!request_locked_q && !s_req_valid[prefer_q]) && s_req_valid[!prefer_q])
			chosen = !prefer_q;
	end
	always @(*) begin
		if (_sv2v_0)
			;
		m_req_valid = 0;
		m_req_write = 0;
		m_req_addr = 0;
		m_req_wdata = 0;
		m_req_wstrb = 0;
		m_req_id = 0;
		m_req_len = 0;
		s_req_ready = 1'sb0;
		if (!rst && !waiting_q) begin
			m_req_valid = s_req_valid[chosen];
			m_req_write = s_req_write[chosen];
			m_req_addr = s_req_addr[chosen * 32+:32];
			m_req_wdata = s_req_wdata[chosen * 128+:128];
			m_req_wstrb = s_req_wstrb[chosen * 16+:16];
			m_req_id = s_req_id[chosen * 4+:4];
			m_req_len = (BURST_ENABLE ? s_req_len[chosen * 4+:4] : 4'd0);
			s_req_ready[chosen] = m_req_ready;
		end
		else if ((!rst && waiting_q) && (write_remaining != 0)) begin
			m_req_valid = s_req_valid[owner_q];
			m_req_write = s_req_write[owner_q];
			m_req_addr = s_req_addr[owner_q * 32+:32];
			m_req_wdata = s_req_wdata[owner_q * 128+:128];
			m_req_wstrb = s_req_wstrb[owner_q * 16+:16];
			m_req_id = s_req_id[owner_q * 4+:4];
			m_req_len = s_req_len[owner_q * 4+:4];
			s_req_ready[owner_q] = m_req_ready;
		end
	end
	always @(*) begin
		if (_sv2v_0)
			;
		m_rsp_ready = 0;
		s_rsp_valid = 1'sb0;
		s_rsp_write = 1'sb0;
		s_rsp_last = 1'sb0;
		s_rsp_id = 1'sb0;
		s_rsp_rdata = 1'sb0;
		s_rsp_error = 1'sb0;
		if (!rst && !waiting_q)
			;
		else if (!rst) begin
			s_rsp_valid[owner_q] = m_rsp_valid;
			s_rsp_last[owner_q] = !BURST_ENABLE || m_rsp_last;
			s_rsp_write[owner_q] = m_rsp_write;
			s_rsp_id[owner_q * 4+:4] = m_rsp_id;
			s_rsp_rdata[owner_q * 128+:128] = m_rsp_rdata;
			s_rsp_error[owner_q] = m_rsp_error;
			m_rsp_ready = s_rsp_ready[owner_q];
		end
	end
	always @(posedge clk)
		if (rst) begin
			waiting_q <= 0;
			owner_q <= 0;
			prefer_q <= 0;
			write_remaining <= 0;
			request_locked_q <= 0;
			request_owner_q <= 0;
		end
		else if (!waiting_q) begin
			if (m_req_valid && m_req_ready) begin
				owner_q <= chosen;
				waiting_q <= 1;
				request_locked_q <= 0;
				write_remaining <= (BURST_ENABLE && m_req_write ? m_req_len : 4'd0);
			end
			else if (m_req_valid) begin
				request_locked_q <= 1;
				request_owner_q <= chosen;
			end
		end
		else if (write_remaining != 0) begin
			if (m_req_valid && m_req_ready)
				write_remaining <= write_remaining - 1'b1;
		end
		else if ((m_rsp_valid && m_rsp_ready) && (!BURST_ENABLE || m_rsp_last)) begin
			waiting_q <= 0;
			prefer_q <= !owner_q;
		end
	initial _sv2v_0 = 0;
endmodule
module soc_concat_dma (
	clk,
	rst,
	start,
	cancel,
	operation,
	image_h,
	image_w,
	input_base,
	aux_base,
	output_base,
	pixels,
	input_channels,
	aux_channels,
	ready,
	busy,
	done_pulse,
	partial_output,
	protocol_poison,
	error_sticky,
	read_bytes,
	write_bytes,
	active_cycles,
	stall_cycles,
	dma_req_valid,
	dma_req_ready,
	dma_req_write,
	dma_req_addr,
	dma_req_wdata,
	dma_req_wstrb,
	dma_req_id,
	dma_req_len,
	dma_rsp_last,
	dma_rsp_valid,
	dma_rsp_ready,
	dma_rsp_write,
	dma_rsp_id,
	dma_rsp_rdata,
	dma_rsp_error
);
	reg _sv2v_0;
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [31:0] DDR_BYTES = 32'h04000000;
	parameter [0:0] PIPELINED_POOL = 1'b1;
	parameter [0:0] PARALLEL_POOL = 1'b1;
	parameter [0:0] PAIR_CAT16 = 1'b1;
	parameter [0:0] PAIR_CAT_WIDE = 1'b1;
	parameter [0:0] UP_WRITE_BURST = 1'b1;
	parameter [0:0] OUTPUT_PIPELINE = 1'b1;
	parameter [0:0] UP_EARLY_READ = 1'b1;
	parameter [0:0] READ_BURST_ENABLE = 1'b0;
	parameter [0:0] WRITE_BURST_ENABLE = 1'b0;
	input wire clk;
	input wire rst;
	input wire start;
	input wire cancel;
	input wire [1:0] operation;
	input wire [15:0] image_h;
	input wire [15:0] image_w;
	input wire [31:0] input_base;
	input wire [31:0] aux_base;
	input wire [31:0] output_base;
	input wire [31:0] pixels;
	input wire [15:0] input_channels;
	input wire [15:0] aux_channels;
	output wire ready;
	output wire busy;
	output reg done_pulse;
	output reg partial_output;
	output reg protocol_poison;
	output reg [7:0] error_sticky;
	output reg [31:0] read_bytes;
	output reg [31:0] write_bytes;
	output reg [31:0] active_cycles;
	output reg [31:0] stall_cycles;
	output wire dma_req_valid;
	input wire dma_req_ready;
	output wire dma_req_write;
	output wire [31:0] dma_req_addr;
	output wire [127:0] dma_req_wdata;
	output wire [15:0] dma_req_wstrb;
	output wire [3:0] dma_req_id;
	output reg [3:0] dma_req_len;
	input wire dma_rsp_last;
	input wire dma_rsp_valid;
	output wire dma_rsp_ready;
	input wire dma_rsp_write;
	input wire [3:0] dma_rsp_id;
	input wire [127:0] dma_rsp_rdata;
	input wire dma_rsp_error;
	localparam [1:0] CAT = 0;
	localparam [1:0] ADD = 1;
	localparam [1:0] UP = 2;
	localparam [1:0] POOL = 3;
	localparam [63:0] DDR_LIMIT = {32'd0, DDR_BASE} + {32'd0, DDR_BYTES};
	localparam [7:0] BAD_SHAPE = 1;
	localparam [7:0] BAD_RANGE = 2;
	localparam [7:0] READ_ERROR = 3;
	localparam [7:0] WRITE_ERROR = 4;
	localparam [7:0] BAD_RESPONSE = 5;
	localparam [7:0] CANCELLED = 6;
	localparam [7:0] BAD_OWNER = 7;
	reg [4:0] state;
	reg [2:0] read_kind;
	reg [1:0] mode_q;
	reg [4:0] batch_words;
	reg [4:0] batch_fill;
	reg [4:0] batch_output;
	reg batch_write_live;
	reg stream_head_valid;
	reg stream_ram_valid;
	reg [4:0] stream_issued;
	reg [8:0] stream_base;
	reg [8:0] stream_up_position;
	reg [8:0] stream_up_row;
	reg [8:0] stream_read_address;
	wire stream_fire = ((state == 5'd27) && stream_head_valid) && dma_req_ready;
	reg cancel_q;
	wire abort_now = cancel_q || cancel;
	wire stream_live = (!abort_now || batch_write_live) || stream_head_valid;
	wire stream_move = (((state == 5'd27) && stream_live) && stream_ram_valid) && (!stream_head_valid || stream_fire);
	wire stream_read = (((state == 5'd27) && stream_live) && (stream_issued < batch_words)) && (!stream_ram_valid || stream_move);
	wire stream_nonlast = stream_fire && ((batch_output + 1'b1) < batch_words);
	reg [15:0] aux_c_q;
	reg [31:0] aux_q;
	reg [15:0] in_c_q;
	reg [31:0] in_q;
	reg [31:0] out_q;
	wire paired_cat = (((READ_BURST_ENABLE && WRITE_BURST_ENABLE) && (mode_q == CAT)) && (in_c_q == aux_c_q)) && (((PAIR_CAT16 && (in_c_q == 16)) && (out_q[4:0] == 0)) || (PAIR_CAT_WIDE && (((((in_c_q == 32) && ((in_q[4:0] | aux_q[4:0]) == 0)) && (out_q[5:0] == 0)) || (((in_c_q == 64) && ((in_q[5:0] | aux_q[5:0]) == 0)) && (out_q[6:0] == 0))) || (((in_c_q == 128) && ((in_q[6:0] | aux_q[6:0]) == 0)) && (out_q[7:0] == 0)))));
	wire [1:0] cat_pair_shift = (in_c_q == 32 ? 2'd1 : (in_c_q == 64 ? 2'd2 : (in_c_q == 128 ? 2'd3 : 2'd0)));
	reg [8:0] cat_pair_address;
	wire parallel_pool = ((PARALLEL_POOL && READ_BURST_ENABLE) && WRITE_BURST_ENABLE) && (mode_q == POOL);
	wire burst_up = ((UP_WRITE_BURST && READ_BURST_ENABLE) && WRITE_BURST_ENABLE) && (mode_q == UP);
	wire tensor_batch_mode = READ_BURST_ENABLE && ((mode_q == ADD) || ((mode_q == CAT) && (!((in_c_q == 16) && (aux_c_q == 16)) || paired_cat)));
	wire batch_write_mode = WRITE_BURST_ENABLE && ((tensor_batch_mode || parallel_pool) || burst_up);
	reg [8:0] batch_limit;
	reg [8:0] request_words;
	reg [8:0] boundary_a;
	reg [8:0] boundary_b;
	reg [8:0] pair_pixels;
	wire response_last = !READ_BURST_ENABLE || dma_rsp_last;
	wire batch_a = read_kind == 3'd4;
	wire batch_b = read_kind == 3'd5;
	reg [31:0] aux_cursor;
	reg aux_segment;
	reg [31:0] bytes_left;
	reg [6:0] cache_word;
	reg [31:0] in_cursor;
	reg [31:0] out_cursor;
	reg [31:0] pixels_left;
	reg [15:0] segment_left;
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		boundary_a = 9'd256 - {1'b0, ((mode_q == CAT) && aux_segment ? aux_cursor[11:4] : in_cursor[11:4])};
		boundary_b = 9'd256 - {1'b0, aux_cursor[11:4]};
		batch_limit = 9'd16;
		if (mode_q == CAT) begin
			if ((segment_left >> 4) < 16)
				batch_limit = sv2v_cast_9(segment_left >> 4);
		end
		else if ((bytes_left >> 4) < 16)
			batch_limit = sv2v_cast_9(bytes_left >> 4);
		if (batch_limit > boundary_a)
			batch_limit = boundary_a;
		if ((mode_q == ADD) && (batch_limit > boundary_b))
			batch_limit = boundary_b;
		if (WRITE_BURST_ENABLE && (batch_limit > (9'd256 - {1'b0, out_cursor[11:4]})))
			batch_limit = 9'd256 - {1'b0, out_cursor[11:4]};
		pair_pixels = 9'd8 >> cat_pair_shift;
		if (pixels_left < sv2v_cast_32(pair_pixels))
			pair_pixels = sv2v_cast_9(pixels_left);
		if (pair_pixels > (boundary_a >> cat_pair_shift))
			pair_pixels = boundary_a >> cat_pair_shift;
		if (pair_pixels > (boundary_b >> cat_pair_shift))
			pair_pixels = boundary_b >> cat_pair_shift;
		if (pair_pixels > ((9'd256 - {1'b0, out_cursor[11:4]}) >> ({1'b0, cat_pair_shift} + 3'd1)))
			pair_pixels = (9'd256 - {1'b0, out_cursor[11:4]}) >> ({1'b0, cat_pair_shift} + 3'd1);
		if (paired_cat)
			batch_limit = pair_pixels << ({1'b0, cat_pair_shift} + 3'd1);
		case (cat_pair_shift)
			0: cat_pair_address = {4'd0, batch_output[0], 4'd0} + {6'd0, batch_output[3:1]};
			1: cat_pair_address = {4'd0, batch_output[1], 4'd0} + {6'd0, batch_output[3:2], batch_output[0]};
			2: cat_pair_address = {4'd0, batch_output[2], 4'd0} + {6'd0, batch_output[3], batch_output[1:0]};
			3: cat_pair_address = {4'd0, batch_output[3], 4'd0} + {6'd0, batch_output[2:0]};
		endcase
		request_words = 1;
		if (READ_BURST_ENABLE && (state == 5'd6)) begin
			if (batch_a || batch_b)
				request_words = (paired_cat ? sv2v_cast_9(batch_words) >> 1 : sv2v_cast_9(batch_words));
			else if (read_kind == 3'd3) begin
				request_words = 9'd80 - sv2v_cast_9(cache_word);
				if (request_words > 16)
					request_words = 16;
				if (request_words > (9'd256 - {1'b0, in_cursor[11:4]}))
					request_words = 9'd256 - {1'b0, in_cursor[11:4]};
			end
		end
		dma_req_len = ((((state == 5'd8) || (state == 5'd27)) && batch_write_mode) && (batch_output == 0) ? sv2v_cast_4(batch_words - 1'b1) : sv2v_cast_4(request_words - 1'b1));
	end
	reg [31:0] pixels_q;
	reg [15:0] h_q;
	reg [15:0] w_q;
	reg [47:0] in_length;
	reg [47:0] aux_length;
	reg [48:0] out_length;
	reg [63:0] in_end;
	reg [63:0] aux_end;
	reg [63:0] out_end;
	wire [127:0] word_q;
	wire [127:0] best_q;
	reg [127:0] word_payload;
	reg [127:0] best_payload;
	wire [127:0] lane_result;
	reg word_initialized;
	reg best_initialized;
	assign word_q = (word_initialized ? word_payload : 128'd0);
	assign best_q = (best_initialized ? best_payload : 128'd0);
	reg [4:0] load_y;
	reg [2:0] fill_bank;
	reg [6:0] up_read_index;
	reg [4:0] row_valid;
	reg [4:0] row_tag [0:4];
	reg [127:0] pool_maxima [0:4];
	reg [3:0] pool_scan_x;
	reg [2:0] pool_stage_index;
	reg [5:0] pool_emit_word;
	reg [4:0] pool_lane_mask;
	reg [8:0] pool_packet_words;
	reg [8:0] up_row_words_left;
	reg [8:0] up_packet_words;
	function automatic [127:0] max_i8x16;
		input reg [127:0] a;
		input reg [127:0] b;
		integer lane;
		for (lane = 0; lane < 16; lane = lane + 1)
			max_i8x16[lane * 8+:8] = ($signed(a[lane * 8+:8]) > $signed(b[lane * 8+:8]) ? a[lane * 8+:8] : b[lane * 8+:8]);
	endfunction
	reg [3:0] pool_oy;
	reg [3:0] pool_ox;
	reg [2:0] pool_cw;
	reg [2:0] pool_ky;
	reg [2:0] pool_kx;
	reg signed [5:0] pool_iy;
	reg signed [5:0] pool_ix;
	reg pool_in_bounds;
	reg pool_bank_found;
	reg [2:0] pool_bank;
	reg [4:0] up_x;
	reg [2:0] up_cw;
	reg up_hrep;
	reg up_vrep;
	reg pool_pending;
	reg pool_pending_last;
	reg pool_scan_done;
	wire [127:0] pool_stream_value = (pool_pending ? lane_result : best_q);
	reg [6:0] up_next_index;
	wire [3:0] channel_words = (in_c_q == 128 ? 4'd8 : 4'd4);
	wire up_next_row = ((({1'b0, up_cw} == (channel_words - 1'b1)) && up_hrep) && ({11'd0, up_x} == (w_q - 1'b1))) && up_vrep;
	wire up_lookahead = ((((((((((UP_EARLY_READ && !burst_up) && (state == 5'd9)) && (mode_q == UP)) && dma_rsp_valid) && dma_rsp_write) && (dma_rsp_id == 1)) && !dma_rsp_error) && !abort_now) && !up_next_row) && row_valid[0]) && (row_tag[0] == (load_y - 1'b1));
	function automatic [6:0] sv2v_cast_7;
		input reg [6:0] inp;
		sv2v_cast_7 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		up_next_index = up_read_index + 1'b1;
		if ({1'b0, up_cw} == (channel_words - 1'b1)) begin
			if (!up_hrep)
				up_next_index = up_read_index - (sv2v_cast_7(channel_words) - 7'd1);
			else if ({11'd0, up_x} == (w_q - 1'b1))
				up_next_index = 0;
		end
	end
	reg ram_wr;
	reg ram_rd;
	reg [8:0] ram_waddr;
	reg [8:0] ram_raddr;
	wire [127:0] ram_rdata;
	reg [127:0] ram_wdata;
	wire read_response_ok = (((((state == 5'd7) && dma_rsp_valid) && !dma_rsp_write) && (dma_rsp_id == 0)) && !dma_rsp_error) && !abort_now;
	function automatic overlaps;
		input reg [31:0] a;
		input reg [31:0] b;
		input reg [63:0] ae;
		input reg [63:0] be;
		overlaps = ({32'd0, a} < be) && ({32'd0, b} < ae);
	endfunction
	task automatic advance_pool;
		input reg [127:0] value;
		if ((pool_ky == 4) && (pool_kx == 4)) begin
			word_payload <= value;
			word_initialized <= 1'b1;
			state <= 5'd8;
		end
		else begin
			if (pool_kx == 4) begin
				pool_kx <= 0;
				pool_ky <= pool_ky + 1'b1;
			end
			else
				pool_kx <= pool_kx + 1'b1;
			state <= 5'd11;
		end
	endtask
	assign ready = ((state == 5'd0) && !rst) && !protocol_poison;
	assign busy = state != 5'd0;
	assign dma_req_valid = !rst && (((state == 5'd6) || (state == 5'd8)) || ((state == 5'd27) && stream_head_valid));
	assign dma_req_write = (state == 5'd8) || (state == 5'd27);
	assign dma_req_addr = ((state == 5'd8) || (state == 5'd27) ? out_cursor : ((read_kind == 3'd2) || batch_b ? aux_cursor : (((read_kind == 3'd0) || (batch_a && (mode_q == CAT))) && aux_segment ? aux_cursor : in_cursor)));
	assign dma_req_wdata = word_q;
	assign dma_req_wstrb = 16'hffff;
	assign dma_req_id = ((state == 5'd8) || (state == 5'd27) ? 4'd1 : 4'd0);
	assign dma_rsp_ready = !rst && ((state == 5'd7) || (state == 5'd9));
	soc_tensor_lane_alu lanes(
		.add_mode(mode_q == ADD),
		.a((mode_q == ADD ? word_q : best_q)),
		.b(((mode_q == ADD) && !READ_BURST_ENABLE ? dma_rsp_rdata : ram_rdata)),
		.result(lane_result)
	);
	soc_tensor_row_ram row_ram(
		.clk(clk),
		.wr_en(ram_wr),
		.rd_en(ram_rd),
		.wr_addr(ram_waddr),
		.rd_addr(ram_raddr),
		.wr_data(ram_wdata),
		.rd_data(ram_rdata)
	);
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	function automatic signed [2:0] sv2v_cast_3_signed;
		input reg signed [2:0] inp;
		sv2v_cast_3_signed = inp;
	endfunction
	function automatic signed [8:0] sv2v_cast_9_signed;
		input reg signed [8:0] inp;
		sv2v_cast_9_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		pool_iy = ($signed({2'b00, pool_oy}) + $signed({3'b000, pool_ky})) - 6'sd2;
		pool_ix = ($signed({2'b00, pool_ox}) + (parallel_pool ? $signed({2'b00, pool_scan_x}) : $signed({3'b000, pool_kx}))) - 6'sd2;
		pool_in_bounds = (((pool_iy >= 0) && (pool_iy < 10)) && (pool_ix >= 0)) && (pool_ix < 10);
		pool_bank = 0;
		pool_bank_found = 0;
		begin : sv2v_autoblock_1
			integer b;
			for (b = 0; b < 5; b = b + 1)
				if (row_valid[b] && (row_tag[b] == sv2v_cast_5_signed(pool_iy))) begin
					pool_bank = sv2v_cast_3_signed(b);
					pool_bank_found = 1;
				end
		end
		ram_wr = (read_response_ok && (((read_kind == 3'd3) || batch_a) || batch_b)) || (((state == 5'd23) && !rst) && !abort_now);
		ram_wdata = (state == 5'd23 ? pool_maxima[pool_stage_index] : dma_rsp_rdata);
		ram_waddr = (state == 5'd23 ? (9'd400 + (sv2v_cast_9(pool_stage_index) << 3)) + sv2v_cast_9(pool_cw) : (batch_a || batch_b ? (batch_b ? 9'd16 : 9'd0) + sv2v_cast_9(batch_fill) : (mode_q == POOL ? (sv2v_cast_9(fill_bank) * 9'd80) + sv2v_cast_9(cache_word) : sv2v_cast_9(cache_word))));
		stream_up_position = stream_base + sv2v_cast_9(stream_issued);
		stream_up_row = (stream_up_position >= 160 ? stream_up_position - 9'd160 : stream_up_position);
		stream_read_address = sv2v_cast_9(stream_issued);
		if (parallel_pool)
			stream_read_address = stream_base + sv2v_cast_9(stream_issued);
		else if (burst_up)
			stream_read_address = (in_c_q == 128 ? {2'd0, stream_up_row[7:4], stream_up_row[2:0]} : {2'd0, stream_up_row[7:3], stream_up_row[1:0]});
		else if (paired_cat)
			case (cat_pair_shift)
				0: stream_read_address = {4'd0, stream_issued[0], 4'd0} + {6'd0, stream_issued[3:1]};
				1: stream_read_address = {4'd0, stream_issued[1], 4'd0} + {6'd0, stream_issued[3:2], stream_issued[0]};
				2: stream_read_address = {4'd0, stream_issued[2], 4'd0} + {6'd0, stream_issued[3], stream_issued[1:0]};
				3: stream_read_address = {4'd0, stream_issued[3], 4'd0} + {6'd0, stream_issued[2:0]};
			endcase
		ram_rd = (!rst && stream_read) || ((!rst && (!abort_now || batch_write_live)) && ((((state == 5'd18) || ((state == 5'd19) && (mode_q == ADD))) || ((((state == 5'd11) || (((state == 5'd16) || (state == 5'd22)) && !pool_scan_done)) && pool_in_bounds) && pool_bank_found)) || ((((state == 5'd13) || up_lookahead) && row_valid[0]) && (row_tag[0] == (load_y - 1'b1)))));
		ram_raddr = (state == 5'd27 ? stream_read_address : ((state == 5'd18) || (state == 5'd19) ? (burst_up ? {2'd0, up_read_index} : (parallel_pool ? 9'd400 + sv2v_cast_9(pool_emit_word) : (paired_cat ? cat_pair_address : sv2v_cast_9(batch_output) + (state == 5'd19 ? 9'd16 : 9'd0)))) : (mode_q == POOL ? ((sv2v_cast_9(pool_bank) * 9'd80) + (sv2v_cast_9_signed(pool_ix) * 9'd8)) + sv2v_cast_9(pool_cw) : (up_lookahead ? {2'd0, up_next_index} : {2'd0, up_read_index}))));
		pool_packet_words = 9'd40 - sv2v_cast_9(pool_emit_word);
		if (pool_packet_words > 16)
			pool_packet_words = 16;
		if (pool_packet_words > (9'd256 - {1'b0, out_cursor[11:4]}))
			pool_packet_words = 9'd256 - {1'b0, out_cursor[11:4]};
		up_packet_words = up_row_words_left;
		if (up_packet_words > 16)
			up_packet_words = 16;
		if (up_packet_words > (9'd256 - {1'b0, out_cursor[11:4]}))
			up_packet_words = 9'd256 - {1'b0, out_cursor[11:4]};
	end
	function automatic [47:0] sv2v_cast_48;
		input reg [47:0] inp;
		sv2v_cast_48 = inp;
	endfunction
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	function automatic signed [3:0] sv2v_cast_4_signed;
		input reg signed [3:0] inp;
		sv2v_cast_4_signed = inp;
	endfunction
	always @(posedge clk) begin
		done_pulse <= 0;
		if (rst) begin
			state <= 5'd0;
			read_kind <= 3'd0;
			batch_words <= 0;
			batch_fill <= 0;
			batch_output <= 0;
			batch_write_live <= 0;
			mode_q <= CAT;
			cancel_q <= 0;
			protocol_poison <= 0;
			partial_output <= 0;
			error_sticky <= 0;
			read_bytes <= 0;
			write_bytes <= 0;
			active_cycles <= 0;
			stall_cycles <= 0;
			in_q <= 0;
			aux_q <= 0;
			out_q <= 0;
			pixels_q <= 0;
			pixels_left <= 0;
			bytes_left <= 0;
			in_c_q <= 0;
			aux_c_q <= 0;
			segment_left <= 0;
			h_q <= 0;
			w_q <= 0;
			aux_segment <= 0;
			in_length <= 0;
			aux_length <= 0;
			out_length <= 0;
			in_end <= 0;
			aux_end <= 0;
			out_end <= 0;
			in_cursor <= 0;
			aux_cursor <= 0;
			out_cursor <= 0;
			word_initialized <= 1'b0;
			best_initialized <= 1'b0;
			load_y <= 0;
			fill_bank <= 0;
			cache_word <= 0;
			up_read_index <= 0;
			row_valid <= 0;
			pool_oy <= 0;
			pool_ox <= 0;
			pool_cw <= 0;
			pool_ky <= 0;
			pool_kx <= 0;
			up_x <= 0;
			up_cw <= 0;
			up_hrep <= 0;
			up_vrep <= 0;
			pool_pending <= 0;
			pool_pending_last <= 0;
			pool_scan_done <= 0;
			pool_scan_x <= 0;
			pool_stage_index <= 0;
			pool_emit_word <= 0;
			pool_lane_mask <= 0;
			up_row_words_left <= 0;
			stream_head_valid <= 0;
			stream_ram_valid <= 0;
			stream_issued <= 0;
			stream_base <= 0;
			begin : sv2v_autoblock_2
				integer b;
				for (b = 0; b < 5; b = b + 1)
					row_tag[b] <= 0;
			end
		end
		else begin
			if (state == 5'd27) begin
				if (stream_fire) begin
					stream_head_valid <= 0;
					batch_write_live <= 1;
					partial_output <= 1;
				end
				if (stream_move) begin
					word_payload <= ram_rdata;
					word_initialized <= 1;
					stream_head_valid <= 1;
					stream_ram_valid <= 0;
				end
				if (stream_read) begin
					stream_ram_valid <= 1;
					stream_issued <= stream_issued + 1'b1;
				end
			end
			if ((state != 5'd16) && (state != 5'd22)) begin
				pool_pending <= 0;
				pool_pending_last <= 0;
			end
			if (busy)
				active_cycles <= active_cycles + 1'b1;
			if ((dma_req_valid && !dma_req_ready) || (dma_rsp_ready && !dma_rsp_valid))
				stall_cycles <= stall_cycles + 1'b1;
			if (cancel && busy)
				cancel_q <= 1;
			case (state)
				5'd0:
					if (start && !protocol_poison) begin
						in_q <= input_base;
						aux_q <= aux_base;
						out_q <= output_base;
						pixels_q <= pixels;
						in_c_q <= input_channels;
						aux_c_q <= aux_channels;
						mode_q <= operation;
						h_q <= image_h;
						w_q <= image_w;
						cancel_q <= 0;
						partial_output <= 0;
						error_sticky <= 0;
						read_bytes <= 0;
						write_bytes <= 0;
						active_cycles <= 0;
						stall_cycles <= 0;
						row_valid <= 0;
						state <= 5'd1;
					end
				5'd1: begin
					in_length <= sv2v_cast_48(pixels_q) * sv2v_cast_48(in_c_q);
					aux_length <= sv2v_cast_48(pixels_q) * sv2v_cast_48(aux_c_q);
					state <= 5'd2;
				end
				5'd2: begin
					case (mode_q)
						CAT: out_length <= {1'b0, in_length} + {1'b0, aux_length};
						ADD: begin
							out_length <= {1'b0, in_length};
							aux_length <= in_length;
						end
						UP: begin
							out_length <= {1'b0, in_length} << 2;
							aux_length <= 0;
						end
						POOL: begin
							out_length <= {1'b0, in_length};
							aux_length <= 0;
						end
					endcase
					state <= 5'd3;
				end
				5'd3: begin
					in_end <= {32'd0, in_q} + {16'd0, in_length};
					aux_end <= {32'd0, aux_q} + {16'd0, aux_length};
					out_end <= {32'd0, out_q} + {15'd0, out_length};
					state <= 5'd4;
				end
				5'd4:
					if ((((((((((pixels_q == 0) || (in_c_q == 0)) || |in_c_q[3:0]) || |in_q[3:0]) || |out_q[3:0]) || ((mode_q == CAT) && ((((aux_c_q == 0) || |aux_c_q[3:0]) || |aux_q[3:0]) || (({1'b0, in_c_q} + {1'b0, aux_c_q}) > 17'd65535)))) || ((mode_q == ADD) && ((aux_c_q != 0) || |aux_q[3:0]))) || (((mode_q == UP) || (mode_q == POOL)) && ((aux_q != 0) || (aux_c_q != 0)))) || ((mode_q == POOL) && !((((h_q == 10) && (w_q == 10)) && (in_c_q == 128)) && (pixels_q == 100)))) || ((mode_q == UP) && !(((((h_q == 10) && (w_q == 10)) && (in_c_q == 128)) && (pixels_q == 100)) || ((((h_q == 20) && (w_q == 20)) && (in_c_q == 64)) && (pixels_q == 400))))) begin
						error_sticky <= BAD_SHAPE;
						state <= 5'd15;
					end
					else if ((((((((in_q < DDR_BASE) || (out_q < DDR_BASE)) || (in_end > DDR_LIMIT)) || (out_end > DDR_LIMIT)) || (in_length > {16'd0, DDR_BYTES})) || (out_length > {17'd0, DDR_BYTES})) || overlaps(in_q, out_q, in_end, out_end)) || ((aux_length != 0) && (((((aux_q < DDR_BASE) || (aux_end > DDR_LIMIT)) || (aux_length > {16'd0, DDR_BYTES})) || overlaps(in_q, aux_q, in_end, aux_end)) || overlaps(aux_q, out_q, aux_end, out_end)))) begin
						error_sticky <= BAD_RANGE;
						state <= 5'd15;
					end
					else if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else begin
						in_cursor <= in_q;
						aux_cursor <= aux_q;
						out_cursor <= out_q;
						bytes_left <= sv2v_cast_32(in_length);
						pixels_left <= pixels_q;
						segment_left <= in_c_q;
						aux_segment <= 0;
						pool_oy <= 0;
						pool_ox <= 0;
						pool_cw <= 0;
						load_y <= 0;
						fill_bank <= 0;
						cache_word <= 0;
						if (tensor_batch_mode)
							state <= 5'd17;
						else if (mode_q == CAT) begin
							read_kind <= 3'd0;
							state <= 5'd6;
						end
						else if (mode_q == ADD) begin
							read_kind <= 3'd1;
							state <= 5'd6;
						end
						else
							state <= 5'd5;
					end
				5'd5:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else if ((mode_q == UP) || ((load_y < 10) && (load_y <= ({1'b0, pool_oy} + 5'd2)))) begin
						row_valid[(mode_q == UP ? 0 : fill_bank)] <= 0;
						cache_word <= 0;
						read_kind <= 3'd3;
						state <= 5'd6;
					end
					else
						state <= 5'd10;
				5'd6:
					if (dma_req_ready)
						state <= 5'd7;
				5'd7:
					if (dma_rsp_valid) begin
						if (dma_rsp_write || (dma_rsp_id != 0)) begin
							error_sticky <= BAD_RESPONSE;
							protocol_poison <= 1;
							state <= 5'd15;
						end
						else if (dma_rsp_error) begin
							error_sticky <= READ_ERROR;
							state <= 5'd15;
						end
						else if (abort_now) begin
							if (response_last) begin
								error_sticky <= CANCELLED;
								state <= 5'd15;
							end
						end
						else begin
							read_bytes <= read_bytes + 32'd16;
							case (read_kind)
								3'd0: begin
									word_payload <= dma_rsp_rdata;
									word_initialized <= 1'b1;
									state <= 5'd8;
								end
								3'd1: begin
									word_payload <= dma_rsp_rdata;
									word_initialized <= 1'b1;
									read_kind <= 3'd2;
									state <= 5'd6;
								end
								3'd2: begin
									word_payload <= lane_result;
									word_initialized <= 1'b1;
									state <= 5'd8;
								end
								3'd4, 3'd5:
									if (response_last) begin
										batch_fill <= 0;
										if (batch_a && ((mode_q == ADD) || paired_cat)) begin
											read_kind <= 3'd5;
											state <= 5'd6;
										end
										else begin
											batch_output <= 0;
											state <= (OUTPUT_PIPELINE && (mode_q != ADD) ? 5'd26 : 5'd18);
										end
									end
									else
										batch_fill <= batch_fill + 1'b1;
								3'd3: begin
									in_cursor <= in_cursor + 32'd16;
									if (cache_word == 79) begin
										row_valid[(mode_q == UP ? 0 : fill_bank)] <= 1;
										row_tag[(mode_q == UP ? 0 : fill_bank)] <= load_y;
										load_y <= load_y + 1'b1;
										cache_word <= 0;
										if (mode_q == POOL) begin
											fill_bank <= (fill_bank == 4 ? 0 : fill_bank + 1'b1);
											state <= 5'd5;
										end
										else begin
											up_x <= 0;
											up_cw <= 0;
											up_hrep <= 0;
											up_vrep <= 0;
											up_read_index <= 0;
											up_row_words_left <= 9'd320;
											state <= (burst_up ? 5'd25 : 5'd13);
										end
									end
									else begin
										cache_word <= cache_word + 1'b1;
										state <= (response_last ? 5'd6 : 5'd7);
									end
								end
							endcase
						end
					end
				5'd17:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else begin
						batch_words <= sv2v_cast_5(batch_limit);
						batch_fill <= 0;
						read_kind <= 3'd4;
						state <= 5'd6;
					end
				5'd18:
					if (abort_now && !batch_write_live) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else
						state <= 5'd19;
				5'd19:
					if (abort_now && !batch_write_live) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else begin
						word_payload <= ram_rdata;
						word_initialized <= 1'b1;
						state <= (mode_q == ADD ? 5'd20 : 5'd8);
					end
				5'd20:
					if (abort_now && !batch_write_live) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else begin
						word_payload <= lane_result;
						word_initialized <= 1'b1;
						state <= 5'd8;
					end
				5'd26:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else begin
						stream_head_valid <= 0;
						stream_ram_valid <= 0;
						stream_issued <= 0;
						stream_base <= (burst_up ? 9'd320 - up_row_words_left : 9'd400 + sv2v_cast_9(pool_emit_word));
						state <= 5'd27;
					end
				5'd10:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else begin
						best_payload <= {16 {8'h80}};
						best_initialized <= 1'b1;
						pool_ky <= 0;
						pool_kx <= 0;
						pool_scan_done <= 0;
						pool_pending <= 0;
						pool_pending_last <= 0;
						pool_scan_x <= 0;
						pool_stage_index <= 0;
						pool_lane_mask <= 0;
						begin : sv2v_autoblock_3
							integer g;
							for (g = 0; g < 5; g = g + 1)
								pool_maxima[g] <= {16 {8'h80}};
						end
						state <= (parallel_pool ? 5'd22 : (PIPELINED_POOL ? 5'd16 : 5'd11));
					end
				5'd22:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else if ((!pool_scan_done && pool_in_bounds) && !pool_bank_found) begin
						error_sticky <= BAD_OWNER;
						state <= 5'd15;
					end
					else begin
						if (pool_pending) begin : sv2v_autoblock_4
							integer g;
							for (g = 0; g < 5; g = g + 1)
								if (pool_lane_mask[g])
									pool_maxima[g] <= max_i8x16(pool_maxima[g], ram_rdata);
						end
						if (pool_pending_last) begin
							pool_pending <= 0;
							state <= 5'd23;
						end
						else begin
							pool_pending <= (!pool_scan_done && pool_in_bounds) && pool_bank_found;
							begin : sv2v_autoblock_5
								integer g;
								for (g = 0; g < 5; g = g + 1)
									pool_lane_mask[g] <= (pool_scan_x >= sv2v_cast_4_signed(g)) && (pool_scan_x < sv2v_cast_4_signed(g + 5));
							end
							pool_pending_last <= (!pool_scan_done && (pool_ky == 4)) && (pool_scan_x == 8);
							if (!pool_scan_done) begin
								if ((pool_ky == 4) && (pool_scan_x == 8))
									pool_scan_done <= 1;
								else if (pool_scan_x == 8) begin
									pool_scan_x <= 0;
									pool_ky <= pool_ky + 1'b1;
								end
								else
									pool_scan_x <= pool_scan_x + 1'b1;
							end
						end
					end
				5'd23:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else if (pool_stage_index == 4) begin
						pool_stage_index <= 0;
						if (pool_cw == 7) begin
							pool_cw <= 0;
							pool_emit_word <= 0;
							state <= 5'd24;
						end
						else begin
							pool_cw <= pool_cw + 1'b1;
							state <= 5'd10;
						end
					end
					else
						pool_stage_index <= pool_stage_index + 1'b1;
				5'd24:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else begin
						batch_words <= sv2v_cast_5(pool_packet_words);
						batch_output <= 0;
						state <= (OUTPUT_PIPELINE ? 5'd26 : 5'd18);
					end
				5'd25:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else if (!row_valid[0] || (row_tag[0] != (load_y - 1'b1))) begin
						error_sticky <= BAD_OWNER;
						state <= 5'd15;
					end
					else begin
						batch_words <= sv2v_cast_5(up_packet_words);
						batch_output <= 0;
						state <= (OUTPUT_PIPELINE ? 5'd26 : 5'd18);
					end
				5'd16:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else if (pool_pending_last) begin
						word_payload <= pool_stream_value;
						word_initialized <= 1'b1;
						state <= 5'd8;
						pool_pending <= 0;
						pool_pending_last <= 0;
					end
					else if ((!pool_scan_done && pool_in_bounds) && !pool_bank_found) begin
						error_sticky <= BAD_OWNER;
						state <= 5'd15;
					end
					else begin
						if (pool_pending) begin
							best_payload <= lane_result;
							best_initialized <= 1'b1;
						end
						pool_pending <= (!pool_scan_done && pool_in_bounds) && pool_bank_found;
						pool_pending_last <= (!pool_scan_done && (pool_ky == 4)) && (pool_kx == 4);
						if (!pool_scan_done) begin
							if ((pool_ky == 4) && (pool_kx == 4))
								pool_scan_done <= 1;
							else if (pool_kx == 4) begin
								pool_kx <= 0;
								pool_ky <= pool_ky + 1'b1;
							end
							else
								pool_kx <= pool_kx + 1'b1;
						end
					end
				5'd11:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else if (!pool_in_bounds)
						advance_pool(best_q);
					else if (!pool_bank_found) begin
						error_sticky <= BAD_OWNER;
						state <= 5'd15;
					end
					else
						state <= 5'd12;
				5'd12:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else begin
						best_payload <= lane_result;
						best_initialized <= 1'b1;
						advance_pool(lane_result);
					end
				5'd13:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else if (!row_valid[0] || (row_tag[0] != (load_y - 1'b1))) begin
						error_sticky <= BAD_OWNER;
						state <= 5'd15;
					end
					else
						state <= 5'd14;
				5'd14:
					if (abort_now) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else begin
						word_payload <= ram_rdata;
						word_initialized <= 1'b1;
						state <= 5'd8;
					end
				5'd8:
					if (dma_req_ready) begin
						partial_output <= 1;
						if (batch_write_mode)
							batch_write_live <= 1;
						state <= (batch_write_mode && ((batch_output + 1'b1) < batch_words) ? 5'd21 : 5'd9);
					end
				5'd27, 5'd9, 5'd21: begin
					if ((((state == 5'd27) && abort_now) && !batch_write_live) && !stream_head_valid) begin
						error_sticky <= CANCELLED;
						state <= 5'd15;
					end
					else if (((state == 5'd27) && stream_fire) && !stream_nonlast)
						state <= 5'd9;
					if (((state == 5'd21) || stream_nonlast) || ((state == 5'd9) && dma_rsp_valid)) begin
						if (state == 5'd9)
							batch_write_live <= 0;
						if ((state == 5'd9) && (!dma_rsp_write || (dma_rsp_id != 1))) begin
							error_sticky <= BAD_RESPONSE;
							protocol_poison <= 1;
							state <= 5'd15;
						end
						else if ((state == 5'd9) && dma_rsp_error) begin
							error_sticky <= WRITE_ERROR;
							state <= 5'd15;
						end
						else if ((state == 5'd9) && abort_now) begin
							error_sticky <= CANCELLED;
							state <= 5'd15;
						end
						else begin
							if (state == 5'd9)
								write_bytes <= write_bytes + (batch_write_mode ? sv2v_cast_32(batch_words) << 4 : 32'd16);
							out_cursor <= out_cursor + 32'd16;
							case (mode_q)
								CAT: begin
									if (aux_segment)
										aux_cursor <= aux_cursor + 32'd16;
									else
										in_cursor <= in_cursor + 32'd16;
									if (segment_left == 16) begin
										if (!aux_segment) begin
											aux_segment <= 1;
											segment_left <= aux_c_q;
											state <= 5'd6;
										end
										else if (pixels_left == 1) begin
											partial_output <= 0;
											state <= 5'd15;
										end
										else begin
											aux_segment <= 0;
											segment_left <= in_c_q;
											pixels_left <= pixels_left - 1'b1;
											state <= 5'd6;
										end
									end
									else begin
										segment_left <= segment_left - 16'd16;
										state <= 5'd6;
									end
									if (tensor_batch_mode && !((aux_segment && (segment_left == 16)) && (pixels_left == 1))) begin
										if ((batch_output + 1'b1) < batch_words) begin
											batch_output <= batch_output + 1'b1;
											state <= 5'd18;
										end
										else
											state <= 5'd17;
									end
								end
								ADD:
									if (bytes_left == 16) begin
										partial_output <= 0;
										state <= 5'd15;
									end
									else begin
										bytes_left <= bytes_left - 32'd16;
										in_cursor <= in_cursor + 32'd16;
										aux_cursor <= aux_cursor + 32'd16;
										read_kind <= 3'd1;
										state <= 5'd6;
										if (READ_BURST_ENABLE) begin
											if ((batch_output + 1'b1) < batch_words) begin
												batch_output <= batch_output + 1'b1;
												state <= 5'd18;
											end
											else
												state <= 5'd17;
										end
									end
								POOL:
									if (parallel_pool) begin
										if (pool_emit_word == 39) begin
											pool_emit_word <= 0;
											pool_cw <= 0;
											if (pool_ox == 0) begin
												pool_ox <= 5;
												state <= 5'd10;
											end
											else begin
												pool_ox <= 0;
												if (pool_oy == 9) begin
													partial_output <= 0;
													state <= 5'd15;
												end
												else begin
													pool_oy <= pool_oy + 1'b1;
													state <= 5'd5;
												end
											end
										end
										else begin
											pool_emit_word <= pool_emit_word + 1'b1;
											if ((batch_output + 1'b1) < batch_words) begin
												batch_output <= batch_output + 1'b1;
												state <= 5'd18;
											end
											else
												state <= 5'd24;
										end
									end
									else begin
										state <= 5'd10;
										if (pool_cw == 7) begin
											pool_cw <= 0;
											if (pool_ox == 9) begin
												pool_ox <= 0;
												if (pool_oy == 9) begin
													partial_output <= 0;
													state <= 5'd15;
												end
												else begin
													pool_oy <= pool_oy + 1'b1;
													state <= 5'd5;
												end
											end
											else
												pool_ox <= pool_ox + 1'b1;
										end
										else
											pool_cw <= pool_cw + 1'b1;
									end
								UP: begin
									state <= (up_lookahead ? 5'd14 : 5'd13);
									if (burst_up) begin
										up_row_words_left <= up_row_words_left - 1'b1;
										if ((batch_output + 1'b1) < batch_words) begin
											batch_output <= batch_output + 1'b1;
											state <= 5'd18;
										end
										else
											state <= 5'd25;
									end
									if ({1'b0, up_cw} == (channel_words - 1'b1)) begin
										up_cw <= 0;
										if (!up_hrep) begin
											up_hrep <= 1;
											up_read_index <= up_read_index - (sv2v_cast_7(channel_words) - 7'd1);
										end
										else begin
											up_hrep <= 0;
											if ({11'd0, up_x} == (w_q - 1'b1)) begin
												up_x <= 0;
												up_read_index <= 0;
												if (!up_vrep)
													up_vrep <= 1;
												else begin
													up_vrep <= 0;
													if ({11'd0, load_y} == h_q) begin
														partial_output <= 0;
														state <= 5'd15;
													end
													else
														state <= 5'd5;
												end
											end
											else begin
												up_x <= up_x + 1'b1;
												up_read_index <= up_read_index + 1'b1;
											end
										end
									end
									else begin
										up_cw <= up_cw + 1'b1;
										up_read_index <= up_read_index + 1'b1;
									end
								end
							endcase
							if (state == 5'd27) begin
								batch_output <= batch_output + 1'b1;
								state <= 5'd27;
							end
						end
					end
				end
				5'd15: begin
					done_pulse <= 1;
					state <= 5'd0;
				end
				default: begin
					error_sticky <= BAD_RESPONSE;
					protocol_poison <= 1;
					state <= 5'd15;
				end
			endcase
		end
	end
	initial _sv2v_0 = 0;
endmodule
module soc_concat_mmio_mem (
	clk,
	rst,
	ddr_ready,
	axi_poisoned,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	engine_start,
	engine_cancel,
	engine_ready,
	engine_done,
	engine_error,
	engine_partial,
	engine_read_bytes,
	engine_write_bytes,
	engine_active_cycles,
	engine_stall_cycles,
	input_base,
	aux_base,
	output_base,
	pixels,
	input_channels,
	aux_channels,
	operation,
	image_h,
	image_w,
	irq_level
);
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	input wire axi_poisoned;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output reg engine_start;
	output reg engine_cancel;
	input wire engine_ready;
	input wire engine_done;
	input wire [7:0] engine_error;
	input wire engine_partial;
	input wire [31:0] engine_read_bytes;
	input wire [31:0] engine_write_bytes;
	input wire [31:0] engine_active_cycles;
	input wire [31:0] engine_stall_cycles;
	output reg [31:0] input_base;
	output reg [31:0] aux_base;
	output reg [31:0] output_base;
	output reg [31:0] pixels;
	output reg [15:0] input_channels;
	output reg [15:0] aux_channels;
	output reg [1:0] operation;
	output reg [15:0] image_h;
	output reg [15:0] image_w;
	output wire irq_level;
	localparam [31:0] ID = 32'h31544143;
	reg busy_q;
	reg done_q;
	reg partial_q;
	reg rejected_q;
	reg irq_enable_q;
	reg [7:0] error_q;
	wire hit = ((req_addr >= 16'h0400) && (req_addr <= 16'h0440)) && (req_addr[1:0] == 0);
	assign req_ready = !rst && !rsp_valid;
	assign irq_level = done_q && irq_enable_q;
	always @(posedge clk) begin
		engine_start <= 0;
		engine_cancel <= 0;
		if (rst) begin
			rsp_valid <= 0;
			rsp_rdata <= 0;
			rsp_error <= 0;
			busy_q <= 0;
			done_q <= 0;
			partial_q <= 0;
			rejected_q <= 0;
			irq_enable_q <= 0;
			error_q <= 0;
			input_base <= 0;
			aux_base <= 0;
			output_base <= 0;
			pixels <= 0;
			input_channels <= 0;
			aux_channels <= 0;
			operation <= 0;
			image_h <= 0;
			image_w <= 0;
		end
		else begin
			if (engine_done) begin
				busy_q <= 0;
				done_q <= 1;
				error_q <= engine_error;
				partial_q <= engine_partial;
			end
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			if (req_valid && req_ready) begin
				rsp_valid <= 1;
				rsp_rdata <= 0;
				rsp_error <= 0;
				if (!hit || (req_write && (req_wstrb != 4'hf))) begin
					rsp_error <= 1;
					rejected_q <= 1;
				end
				else if (req_write) begin
					if ((busy_q && (req_addr == 16'h0400)) && (req_wdata == 2))
						engine_cancel <= 1;
					else if (busy_q) begin
						rsp_error <= 1;
						rejected_q <= 1;
					end
					else
						case (req_addr)
							16'h0400:
								if ((((req_wdata != 1) || !engine_ready) || !ddr_ready) || axi_poisoned) begin
									rsp_error <= 1;
									rejected_q <= 1;
								end
								else begin
									engine_start <= 1;
									busy_q <= 1;
									done_q <= 0;
									error_q <= 0;
									partial_q <= 0;
									rejected_q <= 0;
								end
							16'h0404: input_base <= req_wdata;
							16'h0408: aux_base <= req_wdata;
							16'h040c: output_base <= req_wdata;
							16'h0410: pixels <= req_wdata;
							16'h0414: {aux_channels, input_channels} <= req_wdata;
							16'h0418:
								if (req_wdata <= 1)
									irq_enable_q <= req_wdata[0];
								else begin
									rsp_error <= 1;
									rejected_q <= 1;
								end
							16'h0430:
								if (req_wdata == 1) begin
									done_q <= 0;
									partial_q <= 0;
									error_q <= 0;
									rejected_q <= 0;
								end
								else begin
									rsp_error <= 1;
									rejected_q <= 1;
								end
							16'h0438:
								if (req_wdata <= 3)
									operation <= req_wdata[1:0];
								else begin
									rsp_error <= 1;
									rejected_q <= 1;
								end
							16'h043c: {image_h, image_w} <= req_wdata;
							default: begin
								rsp_error <= 1;
								rejected_q <= 1;
							end
						endcase
				end
				else
					case (req_addr)
						16'h0400: rsp_rdata <= 0;
						16'h0404: rsp_rdata <= input_base;
						16'h0408: rsp_rdata <= aux_base;
						16'h040c: rsp_rdata <= output_base;
						16'h0410: rsp_rdata <= pixels;
						16'h0414: rsp_rdata <= {aux_channels, input_channels};
						16'h0418: rsp_rdata <= {31'd0, irq_enable_q};
						16'h041c: rsp_rdata <= {14'd0, engine_ready, axi_poisoned, ddr_ready, rejected_q, partial_q, error_q, 3'd0, done_q, busy_q};
						16'h0420: rsp_rdata <= engine_read_bytes;
						16'h0424: rsp_rdata <= engine_write_bytes;
						16'h0428: rsp_rdata <= engine_active_cycles;
						16'h042c: rsp_rdata <= engine_stall_cycles;
						16'h0430: rsp_rdata <= 0;
						16'h0434: rsp_rdata <= ID;
						16'h0438: rsp_rdata <= {30'd0, operation};
						16'h043c: rsp_rdata <= {image_h, image_w};
						16'h0440: rsp_rdata <= 32'h31534e54;
						default: begin
							rsp_error <= 1;
							rejected_q <= 1;
						end
					endcase
			end
		end
	end
endmodule
module soc_v2_replay_pipeline (
	clk,
	rst,
	ddr_ready,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	m_awid,
	m_awaddr,
	m_awlen,
	m_awsize,
	m_awburst,
	m_awvalid,
	m_awready,
	m_wdata,
	m_wstrb,
	m_wlast,
	m_wvalid,
	m_wready,
	m_bid,
	m_bresp,
	m_bvalid,
	m_bready,
	m_arid,
	m_araddr,
	m_arlen,
	m_arsize,
	m_arburst,
	m_arvalid,
	m_arready,
	m_rid,
	m_rdata,
	m_rresp,
	m_rlast,
	m_rvalid,
	m_rready
);
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	output wire [3:0] m_awid;
	output wire [31:0] m_awaddr;
	output wire [7:0] m_awlen;
	output wire [2:0] m_awsize;
	output wire [1:0] m_awburst;
	output wire m_awvalid;
	input wire m_awready;
	output wire [127:0] m_wdata;
	output wire [15:0] m_wstrb;
	output wire m_wlast;
	output wire m_wvalid;
	input wire m_wready;
	input wire [3:0] m_bid;
	input wire [1:0] m_bresp;
	input wire m_bvalid;
	output wire m_bready;
	output wire [3:0] m_arid;
	output wire [31:0] m_araddr;
	output wire [7:0] m_arlen;
	output wire [2:0] m_arsize;
	output wire [1:0] m_arburst;
	output wire m_arvalid;
	input wire m_arready;
	input wire [3:0] m_rid;
	input wire [127:0] m_rdata;
	input wire [1:0] m_rresp;
	input wire m_rlast;
	input wire m_rvalid;
	output wire m_rready;
	wire start;
	wire [31:0] source_addr;
	wire [31:0] destination_addr;
	wire lut_write;
	wire lut_ready;
	wire lut_complete;
	wire [7:0] lut_addr;
	wire [7:0] lut_data;
	wire reader_ready;
	wire reader_busy;
	wire reader_done;
	wire reader_valid;
	wire [7:0] reader_errors;
	wire [31:0] reader_pixels;
	wire raw_valid;
	wire raw_ready;
	wire raw_last;
	wire [15:0] raw_pixel;
	wire stream_ready;
	wire stream_busy;
	wire stream_done;
	wire stream_valid;
	wire [7:0] stream_errors;
	wire [31:0] source_pixels;
	wire [31:0] active_pixels;
	wire [31:0] output_pixels;
	wire tensor_valid;
	wire tensor_ready;
	wire tensor_last;
	wire [23:0] tensor_pixel;
	wire writer_busy;
	wire writer_done;
	wire writer_valid;
	wire [7:0] writer_errors;
	wire [31:0] writer_pixels;
	wire [31:0] bytes_written;
	soc_v2_replay_mmio controller(
		.clk(clk),
		.rst(rst),
		.ddr_ready(ddr_ready),
		.req_valid(req_valid),
		.req_ready(req_ready),
		.req_addr(req_addr),
		.req_write(req_write),
		.req_wdata(req_wdata),
		.req_wstrb(req_wstrb),
		.rsp_valid(rsp_valid),
		.rsp_ready(rsp_ready),
		.rsp_rdata(rsp_rdata),
		.rsp_error(rsp_error),
		.start(start),
		.source_addr(source_addr),
		.destination_addr(destination_addr),
		.lut_write(lut_write),
		.lut_addr(lut_addr),
		.lut_data(lut_data),
		.lut_ready(lut_ready),
		.lut_complete(lut_complete),
		.reader_ready(reader_ready),
		.reader_done(reader_done),
		.reader_valid(reader_valid),
		.reader_errors(reader_errors),
		.stream_ready(stream_ready),
		.stream_done(stream_done),
		.stream_valid(stream_valid),
		.stream_errors(stream_errors),
		.writer_busy(writer_busy),
		.writer_done(writer_done),
		.writer_valid(writer_valid),
		.writer_errors(writer_errors),
		.source_pixels(source_pixels),
		.active_pixels(active_pixels),
		.output_pixels(output_pixels),
		.bytes_written(bytes_written)
	);
	soc_video_axi_reader reader(
		.clk(clk),
		.rst(rst),
		.start(start),
		.frame_base(source_addr),
		.frame_pixels(32'd5038848),
		.ready(reader_ready),
		.busy(reader_busy),
		.done_pulse(reader_done),
		.frame_valid(reader_valid),
		.error_sticky(reader_errors),
		.pixels_emitted(reader_pixels),
		.pixel_valid(raw_valid),
		.pixel_ready(raw_ready),
		.pixel_data(raw_pixel),
		.pixel_last(raw_last),
		.m_arid(m_arid),
		.m_araddr(m_araddr),
		.m_arlen(m_arlen),
		.m_arsize(m_arsize),
		.m_arburst(m_arburst),
		.m_arvalid(m_arvalid),
		.m_arready(m_arready),
		.m_rid(m_rid),
		.m_rdata(m_rdata),
		.m_rresp(m_rresp),
		.m_rlast(m_rlast),
		.m_rvalid(m_rvalid),
		.m_rready(m_rready)
	);
	soc_v2_stream_5mp stream(
		.clk(clk),
		.rst(rst),
		.start(start),
		.abort(reader_done && !reader_valid),
		.ready(stream_ready),
		.busy(stream_busy),
		.done_pulse(stream_done),
		.frame_valid(stream_valid),
		.error_sticky(stream_errors),
		.lut_write(lut_write),
		.lut_addr(lut_addr),
		.lut_data(lut_data),
		.lut_ready(lut_ready),
		.lut_complete(lut_complete),
		.in_valid(raw_valid),
		.in_last(raw_last),
		.in_ready(raw_ready),
		.in_rgb565(raw_pixel),
		.out_valid(tensor_valid),
		.out_last(tensor_last),
		.out_ready(tensor_ready),
		.out_rgb_i8(tensor_pixel),
		.source_pixels(source_pixels),
		.active_pixels(active_pixels),
		.output_pixels(output_pixels)
	);
	soc_v2_axi_writer writer(
		.clk(clk),
		.rst(rst),
		.start(start),
		.destination(destination_addr),
		.producer_done(stream_done),
		.producer_valid(stream_valid),
		.pixel_valid(tensor_valid),
		.pixel_last(tensor_last),
		.pixel_ready(tensor_ready),
		.pixel_rgb_i8(tensor_pixel),
		.busy(writer_busy),
		.done_pulse(writer_done),
		.frame_valid(writer_valid),
		.error_sticky(writer_errors),
		.pixels_accepted(writer_pixels),
		.bytes_written(bytes_written),
		.m_awid(m_awid),
		.m_awaddr(m_awaddr),
		.m_awlen(m_awlen),
		.m_awsize(m_awsize),
		.m_awburst(m_awburst),
		.m_awvalid(m_awvalid),
		.m_awready(m_awready),
		.m_wdata(m_wdata),
		.m_wstrb(m_wstrb),
		.m_wlast(m_wlast),
		.m_wvalid(m_wvalid),
		.m_wready(m_wready),
		.m_bid(m_bid),
		.m_bresp(m_bresp),
		.m_bvalid(m_bvalid),
		.m_bready(m_bready)
	);
endmodule
module soc_v2_replay_mmio (
	clk,
	rst,
	ddr_ready,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	start,
	source_addr,
	destination_addr,
	lut_write,
	lut_addr,
	lut_data,
	lut_ready,
	lut_complete,
	reader_ready,
	reader_done,
	reader_valid,
	reader_errors,
	stream_ready,
	stream_done,
	stream_valid,
	stream_errors,
	writer_busy,
	writer_done,
	writer_valid,
	writer_errors,
	source_pixels,
	active_pixels,
	output_pixels,
	bytes_written
);
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output reg start;
	output reg [31:0] source_addr;
	output reg [31:0] destination_addr;
	output wire lut_write;
	output wire [7:0] lut_addr;
	output wire [7:0] lut_data;
	input wire lut_ready;
	input wire lut_complete;
	input wire reader_ready;
	input wire reader_done;
	input wire reader_valid;
	input wire [7:0] reader_errors;
	input wire stream_ready;
	input wire stream_done;
	input wire stream_valid;
	input wire [7:0] stream_errors;
	input wire writer_busy;
	input wire writer_done;
	input wire writer_valid;
	input wire [7:0] writer_errors;
	input wire [31:0] source_pixels;
	input wire [31:0] active_pixels;
	input wire [31:0] output_pixels;
	input wire [31:0] bytes_written;
	localparam [31:0] SOURCE_BYTES = 10077696;
	localparam [31:0] DEST_BYTES = 307200;
	reg job_busy;
	reg done_hold;
	reg valid_hold;
	reg rejected_hold;
	reg [7:0] lut_index;
	wire [31:0] status_word;
	wire request_fire;
	assign req_ready = !rst && !rsp_valid;
	assign request_fire = req_valid && req_ready;
	assign lut_addr = lut_index;
	assign lut_data = req_wdata[7:0];
	assign lut_write = (((((request_fire && req_write) && (req_addr == 16'h0230)) && (req_wstrb == 4'hf)) && (req_wdata[31:8] == 0)) && !job_busy) && lut_ready;
	assign status_word = {25'd0, ddr_ready, ((|reader_errors || |stream_errors) || |writer_errors) || rejected_hold, lut_complete, valid_hold, done_hold, job_busy, ((reader_ready && stream_ready) && !writer_busy) && ddr_ready};
	always @(posedge clk) begin
		start <= 0;
		if (rst) begin
			rsp_valid <= 0;
			rsp_rdata <= 0;
			rsp_error <= 0;
			source_addr <= 32'h81000000;
			destination_addr <= 32'h80100000;
			lut_index <= 0;
			job_busy <= 0;
			done_hold <= 0;
			valid_hold <= 0;
			rejected_hold <= 0;
		end
		else begin
			if (writer_done) begin
				job_busy <= 0;
				done_hold <= 1;
				valid_hold <= writer_valid;
			end
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			if (request_fire) begin
				rsp_valid <= 1;
				rsp_rdata <= 0;
				rsp_error <= 0;
				if ((((req_addr < 16'h0200) || (req_addr > 16'h0234)) || (req_addr[1:0] != 0)) || (req_write && (req_wstrb != 4'hf))) begin
					rsp_error <= 1;
					rejected_hold <= 1;
				end
				else if (req_write)
					case (req_addr)
						16'h0200:
							if (((((((((((((req_wdata != 1) || job_busy) || !ddr_ready) || !reader_ready) || !stream_ready) || writer_busy) || !lut_complete) || (source_addr[7:0] != 0)) || (source_addr < 32'h81000000)) || (source_addr > (32'h83000000 - SOURCE_BYTES))) || (destination_addr[3:0] != 0)) || (destination_addr < 32'h80000000)) || (destination_addr > (32'h81000000 - DEST_BYTES))) begin
								rsp_error <= 1;
								rejected_hold <= 1;
							end
							else begin
								start <= 1;
								job_busy <= 1;
								done_hold <= 0;
								valid_hold <= 0;
								rejected_hold <= 0;
							end
						16'h0204:
							if (!job_busy)
								source_addr <= req_wdata;
							else begin
								rsp_error <= 1;
								rejected_hold <= 1;
							end
						16'h0208:
							if (!job_busy)
								destination_addr <= req_wdata;
							else begin
								rsp_error <= 1;
								rejected_hold <= 1;
							end
						16'h022c:
							if ((!job_busy && lut_ready) && (req_wdata[31:8] == 0))
								lut_index <= req_wdata[7:0];
							else begin
								rsp_error <= 1;
								rejected_hold <= 1;
							end
						16'h0230:
							if (lut_write)
								lut_index <= lut_index + 1;
							else begin
								rsp_error <= 1;
								rejected_hold <= 1;
							end
						default: begin
							rsp_error <= 1;
							rejected_hold <= 1;
						end
					endcase
				else
					case (req_addr)
						16'h0200: rsp_rdata <= 0;
						16'h0204: rsp_rdata <= source_addr;
						16'h0208: rsp_rdata <= destination_addr;
						16'h020c: rsp_rdata <= status_word;
						16'h0210: rsp_rdata <= source_pixels;
						16'h0214: rsp_rdata <= active_pixels;
						16'h0218: rsp_rdata <= output_pixels;
						16'h021c: rsp_rdata <= bytes_written;
						16'h0220: rsp_rdata <= {23'd0, reader_valid, reader_errors};
						16'h0224: rsp_rdata <= {23'd0, stream_valid, stream_errors};
						16'h0228: rsp_rdata <= {23'd0, writer_valid, writer_errors};
						16'h022c: rsp_rdata <= {24'd0, lut_index};
						16'h0230: rsp_rdata <= 0;
						16'h0234: rsp_rdata <= 32'h32563253;
						default: begin
							rsp_error <= 1;
							rejected_hold <= 1;
						end
					endcase
			end
		end
	end
endmodule
module soc_video_axi_reader (
	clk,
	rst,
	start,
	frame_base,
	frame_pixels,
	ready,
	busy,
	done_pulse,
	frame_valid,
	error_sticky,
	pixels_emitted,
	pixel_valid,
	pixel_ready,
	pixel_data,
	pixel_last,
	m_arid,
	m_araddr,
	m_arlen,
	m_arsize,
	m_arburst,
	m_arvalid,
	m_arready,
	m_rid,
	m_rdata,
	m_rresp,
	m_rlast,
	m_rvalid,
	m_rready
);
	parameter [31:0] VIDEO_BASE = 32'h81000000;
	parameter [31:0] VIDEO_BYTES = 32'h02000000;
	parameter signed [31:0] MAX_PIXELS = 5038848;
	input wire clk;
	input wire rst;
	input wire start;
	input wire [31:0] frame_base;
	input wire [31:0] frame_pixels;
	output wire ready;
	output wire busy;
	output reg done_pulse;
	output reg frame_valid;
	output reg [7:0] error_sticky;
	output reg [31:0] pixels_emitted;
	output wire pixel_valid;
	input wire pixel_ready;
	output wire [15:0] pixel_data;
	output wire pixel_last;
	output wire [3:0] m_arid;
	output wire [31:0] m_araddr;
	output wire [7:0] m_arlen;
	output wire [2:0] m_arsize;
	output wire [1:0] m_arburst;
	output wire m_arvalid;
	input wire m_arready;
	input wire [3:0] m_rid;
	input wire [127:0] m_rdata;
	input wire [1:0] m_rresp;
	input wire m_rlast;
	input wire m_rvalid;
	output wire m_rready;
	reg [2:0] state;
	reg [31:0] base_q;
	reg [31:0] target_q;
	(* ram_style = "distributed" *) reg [127:0] burst_data [0:15];
	reg [4:0] burst_beats_q;
	reg [4:0] beat_index_q;
	reg [4:0] emit_index_q;
	reg [3:0] lane_q;
	reg [3:0] beat_pixels_q;
	wire [33:0] frame_end;
	wire valid_config;
	wire [31:0] remaining;
	wire [4:0] next_burst_beats;
	assign frame_end = {2'b00, frame_base} + {1'b0, frame_pixels, 1'b0};
	assign valid_config = ((((frame_base[7:0] == 0) && (frame_pixels != 0)) && (frame_pixels <= MAX_PIXELS)) && (frame_base >= VIDEO_BASE)) && (frame_end <= ({2'b00, VIDEO_BASE} + {2'b00, VIDEO_BYTES}));
	assign remaining = target_q - pixels_emitted;
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	assign next_burst_beats = (remaining >= 32'd128 ? 5'd16 : sv2v_cast_5((remaining + 7) >> 3));
	assign ready = (state == 3'd0) && !rst;
	assign busy = state != 3'd0;
	assign m_arid = 4'hd;
	assign m_araddr = base_q + (pixels_emitted << 1);
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	assign m_arlen = sv2v_cast_8(next_burst_beats - 1'b1);
	assign m_arsize = 3'd4;
	assign m_arburst = 2'b01;
	assign m_arvalid = state == 3'd1;
	assign m_rready = (state == 3'd2) || (state == 3'd4);
	assign pixel_valid = state == 3'd3;
	assign pixel_data = burst_data[emit_index_q[3:0]][16 * lane_q[2:0]+:16];
	assign pixel_last = pixel_valid && ((pixels_emitted + 1) == target_q);
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	always @(posedge clk) begin
		done_pulse <= 0;
		if (rst) begin
			state <= 3'd0;
			base_q <= 0;
			target_q <= 0;
			burst_beats_q <= 0;
			beat_index_q <= 0;
			emit_index_q <= 0;
			lane_q <= 0;
			beat_pixels_q <= 0;
			pixels_emitted <= 0;
			error_sticky <= 0;
			frame_valid <= 0;
		end
		else
			case (state)
				3'd0:
					if (start) begin
						base_q <= frame_base;
						target_q <= frame_pixels;
						pixels_emitted <= 0;
						error_sticky <= 0;
						frame_valid <= 0;
						beat_index_q <= 0;
						emit_index_q <= 0;
						lane_q <= 0;
						if (valid_config)
							state <= 3'd1;
						else begin
							error_sticky[0] <= 1;
							done_pulse <= 1;
						end
					end
				3'd1:
					if (m_arready) begin
						burst_beats_q <= next_burst_beats;
						beat_index_q <= 0;
						state <= 3'd2;
					end
				3'd2:
					if (m_rvalid) begin
						if (((m_rid != 4'hd) || (m_rresp != 2'b00)) || (m_rlast != ((beat_index_q + 1) == burst_beats_q))) begin
							error_sticky[1] <= (m_rid != 4'hd) || (m_rresp != 2'b00);
							error_sticky[2] <= m_rlast != ((beat_index_q + 1) == burst_beats_q);
							if (m_rlast) begin
								done_pulse <= 1;
								state <= 3'd0;
							end
							else
								state <= 3'd4;
						end
						else begin
							burst_data[beat_index_q[3:0]] <= m_rdata;
							if ((beat_index_q + 1) == burst_beats_q) begin
								emit_index_q <= 0;
								lane_q <= 0;
								beat_pixels_q <= (remaining >= 32'd8 ? 4'd8 : sv2v_cast_4(remaining));
								state <= 3'd3;
							end
							else
								beat_index_q <= beat_index_q + 1;
						end
					end
				3'd3:
					if (pixel_ready) begin
						pixels_emitted <= pixels_emitted + 1;
						if ((lane_q + 1) == beat_pixels_q) begin
							if ((pixels_emitted + 1) == target_q) begin
								frame_valid <= 1;
								done_pulse <= 1;
								state <= 3'd0;
							end
							else if ((emit_index_q + 1) == burst_beats_q)
								state <= 3'd1;
							else begin
								emit_index_q <= emit_index_q + 1;
								lane_q <= 0;
								beat_pixels_q <= (remaining > 32'd9 ? 4'd8 : sv2v_cast_4(remaining - 1'b1));
							end
						end
						else
							lane_q <= lane_q + 1;
					end
				3'd4:
					if (m_rvalid && m_rlast) begin
						done_pulse <= 1;
						state <= 3'd0;
					end
				default: state <= 3'd0;
			endcase
	end
	initial if (((VIDEO_BASE[7:0] != 0) || (VIDEO_BYTES < 256)) || (MAX_PIXELS < 1)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_video_axi_reader.sv:120:9 - soc_video_axi_reader.<unnamed_block>\n msg: ", $time, "VIDEO_REPLAY_PARAMETER");
		$finish(1);
	end
endmodule
module soc_v2_stream_5mp (
	clk,
	rst,
	start,
	abort,
	ready,
	busy,
	done_pulse,
	frame_valid,
	error_sticky,
	lut_write,
	lut_addr,
	lut_data,
	lut_ready,
	lut_complete,
	in_valid,
	in_last,
	in_ready,
	in_rgb565,
	out_valid,
	out_last,
	out_ready,
	out_rgb_i8,
	source_pixels,
	active_pixels,
	output_pixels
);
	input wire clk;
	input wire rst;
	input wire start;
	input wire abort;
	output wire ready;
	output wire busy;
	output reg done_pulse;
	output reg frame_valid;
	output reg [7:0] error_sticky;
	input wire lut_write;
	input wire [7:0] lut_addr;
	input wire [7:0] lut_data;
	output wire lut_ready;
	output wire lut_complete;
	input wire in_valid;
	input wire in_last;
	output wire in_ready;
	input wire [15:0] in_rgb565;
	output wire out_valid;
	output wire out_last;
	input wire out_ready;
	output wire [23:0] out_rgb_i8;
	output reg [31:0] source_pixels;
	output reg [31:0] active_pixels;
	output reg [31:0] output_pixels;
	localparam signed [31:0] SRC_W = 2592;
	localparam signed [31:0] SRC_H = 1944;
	localparam signed [31:0] DST_W = 320;
	localparam signed [31:0] ACTIVE_H = 240;
	localparam signed [31:0] SRC_PIXELS = SRC_W * SRC_H;
	localparam signed [31:0] ACTIVE_PIXELS = DST_W * ACTIVE_H;
	localparam signed [31:0] PAD_PIXELS = 12800;
	localparam signed [31:0] OUT_PIXELS = 102400;
	reg [2:0] state;
	(* ram_style = "block" *) reg [15:0] top_left [0:319];
	(* ram_style = "block" *) reg [15:0] top_right [0:319];
	reg [15:0] left_sample;
	reg [11:0] source_x;
	reg [11:0] target_x;
	reg [11:0] target_y;
	reg [10:0] source_y;
	reg [8:0] target_u;
	reg [7:0] target_v;
	reg [4:0] phase_x;
	reg [4:0] phase_y;
	reg [13:0] pad_issued;
	reg source_ok;
	reg [2:0] failed_drain_cycles;
	wire top_row;
	wire bottom_row;
	wire at_left;
	wire at_right;
	wire need_core;
	wire core_in_valid;
	wire core_in_ready;
	wire core_out_valid;
	wire core_out_ready;
	wire [23:0] core_out_data;
	wire source_fire;
	wire core_fire;
	wire output_fire;
	assign ready = (!rst && (state == 3'd0)) && lut_complete;
	assign busy = state != 3'd0;
	assign top_row = (source_y == target_y) && (target_v < ACTIVE_H);
	assign bottom_row = (source_y == (target_y + 12'd1)) && (target_v < ACTIVE_H);
	assign at_left = (source_x == target_x) && (target_u < DST_W);
	assign at_right = (source_x == (target_x + 12'd1)) && (target_u < DST_W);
	assign need_core = bottom_row && at_right;
	assign core_in_valid = ((state == 3'd1) || (state == 3'd3) ? 1'b1 : ((state == 3'd2) && in_valid) && need_core);
	assign in_ready = (state == 3'd2) && (!need_core || core_in_ready);
	assign source_fire = in_valid && in_ready;
	assign core_fire = core_in_valid && core_in_ready;
	assign core_out_ready = (state == 3'd5 ? 1'b1 : out_ready);
	assign out_valid = (core_out_valid && (state != 3'd5)) && (state != 3'd0);
	assign out_rgb_i8 = core_out_data;
	assign out_last = out_valid && (output_pixels == 102399);
	assign output_fire = out_valid && out_ready;
	soc_v2_bilinear_quant arithmetic(
		.clk(clk),
		.rst(rst),
		.lut_write(lut_write),
		.lut_addr(lut_addr),
		.lut_data(lut_data),
		.lut_ready(lut_ready),
		.lut_complete(lut_complete),
		.in_valid(core_in_valid),
		.in_ready(core_in_ready),
		.pad((state == 3'd1) || (state == 3'd3)),
		.c00(top_left[target_u]),
		.c01(top_right[target_u]),
		.c10(left_sample),
		.c11(in_rgb565),
		.phase_x(phase_x),
		.phase_y(phase_y),
		.out_valid(core_out_valid),
		.out_ready(core_out_ready),
		.out_rgb_i8(core_out_data)
	);
	always @(posedge clk) begin
		done_pulse <= 0;
		if (rst) begin
			state <= 3'd0;
			frame_valid <= 0;
			error_sticky <= 0;
			source_ok <= 0;
			failed_drain_cycles <= 0;
			source_x <= 0;
			source_y <= 0;
			target_x <= 12'd3;
			target_y <= 12'd3;
			target_u <= 0;
			target_v <= 0;
			phase_x <= 5'd11;
			phase_y <= 5'd11;
			pad_issued <= 0;
			source_pixels <= 0;
			active_pixels <= 0;
			output_pixels <= 0;
			left_sample <= 0;
		end
		else begin
			if (start && (state != 3'd0))
				error_sticky[3] <= 1;
			if (output_fire) begin
				output_pixels <= output_pixels + 1;
				if (output_pixels == 102399) begin
					frame_valid <= source_ok && (error_sticky == 0);
					done_pulse <= 1;
					state <= 3'd0;
				end
			end
			case (state)
				3'd0:
					if (start) begin
						frame_valid <= 0;
						error_sticky <= 0;
						source_ok <= 0;
						failed_drain_cycles <= 0;
						source_x <= 0;
						source_y <= 0;
						source_pixels <= 0;
						target_x <= 12'd3;
						target_y <= 12'd3;
						target_u <= 0;
						target_v <= 0;
						phase_x <= 5'd11;
						phase_y <= 5'd11;
						active_pixels <= 0;
						pad_issued <= 0;
						output_pixels <= 0;
						if (lut_complete)
							state <= 3'd1;
						else begin
							error_sticky[0] <= 1;
							done_pulse <= 1;
						end
					end
				3'd1:
					if (core_fire) begin
						pad_issued <= pad_issued + 1;
						if (pad_issued == 12799) begin
							pad_issued <= 0;
							state <= 3'd2;
						end
					end
				3'd2:
					if (abort) begin
						error_sticky[1] <= 1;
						done_pulse <= 1;
						state <= 3'd5;
					end
					else if (source_fire) begin
						source_pixels <= source_pixels + 1;
						if (source_x == 2591) begin
							source_x <= 0;
							source_y <= source_y + 1;
							target_x <= 12'd3;
							target_u <= 0;
							phase_x <= 5'd11;
						end
						else
							source_x <= source_x + 1;
						if ((top_row || bottom_row) && at_left)
							left_sample <= in_rgb565;
						if ((top_row || bottom_row) && at_right) begin
							if (top_row) begin
								top_left[target_u] <= left_sample;
								top_right[target_u] <= in_rgb565;
							end
							else begin
								active_pixels <= active_pixels + 1;
								if (target_u == 319) begin
									target_v <= target_v + 1;
									target_y <= (target_y + 12'd8) + (phase_y >= 5'd18);
									phase_y <= (phase_y >= 5'd18 ? phase_y + (5'd2 - 5'd20) : phase_y + 5'd2);
								end
							end
							target_u <= target_u + 1;
							target_x <= (target_x + 12'd8) + (phase_x >= 5'd18);
							phase_x <= (phase_x >= 5'd18 ? phase_x + (5'd2 - 5'd20) : phase_x + 5'd2);
						end
						if (in_last || (source_pixels == (SRC_PIXELS - 1))) begin
							if ((in_last && (source_pixels == (SRC_PIXELS - 1))) && (active_pixels == ACTIVE_PIXELS)) begin
								source_ok <= 1;
								pad_issued <= 0;
								state <= 3'd3;
							end
							else begin
								error_sticky[2] <= 1;
								done_pulse <= 1;
								state <= 3'd5;
								failed_drain_cycles <= 0;
							end
						end
					end
				3'd3:
					if (core_fire) begin
						pad_issued <= pad_issued + 1;
						if (pad_issued == 12799)
							state <= 3'd4;
					end
				3'd4:
					;
				3'd5:
					if (failed_drain_cycles < 3'd5)
						failed_drain_cycles <= failed_drain_cycles + 1'b1;
					else if (!core_out_valid)
						state <= 3'd0;
				default: state <= 3'd5;
			endcase
			if ((abort && (state != 3'd0)) && (state != 3'd5)) begin
				frame_valid <= 0;
				source_ok <= 0;
				error_sticky[1] <= 1;
				done_pulse <= 1;
				state <= 3'd5;
				failed_drain_cycles <= 0;
			end
		end
	end
	initial if (((SRC_W * SRC_H) != 5038848) || 1'd0) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_v2_stream_5mp.sv:164:9 - soc_v2_stream_5mp.<unnamed_block>\n msg: ", $time, "V2_STREAM_DIMENSIONS");
		$finish(1);
	end
endmodule
module soc_v2_bilinear_quant (
	clk,
	rst,
	lut_write,
	lut_addr,
	lut_data,
	lut_ready,
	lut_complete,
	in_valid,
	in_ready,
	pad,
	c00,
	c01,
	c10,
	c11,
	phase_x,
	phase_y,
	out_valid,
	out_ready,
	out_rgb_i8
);
	input wire clk;
	input wire rst;
	input wire lut_write;
	input wire [7:0] lut_addr;
	input wire [7:0] lut_data;
	output wire lut_ready;
	output wire lut_complete;
	input wire in_valid;
	output wire in_ready;
	input wire pad;
	input wire [15:0] c00;
	input wire [15:0] c01;
	input wire [15:0] c10;
	input wire [15:0] c11;
	input wire [4:0] phase_x;
	input wire [4:0] phase_y;
	output wire out_valid;
	input wire out_ready;
	output reg [23:0] out_rgb_i8;
	(* ram_style = "distributed" *) reg [7:0] lut [0:255];
	reg [255:0] written;
	reg locked;
	reg [4:0] valid_q;
	reg [3:0] pad_q;
	reg [8:0] weight_q [0:3];
	reg [7:0] sample_q [0:11];
	reg [16:0] product_q [0:11];
	reg [18:0] sum_q [0:2];
	reg [7:0] rgb_q [0:2];
	wire ready_0;
	wire ready_1;
	wire ready_2;
	wire ready_3;
	wire ready_4;
	function automatic [7:0] expand;
		input reg [15:0] word;
		input reg signed [31:0] channel;
		reg [4:0] five;
		reg [5:0] six;
		case (channel)
			0: begin
				five = word[15:11];
				expand = {five, five[4:2]};
			end
			1: begin
				six = word[10:5];
				expand = {six, six[5:4]};
			end
			default: begin
				five = word[4:0];
				expand = {five, five[4:2]};
			end
		endcase
	endfunction
	assign lut_ready = !rst && !locked;
	assign lut_complete = &written;
	assign ready_4 = !valid_q[4] || out_ready;
	assign ready_3 = !valid_q[3] || ready_4;
	assign ready_2 = !valid_q[2] || ready_3;
	assign ready_1 = !valid_q[1] || ready_2;
	assign ready_0 = !valid_q[0] || ready_1;
	assign in_ready = (!rst && lut_complete) && ready_0;
	assign out_valid = valid_q[4];
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	function automatic [18:0] sv2v_cast_19;
		input reg [18:0] inp;
		sv2v_cast_19 = inp;
	endfunction
	function automatic [16:0] sv2v_cast_17;
		input reg [16:0] inp;
		sv2v_cast_17 = inp;
	endfunction
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			written <= 1'sb0;
			locked <= 0;
			valid_q <= 1'sb0;
			pad_q <= 1'sb0;
			out_rgb_i8 <= 0;
		end
		else begin
			if (lut_write && lut_ready) begin
				lut[lut_addr] <= lut_data;
				written[lut_addr] <= 1;
			end
			if (ready_4) begin
				valid_q[4] <= valid_q[3];
				if (valid_q[3])
					out_rgb_i8 <= {lut[rgb_q[2]], lut[rgb_q[1]], lut[rgb_q[0]]};
			end
			if (ready_3) begin
				valid_q[3] <= valid_q[2];
				if (valid_q[2]) begin
					pad_q[3] <= pad_q[2];
					begin : sv2v_autoblock_1
						reg signed [31:0] ch;
						for (ch = 0; ch < 3; ch = ch + 1)
							rgb_q[ch] <= (pad_q[2] ? 8'd114 : sv2v_cast_8((sum_q[ch] + 19'd200) / 19'd400));
					end
				end
			end
			if (ready_2) begin
				valid_q[2] <= valid_q[1];
				if (valid_q[1]) begin
					pad_q[2] <= pad_q[1];
					begin : sv2v_autoblock_2
						reg signed [31:0] ch;
						for (ch = 0; ch < 3; ch = ch + 1)
							sum_q[ch] <= ((sv2v_cast_19(product_q[(ch * 4) + 0]) + sv2v_cast_19(product_q[(ch * 4) + 1])) + sv2v_cast_19(product_q[(ch * 4) + 2])) + sv2v_cast_19(product_q[(ch * 4) + 3]);
					end
				end
			end
			if (ready_1) begin
				valid_q[1] <= valid_q[0];
				if (valid_q[0]) begin
					pad_q[1] <= pad_q[0];
					begin : sv2v_autoblock_3
						reg signed [31:0] ch;
						for (ch = 0; ch < 3; ch = ch + 1)
							begin : sv2v_autoblock_4
								reg signed [31:0] tap;
								for (tap = 0; tap < 4; tap = tap + 1)
									product_q[(ch * 4) + tap] <= sv2v_cast_17(weight_q[tap]) * sv2v_cast_17(sample_q[(ch * 4) + tap]);
							end
					end
				end
			end
			if (ready_0) begin
				valid_q[0] <= in_valid && lut_complete;
				if (in_valid && lut_complete) begin
					locked <= 1;
					pad_q[0] <= pad;
					weight_q[0] <= sv2v_cast_9(20 - phase_x) * sv2v_cast_9(20 - phase_y);
					weight_q[1] <= sv2v_cast_9(phase_x) * sv2v_cast_9(20 - phase_y);
					weight_q[2] <= sv2v_cast_9(20 - phase_x) * sv2v_cast_9(phase_y);
					weight_q[3] <= sv2v_cast_9(phase_x) * sv2v_cast_9(phase_y);
					begin : sv2v_autoblock_5
						reg signed [31:0] ch;
						for (ch = 0; ch < 3; ch = ch + 1)
							begin
								sample_q[(ch * 4) + 0] <= expand(c00, ch);
								sample_q[(ch * 4) + 1] <= expand(c01, ch);
								sample_q[(ch * 4) + 2] <= expand(c10, ch);
								sample_q[(ch * 4) + 3] <= expand(c11, ch);
							end
					end
				end
			end
		end
endmodule
module soc_v2_axi_writer (
	clk,
	rst,
	start,
	destination,
	producer_done,
	producer_valid,
	pixel_valid,
	pixel_last,
	pixel_ready,
	pixel_rgb_i8,
	busy,
	done_pulse,
	frame_valid,
	error_sticky,
	pixels_accepted,
	bytes_written,
	m_awid,
	m_awaddr,
	m_awlen,
	m_awsize,
	m_awburst,
	m_awvalid,
	m_awready,
	m_wdata,
	m_wstrb,
	m_wlast,
	m_wvalid,
	m_wready,
	m_bid,
	m_bresp,
	m_bvalid,
	m_bready
);
	input wire clk;
	input wire rst;
	input wire start;
	input wire [31:0] destination;
	input wire producer_done;
	input wire producer_valid;
	input wire pixel_valid;
	input wire pixel_last;
	output wire pixel_ready;
	input wire [23:0] pixel_rgb_i8;
	output wire busy;
	output reg done_pulse;
	output reg frame_valid;
	output reg [7:0] error_sticky;
	output reg [31:0] pixels_accepted;
	output reg [31:0] bytes_written;
	output wire [3:0] m_awid;
	output wire [31:0] m_awaddr;
	output wire [7:0] m_awlen;
	output wire [2:0] m_awsize;
	output wire [1:0] m_awburst;
	output wire m_awvalid;
	input wire m_awready;
	output wire [127:0] m_wdata;
	output wire [15:0] m_wstrb;
	output wire m_wlast;
	output wire m_wvalid;
	input wire m_wready;
	input wire [3:0] m_bid;
	input wire [1:0] m_bresp;
	input wire m_bvalid;
	output wire m_bready;
	localparam [31:0] BASE = 32'h80000000;
	localparam [31:0] END_ADDR = 32'h84000000;
	localparam signed [31:0] PIXELS = 102400;
	localparam signed [31:0] BYTES = 307200;
	reg [2:0] state;
	reg [127:0] stage_data;
	reg [15:0] carry_data;
	reg [1:0] carry_count;
	reg [4:0] fill_bytes;
	reg [31:0] write_addr;
	reg producer_done_seen;
	reg producer_good_seen;
	wire [31:0] byte_position;
	assign busy = state != 3'd0;
	assign pixel_ready = ((state == 3'd1) && (pixels_accepted < PIXELS)) && !producer_done_seen;
	assign m_awid = 4'he;
	assign m_awaddr = write_addr;
	assign m_awlen = 0;
	assign m_awsize = 3'd4;
	assign m_awburst = 2'b01;
	assign m_awvalid = state == 3'd2;
	assign m_wdata = stage_data;
	assign m_wstrb = 16'hffff;
	assign m_wlast = 1'b1;
	assign m_wvalid = state == 3'd3;
	assign m_bready = state == 3'd4;
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	function automatic [1:0] sv2v_cast_2;
		input reg [1:0] inp;
		sv2v_cast_2 = inp;
	endfunction
	function automatic [127:0] sv2v_cast_128;
		input reg [127:0] inp;
		sv2v_cast_128 = inp;
	endfunction
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	always @(posedge clk) begin
		done_pulse <= 0;
		if (rst) begin
			state <= 3'd0;
			stage_data <= 0;
			carry_data <= 0;
			carry_count <= 0;
			fill_bytes <= 0;
			write_addr <= 0;
			pixels_accepted <= 0;
			bytes_written <= 0;
			producer_done_seen <= 0;
			producer_good_seen <= 0;
			frame_valid <= 0;
			error_sticky <= 0;
		end
		else begin
			if (start && (state != 3'd0))
				error_sticky[4] <= 1;
			if ((state != 3'd0) && producer_done) begin
				producer_done_seen <= 1;
				producer_good_seen <= producer_valid;
				if (!producer_valid)
					error_sticky[2] <= 1;
			end
			case (state)
				3'd0:
					if (start) begin
						stage_data <= 0;
						carry_data <= 0;
						carry_count <= 0;
						fill_bytes <= 0;
						write_addr <= destination;
						pixels_accepted <= 0;
						bytes_written <= 0;
						producer_done_seen <= 0;
						producer_good_seen <= 0;
						frame_valid <= 0;
						error_sticky <= 0;
						if (((destination[3:0] != 0) || (destination < BASE)) || (destination > (END_ADDR - BYTES))) begin
							error_sticky[0] <= 1;
							done_pulse <= 1;
						end
						else
							state <= 3'd1;
					end
				3'd1:
					if (pixel_valid && pixel_ready) begin
						begin : sv2v_autoblock_1
							reg signed [31:0] b;
							for (b = 0; b < 3; b = b + 1)
								if ((fill_bytes + sv2v_cast_5_signed(b)) < 16)
									stage_data[8 * (fill_bytes + sv2v_cast_5_signed(b))+:8] <= pixel_rgb_i8[8 * b+:8];
								else
									carry_data[8 * ((fill_bytes + sv2v_cast_5_signed(b)) - 5'd16)+:8] <= pixel_rgb_i8[8 * b+:8];
						end
						pixels_accepted <= pixels_accepted + 1;
						if (pixel_last != (pixels_accepted == 102399))
							error_sticky[1] <= 1;
						if ((fill_bytes + 5'd3) >= 16) begin
							carry_count <= sv2v_cast_2(fill_bytes + (5'd3 - 5'd16));
							state <= 3'd2;
						end
						else
							fill_bytes <= fill_bytes + 5'd3;
					end
					else if (producer_done_seen) begin
						if (((((pixels_accepted != PIXELS) || (fill_bytes != 0)) || (bytes_written != BYTES)) || !producer_good_seen) || (error_sticky != 0)) begin
							error_sticky[3] <= ((pixels_accepted != PIXELS) || (fill_bytes != 0)) || (bytes_written != BYTES);
							frame_valid <= 0;
						end
						else
							frame_valid <= 1;
						done_pulse <= 1;
						state <= 3'd0;
					end
				3'd2:
					if (m_awready)
						state <= 3'd3;
				3'd3:
					if (m_wready)
						state <= 3'd4;
				3'd4:
					if (m_bvalid) begin
						if ((m_bid != 4'he) || (m_bresp != 2'b00))
							error_sticky[5] <= 1;
						bytes_written <= bytes_written + 16;
						write_addr <= write_addr + 16;
						stage_data <= sv2v_cast_128(carry_data);
						fill_bytes <= sv2v_cast_5(carry_count);
						carry_data <= 0;
						carry_count <= 0;
						state <= 3'd1;
					end
				default: state <= 3'd0;
			endcase
		end
	end
endmodule
module soc_display_commit_mmio (
	clk,
	rst,
	ddr_ready,
	axi_poisoned,
	cpu_time_gray,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	awvalid,
	awready,
	awaddr,
	awid,
	awlen,
	awsize,
	awburst,
	wvalid,
	wready,
	wstrb,
	wlast,
	bvalid,
	bready,
	bid,
	bresp,
	publish_valid,
	publish_ready,
	publish_fb,
	publish_frame,
	publish_run,
	publish_xy1,
	publish_xy2,
	publish_score,
	publish_class,
	publish_count,
	publish_sequence,
	display_valid,
	display_fb,
	pending_display_valid,
	pending_display_fb
);
	reg _sv2v_0;
	parameter signed [31:0] FRAME_BYTES = 614400;
	parameter signed [31:0] BOX_WIDTH = 640;
	parameter signed [31:0] BOX_HEIGHT = 480;
	parameter signed [31:0] TRACK_DEPTH = 4;
	parameter [3:0] MMIO_PAGE = 4'h2;
	parameter [0:0] REQUIRE_PRESENT_ACK = 0;
	parameter [0:0] SCOPED_WRITER = 0;
	parameter [31:0] FB_MIN = 32'h82000000;
	parameter [31:0] FB_LIMIT = 32'h82400000;
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	input wire axi_poisoned;
	input wire [63:0] cpu_time_gray;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	input wire awvalid;
	input wire awready;
	input wire [31:0] awaddr;
	input wire [3:0] awid;
	input wire [7:0] awlen;
	input wire [2:0] awsize;
	input wire [1:0] awburst;
	input wire wvalid;
	input wire wready;
	input wire [15:0] wstrb;
	input wire wlast;
	input wire bvalid;
	input wire bready;
	input wire [3:0] bid;
	input wire [1:0] bresp;
	output reg publish_valid;
	input wire publish_ready;
	output wire [31:0] publish_fb;
	output wire [31:0] publish_frame;
	output wire [31:0] publish_run;
	output wire [31:0] publish_xy1;
	output wire [31:0] publish_xy2;
	output wire [31:0] publish_score;
	output wire [31:0] publish_class;
	output wire [31:0] publish_count;
	output wire [31:0] publish_sequence;
	input wire display_valid;
	input wire [31:0] display_fb;
	input wire pending_display_valid;
	input wire [31:0] pending_display_fb;
	localparam signed [31:0] PW = $clog2(TRACK_DEPTH);
	reg [88:0] tx [0:TRACK_DEPTH - 1];
	reg [88:0] tx_n [0:TRACK_DEPTH - 1];
	reg [PW - 1:0] aw_tail;
	reg [PW - 1:0] b_head;
	reg [PW - 1:0] w_head;
	reg [PW - 1:0] aw_tail_n;
	reg [PW - 1:0] b_head_n;
	reg [PW - 1:0] w_head_n;
	reg [PW:0] pending;
	reg [PW:0] w_pending;
	reg [PW:0] pending_n;
	reg [PW:0] w_pending_n;
	reg [PW:0] frame_pending;
	reg [PW:0] frame_pending_n;
	reg scope_fault;
	reg scope_fault_n;
	reg armed;
	reg ready_flag;
	reg nms_done;
	reg active_valid;
	reg [7:0] error_code;
	reg [7:0] error_n;
	reg [31:0] accepted_bytes;
	reg [31:0] committed_bytes;
	reg [31:0] accepted_n;
	reg [31:0] committed_n;
	reg [31:0] shadow_fb;
	reg [31:0] shadow_frame;
	reg [31:0] shadow_xy1;
	reg [31:0] shadow_xy2;
	reg [31:0] shadow_score;
	reg [31:0] shadow_class;
	reg [31:0] shadow_count;
	reg [31:0] active_fb;
	reg [31:0] active_frame;
	reg [31:0] active_xy1;
	reg [31:0] active_xy2;
	reg [31:0] active_score;
	reg [31:0] active_class;
	reg [31:0] active_count;
	reg [31:0] commit_sequence;
	reg [31:0] shadow_run;
	reg [31:0] active_run;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [63:0] cpu_gray_meta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [63:0] cpu_gray_sync;
	reg [63:0] cpu_binary;
	reg [63:0] cpu_ticks;
	reg [63:0] tf_ticks;
	reg [63:0] tr_ticks;
	reg tf_recorded;
	reg [31:0] tracked_fb;
	reg aw_seen;
	reg w_seen;
	reg b_seen;
	reg [31:0] awaddr_seen;
	reg [3:0] awid_seen;
	reg [3:0] bid_seen;
	reg [7:0] awlen_seen;
	reg [2:0] awsize_seen;
	reg [1:0] awburst_seen;
	reg [1:0] bresp_seen;
	reg [15:0] wstrb_seen;
	reg wlast_seen;
	reg [63:0] last_b_ticks;
	wire [32:0] shadow_end = {1'b0, shadow_fb} + FRAME_BYTES;
	wire [32:0] tracked_end = {1'b0, tracked_fb} + FRAME_BYTES;
	wire [32:0] live_aw_end = {1'b0, awaddr} + (({25'b0000000000000000000000000, awlen} + 33'd1) << 4);
	wire shadow_aw_hit = (awvalid && ({1'b0, awaddr} < shadow_end)) && (live_aw_end > {1'b0, shadow_fb});
	wire tracked_aw_hit = (awvalid && ({1'b0, awaddr} < tracked_end)) && (live_aw_end > {1'b0, tracked_fb});
	wire aw_fire = aw_seen;
	wire w_fire = w_seen;
	wire b_fire = b_seen;
	wire observation_pending = (aw_seen || w_seen) || b_seen;
	wire access = req_valid && req_ready;
	wire [7:0] off = {req_addr[7:2], 2'b00};
	wire metadata_ok = (shadow_count <= 1) && ((shadow_count == 0) || (((((shadow_xy1[15:0] < shadow_xy2[15:0]) && (shadow_xy1[31:16] < shadow_xy2[31:16])) && (shadow_xy2[15:0] <= BOX_WIDTH)) && (shadow_xy2[31:16] <= BOX_HEIGHT)) && (shadow_score <= 32768)));
	assign req_ready = !rsp_valid || rsp_ready;
	assign publish_fb = active_fb;
	assign publish_frame = active_frame;
	assign publish_run = active_run;
	assign publish_xy1 = active_xy1;
	assign publish_xy2 = active_xy2;
	assign publish_score = active_score;
	assign publish_class = active_class;
	assign publish_count = active_count;
	assign publish_sequence = commit_sequence;
	always @(*) begin : sv2v_autoblock_1
		integer i;
		if (_sv2v_0)
			;
		for (i = 0; i < 64; i = i + 1)
			cpu_binary[i] = ^(cpu_gray_sync >> i);
	end
	function automatic [4:0] strobe_bytes;
		input reg [15:0] s;
		reg [2:0] a;
		reg [2:0] b;
		reg [2:0] c;
		reg [2:0] d;
		begin
			a = (({2'b00, s[0]} + {2'b00, s[1]}) + {2'b00, s[2]}) + {2'b00, s[3]};
			b = (({2'b00, s[4]} + {2'b00, s[5]}) + {2'b00, s[6]}) + {2'b00, s[7]};
			c = (({2'b00, s[8]} + {2'b00, s[9]}) + {2'b00, s[10]}) + {2'b00, s[11]};
			d = (({2'b00, s[12]} + {2'b00, s[13]}) + {2'b00, s[14]}) + {2'b00, s[15]};
			strobe_bytes = ({2'b00, a} + {2'b00, b}) + ({2'b00, c} + {2'b00, d});
		end
	endfunction
	always @(posedge clk)
		if (rst) begin
			aw_seen <= 0;
			w_seen <= 0;
			b_seen <= 0;
			last_b_ticks <= 0;
		end
		else begin
			aw_seen <= awvalid && awready;
			w_seen <= wvalid && wready;
			b_seen <= bvalid && bready;
			if ((bvalid && bready) && !SCOPED_WRITER)
				last_b_ticks <= cpu_ticks;
			if (((((((SCOPED_WRITER && b_seen) && (pending != 0)) && tx[b_head][88]) && tx[b_head][86]) && tx[b_head][87]) && (tx[b_head][85-:4] == bid_seen)) && (bresp_seen == 0))
				last_b_ticks <= cpu_ticks;
		end
	always @(posedge clk) begin
		awaddr_seen <= awaddr;
		awid_seen <= awid;
		awlen_seen <= awlen;
		awsize_seen <= awsize;
		awburst_seen <= awburst;
		wstrb_seen <= wstrb;
		wlast_seen <= wlast;
		bid_seen <= bid;
		bresp_seen <= bresp;
	end
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	function automatic [32:0] sv2v_cast_33;
		input reg [32:0] inp;
		sv2v_cast_33 = inp;
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(*) begin : coverage
		reg [32:0] end_address;
		reg [32:0] effective_address;
		reg [32:0] expected_address;
		reg [15:0] contiguous;
		reg [4:0] first_byte;
		reg [4:0] byte_count;
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_2
			integer i;
			for (i = 0; i < TRACK_DEPTH; i = i + 1)
				tx_n[i] = tx[i];
		end
		aw_tail_n = aw_tail;
		b_head_n = b_head;
		w_head_n = w_head;
		pending_n = pending;
		w_pending_n = w_pending;
		frame_pending_n = frame_pending;
		scope_fault_n = scope_fault;
		error_n = error_code;
		accepted_n = accepted_bytes;
		committed_n = committed_bytes;
		end_address = 0;
		effective_address = 0;
		expected_address = 0;
		contiguous = 0;
		first_byte = 0;
		byte_count = 0;
		if (aw_fire) begin
			end_address = {1'b0, awaddr_seen} + (({25'b0000000000000000000000000, awlen_seen} + 33'd1) << 4);
			if (pending_n == TRACK_DEPTH)
				error_n = 8'd1;
			else begin
				tx_n[aw_tail_n] = 1'sb0;
				tx_n[aw_tail_n][88] = 1;
				tx_n[aw_tail_n][85-:4] = awid_seen;
				tx_n[aw_tail_n][81-:32] = awaddr_seen;
				tx_n[aw_tail_n][17-:9] = {1'b0, awlen_seen} + 9'd1;
				tx_n[aw_tail_n][87] = (armed && ({1'b0, awaddr_seen} < ({1'b0, tracked_fb} + FRAME_BYTES))) && (end_address > {1'b0, tracked_fb});
				if (tx_n[aw_tail_n][87] && ((((((awsize_seen != 4) || (awburst_seen != 1)) || (awaddr_seen[3:0] != 0)) || (({1'b0, awaddr_seen[11:0]} + (({5'b00000, awlen_seen} + 13'd1) << 4)) > 4096)) || (awaddr_seen < tracked_fb)) || (end_address > ({1'b0, tracked_fb} + FRAME_BYTES))))
					error_n = 8'd2;
				if ((armed && !tx_n[aw_tail_n][87]) && !SCOPED_WRITER)
					error_n = 8'd3;
				if (((SCOPED_WRITER && !tx_n[aw_tail_n][87]) && ({1'b0, awaddr_seen} < {1'b0, FB_LIMIT})) && (end_address > {1'b0, FB_MIN})) begin
					error_n = 8'd3;
					scope_fault_n = 1'b1;
				end
				if (tx_n[aw_tail_n][87])
					frame_pending_n = frame_pending_n + 1'b1;
				aw_tail_n = aw_tail_n + 1'b1;
				pending_n = pending_n + 1'b1;
				w_pending_n = w_pending_n + 1'b1;
			end
		end
		if (w_fire) begin
			if (((w_pending_n == 0) || !tx_n[w_head_n][88]) || tx_n[w_head_n][86])
				error_n = 8'd4;
			else begin
				tx_n[w_head_n][8-:9] = tx_n[w_head_n][8-:9] + 9'd1;
				if (wlast_seen != (tx_n[w_head_n][8-:9] == tx_n[w_head_n][17-:9]))
					error_n = 8'd5;
				if (tx_n[w_head_n][87]) begin
					first_byte = 5'd16;
					byte_count = strobe_bytes(wstrb_seen);
					begin : sv2v_autoblock_3
						integer lane;
						for (lane = 15; lane >= 0; lane = lane - 1)
							if (wstrb_seen[lane])
								first_byte = sv2v_cast_5_signed(lane);
					end
					if (byte_count != 0)
						contiguous = (16'hffff >> (5'd16 - byte_count)) << first_byte;
					effective_address = ({1'b0, tx_n[w_head_n][81-:32]} + (({24'b000000000000000000000000, tx_n[w_head_n][8-:9]} - 33'd1) << 4)) + sv2v_cast_33(first_byte);
					expected_address = {1'b0, tracked_fb} + {1'b0, accepted_n};
					if ((((byte_count == 0) || (wstrb_seen != contiguous)) || (effective_address != expected_address)) || ((accepted_n + sv2v_cast_32(byte_count)) > FRAME_BYTES))
						error_n = 8'd6;
					else begin
						accepted_n = accepted_n + sv2v_cast_32(byte_count);
						tx_n[w_head_n][49-:32] = tx_n[w_head_n][49-:32] + sv2v_cast_32(byte_count);
					end
				end
				if (wlast_seen) begin
					tx_n[w_head_n][86] = 1;
					w_head_n = w_head_n + 1'b1;
					w_pending_n = w_pending_n - 1'b1;
				end
			end
		end
		if (b_fire) begin
			if ((((pending_n == 0) || !tx_n[b_head_n][88]) || !tx_n[b_head_n][86]) || (bid_seen != tx_n[b_head_n][85-:4]))
				error_n = 8'd7;
			else begin
				if (bresp_seen != 0)
					error_n = 8'd8;
				if (tx_n[b_head_n][87] && (bresp_seen == 0))
					committed_n = committed_n + tx_n[b_head_n][49-:32];
				if (tx_n[b_head_n][87])
					frame_pending_n = frame_pending_n - 1'b1;
				tx_n[b_head_n] = 1'sb0;
				b_head_n = b_head_n + 1'b1;
				pending_n = pending_n - 1'b1;
			end
		end
		if (armed && axi_poisoned)
			error_n = 8'd9;
	end
	always @(posedge clk)
		if (rst) begin
			rsp_valid <= 0;
			rsp_error <= 0;
			rsp_rdata <= 0;
			aw_tail <= 0;
			b_head <= 0;
			w_head <= 0;
			pending <= 0;
			w_pending <= 0;
			frame_pending <= 0;
			scope_fault <= 0;
			begin : sv2v_autoblock_4
				integer i;
				for (i = 0; i < TRACK_DEPTH; i = i + 1)
					tx[i] <= 1'sb0;
			end
			armed <= 0;
			ready_flag <= 0;
			nms_done <= 0;
			active_valid <= 0;
			error_code <= 0;
			accepted_bytes <= 0;
			committed_bytes <= 0;
			tracked_fb <= 0;
			shadow_fb <= 0;
			shadow_frame <= 0;
			shadow_xy1 <= 0;
			shadow_xy2 <= 0;
			shadow_score <= 0;
			shadow_class <= 0;
			shadow_count <= 0;
			active_fb <= 0;
			active_frame <= 0;
			active_xy1 <= 0;
			active_xy2 <= 0;
			active_score <= 0;
			active_class <= 0;
			active_count <= 0;
			commit_sequence <= 0;
			shadow_run <= 0;
			active_run <= 0;
			publish_valid <= 0;
			cpu_gray_meta <= 0;
			cpu_gray_sync <= 0;
			cpu_ticks <= 0;
			tf_ticks <= 0;
			tr_ticks <= 0;
			tf_recorded <= 0;
		end
		else begin
			cpu_gray_meta <= cpu_time_gray;
			cpu_gray_sync <= cpu_gray_meta;
			cpu_ticks <= cpu_binary;
			aw_tail <= aw_tail_n;
			b_head <= b_head_n;
			w_head <= w_head_n;
			pending <= pending_n;
			w_pending <= w_pending_n;
			frame_pending <= frame_pending_n;
			scope_fault <= scope_fault_n;
			begin : sv2v_autoblock_5
				integer i;
				for (i = 0; i < TRACK_DEPTH; i = i + 1)
					tx[i] <= tx_n[i];
			end
			error_code <= error_n;
			accepted_bytes <= accepted_n;
			committed_bytes <= committed_n;
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			if (publish_valid && publish_ready)
				publish_valid <= 0;
			if ((((armed && (error_code == 0)) && (committed_bytes == FRAME_BYTES)) && (SCOPED_WRITER ? (frame_pending == 0) && !tracked_aw_hit : ((((pending == 0) && !observation_pending) && !awvalid) && !wvalid) && !bvalid)) && !tf_recorded) begin
				tf_ticks <= last_b_ticks;
				tf_recorded <= 1;
			end
			if (access) begin
				rsp_valid <= 1;
				rsp_error <= 0;
				rsp_rdata <= 0;
				if (((req_addr[11:8] != MMIO_PAGE) || (req_addr[1:0] != 0)) || (req_write && (req_wstrb != 4'hf)))
					rsp_error <= 1;
				else if (req_write)
					case (off)
						8'h00:
							if (req_wdata == 1) begin
								ready_flag <= 0;
								if ((((((((((((((!ddr_ready || axi_poisoned) || armed) || scope_fault) || (pending != 0)) || observation_pending) || awvalid) || wvalid) || bvalid) || shadow_aw_hit) || (shadow_fb[3:0] != 0)) || (shadow_fb < FB_MIN)) || (({1'b0, shadow_fb} + FRAME_BYTES) > {1'b0, FB_LIMIT})) || (active_valid && (shadow_fb == active_fb))) || (REQUIRE_PRESENT_ACK && ((publish_valid || (display_valid && (shadow_fb == display_fb))) || (pending_display_valid && (shadow_fb == pending_display_fb))))) begin
									armed <= 0;
									error_code <= 8'd10;
								end
								else begin
									armed <= 1;
									tracked_fb <= shadow_fb;
									nms_done <= 0;
									error_code <= 0;
									accepted_bytes <= 0;
									committed_bytes <= 0;
									tf_ticks <= 0;
									tr_ticks <= 0;
									tf_recorded <= 0;
								end
							end
							else if (req_wdata == 2) begin
								if (!armed)
									error_code <= 8'd11;
								else
									nms_done <= 1;
							end
							else if (req_wdata == 4) begin
								if (((((((((!armed || !nms_done) || (error_code != 0)) || axi_poisoned) || !metadata_ok) || (shadow_fb != tracked_fb)) || (accepted_bytes != FRAME_BYTES)) || (committed_bytes != FRAME_BYTES)) || (SCOPED_WRITER ? (frame_pending != 0) || tracked_aw_hit : ((((pending != 0) || observation_pending) || awvalid) || wvalid) || bvalid)) || (REQUIRE_PRESENT_ACK && publish_valid))
									error_code <= (error_n != 0 ? error_n : 8'd12);
								else begin
									active_fb <= tracked_fb;
									active_frame <= shadow_frame;
									active_xy1 <= (shadow_count ? shadow_xy1 : 0);
									active_xy2 <= (shadow_count ? shadow_xy2 : 0);
									active_score <= (shadow_count ? shadow_score : 0);
									active_class <= (shadow_count ? shadow_class : 0);
									active_count <= shadow_count;
									active_valid <= 1;
									active_run <= shadow_run;
									commit_sequence <= commit_sequence + 1'b1;
									publish_valid <= REQUIRE_PRESENT_ACK;
									tr_ticks <= cpu_ticks;
									ready_flag <= 1;
									armed <= 0;
								end
							end
							else if (req_wdata == 8) begin
								if (((((pending != 0) || observation_pending) || awvalid) || wvalid) || bvalid)
									error_code <= 8'd10;
								else begin
									armed <= 0;
									ready_flag <= 0;
									nms_done <= 0;
									error_code <= 0;
									accepted_bytes <= 0;
									committed_bytes <= 0;
								end
							end
							else if (req_wdata == 16) begin
								if (((((((((((((((!SCOPED_WRITER || !ddr_ready) || armed) || !active_valid) || !metadata_ok) || axi_poisoned) || (pending != 0)) || observation_pending) || awvalid) || wvalid) || bvalid) || publish_valid) || pending_display_valid) || !display_valid) || (display_fb != active_fb)) || (shadow_fb != active_fb))
									error_code <= 8'd12;
								else begin
									active_frame <= shadow_frame;
									active_run <= shadow_run;
									active_xy1 <= (shadow_count ? shadow_xy1 : 0);
									active_xy2 <= (shadow_count ? shadow_xy2 : 0);
									active_score <= (shadow_count ? shadow_score : 0);
									active_class <= (shadow_count ? shadow_class : 0);
									active_count <= shadow_count;
									commit_sequence <= commit_sequence + 1'b1;
									publish_valid <= REQUIRE_PRESENT_ACK;
									tr_ticks <= cpu_ticks;
									ready_flag <= 1;
									error_code <= 0;
								end
							end
							else
								rsp_error <= 1;
						8'h08:
							if (armed)
								rsp_error <= 1;
							else
								shadow_fb <= req_wdata;
						8'h0c: shadow_frame <= req_wdata;
						8'h10: shadow_xy1 <= req_wdata;
						8'h14: shadow_xy2 <= req_wdata;
						8'h18: shadow_score <= req_wdata;
						8'h1c: shadow_class <= req_wdata;
						8'h20: shadow_count <= req_wdata;
						8'h54: shadow_run <= req_wdata;
						default: rsp_error <= 1;
					endcase
				else
					case (off)
						8'h00: rsp_rdata <= 32'h31505344;
						8'h04: rsp_rdata <= {SCOPED_WRITER, 7'b0000000, error_code, 11'b00000000000, active_valid, nms_done, ready_flag, armed, ddr_ready};
						8'h08: rsp_rdata <= shadow_fb;
						8'h0c: rsp_rdata <= shadow_frame;
						8'h24: rsp_rdata <= accepted_bytes;
						8'h28: rsp_rdata <= committed_bytes;
						8'h2c: rsp_rdata <= (SCOPED_WRITER ? sv2v_cast_32(frame_pending) : sv2v_cast_32(pending));
						8'h30: rsp_rdata <= active_fb;
						8'h34: rsp_rdata <= active_frame;
						8'h38: rsp_rdata <= active_xy1;
						8'h3c: rsp_rdata <= active_xy2;
						8'h40: rsp_rdata <= active_score;
						8'h44: rsp_rdata <= active_class;
						8'h48: rsp_rdata <= active_count;
						8'h4c: rsp_rdata <= commit_sequence;
						8'h50: rsp_rdata <= FRAME_BYTES;
						8'h54: rsp_rdata <= shadow_run;
						8'h58: rsp_rdata <= active_run;
						8'h5c: rsp_rdata <= {31'b0000000000000000000000000000000, publish_valid};
						8'h60: rsp_rdata <= tf_ticks[31:0];
						8'h64: rsp_rdata <= tf_ticks[63:32];
						8'h68: rsp_rdata <= tr_ticks[31:0];
						8'h6c: rsp_rdata <= tr_ticks[63:32];
						8'h70: rsp_rdata <= {31'b0000000000000000000000000000000, SCOPED_WRITER};
						8'h74: rsp_rdata <= sv2v_cast_32(pending);
						8'h78: rsp_rdata <= {31'b0000000000000000000000000000000, scope_fault};
						8'h84: rsp_rdata <= {27'b000000000000000000000000000, scope_fault, 1'b0, publish_valid, pending_display_valid, display_valid};
						8'h88: rsp_rdata <= display_fb;
						8'h8c: rsp_rdata <= pending_display_fb;
						default: rsp_error <= 1;
					endcase
			end
		end
	initial if (((TRACK_DEPTH < 2) || ((TRACK_DEPTH & (TRACK_DEPTH - 1)) != 0)) || ((FRAME_BYTES % 16) != 0)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_display_commit_mmio.sv:381:13 - soc_display_commit_mmio.<unnamed_block>.<unnamed_block>\n msg: ", $time, "DISPLAY_COMMIT_BAD_PARAMETERS");
		$finish(1);
	end
	initial _sv2v_0 = 0;
endmodule
module soc_video_event_mmio (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	test_pattern,
	event_tc,
	event_th,
	event_te,
	te_good,
	tc_ticks,
	th_ticks,
	te_ticks,
	tc_frame,
	tc_run,
	th_frame,
	th_run,
	te_frame,
	te_run,
	stat_underflow,
	stat_mismatch,
	stat_presented,
	stat_max_ddr_wait,
	stat_fifo_high,
	stat_fifo_low,
	video_fault
);
	input wire clk;
	input wire rst;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output reg [1:0] test_pattern;
	input wire event_tc;
	input wire event_th;
	input wire event_te;
	input wire te_good;
	input wire [63:0] tc_ticks;
	input wire [63:0] th_ticks;
	input wire [63:0] te_ticks;
	input wire [31:0] tc_frame;
	input wire [31:0] tc_run;
	input wire [31:0] th_frame;
	input wire [31:0] th_run;
	input wire [31:0] te_frame;
	input wire [31:0] te_run;
	input wire [31:0] stat_underflow;
	input wire [31:0] stat_mismatch;
	input wire [31:0] stat_presented;
	input wire [31:0] stat_max_ddr_wait;
	input wire [31:0] stat_fifo_high;
	input wire [31:0] stat_fifo_low;
	input wire [7:0] video_fault;
	reg armed;
	reg seen_tc;
	reg seen_th;
	reg seen_te;
	reg frame_good;
	reg [31:0] expected_frame;
	reg [31:0] expected_run;
	reg [31:0] underflow_before;
	reg [63:0] captured_tc;
	reg [63:0] captured_th;
	reg [63:0] captured_te;
	wire [7:0] off = {req_addr[7:2], 2'b00};
	assign req_ready = !rsp_valid || rsp_ready;
	always @(posedge clk)
		if (rst) begin
			rsp_valid <= 0;
			rsp_rdata <= 0;
			rsp_error <= 0;
			test_pattern <= 1;
			armed <= 0;
			seen_tc <= 0;
			seen_th <= 0;
			seen_te <= 0;
			frame_good <= 0;
			expected_frame <= 0;
			expected_run <= 0;
			underflow_before <= 0;
			captured_tc <= 0;
			captured_th <= 0;
			captured_te <= 0;
		end
		else begin
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			if (armed) begin
				if (((event_tc && !seen_tc) && (tc_frame == expected_frame)) && (tc_run == expected_run)) begin
					seen_tc <= 1;
					captured_tc <= tc_ticks;
				end
				if (((event_th && !seen_th) && (th_frame == expected_frame)) && (th_run == expected_run)) begin
					seen_th <= 1;
					captured_th <= th_ticks;
				end
				if (((event_te && !seen_te) && (te_frame == expected_frame)) && (te_run == expected_run)) begin
					seen_te <= 1;
					captured_te <= te_ticks;
					frame_good <= te_good;
				end
			end
			if (req_valid && req_ready) begin
				rsp_valid <= 1;
				rsp_error <= 0;
				rsp_rdata <= 0;
				if (((req_addr[11:8] != 4'h6) || (req_addr[1:0] != 0)) || (req_write && (req_wstrb != 4'hf)))
					rsp_error <= 1;
				else if (req_write)
					case (off)
						8'h00:
							if (req_wdata == 1) begin
								armed <= 1;
								seen_tc <= 0;
								seen_th <= 0;
								seen_te <= 0;
								frame_good <= 0;
								captured_tc <= 0;
								captured_th <= 0;
								captured_te <= 0;
								underflow_before <= stat_underflow;
							end
							else if (req_wdata == 0)
								armed <= 0;
							else
								rsp_error <= 1;
						8'h08:
							if (armed)
								rsp_error <= 1;
							else
								expected_run <= req_wdata;
						8'h0c:
							if (armed)
								rsp_error <= 1;
							else
								expected_frame <= req_wdata;
						8'h10:
							if (req_wdata > 2)
								rsp_error <= 1;
							else
								test_pattern <= req_wdata[1:0];
						default: rsp_error <= 1;
					endcase
				else
					case (off)
						8'h00: rsp_rdata <= 32'h32544956;
						8'h04: rsp_rdata <= {27'b000000000000000000000000000, frame_good, seen_te, seen_th, seen_tc, armed};
						8'h08: rsp_rdata <= expected_run;
						8'h0c: rsp_rdata <= expected_frame;
						8'h10: rsp_rdata <= {30'b000000000000000000000000000000, test_pattern};
						8'h14: rsp_rdata <= stat_underflow;
						8'h18: rsp_rdata <= stat_mismatch;
						8'h1c: rsp_rdata <= stat_presented;
						8'h20: rsp_rdata <= stat_max_ddr_wait;
						8'h24: rsp_rdata <= stat_fifo_high;
						8'h28: rsp_rdata <= stat_fifo_low;
						8'h2c: rsp_rdata <= {24'b000000000000000000000000, video_fault};
						8'h30: rsp_rdata <= captured_tc[31:0];
						8'h34: rsp_rdata <= captured_tc[63:32];
						8'h38: rsp_rdata <= captured_th[31:0];
						8'h3c: rsp_rdata <= captured_th[63:32];
						8'h40: rsp_rdata <= captured_te[31:0];
						8'h44: rsp_rdata <= captured_te[63:32];
						8'h48: rsp_rdata <= underflow_before;
						8'h4c: rsp_rdata <= 32'd12;
						default: rsp_error <= 1;
					endcase
			end
		end
endmodule
module soc_hdmi_axi_reader (
	clk,
	rst,
	start,
	abort,
	frame_base,
	frame_pixels,
	ready,
	busy,
	done_pulse,
	frame_valid,
	error_sticky,
	pixels_emitted,
	max_wait_cycles,
	pixel_valid,
	pixel_ready,
	pixel_data,
	pixel_last,
	m_arid,
	m_araddr,
	m_arlen,
	m_arsize,
	m_arburst,
	m_arvalid,
	m_arready,
	m_rid,
	m_rdata,
	m_rresp,
	m_rlast,
	m_rvalid,
	m_rready
);
	parameter [31:0] VIDEO_BASE = 32'h81000000;
	parameter [31:0] VIDEO_BYTES = 32'h02000000;
	parameter signed [31:0] MAX_PIXELS = 5038848;
	parameter [0:0] ENABLE_ABORT = 0;
	parameter signed [31:0] WAIT_LIMIT = 0;
	input wire clk;
	input wire rst;
	input wire start;
	input wire abort;
	input wire [31:0] frame_base;
	input wire [31:0] frame_pixels;
	output wire ready;
	output wire busy;
	output reg done_pulse;
	output reg frame_valid;
	output reg [7:0] error_sticky;
	output reg [31:0] pixels_emitted;
	output reg [31:0] max_wait_cycles;
	output wire pixel_valid;
	input wire pixel_ready;
	output wire [15:0] pixel_data;
	output wire pixel_last;
	output wire [3:0] m_arid;
	output wire [31:0] m_araddr;
	output wire [7:0] m_arlen;
	output wire [2:0] m_arsize;
	output wire [1:0] m_arburst;
	output wire m_arvalid;
	input wire m_arready;
	input wire [3:0] m_rid;
	input wire [127:0] m_rdata;
	input wire [1:0] m_rresp;
	input wire m_rlast;
	input wire m_rvalid;
	output wire m_rready;
	reg [2:0] state;
	reg [31:0] base_q;
	reg [31:0] target_q;
	(* ram_style = "distributed" *) reg [127:0] burst_data [0:15];
	reg [4:0] burst_beats_q;
	reg [4:0] beat_index_q;
	reg [4:0] emit_index_q;
	reg [3:0] lane_q;
	reg [3:0] beat_pixels_q;
	wire [33:0] frame_end;
	wire valid_config;
	wire [31:0] remaining;
	wire [4:0] next_burst_beats;
	reg cancelled;
	reg [31:0] wait_cycles;
	wire do_abort = ENABLE_ABORT && abort;
	assign frame_end = {2'b00, frame_base} + {1'b0, frame_pixels, 1'b0};
	assign valid_config = ((((frame_base[3:0] == 0) && (frame_pixels != 0)) && (frame_pixels <= MAX_PIXELS)) && (frame_base >= VIDEO_BASE)) && (frame_end <= ({2'b00, VIDEO_BASE} + {2'b00, VIDEO_BYTES}));
	assign remaining = target_q - pixels_emitted;
	wire [12:0] bytes_to_page = 13'd4096 - {1'b0, m_araddr[11:0]};
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	wire [8:0] beats_to_page = sv2v_cast_9(bytes_to_page >> 4);
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	wire [4:0] beats_for_pixels = (remaining >= 32'd128 ? 5'd16 : sv2v_cast_5((remaining + 7) >> 3));
	assign next_burst_beats = (beats_to_page < sv2v_cast_9(beats_for_pixels) ? sv2v_cast_5(beats_to_page) : beats_for_pixels);
	assign ready = (state == 3'd0) && !rst;
	assign busy = state != 3'd0;
	assign m_arid = 4'hd;
	assign m_araddr = base_q + (pixels_emitted << 1);
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	assign m_arlen = sv2v_cast_8(next_burst_beats - 1'b1);
	assign m_arsize = 3'd4;
	assign m_arburst = 2'b01;
	assign m_arvalid = state == 3'd1;
	assign m_rready = (state == 3'd2) || (state == 3'd4);
	assign pixel_valid = state == 3'd3;
	assign pixel_data = burst_data[emit_index_q[3:0]][16 * lane_q[2:0]+:16];
	assign pixel_last = pixel_valid && ((pixels_emitted + 1) == target_q);
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	always @(posedge clk) begin
		done_pulse <= 0;
		if (rst) begin
			state <= 3'd0;
			base_q <= 0;
			target_q <= 0;
			burst_beats_q <= 0;
			beat_index_q <= 0;
			emit_index_q <= 0;
			lane_q <= 0;
			beat_pixels_q <= 0;
			pixels_emitted <= 0;
			error_sticky <= 0;
			frame_valid <= 0;
			cancelled <= 0;
			wait_cycles <= 0;
			max_wait_cycles <= 0;
		end
		else begin
			if ((state != 3'd0) && do_abort)
				cancelled <= 1;
			if (((state == 3'd1) && !m_arready) || (((state == 3'd2) || (state == 3'd4)) && !m_rvalid)) begin
				if (wait_cycles != 32'hffffffff)
					wait_cycles <= wait_cycles + 1'b1;
				if (wait_cycles >= max_wait_cycles)
					max_wait_cycles <= wait_cycles + 1'b1;
				if ((WAIT_LIMIT > 0) && (wait_cycles >= (WAIT_LIMIT - 1)))
					error_sticky[3] <= 1;
			end
			else
				wait_cycles <= 0;
			case (state)
				3'd0:
					if (start) begin
						base_q <= frame_base;
						target_q <= frame_pixels;
						pixels_emitted <= 0;
						error_sticky <= 0;
						frame_valid <= 0;
						beat_index_q <= 0;
						emit_index_q <= 0;
						lane_q <= 0;
						cancelled <= 0;
						if (valid_config)
							state <= 3'd1;
						else begin
							error_sticky[0] <= 1;
							done_pulse <= 1;
						end
					end
				3'd1:
					if (m_arready) begin
						burst_beats_q <= next_burst_beats;
						beat_index_q <= 0;
						state <= (cancelled || do_abort ? 3'd4 : 3'd2);
					end
				3'd2:
					if (m_rvalid) begin
						if (cancelled || do_abort) begin
							if (m_rlast) begin
								done_pulse <= 1;
								state <= 3'd0;
							end
							else
								state <= 3'd4;
						end
						else if (((m_rid != 4'hd) || (m_rresp != 2'b00)) || (m_rlast != ((beat_index_q + 1) == burst_beats_q))) begin
							error_sticky[1] <= (m_rid != 4'hd) || (m_rresp != 2'b00);
							error_sticky[2] <= m_rlast != ((beat_index_q + 1) == burst_beats_q);
							if (m_rlast) begin
								done_pulse <= 1;
								state <= 3'd0;
							end
							else
								state <= 3'd4;
						end
						else begin
							burst_data[beat_index_q[3:0]] <= m_rdata;
							if ((beat_index_q + 1) == burst_beats_q) begin
								emit_index_q <= 0;
								lane_q <= 0;
								beat_pixels_q <= (remaining >= 32'd8 ? 4'd8 : sv2v_cast_4(remaining));
								state <= 3'd3;
							end
							else
								beat_index_q <= beat_index_q + 1;
						end
					end
				3'd3:
					if (cancelled || do_abort) begin
						done_pulse <= 1;
						state <= 3'd0;
					end
					else if (pixel_ready) begin
						pixels_emitted <= pixels_emitted + 1;
						if ((lane_q + 1) == beat_pixels_q) begin
							if ((pixels_emitted + 1) == target_q) begin
								frame_valid <= 1;
								done_pulse <= 1;
								state <= 3'd0;
							end
							else if ((emit_index_q + 1) == burst_beats_q)
								state <= 3'd1;
							else begin
								emit_index_q <= emit_index_q + 1;
								lane_q <= 0;
								beat_pixels_q <= (remaining > 32'd9 ? 4'd8 : sv2v_cast_4(remaining - 1'b1));
							end
						end
						else
							lane_q <= lane_q + 1;
					end
				3'd4:
					if (m_rvalid && m_rlast) begin
						done_pulse <= 1;
						state <= 3'd0;
					end
				default: state <= 3'd0;
			endcase
		end
	end
	initial if (((VIDEO_BASE[7:0] != 0) || (VIDEO_BYTES < 256)) || (MAX_PIXELS < 1)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_hdmi_axi_reader.sv:143:9 - soc_hdmi_axi_reader.<unnamed_block>\n msg: ", $time, "VIDEO_REPLAY_PARAMETER");
		$finish(1);
	end
endmodule
module soc_display_async_fifo (
	wr_clk,
	rd_clk,
	arst,
	in_valid,
	in_ready,
	in_data,
	out_valid,
	out_ready,
	out_data,
	wr_level
);
	reg _sv2v_0;
	parameter signed [31:0] WIDTH = 44;
	parameter signed [31:0] DEPTH = 4096;
	input wire wr_clk;
	input wire rd_clk;
	input wire arst;
	input wire in_valid;
	output wire in_ready;
	input wire [WIDTH - 1:0] in_data;
	output wire out_valid;
	input wire out_ready;
	output wire [WIDTH - 1:0] out_data;
	output wire [$clog2(DEPTH):0] wr_level;
	localparam signed [31:0] AW = $clog2(DEPTH);
	localparam signed [31:0] PW = AW + 1;
	wire wr_rst;
	wire rd_rst;
	pg_reset_sync wr_release(
		.clk(wr_clk),
		.arst(arst),
		.rst(wr_rst)
	);
	pg_reset_sync rd_release(
		.clk(rd_clk),
		.arst(arst),
		.rst(rd_rst)
	);
	reg [PW - 1:0] wb;
	reg [PW - 1:0] rb;
	reg [PW - 1:0] wg;
	reg [PW - 1:0] rg;
	wire [PW - 1:0] wn;
	wire [PW - 1:0] rn;
	wire [PW - 1:0] wgn;
	wire [PW - 1:0] rgn;
	reg [PW - 1:0] rb_sync;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] rmeta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] rsync;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] wmeta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PW - 1:0] wsync;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg rumeta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg rusync;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg wumeta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg wusync;
	reg full;
	reg empty;
	wire push;
	wire load;
	reg valid;
	reg [WIDTH - 1:0] data;
	(* ram_style = "block" *) reg [WIDTH - 1:0] mem [0:DEPTH - 1];
	assign in_ready = (!wr_rst && rusync) && !full;
	assign out_valid = (!rd_rst && wusync) && valid;
	assign out_data = data;
	assign push = in_valid && in_ready;
	assign load = ((!rd_rst && wusync) && !empty) && (!valid || out_ready);
	function automatic [PW - 1:0] sv2v_cast_D1740;
		input reg [PW - 1:0] inp;
		sv2v_cast_D1740 = inp;
	endfunction
	assign wn = wb + sv2v_cast_D1740(push);
	assign rn = rb + sv2v_cast_D1740(load);
	assign wgn = (wn >> 1) ^ wn;
	assign rgn = (rn >> 1) ^ rn;
	always @(*) begin
		if (_sv2v_0)
			;
		rb_sync[PW - 1] = rsync[PW - 1];
		begin : sv2v_autoblock_1
			integer i;
			for (i = PW - 2; i >= 0; i = i - 1)
				rb_sync[i] = rb_sync[i + 1] ^ rsync[i];
		end
	end
	assign wr_level = wb - rb_sync;
	function automatic signed [PW - 1:0] sv2v_cast_D1740_signed;
		input reg signed [PW - 1:0] inp;
		sv2v_cast_D1740_signed = inp;
	endfunction
	always @(posedge wr_clk or posedge wr_rst)
		if (wr_rst) begin
			wb <= 0;
			wg <= 0;
			full <= 0;
			rmeta <= 0;
			rsync <= 0;
			rumeta <= 0;
			rusync <= 0;
		end
		else begin
			rmeta <= rg;
			rsync <= rmeta;
			rumeta <= !rd_rst;
			rusync <= rumeta;
			wb <= wn;
			wg <= wgn;
			full <= wgn == (rsync ^ (sv2v_cast_D1740_signed(3) << (PW - 2)));
		end
	always @(posedge rd_clk or posedge rd_rst)
		if (rd_rst) begin
			rb <= 0;
			rg <= 0;
			empty <= 1;
			valid <= 0;
			wmeta <= 0;
			wsync <= 0;
			wumeta <= 0;
			wusync <= 0;
		end
		else begin
			wmeta <= wg;
			wsync <= wmeta;
			wumeta <= !wr_rst;
			wusync <= wumeta;
			rb <= rn;
			rg <= rgn;
			empty <= rgn == wsync;
			if (load)
				valid <= 1;
			else if (out_valid && out_ready)
				valid <= 0;
		end
	always @(posedge wr_clk)
		if (push)
			mem[wb[AW - 1:0]] <= in_data;
	always @(posedge rd_clk)
		if (load)
			data <= mem[rb[AW - 1:0]];
	initial if ((DEPTH < 2) || ((DEPTH & (DEPTH - 1)) != 0)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_display_async_fifo.sv:49:43 - soc_display_async_fifo.<unnamed_block>\n msg: ", $time, "DISPLAY_FIFO_PARAMETER");
		$finish(1);
	end
	initial _sv2v_0 = 0;
endmodule
module soc_stereo_osd (
	clk,
	rst,
	vblank,
	displayed_left_id,
	displayed_right_id,
	cfg_valid,
	cfg_enable,
	cfg_left_id,
	cfg_right_id,
	cfg_x1,
	cfg_x2,
	cfg_y1,
	cfg_y2,
	pixel_valid,
	pixel_x,
	pixel_y,
	pixel_rgb,
	pixel_out_valid,
	pixel_out_rgb,
	box_active,
	cfg_error
);
	parameter signed [31:0] X_MIN = 640;
	parameter signed [31:0] X_LIMIT = 1280;
	parameter signed [31:0] Y_MIN = 120;
	parameter signed [31:0] Y_LIMIT = 600;
	input wire clk;
	input wire rst;
	input wire vblank;
	input wire [31:0] displayed_left_id;
	input wire [31:0] displayed_right_id;
	input wire cfg_valid;
	input wire cfg_enable;
	input wire [31:0] cfg_left_id;
	input wire [31:0] cfg_right_id;
	input wire [10:0] cfg_x1;
	input wire [10:0] cfg_x2;
	input wire [9:0] cfg_y1;
	input wire [9:0] cfg_y2;
	input wire pixel_valid;
	input wire [10:0] pixel_x;
	input wire [9:0] pixel_y;
	input wire [23:0] pixel_rgb;
	output reg pixel_out_valid;
	output reg [23:0] pixel_out_rgb;
	output reg box_active;
	output reg cfg_error;
	reg shadow_valid;
	reg shadow_enable;
	reg [31:0] shadow_left_id;
	reg [31:0] shadow_right_id;
	reg [10:0] shadow_x1;
	reg [10:0] shadow_x2;
	reg [10:0] active_x1;
	reg [10:0] active_x2;
	reg [9:0] shadow_y1;
	reg [9:0] shadow_y2;
	reg [9:0] active_y1;
	reg [9:0] active_y2;
	wire border;
	wire cfg_bounds_ok = (((((cfg_x1 >= X_MIN) && (cfg_x2 <= X_LIMIT)) && (cfg_x1 < cfg_x2)) && (cfg_y1 >= Y_MIN)) && (cfg_y2 <= Y_LIMIT)) && (cfg_y1 < cfg_y2);
	assign border = (((((box_active && pixel_valid) && (pixel_x >= active_x1)) && (pixel_x < active_x2)) && (pixel_y >= active_y1)) && (pixel_y < active_y2)) && ((((pixel_x == active_x1) || (pixel_x == (active_x2 - 11'd1))) || (pixel_y == active_y1)) || (pixel_y == (active_y2 - 10'd1)));
	always @(posedge clk)
		if (rst) begin
			shadow_valid <= 0;
			shadow_enable <= 0;
			shadow_left_id <= 0;
			shadow_right_id <= 0;
			shadow_x1 <= 0;
			shadow_x2 <= 0;
			shadow_y1 <= 0;
			shadow_y2 <= 0;
			active_x1 <= 0;
			active_x2 <= 0;
			active_y1 <= 0;
			active_y2 <= 0;
			box_active <= 0;
			cfg_error <= 0;
			pixel_out_valid <= 0;
			pixel_out_rgb <= 0;
		end
		else begin
			pixel_out_valid <= pixel_valid;
			pixel_out_rgb <= (border ? 24'h00ff00 : pixel_rgb);
			if (cfg_valid) begin
				shadow_valid <= 1;
				shadow_enable <= cfg_enable;
				shadow_left_id <= cfg_left_id;
				shadow_right_id <= cfg_right_id;
				shadow_x1 <= cfg_x1;
				shadow_x2 <= cfg_x2;
				shadow_y1 <= cfg_y1;
				shadow_y2 <= cfg_y2;
				cfg_error <= cfg_enable && !((((((cfg_x1 >= X_MIN) && (cfg_x2 <= X_LIMIT)) && (cfg_x1 < cfg_x2)) && (cfg_y1 >= Y_MIN)) && (cfg_y2 <= Y_LIMIT)) && (cfg_y1 < cfg_y2));
			end
			if (vblank) begin
				if (cfg_valid) begin
					box_active <= ((cfg_enable && cfg_bounds_ok) && (cfg_left_id == displayed_left_id)) && (cfg_right_id == displayed_right_id);
					active_x1 <= cfg_x1;
					active_x2 <= cfg_x2;
					active_y1 <= cfg_y1;
					active_y2 <= cfg_y2;
				end
				else begin
					box_active <= (((shadow_valid && shadow_enable) && !cfg_error) && (shadow_left_id == displayed_left_id)) && (shadow_right_id == displayed_right_id);
					active_x1 <= shadow_x1;
					active_x2 <= shadow_x2;
					active_y1 <= shadow_y1;
					active_y2 <= shadow_y2;
				end
			end
		end
endmodule
module soc_hdmi_ddr_scanout (
	ui_clk,
	ui_rst,
	pix_clk,
	pix_rst,
	cpu_time_gray,
	test_pattern,
	publish_valid,
	publish_ready,
	publish_fb,
	publish_frame,
	publish_run,
	publish_xy1,
	publish_xy2,
	publish_score,
	publish_class,
	publish_count,
	publish_sequence,
	pending_valid,
	pending_fb,
	presented_valid,
	presented_fb,
	presented_frame,
	presented_run,
	m_arid,
	m_araddr,
	m_arlen,
	m_arsize,
	m_arburst,
	m_arvalid,
	m_arready,
	m_rid,
	m_rdata,
	m_rresp,
	m_rlast,
	m_rvalid,
	m_rready,
	video_rgb,
	video_de,
	video_hs,
	video_vs,
	event_tc,
	event_th,
	event_te,
	te_good,
	tc_ticks,
	th_ticks,
	te_ticks,
	tc_pixel_ticks,
	th_pixel_ticks,
	te_pixel_ticks,
	tc_frame,
	tc_run,
	th_frame,
	th_run,
	te_frame,
	te_run,
	stat_underflow,
	stat_mismatch,
	stat_presented,
	stat_max_ddr_wait,
	stat_fifo_high,
	stat_fifo_low,
	video_fault
);
	reg _sv2v_0;
	parameter [0:0] SINGLE_VIEW = 1;
	parameter signed [31:0] FIFO_DEPTH = 4096;
	parameter signed [31:0] WAIT_LIMIT = 1048576;
	parameter signed [31:0] TX_EXTRA_CYCLES = 0;
	parameter signed [31:0] W = 680;
	parameter signed [31:0] H = 340;
	parameter signed [31:0] H_ACTIVE = 720;
	parameter signed [31:0] H_FP = 16;
	parameter signed [31:0] H_SYNC = 62;
	parameter signed [31:0] H_BP = 60;
	parameter signed [31:0] V_ACTIVE = 480;
	parameter signed [31:0] V_FP = 9;
	parameter signed [31:0] V_SYNC = 6;
	parameter signed [31:0] V_BP = 30;
	parameter signed [31:0] X_START = 20;
	parameter signed [31:0] Y_START = 70;
	parameter [0:0] HS_NEGATIVE = 1;
	parameter [0:0] VS_NEGATIVE = 1;
	input wire ui_clk;
	input wire ui_rst;
	input wire pix_clk;
	input wire pix_rst;
	input wire [63:0] cpu_time_gray;
	input wire [1:0] test_pattern;
	input wire publish_valid;
	output wire publish_ready;
	input wire [31:0] publish_fb;
	input wire [31:0] publish_frame;
	input wire [31:0] publish_run;
	input wire [31:0] publish_xy1;
	input wire [31:0] publish_xy2;
	input wire [31:0] publish_score;
	input wire [31:0] publish_class;
	input wire [31:0] publish_count;
	input wire [31:0] publish_sequence;
	output reg pending_valid;
	output wire [31:0] pending_fb;
	output reg presented_valid;
	output reg [31:0] presented_fb;
	output reg [31:0] presented_frame;
	output reg [31:0] presented_run;
	output wire [3:0] m_arid;
	output wire [31:0] m_araddr;
	output wire [7:0] m_arlen;
	output wire [2:0] m_arsize;
	output wire [1:0] m_arburst;
	output wire m_arvalid;
	input wire m_arready;
	input wire [3:0] m_rid;
	input wire [127:0] m_rdata;
	input wire [1:0] m_rresp;
	input wire m_rlast;
	input wire m_rvalid;
	output wire m_rready;
	output wire [23:0] video_rgb;
	output wire video_de;
	output wire video_hs;
	output wire video_vs;
	output reg event_tc;
	output reg event_th;
	output reg event_te;
	output reg te_good;
	output reg [63:0] tc_ticks;
	output reg [63:0] th_ticks;
	output reg [63:0] te_ticks;
	output reg [63:0] tc_pixel_ticks;
	output reg [63:0] th_pixel_ticks;
	output reg [63:0] te_pixel_ticks;
	output reg [31:0] tc_frame;
	output reg [31:0] tc_run;
	output reg [31:0] th_frame;
	output reg [31:0] th_run;
	output reg [31:0] te_frame;
	output reg [31:0] te_run;
	output reg [31:0] stat_underflow;
	output reg [31:0] stat_mismatch;
	output reg [31:0] stat_presented;
	output wire [31:0] stat_max_ddr_wait;
	output reg [31:0] stat_fifo_high;
	output reg [31:0] stat_fifo_low;
	output reg [7:0] video_fault;
	localparam signed [31:0] HT = ((H_ACTIVE + H_FP) + H_SYNC) + H_BP;
	localparam signed [31:0] VT = ((V_ACTIVE + V_FP) + V_SYNC) + V_BP;
	localparam signed [31:0] EMIT_PER_ROW = (SINGLE_VIEW ? W : 2 * W);
	localparam signed [31:0] OUTPUT_HEIGHT = H;
	localparam signed [31:0] FW = 68;
	localparam signed [31:0] LP = $clog2(FIFO_DEPTH) + 1;
	localparam signed [31:0] PIPE = 1 + TX_EXTRA_CYCLES;
	reg [287:0] publication;
	reg [287:0] active;
	reg pub_toggle;
	reg ack_toggle;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg pub_meta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg pub_sync;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg ack_meta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg ack_sync;
	reg [11:0] x;
	reg [11:0] y;
	wire vblank = (x == 0) && (y == V_ACTIVE);
	wire de_raw = (x < H_ACTIVE) && (y < V_ACTIVE);
	wire hs_pulse = (x >= (H_ACTIVE + H_FP)) && (x < ((H_ACTIVE + H_FP) + H_SYNC));
	wire vs_pulse = (y >= (V_ACTIVE + V_FP)) && (y < ((V_ACTIVE + V_FP) + V_SYNC));
	wire hs_raw = (HS_NEGATIVE ? !hs_pulse : hs_pulse);
	wire vs_raw = (VS_NEGATIVE ? !vs_pulse : vs_pulse);
	wire image_slot = (((de_raw && (x >= X_START)) && (x < (X_START + EMIT_PER_ROW))) && (y >= Y_START)) && (y < (Y_START + OUTPUT_HEIGHT));
	reg active_valid;
	reg [1:0] mode_active;
	reg [1:0] mode_hold;
	reg mode_request;
	reg mode_ack;
	reg mode_wait;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg mode_meta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg mode_sync;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg mode_ack_meta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg mode_ack_sync;
	wire [1:0] next_mode = (mode_sync != mode_ack ? mode_hold : mode_active);
	reg [31:0] epoch;
	reg [31:0] scan_epoch;
	reg [31:0] scan_fb;
	reg scan_valid;
	reg scan_toggle;
	reg scan_ui_seen;
	reg scan_abort;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg scan_meta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg scan_sync;
	reg [31:0] reader_epoch;
	reg [31:0] reader_fb;
	reg [31:0] reader_index;
	reg [31:0] row;
	reg side;
	reg feed_enabled;
	reg reader_start;
	wire reader_busy;
	wire reader_done;
	wire reader_ready;
	wire [7:0] reader_error;
	wire reader_frame_valid;
	wire pv;
	wire pr;
	wire plast;
	wire [15:0] pdata;
	wire [31:0] reader_pixels;
	wire [31:0] row_addr;
	(* ram_style = "block", syn_ramstyle = "block_ram" *) reg [15:0] row_cache [0:2047];
	reg [1:0] row_ready;
	reg load_bank;
	reg emit_bank;
	reg load_complete;
	reg [9:0] load_column;
	reg [11:0] emit_column;
	reg [31:0] issue_index;
	reg row_out_valid;
	reg row_out_last;
	reg [15:0] row_out_pixel;
	reg [19:0] row_out_index;
	wire fifo_accept;
	wire row_out_fire = ((row_out_valid && fifo_accept) && feed_enabled) && !scan_abort;
	wire row_read_issue = (((feed_enabled && !scan_abort) && row_ready[emit_bank]) && (!row_out_valid || fifo_accept)) && !(row_out_valid && row_out_last);
	function automatic [9:0] sv2v_cast_10;
		input reg [9:0] inp;
		sv2v_cast_10 = inp;
	endfunction
	wire [9:0] cache_read_column = (SINGLE_VIEW ? sv2v_cast_10(emit_column) : sv2v_cast_10((emit_column >= W ? emit_column - W : emit_column)));
	wire [10:0] cache_read_address = {emit_bank, cache_read_column};
	wire cache_write = ((pv && pr) && feed_enabled) && !scan_abort;
	always @(posedge ui_clk) begin
		if (cache_write)
			row_cache[{load_bank, load_column}] <= pdata;
		if (row_read_issue)
			row_out_pixel <= row_cache[cache_read_address];
	end
	wire fifo_valid;
	wire fifo_ready;
	wire fifo_push;
	wire [67:0] fifo_data;
	wire [LP - 1:0] fifo_level;
	wire [19:0] expect_index;
	wire [31:0] fifo_epoch;
	wire [19:0] fifo_index;
	wire [15:0] fifo_pixel;
	wire match_pixel;
	wire stale_pixel;
	reg [23:0] rgb_raw;
	reg [23:0] bars;
	wire [23:0] rgb_labeled;
	wire label_active;
	wire osd_valid;
	wire box_active;
	wire osd_error;
	reg [PIPE - 1:0] hs_pipe;
	reg [PIPE - 1:0] vs_pipe;
	reg [PIPE - 1:0] de_pipe;
	reg [PIPE - 1:0] th_pipe;
	reg [PIPE - 1:0] te_pipe;
	reg [31:0] underflow_count;
	reg [31:0] mismatch_count;
	reg [31:0] presented_count;
	reg frame_bad;
	reg th_delivered;
	reg [63:0] pixel_ticks;
	reg [63:0] cpu_ticks;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [63:0] cpu_gray_meta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [63:0] cpu_gray_sync;
	reg [63:0] cpu_binary;
	reg tc_toggle;
	reg th_toggle;
	reg te_toggle;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [2:0] evt_meta;
	(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [2:0] evt_sync;
	reg [2:0] evt_seen;
	reg [319:0] tc_hold;
	reg [319:0] th_hold;
	reg [319:0] te_hold;
	reg te_good_hold;
	assign publish_ready = !pending_valid;
	assign pending_fb = publication[287-:32];
	always @(posedge ui_clk)
		if (ui_rst) begin
			publication <= 1'sb0;
			pub_toggle <= 0;
			pending_valid <= 0;
			ack_meta <= 0;
			ack_sync <= 0;
			mode_hold <= 1;
			mode_request <= 0;
			mode_wait <= 0;
			mode_ack_meta <= 0;
			mode_ack_sync <= 0;
		end
		else begin
			ack_meta <= ack_toggle;
			ack_sync <= ack_meta;
			mode_ack_meta <= mode_ack;
			mode_ack_sync <= mode_ack_meta;
			if (mode_wait && (mode_ack_sync == mode_request))
				mode_wait <= 0;
			if (!mode_wait && (test_pattern != mode_hold)) begin
				mode_hold <= test_pattern;
				mode_request <= ~mode_request;
				mode_wait <= 1;
			end
			if (pending_valid && (ack_sync == pub_toggle))
				pending_valid <= 0;
			if (publish_valid && publish_ready) begin
				publication <= {publish_fb, publish_frame, publish_run, publish_xy1, publish_xy2, publish_score, publish_class, publish_count, publish_sequence};
				pending_valid <= 1;
				pub_toggle <= ~pub_toggle;
			end
		end
	function automatic [19:0] sv2v_cast_20;
		input reg [19:0] inp;
		sv2v_cast_20 = inp;
	endfunction
	assign expect_index = sv2v_cast_20(((y - Y_START) * EMIT_PER_ROW) + (x - X_START));
	assign {fifo_epoch, fifo_index, fifo_pixel} = fifo_data;
	assign match_pixel = (fifo_valid && (fifo_epoch == epoch)) && (fifo_index == expect_index);
	assign stale_pixel = fifo_valid && ((fifo_epoch != epoch) || (image_slot && (fifo_index < expect_index)));
	assign fifo_ready = stale_pixel || (image_slot && match_pixel);
	assign fifo_push = (row_out_valid && feed_enabled) && !scan_abort;
	assign pr = (!feed_enabled || scan_abort) || !row_ready[load_bank];
	soc_display_async_fifo #(
		.WIDTH(FW),
		.DEPTH(FIFO_DEPTH)
	) display_fifo(
		.wr_clk(ui_clk),
		.rd_clk(pix_clk),
		.arst(ui_rst || pix_rst),
		.in_valid(fifo_push),
		.in_ready(fifo_accept),
		.in_data({reader_epoch, row_out_index, row_out_pixel}),
		.out_valid(fifo_valid),
		.out_ready(fifo_ready),
		.out_data(fifo_data),
		.wr_level(fifo_level)
	);
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	assign row_addr = reader_fb + sv2v_cast_32(row * (W * 2));
	soc_hdmi_axi_reader #(
		.VIDEO_BASE(32'h82000000),
		.VIDEO_BYTES(32'h00400000),
		.MAX_PIXELS(W),
		.ENABLE_ABORT(1),
		.WAIT_LIMIT(WAIT_LIMIT)
	) reader(
		.clk(ui_clk),
		.rst(ui_rst),
		.start(reader_start),
		.abort(scan_abort),
		.frame_base(row_addr),
		.frame_pixels(W),
		.ready(reader_ready),
		.busy(reader_busy),
		.done_pulse(reader_done),
		.frame_valid(reader_frame_valid),
		.error_sticky(reader_error),
		.pixels_emitted(reader_pixels),
		.max_wait_cycles(stat_max_ddr_wait),
		.pixel_valid(pv),
		.pixel_ready(pr),
		.pixel_data(pdata),
		.pixel_last(plast),
		.m_arid(m_arid),
		.m_araddr(m_araddr),
		.m_arlen(m_arlen),
		.m_arsize(m_arsize),
		.m_arburst(m_arburst),
		.m_arvalid(m_arvalid),
		.m_arready(m_arready),
		.m_rid(m_rid),
		.m_rdata(m_rdata),
		.m_rresp(m_rresp),
		.m_rlast(m_rlast),
		.m_rvalid(m_rvalid),
		.m_rready(m_rready)
	);
	always @(posedge ui_clk)
		if (ui_rst) begin
			scan_meta <= 0;
			scan_sync <= 0;
			scan_ui_seen <= 0;
			scan_abort <= 0;
			reader_epoch <= 0;
			reader_fb <= 0;
			reader_index <= 0;
			row <= 0;
			side <= 0;
			row_ready <= 0;
			load_bank <= 0;
			emit_bank <= 0;
			load_complete <= 0;
			load_column <= 0;
			emit_column <= 0;
			issue_index <= 0;
			row_out_valid <= 0;
			row_out_last <= 0;
			row_out_index <= 0;
			feed_enabled <= 0;
			reader_start <= 0;
			stat_fifo_high <= 0;
			stat_fifo_low <= FIFO_DEPTH;
			video_fault <= 0;
		end
		else begin
			scan_meta <= scan_toggle;
			scan_sync <= scan_meta;
			reader_start <= 0;
			if (fifo_level > stat_fifo_high)
				stat_fifo_high <= sv2v_cast_32(fifo_level);
			if (feed_enabled && (fifo_level < stat_fifo_low))
				stat_fifo_low <= sv2v_cast_32(fifo_level);
			if (reader_error != 0) begin
				video_fault <= video_fault | reader_error;
				feed_enabled <= 0;
			end
			if (scan_sync != scan_ui_seen) begin
				scan_abort <= 1;
				feed_enabled <= 0;
			end
			if ((scan_abort && reader_ready) && !reader_start) begin
				scan_ui_seen <= scan_sync;
				scan_abort <= 0;
				reader_epoch <= scan_epoch;
				reader_fb <= scan_fb;
				row <= 0;
				side <= 0;
				reader_index <= 0;
				row_ready <= 0;
				load_bank <= 0;
				emit_bank <= 0;
				load_complete <= 0;
				load_column <= 0;
				emit_column <= 0;
				issue_index <= 0;
				row_out_valid <= 0;
				row_out_last <= 0;
				row_out_index <= 0;
				feed_enabled <= (scan_valid && (video_fault == 0)) && (reader_error == 0);
			end
			else if (((scan_sync == scan_ui_seen) && !scan_abort) && feed_enabled) begin
				if (cache_write)
					load_column <= load_column + 1'b1;
				if (row_out_fire) begin
					reader_index <= reader_index + 1'b1;
					row_out_valid <= 0;
					if (row_out_last) begin
						row_ready[emit_bank] <= 0;
						emit_bank <= ~emit_bank;
						side <= 0;
						if (reader_index == ((EMIT_PER_ROW * OUTPUT_HEIGHT) - 1))
							feed_enabled <= 0;
					end
				end
				if (row_read_issue) begin
					row_out_valid <= 1;
					row_out_last <= emit_column == (EMIT_PER_ROW - 1);
					row_out_index <= sv2v_cast_20(issue_index);
					issue_index <= issue_index + 1'b1;
					if (emit_column == (EMIT_PER_ROW - 1))
						emit_column <= 0;
					else
						emit_column <= emit_column + 1'b1;
					side <= emit_column >= W;
				end
				if (reader_done) begin
					if (!reader_frame_valid)
						feed_enabled <= 0;
					else begin
						row_ready[load_bank] <= 1;
						load_bank <= ~load_bank;
						if (row == (H - 1))
							load_complete <= 1;
						else
							row <= row + 1'b1;
					end
				end
				else if (((reader_ready && !reader_start) && !load_complete) && !row_ready[load_bank]) begin
					reader_start <= 1;
					load_column <= 0;
				end
			end
			if (reader_error != 0) begin
				feed_enabled <= 0;
				reader_start <= 0;
			end
		end
	always @(*) begin
		if (_sv2v_0)
			;
		cpu_binary[63] = cpu_gray_sync[63];
		begin : sv2v_autoblock_1
			integer i;
			for (i = 62; i >= 0; i = i - 1)
				cpu_binary[i] = ^(cpu_gray_sync >> i);
		end
		case ((sv2v_cast_32(x) * 8) / H_ACTIVE)
			0: bars = 24'hffffff;
			1: bars = 24'hffff00;
			2: bars = 24'h00ffff;
			3: bars = 24'h00ff00;
			4: bars = 24'hff00ff;
			5: bars = 24'hff0000;
			6: bars = 24'h0000ff;
			default: bars = 0;
		endcase
		rgb_raw = 0;
		if (de_raw) begin
			if (!active_valid || (mode_active != 2))
				rgb_raw = bars;
			else if (image_slot && match_pixel)
				rgb_raw = {fifo_pixel[15:11], fifo_pixel[15:13], fifo_pixel[10:5], fifo_pixel[10:9], fifo_pixel[4:0], fifo_pixel[4:2]};
		end
	end
	function automatic [10:0] sv2v_cast_11;
		input reg [10:0] inp;
		sv2v_cast_11 = inp;
	endfunction
	soc_gesture_label #(
		.X_MIN((SINGLE_VIEW ? X_START : W)),
		.X_LIMIT((SINGLE_VIEW ? X_START + W : 2 * W)),
		.Y_MIN(Y_START),
		.Y_LIMIT(Y_START + OUTPUT_HEIGHT)
	) gesture_label(
		.enable(((de_raw && active_valid) && (mode_active == 2)) && (active[63-:32] != 0)),
		.class_id(active[95-:32]),
		.score_q15(active[127-:32]),
		.box_x1(sv2v_cast_11(active[175:160] + (SINGLE_VIEW ? X_START : W))),
		.box_y1(sv2v_cast_10(active[191:176] + Y_START)),
		.pixel_x(sv2v_cast_11(x)),
		.pixel_y(sv2v_cast_10(y)),
		.pixel_rgb(rgb_raw),
		.label_rgb(rgb_labeled),
		.label_active(label_active)
	);
	soc_stereo_osd #(
		.X_MIN((SINGLE_VIEW ? X_START : W)),
		.X_LIMIT((SINGLE_VIEW ? X_START + W : 2 * W)),
		.Y_MIN(Y_START),
		.Y_LIMIT(Y_START + OUTPUT_HEIGHT)
	) osd(
		.clk(pix_clk),
		.rst(pix_rst),
		.vblank(vblank),
		.displayed_left_id((pub_sync != ack_toggle ? publication[255-:32] : active[255-:32])),
		.displayed_right_id((pub_sync != ack_toggle ? publication[255-:32] : active[255-:32])),
		.cfg_valid(pub_sync != ack_toggle),
		.cfg_enable(publication[63-:32] != 0),
		.cfg_left_id(publication[255-:32]),
		.cfg_right_id(publication[255-:32]),
		.cfg_x1(sv2v_cast_11(publication[175:160] + (SINGLE_VIEW ? X_START : W))),
		.cfg_x2(sv2v_cast_11(publication[143:128] + (SINGLE_VIEW ? X_START : W))),
		.cfg_y1(sv2v_cast_10(publication[191:176] + Y_START)),
		.cfg_y2(sv2v_cast_10(publication[159:144] + Y_START)),
		.pixel_valid(de_raw),
		.pixel_x(sv2v_cast_11(x)),
		.pixel_y(sv2v_cast_10(y)),
		.pixel_rgb(rgb_labeled),
		.pixel_out_valid(osd_valid),
		.pixel_out_rgb(video_rgb),
		.box_active(box_active),
		.cfg_error(osd_error)
	);
	assign video_de = de_pipe[0];
	assign video_hs = hs_pipe[0];
	assign video_vs = vs_pipe[0];
	function automatic [PIPE - 1:0] sv2v_cast_1513D;
		input reg [PIPE - 1:0] inp;
		sv2v_cast_1513D = inp;
	endfunction
	always @(posedge pix_clk)
		if (pix_rst) begin
			x <= 0;
			y <= 0;
			pixel_ticks <= 0;
			cpu_gray_meta <= 0;
			cpu_gray_sync <= 0;
			cpu_ticks <= 0;
			pub_meta <= 0;
			pub_sync <= 0;
			ack_toggle <= 0;
			active <= 1'sb0;
			active_valid <= 0;
			mode_meta <= 0;
			mode_sync <= 0;
			mode_ack <= 0;
			mode_active <= 1;
			te_good_hold <= 0;
			scan_epoch <= 0;
			scan_fb <= 0;
			scan_valid <= 0;
			scan_toggle <= 0;
			epoch <= 0;
			hs_pipe <= 0;
			vs_pipe <= 0;
			de_pipe <= 0;
			th_pipe <= 0;
			te_pipe <= 0;
			underflow_count <= 0;
			mismatch_count <= 0;
			presented_count <= 0;
			frame_bad <= 0;
			th_delivered <= 0;
			tc_toggle <= 0;
			th_toggle <= 0;
			te_toggle <= 0;
			tc_hold <= 1'sb0;
			th_hold <= 1'sb0;
			te_hold <= 1'sb0;
		end
		else begin
			pixel_ticks <= pixel_ticks + 1'b1;
			cpu_gray_meta <= cpu_time_gray;
			cpu_gray_sync <= cpu_gray_meta;
			cpu_ticks <= cpu_binary;
			pub_meta <= pub_toggle;
			pub_sync <= pub_meta;
			mode_meta <= mode_request;
			mode_sync <= mode_meta;
			if (x == (HT - 1)) begin
				x <= 0;
				if (y == (VT - 1))
					y <= 0;
				else
					y <= y + 1'b1;
			end
			else
				x <= x + 1'b1;
			hs_pipe <= (hs_pipe << 1) | sv2v_cast_1513D(hs_raw);
			vs_pipe <= (vs_pipe << 1) | sv2v_cast_1513D(vs_raw);
			de_pipe <= (de_pipe << 1) | sv2v_cast_1513D(de_raw);
			th_pipe <= (th_pipe << 1) | sv2v_cast_1513D(((((active_valid && (mode_active == 2)) && image_slot) && (x == X_START)) && (y == Y_START)) && !th_delivered);
			te_pipe <= (te_pipe << 1) | sv2v_cast_1513D((((active_valid && (mode_active == 2)) && image_slot) && (x == ((X_START + EMIT_PER_ROW) - 1))) && (y == ((Y_START + OUTPUT_HEIGHT) - 1)));
			if (vblank) begin
				epoch <= epoch + 1'b1;
				scan_epoch <= epoch + 1'b1;
				scan_toggle <= ~scan_toggle;
				scan_fb <= (pub_sync != ack_toggle ? publication[287-:32] : active[287-:32]);
				scan_valid <= (active_valid || (pub_sync != ack_toggle)) && (next_mode == 2);
				frame_bad <= 0;
				mode_active <= next_mode;
				mode_ack <= mode_sync;
				if (pub_sync != ack_toggle) begin
					active <= publication;
					active_valid <= 1;
					ack_toggle <= pub_sync;
					th_delivered <= 0;
					tc_toggle <= ~tc_toggle;
					tc_hold <= {cpu_ticks, pixel_ticks, publication[255-:32], publication[223-:32], publication[287-:32], underflow_count, mismatch_count, presented_count};
				end
			end
			if (((active_valid && (mode_active == 2)) && image_slot) && !match_pixel) begin
				underflow_count <= underflow_count + 1'b1;
				frame_bad <= 1;
			end
			if (stale_pixel)
				mismatch_count <= mismatch_count + 1'b1;
			if (th_pipe[PIPE - 1]) begin
				th_delivered <= 1;
				th_toggle <= ~th_toggle;
				th_hold <= {cpu_ticks, pixel_ticks, active[255-:32], active[223-:32], active[287-:32], underflow_count, mismatch_count, presented_count};
			end
			if (te_pipe[PIPE - 1]) begin
				if (!frame_bad)
					presented_count <= presented_count + 1'b1;
				te_good_hold <= !frame_bad;
				te_toggle <= ~te_toggle;
				te_hold <= {cpu_ticks, pixel_ticks, active[255-:32], active[223-:32], active[287-:32], underflow_count, mismatch_count, presented_count + sv2v_cast_32(!frame_bad)};
			end
		end
	always @(posedge ui_clk)
		if (ui_rst) begin
			evt_meta <= 0;
			evt_sync <= 0;
			evt_seen <= 0;
			event_tc <= 0;
			event_th <= 0;
			event_te <= 0;
			te_good <= 0;
			tc_ticks <= 0;
			th_ticks <= 0;
			te_ticks <= 0;
			tc_pixel_ticks <= 0;
			th_pixel_ticks <= 0;
			te_pixel_ticks <= 0;
			tc_frame <= 0;
			tc_run <= 0;
			th_frame <= 0;
			th_run <= 0;
			te_frame <= 0;
			te_run <= 0;
			presented_valid <= 0;
			presented_fb <= 0;
			presented_frame <= 0;
			presented_run <= 0;
			stat_underflow <= 0;
			stat_mismatch <= 0;
			stat_presented <= 0;
		end
		else begin
			evt_meta <= {te_toggle, th_toggle, tc_toggle};
			evt_sync <= evt_meta;
			evt_seen <= evt_sync;
			event_tc <= evt_sync[0] != evt_seen[0];
			event_th <= evt_sync[1] != evt_seen[1];
			event_te <= evt_sync[2] != evt_seen[2];
			if (evt_sync[0] != evt_seen[0]) begin
				tc_ticks <= tc_hold[319-:64];
				tc_pixel_ticks <= tc_hold[255-:64];
				tc_frame <= tc_hold[191-:32];
				tc_run <= tc_hold[159-:32];
				presented_valid <= 1;
				presented_fb <= tc_hold[127-:32];
				presented_frame <= tc_hold[191-:32];
				presented_run <= tc_hold[159-:32];
				stat_underflow <= tc_hold[95-:32];
				stat_mismatch <= tc_hold[63-:32];
				stat_presented <= tc_hold[31-:32];
			end
			if (evt_sync[1] != evt_seen[1]) begin
				th_ticks <= th_hold[319-:64];
				th_pixel_ticks <= th_hold[255-:64];
				th_frame <= th_hold[191-:32];
				th_run <= th_hold[159-:32];
			end
			if (evt_sync[2] != evt_seen[2]) begin
				te_good <= te_good_hold;
				te_ticks <= te_hold[319-:64];
				te_pixel_ticks <= te_hold[255-:64];
				te_frame <= te_hold[191-:32];
				te_run <= te_hold[159-:32];
				stat_underflow <= te_hold[95-:32];
				stat_mismatch <= te_hold[63-:32];
				stat_presented <= te_hold[31-:32];
			end
		end
	initial if ((((((((((W != 680) || (H != 340)) || !SINGLE_VIEW) || (X_START < 0)) || (Y_START < 0)) || ((X_START + W) > H_ACTIVE)) || ((Y_START + H) > V_ACTIVE)) || (HT > 4096)) || (VT > 4096)) || (TX_EXTRA_CYCLES < 0)) begin
		$display("Fatal [%0t] D:/workspace/riscv-fpga-soc/work/graph_executor_pipeopt7_20261102_21/native_pds25_03/conversion_input/board/soc_hdmi_ddr_scanout.sv:336:4 - soc_hdmi_ddr_scanout.<unnamed_block>.<unnamed_block>\n msg: ", $time, "DISPLAY_SCANOUT_GEOMETRY");
		$finish(1);
	end
	initial _sv2v_0 = 0;
endmodule
module soc_board_camera_top (
	sys_clk,
	clk_p,
	clk_n,
	rst_in,
	uart_rx,
	camera_clk_0,
	camera_href_0,
	camera_vsync_0,
	camera_data_0,
	camera_clk_1,
	camera_href_1,
	camera_vsync_1,
	camera_data_1,
	SCL_0,
	SDA_0,
	SCL_1,
	SDA_1,
	cam_rst_0,
	cam_rst_1,
	uart_tx,
	led,
	tmds_data_p,
	tmds_data_n,
	tmds_clk_p,
	tmds_clk_n,
	mem_rst_n,
	mem_ck,
	mem_ck_n,
	mem_cke,
	mem_cs_n,
	mem_ras_n,
	mem_cas_n,
	mem_we_n,
	mem_odt,
	mem_a,
	mem_ba,
	mem_dqs,
	mem_dqs_n,
	mem_dq,
	mem_dm
);
	parameter ITCM_INIT_FILE = "coremark-itcm.mem";
	parameter DTCM_INIT_FILE = "coremark-dtcm.mem";
	parameter [0:0] S3_BURST_ENABLE = 1'b1;
	input wire sys_clk;
	input wire clk_p;
	input wire clk_n;
	input wire rst_in;
	input wire uart_rx;
	input wire camera_clk_0;
	input wire camera_href_0;
	input wire camera_vsync_0;
	input wire [7:0] camera_data_0;
	input wire camera_clk_1;
	input wire camera_href_1;
	input wire camera_vsync_1;
	input wire [7:0] camera_data_1;
	inout wire SCL_0;
	inout wire SDA_0;
	inout wire SCL_1;
	inout wire SDA_1;
	output wire cam_rst_0;
	output wire cam_rst_1;
	output wire uart_tx;
	output reg [7:0] led;
	output wire [2:0] tmds_data_p;
	output wire [2:0] tmds_data_n;
	output wire tmds_clk_p;
	output wire tmds_clk_n;
	output wire mem_rst_n;
	output wire mem_ck;
	output wire mem_ck_n;
	output wire mem_cke;
	output wire mem_cs_n;
	output wire mem_ras_n;
	output wire mem_cas_n;
	output wire mem_we_n;
	output wire mem_odt;
	output wire [14:0] mem_a;
	output wire [2:0] mem_ba;
	inout wire [3:0] mem_dqs;
	inout wire [3:0] mem_dqs_n;
	inout wire [31:0] mem_dq;
	output wire [3:0] mem_dm;
	(* syn_keep = 1 *) wire region_reset_s3_registers;
	wire mem_reset;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_s3_registers(
		.I0(mem_reset),
		.Z(region_reset_s3_registers)
	);
	(* syn_keep = 1 *) wire region_reset_s3_engine;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_s3_engine(
		.I0(mem_reset),
		.Z(region_reset_s3_engine)
	);
	(* syn_keep = 1 *) wire region_reset_window_registers;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_window_registers(
		.I0(mem_reset),
		.Z(region_reset_window_registers)
	);
	(* syn_keep = 1 *) wire region_reset_window_engine;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_window_engine(
		.I0(mem_reset),
		.Z(region_reset_window_engine)
	);
	(* syn_keep = 1 *) wire region_reset_concat_registers;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_concat_registers(
		.I0(mem_reset),
		.Z(region_reset_concat_registers)
	);
	(* syn_keep = 1 *) wire region_reset_concat_engine;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_concat_engine(
		.I0(mem_reset),
		.Z(region_reset_concat_engine)
	);
	(* syn_keep = 1 *) wire region_reset_s3_axi;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_s3_axi(
		.I0(mem_reset),
		.Z(region_reset_s3_axi)
	);
	(* syn_keep = 1 *) wire region_reset_v2_replay;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_v2_replay(
		.I0(mem_reset),
		.Z(region_reset_v2_replay)
	);
	(* syn_keep = 1 *) wire region_reset_v2_share;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_v2_share(
		.I0(mem_reset),
		.Z(region_reset_v2_share)
	);
	(* syn_keep = 1 *) wire region_reset_video_share;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_video_share(
		.I0(mem_reset),
		.Z(region_reset_video_share)
	);
	(* syn_keep = 1 *) wire region_reset_s3_share;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_s3_share(
		.I0(mem_reset),
		.Z(region_reset_s3_share)
	);
	(* syn_keep = 1 *) wire region_reset_camera_share;
	(* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *) GTP_LUT1 #(.INIT(2'b10)) reset_driver_camera_share(
		.I0(mem_reset),
		.Z(region_reset_camera_share)
	);
	wire ref_clk;
	wire mem_clk;
	wire cpu_clk_fast;
	wire npu_clk_fast;
	wire cpu_pll_lock;
	wire npu_pll_lock;
	wire arst;
	wire hdmi_pixel_clk;
	wire hdmi_serial_clk;
	wire hdmi_pll_locked;
	wire hdmi_pixel_reset_n;
	wire hdmi_pixel_reset;
	wire hdmi_serial_reset;
	wire [63:0] cpu_time_gray;
	wire [1:0] video_mode;
	wire publish_valid;
	wire publish_ready;
	wire pending_display_valid;
	wire displayed_valid;
	wire [31:0] publish_fb;
	wire [31:0] publish_frame;
	wire [31:0] publish_run;
	wire [31:0] publish_xy1;
	wire [31:0] publish_xy2;
	wire [31:0] publish_score;
	wire [31:0] publish_class;
	wire [31:0] publish_count;
	wire [31:0] publish_sequence;
	wire [31:0] pending_display_fb;
	wire [31:0] displayed_fb;
	wire [31:0] displayed_frame;
	wire [31:0] displayed_run;
	wire [23:0] video_rgb;
	wire video_de;
	wire video_hs;
	wire video_vs;
	wire event_tc;
	wire event_th;
	wire event_te;
	wire te_good;
	wire [63:0] tc_ticks;
	wire [63:0] th_ticks;
	wire [63:0] te_ticks;
	wire [31:0] tc_frame;
	wire [31:0] tc_run;
	wire [31:0] th_frame;
	wire [31:0] th_run;
	wire [31:0] te_frame;
	wire [31:0] te_run;
	wire [31:0] stat_underflow;
	wire [31:0] stat_mismatch;
	wire [31:0] stat_presented;
	wire [31:0] stat_max_ddr_wait;
	wire [31:0] stat_fifo_high;
	wire [31:0] stat_fifo_low;
	wire [7:0] video_fault;
	soc_mini_hdmi_clock u_hdmi_clock(
		.sys_clk(sys_clk),
		.reset_n(rst_in),
		.pixel_clk(hdmi_pixel_clk),
		.serial_clk(hdmi_serial_clk),
		.pll_locked(hdmi_pll_locked),
		.pixel_reset_n(hdmi_pixel_reset_n)
	);
	soc_reset_sync u_hdmi_pixel_reset(
		.clk(hdmi_pixel_clk),
		.arst(arst),
		.rst(hdmi_pixel_reset)
	);
	soc_reset_sync u_hdmi_serial_reset(
		.clk(hdmi_serial_clk),
		.arst(arst),
		.rst(hdmi_serial_reset)
	);
	wire cpu_reset;
	wire npu_reset;
	wire board27_reset;
	wire ddr_ref_reset;
	wire ddr_init_done;
	reg ddr_ready;
	wire ddr_pll_lock;
	wire ddr_phy_lock;
	wire ddr_cal_fail;
	wire adapter_fault;
	wire adapter_fault_cpu;
	wire ddr_ready_cpu;
	wire cal_fail_cpu;
	wire soc_fault;
	wire ddr_fault;
	wire fatal_state;
	wire sleeping;
	wire [31:0] gpio_out;
	wire [31:0] diag_mailbox;
	wire unused_aux_tx;
	wire camera_init_done;
	wire camera_ready;
	wire camera_busy;
	wire camera_done;
	wire camera_valid;
	wire [7:0] camera_errors;
	wire [31:0] camera_pixels_written;
	wire [31:0] camera_sensor_pixels;
	wire [31:0] camera_frame_base;
	wire camera_start;
	wire camera_diag_snapshot;
	wire [511:0] camera_diag_words;
	wire camera_init_done_1;
	wire camera_init_mem_1;
	wire camera_diag_snapshot_1;
	wire [511:0] camera_diag_words_1;
	wire auto_scl_0;
	wire auto_sda_0;
	wire auto_scl_1;
	wire auto_sda_1;
	wire [5:0] sccb_control;
	(* keep = "true" *) reg [5:0] sccb_pin_control;
	always @(posedge mem_clk)
		if (mem_reset)
			sccb_pin_control <= 0;
		else
			sccb_pin_control <= sccb_control;
	reg [31:0] camera_io_meta;
	reg [31:0] camera_io_levels;
	assign SCL_0 = (sccb_pin_control[0] && !arst ? (sccb_pin_control[2] ? 1'b0 : 1'bz) : auto_scl_0);
	assign SDA_0 = (sccb_pin_control[0] && !arst ? (sccb_pin_control[3] ? 1'b0 : 1'bz) : auto_sda_0);
	assign SCL_1 = (sccb_pin_control[1] && !arst ? (sccb_pin_control[4] ? 1'b0 : 1'bz) : auto_scl_1);
	assign SDA_1 = (sccb_pin_control[1] && !arst ? (sccb_pin_control[5] ? 1'b0 : 1'bz) : auto_sda_1);
	wire [1:0] camera0_diag_sync_held;
	always @(posedge mem_clk)
		if (mem_reset) begin
			camera_io_meta <= 0;
			camera_io_levels <= 0;
		end
		else begin
			camera_io_meta <= {6'b000000, camera_vsync_1, camera_href_1, camera_clk_1, camera0_diag_sync_held[1], camera0_diag_sync_held[0], camera_clk_0, 16'b0000000000000000, SDA_1, SCL_1, SDA_0, SCL_0};
			camera_io_levels <= camera_io_meta;
		end
	wire [7:0] camera_data_held;
	soc_camera_input_hold #(
		.WIDTH(2),
		.HOLD_SET("500ps")
	) camera0_diag_hold(
		.data_in({camera_vsync_0, camera_href_0}),
		.data_out(camera0_diag_sync_held)
	);
	soc_camera_input_hold camera_input_hold(
		.data_in(camera_data_1),
		.data_out(camera_data_held)
	);
	wire board_req_valid;
	wire board_req_ready;
	wire board_req_write;
	wire board_req_fetch;
	wire [31:0] board_req_addr;
	wire [31:0] board_req_wdata;
	wire [31:0] board_rsp_rdata;
	wire [3:0] board_req_wstrb;
	wire board_rsp_valid;
	wire board_rsp_ready;
	wire board_rsp_error;
	wire cam_mem_req_valid;
	wire cam_mem_req_ready;
	wire cam_mem_req_write;
	wire [15:0] cam_mem_req_addr;
	wire [31:0] cam_mem_req_wdata;
	wire [31:0] cam_mem_rsp_rdata;
	wire [3:0] cam_mem_req_wstrb;
	wire cam_mem_rsp_valid;
	wire cam_mem_rsp_ready;
	wire cam_mem_rsp_error;
	wire cam_unit_req_ready;
	wire cam_unit_rsp_valid;
	wire cam_unit_rsp_error;
	wire [31:0] cam_unit_rsp_rdata;
	wire s3_mem_req_ready;
	wire s3_mem_rsp_valid;
	wire s3_mem_rsp_error;
	wire [31:0] s3_mem_rsp_rdata;
	wire s2_mem_req_ready;
	wire s2_mem_rsp_valid;
	wire s2_mem_rsp_error;
	wire [31:0] s2_mem_rsp_rdata;
	reg [2:0] mmio_response_owner;
	wire display_mem_req_ready;
	wire display_mem_rsp_valid;
	wire display_mem_rsp_error;
	wire [31:0] display_mem_rsp_rdata;
	wire win_mem_req_ready;
	wire win_mem_rsp_valid;
	wire win_mem_rsp_error;
	wire [31:0] win_mem_rsp_rdata;
	wire concat_mem_req_ready;
	wire concat_mem_rsp_valid;
	wire concat_mem_rsp_error;
	wire [31:0] concat_mem_rsp_rdata;
	wire concat_irq_mem;
	wire concat_irq_cpu;
	wire video_mem_req_ready;
	wire video_mem_rsp_valid;
	wire video_mem_rsp_error;
	wire [31:0] video_mem_rsp_rdata;
	wire image_mem_req_ready;
	wire image_mem_rsp_valid;
	wire image_mem_rsp_error;
	wire [31:0] image_mem_rsp_rdata;
	wire [2:0] mmio_request_unit = (cam_mem_req_addr[11:8] == 4'h7 ? 3'd7 : (cam_mem_req_addr[11:8] == 4'h4 ? 3'd6 : (cam_mem_req_addr[11:8] == 4'h3 ? 3'd5 : (cam_mem_req_addr[11:8] == 4'h1 ? 3'd1 : (cam_mem_req_addr[11:8] == 4'h2 ? 3'd2 : (cam_mem_req_addr[11:8] == 4'h5 ? 3'd3 : (cam_mem_req_addr[11:8] == 4'h6 ? 3'd4 : 3'd0)))))));
	reg ddr_ready_ref_meta;
	reg ddr_ready_ref;
	reg ddr_pll_ref_meta;
	reg ddr_pll_ref;
	reg ddr_phy_ref_meta;
	reg ddr_phy_ref;
	reg ddr_ready_seen_ref;
	reg ddr_lock_fault_q;
	always @(posedge ref_clk or negedge rst_in or negedge cpu_pll_lock or negedge npu_pll_lock)
		if ((!rst_in || !cpu_pll_lock) || !npu_pll_lock) begin
			ddr_ready_ref_meta <= 0;
			ddr_ready_ref <= 0;
			ddr_pll_ref_meta <= 0;
			ddr_pll_ref <= 0;
			ddr_phy_ref_meta <= 0;
			ddr_phy_ref <= 0;
			ddr_ready_seen_ref <= 0;
			ddr_lock_fault_q <= 0;
		end
		else begin
			ddr_ready_ref_meta <= ddr_ready;
			ddr_ready_ref <= ddr_ready_ref_meta;
			ddr_pll_ref_meta <= ddr_pll_lock;
			ddr_pll_ref <= ddr_pll_ref_meta;
			ddr_phy_ref_meta <= ddr_phy_lock;
			ddr_phy_ref <= ddr_phy_ref_meta;
			if (ddr_ready_ref)
				ddr_ready_seen_ref <= 1;
			if (ddr_ready_seen_ref && (!ddr_pll_ref || !ddr_phy_ref))
				ddr_lock_fault_q <= 1;
		end
	assign arst = (((!rst_in || !cpu_pll_lock) || !npu_pll_lock) || !hdmi_pll_locked) || ddr_lock_fault_q;
	soc_cpu70_pll_probe u_cpu_pll(
		.clkin1(ref_clk),
		.clkout1(cpu_clk_fast),
		.lock(cpu_pll_lock)
	);
	soc_cpu100_pll_probe u_npu_pll(
		.clkin1(ref_clk),
		.clkout1(npu_clk_fast),
		.lock(npu_pll_lock)
	);
	GTP_INBUFGDS #(
		.IOSTANDARD("DEFAULT"),
		.TERM_DIFF("ON")
	) u_refclk(
		.O(ref_clk),
		.I(clk_p),
		.IB(clk_n)
	);
	soc_reset_sync u_board27_reset(
		.clk(sys_clk),
		.arst(arst),
		.rst(board27_reset)
	);
	soc_reset_sync u_ddr_ref_reset(
		.clk(ref_clk),
		.arst(arst),
		.rst(ddr_ref_reset)
	);
	always @(posedge mem_clk or posedge arst)
		if (arst)
			ddr_ready <= 0;
		else
			ddr_ready <= ((ddr_init_done && ddr_pll_lock) && ddr_phy_lock) && !ddr_cal_fail;
	pg_level_sync u_adapter_fault_sync(
		.clk(cpu_clk_fast),
		.rst(cpu_reset),
		.async_level(adapter_fault),
		.level(adapter_fault_cpu)
	);
	pg_level_sync u_ready_sync(
		.clk(cpu_clk_fast),
		.rst(cpu_reset),
		.async_level(ddr_ready),
		.level(ddr_ready_cpu)
	);
	pg_level_sync u_cal_fault_sync(
		.clk(cpu_clk_fast),
		.rst(cpu_reset),
		.async_level(ddr_cal_fail),
		.level(cal_fail_cpu)
	);
	wire [7:0] led_cpu;
	wire [7:0] led_27;
	assign led_cpu = {((fatal_state | adapter_fault_cpu) | soc_fault) | ddr_fault, cal_fail_cpu, ddr_ready_cpu, !cpu_reset, gpio_out[3:0]};
	genvar _gv_l_1;
	generate
		for (_gv_l_1 = 0; _gv_l_1 < 8; _gv_l_1 = _gv_l_1 + 1) begin : led_cdc
			localparam l = _gv_l_1;
			pg_level_sync u_sync(
				.clk(sys_clk),
				.rst(board27_reset),
				.async_level(led_cpu[l]),
				.level(led_27[l])
			);
		end
	endgenerate
	always @(posedge sys_clk)
		if (board27_reset)
			led <= 8'd0;
		else
			led <= led_27;
	wire [3:0] s_awid;
	wire [31:0] s_awaddr;
	wire [7:0] s_awlen;
	wire [2:0] s_awsize;
	wire [1:0] s_awburst;
	wire s_awvalid;
	wire s_awready;
	wire [127:0] s_wdata;
	wire [15:0] s_wstrb;
	wire s_wlast;
	wire s_wvalid;
	wire s_wready;
	wire [3:0] s_bid;
	wire [1:0] s_bresp;
	wire s_bvalid;
	wire s_bready;
	wire [3:0] s_arid;
	wire [31:0] s_araddr;
	wire [7:0] s_arlen;
	wire [2:0] s_arsize;
	wire [1:0] s_arburst;
	wire s_arvalid;
	wire s_arready;
	wire [3:0] s_rid;
	wire [127:0] s_rdata;
	wire [1:0] s_rresp;
	wire s_rlast;
	wire s_rvalid;
	wire s_rready;
	wire [7:0] m_awid;
	wire [29:0] m_awaddr;
	wire [7:0] m_awlen;
	wire [2:0] m_awsize;
	wire [1:0] m_awburst;
	wire m_awvalid;
	wire m_awready;
	wire [255:0] m_wdata;
	wire [31:0] m_wstrb;
	wire m_wlast;
	wire m_wvalid;
	wire m_wready;
	wire [7:0] m_bid;
	wire [1:0] m_bresp;
	wire m_bvalid;
	wire m_bready;
	wire [7:0] m_arid;
	wire [29:0] m_araddr;
	wire [7:0] m_arlen;
	wire [2:0] m_arsize;
	wire [1:0] m_arburst;
	wire m_arvalid;
	wire m_arready;
	wire [7:0] m_rid;
	wire [255:0] m_rdata;
	wire [1:0] m_rresp;
	wire m_rlast;
	wire m_rvalid;
	wire m_rready;
	wire gex_locked_npu;
	wire [15:0] gex_win_req_addr;
	wire gex_win_req_ready;
	wire gex_win_req_valid;
	wire [31:0] gex_win_req_wdata;
	wire gex_win_req_write;
	wire [3:0] gex_win_req_wstrb;
	wire gex_win_rsp_error;
	wire [31:0] gex_win_rsp_rdata;
	wire gex_win_rsp_ready;
	wire gex_win_rsp_valid;
	soc_soc_top #(
		.CPU_CLOCK_HZ(70000000),
		.UART_BAUD(115200),
		.BOARD_MMIO_ENABLE(1'b1),
		.DMA_TIMEOUT_CYCLES(500000),
		.ITCM_INIT_FILE(ITCM_INIT_FILE),
		.DTCM_INIT_FILE(DTCM_INIT_FILE)
	) soc(
		.cpu_clk(cpu_clk_fast),
		.npu_clk(npu_clk_fast),
		.mem_clk(mem_clk),
		.arst(arst),
		.mem_ready(ddr_ready),
		.cpu_reset(cpu_reset),
		.npu_reset(npu_reset),
		.mem_reset(mem_reset),
		.irq_nmi_fault(adapter_fault_cpu),
		.irq_fast_adc(1'b0),
		.irq_fast_pwm(1'b0),
		.irq_qei(1'b0),
		.irq_timer(1'b0),
		.irq_ipc(1'b0),
		.irq_platform({7'b0000000, concat_irq_cpu}),
		.gpio_in({28'b0000000000000000000000000000, cal_fail_cpu, adapter_fault_cpu, ddr_ready_cpu, 1'b1}),
		.gpio_out(gpio_out),
		.diagnostic_mailbox(diag_mailbox),
		.uart_tx(uart_tx),
		.uart_rx(uart_rx),
		.uart_aux_tx(unused_aux_tx),
		.timer_gray(cpu_time_gray),
		.board_req_valid(board_req_valid),
		.board_req_ready(board_req_ready),
		.board_req_addr(board_req_addr),
		.board_req_wdata(board_req_wdata),
		.board_req_write(board_req_write),
		.board_req_is_fetch(board_req_fetch),
		.board_req_wstrb(board_req_wstrb),
		.board_rsp_valid(board_rsp_valid),
		.board_rsp_ready(board_rsp_ready),
		.board_rsp_rdata(board_rsp_rdata),
		.board_rsp_error(board_rsp_error),
		.gex_win_req_valid(gex_win_req_valid),
		.gex_win_req_ready(gex_win_req_ready),
		.gex_win_req_addr(gex_win_req_addr),
		.gex_win_req_write(gex_win_req_write),
		.gex_win_req_wdata(gex_win_req_wdata),
		.gex_win_req_wstrb(gex_win_req_wstrb),
		.gex_win_rsp_valid(gex_win_rsp_valid),
		.gex_win_rsp_ready(gex_win_rsp_ready),
		.gex_win_rsp_rdata(gex_win_rsp_rdata),
		.gex_win_rsp_error(gex_win_rsp_error),
		.gex_locked_out(gex_locked_npu),
		.routing_protocol_fault(soc_fault),
		.ddr_protocol_fault(ddr_fault),
		.fatal_state_diag(fatal_state),
		.core_sleeping(sleeping),
		.m_axi_awid(s_awid),
		.m_axi_awaddr(s_awaddr),
		.m_axi_awlen(s_awlen),
		.m_axi_awsize(s_awsize),
		.m_axi_awburst(s_awburst),
		.m_axi_awvalid(s_awvalid),
		.m_axi_awready(s_awready),
		.m_axi_wdata(s_wdata),
		.m_axi_wstrb(s_wstrb),
		.m_axi_wlast(s_wlast),
		.m_axi_wvalid(s_wvalid),
		.m_axi_wready(s_wready),
		.m_axi_bid(s_bid),
		.m_axi_bresp(s_bresp),
		.m_axi_bvalid(s_bvalid),
		.m_axi_bready(s_bready),
		.m_axi_arid(s_arid),
		.m_axi_araddr(s_araddr),
		.m_axi_arlen(s_arlen),
		.m_axi_arsize(s_arsize),
		.m_axi_arburst(s_arburst),
		.m_axi_arvalid(s_arvalid),
		.m_axi_arready(s_arready),
		.m_axi_rid(s_rid),
		.m_axi_rdata(s_rdata),
		.m_axi_rresp(s_rresp),
		.m_axi_rlast(s_rlast),
		.m_axi_rvalid(s_rvalid),
		.m_axi_rready(s_rready)
	);
	soc_ov5640_config sensor_init(
		.clk_27m(sys_clk),
		.rst_n(!board27_reset),
		.SCL(auto_scl_0),
		.SDA(auto_sda_0),
		.cam_rst_n(cam_rst_0),
		.init_done(camera_init_done)
	);
	soc_ov5640_config sensor_init_1(
		.clk_27m(sys_clk),
		.rst_n(!board27_reset),
		.SCL(auto_scl_1),
		.SDA(auto_sda_1),
		.cam_rst_n(cam_rst_1),
		.init_done(camera_init_done_1)
	);
	wire camera_init_mem;
	pg_level_sync u_camera_init_sync(
		.clk(mem_clk),
		.rst(mem_reset),
		.async_level(camera_init_done),
		.level(camera_init_mem)
	);
	pg_level_sync u_camera_init_sync_1(
		.clk(mem_clk),
		.rst(mem_reset),
		.async_level(camera_init_done_1),
		.level(camera_init_mem_1)
	);
	pg_mmio_cdc camera_register_cdc(
		.src_clk(cpu_clk_fast),
		.dst_clk(mem_clk),
		.arst(arst),
		.s_req_valid(board_req_valid),
		.s_req_ready(board_req_ready),
		.s_req_addr(board_req_addr[15:0]),
		.s_req_write(board_req_write),
		.s_req_wdata(board_req_wdata),
		.s_req_wstrb(board_req_wstrb),
		.s_rsp_valid(board_rsp_valid),
		.s_rsp_ready(board_rsp_ready),
		.s_rsp_rdata(board_rsp_rdata),
		.s_rsp_error(board_rsp_error),
		.m_req_valid(cam_mem_req_valid),
		.m_req_ready(cam_mem_req_ready),
		.m_req_addr(cam_mem_req_addr),
		.m_req_write(cam_mem_req_write),
		.m_req_wdata(cam_mem_req_wdata),
		.m_req_wstrb(cam_mem_req_wstrb),
		.m_rsp_valid(cam_mem_rsp_valid),
		.m_rsp_ready(cam_mem_rsp_ready),
		.m_rsp_rdata(cam_mem_rsp_rdata),
		.m_rsp_error(cam_mem_rsp_error)
	);
	soc_camera_mmio_mem #(
		.WIDTH(1280),
		.HEIGHT(720),
		.CAPTURE_CHANNEL(1),
		.IMAGE_ACCEL_PRESENT(1)
	) camera_registers(
		.clk(mem_clk),
		.rst(mem_reset),
		.ddr_ready(ddr_ready),
		.camera_init_done(camera_init_mem),
		.req_valid(cam_mem_req_valid && (mmio_request_unit == 0)),
		.req_ready(cam_unit_req_ready),
		.req_addr(cam_mem_req_addr),
		.req_write(cam_mem_req_write),
		.req_wdata(cam_mem_req_wdata),
		.req_wstrb(cam_mem_req_wstrb),
		.rsp_valid(cam_unit_rsp_valid),
		.rsp_ready(cam_mem_rsp_ready && (mmio_response_owner == 0)),
		.rsp_rdata(cam_unit_rsp_rdata),
		.rsp_error(cam_unit_rsp_error),
		.start(camera_start),
		.frame_base(camera_frame_base),
		.camera_ready(camera_ready),
		.camera_busy(camera_busy),
		.camera_done(camera_done),
		.camera_valid(camera_valid),
		.camera_errors(camera_errors),
		.pixels_written(camera_pixels_written),
		.sensor_pixels(camera_sensor_pixels),
		.diag_words(camera_diag_words),
		.diag_snapshot(camera_diag_snapshot),
		.camera_init_done_1(camera_init_mem_1),
		.diag_words_1(camera_diag_words_1),
		.diag_snapshot_1(camera_diag_snapshot_1),
		.sccb_control(sccb_control),
		.camera_io_levels(camera_io_levels)
	);
	soc_camera_dvp_diag camera_diagnostics(
		.pclk(camera_clk_0),
		.mem_clk(mem_clk),
		.arst(arst),
		.vsync(camera0_diag_sync_held[1]),
		.href(camera0_diag_sync_held[0]),
		.snapshot_req(camera_diag_snapshot),
		.snapshot_words(camera_diag_words)
	);
	soc_camera_dvp_diag camera_diagnostics_1(
		.pclk(camera_clk_1),
		.mem_clk(mem_clk),
		.arst(arst),
		.vsync(camera_vsync_1),
		.href(camera_href_1),
		.snapshot_req(camera_diag_snapshot_1),
		.snapshot_words(camera_diag_words_1)
	);
	assign cam_mem_req_ready = (mmio_request_unit == 7 ? image_mem_req_ready : (mmio_request_unit == 6 ? concat_mem_req_ready : (mmio_request_unit == 5 ? win_mem_req_ready : (mmio_request_unit == 4 ? video_mem_req_ready : (mmio_request_unit == 3 ? display_mem_req_ready : (mmio_request_unit == 1 ? s3_mem_req_ready : (mmio_request_unit == 2 ? s2_mem_req_ready : cam_unit_req_ready)))))));
	assign cam_mem_rsp_valid = (mmio_response_owner == 7 ? image_mem_rsp_valid : (mmio_response_owner == 6 ? concat_mem_rsp_valid : (mmio_response_owner == 5 ? win_mem_rsp_valid : (mmio_response_owner == 4 ? video_mem_rsp_valid : (mmio_response_owner == 3 ? display_mem_rsp_valid : (mmio_response_owner == 1 ? s3_mem_rsp_valid : (mmio_response_owner == 2 ? s2_mem_rsp_valid : cam_unit_rsp_valid)))))));
	assign cam_mem_rsp_rdata = (mmio_response_owner == 7 ? image_mem_rsp_rdata : (mmio_response_owner == 6 ? concat_mem_rsp_rdata : (mmio_response_owner == 5 ? win_mem_rsp_rdata : (mmio_response_owner == 4 ? video_mem_rsp_rdata : (mmio_response_owner == 3 ? display_mem_rsp_rdata : (mmio_response_owner == 1 ? s3_mem_rsp_rdata : (mmio_response_owner == 2 ? s2_mem_rsp_rdata : cam_unit_rsp_rdata)))))));
	assign cam_mem_rsp_error = (mmio_response_owner == 7 ? image_mem_rsp_error : (mmio_response_owner == 6 ? concat_mem_rsp_error : (mmio_response_owner == 5 ? win_mem_rsp_error : (mmio_response_owner == 4 ? video_mem_rsp_error : (mmio_response_owner == 3 ? display_mem_rsp_error : (mmio_response_owner == 1 ? s3_mem_rsp_error : (mmio_response_owner == 2 ? s2_mem_rsp_error : cam_unit_rsp_error)))))));
	always @(posedge mem_clk)
		if (mem_reset)
			mmio_response_owner <= 0;
		else if (cam_mem_req_valid && cam_mem_req_ready)
			mmio_response_owner <= mmio_request_unit;
	wire rq_start_valid;
	wire rq_start_ready;
	wire rq_done_valid;
	wire rq_done_ready;
	wire rq_partial;
	wire rq_use_lut;
	wire rq_axi_poisoned;
	wire [3:0] rq_error;
	wire [31:0] rq_source;
	wire [31:0] rq_output;
	wire [31:0] rq_bias;
	wire [31:0] rq_mult;
	wire [31:0] rq_shift;
	wire [31:0] rq_lut;
	wire [31:0] rq_pixels;
	wire [31:0] rq_bound;
	wire [31:0] rq_read_bytes;
	wire [31:0] rq_write_bytes;
	wire [31:0] rq_stall_cycles;
	wire [31:0] rq_active_cycles;
	wire [8:0] rq_channels;
	wire [1:0] rq_rounding;
	wire signed [31:0] rq_zero;
	wire signed [31:0] rq_min;
	wire signed [31:0] rq_max;
	wire rq_dma_req_valid;
	wire rq_dma_req_ready;
	wire rq_dma_req_write;
	wire [31:0] rq_dma_req_addr;
	wire [127:0] rq_dma_req_wdata;
	wire [127:0] rq_dma_rsp_rdata;
	wire [15:0] rq_dma_req_wstrb;
	wire [3:0] rq_dma_req_id;
	wire [3:0] rq_dma_rsp_id;
	wire rq_dma_rsp_valid;
	wire rq_dma_rsp_ready;
	wire rq_dma_rsp_write;
	wire rq_dma_rsp_error;
	wire rq_dma_rsp_last;
	wire [3:0] rq_dma_req_len;
	soc_s3_mmio_mem s3_registers(
		.clk(mem_clk),
		.rst(region_reset_s3_registers),
		.ddr_ready(ddr_ready),
		.axi_poisoned(rq_axi_poisoned),
		.req_valid(cam_mem_req_valid && (mmio_request_unit == 1)),
		.req_ready(s3_mem_req_ready),
		.req_addr({4'b0000, cam_mem_req_addr[11:0]}),
		.req_write(cam_mem_req_write),
		.req_wdata(cam_mem_req_wdata),
		.req_wstrb(cam_mem_req_wstrb),
		.rsp_valid(s3_mem_rsp_valid),
		.rsp_ready(cam_mem_rsp_ready && (mmio_response_owner == 1)),
		.rsp_rdata(s3_mem_rsp_rdata),
		.rsp_error(s3_mem_rsp_error),
		.start_valid(rq_start_valid),
		.start_ready(rq_start_ready),
		.done_valid(rq_done_valid),
		.done_ready(rq_done_ready),
		.engine_error(rq_error),
		.engine_partial(rq_partial),
		.engine_read_bytes(rq_read_bytes),
		.engine_write_bytes(rq_write_bytes),
		.engine_stall_cycles(rq_stall_cycles),
		.engine_active_cycles(rq_active_cycles),
		.source_addr(rq_source),
		.output_addr(rq_output),
		.bias_addr(rq_bias),
		.multiplier_addr(rq_mult),
		.shift_addr(rq_shift),
		.lut_addr(rq_lut),
		.use_lut(rq_use_lut),
		.pixels(rq_pixels),
		.channels(rq_channels),
		.acc_abs_bound(rq_bound),
		.rounding_mode(rq_rounding),
		.output_zero(rq_zero),
		.clamp_min(rq_min),
		.clamp_max(rq_max)
	);
	soc_requant_lut_dma #(
		.DDR_BASE(32'h80000000),
		.DDR_BYTES(33'h004000000),
		.READ_BURST_ENABLE(S3_BURST_ENABLE)
	) s3_engine(
		.clk(mem_clk),
		.rst(region_reset_s3_engine),
		.start_valid(rq_start_valid),
		.start_ready(rq_start_ready),
		.source_addr(rq_source),
		.output_addr(rq_output),
		.bias_addr(rq_bias),
		.multiplier_addr(rq_mult),
		.shift_addr(rq_shift),
		.lut_addr(rq_lut),
		.use_lut(rq_use_lut),
		.pixels(rq_pixels),
		.channels(rq_channels),
		.acc_abs_bound(rq_bound),
		.rounding_mode(rq_rounding),
		.output_zero(rq_zero),
		.clamp_min(rq_min),
		.clamp_max(rq_max),
		.done_valid(rq_done_valid),
		.done_ready(rq_done_ready),
		.error_code(rq_error),
		.partial_output(rq_partial),
		.read_bytes(rq_read_bytes),
		.write_bytes(rq_write_bytes),
		.stall_cycles(rq_stall_cycles),
		.active_cycles(rq_active_cycles),
		.dma_req_valid(rq_dma_req_valid),
		.dma_req_ready(rq_dma_req_ready),
		.dma_req_write(rq_dma_req_write),
		.dma_req_addr(rq_dma_req_addr),
		.dma_req_wdata(rq_dma_req_wdata),
		.dma_req_wstrb(rq_dma_req_wstrb),
		.dma_req_id(rq_dma_req_id),
		.dma_req_len(rq_dma_req_len),
		.dma_rsp_last(rq_dma_rsp_last),
		.dma_rsp_valid(rq_dma_rsp_valid),
		.dma_rsp_ready(rq_dma_rsp_ready),
		.dma_rsp_write(rq_dma_rsp_write),
		.dma_rsp_id(rq_dma_rsp_id),
		.dma_rsp_rdata(rq_dma_rsp_rdata),
		.dma_rsp_error(rq_dma_rsp_error)
	);
	wire gex_locked_mem;
	wire gw_req_valid;
	wire gw_req_ready;
	wire gw_req_write;
	wire gw_rsp_valid;
	wire gw_rsp_ready;
	wire gw_rsp_error;
	wire [15:0] gw_req_addr;
	wire [31:0] gw_req_wdata;
	wire [31:0] gw_rsp_rdata;
	wire [3:0] gw_req_wstrb;
	wire win_reg_req_ready;
	wire win_reg_rsp_valid;
	wire win_reg_rsp_ready;
	wire win_reg_rsp_error;
	reg win_reg_owner;
	wire [31:0] win_reg_rsp_data;
	pg_level_sync gex_window_lease_sync(
		.clk(mem_clk),
		.rst(mem_reset),
		.async_level(gex_locked_npu),
		.level(gex_locked_mem)
	);
	pg_mmio_cdc gex_window_register_cdc(
		.src_clk(npu_clk_fast),
		.dst_clk(mem_clk),
		.arst(arst),
		.s_req_valid(gex_win_req_valid),
		.s_req_ready(gex_win_req_ready),
		.s_req_addr(gex_win_req_addr),
		.s_req_write(gex_win_req_write),
		.s_req_wdata(gex_win_req_wdata),
		.s_req_wstrb(gex_win_req_wstrb),
		.s_rsp_valid(gex_win_rsp_valid),
		.s_rsp_ready(gex_win_rsp_ready),
		.s_rsp_rdata(gex_win_rsp_rdata),
		.s_rsp_error(gex_win_rsp_error),
		.m_req_valid(gw_req_valid),
		.m_req_ready(gw_req_ready),
		.m_req_addr(gw_req_addr),
		.m_req_write(gw_req_write),
		.m_req_wdata(gw_req_wdata),
		.m_req_wstrb(gw_req_wstrb),
		.m_rsp_valid(gw_rsp_valid),
		.m_rsp_ready(gw_rsp_ready),
		.m_rsp_rdata(gw_rsp_rdata),
		.m_rsp_error(gw_rsp_error)
	);
	assign gw_req_ready = win_reg_req_ready;
	assign win_mem_req_ready = (win_reg_req_ready && !gex_locked_mem) && !gw_req_valid;
	assign gw_rsp_valid = win_reg_rsp_valid && win_reg_owner;
	assign gw_rsp_rdata = win_reg_rsp_data;
	assign gw_rsp_error = win_reg_rsp_error;
	assign win_mem_rsp_valid = win_reg_rsp_valid && !win_reg_owner;
	assign win_mem_rsp_rdata = win_reg_rsp_data;
	assign win_mem_rsp_error = win_reg_rsp_error;
	assign win_reg_rsp_ready = (win_reg_owner ? gw_rsp_ready : cam_mem_rsp_ready && (mmio_response_owner == 5));
	always @(posedge mem_clk)
		if (mem_reset)
			win_reg_owner <= 0;
		else if (win_reg_req_ready && (gw_req_valid || ((cam_mem_req_valid && (mmio_request_unit == 5)) && !gex_locked_mem)))
			win_reg_owner <= gw_req_valid;
	wire win_start;
	wire win_ready;
	wire win_busy;
	wire win_done;
	wire win_partial;
	wire win_flush;
	wire [7:0] win_error;
	wire [31:0] win_input_base;
	wire [31:0] win_scratch_base;
	wire [31:0] win_first_row;
	wire [15:0] win_input_h;
	wire [15:0] win_input_w;
	wire [15:0] win_input_c;
	wire [15:0] win_output_h;
	wire [15:0] win_output_w;
	wire [15:0] win_first_oy;
	wire [15:0] win_first_ox;
	wire [15:0] win_row_count;
	wire [7:0] win_kernel_h;
	wire [7:0] win_kernel_w;
	wire [7:0] win_stride_h;
	wire [7:0] win_stride_w;
	wire [7:0] win_dilation_h;
	wire [7:0] win_dilation_w;
	wire [7:0] win_pad_top;
	wire [7:0] win_pad_left;
	wire [7:0] win_pad_bottom;
	wire [7:0] win_pad_right;
	wire [31:0] win_read_bytes;
	wire [31:0] win_write_bytes;
	wire [31:0] win_cache_hits;
	wire [31:0] win_cache_misses;
	wire [31:0] win_active_cycles;
	wire [31:0] win_stall_cycles;
	wire win_dma_req_valid;
	wire win_dma_req_ready;
	wire win_dma_req_write;
	wire [31:0] win_dma_req_addr;
	wire [127:0] win_dma_req_wdata;
	wire [127:0] win_dma_rsp_rdata;
	wire [15:0] win_dma_req_wstrb;
	wire [3:0] win_dma_req_id;
	wire [3:0] win_dma_rsp_id;
	wire [3:0] win_dma_req_len;
	wire win_dma_rsp_valid;
	wire win_dma_rsp_ready;
	wire win_dma_rsp_write;
	wire win_dma_rsp_error;
	soc_window_mmio_mem window_registers(
		.clk(mem_clk),
		.rst(region_reset_window_registers),
		.ddr_ready(ddr_ready),
		.axi_poisoned(rq_axi_poisoned),
		.req_valid(gw_req_valid || ((cam_mem_req_valid && (mmio_request_unit == 5)) && !gex_locked_mem)),
		.req_ready(win_reg_req_ready),
		.req_addr((gw_req_valid ? gw_req_addr : {4'b0000, cam_mem_req_addr[11:0]})),
		.req_write((gw_req_valid ? gw_req_write : cam_mem_req_write)),
		.req_wdata((gw_req_valid ? gw_req_wdata : cam_mem_req_wdata)),
		.req_wstrb((gw_req_valid ? gw_req_wstrb : cam_mem_req_wstrb)),
		.rsp_valid(win_reg_rsp_valid),
		.rsp_ready(win_reg_rsp_ready),
		.rsp_rdata(win_reg_rsp_data),
		.rsp_error(win_reg_rsp_error),
		.engine_start(win_start),
		.engine_ready(win_ready),
		.engine_done(win_done),
		.engine_error(win_error),
		.engine_partial(win_partial),
		.engine_read_bytes(win_read_bytes),
		.engine_write_bytes(win_write_bytes),
		.engine_cache_hits(win_cache_hits),
		.engine_cache_misses(win_cache_misses),
		.engine_active_cycles(win_active_cycles),
		.engine_stall_cycles(win_stall_cycles),
		.input_base(win_input_base),
		.scratch_base(win_scratch_base),
		.first_row(win_first_row),
		.input_h(win_input_h),
		.input_w(win_input_w),
		.input_c(win_input_c),
		.output_h(win_output_h),
		.output_w(win_output_w),
		.first_oy(win_first_oy),
		.first_ox(win_first_ox),
		.row_count(win_row_count),
		.kernel_h(win_kernel_h),
		.kernel_w(win_kernel_w),
		.stride_h(win_stride_h),
		.stride_w(win_stride_w),
		.dilation_h(win_dilation_h),
		.dilation_w(win_dilation_w),
		.pad_top(win_pad_top),
		.pad_left(win_pad_left),
		.pad_bottom(win_pad_bottom),
		.pad_right(win_pad_right),
		.flush_cache(win_flush)
	);
	wire win_dma_rsp_last;
	soc_window_gather_dma #(
		.DDR_BASE(32'h80000000),
		.DDR_BYTES(32'h04000000),
		.WRITE_BURST_ENABLE(S3_BURST_ENABLE)
	) window_engine(
		.clk(mem_clk),
		.rst(region_reset_window_engine),
		.start(win_start),
		.flush_cache(win_flush),
		.input_base(win_input_base),
		.scratch_base(win_scratch_base),
		.first_row(win_first_row),
		.input_h(win_input_h),
		.input_w(win_input_w),
		.input_c(win_input_c),
		.output_h(win_output_h),
		.output_w(win_output_w),
		.first_oy(win_first_oy),
		.first_ox(win_first_ox),
		.kernel_h(win_kernel_h),
		.kernel_w(win_kernel_w),
		.stride_h(win_stride_h),
		.stride_w(win_stride_w),
		.dilation_h(win_dilation_h),
		.dilation_w(win_dilation_w),
		.pad_top(win_pad_top),
		.pad_left(win_pad_left),
		.pad_bottom(win_pad_bottom),
		.pad_right(win_pad_right),
		.row_count(win_row_count),
		.ready(win_ready),
		.busy(win_busy),
		.done_pulse(win_done),
		.partial_output(win_partial),
		.error_sticky(win_error),
		.source_read_bytes(win_read_bytes),
		.scratch_write_bytes(win_write_bytes),
		.cache_hits(win_cache_hits),
		.cache_misses(win_cache_misses),
		.active_cycles(win_active_cycles),
		.stall_cycles(win_stall_cycles),
		.dma_req_valid(win_dma_req_valid),
		.dma_req_ready(win_dma_req_ready),
		.dma_req_write(win_dma_req_write),
		.dma_req_addr(win_dma_req_addr),
		.dma_req_wdata(win_dma_req_wdata),
		.dma_req_wstrb(win_dma_req_wstrb),
		.dma_req_id(win_dma_req_id),
		.dma_req_len(win_dma_req_len),
		.dma_rsp_last(win_dma_rsp_last),
		.dma_rsp_valid(win_dma_rsp_valid),
		.dma_rsp_ready(win_dma_rsp_ready),
		.dma_rsp_write(win_dma_rsp_write),
		.dma_rsp_id(win_dma_rsp_id),
		.dma_rsp_rdata(win_dma_rsp_rdata),
		.dma_rsp_error(win_dma_rsp_error)
	);
	wire native_req_valid;
	wire native_req_ready;
	wire native_req_write;
	wire [31:0] native_req_addr;
	wire [127:0] native_req_wdata;
	wire [127:0] native_rsp_rdata;
	wire [15:0] native_req_wstrb;
	wire [3:0] native_req_id;
	wire [3:0] native_rsp_id;
	wire native_rsp_valid;
	wire native_rsp_ready;
	wire native_rsp_write;
	wire native_rsp_error;
	wire native_rsp_last;
	wire [3:0] native_req_len;
	soc_native_2m_arbiter #(.BURST_ENABLE(S3_BURST_ENABLE)) s3_window_share(
		.clk(mem_clk),
		.rst(mem_reset),
		.s_req_valid({win_dma_req_valid, rq_dma_req_valid}),
		.s_req_ready({win_dma_req_ready, rq_dma_req_ready}),
		.s_req_write({win_dma_req_write, rq_dma_req_write}),
		.s_req_addr({win_dma_req_addr, rq_dma_req_addr}),
		.s_req_wdata({win_dma_req_wdata, rq_dma_req_wdata}),
		.s_req_wstrb({win_dma_req_wstrb, rq_dma_req_wstrb}),
		.s_req_id({win_dma_req_id, rq_dma_req_id}),
		.s_req_len({win_dma_req_len, rq_dma_req_len}),
		.s_rsp_last({win_dma_rsp_last, rq_dma_rsp_last}),
		.s_rsp_valid({win_dma_rsp_valid, rq_dma_rsp_valid}),
		.s_rsp_ready({win_dma_rsp_ready, rq_dma_rsp_ready}),
		.s_rsp_write({win_dma_rsp_write, rq_dma_rsp_write}),
		.s_rsp_id({win_dma_rsp_id, rq_dma_rsp_id}),
		.s_rsp_rdata({win_dma_rsp_rdata, rq_dma_rsp_rdata}),
		.s_rsp_error({win_dma_rsp_error, rq_dma_rsp_error}),
		.m_req_valid(native_req_valid),
		.m_req_ready(native_req_ready),
		.m_req_write(native_req_write),
		.m_req_addr(native_req_addr),
		.m_req_wdata(native_req_wdata),
		.m_req_wstrb(native_req_wstrb),
		.m_req_id(native_req_id),
		.m_req_len(native_req_len),
		.m_rsp_last(native_rsp_last),
		.m_rsp_valid(native_rsp_valid),
		.m_rsp_ready(native_rsp_ready),
		.m_rsp_write(native_rsp_write),
		.m_rsp_id(native_rsp_id),
		.m_rsp_rdata(native_rsp_rdata),
		.m_rsp_error(native_rsp_error)
	);
	wire [3:0] q_awid;
	wire [3:0] q_bid;
	wire [3:0] q_arid;
	wire [3:0] q_rid;
	wire concat_start;
	wire concat_ready;
	wire concat_busy;
	wire concat_done;
	wire concat_partial;
	wire tensor_cancel;
	wire tensor_poison;
	wire [1:0] tensor_operation;
	wire [15:0] tensor_h;
	wire [15:0] tensor_w;
	wire [7:0] concat_error;
	wire [31:0] concat_input;
	wire [31:0] concat_aux;
	wire [31:0] concat_output;
	wire [31:0] concat_pixels;
	wire [15:0] concat_input_c;
	wire [15:0] concat_aux_c;
	wire [31:0] concat_read_bytes;
	wire [31:0] concat_write_bytes;
	wire [31:0] concat_active;
	wire [31:0] concat_stall;
	wire cat_req_valid;
	wire cat_req_ready;
	wire cat_req_write;
	wire cat_rsp_valid;
	wire cat_rsp_ready;
	wire cat_rsp_write;
	wire cat_rsp_error;
	wire [31:0] cat_req_addr;
	wire [127:0] cat_req_wdata;
	wire [127:0] cat_rsp_rdata;
	wire [15:0] cat_req_wstrb;
	wire [3:0] cat_req_id;
	wire [3:0] cat_rsp_id;
	wire [3:0] cat_req_len;
	wire cat_rsp_last;
	soc_concat_mmio_mem concat_registers(
		.clk(mem_clk),
		.rst(region_reset_concat_registers),
		.ddr_ready(ddr_ready),
		.axi_poisoned(rq_axi_poisoned | tensor_poison),
		.req_valid(cam_mem_req_valid && (mmio_request_unit == 6)),
		.req_ready(concat_mem_req_ready),
		.req_addr({4'b0000, cam_mem_req_addr[11:0]}),
		.req_write(cam_mem_req_write),
		.req_wdata(cam_mem_req_wdata),
		.req_wstrb(cam_mem_req_wstrb),
		.rsp_valid(concat_mem_rsp_valid),
		.rsp_ready(cam_mem_rsp_ready && (mmio_response_owner == 6)),
		.rsp_rdata(concat_mem_rsp_rdata),
		.rsp_error(concat_mem_rsp_error),
		.engine_start(concat_start),
		.engine_cancel(tensor_cancel),
		.operation(tensor_operation),
		.image_h(tensor_h),
		.image_w(tensor_w),
		.engine_ready(concat_ready),
		.engine_done(concat_done),
		.engine_error(concat_error),
		.engine_partial(concat_partial),
		.engine_read_bytes(concat_read_bytes),
		.engine_write_bytes(concat_write_bytes),
		.engine_active_cycles(concat_active),
		.engine_stall_cycles(concat_stall),
		.input_base(concat_input),
		.aux_base(concat_aux),
		.output_base(concat_output),
		.pixels(concat_pixels),
		.input_channels(concat_input_c),
		.aux_channels(concat_aux_c),
		.irq_level(concat_irq_mem)
	);
	pg_level_sync concat_completion_sync(
		.clk(cpu_clk_fast),
		.rst(cpu_reset),
		.async_level(concat_irq_mem),
		.level(concat_irq_cpu)
	);
	soc_concat_dma #(
		.READ_BURST_ENABLE(S3_BURST_ENABLE),
		.WRITE_BURST_ENABLE(S3_BURST_ENABLE)
	) concat_engine(
		.clk(mem_clk),
		.rst(region_reset_concat_engine),
		.start(concat_start),
		.cancel(tensor_cancel),
		.protocol_poison(tensor_poison),
		.operation(tensor_operation),
		.image_h(tensor_h),
		.image_w(tensor_w),
		.input_base(concat_input),
		.aux_base(concat_aux),
		.output_base(concat_output),
		.pixels(concat_pixels),
		.input_channels(concat_input_c),
		.aux_channels(concat_aux_c),
		.ready(concat_ready),
		.busy(concat_busy),
		.done_pulse(concat_done),
		.partial_output(concat_partial),
		.error_sticky(concat_error),
		.read_bytes(concat_read_bytes),
		.write_bytes(concat_write_bytes),
		.active_cycles(concat_active),
		.stall_cycles(concat_stall),
		.dma_req_valid(cat_req_valid),
		.dma_req_ready(cat_req_ready),
		.dma_req_write(cat_req_write),
		.dma_req_addr(cat_req_addr),
		.dma_req_wdata(cat_req_wdata),
		.dma_req_wstrb(cat_req_wstrb),
		.dma_req_id(cat_req_id),
		.dma_req_len(cat_req_len),
		.dma_rsp_last(cat_rsp_last),
		.dma_rsp_valid(cat_rsp_valid),
		.dma_rsp_ready(cat_rsp_ready),
		.dma_rsp_write(cat_rsp_write),
		.dma_rsp_id(cat_rsp_id),
		.dma_rsp_rdata(cat_rsp_rdata),
		.dma_rsp_error(cat_rsp_error)
	);
	wire shared_req_valid;
	wire shared_req_ready;
	wire shared_req_write;
	wire [31:0] shared_req_addr;
	wire [127:0] shared_req_wdata;
	wire [127:0] shared_rsp_rdata;
	wire [15:0] shared_req_wstrb;
	wire [3:0] shared_req_id;
	wire [3:0] shared_rsp_id;
	wire shared_rsp_valid;
	wire shared_rsp_ready;
	wire shared_rsp_write;
	wire shared_rsp_error;
	wire shared_rsp_last;
	wire [3:0] shared_req_len;
	soc_native_2m_arbiter #(.BURST_ENABLE(S3_BURST_ENABLE)) tensor_native_share(
		.clk(mem_clk),
		.rst(mem_reset),
		.s_req_valid({cat_req_valid, native_req_valid}),
		.s_req_ready({cat_req_ready, native_req_ready}),
		.s_req_write({cat_req_write, native_req_write}),
		.s_req_addr({cat_req_addr, native_req_addr}),
		.s_req_wdata({cat_req_wdata, native_req_wdata}),
		.s_req_wstrb({cat_req_wstrb, native_req_wstrb}),
		.s_req_len({cat_req_len, native_req_len}),
		.s_rsp_last({cat_rsp_last, native_rsp_last}),
		.s_req_id({cat_req_id, native_req_id}),
		.s_rsp_valid({cat_rsp_valid, native_rsp_valid}),
		.s_rsp_ready({cat_rsp_ready, native_rsp_ready}),
		.s_rsp_write({cat_rsp_write, native_rsp_write}),
		.s_rsp_id({cat_rsp_id, native_rsp_id}),
		.s_rsp_rdata({cat_rsp_rdata, native_rsp_rdata}),
		.s_rsp_error({cat_rsp_error, native_rsp_error}),
		.m_req_valid(shared_req_valid),
		.m_req_ready(shared_req_ready),
		.m_req_write(shared_req_write),
		.m_req_addr(shared_req_addr),
		.m_req_wdata(shared_req_wdata),
		.m_req_wstrb(shared_req_wstrb),
		.m_req_id(shared_req_id),
		.m_req_len(shared_req_len),
		.m_rsp_last(shared_rsp_last),
		.m_rsp_valid(shared_rsp_valid),
		.m_rsp_ready(shared_rsp_ready),
		.m_rsp_write(shared_rsp_write),
		.m_rsp_id(shared_rsp_id),
		.m_rsp_rdata(shared_rsp_rdata),
		.m_rsp_error(shared_rsp_error)
	);
	wire [31:0] q_awaddr;
	wire [31:0] q_araddr;
	wire [7:0] q_awlen;
	wire [7:0] q_arlen;
	wire [2:0] q_awsize;
	wire [2:0] q_arsize;
	wire [1:0] q_awburst;
	wire [1:0] q_arburst;
	wire [1:0] q_bresp;
	wire [1:0] q_rresp;
	wire q_awvalid;
	wire q_awready;
	wire q_wlast;
	wire q_wvalid;
	wire q_wready;
	wire q_bvalid;
	wire q_bready;
	wire q_arvalid;
	wire q_arready;
	wire q_rlast;
	wire q_rvalid;
	wire q_rready;
	wire [127:0] q_wdata;
	wire [127:0] q_rdata;
	wire [15:0] q_wstrb;
	soc_rq_to_axi #(.BURST_ENABLE(S3_BURST_ENABLE)) s3_axi(
		.clk(mem_clk),
		.rst(region_reset_s3_axi),
		.ddr_ready(ddr_ready),
		.req_valid(shared_req_valid),
		.req_ready(shared_req_ready),
		.req_write(shared_req_write),
		.req_addr(shared_req_addr),
		.req_wdata(shared_req_wdata),
		.req_wstrb(shared_req_wstrb),
		.req_len(shared_req_len),
		.rsp_last(shared_rsp_last),
		.req_id(shared_req_id),
		.rsp_valid(shared_rsp_valid),
		.rsp_ready(shared_rsp_ready),
		.rsp_write(shared_rsp_write),
		.rsp_id(shared_rsp_id),
		.rsp_rdata(shared_rsp_rdata),
		.rsp_error(shared_rsp_error),
		.poisoned(rq_axi_poisoned),
		.m_awid(q_awid),
		.m_awaddr(q_awaddr),
		.m_awlen(q_awlen),
		.m_awsize(q_awsize),
		.m_awburst(q_awburst),
		.m_awvalid(q_awvalid),
		.m_awready(q_awready),
		.m_wdata(q_wdata),
		.m_wstrb(q_wstrb),
		.m_wlast(q_wlast),
		.m_wvalid(q_wvalid),
		.m_wready(q_wready),
		.m_bid(q_bid),
		.m_bresp(q_bresp),
		.m_bvalid(q_bvalid),
		.m_bready(q_bready),
		.m_arid(q_arid),
		.m_araddr(q_araddr),
		.m_arlen(q_arlen),
		.m_arsize(q_arsize),
		.m_arburst(q_arburst),
		.m_arvalid(q_arvalid),
		.m_arready(q_arready),
		.m_rid(q_rid),
		.m_rdata(q_rdata),
		.m_rresp(q_rresp),
		.m_rlast(q_rlast),
		.m_rvalid(q_rvalid),
		.m_rready(q_rready)
	);
	wire [3:0] c_awid;
	wire [3:0] c_bid;
	wire [3:0] c_arid;
	wire [3:0] c_rid;
	wire [31:0] c_awaddr;
	wire [31:0] c_araddr;
	wire [7:0] c_awlen;
	wire [7:0] c_arlen;
	wire [2:0] c_awsize;
	wire [2:0] c_arsize;
	wire [1:0] c_awburst;
	wire [1:0] c_arburst;
	wire [1:0] c_bresp;
	wire [1:0] c_rresp;
	wire c_awvalid;
	wire c_awready;
	wire c_wlast;
	wire c_wvalid;
	wire c_wready;
	wire c_bvalid;
	wire c_bready;
	wire c_arvalid;
	wire c_arready;
	wire c_rlast;
	wire c_rvalid;
	wire c_rready;
	wire [127:0] c_wdata;
	wire [127:0] c_rdata;
	wire [15:0] c_wstrb;
	soc_camera_frame_pipeline #(
		.WIDTH(1280),
		.HEIGHT(720)
	) camera_frame(
		.pclk(camera_clk_1),
		.mem_clk(mem_clk),
		.arst(arst),
		.start(camera_start),
		.frame_base(camera_frame_base),
		.vsync(camera_vsync_1),
		.href(camera_href_1),
		.byte_data(camera_data_held),
		.ready(camera_ready),
		.busy(camera_busy),
		.done_pulse(camera_done),
		.frame_valid(camera_valid),
		.error_sticky(camera_errors),
		.pixels_written(camera_pixels_written),
		.sensor_pixels(camera_sensor_pixels),
		.m_awid(c_awid),
		.m_awaddr(c_awaddr),
		.m_awlen(c_awlen),
		.m_awsize(c_awsize),
		.m_awburst(c_awburst),
		.m_awvalid(c_awvalid),
		.m_awready(c_awready),
		.m_wdata(c_wdata),
		.m_wstrb(c_wstrb),
		.m_wlast(c_wlast),
		.m_wvalid(c_wvalid),
		.m_wready(c_wready),
		.m_bid(c_bid),
		.m_bresp(c_bresp),
		.m_bvalid(c_bvalid),
		.m_bready(c_bready)
	);
	assign c_arid = 0;
	assign c_araddr = 0;
	assign c_arlen = 0;
	assign c_arsize = 0;
	assign c_arburst = 0;
	assign c_arvalid = 0;
	assign c_rready = 1'b1;
	wire [3:0] a_awid;
	wire [3:0] a_bid;
	wire [3:0] a_arid;
	wire [3:0] a_rid;
	wire [31:0] a_awaddr;
	wire [31:0] a_araddr;
	wire [7:0] a_awlen;
	wire [7:0] a_arlen;
	wire [2:0] a_awsize;
	wire [2:0] a_arsize;
	wire [1:0] a_awburst;
	wire [1:0] a_arburst;
	wire [1:0] a_bresp;
	wire [1:0] a_rresp;
	wire a_awvalid;
	wire a_awready;
	wire a_wlast;
	wire a_wvalid;
	wire a_wready;
	wire a_bvalid;
	wire a_bready;
	wire a_arvalid;
	wire a_arready;
	wire a_rlast;
	wire a_rvalid;
	wire a_rready;
	wire [127:0] a_wdata;
	wire [127:0] a_rdata;
	wire [15:0] a_wstrb;
	wire [3:0] b_awid;
	wire [3:0] b_bid;
	wire [3:0] b_arid;
	wire [3:0] b_rid;
	wire [31:0] b_awaddr;
	wire [31:0] b_araddr;
	wire [7:0] b_awlen;
	wire [7:0] b_arlen;
	wire [2:0] b_awsize;
	wire [2:0] b_arsize;
	wire [1:0] b_awburst;
	wire [1:0] b_arburst;
	wire [1:0] b_bresp;
	wire [1:0] b_rresp;
	wire b_awvalid;
	wire b_awready;
	wire b_wlast;
	wire b_wvalid;
	wire b_wready;
	wire b_bvalid;
	wire b_bready;
	wire b_arvalid;
	wire b_arready;
	wire b_rlast;
	wire b_rvalid;
	wire b_rready;
	wire [127:0] b_wdata;
	wire [127:0] b_rdata;
	wire [15:0] b_wstrb;
	wire [3:0] v_awid;
	wire [3:0] v_bid;
	wire [3:0] v_arid;
	wire [3:0] v_rid;
	wire [31:0] v_awaddr;
	wire [31:0] v_araddr;
	wire [7:0] v_awlen;
	wire [7:0] v_arlen;
	wire [2:0] v_awsize;
	wire [2:0] v_arsize;
	wire [1:0] v_awburst;
	wire [1:0] v_arburst;
	wire [1:0] v_bresp;
	wire [1:0] v_rresp;
	wire v_awvalid;
	wire v_awready;
	wire v_wlast;
	wire v_wvalid;
	wire v_wready;
	wire v_bvalid;
	wire v_bready;
	wire v_arvalid;
	wire v_arready;
	wire v_rlast;
	wire v_rvalid;
	wire v_rready;
	wire [127:0] v_wdata;
	wire [127:0] v_rdata;
	wire [15:0] v_wstrb;
	wire [3:0] vr_awid;
	wire [3:0] vr_bid;
	wire [3:0] vr_arid;
	wire [3:0] vr_rid;
	wire [31:0] vr_awaddr;
	wire [31:0] vr_araddr;
	wire [7:0] vr_awlen;
	wire [7:0] vr_arlen;
	wire [2:0] vr_awsize;
	wire [2:0] vr_arsize;
	wire [1:0] vr_awburst;
	wire [1:0] vr_arburst;
	wire [1:0] vr_bresp;
	wire [1:0] vr_rresp;
	wire vr_awvalid;
	wire vr_awready;
	wire vr_wlast;
	wire vr_wvalid;
	wire vr_wready;
	wire vr_bvalid;
	wire vr_bready;
	wire vr_arvalid;
	wire vr_arready;
	wire vr_rlast;
	wire vr_rvalid;
	wire vr_rready;
	wire [127:0] vr_wdata;
	wire [127:0] vr_rdata;
	wire [15:0] vr_wstrb;
	soc_v2_replay_pipeline v2_replay(
		.clk(mem_clk),
		.rst(region_reset_v2_replay),
		.ddr_ready(ddr_ready),
		.req_valid(cam_mem_req_valid && (mmio_request_unit == 2)),
		.req_ready(s2_mem_req_ready),
		.req_addr({4'b0000, cam_mem_req_addr[11:0]}),
		.req_write(cam_mem_req_write),
		.req_wdata(cam_mem_req_wdata),
		.req_wstrb(cam_mem_req_wstrb),
		.rsp_valid(s2_mem_rsp_valid),
		.rsp_ready(cam_mem_rsp_ready && (mmio_response_owner == 2)),
		.rsp_rdata(s2_mem_rsp_rdata),
		.rsp_error(s2_mem_rsp_error),
		.m_awid(vr_awid),
		.m_awaddr(vr_awaddr),
		.m_awlen(vr_awlen),
		.m_awsize(vr_awsize),
		.m_awburst(vr_awburst),
		.m_awvalid(vr_awvalid),
		.m_awready(vr_awready),
		.m_wdata(vr_wdata),
		.m_wstrb(vr_wstrb),
		.m_wlast(vr_wlast),
		.m_wvalid(vr_wvalid),
		.m_wready(vr_wready),
		.m_bid(vr_bid),
		.m_bresp(vr_bresp),
		.m_bvalid(vr_bvalid),
		.m_bready(vr_bready),
		.m_arid(vr_arid),
		.m_araddr(vr_araddr),
		.m_arlen(vr_arlen),
		.m_arsize(vr_arsize),
		.m_arburst(vr_arburst),
		.m_arvalid(vr_arvalid),
		.m_arready(vr_arready),
		.m_rid(vr_rid),
		.m_rdata(vr_rdata),
		.m_rresp(vr_rresp),
		.m_rlast(vr_rlast),
		.m_rvalid(vr_rvalid),
		.m_rready(vr_rready)
	);
	soc_axi_2m_arbiter camera_share(
		.clk(mem_clk),
		.rst(region_reset_camera_share),
		.busy(),
		.s_awid({c_awid, s_awid}),
		.s_awaddr({c_awaddr, s_awaddr}),
		.s_awlen({c_awlen, s_awlen}),
		.s_awsize({c_awsize, s_awsize}),
		.s_awburst({c_awburst, s_awburst}),
		.s_awvalid({c_awvalid, s_awvalid}),
		.s_awready({c_awready, s_awready}),
		.s_wdata({c_wdata, s_wdata}),
		.s_wstrb({c_wstrb, s_wstrb}),
		.s_wlast({c_wlast, s_wlast}),
		.s_wvalid({c_wvalid, s_wvalid}),
		.s_wready({c_wready, s_wready}),
		.s_bid({c_bid, s_bid}),
		.s_bresp({c_bresp, s_bresp}),
		.s_bvalid({c_bvalid, s_bvalid}),
		.s_bready({c_bready, s_bready}),
		.s_arid({c_arid, s_arid}),
		.s_araddr({c_araddr, s_araddr}),
		.s_arlen({c_arlen, s_arlen}),
		.s_arsize({c_arsize, s_arsize}),
		.s_arburst({c_arburst, s_arburst}),
		.s_arvalid({c_arvalid, s_arvalid}),
		.s_arready({c_arready, s_arready}),
		.s_rid({c_rid, s_rid}),
		.s_rdata({c_rdata, s_rdata}),
		.s_rresp({c_rresp, s_rresp}),
		.s_rlast({c_rlast, s_rlast}),
		.s_rvalid({c_rvalid, s_rvalid}),
		.s_rready({c_rready, s_rready}),
		.m_awid(a_awid),
		.m_awaddr(a_awaddr),
		.m_awlen(a_awlen),
		.m_awsize(a_awsize),
		.m_awburst(a_awburst),
		.m_awvalid(a_awvalid),
		.m_awready(a_awready),
		.m_wdata(a_wdata),
		.m_wstrb(a_wstrb),
		.m_wlast(a_wlast),
		.m_wvalid(a_wvalid),
		.m_wready(a_wready),
		.m_bid(a_bid),
		.m_bresp(a_bresp),
		.m_bvalid(a_bvalid),
		.m_bready(a_bready),
		.m_arid(a_arid),
		.m_araddr(a_araddr),
		.m_arlen(a_arlen),
		.m_arsize(a_arsize),
		.m_arburst(a_arburst),
		.m_arvalid(a_arvalid),
		.m_arready(a_arready),
		.m_rid(a_rid),
		.m_rdata(a_rdata),
		.m_rresp(a_rresp),
		.m_rlast(a_rlast),
		.m_rvalid(a_rvalid),
		.m_rready(a_rready)
	);
	soc_axi_2m_arbiter s3_share(
		.clk(mem_clk),
		.rst(region_reset_s3_share),
		.busy(),
		.s_awid({q_awid, a_awid}),
		.s_awaddr({q_awaddr, a_awaddr}),
		.s_awlen({q_awlen, a_awlen}),
		.s_awsize({q_awsize, a_awsize}),
		.s_awburst({q_awburst, a_awburst}),
		.s_awvalid({q_awvalid, a_awvalid}),
		.s_awready({q_awready, a_awready}),
		.s_wdata({q_wdata, a_wdata}),
		.s_wstrb({q_wstrb, a_wstrb}),
		.s_wlast({q_wlast, a_wlast}),
		.s_wvalid({q_wvalid, a_wvalid}),
		.s_wready({q_wready, a_wready}),
		.s_bid({q_bid, a_bid}),
		.s_bresp({q_bresp, a_bresp}),
		.s_bvalid({q_bvalid, a_bvalid}),
		.s_bready({q_bready, a_bready}),
		.s_arid({q_arid, a_arid}),
		.s_araddr({q_araddr, a_araddr}),
		.s_arlen({q_arlen, a_arlen}),
		.s_arsize({q_arsize, a_arsize}),
		.s_arburst({q_arburst, a_arburst}),
		.s_arvalid({q_arvalid, a_arvalid}),
		.s_arready({q_arready, a_arready}),
		.s_rid({q_rid, a_rid}),
		.s_rdata({q_rdata, a_rdata}),
		.s_rresp({q_rresp, a_rresp}),
		.s_rlast({q_rlast, a_rlast}),
		.s_rvalid({q_rvalid, a_rvalid}),
		.s_rready({q_rready, a_rready}),
		.m_awid(b_awid),
		.m_awaddr(b_awaddr),
		.m_awlen(b_awlen),
		.m_awsize(b_awsize),
		.m_awburst(b_awburst),
		.m_awvalid(b_awvalid),
		.m_awready(b_awready),
		.m_wdata(b_wdata),
		.m_wstrb(b_wstrb),
		.m_wlast(b_wlast),
		.m_wvalid(b_wvalid),
		.m_wready(b_wready),
		.m_bid(b_bid),
		.m_bresp(b_bresp),
		.m_bvalid(b_bvalid),
		.m_bready(b_bready),
		.m_arid(b_arid),
		.m_araddr(b_araddr),
		.m_arlen(b_arlen),
		.m_arsize(b_arsize),
		.m_arburst(b_arburst),
		.m_arvalid(b_arvalid),
		.m_arready(b_arready),
		.m_rid(b_rid),
		.m_rdata(b_rdata),
		.m_rresp(b_rresp),
		.m_rlast(b_rlast),
		.m_rvalid(b_rvalid),
		.m_rready(b_rready)
	);
	wire [3:0] d_awid;
	wire [3:0] d_bid;
	wire [3:0] d_arid;
	wire [3:0] d_rid;
	wire [31:0] d_awaddr;
	wire [31:0] d_araddr;
	wire [7:0] d_awlen;
	wire [7:0] d_arlen;
	wire [2:0] d_awsize;
	wire [2:0] d_arsize;
	wire [1:0] d_awburst;
	wire [1:0] d_arburst;
	wire [1:0] d_bresp;
	wire [1:0] d_rresp;
	wire d_awvalid;
	wire d_awready;
	wire d_wlast;
	wire d_wvalid;
	wire d_wready;
	wire d_bvalid;
	wire d_bready;
	wire d_arvalid;
	wire d_arready;
	wire d_rlast;
	wire d_rvalid;
	wire d_rready;
	wire [127:0] d_wdata;
	wire [127:0] d_rdata;
	wire [15:0] d_wstrb;
	soc_axi_2m_arbiter v2_share(
		.clk(mem_clk),
		.rst(region_reset_v2_share),
		.busy(),
		.s_awid({v_awid, b_awid}),
		.s_awaddr({v_awaddr, b_awaddr}),
		.s_awlen({v_awlen, b_awlen}),
		.s_awsize({v_awsize, b_awsize}),
		.s_awburst({v_awburst, b_awburst}),
		.s_awvalid({v_awvalid, b_awvalid}),
		.s_awready({v_awready, b_awready}),
		.s_wdata({v_wdata, b_wdata}),
		.s_wstrb({v_wstrb, b_wstrb}),
		.s_wlast({v_wlast, b_wlast}),
		.s_wvalid({v_wvalid, b_wvalid}),
		.s_wready({v_wready, b_wready}),
		.s_bid({v_bid, b_bid}),
		.s_bresp({v_bresp, b_bresp}),
		.s_bvalid({v_bvalid, b_bvalid}),
		.s_bready({v_bready, b_bready}),
		.s_arid({v_arid, b_arid}),
		.s_araddr({v_araddr, b_araddr}),
		.s_arlen({v_arlen, b_arlen}),
		.s_arsize({v_arsize, b_arsize}),
		.s_arburst({v_arburst, b_arburst}),
		.s_arvalid({v_arvalid, b_arvalid}),
		.s_arready({v_arready, b_arready}),
		.s_rid({v_rid, b_rid}),
		.s_rdata({v_rdata, b_rdata}),
		.s_rresp({v_rresp, b_rresp}),
		.s_rlast({v_rlast, b_rlast}),
		.s_rvalid({v_rvalid, b_rvalid}),
		.s_rready({v_rready, b_rready}),
		.m_awid(d_awid),
		.m_awaddr(d_awaddr),
		.m_awlen(d_awlen),
		.m_awsize(d_awsize),
		.m_awburst(d_awburst),
		.m_awvalid(d_awvalid),
		.m_awready(d_awready),
		.m_wdata(d_wdata),
		.m_wstrb(d_wstrb),
		.m_wlast(d_wlast),
		.m_wvalid(d_wvalid),
		.m_wready(d_wready),
		.m_bid(d_bid),
		.m_bresp(d_bresp),
		.m_bvalid(d_bvalid),
		.m_bready(d_bready),
		.m_arid(d_arid),
		.m_araddr(d_araddr),
		.m_arlen(d_arlen),
		.m_arsize(d_arsize),
		.m_arburst(d_arburst),
		.m_arvalid(d_arvalid),
		.m_arready(d_arready),
		.m_rid(d_rid),
		.m_rdata(d_rdata),
		.m_rresp(d_rresp),
		.m_rlast(d_rlast),
		.m_rvalid(d_rvalid),
		.m_rready(d_rready)
	);
	wire [3:0] h_awid;
	wire [3:0] h_bid;
	wire [3:0] h_arid;
	wire [3:0] h_rid;
	wire [31:0] h_awaddr;
	wire [31:0] h_araddr;
	wire [7:0] h_awlen;
	wire [7:0] h_arlen;
	wire [2:0] h_awsize;
	wire [2:0] h_arsize;
	wire [1:0] h_awburst;
	wire [1:0] h_arburst;
	wire [1:0] h_bresp;
	wire [1:0] h_rresp;
	wire h_awvalid;
	wire h_awready;
	wire h_wlast;
	wire h_wvalid;
	wire h_wready;
	wire h_bvalid;
	wire h_bready;
	wire h_arvalid;
	wire h_arready;
	wire h_rlast;
	wire h_rvalid;
	wire h_rready;
	wire [127:0] h_wdata;
	wire [127:0] h_rdata;
	wire [15:0] h_wstrb;
	wire [3:0] e_awid;
	wire [3:0] e_bid;
	wire [3:0] e_arid;
	wire [3:0] e_rid;
	wire [31:0] e_awaddr;
	wire [31:0] e_araddr;
	wire [7:0] e_awlen;
	wire [7:0] e_arlen;
	wire [2:0] e_awsize;
	wire [2:0] e_arsize;
	wire [1:0] e_awburst;
	wire [1:0] e_arburst;
	wire [1:0] e_bresp;
	wire [1:0] e_rresp;
	wire e_awvalid;
	wire e_awready;
	wire e_wlast;
	wire e_wvalid;
	wire e_wready;
	wire e_bvalid;
	wire e_bready;
	wire e_arvalid;
	wire e_arready;
	wire e_rlast;
	wire e_rvalid;
	wire e_rready;
	wire [127:0] e_wdata;
	wire [127:0] e_rdata;
	wire [15:0] e_wstrb;
	soc_axi_2m_arbiter video_share(
		.clk(mem_clk),
		.rst(region_reset_video_share),
		.busy(),
		.s_awid({4'd0, d_awid}),
		.s_awaddr({32'd0, d_awaddr}),
		.s_awlen({8'd0, d_awlen}),
		.s_awsize({3'd4, d_awsize}),
		.s_awburst({2'd1, d_awburst}),
		.s_awvalid({1'b0, d_awvalid}),
		.s_awready({h_awready, d_awready}),
		.s_wdata({128'd0, d_wdata}),
		.s_wstrb({16'd0, d_wstrb}),
		.s_wlast({1'b0, d_wlast}),
		.s_wvalid({1'b0, d_wvalid}),
		.s_wready({h_wready, d_wready}),
		.s_bid({h_bid, d_bid}),
		.s_bresp({h_bresp, d_bresp}),
		.s_bvalid({h_bvalid, d_bvalid}),
		.s_bready({1'b1, d_bready}),
		.s_arid({h_arid, d_arid}),
		.s_araddr({h_araddr, d_araddr}),
		.s_arlen({h_arlen, d_arlen}),
		.s_arsize({h_arsize, d_arsize}),
		.s_arburst({h_arburst, d_arburst}),
		.s_arvalid({h_arvalid, d_arvalid}),
		.s_arready({h_arready, d_arready}),
		.s_rid({h_rid, d_rid}),
		.s_rdata({h_rdata, d_rdata}),
		.s_rresp({h_rresp, d_rresp}),
		.s_rlast({h_rlast, d_rlast}),
		.s_rvalid({h_rvalid, d_rvalid}),
		.s_rready({h_rready, d_rready}),
		.m_awid(e_awid),
		.m_awaddr(e_awaddr),
		.m_awlen(e_awlen),
		.m_awsize(e_awsize),
		.m_awburst(e_awburst),
		.m_awvalid(e_awvalid),
		.m_awready(e_awready),
		.m_wdata(e_wdata),
		.m_wstrb(e_wstrb),
		.m_wlast(e_wlast),
		.m_wvalid(e_wvalid),
		.m_wready(e_wready),
		.m_bid(e_bid),
		.m_bresp(e_bresp),
		.m_bvalid(e_bvalid),
		.m_bready(e_bready),
		.m_arid(e_arid),
		.m_araddr(e_araddr),
		.m_arlen(e_arlen),
		.m_arsize(e_arsize),
		.m_arburst(e_arburst),
		.m_arvalid(e_arvalid),
		.m_arready(e_arready),
		.m_rid(e_rid),
		.m_rdata(e_rdata),
		.m_rresp(e_rresp),
		.m_rlast(e_rlast),
		.m_rvalid(e_rvalid),
		.m_rready(e_rready)
	);
	wire [3:0] im_awid;
	wire [31:0] im_awaddr;
	wire [7:0] im_awlen;
	wire [2:0] im_awsize;
	wire [1:0] im_awburst;
	wire im_awvalid;
	wire im_awready;
	wire [127:0] im_wdata;
	wire [15:0] im_wstrb;
	wire im_wlast;
	wire im_wvalid;
	wire im_wready;
	wire [3:0] im_bid;
	wire [1:0] im_bresp;
	wire im_bvalid;
	wire im_bready;
	wire [3:0] im_arid;
	wire [31:0] im_araddr;
	wire [7:0] im_arlen;
	wire [2:0] im_arsize;
	wire [1:0] im_arburst;
	wire im_arvalid;
	wire im_arready;
	wire [3:0] im_rid;
	wire [127:0] im_rdata;
	wire [1:0] im_rresp;
	wire im_rlast;
	wire im_rvalid;
	wire im_rready;
	soc_display_commit_mmio #(
		.FRAME_BYTES(462400),
		.BOX_WIDTH(680),
		.BOX_HEIGHT(340),
		.MMIO_PAGE(4'h5),
		.REQUIRE_PRESENT_ACK(1),
		.SCOPED_WRITER(1)
	) display_commit(
		.clk(mem_clk),
		.rst(mem_reset),
		.ddr_ready(ddr_ready),
		.axi_poisoned(adapter_fault || rq_axi_poisoned),
		.cpu_time_gray(cpu_time_gray),
		.req_valid(cam_mem_req_valid && (mmio_request_unit == 3)),
		.req_ready(display_mem_req_ready),
		.req_addr(cam_mem_req_addr),
		.req_write(cam_mem_req_write),
		.req_wdata(cam_mem_req_wdata),
		.req_wstrb(cam_mem_req_wstrb),
		.rsp_valid(display_mem_rsp_valid),
		.rsp_ready(cam_mem_rsp_ready && (mmio_response_owner == 3)),
		.rsp_rdata(display_mem_rsp_rdata),
		.rsp_error(display_mem_rsp_error),
		.awvalid(im_awvalid),
		.awready(im_awready),
		.awaddr(im_awaddr),
		.awid(im_awid),
		.awlen(im_awlen),
		.awsize(im_awsize),
		.awburst(im_awburst),
		.wvalid(im_wvalid),
		.wready(im_wready),
		.wstrb(im_wstrb),
		.wlast(im_wlast),
		.bvalid(im_bvalid),
		.bready(im_bready),
		.bid(im_bid),
		.bresp(im_bresp),
		.publish_valid(publish_valid),
		.publish_ready(publish_ready),
		.publish_fb(publish_fb),
		.publish_frame(publish_frame),
		.publish_run(publish_run),
		.publish_xy1(publish_xy1),
		.publish_xy2(publish_xy2),
		.publish_score(publish_score),
		.publish_class(publish_class),
		.publish_count(publish_count),
		.publish_sequence(publish_sequence),
		.display_valid(displayed_valid),
		.display_fb(displayed_fb),
		.pending_display_valid(pending_display_valid),
		.pending_display_fb(pending_display_fb)
	);
	soc_hdmi_ddr_scanout #(
		.SINGLE_VIEW(1),
		.W(680),
		.H(340),
		.X_START(20),
		.Y_START(70),
		.TX_EXTRA_CYCLES(0)
	) display_scanout(
		.ui_clk(mem_clk),
		.ui_rst(mem_reset),
		.pix_clk(hdmi_pixel_clk),
		.pix_rst(hdmi_pixel_reset),
		.cpu_time_gray(cpu_time_gray),
		.test_pattern(video_mode),
		.publish_valid(publish_valid),
		.publish_ready(publish_ready),
		.publish_fb(publish_fb),
		.publish_frame(publish_frame),
		.publish_run(publish_run),
		.publish_xy1(publish_xy1),
		.publish_xy2(publish_xy2),
		.publish_score(publish_score),
		.publish_class(publish_class),
		.publish_count(publish_count),
		.publish_sequence(publish_sequence),
		.pending_valid(pending_display_valid),
		.pending_fb(pending_display_fb),
		.presented_valid(displayed_valid),
		.presented_fb(displayed_fb),
		.presented_frame(displayed_frame),
		.presented_run(displayed_run),
		.m_arid(h_arid),
		.m_araddr(h_araddr),
		.m_arlen(h_arlen),
		.m_arsize(h_arsize),
		.m_arburst(h_arburst),
		.m_arvalid(h_arvalid),
		.m_arready(h_arready),
		.m_rid(h_rid),
		.m_rdata(h_rdata),
		.m_rresp(h_rresp),
		.m_rlast(h_rlast),
		.m_rvalid(h_rvalid),
		.m_rready(h_rready),
		.video_rgb(video_rgb),
		.video_de(video_de),
		.video_hs(video_hs),
		.video_vs(video_vs),
		.event_tc(event_tc),
		.event_th(event_th),
		.event_te(event_te),
		.te_good(te_good),
		.tc_ticks(tc_ticks),
		.th_ticks(th_ticks),
		.te_ticks(te_ticks),
		.tc_pixel_ticks(),
		.th_pixel_ticks(),
		.te_pixel_ticks(),
		.tc_frame(tc_frame),
		.tc_run(tc_run),
		.th_frame(th_frame),
		.th_run(th_run),
		.te_frame(te_frame),
		.te_run(te_run),
		.stat_underflow(stat_underflow),
		.stat_mismatch(stat_mismatch),
		.stat_presented(stat_presented),
		.stat_max_ddr_wait(stat_max_ddr_wait),
		.stat_fifo_high(stat_fifo_high),
		.stat_fifo_low(stat_fifo_low),
		.video_fault(video_fault)
	);
	soc_video_event_mmio video_registers(
		.clk(mem_clk),
		.rst(mem_reset),
		.req_valid(cam_mem_req_valid && (mmio_request_unit == 4)),
		.req_ready(video_mem_req_ready),
		.req_addr(cam_mem_req_addr),
		.req_write(cam_mem_req_write),
		.req_wdata(cam_mem_req_wdata),
		.req_wstrb(cam_mem_req_wstrb),
		.rsp_valid(video_mem_rsp_valid),
		.rsp_ready(cam_mem_rsp_ready && (mmio_response_owner == 4)),
		.rsp_rdata(video_mem_rsp_rdata),
		.rsp_error(video_mem_rsp_error),
		.test_pattern(video_mode),
		.event_tc(event_tc),
		.event_th(event_th),
		.event_te(event_te),
		.te_good(te_good),
		.tc_ticks(tc_ticks),
		.th_ticks(th_ticks),
		.te_ticks(te_ticks),
		.tc_frame(tc_frame),
		.tc_run(tc_run),
		.th_frame(th_frame),
		.th_run(th_run),
		.te_frame(te_frame),
		.te_run(te_run),
		.stat_underflow(stat_underflow),
		.stat_mismatch(stat_mismatch),
		.stat_presented(stat_presented),
		.stat_max_ddr_wait(stat_max_ddr_wait),
		.stat_fifo_high(stat_fifo_high),
		.stat_fifo_low(stat_fifo_low),
		.video_fault(video_fault)
	);
	soc_mini_hdmi_tx u_hdmi_tx(
		.pixel_clk(hdmi_pixel_clk),
		.serial_clk(hdmi_serial_clk),
		.reset_n(!hdmi_pixel_reset),
		.serial_reset_n(!hdmi_serial_reset),
		.rgb888(video_rgb),
		.de(video_de),
		.hsync(video_hs),
		.vsync(video_vs),
		.tmds_data_p(tmds_data_p),
		.tmds_data_n(tmds_data_n),
		.tmds_clk_p(tmds_clk_p),
		.tmds_clk_n(tmds_clk_n)
	);
	soc_image_accel image_accel(
		.clk(mem_clk),
		.rst(mem_reset),
		.ddr_ready(ddr_ready),
		.external_poisoned(adapter_fault || rq_axi_poisoned),
		.req_valid(cam_mem_req_valid && (mmio_request_unit == 7)),
		.req_ready(image_mem_req_ready),
		.req_addr(cam_mem_req_addr),
		.req_write(cam_mem_req_write),
		.req_wdata(cam_mem_req_wdata),
		.req_wstrb(cam_mem_req_wstrb),
		.rsp_valid(image_mem_rsp_valid),
		.rsp_ready(cam_mem_rsp_ready && (mmio_response_owner == 7)),
		.rsp_rdata(image_mem_rsp_rdata),
		.rsp_error(image_mem_rsp_error),
		.m_awid(im_awid),
		.m_awaddr(im_awaddr),
		.m_awlen(im_awlen),
		.m_awsize(im_awsize),
		.m_awburst(im_awburst),
		.m_awvalid(im_awvalid),
		.m_awready(im_awready),
		.m_wdata(im_wdata),
		.m_wstrb(im_wstrb),
		.m_wlast(im_wlast),
		.m_wvalid(im_wvalid),
		.m_wready(im_wready),
		.m_bid(im_bid),
		.m_bresp(im_bresp),
		.m_bvalid(im_bvalid),
		.m_bready(im_bready),
		.m_arid(im_arid),
		.m_araddr(im_araddr),
		.m_arlen(im_arlen),
		.m_arsize(im_arsize),
		.m_arburst(im_arburst),
		.m_arvalid(im_arvalid),
		.m_arready(im_arready),
		.m_rid(im_rid),
		.m_rdata(im_rdata),
		.m_rresp(im_rresp),
		.m_rlast(im_rlast),
		.m_rvalid(im_rvalid),
		.m_rready(im_rready)
	);
	soc_axi_2m_arbiter image_v2_share(
		.clk(mem_clk),
		.rst(mem_reset),
		.busy(),
		.s_awid({im_awid, vr_awid}),
		.s_awaddr({im_awaddr, vr_awaddr}),
		.s_awlen({im_awlen, vr_awlen}),
		.s_awsize({im_awsize, vr_awsize}),
		.s_awburst({im_awburst, vr_awburst}),
		.s_awvalid({im_awvalid, vr_awvalid}),
		.s_awready({im_awready, vr_awready}),
		.s_wdata({im_wdata, vr_wdata}),
		.s_wstrb({im_wstrb, vr_wstrb}),
		.s_wlast({im_wlast, vr_wlast}),
		.s_wvalid({im_wvalid, vr_wvalid}),
		.s_wready({im_wready, vr_wready}),
		.s_bid({im_bid, vr_bid}),
		.s_bresp({im_bresp, vr_bresp}),
		.s_bvalid({im_bvalid, vr_bvalid}),
		.s_bready({im_bready, vr_bready}),
		.s_arid({im_arid, vr_arid}),
		.s_araddr({im_araddr, vr_araddr}),
		.s_arlen({im_arlen, vr_arlen}),
		.s_arsize({im_arsize, vr_arsize}),
		.s_arburst({im_arburst, vr_arburst}),
		.s_arvalid({im_arvalid, vr_arvalid}),
		.s_arready({im_arready, vr_arready}),
		.s_rid({im_rid, vr_rid}),
		.s_rdata({im_rdata, vr_rdata}),
		.s_rresp({im_rresp, vr_rresp}),
		.s_rlast({im_rlast, vr_rlast}),
		.s_rvalid({im_rvalid, vr_rvalid}),
		.s_rready({im_rready, vr_rready}),
		.m_awid(v_awid),
		.m_awaddr(v_awaddr),
		.m_awlen(v_awlen),
		.m_awsize(v_awsize),
		.m_awburst(v_awburst),
		.m_awvalid(v_awvalid),
		.m_awready(v_awready),
		.m_wdata(v_wdata),
		.m_wstrb(v_wstrb),
		.m_wlast(v_wlast),
		.m_wvalid(v_wvalid),
		.m_wready(v_wready),
		.m_bid(v_bid),
		.m_bresp(v_bresp),
		.m_bvalid(v_bvalid),
		.m_bready(v_bready),
		.m_arid(v_arid),
		.m_araddr(v_araddr),
		.m_arlen(v_arlen),
		.m_arsize(v_arsize),
		.m_arburst(v_arburst),
		.m_arvalid(v_arvalid),
		.m_arready(v_arready),
		.m_rid(v_rid),
		.m_rdata(v_rdata),
		.m_rresp(v_rresp),
		.m_rlast(v_rlast),
		.m_rvalid(v_rvalid),
		.m_rready(v_rready)
	);
	soc_hmic_axi_adapter bridge(
		.clk(mem_clk),
		.rst(mem_reset),
		.ddr_ready(ddr_ready),
		.protocol_fault(adapter_fault),
		.s_awid(e_awid),
		.s_awaddr(e_awaddr),
		.s_awlen(e_awlen),
		.s_awsize(e_awsize),
		.s_awburst(e_awburst),
		.s_awvalid(e_awvalid),
		.s_awready(e_awready),
		.s_wdata(e_wdata),
		.s_wstrb(e_wstrb),
		.s_wlast(e_wlast),
		.s_wvalid(e_wvalid),
		.s_wready(e_wready),
		.s_bid(e_bid),
		.s_bresp(e_bresp),
		.s_bvalid(e_bvalid),
		.s_bready(e_bready),
		.s_arid(e_arid),
		.s_araddr(e_araddr),
		.s_arlen(e_arlen),
		.s_arsize(e_arsize),
		.s_arburst(e_arburst),
		.s_arvalid(e_arvalid),
		.s_arready(e_arready),
		.s_rid(e_rid),
		.s_rdata(e_rdata),
		.s_rresp(e_rresp),
		.s_rlast(e_rlast),
		.s_rvalid(e_rvalid),
		.s_rready(e_rready),
		.m_awid(m_awid),
		.m_awaddr(m_awaddr),
		.m_awlen(m_awlen),
		.m_awsize(m_awsize),
		.m_awburst(m_awburst),
		.m_awvalid(m_awvalid),
		.m_awready(m_awready),
		.m_wdata(m_wdata),
		.m_wstrb(m_wstrb),
		.m_wlast(m_wlast),
		.m_wvalid(m_wvalid),
		.m_wready(m_wready),
		.m_bid(m_bid),
		.m_bresp(m_bresp),
		.m_bvalid(m_bvalid),
		.m_bready(m_bready),
		.m_arid(m_arid),
		.m_araddr(m_araddr),
		.m_arlen(m_arlen),
		.m_arsize(m_arsize),
		.m_arburst(m_arburst),
		.m_arvalid(m_arvalid),
		.m_arready(m_arready),
		.m_rid(m_rid),
		.m_rdata(m_rdata),
		.m_rresp(m_rresp),
		.m_rlast(m_rlast),
		.m_rvalid(m_rvalid),
		.m_rready(m_rready)
	);
	soc_ddr800 I_ips_ddr_top(
		.ref_clk(ref_clk),
		.resetn(!ddr_ref_reset),
		.core_clk(mem_clk),
		.pll_lock(ddr_pll_lock),
		.phy_pll_lock(ddr_phy_lock),
		.ddr_init_done(ddr_init_done),
		.axi_awid(m_awid),
		.axi_awaddr(m_awaddr),
		.axi_awlen(m_awlen),
		.axi_awsize(m_awsize),
		.axi_awburst(m_awburst),
		.axi_awvalid(m_awvalid),
		.axi_awready(m_awready),
		.axi_wdata(m_wdata),
		.axi_wstrb(m_wstrb),
		.axi_wlast(m_wlast),
		.axi_wvalid(m_wvalid),
		.axi_wready(m_wready),
		.axi_bid(m_bid),
		.axi_bresp(m_bresp),
		.axi_bvalid(m_bvalid),
		.axi_bready(m_bready),
		.axi_arid(m_arid),
		.axi_araddr(m_araddr),
		.axi_arlen(m_arlen),
		.axi_arsize(m_arsize),
		.axi_arburst(m_arburst),
		.axi_arvalid(m_arvalid),
		.axi_arready(m_arready),
		.axi_rid(m_rid),
		.axi_rdata(m_rdata),
		.axi_rresp(m_rresp),
		.axi_rlast(m_rlast),
		.axi_rvalid(m_rvalid),
		.axi_rready(m_rready),
		.mem_cs_n(mem_cs_n),
		.mem_rst_n(mem_rst_n),
		.mem_ck(mem_ck),
		.mem_ck_n(mem_ck_n),
		.mem_cke(mem_cke),
		.mem_ras_n(mem_ras_n),
		.mem_cas_n(mem_cas_n),
		.mem_we_n(mem_we_n),
		.mem_odt(mem_odt),
		.mem_a(mem_a),
		.mem_ba(mem_ba),
		.mem_dqs(mem_dqs),
		.mem_dqs_n(mem_dqs_n),
		.mem_dq(mem_dq),
		.mem_dm(mem_dm),
		.apb_clk(1'b0),
		.apb_rst_n(1'b0),
		.apb_sel(1'b0),
		.apb_enable(1'b0),
		.apb_addr(8'b00000000),
		.apb_write(1'b0),
		.apb_wdata(16'b0000000000000000),
		.dbg_gate_start(1'b0),
		.dbg_cpd_start(1'b0),
		.dbg_ddrphy_rst_n(1'b1),
		.dbg_gpll_scan_rst(1'b0),
		.samp_position_dyn_adj(1'b0),
		.init_samp_position_even(32'b00000000000000000000000000000000),
		.wrcal_position_dyn_adj(1'b0),
		.init_wrcal_position(32'b00000000000000000000000000000000),
		.force_read_clk_ctrl(1'b0),
		.init_slip_step(16'b0000000000000000),
		.init_read_clk_ctrl(12'b000000000000),
		.debug_cpd_offset_adj(1'b0),
		.debug_cpd_offset_dir(1'b0),
		.debug_cpd_offset(10'b0000000000),
		.ck_dly_en(1'b1),
		.init_ck_dly_step(8'b00000000),
		.dbg_ddrphy_init_fail(ddr_cal_fail)
	);
endmodule
module soc_camera_input_hold (
	data_in,
	data_out
);
	parameter integer WIDTH = 8;
	parameter HOLD_SET = "1500ps";
	input wire [WIDTH - 1:0] data_in;
	output wire [WIDTH - 1:0] data_out;
	genvar _gv_bit_index_1;
	generate
		for (_gv_bit_index_1 = 0; _gv_bit_index_1 < WIDTH; _gv_bit_index_1 = _gv_bit_index_1 + 1) begin : bit_hold
			localparam bit_index = _gv_bit_index_1;
			GTP_ZEROHOLDDELAY #(.ZHOLD_SET(HOLD_SET)) hold_cell(
				.DI(data_in[bit_index]),
				.DO(data_out[bit_index])
			);
		end
	endgenerate
endmodule
module soc_preprocess320_core (
	clk,
	rst,
	start,
	src_base,
	dst_base,
	busy,
	done,
	lut_we,
	lut_idx,
	lut_dat,
	rd_valid,
	rd_ready,
	rd_addr,
	rsp_valid,
	rsp_ready,
	rsp_data,
	wr_valid,
	wr_ready,
	wr_addr,
	wr_data,
	stat_rd_beats,
	stat_wr_beats
);
	reg _sv2v_0;
	parameter [0:0] WIDE_OUTPUT_PACK = 1'b1;
	parameter signed [31:0] SRC_STRIDE_B = 2560;
	parameter signed [31:0] OUT_STRIDE_B = 960;
	parameter signed [31:0] OUT_H = 320;
	parameter signed [31:0] TOP = 70;
	parameter signed [31:0] ACT_H = 180;
	parameter signed [31:0] BEATS_PER_SRC_ROW = SRC_STRIDE_B / 16;
	input wire clk;
	input wire rst;
	input wire start;
	input wire [29:0] src_base;
	input wire [29:0] dst_base;
	output reg busy;
	output reg done;
	input wire lut_we;
	input wire [7:0] lut_idx;
	input wire [7:0] lut_dat;
	output wire rd_valid;
	input wire rd_ready;
	output wire [29:0] rd_addr;
	input wire rsp_valid;
	output wire rsp_ready;
	input wire [127:0] rsp_data;
	output reg wr_valid;
	input wire wr_ready;
	output reg [29:0] wr_addr;
	output reg [127:0] wr_data;
	output reg [31:0] stat_rd_beats;
	output reg [31:0] stat_wr_beats;
	reg [3:0] state;
	reg [7:0] lut_q [0:255];
	reg [59:0] psum_q [0:BEATS_PER_SRC_ROW - 1];
	reg [29:0] source_q;
	reg [29:0] dest_q;
	reg [29:0] rowa_q;
	reg [29:0] rowb_q;
	reg [29:0] outrow_q;
	reg [8:0] y_q;
	reg [8:0] k_q;
	reg [10:0] row_bytes;
	reg [127:0] pack_q;
	reg [127:0] pack_next;
	reg [3:0] pack_count;
	reg [47:0] stage_q;
	reg [2:0] stage_count;
	localparam [0:0] FAST_PACK = WIDE_OUTPUT_PACK && ((OUT_STRIDE_B % 16) == 0);
	wire can_push = !wr_valid || wr_ready;
	wire [175:0] wide_pack = {48'd0, pack_q} | ({128'd0, stage_q} << (8 * pack_count));
	wire [4:0] wide_count = {1'b0, pack_count} + {2'b00, stage_count};
	function automatic signed [10:0] sv2v_cast_11_signed;
		input reg signed [10:0] inp;
		sv2v_cast_11_signed = inp;
	endfunction
	wire push = ((state == 4'd2) && (row_bytes < sv2v_cast_11_signed(OUT_STRIDE_B))) || ((state == 4'd7) && (stage_count != 0));
	wire [7:0] push_byte = (state == 4'd2 ? lut_q[114] : stage_q[7:0]);
	function automatic [7:0] red8;
		input reg [15:0] p;
		red8 = {p[15:11], p[15:13]};
	endfunction
	function automatic [7:0] grn8;
		input reg [15:0] p;
		grn8 = {p[10:5], p[10:9]};
	endfunction
	function automatic [7:0] blu8;
		input reg [15:0] p;
		blu8 = {p[4:0], p[4:2]};
	endfunction
	function automatic [9:0] sv2v_cast_10;
		input reg [9:0] inp;
		sv2v_cast_10 = inp;
	endfunction
	function automatic [29:0] pair_sum;
		input reg [127:0] b;
		input reg signed [31:0] lo;
		reg [15:0] a;
		reg [15:0] c;
		reg [9:0] r;
		reg [9:0] g;
		reg [9:0] bl;
		begin
			a = b[lo * 16+:16];
			c = b[(lo + 1) * 16+:16];
			r = sv2v_cast_10(red8(a)) + sv2v_cast_10(red8(c));
			g = sv2v_cast_10(grn8(a)) + sv2v_cast_10(grn8(c));
			bl = sv2v_cast_10(blu8(a)) + sv2v_cast_10(blu8(c));
			pair_sum = {r, g, bl};
		end
	endfunction
	wire [59:0] upper = psum_q[k_q[7:0]];
	wire [29:0] lo = pair_sum(rsp_data, 1);
	wire [29:0] hi = pair_sum(rsp_data, 5);
	function automatic [10:0] sv2v_cast_11;
		input reg [10:0] inp;
		sv2v_cast_11 = inp;
	endfunction
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	wire [7:0] r0 = sv2v_cast_8(((sv2v_cast_11(upper[29:20]) + sv2v_cast_11(lo[29:20])) + 11'd2) >> 2);
	wire [7:0] g0 = sv2v_cast_8(((sv2v_cast_11(upper[19:10]) + sv2v_cast_11(lo[19:10])) + 11'd2) >> 2);
	wire [7:0] b0 = sv2v_cast_8(((sv2v_cast_11(upper[9:0]) + sv2v_cast_11(lo[9:0])) + 11'd2) >> 2);
	wire [7:0] r1 = sv2v_cast_8(((sv2v_cast_11(upper[59:50]) + sv2v_cast_11(hi[29:20])) + 11'd2) >> 2);
	wire [7:0] g1 = sv2v_cast_8(((sv2v_cast_11(upper[49:40]) + sv2v_cast_11(hi[19:10])) + 11'd2) >> 2);
	wire [7:0] b1 = sv2v_cast_8(((sv2v_cast_11(upper[39:30]) + sv2v_cast_11(hi[9:0])) + 11'd2) >> 2);
	always @(*) begin
		if (_sv2v_0)
			;
		pack_next = pack_q;
		pack_next[pack_count * 8+:8] = push_byte;
	end
	assign rd_valid = ((state == 4'd3) || (state == 4'd5)) && !rst;
	assign rd_addr = (state == 4'd3 ? rowa_q : rowb_q) + {17'd0, k_q, 4'd0};
	assign rsp_ready = ((state == 4'd4) || (state == 4'd6)) && !rst;
	function automatic [29:0] sv2v_cast_30;
		input reg [29:0] inp;
		sv2v_cast_30 = inp;
	endfunction
	function automatic signed [8:0] sv2v_cast_9_signed;
		input reg signed [8:0] inp;
		sv2v_cast_9_signed = inp;
	endfunction
	function automatic signed [29:0] sv2v_cast_30_signed;
		input reg signed [29:0] inp;
		sv2v_cast_30_signed = inp;
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @(posedge clk) begin
		if (lut_we)
			lut_q[lut_idx] <= lut_dat;
		done <= 0;
		if (rst) begin
			state <= 4'd0;
			busy <= 0;
			done <= 0;
			source_q <= 0;
			dest_q <= 0;
			rowa_q <= 0;
			rowb_q <= 0;
			outrow_q <= 0;
			y_q <= 0;
			k_q <= 0;
			row_bytes <= 0;
			pack_q <= 0;
			pack_count <= 0;
			stage_q <= 0;
			stage_count <= 0;
			wr_valid <= 0;
			wr_addr <= 0;
			wr_data <= 0;
			stat_rd_beats <= 0;
			stat_wr_beats <= 0;
		end
		else begin
			if (wr_valid && wr_ready) begin
				wr_valid <= 0;
				stat_wr_beats <= stat_wr_beats + 1'b1;
			end
			if ((!FAST_PACK && push) && can_push) begin
				pack_q <= pack_next;
				pack_count <= pack_count + 1'b1;
				row_bytes <= row_bytes + 1'b1;
				if (pack_count == 15) begin
					wr_valid <= 1;
					wr_data <= pack_next;
					wr_addr <= (outrow_q + sv2v_cast_30(row_bytes)) - 30'd15;
				end
				if (state == 4'd7) begin
					stage_q <= stage_q >> 8;
					stage_count <= stage_count - 1'b1;
				end
			end
			case (state)
				4'd0:
					if (start) begin
						source_q <= src_base;
						dest_q <= dst_base;
						outrow_q <= dst_base;
						y_q <= 0;
						k_q <= 0;
						row_bytes <= 0;
						pack_count <= 0;
						stat_rd_beats <= 0;
						stat_wr_beats <= 0;
						busy <= 1;
						state <= 4'd1;
					end
				4'd1: begin
					row_bytes <= 0;
					k_q <= 0;
					if (FAST_PACK) begin
						pack_q <= 0;
						pack_count <= 0;
					end
					if (y_q >= sv2v_cast_9_signed(OUT_H))
						state <= 4'd9;
					else if ((y_q < sv2v_cast_9_signed(TOP)) || (y_q >= sv2v_cast_9_signed(TOP + ACT_H)))
						state <= 4'd2;
					else begin
						rowa_q <= source_q + sv2v_cast_30_signed(((4 * (sv2v_cast_32_signed(y_q) - TOP)) + 1) * SRC_STRIDE_B);
						rowb_q <= source_q + sv2v_cast_30_signed(((4 * (sv2v_cast_32_signed(y_q) - TOP)) + 2) * SRC_STRIDE_B);
						state <= 4'd3;
					end
				end
				4'd2:
					if (row_bytes == sv2v_cast_11_signed(OUT_STRIDE_B))
						state <= 4'd8;
					else if (FAST_PACK && can_push) begin
						wr_valid <= 1;
						wr_data <= {16 {lut_q[114]}};
						wr_addr <= outrow_q + sv2v_cast_30(row_bytes);
						row_bytes <= row_bytes + 11'd16;
					end
				4'd3:
					if (rd_ready)
						state <= 4'd4;
				4'd4:
					if (rsp_valid) begin
						psum_q[k_q[7:0]] <= {pair_sum(rsp_data, 5), pair_sum(rsp_data, 1)};
						stat_rd_beats <= stat_rd_beats + 1'b1;
						if (k_q == sv2v_cast_9_signed(BEATS_PER_SRC_ROW - 1)) begin
							k_q <= 0;
							state <= 4'd5;
						end
						else begin
							k_q <= k_q + 1'b1;
							state <= 4'd3;
						end
					end
				4'd5:
					if (rd_ready)
						state <= 4'd6;
				4'd6:
					if (rsp_valid) begin
						stat_rd_beats <= stat_rd_beats + 1'b1;
						stage_q <= {lut_q[b1], lut_q[g1], lut_q[r1], lut_q[b0], lut_q[g0], lut_q[r0]};
						stage_count <= 6;
						state <= 4'd7;
					end
				4'd7:
					if ((FAST_PACK && (stage_count != 0)) && can_push) begin
						row_bytes <= row_bytes + sv2v_cast_11(stage_count);
						stage_count <= 0;
						if (wide_count >= 5'd16) begin
							wr_valid <= 1;
							wr_data <= wide_pack[127:0];
							wr_addr <= (outrow_q + sv2v_cast_30(row_bytes)) - sv2v_cast_30(pack_count);
							pack_q <= {80'd0, wide_pack[175:128]};
							pack_count <= sv2v_cast_4(wide_count - 5'd16);
						end
						else begin
							pack_q <= wide_pack[127:0];
							pack_count <= wide_count[3:0];
						end
						if (k_q == sv2v_cast_9_signed(BEATS_PER_SRC_ROW - 1))
							state <= 4'd8;
						else begin
							k_q <= k_q + 1'b1;
							state <= 4'd5;
						end
					end
					else if (stage_count == 0) begin
						if (k_q == sv2v_cast_9_signed(BEATS_PER_SRC_ROW - 1))
							state <= 4'd8;
						else begin
							k_q <= k_q + 1'b1;
							state <= 4'd5;
						end
					end
				4'd8:
					if (!wr_valid) begin
						y_q <= y_q + 1'b1;
						outrow_q <= outrow_q + sv2v_cast_30_signed(OUT_STRIDE_B);
						state <= 4'd1;
					end
				4'd9:
					if (!wr_valid) begin
						busy <= 0;
						done <= 1;
						state <= 4'd10;
					end
				4'd10:
					if (!start)
						state <= 4'd0;
				default: state <= 4'd0;
			endcase
		end
	end
	initial _sv2v_0 = 0;
endmodule
module soc_display_resize_core (
	clk,
	rst,
	start,
	src_base,
	dst_base,
	busy,
	done,
	rd_valid,
	rd_ready,
	rd_addr,
	rsp_valid,
	rsp_ready,
	rsp_data,
	wr_valid,
	wr_ready,
	wr_addr,
	wr_data,
	stat_rd_beats,
	stat_wr_beats
);
	parameter [0:0] SKIP_UNSAMPLED = 1'b1;
	parameter [0:0] REFILL_SAME_CYCLE = 1'b1;
	input wire clk;
	input wire rst;
	input wire start;
	input wire [29:0] src_base;
	input wire [29:0] dst_base;
	output reg busy;
	output reg done;
	output wire rd_valid;
	input wire rd_ready;
	output wire [29:0] rd_addr;
	input wire rsp_valid;
	output wire rsp_ready;
	input wire [127:0] rsp_data;
	output reg wr_valid;
	input wire wr_ready;
	output reg [29:0] wr_addr;
	output reg [127:0] wr_data;
	output reg [31:0] stat_rd_beats;
	output reg [31:0] stat_wr_beats;
	localparam [31:0] READ_BEATS = 32'd54400;
	localparam [31:0] WRITE_BEATS = 32'd28900;
	reg [29:0] row_base_q;
	reg [29:0] write_addr_q;
	reg [7:0] req_x_q;
	reg [4:0] y_rem_q;
	reg [4:0] x_rem_q;
	reg [10:0] source_x_q;
	reg [10:0] target_x_q;
	reg [31:0] issued_q;
	reg [2:0] inflight_q;
	reg [2:0] beat_pixel_q;
	reg [2:0] packed_count_q;
	reg beat_valid_q;
	reg [127:0] beat_q;
	reg [127:0] packed_q;
	wire read_fire = rd_valid && rd_ready;
	wire response_fire = rsp_valid && rsp_ready;
	wire write_fire = wr_valid && wr_ready;
	wire selected = (SKIP_UNSAMPLED ? source_x_q[10:3] == target_x_q[10:3] : source_x_q == target_x_q);
	wire [10:0] target_next = target_x_q + (x_rem_q >= 2 ? 11'd2 : 11'd1);
	wire [2:0] sample_lane = (SKIP_UNSAMPLED ? target_x_q[2:0] : beat_pixel_q);
	wire beat_last = target_next[10:3] != source_x_q[10:3];
	wire process_pixel = beat_valid_q && (((!selected || (packed_count_q != 7)) || !wr_valid) || wr_ready);
	assign rd_valid = (busy && (issued_q < READ_BEATS)) && (inflight_q < 3'd4);
	assign rd_addr = row_base_q + {18'd0, req_x_q, 4'd0};
	assign rsp_ready = busy && (!beat_valid_q || (((SKIP_UNSAMPLED && REFILL_SAME_CYCLE) && process_pixel) && beat_last));
	always @(posedge clk or posedge rst)
		if (rst) begin
			busy <= 0;
			done <= 0;
			row_base_q <= 0;
			write_addr_q <= 0;
			req_x_q <= 0;
			y_rem_q <= 0;
			x_rem_q <= 0;
			source_x_q <= 0;
			target_x_q <= 0;
			issued_q <= 0;
			inflight_q <= 0;
			beat_pixel_q <= 0;
			packed_count_q <= 0;
			beat_valid_q <= 0;
			beat_q <= 0;
			packed_q <= 0;
			wr_valid <= 0;
			wr_addr <= 0;
			wr_data <= 0;
			stat_rd_beats <= 0;
			stat_wr_beats <= 0;
		end
		else begin
			done <= 0;
			if (!busy && start) begin
				busy <= 1;
				row_base_q <= src_base + 30'd2560;
				write_addr_q <= dst_base;
				req_x_q <= 0;
				y_rem_q <= 1;
				x_rem_q <= 16;
				source_x_q <= 0;
				target_x_q <= 0;
				issued_q <= 0;
				inflight_q <= 0;
				beat_pixel_q <= 0;
				packed_count_q <= 0;
				beat_valid_q <= 0;
				wr_valid <= 0;
				stat_rd_beats <= 0;
				stat_wr_beats <= 0;
			end
			else if (busy) begin
				case ({read_fire, response_fire})
					2'b10: inflight_q <= inflight_q + 1'b1;
					2'b01: inflight_q <= inflight_q - 1'b1;
					default:
						;
				endcase
				if (read_fire) begin
					issued_q <= issued_q + 1'b1;
					if (req_x_q == 159) begin
						req_x_q <= 0;
						if (y_rem_q >= 15) begin
							row_base_q <= row_base_q + 30'd7680;
							y_rem_q <= y_rem_q - 5'd15;
						end
						else begin
							row_base_q <= row_base_q + 30'd5120;
							y_rem_q <= y_rem_q + 5'd2;
						end
					end
					else
						req_x_q <= req_x_q + 1'b1;
				end
				if (write_fire) begin
					wr_valid <= 0;
					stat_wr_beats <= stat_wr_beats + 1'b1;
					if (stat_wr_beats == 28899) begin
						busy <= 0;
						done <= 1;
					end
				end
				if (process_pixel) begin
					if (selected) begin
						if (packed_count_q == 7) begin
							wr_data <= {beat_q[sample_lane * 16+:16], packed_q[111:0]};
							wr_addr <= write_addr_q;
							write_addr_q <= write_addr_q + 30'd16;
							wr_valid <= 1;
							packed_count_q <= 0;
						end
						else begin
							packed_q[packed_count_q * 16+:16] <= beat_q[sample_lane * 16+:16];
							packed_count_q <= packed_count_q + 1'b1;
						end
						if (x_rem_q >= 2) begin
							target_x_q <= target_x_q + 11'd2;
							x_rem_q <= x_rem_q - 5'd2;
						end
						else begin
							target_x_q <= target_x_q + 11'd1;
							x_rem_q <= x_rem_q + 5'd15;
						end
					end
					if (SKIP_UNSAMPLED) begin
						if (beat_last) begin
							beat_valid_q <= 0;
							if (source_x_q == 1272) begin
								source_x_q <= 0;
								target_x_q <= 0;
								x_rem_q <= 16;
							end
							else
								source_x_q <= source_x_q + 11'd8;
						end
					end
					else begin
						if (source_x_q == 1279) begin
							source_x_q <= 0;
							target_x_q <= 0;
							x_rem_q <= 16;
						end
						else
							source_x_q <= source_x_q + 1'b1;
						if (beat_pixel_q == 7) begin
							beat_valid_q <= 0;
							beat_pixel_q <= 0;
						end
						else
							beat_pixel_q <= beat_pixel_q + 1'b1;
					end
				end
				if (response_fire) begin
					beat_q <= rsp_data;
					beat_valid_q <= 1;
					beat_pixel_q <= 0;
					stat_rd_beats <= stat_rd_beats + 1'b1;
				end
			end
		end
endmodule
module soc_image_axi_adapter (
	clk,
	rst,
	frame_start,
	frame_finish,
	rd_valid,
	rd_ready,
	rd_addr,
	rsp_valid,
	rsp_ready,
	rsp_data,
	wr_valid,
	wr_ready,
	wr_addr,
	wr_data,
	idle,
	drained,
	error_sticky,
	poisoned,
	m_awid,
	m_awaddr,
	m_awlen,
	m_awsize,
	m_awburst,
	m_awvalid,
	m_awready,
	m_wdata,
	m_wstrb,
	m_wlast,
	m_wvalid,
	m_wready,
	m_bid,
	m_bresp,
	m_bvalid,
	m_bready,
	m_arid,
	m_araddr,
	m_arlen,
	m_arsize,
	m_arburst,
	m_arvalid,
	m_arready,
	m_rid,
	m_rdata,
	m_rresp,
	m_rlast,
	m_rvalid,
	m_rready
);
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [30:0] DDR_BYTES = 31'h08000000;
	parameter [3:0] AXI_ID = 4'he;
	input wire clk;
	input wire rst;
	input wire frame_start;
	input wire frame_finish;
	input wire rd_valid;
	output wire rd_ready;
	input wire [29:0] rd_addr;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [127:0] rsp_data;
	input wire wr_valid;
	output wire wr_ready;
	input wire [29:0] wr_addr;
	input wire [127:0] wr_data;
	output wire idle;
	output wire drained;
	output wire [7:0] error_sticky;
	output wire poisoned;
	output wire [3:0] m_awid;
	output wire [31:0] m_awaddr;
	output wire [7:0] m_awlen;
	output wire [2:0] m_awsize;
	output wire [1:0] m_awburst;
	output wire m_awvalid;
	input wire m_awready;
	output wire [127:0] m_wdata;
	output wire [15:0] m_wstrb;
	output wire m_wlast;
	output wire m_wvalid;
	input wire m_wready;
	input wire [3:0] m_bid;
	input wire [1:0] m_bresp;
	input wire m_bvalid;
	output wire m_bready;
	output wire [3:0] m_arid;
	output wire [31:0] m_araddr;
	output wire [7:0] m_arlen;
	output wire [2:0] m_arsize;
	output wire [1:0] m_arburst;
	output wire m_arvalid;
	input wire m_arready;
	input wire [3:0] m_rid;
	input wire [127:0] m_rdata;
	input wire [1:0] m_rresp;
	input wire m_rlast;
	input wire m_rvalid;
	output wire m_rready;
	reg [2:0] rstate;
	reg [1:0] wstate;
	reg [127:0] cache_data [0:15];
	reg [127:0] write_data [0:15];
	reg cache_valid;
	reg read_poison;
	reg write_poison;
	reg finish_q;
	reg [21:0] cache_tag;
	reg [29:0] read_addr_q;
	reg [29:0] write_base_q;
	reg [3:0] read_index_q;
	reg [3:0] write_index_q;
	reg [4:0] write_count_q;
	reg [7:0] read_error;
	reg [7:0] write_error;
	wire read_address_ok = (rd_addr[3:0] == 0) && ({1'b0, rd_addr} < DDR_BYTES);
	wire write_address_ok = (wr_addr[3:0] == 0) && ({1'b0, wr_addr} < DDR_BYTES);
	wire write_contiguous = wr_addr == (write_base_q + {21'd0, write_count_q, 4'd0});
	wire read_fire = rd_valid && rd_ready;
	wire write_fire = wr_valid && wr_ready;
	assign poisoned = read_poison || write_poison;
	assign error_sticky = read_error | write_error;
	assign rd_ready = ((!rst && !frame_start) && (rstate == 3'd0)) && !rsp_valid;
	assign wr_ready = ((!rst && !frame_start) && (wstate == 2'd0)) && ((poisoned || (write_count_q == 0)) || ((write_count_q < 16) && write_contiguous));
	assign idle = (((!rst && (rstate == 3'd0)) && !rsp_valid) && (wstate == 2'd0)) && (write_count_q == 0);
	assign drained = finish_q && idle;
	assign m_arid = AXI_ID;
	assign m_araddr = DDR_BASE + {2'd0, read_addr_q[29:8], 8'd0};
	assign m_arlen = 8'd15;
	assign m_arsize = 3'd4;
	assign m_arburst = 2'b01;
	assign m_arvalid = !rst && (rstate == 3'd1);
	assign m_rready = !rst && ((rstate == 3'd2) || (rstate == 3'd3));
	assign m_awid = AXI_ID;
	assign m_awaddr = DDR_BASE + {2'd0, write_base_q};
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	assign m_awlen = sv2v_cast_8(write_count_q - 1'b1);
	assign m_awsize = 3'd4;
	assign m_awburst = 2'b01;
	assign m_awvalid = !rst && (wstate == 2'd1);
	assign m_wdata = write_data[write_index_q];
	assign m_wstrb = 16'hffff;
	assign m_wlast = ({1'b0, write_index_q} + 5'd1) == write_count_q;
	assign m_wvalid = !rst && (wstate == 2'd2);
	assign m_bready = !rst && (wstate == 2'd3);
	always @(posedge clk)
		if (rst)
			finish_q <= 0;
		else begin
			if (frame_start)
				finish_q <= 0;
			if (frame_finish)
				finish_q <= 1;
		end
	always @(posedge clk)
		if (rst) begin
			rstate <= 3'd0;
			cache_valid <= 0;
			cache_tag <= 0;
			read_addr_q <= 0;
			read_index_q <= 0;
			rsp_valid <= 0;
			rsp_data <= 0;
			read_error <= 0;
			read_poison <= 0;
		end
		else begin
			if (frame_start) begin
				cache_valid <= 0;
				read_error <= 0;
			end
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			case (rstate)
				3'd0:
					if (read_fire) begin
						read_addr_q <= rd_addr;
						if (!read_address_ok || poisoned) begin
							rsp_valid <= 1;
							rsp_data <= 0;
							if (!read_address_ok)
								read_error[0] <= 1;
						end
						else if (cache_valid && (cache_tag == rd_addr[29:8])) begin
							rsp_valid <= 1;
							rsp_data <= cache_data[rd_addr[7:4]];
						end
						else begin
							cache_valid <= 0;
							read_index_q <= 0;
							rstate <= 3'd1;
						end
					end
				3'd1:
					if (m_arready)
						rstate <= 3'd2;
				3'd2:
					if (m_rvalid) begin
						cache_data[read_index_q] <= m_rdata;
						if (m_rresp != 0)
							read_error[1] <= 1;
						if ((m_rid != AXI_ID) || (m_rlast != (read_index_q == 15))) begin
							read_error[2] <= 1;
							read_poison <= 1;
							cache_valid <= 0;
						end
						if (m_rlast) begin
							if (((read_index_q == 15) && (m_rid == AXI_ID)) && !poisoned) begin
								cache_valid <= 1;
								cache_tag <= read_addr_q[29:8];
								rsp_data <= (read_addr_q[7:4] == 15 ? m_rdata : cache_data[read_addr_q[7:4]]);
							end
							else
								rsp_data <= 0;
							rsp_valid <= 1;
							rstate <= 3'd0;
						end
						else if (read_index_q == 15)
							rstate <= 3'd3;
						else
							read_index_q <= read_index_q + 1'b1;
					end
				3'd3:
					if (m_rvalid && m_rlast) begin
						rsp_data <= 0;
						rsp_valid <= 1;
						rstate <= 3'd0;
					end
				default: rstate <= 3'd0;
			endcase
		end
	always @(posedge clk)
		if (rst) begin
			wstate <= 2'd0;
			write_base_q <= 0;
			write_index_q <= 0;
			write_count_q <= 0;
			write_error <= 0;
			write_poison <= 0;
		end
		else begin
			if (frame_start)
				write_error <= 0;
			case (wstate)
				2'd0: begin
					if (poisoned)
						write_count_q <= 0;
					else if ((write_count_q != 0) && ((finish_q || frame_finish) || (wr_valid && !write_contiguous))) begin
						write_index_q <= 0;
						wstate <= 2'd1;
					end
					if (write_fire) begin
						if (!write_address_ok)
							write_error[0] <= 1;
						else if (!poisoned) begin
							if (write_count_q == 0)
								write_base_q <= wr_addr;
							write_data[write_count_q[3:0]] <= wr_data;
							write_count_q <= write_count_q + 1'b1;
							if ((write_count_q == 15) || (wr_addr[11:4] == 8'hff)) begin
								write_index_q <= 0;
								wstate <= 2'd1;
							end
						end
					end
				end
				2'd1:
					if (m_awready) begin
						write_index_q <= 0;
						wstate <= 2'd2;
					end
				2'd2:
					if (m_wready) begin
						if (m_wlast)
							wstate <= 2'd3;
						else
							write_index_q <= write_index_q + 1'b1;
					end
				2'd3:
					if (m_bvalid) begin
						if (m_bresp != 0)
							write_error[3] <= 1;
						if (m_bid != AXI_ID) begin
							write_error[4] <= 1;
							write_poison <= 1;
						end
						write_count_q <= 0;
						wstate <= 2'd0;
					end
				default: wstate <= 2'd0;
			endcase
		end
endmodule
module soc_image_mmio_mem (
	clk,
	rst,
	ddr_ready,
	axi_poisoned,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	start,
	mode,
	src_base,
	dst_base,
	lut_we,
	lut_idx,
	lut_dat,
	engine_busy,
	engine_done,
	engine_error,
	active_cycles,
	read_beats,
	write_beats
);
	parameter [31:0] DDR_BASE = 32'h80000000;
	parameter [31:0] DDR_END = 32'h88000000;
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	input wire axi_poisoned;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output reg start;
	output reg mode;
	output wire [29:0] src_base;
	output wire [29:0] dst_base;
	output reg lut_we;
	output reg [7:0] lut_idx;
	output reg [7:0] lut_dat;
	input wire engine_busy;
	input wire engine_done;
	input wire engine_error;
	input wire [31:0] active_cycles;
	input wire [31:0] read_beats;
	input wire [31:0] write_beats;
	reg [31:0] source_q;
	reg [31:0] dest_q;
	reg done_hold;
	reg error_hold;
	reg rejected_hold;
	reg [7:0] lut_index;
	reg [255:0] lut_written;
	wire [31:0] out_bytes = (mode ? 32'd462400 : 32'd307200);
	wire valid_ranges = ((((((source_q >= DDR_BASE) && (source_q <= (DDR_END - 32'd1843200))) && (dest_q >= DDR_BASE)) && (dest_q <= (DDR_END - out_bytes))) && (source_q[3:0] == 0)) && (dest_q[3:0] == 0)) && ((({1'b0, dest_q} + {1'b0, out_bytes}) <= {1'b0, source_q}) || (({1'b0, source_q} + 33'd1843200) <= {1'b0, dest_q}));
	wire hit = (req_addr[15:8] == 8'h17) && (req_addr[1:0] == 0);
	assign req_ready = !rst && !rsp_valid;
	function automatic [29:0] sv2v_cast_30;
		input reg [29:0] inp;
		sv2v_cast_30 = inp;
	endfunction
	assign src_base = sv2v_cast_30(source_q - DDR_BASE);
	assign dst_base = sv2v_cast_30(dest_q - DDR_BASE);
	always @(posedge clk) begin
		start <= 0;
		lut_we <= 0;
		if (rst) begin
			source_q <= 0;
			dest_q <= 0;
			mode <= 0;
			done_hold <= 0;
			error_hold <= 0;
			rejected_hold <= 0;
			lut_written <= 0;
			lut_index <= 0;
			lut_idx <= 0;
			lut_dat <= 0;
			rsp_valid <= 0;
			rsp_error <= 0;
			rsp_rdata <= 0;
		end
		else begin
			if (engine_done) begin
				done_hold <= 1;
				error_hold <= engine_error;
			end
			if (engine_error)
				error_hold <= 1;
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			if (req_valid && req_ready) begin
				rsp_valid <= 1;
				rsp_error <= 0;
				rsp_rdata <= 0;
				if (!hit || (req_write && (req_wstrb != 4'hf))) begin
					rsp_error <= 1;
					rejected_hold <= 1;
				end
				else if (req_write) begin
					if (engine_busy) begin
						rsp_error <= 1;
						rejected_hold <= 1;
					end
					else
						case (req_addr[7:0])
							8'h00:
								if (((((req_wdata != 1) || !ddr_ready) || axi_poisoned) || !valid_ranges) || (!mode && !(&lut_written))) begin
									rsp_error <= 1;
									rejected_hold <= 1;
								end
								else begin
									start <= 1;
									done_hold <= 0;
									error_hold <= 0;
									rejected_hold <= 0;
								end
							8'h04: source_q <= req_wdata;
							8'h08: dest_q <= req_wdata;
							8'h0c:
								if (req_wdata > 1) begin
									rsp_error <= 1;
									rejected_hold <= 1;
								end
								else
									mode <= req_wdata[0];
							8'h24:
								if (req_wdata == 1) begin
									done_hold <= 0;
									error_hold <= 0;
									rejected_hold <= 0;
								end
								else begin
									rsp_error <= 1;
									rejected_hold <= 1;
								end
							8'h28:
								if (req_wdata > 255) begin
									rsp_error <= 1;
									rejected_hold <= 1;
								end
								else
									lut_index <= req_wdata[7:0];
							8'h2c:
								if (req_wdata > 255) begin
									rsp_error <= 1;
									rejected_hold <= 1;
								end
								else begin
									lut_we <= 1;
									lut_idx <= lut_index;
									lut_dat <= req_wdata[7:0];
									lut_written[lut_index] <= 1;
									lut_index <= lut_index + 1'b1;
								end
							default: begin
								rsp_error <= 1;
								rejected_hold <= 1;
							end
						endcase
				end
				else
					case (req_addr[7:0])
						8'h00: rsp_rdata <= 0;
						8'h04: rsp_rdata <= source_q;
						8'h08: rsp_rdata <= dest_q;
						8'h0c: rsp_rdata <= {31'd0, mode};
						8'h10: rsp_rdata <= {26'd0, axi_poisoned, ddr_ready, rejected_hold, error_hold || engine_error, done_hold, engine_busy};
						8'h14: rsp_rdata <= active_cycles;
						8'h18: rsp_rdata <= read_beats;
						8'h1c: rsp_rdata <= write_beats;
						8'h20: rsp_rdata <= 32'h494d4731;
						8'h24: rsp_rdata <= 0;
						8'h28: rsp_rdata <= {24'd0, lut_index};
						8'h2c: rsp_rdata <= 0;
						default: begin
							rsp_error <= 1;
							rejected_hold <= 1;
						end
					endcase
			end
		end
	end
endmodule
module soc_image_accel (
	clk,
	rst,
	ddr_ready,
	external_poisoned,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	m_awid,
	m_awaddr,
	m_awlen,
	m_awsize,
	m_awburst,
	m_awvalid,
	m_awready,
	m_wdata,
	m_wstrb,
	m_wlast,
	m_wvalid,
	m_wready,
	m_bid,
	m_bresp,
	m_bvalid,
	m_bready,
	m_arid,
	m_araddr,
	m_arlen,
	m_arsize,
	m_arburst,
	m_arvalid,
	m_arready,
	m_rid,
	m_rdata,
	m_rresp,
	m_rlast,
	m_rvalid,
	m_rready
);
	input wire clk;
	input wire rst;
	input wire ddr_ready;
	input wire external_poisoned;
	input wire req_valid;
	output wire req_ready;
	input wire [15:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output wire rsp_valid;
	input wire rsp_ready;
	output wire [31:0] rsp_rdata;
	output wire rsp_error;
	output wire [3:0] m_awid;
	output wire [31:0] m_awaddr;
	output wire [7:0] m_awlen;
	output wire [2:0] m_awsize;
	output wire [1:0] m_awburst;
	output wire m_awvalid;
	input wire m_awready;
	output wire [127:0] m_wdata;
	output wire [15:0] m_wstrb;
	output wire m_wlast;
	output wire m_wvalid;
	input wire m_wready;
	input wire [3:0] m_bid;
	input wire [1:0] m_bresp;
	input wire m_bvalid;
	output wire m_bready;
	output wire [3:0] m_arid;
	output wire [31:0] m_araddr;
	output wire [7:0] m_arlen;
	output wire [2:0] m_arsize;
	output wire [1:0] m_arburst;
	output wire m_arvalid;
	input wire m_arready;
	input wire [3:0] m_rid;
	input wire [127:0] m_rdata;
	input wire [1:0] m_rresp;
	input wire m_rlast;
	input wire m_rvalid;
	output wire m_rready;
	wire start;
	wire mode;
	wire lut_we;
	wire [29:0] src_base;
	wire [29:0] dst_base;
	wire [7:0] lut_idx;
	wire [7:0] lut_dat;
	reg busy;
	reg finish_seen;
	reg done;
	wire adapter_idle;
	wire drained;
	wire poisoned;
	wire [7:0] errors;
	reg [31:0] cycles;
	wire [31:0] read_beats;
	wire [31:0] write_beats;
	wire failed = (|errors || poisoned) || external_poisoned;
	wire [1:0] cbusy;
	wire [1:0] cdone;
	wire [1:0] rd_valid;
	wire [1:0] rd_ready;
	wire [1:0] rspv;
	wire [1:0] rspr;
	wire [1:0] wr_valid;
	wire [1:0] wr_ready;
	wire [59:0] rd_addr;
	wire [59:0] wr_addr;
	wire [255:0] rspd;
	wire [255:0] wr_data;
	wire [63:0] reads;
	wire [63:0] writes;
	assign read_beats = reads[mode * 32+:32];
	assign write_beats = writes[mode * 32+:32];
	soc_image_mmio_mem registers(
		.clk(clk),
		.rst(rst),
		.ddr_ready(ddr_ready),
		.axi_poisoned(poisoned || external_poisoned),
		.req_valid(req_valid),
		.req_ready(req_ready),
		.req_addr(req_addr),
		.req_write(req_write),
		.req_wdata(req_wdata),
		.req_wstrb(req_wstrb),
		.rsp_valid(rsp_valid),
		.rsp_ready(rsp_ready),
		.rsp_rdata(rsp_rdata),
		.rsp_error(rsp_error),
		.start(start),
		.mode(mode),
		.src_base(src_base),
		.dst_base(dst_base),
		.lut_we(lut_we),
		.lut_idx(lut_idx),
		.lut_dat(lut_dat),
		.engine_busy(busy || start),
		.engine_done(done),
		.engine_error((busy || done) && failed),
		.active_cycles(cycles),
		.read_beats(read_beats),
		.write_beats(write_beats)
	);
	always @(posedge clk) begin
		done <= 0;
		if (rst) begin
			busy <= 0;
			finish_seen <= 0;
			done <= 0;
			cycles <= 0;
		end
		else if (start) begin
			busy <= 1;
			finish_seen <= 0;
			cycles <= 0;
		end
		else if (busy) begin
			if (cycles != 32'hffffffff)
				cycles <= cycles + 1'b1;
			if (cdone[mode])
				finish_seen <= 1;
			if (finish_seen && drained) begin
				busy <= 0;
				done <= 1;
			end
		end
	end
	soc_preprocess320_core preprocess(
		.clk(clk),
		.rst(rst),
		.start(start && !mode),
		.src_base(src_base),
		.dst_base(dst_base),
		.busy(cbusy[0]),
		.done(cdone[0]),
		.lut_we(lut_we),
		.lut_idx(lut_idx),
		.lut_dat(lut_dat),
		.rd_valid(rd_valid[0]),
		.rd_ready(rd_ready[0]),
		.rd_addr(rd_addr[0+:30]),
		.rsp_valid(rspv[0]),
		.rsp_ready(rspr[0]),
		.rsp_data(rspd[0+:128]),
		.wr_valid(wr_valid[0]),
		.wr_ready(wr_ready[0]),
		.wr_addr(wr_addr[0+:30]),
		.wr_data(wr_data[0+:128]),
		.stat_rd_beats(reads[0+:32]),
		.stat_wr_beats(writes[0+:32])
	);
	soc_display_resize_core resize(
		.clk(clk),
		.rst(rst),
		.start(start && mode),
		.src_base(src_base),
		.dst_base(dst_base),
		.busy(cbusy[1]),
		.done(cdone[1]),
		.rd_valid(rd_valid[1]),
		.rd_ready(rd_ready[1]),
		.rd_addr(rd_addr[30+:30]),
		.rsp_valid(rspv[1]),
		.rsp_ready(rspr[1]),
		.rsp_data(rspd[128+:128]),
		.wr_valid(wr_valid[1]),
		.wr_ready(wr_ready[1]),
		.wr_addr(wr_addr[30+:30]),
		.wr_data(wr_data[128+:128]),
		.stat_rd_beats(reads[32+:32]),
		.stat_wr_beats(writes[32+:32])
	);
	wire core_rdready;
	wire core_rspvalid;
	wire core_wrready;
	wire [127:0] core_rspdata;
	assign rd_ready = (mode ? {core_rdready, 1'b0} : {1'b0, core_rdready});
	assign rspv = (mode ? {core_rspvalid, 1'b0} : {1'b0, core_rspvalid});
	assign wr_ready = (mode ? {core_wrready, 1'b0} : {1'b0, core_wrready});
	assign rspd = {core_rspdata, core_rspdata};
	soc_image_axi_adapter adapter(
		.clk(clk),
		.rst(rst),
		.frame_start(start),
		.frame_finish(cdone[mode]),
		.rd_valid(rd_valid[mode]),
		.rd_ready(core_rdready),
		.rd_addr(rd_addr[mode * 30+:30]),
		.rsp_valid(core_rspvalid),
		.rsp_ready(rspr[mode]),
		.rsp_data(core_rspdata),
		.wr_valid(wr_valid[mode]),
		.wr_ready(core_wrready),
		.wr_addr(wr_addr[mode * 30+:30]),
		.wr_data(wr_data[mode * 128+:128]),
		.idle(adapter_idle),
		.drained(drained),
		.error_sticky(errors),
		.poisoned(poisoned),
		.m_awid(m_awid),
		.m_awaddr(m_awaddr),
		.m_awlen(m_awlen),
		.m_awsize(m_awsize),
		.m_awburst(m_awburst),
		.m_awvalid(m_awvalid),
		.m_awready(m_awready),
		.m_wdata(m_wdata),
		.m_wstrb(m_wstrb),
		.m_wlast(m_wlast),
		.m_wvalid(m_wvalid),
		.m_wready(m_wready),
		.m_bid(m_bid),
		.m_bresp(m_bresp),
		.m_bvalid(m_bvalid),
		.m_bready(m_bready),
		.m_arid(m_arid),
		.m_araddr(m_araddr),
		.m_arlen(m_arlen),
		.m_arsize(m_arsize),
		.m_arburst(m_arburst),
		.m_arvalid(m_arvalid),
		.m_arready(m_arready),
		.m_rid(m_rid),
		.m_rdata(m_rdata),
		.m_rresp(m_rresp),
		.m_rlast(m_rlast),
		.m_rvalid(m_rvalid),
		.m_rready(m_rready)
	);
endmodule
module soc_gesture_label (
	enable,
	class_id,
	score_q15,
	box_x1,
	pixel_x,
	box_y1,
	pixel_y,
	pixel_rgb,
	label_rgb,
	label_active
);
	reg _sv2v_0;
	parameter signed [31:0] X_MIN = 20;
	parameter signed [31:0] X_LIMIT = 700;
	parameter signed [31:0] Y_MIN = 70;
	parameter signed [31:0] Y_LIMIT = 410;
	input wire enable;
	input wire [31:0] class_id;
	input wire [31:0] score_q15;
	input wire [10:0] box_x1;
	input wire [10:0] pixel_x;
	input wire [9:0] box_y1;
	input wire [9:0] pixel_y;
	input wire [23:0] pixel_rgb;
	output reg [23:0] label_rgb;
	output reg label_active;
	function automatic [34:0] glyph;
		input reg [7:0] ch;
		case (ch)
			8'd65: glyph = 35'b01110100011000111111100011000110001;
			8'd67: glyph = 35'b01111100001000010000100001000001111;
			8'd69: glyph = 35'b11111100001000011110100001000011111;
			8'd70: glyph = 35'b11111100001000011110100001000010000;
			8'd72: glyph = 35'b10001100011000111111100011000110001;
			8'd73: glyph = 35'b11111001000010000100001000010011111;
			8'd76: glyph = 35'b10000100001000010000100001000011111;
			8'd77: glyph = 35'b10001110111010110101100011000110001;
			8'd78: glyph = 35'b10001110011010110011100011000110001;
			8'd79: glyph = 35'b01110100011000110001100011000101110;
			8'd80: glyph = 35'b11110100011000111110100001000010000;
			8'd82: glyph = 35'b11110100011000111110101001001010001;
			8'd83: glyph = 35'b01111100001000001110000010000111110;
			8'd84: glyph = 35'b11111001000010000100001000010000100;
			8'd85: glyph = 35'b10001100011000110001100011000101110;
			8'd48: glyph = 35'b01110100011001110101110011000101110;
			8'd49: glyph = 35'b00100011000010000100001000010001110;
			8'd50: glyph = 35'b01110100010000100010001000100011111;
			8'd51: glyph = 35'b11110000010000101110000010000111110;
			8'd52: glyph = 35'b00010001100101010010111110001000010;
			8'd53: glyph = 35'b11111100001000011110000010000111110;
			8'd54: glyph = 35'b01110100001000011110100011000101110;
			8'd55: glyph = 35'b11111000010001000100010000100001000;
			8'd56: glyph = 35'b01110100011000101110100011000101110;
			8'd57: glyph = 35'b01110100011000101111000010000101110;
			8'd37: glyph = 35'b11001110100001000100010000101110011;
			default: glyph = 0;
		endcase
	endfunction
	function automatic [39:0] class_text;
		input reg [2:0] id;
		case (id)
			0: class_text = "FIST ";
			1: class_text = "ONE  ";
			2: class_text = "PEACE";
			3: class_text = "THREE";
			4: class_text = "FOUR ";
			5: class_text = "PALM ";
			default: class_text = "     ";
		endcase
	endfunction
	reg [39:0] name;
	reg [34:0] bits;
	reg [7:0] character;
	reg [21:0] scaled_score;
	reg [3:0] decimal_tens;
	reg [3:0] decimal_ones;
	reg [7:0] local_x;
	integer name_len;
	integer percent;
	integer digits;
	integer text_len;
	integer panel_width;
	integer left;
	integer top;
	integer dx;
	integer dy;
	integer index;
	integer number_index;
	integer gx;
	integer gy;
	function automatic [21:0] sv2v_cast_22;
		input reg [21:0] inp;
		sv2v_cast_22 = inp;
	endfunction
	function automatic signed [3:0] sv2v_cast_4_signed;
		input reg signed [3:0] inp;
		sv2v_cast_4_signed = inp;
	endfunction
	function automatic signed [7:0] sv2v_cast_8_signed;
		input reg signed [7:0] inp;
		sv2v_cast_8_signed = inp;
	endfunction
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		label_rgb = pixel_rgb;
		label_active = 0;
		name = class_text(class_id[2:0]);
		name_len = (class_id == 1 ? 3 : ((class_id == 2) || (class_id == 3) ? 5 : 4));
		scaled_score = (sv2v_cast_22(score_q15[15:0]) * 22'd100) + 22'd16384;
		percent = sv2v_cast_32_signed(scaled_score >> 15);
		if (percent > 100)
			percent = 100;
		decimal_tens = 0;
		decimal_ones = 0;
		if (percent < 100) begin
			begin : sv2v_autoblock_1
				integer digit;
				for (digit = 1; digit < 10; digit = digit + 1)
					if (percent >= (digit * 10))
						decimal_tens = sv2v_cast_4_signed(digit);
			end
			decimal_ones = sv2v_cast_4_signed(percent - (sv2v_cast_32_signed(decimal_tens) * 10));
		end
		digits = (percent >= 100 ? 3 : (percent >= 10 ? 2 : 1));
		text_len = ((name_len + 1) + digits) + 1;
		panel_width = 4 + (text_len * 12);
		left = sv2v_cast_32_signed(box_x1);
		if (left < X_MIN)
			left = X_MIN;
		if ((left + panel_width) > X_LIMIT)
			left = X_LIMIT - panel_width;
		top = (sv2v_cast_32_signed(box_y1) >= (Y_MIN + 18) ? sv2v_cast_32_signed(box_y1) - 18 : sv2v_cast_32_signed(box_y1) + 2);
		if (top < Y_MIN)
			top = Y_MIN;
		if ((top + 18) > Y_LIMIT)
			top = Y_LIMIT - 18;
		dx = sv2v_cast_32_signed(pixel_x) - left;
		dy = sv2v_cast_32_signed(pixel_y) - top;
		index = 0;
		number_index = 0;
		gx = 0;
		gy = 0;
		local_x = 0;
		character = 8'd32;
		bits = 0;
		if (((((((((((enable && (class_id < 6)) && (score_q15 <= 32768)) && ((X_LIMIT - X_MIN) >= panel_width)) && (pixel_x >= X_MIN)) && (pixel_x < X_LIMIT)) && (pixel_y >= Y_MIN)) && (pixel_y < Y_LIMIT)) && (dx >= 0)) && (dx < panel_width)) && (dy >= 0)) && (dy < 18)) begin
			label_active = 1;
			label_rgb = 24'h101010;
			if ((((dx >= 2) && (dx < (panel_width - 2))) && (dy >= 2)) && (dy < 16)) begin
				local_x = sv2v_cast_8_signed(dx - 2);
				begin : sv2v_autoblock_2
					integer cell_index;
					for (cell_index = 1; cell_index < 10; cell_index = cell_index + 1)
						if (local_x >= sv2v_cast_8_signed(cell_index * 12))
							index = cell_index;
				end
				gx = (sv2v_cast_32_signed(local_x) - (index * 12)) >> 1;
				gy = (dy - 2) >> 1;
				if (index < name_len)
					character = name[39 - (index * 8)-:8];
				else if ((index > name_len) && (index < ((name_len + 1) + digits))) begin
					number_index = (index - name_len) - 1;
					if ((digits == 3) && (number_index == 0))
						character = 8'd49;
					else if (number_index == (digits - 1))
						character = sv2v_cast_8(48 + decimal_ones);
					else
						character = sv2v_cast_8(48 + decimal_tens);
				end
				else if (index == (text_len - 1))
					character = 8'd37;
				bits = glyph(character);
				if (((gx < 5) && (gy < 7)) && bits[(34 - (gy * 5)) - gx])
					label_rgb = 24'hffffff;
			end
		end
	end
	initial _sv2v_0 = 0;
endmodule
module soc_mmio_2m_registered (
	clk,
	rst,
	s_req_valid,
	s_req_ready,
	s_req_addr,
	s_req_wdata,
	s_req_write,
	s_req_fetch,
	s_req_wstrb,
	s_rsp_valid,
	s_rsp_ready,
	s_rsp_rdata,
	s_rsp_error,
	m_req_valid,
	m_req_ready,
	m_req_addr,
	m_req_wdata,
	m_req_write,
	m_req_fetch,
	m_req_wstrb,
	m_rsp_valid,
	m_rsp_ready,
	m_rsp_rdata,
	m_rsp_error
);
	reg _sv2v_0;
	input wire clk;
	input wire rst;
	input wire [1:0] s_req_valid;
	output reg [1:0] s_req_ready;
	input wire [63:0] s_req_addr;
	input wire [63:0] s_req_wdata;
	input wire [1:0] s_req_write;
	input wire [1:0] s_req_fetch;
	input wire [7:0] s_req_wstrb;
	output reg [1:0] s_rsp_valid;
	input wire [1:0] s_rsp_ready;
	output reg [63:0] s_rsp_rdata;
	output reg [1:0] s_rsp_error;
	output reg m_req_valid;
	input wire m_req_ready;
	output reg [31:0] m_req_addr;
	output reg [31:0] m_req_wdata;
	output reg m_req_write;
	output reg m_req_fetch;
	output reg [3:0] m_req_wstrb;
	input wire m_rsp_valid;
	output reg m_rsp_ready;
	input wire [31:0] m_rsp_rdata;
	input wire m_rsp_error;
	localparam [1:0] IDLE = 0;
	localparam [1:0] ISSUE = 1;
	localparam [1:0] WAIT_RSP = 2;
	localparam [1:0] RETURN_RSP = 3;
	reg [1:0] state;
	reg owner;
	reg prefer;
	reg selected;
	reg [31:0] response;
	reg response_error;
	always @(*) begin
		if (_sv2v_0)
			;
		selected = (s_req_valid[prefer] ? prefer : ~prefer);
		s_req_ready = 0;
		s_rsp_valid = 0;
		s_rsp_error = 0;
		s_rsp_rdata[0+:32] = response;
		s_rsp_rdata[32+:32] = response;
		m_req_valid = !rst && (state == ISSUE);
		m_rsp_ready = !rst && (state == WAIT_RSP);
		if (!rst && (state == IDLE))
			s_req_ready[selected] = 1;
		if (!rst && (state == RETURN_RSP)) begin
			s_rsp_valid[owner] = 1;
			s_rsp_error[owner] = response_error;
		end
	end
	always @(posedge clk)
		if (rst) begin
			state <= IDLE;
			owner <= 0;
			prefer <= 0;
			response <= 0;
			response_error <= 0;
			m_req_addr <= 0;
			m_req_wdata <= 0;
			m_req_write <= 0;
			m_req_fetch <= 0;
			m_req_wstrb <= 0;
		end
		else
			case (state)
				IDLE:
					if (s_req_valid[selected]) begin
						owner <= selected;
						prefer <= ~selected;
						m_req_addr <= s_req_addr[selected * 32+:32];
						m_req_wdata <= s_req_wdata[selected * 32+:32];
						m_req_write <= s_req_write[selected];
						m_req_fetch <= s_req_fetch[selected];
						m_req_wstrb <= s_req_wstrb[selected * 4+:4];
						state <= ISSUE;
					end
				ISSUE:
					if (m_req_ready)
						state <= WAIT_RSP;
				WAIT_RSP:
					if (m_rsp_valid) begin
						response <= m_rsp_rdata;
						response_error <= m_rsp_error;
						state <= RETURN_RSP;
					end
				RETURN_RSP:
					if (s_rsp_ready[owner])
						state <= IDLE;
			endcase
	initial _sv2v_0 = 0;
endmodule
module soc_graph_executor (
	clk,
	rst,
	req_valid,
	req_ready,
	req_addr,
	req_write,
	req_wdata,
	req_wstrb,
	rsp_valid,
	rsp_ready,
	rsp_rdata,
	rsp_error,
	m_req_valid,
	m_req_ready,
	m_req_addr,
	m_req_wdata,
	m_req_write,
	m_req_wstrb,
	m_rsp_valid,
	m_rsp_ready,
	m_rsp_rdata,
	m_rsp_error,
	busy,
	poison,
	input_consumed
);
	parameter integer PROGRAM_ADDR_BITS = 13;
	parameter integer MAX_NODES = 256;
	input wire clk;
	input wire rst;
	input wire req_valid;
	output wire req_ready;
	input wire [7:0] req_addr;
	input wire req_write;
	input wire [31:0] req_wdata;
	input wire [3:0] req_wstrb;
	output reg rsp_valid;
	input wire rsp_ready;
	output reg [31:0] rsp_rdata;
	output reg rsp_error;
	output wire m_req_valid;
	input wire m_req_ready;
	output wire [31:0] m_req_addr;
	output wire [31:0] m_req_wdata;
	output wire m_req_write;
	output wire [3:0] m_req_wstrb;
	input wire m_rsp_valid;
	output wire m_rsp_ready;
	input wire [31:0] m_rsp_rdata;
	input wire m_rsp_error;
	output wire busy;
	output reg poison;
	output reg input_consumed;
	localparam integer DEPTH = 1 << PROGRAM_ADDR_BITS;
	localparam integer MAX_WORDS = DEPTH * 4;
	localparam [3:0] IDLE = 0;
	localparam [3:0] FETCH = 1;
	localparam [3:0] DECODE = 2;
	localparam [3:0] ISSUE = 3;
	localparam [3:0] RESPONSE = 4;
	localparam [3:0] POLL_DELAY = 5;
	localparam [3:0] TRACE0 = 6;
	localparam [3:0] TRACE1 = 7;
	localparam [3:0] TRACE2 = 8;
	localparam [3:0] TRACE3 = 9;
	localparam [3:0] FAULT_WAIT = 10;
	localparam [3:0] FAULT = 11;
	localparam [7:0] OP_END = 0;
	localparam [7:0] OP_WRITE = 1;
	localparam [7:0] OP_CONTEXT = 2;
	localparam [7:0] OP_WAIT = 3;
	localparam [7:0] OP_CHECK = 4;
	localparam [7:0] OP_ACCUM = 5;
	localparam [7:0] OP_BEGIN = 6;
	localparam [7:0] OP_END_NODE = 7;
	reg [31:0] program0 [0:DEPTH - 1];
	reg [31:0] program1 [0:DEPTH - 1];
	reg [31:0] program2 [0:DEPTH - 1];
	reg [31:0] program3 [0:DEPTH - 1];
	reg [31:0] q0;
	reg [31:0] q1;
	reg [31:0] q2;
	reg [31:0] q3;
	reg [31:0] a;
	reg [31:0] b;
	reg [31:0] c;
	reg [7:0] op;
	reg [PROGRAM_ADDR_BITS:0] pc;
	reg [31:0] loaded_words;
	reg [31:0] expected_words;
	reg [31:0] expected_crc;
	reg [31:0] crc_state;
	reg [31:0] crc_shift;
	reg [2:0] crc_left;
	reg program_valid;
	reg done;
	reg [31:0] model_epoch;
	reg [31:0] frame_epoch;
	reg [31:0] expected_nodes;
	reg [31:0] timeout_cycles;
	reg [31:0] program_generation;
	reg [31:0] elapsed;
	reg [31:0] instructions;
	reg [31:0] writes;
	reg [31:0] reads;
	reg [31:0] completed;
	reg [31:0] failure;
	reg [31:0] last_read;
	reg [31:0] node;
	reg [31:0] node_kind;
	reg [31:0] node_begin;
	reg [31:0] watchdog;
	reg [31:0] trace_elapsed;
	reg [31:0] trace_flags;
	reg [3:0] state;
	reg node_open;
	reg trace_fused;
	reg [4:0] poll_delay;
	reg [63:0] counters [0:31];
	reg [31:0] counter_latch_hi;
	reg [4:0] counter_index;
	reg [31:0] trace_mem [0:(MAX_NODES * 4) - 1];
	reg [31:0] trace_q;
	reg [9:0] trace_index;
	reg [9:0] trace_write_index;
	reg [31:0] trace_count;
	wire ctl = req_valid && req_ready;
	assign req_ready = (!rst && !rsp_valid) && (crc_left == 0);
	assign busy = state != IDLE;
	assign m_req_valid = !rst && (state == ISSUE);
	assign m_rsp_ready = !rst && ((state == RESPONSE) || (state == FAULT_WAIT));
	assign m_req_addr = a;
	assign m_req_wdata = (op[7:0] == OP_CONTEXT ? (b == 0 ? model_epoch : frame_epoch) : b);
	assign m_req_write = (op[7:0] == OP_WRITE) || (op[7:0] == OP_CONTEXT);
	assign m_req_wstrb = 4'hf;
	function automatic [31:0] crc_byte;
		input [31:0] prior;
		input [7:0] value;
		reg [31:0] r;
		integer i;
		begin
			r = prior ^ {24'd0, value};
			for (i = 0; i < 8; i = i + 1)
				r = (r[0] ? (r >> 1) ^ 32'hedb88320 : r >> 1);
			crc_byte = r;
		end
	endfunction
	function automatic allowed;
		input [31:0] addr;
		input wr;
		allowed = (addr[1:0] == 0) && ((((((addr >= 32'h70000100) && (addr <= 32'h700001bc)) || ((addr >= 32'h60001100) && (addr <= 32'h60001140))) || ((addr >= 32'h60001400) && (addr <= 32'h60001440))) || (!wr && (addr == 32'h7000000c))) || (wr && ((addr == 32'h70000014) || (addr == 32'h70000078))));
	endfunction
	always @(posedge clk) begin
		q0 <= program0[pc[PROGRAM_ADDR_BITS - 1:0]];
		q1 <= program1[pc[PROGRAM_ADDR_BITS - 1:0]];
		q2 <= program2[pc[PROGRAM_ADDR_BITS - 1:0]];
		q3 <= program3[pc[PROGRAM_ADDR_BITS - 1:0]];
		trace_q <= trace_mem[trace_index];
		if (((((((ctl && req_write) && (req_wstrb == 4'hf)) && (req_addr == 8'h1c)) && !busy) && !poison) && !program_valid) && (loaded_words < MAX_WORDS))
			case (loaded_words[1:0])
				0: program0[loaded_words[PROGRAM_ADDR_BITS + 1:2]] <= req_wdata;
				1: program1[loaded_words[PROGRAM_ADDR_BITS + 1:2]] <= req_wdata;
				2: program2[loaded_words[PROGRAM_ADDR_BITS + 1:2]] <= req_wdata;
				3: program3[loaded_words[PROGRAM_ADDR_BITS + 1:2]] <= req_wdata;
			endcase
		if (!rst)
			case (state)
				TRACE0: trace_mem[trace_write_index] <= trace_elapsed;
				TRACE1: trace_mem[trace_write_index + 10'd1] <= trace_flags;
				TRACE2: trace_mem[trace_write_index + 10'd2] <= 0;
				TRACE3: trace_mem[trace_write_index + 10'd3] <= 0;
				default:
					;
			endcase
	end
	integer i;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			rsp_valid <= 0;
			rsp_rdata <= 0;
			rsp_error <= 0;
			state <= IDLE;
			pc <= 0;
			loaded_words <= 0;
			expected_words <= 0;
			expected_crc <= 0;
			crc_state <= 32'hffffffff;
			crc_shift <= 0;
			crc_left <= 0;
			program_valid <= 0;
			done <= 0;
			poison <= 0;
			input_consumed <= 0;
			model_epoch <= 0;
			frame_epoch <= 0;
			expected_nodes <= 0;
			timeout_cycles <= 350000000;
			program_generation <= 0;
			elapsed <= 0;
			instructions <= 0;
			writes <= 0;
			reads <= 0;
			completed <= 0;
			failure <= 0;
			last_read <= 0;
			node <= 0;
			node_kind <= 0;
			node_begin <= 0;
			node_open <= 0;
			watchdog <= 0;
			poll_delay <= 0;
			trace_elapsed <= 0;
			trace_flags <= 0;
			trace_fused <= 0;
			trace_index <= 0;
			trace_write_index <= 0;
			trace_count <= 0;
			counter_index <= 0;
			counter_latch_hi <= 0;
			op <= 0;
			a <= 0;
			b <= 0;
			c <= 0;
			for (i = 0; i < 32; i = i + 1)
				counters[i] <= 0;
		end
		else begin
			if (rsp_valid && rsp_ready)
				rsp_valid <= 0;
			if (crc_left != 0) begin
				crc_state <= crc_byte(crc_state, crc_shift[7:0]);
				crc_shift <= crc_shift >> 8;
				crc_left <= crc_left - 1'b1;
			end
			if (busy && !poison) begin
				elapsed <= elapsed + 1'b1;
				watchdog <= watchdog + 1'b1;
			end
			if (ctl) begin
				rsp_valid <= 1;
				rsp_rdata <= 0;
				rsp_error <= 0;
				if ((req_addr[1:0] != 0) || (req_write && (req_wstrb != 4'hf)))
					rsp_error <= 1;
				else if (req_write) begin
					if (req_addr == 8'h54)
						trace_index <= req_wdata[9:0];
					else if (req_addr == 8'h5c)
						counter_index <= req_wdata[4:0];
					else if (busy || poison)
						rsp_error <= 1;
					else
						case (req_addr)
							8'h08:
								case (req_wdata)
									1: begin
										program_valid <= 0;
										done <= 0;
										loaded_words <= 0;
										crc_state <= 32'hffffffff;
										expected_words <= 0;
										expected_crc <= 0;
									end
									2:
										if ((((((loaded_words == 0) || (loaded_words[1:0] != 0)) || (loaded_words != expected_words)) || (~crc_state != expected_crc)) || (expected_nodes == 0)) || (expected_nodes > MAX_NODES))
											rsp_error <= 1;
										else begin
											program_valid <= 1;
											program_generation <= program_generation + 1'b1;
										end
									4:
										if (((!program_valid || (model_epoch == 0)) || (frame_epoch == 0)) || (timeout_cycles == 0))
											rsp_error <= 1;
										else begin
											state <= FETCH;
											pc <= 0;
											done <= 0;
											input_consumed <= 0;
											elapsed <= 0;
											watchdog <= 0;
											completed <= 0;
											trace_count <= 0;
											failure <= 0;
											instructions <= 0;
											writes <= 0;
											reads <= 0;
											node_open <= 0;
											for (i = 0; i < 32; i = i + 1)
												counters[i] <= 0;
										end
									8: done <= 0;
									default: rsp_error <= 1;
								endcase
							8'h10: expected_words <= req_wdata;
							8'h14: expected_crc <= req_wdata;
							8'h1c:
								if (program_valid || (loaded_words >= MAX_WORDS))
									rsp_error <= 1;
								else begin
									loaded_words <= loaded_words + 1'b1;
									crc_shift <= req_wdata;
									crc_left <= 4;
								end
							8'h20: model_epoch <= req_wdata;
							8'h24: frame_epoch <= req_wdata;
							8'h28: expected_nodes <= req_wdata;
							8'h2c: timeout_cycles <= req_wdata;
							default: rsp_error <= 1;
						endcase
				end
				else
					case (req_addr)
						8'h00: rsp_rdata <= 32'h31585047;
						8'h04: rsp_rdata <= {26'd0, input_consumed, crc_left != 0, poison, program_valid, done, busy};
						8'h0c: rsp_rdata <= loaded_words;
						8'h10: rsp_rdata <= expected_words;
						8'h14: rsp_rdata <= expected_crc;
						8'h18: rsp_rdata <= ~crc_state;
						8'h20: rsp_rdata <= model_epoch;
						8'h24: rsp_rdata <= frame_epoch;
						8'h28: rsp_rdata <= expected_nodes;
						8'h2c: rsp_rdata <= timeout_cycles;
						8'h30: rsp_rdata <= {{31 - PROGRAM_ADDR_BITS {1'b0}}, pc};
						8'h34: rsp_rdata <= completed;
						8'h38: rsp_rdata <= failure;
						8'h3c: rsp_rdata <= last_read;
						8'h40: rsp_rdata <= elapsed;
						8'h44: rsp_rdata <= instructions;
						8'h48: rsp_rdata <= writes;
						8'h4c: rsp_rdata <= reads;
						8'h50: rsp_rdata <= node;
						8'h54: rsp_rdata <= {22'd0, trace_index};
						8'h58: begin
							rsp_rdata <= ({22'd0, trace_index} < (trace_count * 4) ? trace_q : 0);
							trace_index <= trace_index + 1'b1;
						end
						8'h5c: rsp_rdata <= {27'd0, counter_index};
						8'h60: begin
							rsp_rdata <= counters[counter_index][31:0];
							counter_latch_hi <= counters[counter_index][63:32];
						end
						8'h64: rsp_rdata <= counter_latch_hi;
						8'h68: rsp_rdata <= MAX_WORDS;
						8'h6c: rsp_rdata <= program_generation;
						default: rsp_error <= 1;
					endcase
			end
			case (state)
				IDLE:
					;
				FETCH:
					if (({{31 - PROGRAM_ADDR_BITS {1'b0}}, pc} << 2) >= loaded_words) begin
						poison <= 1;
						failure <= 1;
						state <= FAULT;
					end
					else
						state <= DECODE;
				DECODE: begin
					op <= q0[7:0];
					a <= q1;
					b <= q2;
					c <= q3;
					watchdog <= 0;
					if (q0[31:8] != 0) begin
						poison <= 1;
						failure <= 2;
						state <= FAULT;
					end
					else
						case (q0[7:0])
							OP_END:
								if (((((node_open || (completed != expected_nodes)) || (q1 != expected_nodes)) || (q2 != 0)) || (q3 != 0)) || (((sv2v_cast_32(pc) + 1) * 4) != loaded_words)) begin
									poison <= 1;
									failure <= 3;
									state <= FAULT;
								end
								else begin
									done <= 1;
									state <= IDLE;
									instructions <= instructions + 1'b1;
								end
							OP_WRITE, OP_CONTEXT, OP_WAIT, OP_CHECK, OP_ACCUM:
								if ((((!allowed(q1, (q0[7:0] == OP_WRITE) || (q0[7:0] == OP_CONTEXT)) || ((q0[7:0] == OP_CONTEXT) && ((q2 > 1) || (q3 != 0)))) || ((q0[7:0] == OP_WRITE) && (q3 != 0))) || ((q0[7:0] == OP_WAIT) && (q2 == 0))) || ((q0[7:0] == OP_ACCUM) && ((q2 > 31) || ((q3 != 0) && (q3 != 32))))) begin
									poison <= 1;
									failure <= 4;
									state <= FAULT;
								end
								else
									state <= ISSUE;
							OP_BEGIN:
								if (((((node_open || (q1 != completed)) || (q1 >= expected_nodes)) || (q2 < 1)) || (q2 > 6)) || (q3 != 0)) begin
									poison <= 1;
									failure <= 5;
									state <= FAULT;
								end
								else begin
									node <= q1;
									node_kind <= q2;
									node_begin <= elapsed;
									node_open <= 1;
									pc <= pc + 1'b1;
									state <= FETCH;
									instructions <= instructions + 1'b1;
								end
							OP_END_NODE:
								if (((((!node_open || (q1 != node)) || (q2 > 1)) || (q3 > 2)) || ((q2 != 0) && (node_kind != 2))) || (((completed + 1) + q2) > expected_nodes)) begin
									poison <= 1;
									failure <= 6;
									state <= FAULT;
								end
								else begin
									node_open <= 0;
									trace_elapsed <= elapsed - node_begin;
									trace_flags <= 32'ha0000000;
									trace_write_index <= {node[7:0], 2'b00};
									trace_fused <= q2 != 0;
									state <= TRACE0;
									if (node == 0)
										input_consumed <= 1;
									case (node_kind)
										1: begin
											counters[18] <= counters[18] + 1'b1;
											counters[23] <= counters[23] + {32'd0, elapsed - node_begin};
											if (q3 == 1)
												counters[29] <= counters[29] + 1'b1;
											if (q3 == 2)
												counters[30] <= counters[30] + 1'b1;
										end
										2: begin
											counters[19] <= counters[19] + 1'b1;
											counters[24] <= counters[24] + {32'd0, elapsed - node_begin};
											if (q2 != 0)
												counters[20] <= counters[20] + 1'b1;
										end
										3: begin
											counters[21] <= counters[21] + 1'b1;
											counters[25] <= counters[25] + {32'd0, elapsed - node_begin};
										end
										4: begin
											counters[22] <= counters[22] + 1'b1;
											counters[26] <= counters[26] + {32'd0, elapsed - node_begin};
										end
										5: begin
											counters[22] <= counters[22] + 1'b1;
											counters[27] <= counters[27] + {32'd0, elapsed - node_begin};
										end
										6: begin
											counters[22] <= counters[22] + 1'b1;
											counters[28] <= counters[28] + {32'd0, elapsed - node_begin};
										end
										default:
											;
									endcase
								end
							default: begin
								poison <= 1;
								failure <= 7;
								state <= FAULT;
							end
						endcase
				end
				ISSUE:
					if (m_req_ready) begin
						state <= RESPONSE;
						if (m_req_write)
							writes <= writes + 1'b1;
						else
							reads <= reads + 1'b1;
					end
					else if (watchdog >= timeout_cycles) begin
						poison <= 1;
						failure <= 8;
						state <= FAULT;
					end
				RESPONSE:
					if (m_rsp_valid) begin
						last_read <= m_rsp_rdata;
						if (m_rsp_error) begin
							poison <= 1;
							failure <= 9;
							state <= FAULT;
						end
						else if ((op[7:0] == OP_WAIT) && ((m_rsp_rdata & c) != 0)) begin
							poison <= 1;
							failure <= 10;
							state <= FAULT;
						end
						else if ((op[7:0] == OP_WAIT) && ((m_rsp_rdata & b) == 0)) begin
							if (watchdog >= timeout_cycles) begin
								poison <= 1;
								failure <= 11;
								state <= FAULT;
							end
							else begin
								state <= POLL_DELAY;
								poll_delay <= 15;
							end
						end
						else if ((op[7:0] == OP_CHECK) && ((m_rsp_rdata & c) != (b & c))) begin
							poison <= 1;
							failure <= 12;
							state <= FAULT;
						end
						else begin
							if (op[7:0] == OP_ACCUM)
								counters[b[4:0]] <= counters[b[4:0]] + (c == 32 ? {m_rsp_rdata, 32'd0} : {32'd0, m_rsp_rdata});
							pc <= pc + 1'b1;
							state <= FETCH;
							instructions <= instructions + 1'b1;
						end
					end
					else if (watchdog >= timeout_cycles) begin
						poison <= 1;
						failure <= 13;
						state <= FAULT_WAIT;
					end
				POLL_DELAY:
					if (poll_delay == 0)
						state <= ISSUE;
					else
						poll_delay <= poll_delay - 1'b1;
				TRACE0: state <= TRACE1;
				TRACE1: state <= TRACE2;
				TRACE2: state <= TRACE3;
				TRACE3: begin
					completed <= completed + 1'b1;
					trace_count <= trace_count + 1'b1;
					if (trace_fused) begin
						trace_fused <= 0;
						trace_write_index <= trace_write_index + 10'd4;
						trace_elapsed <= 0;
						trace_flags <= 32'he0000000;
						state <= TRACE0;
					end
					else begin
						pc <= pc + 1'b1;
						state <= FETCH;
						instructions <= instructions + 1'b1;
					end
				end
				FAULT_WAIT:
					if (m_rsp_valid)
						state <= FAULT;
				FAULT:
					;
				default: begin
					poison <= 1;
					failure <= 14;
					state <= FAULT;
				end
			endcase
		end
endmodule
module soc_graph_mmio_fabric (
	clk,
	rst,
	cn_req_valid,
	cn_req_ready,
	cn_req_addr,
	cn_req_write,
	cn_req_wdata,
	cn_req_wstrb,
	cn_rsp_valid,
	cn_rsp_ready,
	cn_rsp_rdata,
	cn_rsp_error,
	n_req_valid,
	n_req_ready,
	n_req_addr,
	n_req_write,
	n_req_wdata,
	n_req_wstrb,
	n_rsp_valid,
	n_rsp_ready,
	n_rsp_rdata,
	n_rsp_error,
	cb_req_valid,
	cb_req_ready,
	cb_req_addr,
	cb_req_wdata,
	cb_req_write,
	cb_req_fetch,
	cb_req_wstrb,
	cb_rsp_valid,
	cb_rsp_ready,
	cb_rsp_rdata,
	cb_rsp_error,
	b_req_valid,
	b_req_ready,
	b_req_addr,
	b_req_wdata,
	b_req_write,
	b_req_fetch,
	b_req_wstrb,
	b_rsp_valid,
	b_rsp_ready,
	b_rsp_rdata,
	b_rsp_error,
	graph_busy,
	graph_poison,
	graph_input_consumed
);
	parameter integer PROGRAM_ADDR_BITS = 13;
	input wire clk;
	input wire rst;
	input wire cn_req_valid;
	output wire cn_req_ready;
	input wire [15:0] cn_req_addr;
	input wire cn_req_write;
	input wire [31:0] cn_req_wdata;
	input wire [3:0] cn_req_wstrb;
	output wire cn_rsp_valid;
	input wire cn_rsp_ready;
	output wire [31:0] cn_rsp_rdata;
	output wire cn_rsp_error;
	output wire n_req_valid;
	input wire n_req_ready;
	output wire [15:0] n_req_addr;
	output wire n_req_write;
	output wire [31:0] n_req_wdata;
	output wire [3:0] n_req_wstrb;
	input wire n_rsp_valid;
	output wire n_rsp_ready;
	input wire [31:0] n_rsp_rdata;
	input wire n_rsp_error;
	input wire cb_req_valid;
	output wire cb_req_ready;
	input wire [31:0] cb_req_addr;
	input wire [31:0] cb_req_wdata;
	input wire cb_req_write;
	input wire cb_req_fetch;
	input wire [3:0] cb_req_wstrb;
	output wire cb_rsp_valid;
	input wire cb_rsp_ready;
	output wire [31:0] cb_rsp_rdata;
	output wire cb_rsp_error;
	output wire b_req_valid;
	input wire b_req_ready;
	output wire [31:0] b_req_addr;
	output wire [31:0] b_req_wdata;
	output wire b_req_write;
	output wire b_req_fetch;
	output wire [3:0] b_req_wstrb;
	input wire b_rsp_valid;
	output wire b_rsp_ready;
	input wire [31:0] b_rsp_rdata;
	input wire b_rsp_error;
	output wire graph_busy;
	output wire graph_poison;
	output wire graph_input_consumed;
	reg local_owner;
	reg cn_busy;
	wire local_select = cn_req_addr[15:8] == 8'h02;
	wire l_req_ready;
	wire l_rsp_valid;
	wire l_rsp_ready;
	wire l_rsp_error;
	wire [31:0] l_rsp_data;
	wire g_req_valid;
	wire g_req_ready;
	wire g_req_write;
	wire g_rsp_valid;
	wire g_rsp_ready;
	wire g_rsp_error;
	wire [31:0] g_req_addr;
	wire [31:0] g_req_data;
	wire [31:0] g_rsp_data;
	wire [3:0] g_req_strb;
	wire [1:0] nv;
	wire [1:0] nr;
	wire [1:0] nsv;
	wire [1:0] nsr;
	wire [1:0] nse;
	wire [1:0] bv;
	wire [1:0] br;
	wire [1:0] bsv;
	wire [1:0] bsr;
	wire [1:0] bse;
	wire [63:0] na;
	wire [63:0] nd;
	wire [63:0] nsd;
	wire [63:0] ba;
	wire [63:0] bd;
	wire [63:0] bsd;
	wire [31:0] unused_n_full_addr;
	wire n_unused_fetch;
	assign cn_req_ready = !cn_busy && (local_select ? l_req_ready : nr[0]);
	assign cn_rsp_valid = cn_busy && (local_owner ? l_rsp_valid : nsv[0]);
	assign cn_rsp_rdata = (local_owner ? l_rsp_data : nsd[0+:32]);
	assign cn_rsp_error = (local_owner ? l_rsp_error : nse[0]);
	assign l_rsp_ready = (cn_busy && local_owner) && cn_rsp_ready;
	assign nsr[0] = (cn_busy && !local_owner) && cn_rsp_ready;
	always @(posedge clk)
		if (rst) begin
			cn_busy <= 0;
			local_owner <= 0;
		end
		else begin
			if (cn_req_valid && cn_req_ready) begin
				cn_busy <= 1;
				local_owner <= local_select;
			end
			if (cn_rsp_valid && cn_rsp_ready)
				cn_busy <= 0;
		end
	soc_graph_executor #(.PROGRAM_ADDR_BITS(PROGRAM_ADDR_BITS)) executor(
		.clk(clk),
		.rst(rst),
		.req_valid((cn_req_valid && !cn_busy) && local_select),
		.req_ready(l_req_ready),
		.req_addr(cn_req_addr[7:0]),
		.req_write(cn_req_write),
		.req_wdata(cn_req_wdata),
		.req_wstrb(cn_req_wstrb),
		.rsp_valid(l_rsp_valid),
		.rsp_ready(l_rsp_ready),
		.rsp_rdata(l_rsp_data),
		.rsp_error(l_rsp_error),
		.m_req_valid(g_req_valid),
		.m_req_ready(g_req_ready),
		.m_req_addr(g_req_addr),
		.m_req_wdata(g_req_data),
		.m_req_write(g_req_write),
		.m_req_wstrb(g_req_strb),
		.m_rsp_valid(g_rsp_valid),
		.m_rsp_ready(g_rsp_ready),
		.m_rsp_rdata(g_rsp_data),
		.m_rsp_error(g_rsp_error),
		.busy(graph_busy),
		.poison(graph_poison),
		.input_consumed(graph_input_consumed)
	);
	assign nv = {g_req_valid && g_req_addr[28], (cn_req_valid && !cn_busy) && !local_select};
	assign na = {g_req_addr, 16'd0, cn_req_addr};
	assign nd = {g_req_data, cn_req_wdata};
	assign bv = {g_req_valid && !g_req_addr[28], cb_req_valid};
	assign ba = {g_req_addr, cb_req_addr};
	assign bd = {g_req_data, cb_req_wdata};
	assign g_req_ready = (g_req_addr[28] ? nr[1] : br[1]);
	assign g_rsp_valid = (g_req_addr[28] ? nsv[1] : bsv[1]);
	assign g_rsp_data = (g_req_addr[28] ? nsd[32+:32] : bsd[32+:32]);
	assign g_rsp_error = (g_req_addr[28] ? nse[1] : bse[1]);
	assign nsr[1] = g_rsp_ready && g_req_addr[28];
	assign bsr = {g_rsp_ready && !g_req_addr[28], cb_rsp_ready};
	assign cb_req_ready = br[0];
	assign cb_rsp_valid = bsv[0];
	assign cb_rsp_rdata = bsd[0+:32];
	assign cb_rsp_error = bse[0];
	assign n_req_addr = unused_n_full_addr[15:0];
	soc_mmio_2m_registered npu_arb(
		.clk(clk),
		.rst(rst),
		.s_req_valid(nv),
		.s_req_ready(nr),
		.s_req_addr(na),
		.s_req_wdata(nd),
		.s_req_write({g_req_write, cn_req_write}),
		.s_req_fetch(2'b00),
		.s_req_wstrb({g_req_strb, cn_req_wstrb}),
		.s_rsp_valid(nsv),
		.s_rsp_ready(nsr),
		.s_rsp_rdata(nsd),
		.s_rsp_error(nse),
		.m_req_valid(n_req_valid),
		.m_req_ready(n_req_ready),
		.m_req_addr(unused_n_full_addr),
		.m_req_wdata(n_req_wdata),
		.m_req_write(n_req_write),
		.m_req_fetch(n_unused_fetch),
		.m_req_wstrb(n_req_wstrb),
		.m_rsp_valid(n_rsp_valid),
		.m_rsp_ready(n_rsp_ready),
		.m_rsp_rdata(n_rsp_rdata),
		.m_rsp_error(n_rsp_error)
	);
	soc_mmio_2m_registered board_arb(
		.clk(clk),
		.rst(rst),
		.s_req_valid(bv),
		.s_req_ready(br),
		.s_req_addr(ba),
		.s_req_wdata(bd),
		.s_req_write({g_req_write, cb_req_write}),
		.s_req_fetch({1'b0, cb_req_fetch}),
		.s_req_wstrb({g_req_strb, cb_req_wstrb}),
		.s_rsp_valid(bsv),
		.s_rsp_ready(bsr),
		.s_rsp_rdata(bsd),
		.s_rsp_error(bse),
		.m_req_valid(b_req_valid),
		.m_req_ready(b_req_ready),
		.m_req_addr(b_req_addr),
		.m_req_wdata(b_req_wdata),
		.m_req_write(b_req_write),
		.m_req_fetch(b_req_fetch),
		.m_req_wstrb(b_req_wstrb),
		.m_rsp_valid(b_rsp_valid),
		.m_rsp_ready(b_rsp_ready),
		.m_rsp_rdata(b_rsp_rdata),
		.m_rsp_error(b_rsp_error)
	);
endmodule
module npu_response_order_inorder (
	clk,
	rst,
	issue_valid,
	issue_ready,
	issue_id,
	issue_write,
	rsp_valid,
	rsp_ready,
	rsp_id,
	rsp_write,
	rsp_error,
	rsp_data,
	out_valid,
	out_ready,
	out_id,
	out_write,
	out_error,
	out_data,
	drained,
	idle,
	protocol_poison,
	owned
);
	parameter signed [31:0] DATA_W = 128;
	parameter signed [31:0] ID_W = 4;
	parameter signed [31:0] SLOTS = 16;
	input wire clk;
	input wire rst;
	input wire issue_valid;
	output wire issue_ready;
	input wire [ID_W - 1:0] issue_id;
	input wire issue_write;
	input wire rsp_valid;
	output wire rsp_ready;
	input wire [ID_W - 1:0] rsp_id;
	input wire rsp_write;
	input wire rsp_error;
	input wire [DATA_W - 1:0] rsp_data;
	output wire out_valid;
	input wire out_ready;
	output wire [ID_W - 1:0] out_id;
	output wire out_write;
	output wire out_error;
	output wire [DATA_W - 1:0] out_data;
	output wire drained;
	output wire idle;
	output reg protocol_poison;
	output reg [$clog2(SLOTS + 1) - 1:0] owned;
	localparam signed [31:0] PTR_W = $clog2(SLOTS);
	localparam signed [31:0] COUNT_W = $clog2(SLOTS + 1);
	reg [SLOTS - 1:0] live;
	reg [ID_W:0] expected [0:SLOTS - 1];
	reg [PTR_W - 1:0] head;
	reg [PTR_W - 1:0] tail;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	wire issue_known = sv2v_cast_32(issue_id) < SLOTS;
	wire response_legal = (((owned != 0) && (sv2v_cast_32(rsp_id) < SLOTS)) && live[rsp_id]) && (expected[head] == {rsp_write, rsp_id});
	function automatic signed [COUNT_W - 1:0] sv2v_cast_D4579_signed;
		input reg signed [COUNT_W - 1:0] inp;
		sv2v_cast_D4579_signed = inp;
	endfunction
	assign issue_ready = (((!rst && !protocol_poison) && issue_known) && !live[issue_id]) && (owned < sv2v_cast_D4579_signed(SLOTS));
	assign rsp_ready = !rst && ((protocol_poison || !response_legal) || out_ready);
	assign out_valid = ((!rst && !protocol_poison) && rsp_valid) && response_legal;
	assign out_data = rsp_data;
	assign out_id = rsp_id;
	assign out_write = rsp_write;
	assign out_error = rsp_error;
	wire push = issue_valid && issue_ready;
	wire pop = out_valid && out_ready;
	assign drained = owned == 0;
	assign idle = (!rst && !protocol_poison) && drained;
	always @(posedge clk)
		if (rst) begin
			live <= 0;
			head <= 0;
			tail <= 0;
			owned <= 0;
			protocol_poison <= 0;
		end
		else begin
			if (issue_valid && !issue_known)
				protocol_poison <= 1;
			if (((rsp_valid && rsp_ready) && !protocol_poison) && !response_legal)
				protocol_poison <= 1;
			if (push) begin
				expected[tail] <= {issue_write, issue_id};
				tail <= tail + 1'b1;
				live[issue_id] <= 1;
			end
			if (pop) begin
				head <= head + 1'b1;
				live[out_id] <= 0;
			end
			case ({push, pop})
				2'b10: owned <= owned + 1'b1;
				2'b01: owned <= owned - 1'b1;
				default:
					;
			endcase
		end
	initial if (((SLOTS < 2) || ((SLOTS & (SLOTS - 1)) != 0)) || (SLOTS > (1 << ID_W))) begin
		$display("Fatal [%0t] F:/Codex/G24/optimization_final/after_conversion/npu_response_order.sv:82:4 - npu_response_order_inorder.<unnamed_block>.<unnamed_block>\n msg: ", $time, "ORDERED_RETURN_PARAMETER_RED");
		$finish(1);
	end
endmodule

module npu_response_order_reorder (
	clk,
	rst,
	issue_valid,
	issue_ready,
	issue_id,
	issue_write,
	rsp_valid,
	rsp_ready,
	rsp_id,
	rsp_write,
	rsp_error,
	rsp_data,
	out_valid,
	out_ready,
	out_id,
	out_write,
	out_error,
	out_data,
	drained,
	idle,
	protocol_poison,
	owned
);
	parameter signed [31:0] DATA_W = 128;
	parameter signed [31:0] ID_W = 4;
	parameter signed [31:0] SLOTS = 16;
	input wire clk;
	input wire rst;
	input wire issue_valid;
	output wire issue_ready;
	input wire [ID_W - 1:0] issue_id;
	input wire issue_write;
	input wire rsp_valid;
	output wire rsp_ready;
	input wire [ID_W - 1:0] rsp_id;
	input wire rsp_write;
	input wire rsp_error;
	input wire [DATA_W - 1:0] rsp_data;
	output wire out_valid;
	input wire out_ready;
	output wire [ID_W - 1:0] out_id;
	output wire out_write;
	output wire out_error;
	output wire [DATA_W - 1:0] out_data;
	output wire drained;
	output wire idle;
	output reg protocol_poison;
	output reg [$clog2(SLOTS + 1) - 1:0] owned;
	localparam signed [31:0] PTR_W = $clog2(SLOTS);
	localparam signed [31:0] COUNT_W = $clog2(SLOTS + 1);
	localparam signed [31:0] PAYLOAD_W = (DATA_W + ID_W) + 2;
	reg [SLOTS - 1:0] live;
	reg [SLOTS - 1:0] returned;
	reg [SLOTS - 1:0] expected_write;
	reg [ID_W - 1:0] order_ids [0:SLOTS - 1];
	reg [PTR_W - 1:0] tail;
	reg [PTR_W - 1:0] fetch;
	reg [COUNT_W - 1:0] unfetched;
	reg [1:0] fifo_count;
	reg fifo_rd;
	reg fifo_wr;
	reg [PAYLOAD_W - 1:0] fifo_payload [0:1];
	reg read_pending;
	reg [ID_W - 1:0] ram_tag;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	wire issue_known = sv2v_cast_32(issue_id) < SLOTS;
	wire response_known = ((sv2v_cast_32(rsp_id) < SLOTS) && live[rsp_id]) && !returned[rsp_id];
	function automatic signed [COUNT_W - 1:0] sv2v_cast_D4579_signed;
		input reg signed [COUNT_W - 1:0] inp;
		sv2v_cast_D4579_signed = inp;
	endfunction
	assign issue_ready = (((!rst && !protocol_poison) && issue_known) && !live[issue_id]) && (owned < sv2v_cast_D4579_signed(SLOTS));
	assign rsp_ready = !rst;
	wire push = issue_valid && issue_ready;
	wire receive = rsp_valid && rsp_ready;
	wire receive_owned = receive && response_known;
	assign out_valid = !rst && (fifo_count != 0);
	assign {out_write, out_error, out_id, out_data} = fifo_payload[fifo_rd];
	wire pop = out_valid && out_ready;
	wire fifo_in_ready = (fifo_count < 2) || pop;
	wire fifo_in_fire = read_pending && fifo_in_ready;
	wire [2:0] buffered = {1'b0, fifo_count} + {2'd0, read_pending};
	wire [ID_W - 1:0] fetch_id = order_ids[fetch];
	wire read_issue = (((!rst && (unfetched != 0)) && returned[fetch_id]) && (!read_pending || fifo_in_ready)) && ((buffered < 2) || pop);
	wire [DATA_W + 1:0] memory_result;
	function automatic [PTR_W - 1:0] sv2v_cast_E310E;
		input reg [PTR_W - 1:0] inp;
		sv2v_cast_E310E = inp;
	endfunction
	npu_order_word_ram #(
		.WIDTH(DATA_W + 2),
		.ADDR_W(PTR_W)
	) payload(
		.clk(clk),
		.wr_en(receive_owned),
		.wr_addr(sv2v_cast_E310E(rsp_id)),
		.wr_data({rsp_write, rsp_error, rsp_data}),
		.rd_en(read_issue),
		.rd_addr(sv2v_cast_E310E(fetch_id)),
		.rd_data(memory_result)
	);
	assign drained = (((owned == 0) && (unfetched == 0)) && (fifo_count == 0)) && !read_pending;
	assign idle = (!rst && drained) && !protocol_poison;
	always @(posedge clk)
		if (rst) begin
			live <= 0;
			returned <= 0;
			expected_write <= 0;
			tail <= 0;
			fetch <= 0;
			owned <= 0;
			unfetched <= 0;
			fifo_count <= 0;
			fifo_rd <= 0;
			fifo_wr <= 0;
			read_pending <= 0;
			ram_tag <= 0;
			protocol_poison <= 0;
		end
		else begin
			if (issue_valid && !issue_known)
				protocol_poison <= 1;
			if (push) begin
				order_ids[tail] <= issue_id;
				tail <= tail + 1'b1;
				live[issue_id] <= 1;
				returned[issue_id] <= 0;
				expected_write[issue_id] <= issue_write;
			end
			if (receive) begin
				if (!response_known)
					protocol_poison <= 1;
				else begin
					returned[rsp_id] <= 1;
					if (rsp_write != expected_write[rsp_id])
						protocol_poison <= 1;
				end
			end
			if (fifo_in_fire) begin
				fifo_payload[fifo_wr] <= {memory_result[DATA_W + 1:DATA_W], ram_tag, memory_result[DATA_W - 1:0]};
				fifo_wr <= !fifo_wr;
				read_pending <= 0;
			end
			if (read_issue) begin
				ram_tag <= fetch_id;
				fetch <= fetch + 1'b1;
				read_pending <= 1;
			end
			if (pop) begin
				if (((sv2v_cast_32(out_id) >= SLOTS) || !live[out_id]) || !returned[out_id])
					protocol_poison <= 1;
				else begin
					live[out_id] <= 0;
					returned[out_id] <= 0;
				end
				fifo_rd <= !fifo_rd;
			end
			case ({push, pop})
				2'b10: owned <= owned + 1'b1;
				2'b01: owned <= owned - 1'b1;
				default:
					;
			endcase
			case ({push, read_issue})
				2'b10: unfetched <= unfetched + 1'b1;
				2'b01: unfetched <= unfetched - 1'b1;
				default:
					;
			endcase
			case ({fifo_in_fire, pop})
				2'b10: fifo_count <= fifo_count + 1'b1;
				2'b01: fifo_count <= fifo_count - 1'b1;
				default:
					;
			endcase
		end
	initial if (((SLOTS < 2) || ((SLOTS & (SLOTS - 1)) != 0)) || (SLOTS > (1 << ID_W))) begin
		$display("Fatal [%0t] F:/Codex/G24/optimization_final/after_conversion/npu_response_order.sv:163:53 - npu_response_order_reorder.<unnamed_block>.<unnamed_block>\n msg: ", $time, "RESPONSE_ORDER_PARAMETER_RED");
		$finish(1);
	end
endmodule
