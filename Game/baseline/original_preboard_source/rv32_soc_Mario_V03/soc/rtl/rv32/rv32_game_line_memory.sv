// Read ownership is retained for all eight 64-bit beats; write ownership
// survives the last data beat until the real backing-memory acknowledgement.
module rv32_game_line_memory #(
 parameter ITCM_INIT_FILE="",DTCM_INIT_FILE="",
 parameter logic [31:0] DDR_BASE=32'h80000000,
 parameter logic [32:0] DDR_BYTES=33'h010000000
)(
 input logic clk,rst,
 input logic i_req,output logic i_gnt,input logic [31:0] i_addr,
 output logic i_valid,input logic i_ready,output logic [63:0] i_data,output logic i_error,
 input logic d_req,output logic d_gnt,input logic [31:0] d_addr,input logic d_id,
 output logic d_valid,input logic d_ready,output logic [63:0] d_data,output logic d_error,d_rid,
 input logic w_req,output logic w_gnt,input logic [31:0] w_addr,
 input logic [63:0] w_data,input logic w_last,w_id,
 output logic b_valid,b_error,b_id,output logic fault,
 output logic [1:0] mem_req_valid,mem_req_write,input logic [1:0] mem_req_ready,
 output logic [1:0][31:0] mem_req_addr,output logic [1:0][127:0] mem_req_wdata,
 output logic [1:0][15:0] mem_req_wstrb,output logic [1:0][3:0] mem_req_tag,
 input logic [1:0] mem_rsp_valid,mem_rsp_write,mem_rsp_error,
 output logic [1:0] mem_rsp_ready,input logic [1:0][127:0] mem_rsp_rdata,
 input logic [1:0][3:0] mem_rsp_tag
);
 function automatic logic [1:0] destination(input logic [31:0] address);
  if(address[31:16]==16'h1000)destination=0;
  else if(address[31:16]==16'h2000)destination=1;
  else destination=2;
 endfunction
 logic i_owner;
 logic [1:0] d_owner,w_owner;
 logic w_active;
 wire i_select=i_addr[31:16]!=16'h1000;
 wire [1:0] d_select=destination(d_addr);
 wire [1:0] w_select=w_active?w_owner:destination(w_addr);
 logic [2:0] iv,ig,ir,ie,dv,dg,dr,de,di,wg,bv,be,bi;
 logic [2:0][63:0] id,dd;
 logic ifault,dfault;
 assign fault=ifault|dfault;
 assign i_gnt=i_select?ig[2]:ig[0];
 assign i_valid=i_owner?iv[2]:iv[0];
 assign i_data=i_owner?id[2]:id[0];
 assign i_error=i_owner?ie[2]:ie[0];
 assign ir={i_ready&&i_owner,1'b0,i_ready&&!i_owner};
 assign d_gnt=dg[d_select];assign d_valid=dv[d_owner];
 assign d_data=dd[d_owner];assign d_error=de[d_owner];assign d_rid=di[d_owner];
 assign w_gnt=wg[w_select];
 assign b_valid=bv[w_owner];assign b_error=be[w_owner];assign b_id=bi[w_owner];
 for(genvar n=0;n<3;n=n+1)begin:response_ready
  assign dr[n]=d_ready&&(d_owner==n);
 end
 always_ff @(posedge clk)begin
  if(rst)begin i_owner<=0;d_owner<=0;w_owner<=0;w_active<=0;end
  else begin
   if(i_req&&i_gnt)i_owner<=i_select;
   if(d_req&&d_gnt)d_owner<=d_select;
   if(w_req&&w_gnt&&!w_active)begin w_owner<=w_select;w_active<=1;end
   if(b_valid)w_active<=0;
  end
 end
 rv32_game_sram #(.INIT_FILE(ITCM_INIT_FILE),.BASE_PREFIX(16'h1000)) sram0(
  .clk,.reset(rst),.i_req(i_req&&!i_select),.i_gnt(ig[0]),.i_addr,
  .i_valid(iv[0]),.i_ready(ir[0]),.i_data(id[0]),.i_error(ie[0]),
  .d_req(d_req&&d_select==0),.d_gnt(dg[0]),.d_addr,.d_id,
  .d_valid(dv[0]),.d_ready(dr[0]),.d_data(dd[0]),.d_error(de[0]),.d_rid(di[0]),
  .w_req(w_req&&w_select==0),.w_gnt(wg[0]),.w_addr,.w_data,.w_last,.w_id,
  .b_valid(bv[0]),.b_error(be[0]),.b_id(bi[0]));
 rv32_game_sram #(.INIT_FILE(DTCM_INIT_FILE),.BASE_PREFIX(16'h2000)) sram1(
  .clk,.reset(rst),.i_req(1'b0),.i_gnt(ig[1]),.i_addr,
  .i_valid(iv[1]),.i_ready(ir[1]),.i_data(id[1]),.i_error(ie[1]),
  .d_req(d_req&&d_select==1),.d_gnt(dg[1]),.d_addr,.d_id,
  .d_valid(dv[1]),.d_ready(dr[1]),.d_data(dd[1]),.d_error(de[1]),.d_rid(di[1]),
  .w_req(w_req&&w_select==1),.w_gnt(wg[1]),.w_addr,.w_data,.w_last,.w_id,
  .b_valid(bv[1]),.b_error(be[1]),.b_id(bi[1]));
 rv32_line128_adapter #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) instruction_ddr(
  .clk,.rst,.rd_req(i_req&&i_select),.rd_gnt(ig[2]),.rd_addr(i_addr),.rd_id(1'b0),
  .rd_valid(iv[2]),.rd_ready(ir[2]),.rd_data(id[2]),.rd_error(ie[2]),.rd_rid(),
  .wr_req(1'b0),.wr_gnt(),.wr_addr(32'd0),.wr_data(64'd0),.wr_last(1'b0),.wr_id(1'b0),
  .b_valid(),.b_error(),.b_id(),.fault(ifault),
  .mem_req_valid(mem_req_valid[0]),.mem_req_ready(mem_req_ready[0]),.mem_req_write(mem_req_write[0]),
  .mem_req_addr(mem_req_addr[0]),.mem_req_wdata(mem_req_wdata[0]),.mem_req_wstrb(mem_req_wstrb[0]),.mem_req_tag(mem_req_tag[0]),
  .mem_rsp_valid(mem_rsp_valid[0]),.mem_rsp_ready(mem_rsp_ready[0]),.mem_rsp_write(mem_rsp_write[0]),
  .mem_rsp_rdata(mem_rsp_rdata[0]),.mem_rsp_tag(mem_rsp_tag[0]),.mem_rsp_error(mem_rsp_error[0]));
 rv32_line128_adapter #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) data_ddr(
  .clk,.rst,.rd_req(d_req&&d_select==2),.rd_gnt(dg[2]),.rd_addr(d_addr),.rd_id(d_id),
  .rd_valid(dv[2]),.rd_ready(dr[2]),.rd_data(dd[2]),.rd_error(de[2]),.rd_rid(di[2]),
  .wr_req(w_req&&w_select==2),.wr_gnt(wg[2]),.wr_addr(w_addr),.wr_data(w_data),.wr_last(w_last),.wr_id(w_id),
  .b_valid(bv[2]),.b_error(be[2]),.b_id(bi[2]),.fault(dfault),
  .mem_req_valid(mem_req_valid[1]),.mem_req_ready(mem_req_ready[1]),.mem_req_write(mem_req_write[1]),
  .mem_req_addr(mem_req_addr[1]),.mem_req_wdata(mem_req_wdata[1]),.mem_req_wstrb(mem_req_wstrb[1]),.mem_req_tag(mem_req_tag[1]),
  .mem_rsp_valid(mem_rsp_valid[1]),.mem_rsp_ready(mem_rsp_ready[1]),.mem_rsp_write(mem_rsp_write[1]),
  .mem_rsp_rdata(mem_rsp_rdata[1]),.mem_rsp_tag(mem_rsp_tag[1]),.mem_rsp_error(mem_rsp_error[1]));
endmodule
