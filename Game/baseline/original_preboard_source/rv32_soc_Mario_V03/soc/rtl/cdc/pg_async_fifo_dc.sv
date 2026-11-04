// Power-of-two dual-clock FIFO. Gray pointers cross via two synchronizers.
// Read port is synchronous and has a one-entry holding register; the public
// channel can hold DEPTH memory entries plus this registered output entry.
// No ready/valid or payload combinational path crosses clock domains.
// The RAM read pointer advances on PREFETCH, not output consumption: after
// prefetch the word belongs to out_data_q, so that RAM slot can safely recycle.
// No memory reset. Only coordinated global reset is supported.
(* KEEP_HIERARCHY="yes" *)
module pg_async_fifo_dc #(parameter int WIDTH=8,DEPTH=8)(
 input logic wr_clk,rd_clk,arst,
 input logic in_valid,output logic in_ready,input logic[WIDTH-1:0] in_data,
 output logic out_valid,input logic out_ready,output logic[WIDTH-1:0] out_data
);
 timeunit 1ns;timeprecision 1ps;
 localparam int AW=(DEPTH>1)?$clog2(DEPTH):1;
 localparam int PW=AW+1;
 logic wr_rst,rd_rst;
 pg_reset_sync wr_release(.clk(wr_clk),.arst,.rst(wr_rst));
 pg_reset_sync rd_release(.clk(rd_clk),.arst,.rst(rd_rst));
 logic[PW-1:0] wbin_q,rbin_q,wgray_q,rgray_q,wbin_next,rbin_next,wgray_next,rgray_next;
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic[PW-1:0] rgray_wmeta_q,rgray_wsync_q;
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic[PW-1:0] wgray_rmeta_q,wgray_rsync_q;
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic rup_wmeta_q,rup_wsync_q,wup_rmeta_q,wup_rsync_q;
 logic wfull_q,rempty_q,wpush,rload,rvalid_q;
 logic[WIDTH-1:0] rdata_q;
 (* ram_style="distributed" *) logic[WIDTH-1:0] memory[0:DEPTH-1];
 logic[PW-1:0] full_target;
 assign in_ready=!wr_rst&&rup_wsync_q&&!wfull_q;
 assign out_valid=!rd_rst&&wup_rsync_q&&rvalid_q;
 assign out_data=rdata_q;
 assign wpush=in_valid&&in_ready;
 assign rload=!rd_rst&&wup_rsync_q&&!rempty_q&&(!rvalid_q||out_ready);
 assign wbin_next=wbin_q+PW'(wpush);
 assign rbin_next=rbin_q+PW'(rload);
 assign wgray_next=(wbin_next>>1)^wbin_next;
 assign rgray_next=(rbin_next>>1)^rbin_next;
 assign full_target=rgray_wsync_q ^ (PW'(3)<<(PW-2));
 always_ff @(posedge wr_clk or posedge wr_rst)begin
  if(wr_rst)begin
   wbin_q<=0;wgray_q<=0;wfull_q<=0;
   rgray_wmeta_q<=0;rgray_wsync_q<=0;rup_wmeta_q<=0;rup_wsync_q<=0;
  end else begin
   rgray_wmeta_q<=rgray_q;rgray_wsync_q<=rgray_wmeta_q;
   rup_wmeta_q<=!rd_rst;rup_wsync_q<=rup_wmeta_q;
   wbin_q<=wbin_next;wgray_q<=wgray_next;wfull_q<=(wgray_next==full_target);
  end
 end
 always_ff @(posedge rd_clk or posedge rd_rst)begin
  if(rd_rst)begin
   rbin_q<=0;rgray_q<=0;rempty_q<=1;rvalid_q<=0;
   wgray_rmeta_q<=0;wgray_rsync_q<=0;wup_rmeta_q<=0;wup_rsync_q<=0;
  end else begin
   wgray_rmeta_q<=wgray_q;wgray_rsync_q<=wgray_rmeta_q;
   wup_rmeta_q<=!wr_rst;wup_rsync_q<=wup_rmeta_q;
   rbin_q<=rbin_next;rgray_q<=rgray_next;rempty_q<=(rgray_next==wgray_rsync_q);
   if(rload)rvalid_q<=1;
   else if(out_valid&&out_ready)rvalid_q<=0;
  end
 end
 // A single writer and a synchronous read port; each physical slot remains
 // stable from write until the Gray-synchronized pointer permits prefetch.
 always_ff @(posedge wr_clk)if(wpush)memory[wbin_q[AW-1:0]]<=in_data;
 always_ff @(posedge rd_clk)if(rload)rdata_q<=memory[rbin_q[AW-1:0]];
 initial begin
  if(WIDTH<1||DEPTH<2||(DEPTH&(DEPTH-1))!=0)$fatal(1,"CP6_ASYNC_FIFO_PARAMETER_RED");
 end
 // synthesis translate_off
 logic[PW-1:0] prev_wgray,prev_rgray;
 always_ff @(posedge wr_clk or posedge wr_rst)
  if(wr_rst)prev_wgray<=0;
  else begin
   if(!$onehot0(wgray_q^prev_wgray))$fatal(1,"CP6_FIFO_WRITE_GRAY_RED");
   prev_wgray<=wgray_q;
  end
 always_ff @(posedge rd_clk or posedge rd_rst)
  if(rd_rst)prev_rgray<=0;
  else begin
   if(!$onehot0(rgray_q^prev_rgray))$fatal(1,"CP6_FIFO_READ_GRAY_RED");
   prev_rgray<=rgray_q;
  end
 // synthesis translate_on
endmodule
