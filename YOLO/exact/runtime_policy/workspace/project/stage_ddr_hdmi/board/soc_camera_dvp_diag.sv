// Passive DVP observation. It does not gate or alter the production receiver.
// A held frame packet crosses to the DDR UI domain using toggle/ack CDC.
// CPU-requested snapshots are immutable until the next snapshot write.
module soc_camera_dvp_diag #(
 parameter int WIDTH=1280, HEIGHT=720,
 parameter int MEASURE_TICKS=937500
)(
 input logic pclk,mem_clk,arst,vsync,href,
 input logic snapshot_req,
 output logic [511:0] snapshot_words
);
 timeunit 1ns;timeprecision 1ps;
 logic pclk_rst,mem_rst;
 pg_reset_sync p_reset(.clk(pclk),.arst,.rst(pclk_rst));
 pg_reset_sync m_reset(.clk(mem_clk),.arst,.rst(mem_rst));
 logic vs_sample,href_sample,vs_prev,href_prev,running;
 logic [31:0] frame_seq,frame_cycles,total_bytes,line_bytes,lines;
 logic [31:0] min_line,max_line,short_lines,long_lines,odd_lines;
 logic overflow_hold;
 logic [351:0] frame_hold,frame_mem;
 logic frame_toggle,ack_toggle,ack_pclk,frame_toggle_mem;
 logic frame_seen_mem,frame_pending,frame_available;
 logic [31:0] dropped_frames;
 pg_level_sync ack_sync(.clk(pclk),.rst(pclk_rst),
   .async_level(ack_toggle),.level(ack_pclk));
 pg_level_sync frame_sync(.clk(mem_clk),.rst(mem_rst),
   .async_level(frame_toggle),.level(frame_toggle_mem));
 wire [31:0] finish_flags={25'b0,overflow_hold,(long_lines!=0),
     (short_lines!=0),(odd_lines!=0),(lines!=HEIGHT),(lines==0),
     (href_sample||href_prev||line_bytes!=0)};

 // Counts all pin PCLK edges, including blanking. 24 bits wrap safely because
 // a supported observation window contains fewer than 2**24 edges.
 logic [23:0] edge_counter,edge_gray;
 always_ff @(posedge pclk or posedge pclk_rst)begin
  if(pclk_rst)begin edge_counter<=0;edge_gray<=0;end
  else begin
   edge_counter<=edge_counter+24'd1;
   edge_gray<=((edge_counter+24'd1)>>1)^(edge_counter+24'd1);
  end
 end
 always_ff @(posedge pclk or posedge pclk_rst)begin
  if(pclk_rst)begin
   vs_sample<=1;href_sample<=0;vs_prev<=1;href_prev<=0;running<=0;
   frame_seq<=0;frame_cycles<=0;total_bytes<=0;line_bytes<=0;lines<=0;
   min_line<=32'hffff_ffff;max_line<=0;short_lines<=0;long_lines<=0;odd_lines<=0;
   overflow_hold<=0;frame_hold<=0;frame_toggle<=0;dropped_frames<=0;
  end else begin
   // Matches the production pipeline's one common input sampling edge.
   vs_sample<=vsync;href_sample<=href;
   vs_prev<=vs_sample;href_prev<=href_sample;
   if(vs_prev&&!vs_sample)begin
    running<=1;frame_cycles<=0;lines<=0;
    total_bytes<=href_sample?32'd1:32'd0;
    line_bytes<=href_sample?32'd1:32'd0;
    min_line<=32'hffff_ffff;max_line<=0;short_lines<=0;long_lines<=0;odd_lines<=0;
    overflow_hold<=0;
   end else if(running)begin
    if(!vs_prev&&vs_sample)begin
     running<=0;frame_seq<=frame_seq+1'b1;
     if(frame_toggle==ack_pclk)begin
      frame_hold<={dropped_frames,finish_flags,odd_lines,long_lines,short_lines,
          max_line,(lines==0?32'd0:min_line),lines,total_bytes,frame_cycles,frame_seq+32'd1};
      frame_toggle<=!frame_toggle;
     end else dropped_frames<=dropped_frames+1'b1;
    end else begin
     if(frame_cycles==32'hffff_ffff)overflow_hold<=1;
     else frame_cycles<=frame_cycles+1'b1;
     if(href_sample&&!vs_sample)begin
      if(total_bytes==32'hffff_ffff||line_bytes==32'hffff_ffff)overflow_hold<=1;
      else begin total_bytes<=total_bytes+1'b1;line_bytes<=line_bytes+1'b1;end
     end else if(href_prev&&!href_sample)begin
      if(lines==32'hffff_ffff)overflow_hold<=1;
      else lines<=lines+1'b1;
      if(line_bytes<min_line)min_line<=line_bytes;
      if(line_bytes>max_line)max_line<=line_bytes;
      if(line_bytes<2*WIDTH)short_lines<=short_lines+1'b1;
      if(line_bytes>2*WIDTH)long_lines<=long_lines+1'b1;
      if(line_bytes[0])odd_lines<=odd_lines+1'b1;
      line_bytes<=0;
     end
    end
   end
  end
 end

 (* ASYNC_REG="TRUE" *) logic [23:0] edge_gray_sync1,edge_gray_sync2;
 logic [23:0] edge_binary_sync,edge_at_window,measured_edges;
 logic [$clog2(MEASURE_TICKS)-1:0] measure_count;
 logic frequency_available,window_primed;
 logic [31:0] snapshot_seq;
 function automatic [23:0] gray_binary(input logic [23:0] value);
  for(int i=0;i<24;i++)gray_binary[i]=^(value>>i);
 endfunction
 always_ff @(posedge mem_clk)begin
  if(mem_rst)begin
   edge_gray_sync1<=0;edge_gray_sync2<=0;edge_binary_sync<=0;
   edge_at_window<=0;measured_edges<=0;measure_count<=0;frequency_available<=0;window_primed<=0;
   frame_seen_mem<=0;frame_pending<=0;frame_mem<=0;frame_available<=0;ack_toggle<=0;
   snapshot_seq<=0;snapshot_words<=0;
   snapshot_words[31:0]<=32'h3147_4443; // bytes "CDG1"
  end else begin
   edge_gray_sync1<=edge_gray;edge_gray_sync2<=edge_gray_sync1;
   edge_binary_sync<=gray_binary(edge_gray_sync2);
   if(measure_count==MEASURE_TICKS-1)begin
    measure_count<=0;
    // The first interval includes reset release and Gray pipeline warmup.
    // Establish the first endpoint without publishing that partial interval.
    if(window_primed)begin
     measured_edges<=edge_binary_sync-edge_at_window;frequency_available<=1;
    end
    edge_at_window<=edge_binary_sync;window_primed<=1;
   end else measure_count<=measure_count+1'b1;
   if(frame_toggle_mem!=frame_seen_mem&&!frame_pending)frame_pending<=1;
   else if(frame_pending)begin
    // The source packet was held before the two-flop toggle synchronizer.
    // One extra memory edge precedes sampling; acknowledge only after sampling.
    frame_mem<=frame_hold;frame_seen_mem<=frame_toggle_mem;
    ack_toggle<=frame_toggle_mem;frame_pending<=0;frame_available<=1;
   end
   if(snapshot_req)begin
    snapshot_seq<=snapshot_seq+1'b1;
    snapshot_words[31:0]<=32'h3147_4443;
    snapshot_words[63:32]<={16'd1,14'd0,frequency_available,frame_available};
    snapshot_words[95:64]<=snapshot_seq+1'b1;
    snapshot_words[127:96]<={8'd0,measured_edges};
    snapshot_words[159:128]<=32'(MEASURE_TICKS);
    for(int i=0;i<11;i++)snapshot_words[32*(i+5)+:32]<=frame_mem[32*i+:32];
   end
  end
 end
 initial if(WIDTH<1||HEIGHT<1||MEASURE_TICKS<8)
  $fatal(1,"CAMERA_DIAG_PARAMETERS");
endmodule
