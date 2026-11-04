`timescale 1ns/1ps
// Single-clock 3-master router: I=0, D=1, NPU=2. Full 6-bit owner/tag identity.
// Each accepted request reserves one of 16 response slots until consumption.
// Tags cannot be reused while live; requests and responses have local FIFOs.
// Unexpected/duplicate/not-yet-issued responses enter a sticky coordinated-reset fault.
module pg_three_request_mux(
 input logic clk,rst,
 input logic [2:0] req_valid,output logic [2:0] req_ready,
 input logic [2:0] req_write,input logic [2:0][31:0] req_addr,
 input logic [2:0][127:0] req_wdata,input logic [2:0][15:0] req_wstrb,input logic [2:0][3:0] req_id,
 output logic [2:0] rsp_valid,input logic [2:0] rsp_ready,
 output logic [2:0] rsp_write,rsp_error,output logic [2:0][127:0] rsp_rdata,output logic [2:0][3:0] rsp_id,
 output logic m_req_valid,input logic m_req_ready,output logic m_req_write,output logic [31:0] m_req_addr,
 output logic [127:0] m_req_wdata,output logic [15:0] m_req_wstrb,output logic [5:0] m_req_tag,
 input logic m_rsp_valid,output logic m_rsp_ready,input logic m_rsp_write,m_rsp_error,
 input logic [127:0] m_rsp_rdata,input logic [5:0] m_rsp_tag,
 output logic protocol_fault
);
 localparam integer PW=181,RW=134;
 logic [2:0] qi_ready,qo_valid,qo_ready,ri_ready,ro_valid;
 logic [2:0][PW-1:0] qo_data;
 logic [2:0][RW-1:0] ro_data;
 logic [2:0][1:0] unused_request_level;
 logic [2:0][4:0] unused_response_level;
 logic [2:0][15:0] live,issued,returned,write_kind;
 logic [1:0] turn,locked_owner,selected,response_owner;
 logic locked,found,response_legal;
 integer idx;
 assign response_owner=m_rsp_tag[5:4];
 always_comb begin
  response_legal=0;
  if(response_owner<3)response_legal=live[response_owner][m_rsp_tag[3:0]]&&issued[response_owner][m_rsp_tag[3:0]]&&!returned[response_owner][m_rsp_tag[3:0]]&&(write_kind[response_owner][m_rsp_tag[3:0]]==m_rsp_write);
 end
 for(genvar g=0;g<3;g++)begin:queues
  assign req_ready[g]=!protocol_fault&&qi_ready[g]&&!live[g][req_id[g]];
  pg_sync_fifo #(.WIDTH(PW),.DEPTH(2)) requests(
   .clk,.rst,.in_valid(req_valid[g]&&!protocol_fault&&!live[g][req_id[g]]),.in_ready(qi_ready[g]),
   .in_data({req_write[g],req_addr[g],req_wdata[g],req_wstrb[g],req_id[g]}),
   .out_valid(qo_valid[g]),.out_ready(qo_ready[g]),.out_data(qo_data[g]),.level(unused_request_level[g]));
  pg_sync_fifo #(.WIDTH(RW),.DEPTH(16)) responses(
   .clk,.rst,.in_valid(m_rsp_valid&&response_legal&&!protocol_fault&&(response_owner==2'(g))),.in_ready(ri_ready[g]),
   .in_data({m_rsp_error,m_rsp_write,m_rsp_tag[3:0],m_rsp_rdata}),
   .out_valid(ro_valid[g]),.out_ready(rsp_ready[g]&&!protocol_fault),.out_data(ro_data[g]),.level(unused_response_level[g]));
  assign rsp_valid[g]=ro_valid[g]&&!protocol_fault;
  assign {rsp_error[g],rsp_write[g],rsp_id[g],rsp_rdata[g]}=ro_data[g];
 end
 // Fixed 3-way circular priority: no integer addition/modulo/index chain.
 logic [2:0] cp9_rr_grant,cp9_data_grant;
 always_comb begin
  case(turn)
   2'd1: cp9_rr_grant={qo_valid[2]&&!qo_valid[1],qo_valid[1],qo_valid[0]&&!qo_valid[1]&&!qo_valid[2]};
   2'd2: cp9_rr_grant={qo_valid[2],qo_valid[1]&&!qo_valid[2]&&!qo_valid[0],qo_valid[0]&&!qo_valid[2]};
   default: cp9_rr_grant={qo_valid[2]&&!qo_valid[0]&&!qo_valid[1],qo_valid[1]&&!qo_valid[0],qo_valid[0]};
  endcase
  selected=turn;found=|qo_valid;idx=0;
  if(cp9_rr_grant[0])selected=2'd0;
  else if(cp9_rr_grant[1])selected=2'd1;
  else if(cp9_rr_grant[2])selected=2'd2;
  if(locked)selected=locked_owner;
 end
 assign cp9_data_grant=locked ? {locked_owner==2'd2,locked_owner==2'd1,locked_owner==2'd0}:cp9_rr_grant;
 // An empty pg_sync_fifo presents zero. Keep the old upper tag even idle.
 // Data no longer traverses priority encoder -> dynamic wide mux decoder.
 logic [PW-1:0] cp9_selected_data;
 assign cp9_selected_data=({PW{cp9_data_grant[0]}}&qo_data[0])|
                          ({PW{cp9_data_grant[1]}}&qo_data[1])|
                          ({PW{cp9_data_grant[2]}}&qo_data[2]);
 // synthesis translate_off
 always_ff @(posedge clk)if(!rst)begin
  if(turn>=3 || (locked && locked_owner>=3))$fatal(1,"CP9_RR_STATE_RED");
  if(cp9_selected_data!==qo_data[selected])$fatal(1,"CP9_RR_DATA_RED");
 end
 // synthesis translate_on
 // With no locked request, a work-conserving arbiter is valid exactly
 // when ANY request FIFO is nonempty. No priority encoder is in this cone.
 assign m_req_valid=!rst&&!protocol_fault&&(locked?qo_valid[locked_owner]:(|qo_valid));
 // synthesis translate_off
 always_ff @(posedge clk)if(!rst)begin
  if(m_req_valid !== (!rst&&!protocol_fault&&qo_valid[selected]))$fatal(1,"CP9_RR_VALID_RED");
 end
 // synthesis translate_on
 assign {m_req_write,m_req_addr,m_req_wdata,m_req_wstrb,m_req_tag[3:0]}=cp9_selected_data;
 assign m_req_tag[5:4]=selected;
 always_comb begin
  qo_ready=0;qo_ready[selected]=m_req_valid&&m_req_ready;
  m_rsp_ready=!rst;
  if(!protocol_fault&&response_legal)m_rsp_ready=!rst&&ri_ready[response_owner];
 end
 always_ff @(posedge clk)begin
  if(rst)begin turn<=0;locked_owner<=0;locked<=0;protocol_fault<=0;live<=0;issued<=0;returned<=0;write_kind<=0;end
  else begin
   if(m_req_valid)begin
    if(m_req_ready)begin turn<=selected==2?2'd0:selected+1'b1;locked<=0;issued[selected][m_req_tag[3:0]]<=1;end
    else begin locked<=1;locked_owner<=selected;end
   end
   if(m_rsp_valid&&m_rsp_ready&&!protocol_fault)begin
    if(!response_legal)protocol_fault<=1;
    else returned[response_owner][m_rsp_tag[3:0]]<=1;
   end
   for(integer g=0;g<3;g++)begin
    if(req_valid[g]&&req_ready[g])begin live[g][req_id[g]]<=1;write_kind[g][req_id[g]]<=req_write[g];end
    if(rsp_valid[g]&&rsp_ready[g])begin live[g][rsp_id[g]]<=0;issued[g][rsp_id[g]]<=0;returned[g][rsp_id[g]]<=0;end
   end
  end
 end
endmodule
