// SPDX-License-Identifier: MIT
// Generic 720p raster + bounded two-line RGB565 DMA reader. One clock domain.
// No DDR controller, PHY, TMDS encoder or serializer is implied by this module.
// Memory accepts exactly one 32-bit read, responds valid/ready with data/error.
module rv32_framebuffer_scanout #(
 parameter [31:0] REGION_BASE=32'h83f00000, REGION_LIMIT=32'h84000000,
 parameter H_ACTIVE=1280,H_FRONT=110,H_SYNC=40,H_BACK=220,
 parameter V_ACTIVE=720,V_FRONT=5,V_SYNC=5,V_BACK=20
)(
 input clk,reset,input [31:0] active_base,input active_enable,
 output vblank,output de,hsync,vsync,output [15:0] pixel_rgb565,
 output [11:0] pixel_x,output [10:0] pixel_y,
 output mem_req_valid,input mem_req_ready,output [31:0] mem_req_addr,
 input mem_rsp_valid,output mem_rsp_ready,input [31:0] mem_rsp_data,input mem_rsp_error,
 output reg [31:0] frame_count,underflow_rows,dma_errors,bounds_errors
);
 localparam HTOTAL=H_ACTIVE+H_FRONT+H_SYNC+H_BACK;
 localparam VTOTAL=V_ACTIVE+V_FRONT+V_SYNC+V_BACK;
 localparam SRC_WIDTH=H_ACTIVE/2,SRC_HEIGHT=V_ACTIVE/2,WORDS=SRC_WIDTH/2;
 localparam WIDX=(WORDS<=1)?1:$clog2(WORDS);
 localparam FRAME_BYTES=SRC_WIDTH*SRC_HEIGHT*2;
 reg [11:0] hx;reg [10:0] vy;
 reg [31:0] line0[0:WORDS-1],line1[0:WORDS-1];
 reg [1:0] line_ready,line_bad;reg [9:0] tag0,tag1;
 reg row_ok,enabled;
 reg [31:0] frame_base;
 reg [9:0] fill_y,fill_word;
 reg fill_bad;
 reg [1:0] state;reg request_stale,request_bank;
 reg [9:0] request_word,request_y;reg [31:0] request_address;
 wire frame_latch=(vy==V_ACTIVE)&&(hx==1);
 wire base_ok=(active_base[5:0]==0)&&(active_base>=REGION_BASE)&&
  ({1'b0,active_base}+FRAME_BYTES<={1'b0,REGION_LIMIT});
 wire [9:0] source_y=vy[10:1];wire bank=source_y[0];
 // Registered memory read ports permit block-RAM mapping; all video metadata
 // is delayed identically by one pixel clock. Physical mapping still needs PDS.
 reg [31:0] read0,read1;reg pixel_bank,pixel_half,pixel_ok;
 reg [11:0] out_x;reg [10:0] out_y;
 wire [31:0] pixel_word=pixel_bank?read1:read0;
 assign pixel_rgb565=de&&pixel_ok?(pixel_half?pixel_word[31:16]:pixel_word[15:0]):16'd0;
 assign de=(out_x<H_ACTIVE)&&(out_y<V_ACTIVE);
 assign hsync=(out_x>=H_ACTIVE+H_FRONT)&&(out_x<H_ACTIVE+H_FRONT+H_SYNC);
 assign vsync=(out_y>=V_ACTIVE+V_FRONT)&&(out_y<V_ACTIVE+V_FRONT+V_SYNC);
 assign pixel_x=out_x;assign pixel_y=out_y;
 always @(posedge clk)begin
  read0<=line0[hx[WIDX+1:2]];read1<=line1[hx[WIDX+1:2]];
  if(reset)begin out_x<=0;out_y<=V_ACTIVE;pixel_bank<=0;pixel_half<=0;pixel_ok<=0;end
  else begin out_x<=hx;out_y<=vy;pixel_bank<=bank;pixel_half<=hx[1];pixel_ok<=enabled&&row_ok;end
 end
 assign vblank=(vy==V_ACTIVE)&&(hx==0);
 assign mem_req_valid=(state==1);assign mem_req_addr=request_address;
 assign mem_rsp_ready=(state==2);
 wire [10:0] next_v=(vy==VTOTAL-1)?11'd0:vy+1'b1;
 wire [9:0] next_sy=next_v[10:1];
 wire next_row_ready=next_sy[0]?(line_ready[1]&&!line_bad[1]&&tag1==next_sy):(line_ready[0]&&!line_bad[0]&&tag0==next_sy);
 always @(posedge clk)begin
  if(reset)begin
   hx<=0;vy<=V_ACTIVE;frame_count<=0;underflow_rows<=0;dma_errors<=0;bounds_errors<=0;
   line_ready<=0;line_bad<=0;tag0<=0;tag1<=0;row_ok<=0;enabled<=0;frame_base<=REGION_BASE;
   fill_y<=0;fill_word<=0;fill_bad<=0;state<=0;request_stale<=0;request_bank<=0;request_word<=0;request_y<=0;request_address<=REGION_BASE;
  end else begin
   if(hx==HTOTAL-1)begin
    hx<=0;vy<=next_v;
    if(vy==VTOTAL-1)frame_count<=frame_count+1'b1;
    if(next_v<V_ACTIVE&&!next_v[0])row_ok<=next_row_ready;
   end else hx<=hx+1'b1;
   if(hx==0&&vy<V_ACTIVE&&!vy[0]&&enabled&&!row_ok)underflow_rows<=underflow_rows+1'b1;
   if(hx==H_ACTIVE-1&&vy<V_ACTIVE&&vy[0])line_ready[bank]<=0;
   if(state==0&&!frame_latch&&enabled&&fill_y<SRC_HEIGHT&&!line_ready[fill_y[0]])begin
    request_address<=frame_base+fill_y*(SRC_WIDTH*2)+fill_word*4;
    request_stale<=0;request_bank<=fill_y[0];request_word<=fill_word;request_y<=fill_y;state<=1;
   end
   if(state==1&&mem_req_ready)state<=2;
   if(state==2&&mem_rsp_valid)begin
    state<=0;
    if(!request_stale&&!frame_latch)begin
     if(request_bank)line1[request_word[WIDX-1:0]]<=mem_rsp_error?32'd0:mem_rsp_data;
     else line0[request_word[WIDX-1:0]]<=mem_rsp_error?32'd0:mem_rsp_data;
     if(mem_rsp_error)begin dma_errors<=dma_errors+1'b1;fill_bad<=1;end
     if({22'd0,request_word}==WORDS-1)begin
      line_ready[request_bank]<=1;line_bad[request_bank]<=fill_bad||mem_rsp_error;
      if(request_bank)tag1<=request_y;else tag0<=request_y;
      fill_y<=fill_y+1'b1;fill_word<=0;fill_bad<=0;
     end else fill_word<=fill_word+1'b1;
    end
   end
   // Keep an already presented memory request stable; drain its stale response.
   // All line ownership and next requests switch epoch atomically at vblank+1.
   if(frame_latch)begin
    request_stale<=1;frame_base<=active_base;enabled<=active_enable&&base_ok;
    line_ready<=0;line_bad<=0;fill_y<=0;fill_word<=0;fill_bad<=0;row_ok<=0;
    if(active_enable&&!base_ok)bounds_errors<=bounds_errors+1'b1;
   end
  end
 end
endmodule
