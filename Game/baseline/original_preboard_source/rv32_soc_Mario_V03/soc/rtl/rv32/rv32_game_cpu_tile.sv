// CPU/cache RTL is imported byte-for-byte from rv32_core_01 RV32CM120 I2W2.
// Direct core/cache connections equal the donor REGISTER_* = 0 integration.
// Board-only DATA_RAM_GUARD is disabled so the game data SRAM and DDR cache
// window are legal. SRAM and DDR adapters independently enforce their ranges.
module rv32_game_cpu_tile #(
 parameter ITCM_INIT_FILE="",DTCM_INIT_FILE="",
 parameter logic [31:0] DDR_BASE=32'h80000000,
 parameter logic [32:0] DDR_BYTES=33'h010000000
)(
 input logic clk,rst,irq_fault,
 output logic system_req_valid,input logic system_req_ready,
 output logic [31:0] system_req_addr,system_req_wdata,
 output logic system_req_write,system_req_is_fetch,output logic [3:0] system_req_wstrb,
 input logic system_rsp_valid,output logic system_rsp_ready,
 input logic [31:0] system_rsp_rdata,input logic system_rsp_error,
 output logic [1:0] cache_mem_req_valid,cache_mem_req_write,
 input logic [1:0] cache_mem_req_ready,
 output logic [1:0][31:0] cache_mem_req_addr,
 output logic [1:0][127:0] cache_mem_req_wdata,
 output logic [1:0][15:0] cache_mem_req_wstrb,
 output logic [1:0][3:0] cache_mem_req_tag,
 input logic [1:0] cache_mem_rsp_valid,cache_mem_rsp_write,cache_mem_rsp_error,
 output logic [1:0] cache_mem_rsp_ready,
 input logic [1:0][127:0] cache_mem_rsp_rdata,
 input logic [1:0][3:0] cache_mem_rsp_tag,
 output logic cache_protocol_fault,retire_valid_diag,trap_event,
 output logic [31:0] retire_pc_diag,output logic [1:0] retire_count_diag
);
 wire iv,ir,ipv,ipr,dv,dr,dw,dpv,dpr,dpe,fi,fd,maintenance_busy,event_i,event_d,event_w;
 wire [31:0] ia,da,dwd,dpd;
 wire [63:0] ipd;
 wire [1:0] ipe,dz;
 wire [3:0] ds;
 wire [1:0] retired_mask;
 wire [31:0] retire_pc0,retire_pc1,retire_instruction0,retire_instruction1,retire_value0,retire_value1;
 wire [4:0] retire_destination0,retire_destination1;
 wire redirect_event;
 logic [63:0] cycles;
 always_ff @(posedge clk)if(rst)cycles<=0;else cycles<=cycles+1'b1;
 assign retire_valid_diag=|retired_mask;
 assign retire_count_diag={1'b0,retired_mask[0]}+{1'b0,retired_mask[1]};
 assign retire_pc_diag=retired_mask[0]?retire_pc0:retire_pc1;
 assign system_req_is_fetch=1'b0;
 wire instr_req_o,instr_gnt_i,instr_io_o,instr_rvalid_i,instr_rready_o,instr_err_i;
 wire [31:0] instr_addr_o;
 wire [63:0] instr_rdata_i;
 wire data_rd_req_o,data_rd_gnt_i,data_rd_id_o,data_rd_rvalid_i,data_rd_rready_o,data_rd_rid_i,data_rd_err_i;
 wire [31:0] data_rd_addr_o;
 wire [63:0] data_rd_rdata_i;
 wire data_wr_req_o,data_wr_gnt_i,data_wr_last_o,data_wr_id_o,data_wr_bvalid_i,data_wr_berr_i,data_wr_bid_i;
 wire [31:0] data_wr_addr_o;
 wire [63:0] data_wr_data_o;
 wire periph_req_o,periph_gnt_i,periph_we_o,periph_rvalid_i,periph_err_i;
 wire [31:0] periph_addr_o,periph_wdata_o,periph_rdata_i;
 wire [3:0] periph_be_o;
 wire [1:0] periph_size_o;
 rv32_ooo_core #(
  .RESET_VECTOR(32'h10000000),
  .LOAD_ORDER_ISSUE_LOOKAHEAD(1),
  .MEMORY_CREDITS(3),
  .FETCH_CREDITS(2),
  .ENABLE_COMMITTED_RAS(1),
  .RAS_DEPTH(16),
  .HISTORY_BITS(12),
  .BIMODAL_INDEX_BITS(9),
  .GSHARE_INDEX_BITS(12),
  .ENABLE_PAIRING(1),
  .FAST_WAKEUP(1),
  .ENABLE_SAME_CYCLE_REUSE(0),
  .CARRIED_COMPLETION_WRITES(1),
  .DECOUPLED_ALLOCATION_PAYLOAD(1),
  .BANKED_ISSUE(1),
  .ENABLE_MDU_TURNOVER(1),
  .ENABLE_MDU_SPILL(1),
  .ENABLE_MUL_STREAM(1),
  .ENABLE_STEALING(1),
  .ENABLE_ORDERED_STORE_PREP(1),
  .ENABLE_STORE_HEAD_LOOKAHEAD(1),
  .ENABLE_STORE_ISSUE_LOOKAHEAD(1),
  .ENABLE_REDIRECT_FETCH(1),
  .ENABLE_CURRENT_INTEGER_PAIR(1),
  .ENABLE_CONTROL_DISPATCH(1),
  .ENABLE_DISPATCH_BYPASS(1),
  .DISPATCH_BYPASS_UNMAPPED_ONLY(1),
  .LOAD_BYPASS(1),
  .ENABLE_TRACE(0)
 ) processor(
        .clk(clk),.reset(rst),
        .imem_request_valid(iv),.imem_request_ready(ir),.imem_request_address(ia),
        .imem_response_valid(ipv),.imem_response_ready(ipr),
        .imem_response_data(ipd),.imem_response_error(ipe),
        .dmem_request_valid(dv),.dmem_request_ready(dr),.dmem_request_address(da),
        .dmem_request_write(dw),.dmem_request_size(dz),.dmem_request_wdata(dwd),
        .dmem_request_wstrb(ds),.dmem_response_valid(dpv),.dmem_response_ready(dpr),
        .dmem_response_rdata(dpd),.dmem_response_error(dpe),
        .irq_software(1'b0),.irq_timer(1'b0),.irq_external(irq_fault|cache_protocol_fault),
        .mtime(cycles),.event_icache_refill(event_i),.event_dcache_refill(event_d),
        .event_dcache_writeback(event_w),.fence_i(fi),.fence_d(fd),
        .debug_redirect(redirect_event),.debug_trap(trap_event),
        .debug_branch_miss(),.debug_jump_miss(),
        .debug_dispatch_stall(),.debug_frontend_stall(),
        .retire_valid(retired_mask),.retire_pc0(retire_pc0),.retire_pc1(retire_pc1),
        .retire_instruction0(retire_instruction0),.retire_instruction1(retire_instruction1),
        .retire_destination0(retire_destination0),.retire_destination1(retire_destination1),
        .retire_value0(retire_value0),.retire_value1(retire_value1)
    );
    rv32_memory_system #(.I_INDEX_BITS(7),.I_WAYS(2),.D_INDEX_BITS(6),.D_WAYS(2),
        .ENABLE_FAST_ICROSS(1),
        .ENABLE_DATA_RAM_GUARD(0),
        .DATA_RAM_BASE(32'h10000000),.DATA_RAM_LIMIT(32'h8fffffff)) memory (
        .clk(clk),.reset(rst),
        .imem_request_valid(iv),.imem_request_ready(ir),.imem_request_address(ia),
        .imem_response_valid(ipv),.imem_response_ready(ipr),
        .imem_response_data(ipd),.imem_response_error(ipe),
        .dmem_request_valid(dv),.dmem_request_ready(dr),.dmem_request_address(da),
        .dmem_request_write(dw),.dmem_request_wdata(dwd),.dmem_request_wstrb(ds),
        .dmem_request_size(dz),.dmem_response_valid(dpv),.dmem_response_ready(dpr),
        .dmem_response_rdata(dpd),.dmem_response_error(dpe),
        .fence_i(fi),.fence_d(fd),.maintenance_busy(maintenance_busy),
        .event_icache_refill(event_i),.event_dcache_refill(event_d),.event_dcache_writeback(event_w),
        .instr_req_o(instr_req_o),.instr_gnt_i(instr_gnt_i),.instr_addr_o(instr_addr_o),
        .instr_io_o(instr_io_o),.instr_rvalid_i(instr_rvalid_i),.instr_rready_o(instr_rready_o),
        .instr_rdata_i(instr_rdata_i),.instr_err_i(instr_err_i),
        .data_rd_req_o(data_rd_req_o),.data_rd_gnt_i(data_rd_gnt_i),
        .data_rd_id_o(data_rd_id_o),.data_rd_addr_o(data_rd_addr_o),
        .data_rd_rvalid_i(data_rd_rvalid_i),.data_rd_rready_o(data_rd_rready_o),
        .data_rd_rid_i(data_rd_rid_i),.data_rd_rdata_i(data_rd_rdata_i),.data_rd_err_i(data_rd_err_i),
        .data_wr_req_o(data_wr_req_o),.data_wr_gnt_i(data_wr_gnt_i),
        .data_wr_last_o(data_wr_last_o),.data_wr_addr_o(data_wr_addr_o),
        .data_wr_data_o(data_wr_data_o),.data_wr_id_o(data_wr_id_o),
        .data_wr_bvalid_i(data_wr_bvalid_i),.data_wr_berr_i(data_wr_berr_i),.data_wr_bid_i(data_wr_bid_i),
        .periph_req_o(periph_req_o),.periph_gnt_i(periph_gnt_i),.periph_we_o(periph_we_o),
        .periph_addr_o(periph_addr_o),.periph_wdata_o(periph_wdata_o),
        .periph_be_o(periph_be_o),.periph_size_o(periph_size_o),
        .periph_rvalid_i(periph_rvalid_i),.periph_err_i(periph_err_i),.periph_rdata_i(periph_rdata_i)
    );
 logic [1:0] lv,lw,lr,lsv,lsr;
 logic [1:0][31:0] la;
 logic [1:0][127:0] ld;
 logic [1:0][15:0] lm;
 logic [1:0][3:0] lt;
 logic pv,pw,pr,psv,psr,pactive,line_fault,periph_fault;
 logic [31:0] pa;logic [127:0] pd;logic [15:0] pm;logic [3:0] pt;
 rv32_game_line_memory #(.ITCM_INIT_FILE(ITCM_INIT_FILE),.DTCM_INIT_FILE(DTCM_INIT_FILE),.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) backing(
  .clk,.rst,
  .i_req(instr_req_o),.i_gnt(instr_gnt_i),.i_addr(instr_addr_o),.i_valid(instr_rvalid_i),.i_ready(instr_rready_o),.i_data(instr_rdata_i),.i_error(instr_err_i),
  .d_req(data_rd_req_o),.d_gnt(data_rd_gnt_i),.d_addr(data_rd_addr_o),.d_id(data_rd_id_o),
  .d_valid(data_rd_rvalid_i),.d_ready(data_rd_rready_o),.d_data(data_rd_rdata_i),.d_error(data_rd_err_i),.d_rid(data_rd_rid_i),
  .w_req(data_wr_req_o),.w_gnt(data_wr_gnt_i),.w_addr(data_wr_addr_o),.w_data(data_wr_data_o),.w_last(data_wr_last_o),.w_id(data_wr_id_o),
  .b_valid(data_wr_bvalid_i),.b_error(data_wr_berr_i),.b_id(data_wr_bid_i),.fault(line_fault),
  .mem_req_valid(lv),.mem_req_write(lw),.mem_req_ready(lr),.mem_req_addr(la),.mem_req_wdata(ld),.mem_req_wstrb(lm),.mem_req_tag(lt),
  .mem_rsp_valid(lsv),.mem_rsp_write(cache_mem_rsp_write),.mem_rsp_error(cache_mem_rsp_error),
  .mem_rsp_ready(lsr),.mem_rsp_rdata(cache_mem_rsp_rdata),.mem_rsp_tag(cache_mem_rsp_tag));
 rv32_game_periph #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) periph(
  .clk,.rst,.req(periph_req_o),.gnt(periph_gnt_i),.write(periph_we_o),.addr(periph_addr_o),.wdata(periph_wdata_o),.be(periph_be_o),
  .rvalid(periph_rvalid_i),.error(periph_err_i),.rdata(periph_rdata_i),
  .system_req_valid,.system_req_ready,.system_req_addr,.system_req_write,.system_req_wdata,.system_req_wstrb,
  .system_rsp_valid,.system_rsp_ready,.system_rsp_rdata,.system_rsp_error,
  .mem_active(pactive),.mem_req_valid(pv),.mem_req_ready(pr),.mem_req_write(pw),.mem_req_addr(pa),.mem_req_wdata(pd),.mem_req_wstrb(pm),.mem_req_tag(pt),
  .mem_rsp_valid(psv),.mem_rsp_ready(psr),.mem_rsp_write(cache_mem_rsp_write[1]),.mem_rsp_rdata(cache_mem_rsp_rdata[1]),
  .mem_rsp_tag(cache_mem_rsp_tag[1]),.mem_rsp_error(cache_mem_rsp_error[1]),.fault(periph_fault));
 // The blocking RV32 D-cache serializes cache fills/writebacks and IO commands.
 // Keep the uncached owner selected until its DDR response is consumed.
 assign cache_mem_req_valid[0]=lv[0];assign cache_mem_req_write[0]=lw[0];
 assign cache_mem_req_addr[0]=la[0];assign cache_mem_req_wdata[0]=ld[0];
 assign cache_mem_req_wstrb[0]=lm[0];assign cache_mem_req_tag[0]=lt[0];
 assign lr[0]=cache_mem_req_ready[0];assign lsv[0]=cache_mem_rsp_valid[0];
 assign cache_mem_rsp_ready[0]=lsr[0];
 assign cache_mem_req_valid[1]=pactive?pv:lv[1];assign cache_mem_req_write[1]=pactive?pw:lw[1];
 assign cache_mem_req_addr[1]=pactive?pa:la[1];assign cache_mem_req_wdata[1]=pactive?pd:ld[1];
 assign cache_mem_req_wstrb[1]=pactive?pm:lm[1];assign cache_mem_req_tag[1]=pactive?pt:lt[1];
 assign lr[1]=cache_mem_req_ready[1]&&!pactive;assign pr=cache_mem_req_ready[1]&&pactive;
 assign lsv[1]=cache_mem_rsp_valid[1]&&!pactive;assign psv=cache_mem_rsp_valid[1]&&pactive;
 assign cache_mem_rsp_ready[1]=pactive?psr:lsr[1];
 assign cache_protocol_fault=line_fault|periph_fault;
endmodule
