`timescale 1ns/1ps
// Unmerged compact Conv service at unused NPU MMIO page0x70000100.
// Static validation remains in the CPU driver; this block removes perTile
// CPU submission and owns the existing NPU and Window interfaces until both
// have genuinely completed. It is not a second Scheduler/DMA/PE array.
module soc_conv_service #(parameter integer WINDOW_BATCH_ROWS=64)(
 input logic clk,rst,can_start,
 input logic req_valid,output logic req_ready,input logic [15:0] req_addr,
 input logic req_write,input logic [31:0] req_wdata,input logic [3:0] req_wstrb,
 output logic rsp_valid,input logic rsp_ready,output logic [31:0] rsp_rdata,output logic rsp_error,
 output logic locked,protocol_poison,
 output logic resident_enable,
 output logic [31:0] resident_model_epoch,resident_frame_epoch,resident_task_generation,resident_a_generation,resident_b_base,
 output logic [4:0] resident_next_a_rows,
 output logic [8:0] resident_b_columns,output logic [4:0] resident_b_group,
 output logic [31:0] legacy_addr,legacy_wdata,output logic legacy_wen,
 output logic [1:0] legacy_mask,input logic [31:0] legacy_rdata,
 output logic Window_req_valid,input logic Window_req_ready,output logic [15:0] Window_req_addr,
 output logic Window_req_write,output logic [31:0] Window_req_wdata,output logic [3:0] Window_req_wstrb,
 input logic Window_rsp_valid,output logic Window_rsp_ready,input logic [31:0] Window_rsp_rdata,input logic Window_rsp_error
);
 // Regional synchronous reset distribution; identity LUTs add no clock cycle.
 // Targeted preservation applies only to these drivers, not to their loads.
 (* syn_keep=1 *) wire region_reset_control;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_control(.I0(rst),.Z(region_reset_control));
 (* syn_keep=1 *) wire region_reset_npu_client;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_npu_client(.I0(rst),.Z(region_reset_npu_client));
 (* syn_keep=1 *) wire region_reset_Window_client;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_Window_client(.I0(rst),.Z(region_reset_Window_client));

 import npu_defs_pkg::*;
 // Visible configuration is reset to zero by one valid bit per word.
 // Payload is written before becoming visible; all reads and datapath users
 // share this masked view, so reset-time software-visible values are retained.
 wire [31:0] cfg[0:30];
 logic [31:0] cfg_payload[0:30];
 logic [30:0] cfg_initialized;
 logic cfg_write_accepted;
 for(genvar cfg_word=0;cfg_word<31;cfg_word++)begin:g_cfg_visible
  assign cfg[cfg_word]=cfg_initialized[cfg_word]?cfg_payload[cfg_word]:32'd0;
 end
 always_comb begin
  cfg_write_accepted=1'b0;
  // Match the original procedural decode, including reject/write priority.
  if(req_valid&&req_ready)begin
   if(!hit||(req_write&&req_wstrb!=4'hf))begin end
   else if(req_write)begin
    if(req_addr==16'h0100)begin end
    else if(cfg_hit&&!locked)cfg_write_accepted=1'b1;
   end
  end
 end
 always_ff @(posedge clk)begin
  if(cfg_write_accepted)cfg_payload[cfg_index]<=req_wdata;
  if(rst)cfg_initialized<='0;
  else if(cfg_write_accepted)cfg_initialized[cfg_index]<=1'b1;
 end
 logic start_q,cancel_q,done_q,busy_q,rejected_q;
 logic g_ready,g_busy,g_done,g_partial,g_poison,g_rejected;
 logic [7:0] g_error;logic [2:0] g_source;
 logic [63:0] g_MACs;logic [31:0] g_commands,g_Windows;
 logic n_cmd_valid,n_cmd_ready,n_comp_valid,n_comp_ready,n_busy,n_poison;
 npu_cmd_t n_cmd;npu_completion_t n_comp;
 logic w_valid,w_ready,w_done_valid,w_done_ready,w_partial,w_busy,w_poison;
 logic [351:0] w_data;logic [31:0] w_cookie,w_done_cookie;
 logic [7:0] w_error;
 logic [31:0] n_service_cycles,n_command_ticks,w_command_ticks,w_read,w_write,w_active,w_stall,w_hits,w_misses;
 wire hit=req_addr[15:8]==8'h01&&req_addr[1:0]==0;
 wire cfg_hit=req_addr>=16'h0140&&req_addr<=16'h01b8;
 wire [5:0] cfg_index=req_addr[7:2]-6'd16;
 wire reserved_ok=cfg[4][31:16]==0&&cfg[5][31:2]==0&&cfg[16]==0&&cfg[17]==0&&cfg[18]==0&&cfg[19]==0;
 assign resident_enable=locked&&!cfg[5][1];
 assign resident_model_epoch=cfg[0];assign resident_frame_epoch=cfg[1];
 assign req_ready=!rst&&!rsp_valid;
 assign protocol_poison=g_poison||n_poison||w_poison;
 assign locked=busy_q||protocol_poison;
 soc_conv_microsequencer #(.WINDOW_BATCH_ROWS(WINDOW_BATCH_ROWS)) control(
  .clk,.rst(region_reset_control),.start(start_q),.cancel(cancel_q),
  .model_epoch(cfg[0]),.frame_epoch(cfg[1]),.total_rows(cfg[2]),.columns(cfg[3][15:0]),.k_length(cfg[3][31:16]),.output_width(cfg[4][15:0]),
  .use_window(cfg[5][0]),.input_int16(cfg[5][1]),.a_base(cfg[6]),.b_base(cfg[7]),.c_base(cfg[8]),.a_stride(cfg[9]),.c_stride(cfg[10]),
  .a_block_step(cfg[11]),.c_block_step(cfg[12]),.b_group_step(cfg[13]),.scratch_base(cfg[14]),.scratch_stride(cfg[15]),
  .window_template({cfg[30],cfg[29],cfg[28],cfg[27],cfg[26],cfg[25],cfg[24],cfg[23],cfg[22],cfg[21],cfg[20]}),
  .resident_a_generation,.resident_b_base,.resident_b_columns,.resident_b_group,.resident_next_a_rows,
  .ready(g_ready),.busy(g_busy),.done_pulse(g_done),.partial_output(g_partial),.protocol_poison(g_poison),.rejected_busy(g_rejected),
  .error_code(g_error),.error_source(g_source),.completed_MACs(g_MACs),.command_count(g_commands),.Window_count(g_Windows),
  .npu_cmd_valid(n_cmd_valid),.npu_cmd_ready(n_cmd_ready),.npu_cmd(n_cmd),.npu_comp_valid(n_comp_valid),.npu_comp_ready(n_comp_ready),.npu_comp(n_comp),
  .Window_req_valid(w_valid),.Window_req_ready(w_ready),.Window_req_data(w_data),.Window_req_cookie(w_cookie),
  .Window_rsp_valid(w_done_valid),.Window_rsp_ready(w_done_ready),.Window_rsp_cookie(w_done_cookie),.Window_rsp_error(w_error),.Window_rsp_partial(w_partial));
 soc_npu_legacy_descriptor_port npu_client(
  .clk,.rst(region_reset_npu_client),.enable(locked),.clear_counters(start_q),.cmd_valid(n_cmd_valid),.cmd_ready(n_cmd_ready),.cmd(n_cmd),
  .comp_valid(n_comp_valid),.comp_ready(n_comp_ready),.comp(n_comp),.legacy_addr,.legacy_wdata,.legacy_wen,.legacy_mask,.legacy_rdata,
  .busy(n_busy),.protocol_poison(n_poison),.completed_service_cycles(n_service_cycles),.total_command_ticks(n_command_ticks));
 soc_window_descriptor_port Window_client(
  .clk,.rst(region_reset_Window_client),.clear_counters(start_q),.job_valid(w_valid),.job_ready(w_ready),.job_data(w_data),.job_cookie(w_cookie),.expected_K(cfg[3][31:16]),
  .done_valid(w_done_valid),.done_ready(w_done_ready),.done_cookie(w_done_cookie),.done_error(w_error),.done_partial(w_partial),
  .req_valid(Window_req_valid),.req_ready(Window_req_ready),.req_addr(Window_req_addr),.req_write(Window_req_write),.req_wdata(Window_req_wdata),.req_wstrb(Window_req_wstrb),
  .rsp_valid(Window_rsp_valid),.rsp_ready(Window_rsp_ready),.rsp_rdata(Window_rsp_rdata),.rsp_error(Window_rsp_error),
  .busy(w_busy),.protocol_poison(w_poison),.total_read_bytes(w_read),.total_write_bytes(w_write),.total_active_UI(w_active),.total_stall_UI(w_stall),.total_hits(w_hits),.total_misses(w_misses),.total_command_ticks(w_command_ticks));
 always_ff @(posedge clk)begin
  start_q<=0;cancel_q<=0;
  if(rst)begin
   resident_task_generation<=0;rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;busy_q<=0;done_q<=0;rejected_q<=0;

  end else begin
   if(rsp_valid&&rsp_ready)rsp_valid<=0;
   if(g_done)begin
    if(n_busy||w_busy||g_busy)begin
     // g_busy is sampled while g_done is high after FINISH's transition to
     // IDLE; every descriptor response must already be released by then.
     rejected_q<=1;
    end else begin busy_q<=0;done_q<=1;end
   end
   if(req_valid&&req_ready)begin
    rsp_valid<=1;rsp_rdata<=0;rsp_error<=0;
    if(!hit||(req_write&&req_wstrb!=4'hf))begin rsp_error<=1;rejected_q<=1;end
    else if(req_write)begin
     if(req_addr==16'h0100)begin
      if(req_wdata==1&&!locked&&can_start&&g_ready&&!n_busy&&!w_busy&&reserved_ok&&resident_task_generation!=32'hffffffff)begin resident_task_generation<=resident_task_generation+1'b1;start_q<=1;busy_q<=1;done_q<=0;rejected_q<=0;end
      else if(req_wdata==2&&busy_q&&!protocol_poison)cancel_q<=1;
      else begin rsp_error<=1;rejected_q<=1;end
     end else if(cfg_hit&&!locked)begin end // payload/valid update above
     else begin rsp_error<=1;rejected_q<=1;end
    end else if(cfg_hit)rsp_rdata<=cfg[cfg_index];
    else case(req_addr)
     16'h0100:rsp_rdata<=0;
     16'h0104:rsp_rdata<={16'd0,protocol_poison,rejected_q,g_source,g_error,g_partial,done_q,busy_q};
     16'h0108:rsp_rdata<=32'h32584547; // GEX2: explicit producer/consumer batch contract
     16'h010c:rsp_rdata<=g_MACs[31:0];
     16'h0110:rsp_rdata<=g_MACs[63:32];
     16'h0114:rsp_rdata<=g_commands;
     16'h0118:rsp_rdata<=g_Windows;
     16'h011c:rsp_rdata<=n_service_cycles;
     16'h0120:rsp_rdata<=w_read;
     16'h0124:rsp_rdata<=w_write;
     16'h0128:rsp_rdata<=w_active;
     16'h012c:rsp_rdata<=w_stall;
     16'h0130:rsp_rdata<=w_hits;
     16'h0134:rsp_rdata<=w_misses;
     16'h0138:rsp_rdata<=w_command_ticks;
     16'h013c:rsp_rdata<=n_command_ticks;
     16'h01bc:rsp_rdata<=32'(WINDOW_BATCH_ROWS); // read-only capability
     default:begin rsp_error<=1;rejected_q<=1;end
    endcase
   end
  end
 end
 // synthesis translate_off
 always_ff @(posedge clk)if(!rst)begin
  if(g_done&&(n_busy||w_busy||g_busy))$fatal(1,"GEX_SERVICE_DONE_WITH_LIVE_OWNER_RED");
  if(legacy_wen&&!locked)$fatal(1,"GEX_SERVICE_UNOWNED_NPU_WRITE_RED");
 end
 // synthesis translate_on
endmodule
