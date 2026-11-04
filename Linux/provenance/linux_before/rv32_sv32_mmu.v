// RV32 Sv32 translator, original implementation, 2026.
// Svade: missing A/D raises a page fault; this block NEVER writes page tables.
// PTW MUST be routed through a coherent physical-memory port (including PMP/PMA).
// One request in flight. flush kills the request; an accepted PTW read is drained.
// Full SFENCE.VMA overflush is intentionally used, including global entries.
module rv32_sv32_mmu #(parameter TLB_ENTRIES=8)(
 input clk, reset, flush,
 input req_valid, output req_ready,
 input [31:0] req_vaddr, req_satp,
 input [1:0] req_access, req_priv, // access: 0 fetch, 1 load, 2 store/AMO
 input req_mprv, input [1:0] req_mpp, input req_sum, req_mxr,
 output reg rsp_valid, input rsp_ready,
 output reg [33:0] rsp_paddr,
 output reg rsp_fault, output reg [4:0] rsp_cause,
 output reg [31:0] rsp_tval,
 output ptw_req_valid, input ptw_req_ready, output [33:0] ptw_req_addr,
 input ptw_rsp_valid, output ptw_rsp_ready,
 input [31:0] ptw_rsp_data, input ptw_rsp_error,
 output busy
);
 localparam IDLE=3'd0, LOOKUP=3'd1, READ_REQ=3'd2, READ_WAIT=3'd3, DRAIN=3'd4;
 reg [2:0] state;
 reg [31:0] va;
 reg [30:0] satp;
 reg [1:0] access_kind, privilege;
 reg sum_bit, mxr_bit, level, global_path;
 reg [33:0] pte_addr;
 reg tlb_valid[0:TLB_ENTRIES-1];
 reg [19:0] tlb_vpn[0:TLB_ENTRIES-1];
 reg [8:0] tlb_asid[0:TLB_ENTRIES-1];
 reg [31:0] tlb_pte[0:TLB_ENTRIES-1];
 reg tlb_superpage[0:TLB_ENTRIES-1], tlb_global[0:TLB_ENTRIES-1];
 integer replacement, j;
 reg hit_found;
 reg [31:0] hit_pte;
 reg hit_level;
 wire [1:0] effective_priv = (req_priv==2'd3 && req_mprv && req_access!=0) ? req_mpp : req_priv;
 assign req_ready = state==IDLE && !rsp_valid && !flush && !reset;
 assign ptw_req_valid = state==READ_REQ && !flush && !reset;
 assign ptw_req_addr = pte_addr;
 assign ptw_rsp_ready = (state==READ_WAIT || state==DRAIN) && !reset;
 assign busy = state!=IDLE || rsp_valid;
 // Reserved nonleaf U/A/D bits must be zero. G is inherited by descendants.
 function permission_ok;
 /* verilator lint_off UNUSEDSIGNAL */
 input [7:0] pte;
 /* verilator lint_on UNUSEDSIGNAL */
 input [1:0] acc, priv;
 input sum_v,mxr_v;
 begin
 permission_ok = pte[0] && !(pte[2]&&!pte[1]) && pte[6] && (acc!=2 || pte[7]);
 if(priv==0 && !pte[4]) permission_ok=0;
 if(priv==1 && pte[4] && (acc==0 || !sum_v)) permission_ok=0;
 if(acc==0 && !pte[3]) permission_ok=0;
 if(acc==1 && !(pte[1] || (mxr_v && pte[3]))) permission_ok=0;
 if(acc==2 && !pte[2]) permission_ok=0;
 if(acc==3 || priv==2) permission_ok=0;
 end endfunction
 function [4:0] page_cause;
 input [1:0] acc;
 begin case(acc) 0:page_cause=12; 1:page_cause=13; default:page_cause=15; endcase end
 endfunction
 function [4:0] access_cause;
 input [1:0] acc;
 begin case(acc) 0:access_cause=1; 1:access_cause=5; default:access_cause=7; endcase end
 endfunction
 function [33:0] translated_pa;
 /* verilator lint_off UNUSEDSIGNAL */
 input [31:0] pte, addr;
 /* verilator lint_on UNUSEDSIGNAL */
 input superpage;
 begin translated_pa = superpage ? {pte[31:20],addr[21:0]} : {pte[31:10],addr[11:0]}; end
 endfunction
 always @* begin
 hit_found=0; hit_pte=0; hit_level=0;
 for(integer k=0;k<TLB_ENTRIES;k=k+1) begin
 if(tlb_valid[k] && (tlb_global[k] || tlb_asid[k]==satp[30:22]) &&
 tlb_vpn[k][19:10]==va[31:22] && (tlb_superpage[k] || tlb_vpn[k][9:0]==va[21:12])) begin
 hit_found=1;hit_pte=tlb_pte[k];hit_level=tlb_superpage[k];
 end end
 end
 always @(posedge clk) begin
 if(reset) begin
 state<=IDLE; rsp_valid<=0;rsp_paddr<=0;rsp_fault<=0;rsp_cause<=0;rsp_tval<=0;
 va<=0;satp<=0;access_kind<=0;privilege<=3;sum_bit<=0;mxr_bit<=0;
 level<=0;global_path<=0;pte_addr<=0;replacement<=0;
 for(j=0;j<TLB_ENTRIES;j=j+1) begin tlb_valid[j]<=0;tlb_vpn[j]<=0;tlb_asid[j]<=0;tlb_pte[j]<=0;tlb_superpage[j]<=0;tlb_global[j]<=0;end
 end else if(flush) begin
 for(j=0;j<TLB_ENTRIES;j=j+1) tlb_valid[j]<=0;
 rsp_valid<=0;
 if((state==READ_WAIT || state==DRAIN) && !ptw_rsp_valid) state<=DRAIN;
 else state<=IDLE;
 end else begin
 if(rsp_valid && rsp_ready) rsp_valid<=0;
 case(state)
 IDLE: if(req_valid && req_ready) begin
 va<=req_vaddr;satp<=req_satp[30:0];access_kind<=req_access;privilege<=effective_priv;
 sum_bit<=req_sum;mxr_bit<=req_mxr;
 rsp_fault<=0;rsp_cause<=0;rsp_tval<=req_vaddr;rsp_paddr<=0;
 if(!req_satp[31] || effective_priv==3) begin rsp_valid<=1;rsp_paddr<={2'b0,req_vaddr};end
 else state<=LOOKUP;
 end
 LOOKUP: begin
 if(hit_found) begin
 rsp_valid<=1;state<=IDLE;
 rsp_fault<=!permission_ok(hit_pte[7:0],access_kind,privilege,sum_bit,mxr_bit);
 rsp_cause<=permission_ok(hit_pte[7:0],access_kind,privilege,sum_bit,mxr_bit) ? 0 : page_cause(access_kind);
 rsp_paddr<=translated_pa(hit_pte,va,hit_level);
 end else begin
 pte_addr<={satp[21:0],12'b0}+{22'b0,va[31:22],2'b0};
 level<=1;global_path<=0;state<=READ_REQ;
 end end
 READ_REQ: if(ptw_req_ready) state<=READ_WAIT;
 READ_WAIT: if(ptw_rsp_valid) begin
 if(ptw_rsp_error) begin
 rsp_valid<=1;rsp_fault<=1;rsp_cause<=access_cause(access_kind);state<=IDLE;
 end else if(!ptw_rsp_data[0] || (!ptw_rsp_data[1] && ptw_rsp_data[2])) begin
 rsp_valid<=1;rsp_fault<=1;rsp_cause<=page_cause(access_kind);state<=IDLE;
 end else if(ptw_rsp_data[1] || ptw_rsp_data[3]) begin
 rsp_valid<=1;state<=IDLE;
 if(!permission_ok(ptw_rsp_data[7:0],access_kind,privilege,sum_bit,mxr_bit) || (level && ptw_rsp_data[19:10]!=0)) begin
 rsp_fault<=1;rsp_cause<=page_cause(access_kind);
 end else begin
 rsp_paddr<=translated_pa(ptw_rsp_data,va,level);rsp_fault<=0;rsp_cause<=0;
 tlb_valid[replacement]<=1;tlb_vpn[replacement]<=va[31:12];tlb_asid[replacement]<=satp[30:22];
 tlb_pte[replacement]<=ptw_rsp_data;tlb_superpage[replacement]<=level;
 tlb_global[replacement]<=global_path || ptw_rsp_data[5];
 if(replacement==TLB_ENTRIES-1)replacement<=0;else replacement<=replacement+1;
 end
 end else if(!level || ptw_rsp_data[7:6]!=0 || ptw_rsp_data[4]) begin
 rsp_valid<=1;rsp_fault<=1;rsp_cause<=page_cause(access_kind);state<=IDLE;
 end else begin
 pte_addr<={ptw_rsp_data[31:10],12'b0}+{22'b0,va[21:12],2'b0};
 level<=0;global_path<=global_path||ptw_rsp_data[5];state<=READ_REQ;
 end
 end
 DRAIN: if(ptw_rsp_valid) state<=IDLE;
 default: state<=IDLE;
 endcase
 end
 end
endmodule
