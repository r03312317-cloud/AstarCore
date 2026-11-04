// Virtual core to physical cache bridge. Original RV32 implementation.
// Page walks share the physical D-cache port: dirty cached PTEs are visible.
module rv32_linux_memory_bridge #(
 parameter [31:0] RAM_BASE=32'h80000000, RAM_LIMIT=32'h84000000
)(
 input clk,reset,sfence,reservation_kill,
 input [1:0] privilege_mode,mmu_mpp,
 input [31:0] mmu_satp,input mmu_sum,mmu_mxr,mmu_mprv,
 input c_i_valid,output c_i_ready,input [31:0] c_i_addr,
 output reg c_i_rsp_valid,input c_i_rsp_ready,output reg [63:0] c_i_rsp_data,
 output reg [1:0] c_i_rsp_error,c_i_rsp_pagefault,
 input c_d_valid,output c_d_ready,input [31:0] c_d_addr,c_d_wdata,
 input c_d_write,input [3:0] c_d_wstrb,input [1:0] c_d_size,
 input c_d_atomic,input [4:0] c_d_amo,
 output reg c_d_rsp_valid,input c_d_rsp_ready,output reg [31:0] c_d_rsp_data,
 output reg c_d_rsp_error,c_d_rsp_pagefault,
 output p_i_valid,input p_i_ready,output [31:0] p_i_addr,
 input p_i_rsp_valid,output p_i_rsp_ready,input [63:0] p_i_rsp_data,input [1:0] p_i_rsp_error,
 output p_d_valid,input p_d_ready,output [31:0] p_d_addr,p_d_wdata,
 output p_d_write,output [3:0] p_d_wstrb,output [1:0] p_d_size,
 input p_d_rsp_valid,output p_d_rsp_ready,input [31:0] p_d_rsp_data,input p_d_rsp_error,
 output busy,flush_busy
);
 localparam IDLE=0, TRANSLATE=1, TRANSLATE_WAIT=2, PHYSICAL=3, PHYSICAL_WAIT=4;
 reg [2:0] is,ds;
 reg flush_pending;
 reg [31:0] iva,ipa,dva,dpa,ddata;
 reg iword,dwrite,datomic;
 reg [3:0] dstrb;reg [1:0] dsize;reg [4:0] damo;
 reg [31:0] isatp,dsatp;reg [1:0] ipriv,dpriv,impp,dmpp;
 reg isum,imxr,imprv,dsum,dmxr,dmprv;
 wire im_ready,im_valid,im_fault,im_busy,dm_ready,dm_valid,dm_fault,dm_busy;
 wire [33:0] im_pa,dm_pa;
 wire [4:0] im_cause,dm_cause;
 wire [31:0] im_tval,dm_tval;
 wire iw_req,iw_ready,iw_rsp,iw_rsp_ready,iw_error;
 wire dw_req,dw_ready,dw_rsp,dw_rsp_ready,dw_error;
 wire [33:0] iw_addr,dw_addr;
 wire [31:0] iw_data,dw_data;
 wire am_req_ready,am_rsp_valid,am_rsp_error,am_lock;
 wire [31:0] am_rsp_data;
 wire am_valid,am_ready,am_write,am_rsp_in_valid,am_rsp_in_ready,am_rsp_in_error;
 wire [31:0] am_addr,am_wdata,am_rsp_in_data;
 wire [3:0] am_wstrb;wire [1:0] am_size;
 reg arb_busy,arb_error;
 reg [1:0] arb_owner;
 reg [1:0] selection;
 wire all_idle=(is==IDLE)&&(ds==IDLE)&&!c_i_rsp_valid&&!c_d_rsp_valid&&!arb_busy&&!im_busy&&!dm_busy&&!am_lock&&!am_rsp_valid;
 wire flush_now=flush_pending&&all_idle;
 assign flush_busy=flush_pending||sfence;
 assign busy=!all_idle||flush_busy;
 assign c_i_ready=!reset&&!flush_busy&&is==IDLE&&!c_i_rsp_valid;
 assign c_d_ready=!reset&&!flush_busy&&ds==IDLE&&!c_d_rsp_valid;
 assign p_i_valid=!reset&&is==PHYSICAL;
 assign p_i_addr=ipa;
 assign p_i_rsp_ready=is==PHYSICAL_WAIT;
 wire [1:0] data_access=datomic ? (damo==2 ? 2'd1 : 2'd2) : (dwrite ? 2'd2 : 2'd1);
 rv32_sv32_mmu itlb(
 .clk(clk),.reset(reset),.flush(flush_now),.req_valid(is==TRANSLATE),.req_ready(im_ready),
 .req_vaddr(iva),.req_satp(isatp),.req_access(2'd0),.req_priv(ipriv),.req_mprv(imprv),.req_mpp(impp),.req_sum(isum),.req_mxr(imxr),
 .rsp_valid(im_valid),.rsp_ready(is==TRANSLATE_WAIT),.rsp_paddr(im_pa),.rsp_fault(im_fault),.rsp_cause(im_cause),.rsp_tval(im_tval),
 .ptw_req_valid(iw_req),.ptw_req_ready(iw_ready),.ptw_req_addr(iw_addr),.ptw_rsp_valid(iw_rsp),.ptw_rsp_ready(iw_rsp_ready),.ptw_rsp_data(iw_data),.ptw_rsp_error(iw_error),.busy(im_busy));
 rv32_sv32_mmu dtlb(
 .clk(clk),.reset(reset),.flush(flush_now),.req_valid(ds==TRANSLATE),.req_ready(dm_ready),
 .req_vaddr(dva),.req_satp(dsatp),.req_access(data_access),.req_priv(dpriv),.req_mprv(dmprv),.req_mpp(dmpp),.req_sum(dsum),.req_mxr(dmxr),
 .rsp_valid(dm_valid),.rsp_ready(ds==TRANSLATE_WAIT),.rsp_paddr(dm_pa),.rsp_fault(dm_fault),.rsp_cause(dm_cause),.rsp_tval(dm_tval),
 .ptw_req_valid(dw_req),.ptw_req_ready(dw_ready),.ptw_req_addr(dw_addr),.ptw_rsp_valid(dw_rsp),.ptw_rsp_ready(dw_rsp_ready),.ptw_rsp_data(dw_data),.ptw_rsp_error(dw_error),.busy(dm_busy));
 rv32_atomic_memory atomic_unit(
 .clk(clk),.reset(reset),.reservation_kill(reservation_kill||flush_now),
 .req_valid(ds==PHYSICAL),.req_ready(am_req_ready),.req_addr(dpa),.req_wdata(ddata),.req_write(dwrite),.req_wstrb(dstrb),.req_size(dsize),.req_atomic(datomic),.req_amo(damo),
 .rsp_valid(am_rsp_valid),.rsp_ready(ds==PHYSICAL_WAIT),.rsp_data(am_rsp_data),.rsp_error(am_rsp_error),
 .mem_valid(am_valid),.mem_ready(am_ready),.mem_addr(am_addr),.mem_wdata(am_wdata),.mem_write(am_write),.mem_wstrb(am_wstrb),.mem_size(am_size),
 .mem_rsp_valid(am_rsp_in_valid),.mem_rsp_ready(am_rsp_in_ready),.mem_rsp_data(am_rsp_in_data),.mem_rsp_error(am_rsp_in_error),.lock(am_lock));
 // One owner through response retirement; atomic owner excludes walks during RMW.
 always @* begin
 selection=0;
 if(!arb_busy)begin
 if(am_valid)selection=3;
 else if(!am_lock&&dw_req)selection=2;
 else if(!am_lock&&iw_req)selection=1;
 end end
 // Page tables are RAM-only: a malformed SATP/PTE must never read MMIO.
 wire iw_bad=(iw_addr < {2'b0,RAM_BASE}) || (iw_addr > ({2'b0,RAM_LIMIT}-34'd4));
 wire dw_bad=(dw_addr < {2'b0,RAM_BASE}) || (dw_addr > ({2'b0,RAM_LIMIT}-34'd4));
 wire selected_high=(selection==1&&iw_bad)||(selection==2&&dw_bad);
 assign p_d_valid=!reset&&selection!=0&&!selected_high;
 assign p_d_addr=selection==3?am_addr:(selection==2?dw_addr[31:0]:iw_addr[31:0]);
 assign p_d_wdata=selection==3?am_wdata:0;
 assign p_d_write=selection==3&&am_write;
 assign p_d_wstrb=selection==3?am_wstrb:4'h0;
 assign p_d_size=selection==3?am_size:2'd2;
 assign iw_ready=!reset&&selection==1&&(selected_high||p_d_ready);
 assign dw_ready=!reset&&selection==2&&(selected_high||p_d_ready);
 assign am_ready=!reset&&selection==3&&p_d_ready;
 wire selected_rsp_ready=arb_owner==1?iw_rsp_ready:(arb_owner==2?dw_rsp_ready:am_rsp_in_ready);
 assign p_d_rsp_ready=arb_busy&&!arb_error&&selected_rsp_ready;
 assign iw_rsp=arb_busy&&arb_owner==1&&(arb_error||p_d_rsp_valid);
 assign dw_rsp=arb_busy&&arb_owner==2&&(arb_error||p_d_rsp_valid);
 assign am_rsp_in_valid=arb_busy&&arb_owner==3&&(arb_error||p_d_rsp_valid);
 assign iw_data=p_d_rsp_data;assign dw_data=p_d_rsp_data;assign am_rsp_in_data=p_d_rsp_data;
 assign iw_error=arb_error||p_d_rsp_error;assign dw_error=arb_error||p_d_rsp_error;assign am_rsp_in_error=arb_error||p_d_rsp_error;
 always @(posedge clk)begin
 if(reset)begin
 is<=IDLE;ds<=IDLE;flush_pending<=0;c_i_rsp_valid<=0;c_i_rsp_data<=0;c_i_rsp_error<=0;c_i_rsp_pagefault<=0;
 c_d_rsp_valid<=0;c_d_rsp_data<=0;c_d_rsp_error<=0;c_d_rsp_pagefault<=0;
 arb_busy<=0;arb_owner<=0;arb_error<=0;
 iva<=0;ipa<=0;dva<=0;dpa<=0;ddata<=0;iword<=0;dwrite<=0;datomic<=0;dstrb<=0;dsize<=0;damo<=0;
 isatp<=0;dsatp<=0;ipriv<=3;dpriv<=3;impp<=0;dmpp<=0;isum<=0;imxr<=0;imprv<=0;dsum<=0;dmxr<=0;dmprv<=0;
 end else begin
 if(sfence)flush_pending<=1;else if(flush_now)flush_pending<=0;
 if(c_i_rsp_valid&&c_i_rsp_ready)c_i_rsp_valid<=0;
 if(c_d_rsp_valid&&c_d_rsp_ready)c_d_rsp_valid<=0;
 if(!arb_busy&&selection!=0&&(selected_high||p_d_ready))begin arb_busy<=1;arb_owner<=selection;arb_error<=selected_high;end
 else if(arb_busy&&(arb_error||p_d_rsp_valid)&&selected_rsp_ready)begin arb_busy<=0;arb_error<=0;end
 case(is)
 IDLE:if(c_i_valid&&c_i_ready)begin
 iva<=c_i_addr;iword<=0;c_i_rsp_data<=0;c_i_rsp_error<=0;c_i_rsp_pagefault<=0;
 isatp<=mmu_satp;ipriv<=privilege_mode;impp<=mmu_mpp;isum<=mmu_sum;imxr<=mmu_mxr;imprv<=mmu_mprv;is<=TRANSLATE;
 end
 TRANSLATE:if(im_ready)is<=TRANSLATE_WAIT;
 TRANSLATE_WAIT:if(im_valid)begin
 if(im_fault|| |im_pa[33:32])begin
 c_i_rsp_error[iword]<=!im_fault||im_cause!=12;c_i_rsp_pagefault[iword]<=im_fault&&im_cause==12;
 if(iword)begin is<=IDLE;c_i_rsp_valid<=1;end
 else begin iword<=1;iva<=iva+4;is<=TRANSLATE;end
 end else begin ipa<=im_pa[31:0];is<=PHYSICAL;end
 end
 PHYSICAL:if(p_i_ready)is<=PHYSICAL_WAIT;
 PHYSICAL_WAIT:if(p_i_rsp_valid)begin
 if(iword)c_i_rsp_data[63:32]<=p_i_rsp_data[31:0];else c_i_rsp_data[31:0]<=p_i_rsp_data[31:0];
 c_i_rsp_error[iword]<=p_i_rsp_error[0];
 if(iword)begin is<=IDLE;c_i_rsp_valid<=1;end
 else begin iword<=1;iva<=iva+4;is<=TRANSLATE;end
 end
 default:is<=IDLE;
 endcase
 case(ds)
 IDLE:if(c_d_valid&&c_d_ready)begin
 dva<=c_d_addr;ddata<=c_d_wdata;dwrite<=c_d_write;dstrb<=c_d_wstrb;dsize<=c_d_size;datomic<=c_d_atomic;damo<=c_d_amo;
 dsatp<=mmu_satp;dpriv<=privilege_mode;dmpp<=mmu_mpp;dsum<=mmu_sum;dmxr<=mmu_mxr;dmprv<=mmu_mprv;
 c_d_rsp_error<=0;c_d_rsp_pagefault<=0;c_d_rsp_data<=0;ds<=TRANSLATE;
 end
 TRANSLATE:if(dm_ready)ds<=TRANSLATE_WAIT;
 TRANSLATE_WAIT:if(dm_valid)begin
 if(dm_fault|| |dm_pa[33:32] || (datomic&&(dm_pa[31:0]<RAM_BASE||dm_pa[31:0]>=RAM_LIMIT)))begin
 c_d_rsp_error<=!dm_fault||(dm_cause!=13&&dm_cause!=15);c_d_rsp_pagefault<=dm_fault&&(dm_cause==13||dm_cause==15);
 ds<=IDLE;c_d_rsp_valid<=1;
 end else begin dpa<=dm_pa[31:0];ds<=PHYSICAL;end
 end
 PHYSICAL:if(am_req_ready)ds<=PHYSICAL_WAIT;
 PHYSICAL_WAIT:if(am_rsp_valid)begin c_d_rsp_data<=am_rsp_data;c_d_rsp_error<=am_rsp_error;ds<=IDLE;c_d_rsp_valid<=1;end
 default:ds<=IDLE;
 endcase
 end end
endmodule
