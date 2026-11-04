// Board system with UART boot loader muxed onto the SRAM writeback channel.
// While the loader is active the CPU is held in reset and the loader owns the
// write port; afterwards the CPU runs exactly as in rv32_coremark_system.
module rv32_coremark_system_boot #(
    parameter INIT_FILE="firmware.hex",
    parameter BOOT_TIMEOUT_CYCLES=32'd3400000000,
    parameter UART_DIV=1128, // 130 MHz / 115200 rounded.
    parameter LOAD_BYPASS=1,
    parameter BIMODAL_INDEX_BITS=9,
    parameter GSHARE_INDEX_BITS=12,
    parameter HISTORY_BITS=12
)(
    input clk, reset,
    input uart_rx,
    output uart_tx,
    output reg done, output reg [31:0] exit_code,
    output reg fault,
    output [63:0] elapsed_clocks,
    output reg debug_uart_valid, output reg [7:0] debug_uart_data,
    output debug_timer_valid, output [31:0] debug_timer_value,
    output [1:0] debug_retire,
    output debug_i_fill, debug_d_fill, debug_writeback,
    output debug_bus_read_error,
    output [63:0] debug_retired_start, debug_retired_stop,
    output loading
);
    wire ir,ig,iv,irdy,ie,iio; wire [31:0] ia; wire [63:0] idata;
    wire dr,dg,did,dv,drdy,de,drid; wire [31:0] da; wire [63:0] ddata;
    wire wr,wg,wl,wid,bv,be,bid; wire [31:0] wa; wire [63:0] wd;
    wire pr,pg,pwe,pv,pe; wire [31:0] pa,pwd,prd;
    wire [3:0] pbe; wire [1:0] psz;
    wire trap_event;
    reg [63:0] clocks;
    reg p_valid,p_error; reg [31:0] p_data;
    reg [9:0] tx_shift; reg [3:0] tx_bits;
    reg [10:0] tx_counter;
    wire uart_store=pwe && (pa==32'h30000000);
    wire p_fire=pr && pg;

    // ---- loader ----
    wire ld_req, ld_last, ld_busy_tx, ld_tx;
    wire [31:0] ld_addr; wire [63:0] ld_data;
    wire ld_dreq; wire [31:0] ld_daddr;
    uart_loader #(.UART_DIV(UART_DIV),.AUTOBOOT_CYCLES(BOOT_TIMEOUT_CYCLES)) loader(
        .clk(clk),.reset(reset),.uart_rx(uart_rx),
        .loading(loading),.loaded_bytes(),
        .w_req(ld_req),.w_gnt(wg),.w_addr(ld_addr),.w_data(ld_data),
        .w_last(ld_last),.w_id(),
        .b_valid(bv),.b_error(be),
        .tx(ld_tx),.tx_busy(ld_busy_tx),
        .d_req(ld_dreq),.d_gnt(dg),.d_addr(ld_daddr),
        .d_valid(dv),.d_data(ddata),.d_error(de));

    // CPU is held in reset while the loader owns the memory.
    wire cpu_reset=reset || loading;

    // write channel mux: loader while loading, CPU otherwise
    wire mem_wr = loading ? ld_req  : wr;
    wire [31:0] mem_wa = loading ? ld_addr : wa;
    wire [63:0] mem_wd = loading ? ld_data : wd;
    wire mem_wl = loading ? ld_last : wl;
    wire mem_wid = loading ? 1'b0 : wid;
    // read channel mux for verify: loader while loading, CPU otherwise
    wire mem_dr = loading ? ld_dreq : dr;
    wire [31:0] mem_da = loading ? ld_daddr : da;

    assign pg=!cpu_reset && !p_valid && (!uart_store || tx_bits==0);
    assign pv=p_valid; assign pe=p_error; assign prd=p_data;
    assign elapsed_clocks=clocks;
    assign debug_timer_valid=p_fire && !pwe && pa==32'h30000010;
    assign debug_timer_value=clocks[31:0];
    assign debug_i_fill=ir && ig;
    assign debug_d_fill=dr && dg;
    assign debug_writeback=wr && wg && wl;
    assign debug_bus_read_error=(iv && ie) || (dv && de);

    reg cpu_uart_tx;
    assign uart_tx=loading ? ld_tx : cpu_uart_tx;
    // Retired-instruction snapshots use the SAME accepted timer reads as CoreMark.
    // trace_retire is registered; include its pending increment on this edge.
    reg [63:0] retired_total, retired_start, retired_stop;
    reg [31:0] timer_reads;
    wire [1:0] retire_inc={1'b0,debug_retire[0]}+{1'b0,debug_retire[1]};
    wire [63:0] retired_at_edge=retired_total+retire_inc;
    assign debug_retired_start=retired_start;
    assign debug_retired_stop=retired_stop;
    always @(posedge clk) begin
        if(cpu_reset) begin
            retired_total<=0; retired_start<=0; retired_stop<=0; timer_reads<=0;
        end else begin
            retired_total<=retired_at_edge;
            if(debug_timer_valid) begin
                if(timer_reads==0) retired_start<=retired_at_edge;
                if(timer_reads==1) retired_stop<=retired_at_edge;
                timer_reads<=timer_reads+1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if(cpu_reset) begin
            clocks<=0; p_valid<=0; p_error<=0; p_data<=0;
            done<=0; exit_code<=0; fault<=0;
            tx_shift<=10'h3ff; tx_bits<=0; tx_counter<=0; cpu_uart_tx<=1;
            debug_uart_valid<=0; debug_uart_data<=0;
        end else begin
            clocks<=clocks+1'b1;
            p_valid<=0; p_error<=0; debug_uart_valid<=0;
            if(trap_event || (bv && be)) fault<=1;
            if(tx_bits!=0) begin
                if(tx_counter==0) begin
                    cpu_uart_tx<=tx_shift[0]; tx_shift<={1'b1,tx_shift[9:1]};
                    tx_counter<=UART_DIV-1; tx_bits<=tx_bits-1'b1;
                end else tx_counter<=tx_counter-1'b1;
            end else cpu_uart_tx<=1;
            if(p_fire) begin
                p_valid<=1; p_data<=0;
                if(pwe) begin
                    case(pa)
                        32'h30000000: if(pbe[0]) begin
                            cpu_uart_tx<=0; tx_shift<={2'b11,pwd[7:0]};
                            tx_bits<=10; tx_counter<=UART_DIV-1;
                            debug_uart_valid<=1; debug_uart_data<=pwd[7:0];
                        end
                        32'h30000004: begin done<=1; exit_code<=pwd; end
                        default: begin p_error<=1; fault<=1; end
                    endcase
                end else begin
                    case(pa)
                        32'h30000010: p_data<=clocks[31:0];
                        32'h30000014: p_data<=clocks[63:32];
                        32'h30000018: p_data<={31'b0,tx_bits==0};
                        32'h30000020: p_data<=retired_start[31:0];
                        32'h30000024: p_data<=retired_start[63:32];
                        32'h30000028: p_data<=retired_stop[31:0];
                        32'h3000002c: p_data<=retired_stop[63:32];
                        32'h30000030: p_data<=timer_reads;
                        32'h30000034: p_data<=32'h52353231; // RV321 counter ABI
                        default: begin p_error<=1; fault<=1; end
                    endcase
                end
            end
        end
    end
    // The memory itself must stay out of reset so the loader can write it;
    // the CPU is held in reset and therefore issues no requests meanwhile.
    rv32_board_memory #(.INIT_FILE(INIT_FILE)) memory(
        .clk(clk),.reset(reset),
        .i_req(ir),.i_gnt(ig),.i_addr(ia),.i_valid(iv),.i_ready(irdy),.i_data(idata),.i_error(ie),
        .d_req(mem_dr),.d_gnt(dg),.d_addr(mem_da),.d_id(did),.d_valid(dv),.d_ready(loading ? 1'b1 : drdy),
        .d_data(ddata),.d_error(de),.d_rid(drid),
        .w_req(mem_wr),.w_gnt(wg),.w_addr(mem_wa),.w_data(mem_wd),.w_last(mem_wl),.w_id(mem_wid),
        .b_valid(bv),.b_error(be),.b_id(bid)
    );
    rv32_ooo_soc_top #(.RESET_VECTOR(32'h10000000),.ENABLE_PAIRING(1),.LOAD_ORDER_ISSUE_LOOKAHEAD(1),.MEMORY_CREDITS(3),.FETCH_CREDITS(2),.REGISTER_INSTRUCTION_REQUEST(0),.REGISTER_RESPONSES(0),
        .ENABLE_ORDERED_STORE_PREP(1),.ENABLE_STORE_HEAD_LOOKAHEAD(1),.ENABLE_STORE_ISSUE_LOOKAHEAD(1),
        .ENABLE_REDIRECT_FETCH(1),.ENABLE_CURRENT_INTEGER_PAIR(1),.ENABLE_DISPATCH_BYPASS(1),.DISPATCH_BYPASS_UNMAPPED_ONLY(1),.ENABLE_CONTROL_DISPATCH(1),.ENABLE_COMMITTED_RAS(1),.RAS_DEPTH(16),.BIMODAL_INDEX_BITS(BIMODAL_INDEX_BITS),.GSHARE_INDEX_BITS(GSHARE_INDEX_BITS),.HISTORY_BITS(HISTORY_BITS),.BANKED_ISSUE(1),.DECOUPLED_ALLOCATION_PAYLOAD(1),
        .CARRIED_COMPLETION_WRITES(1),.FAST_WAKEUP(1),.ENABLE_SAME_CYCLE_REUSE(0),.LOAD_BYPASS(LOAD_BYPASS),
        .ENABLE_FAST_ICROSS(1),
        .ENABLE_DATA_RAM_GUARD(1),.DATA_RAM_BASE(32'h10000000),.DATA_RAM_LIMIT(32'h1000ffff),
        .I_INDEX_BITS(7),.I_WAYS(2),.D_INDEX_BITS(6),.D_WAYS(2)) cpu(
        .clk(clk),.reset(cpu_reset),
        .instr_req_o(ir),.instr_gnt_i(ig),.instr_addr_o(ia),.instr_io_o(iio),
        .instr_rvalid_i(iv),.instr_rready_o(irdy),.instr_rdata_i(idata),.instr_err_i(ie),
        .irq_timer_i(1'b0),.irq_software_i(1'b0),.irq_external_i(1'b0),.mtime_i(clocks),
        .periph_req_o(pr),.periph_gnt_i(pg),.periph_we_o(pwe),.periph_addr_o(pa),
        .periph_wdata_o(pwd),.periph_be_o(pbe),.periph_size_o(psz),
        .periph_rvalid_i(pv),.periph_err_i(pe),.periph_rdata_i(prd),
        .data_rd_req_o(dr),.data_rd_gnt_i(dg),.data_rd_id_o(did),.data_rd_addr_o(da),
        .data_rd_rvalid_i(dv),.data_rd_rready_o(drdy),.data_rd_rid_i(drid),
        .data_rd_rdata_i(ddata),.data_rd_err_i(de),
        .data_wr_req_o(wr),.data_wr_gnt_i(wg),.data_wr_last_o(wl),.data_wr_addr_o(wa),
        .data_wr_data_o(wd),.data_wr_id_o(wid),.data_wr_bvalid_i(bv),.data_wr_berr_i(be),.data_wr_bid_i(bid),
        .trace_retire_mask_o(debug_retire),.trace_reschedule_trap_o(trap_event)
    );
endmodule
