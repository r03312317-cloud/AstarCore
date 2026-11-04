// OV5640 RGB565 DVP byte receiver. The sensor emits the high byte first.
// A level arm from the memory domain is synchronized locally. A frame starts
// on VSYNC falling and ends on VSYNC rising. No pixel backpressure exists:
// FIFO overflow or a malformed line poisons the whole frame. done_toggle,
// bad_hold and pixels_hold stay stable until arm is deasserted and reasserted.
module soc_camera_dvp_capture #(
 parameter int WIDTH=1280, HEIGHT=720
)(
 input logic pclk,arst,arm,vsync,href,
 input logic [7:0] byte_data,
 output logic pixel_valid,input logic pixel_ready,
 output logic [15:0] pixel_data,
 output logic done_toggle,bad_hold,
 output logic [31:0] pixels_hold
);
 timeunit 1ns;timeprecision 1ps;
 logic rst,armed,seen_vsync,vsync_q,href_q;
 pg_reset_sync u_reset(.clk(pclk),.arst,.rst);
 pg_level_sync u_arm(.clk(pclk),.rst,.async_level(arm),.level(armed));
 typedef enum logic [1:0] {WAIT_ARM,WAIT_LOW,CAPTURE,WAIT_RELEASE} state_t;
 state_t state;
 logic half_byte,bad;
 logic [7:0] first_byte;
 logic [15:0] col,row;
 logic [31:0] pixels;
 // DVP cannot hold a pixel. A full FIFO drops this pixel and marks the frame
 // bad; it must never present an unstable stalled ready/valid payload.
 assign pixel_valid=!rst && state==CAPTURE && !vsync && href &&
                    half_byte && row<HEIGHT && col<WIDTH && pixel_ready;
 assign pixel_data={first_byte,byte_data};
 always_ff @(posedge pclk) begin
  if(rst)begin
   state<=WAIT_ARM;seen_vsync<=0;vsync_q<=1;href_q<=0;
   half_byte<=0;first_byte<=0;col<=0;row<=0;pixels<=0;
   done_toggle<=0;bad_hold<=0;pixels_hold<=0;bad<=0;
  end else begin
   vsync_q<=vsync;href_q<=href;
   if(vsync)seen_vsync<=1;
   case(state)
    WAIT_ARM:if(armed&&seen_vsync)state<=WAIT_LOW;
    WAIT_LOW:begin
     if(!armed)state<=WAIT_ARM;
     else if(vsync_q&&!vsync)begin
      // HREF may already carry the first RGB565 high byte on this edge.
      state<=CAPTURE;half_byte<=href;
      if(href)first_byte<=byte_data;
      col<=0;row<=0;pixels<=0;bad<=0;
     end
    end
    CAPTURE:begin
     if(!vsync_q&&vsync)begin
      // A final HREF ending on the VSYNC edge is malformed.
      bad_hold<=bad || href || href_q || half_byte || col!=0 || row!=HEIGHT;
      pixels_hold<=pixels;done_toggle<=!done_toggle;state<=WAIT_RELEASE;
     end else if(vsync)bad<=1;
     else if(href)begin
      if(row>=HEIGHT)bad<=1;
      if(!half_byte)begin first_byte<=byte_data;half_byte<=1;end
      else begin
       half_byte<=0;
       if(col>=WIDTH || !pixel_ready)bad<=1;
       if(col<WIDTH)col<=col+1'b1;
       if(row<HEIGHT&&col<WIDTH)pixels<=pixels+1'b1;
      end
     end else if(href_q)begin
      if(half_byte||col!=WIDTH||row>=HEIGHT)bad<=1;
      half_byte<=0;col<=0;row<=row+1'b1;
     end
    end
    WAIT_RELEASE:if(!armed)state<=WAIT_ARM;
    default:state<=WAIT_ARM;
   endcase
  end
 end
 initial if(WIDTH<8||HEIGHT<1||WIDTH>65535||HEIGHT>65535)
  $fatal(1,"CAMERA_DVP_DIMENSION");
endmodule
