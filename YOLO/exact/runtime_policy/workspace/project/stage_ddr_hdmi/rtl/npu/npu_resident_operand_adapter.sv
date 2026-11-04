`timescale 1ns/1ps
// RV32 operand-phase extension. No second DMA, Scheduler or PE array.
// Old K64 requests name slices of committed full-K resident generations.
// Cache hits complete an operand lookup; they NEVER fabricate DDR responses.
// Store and nonresident INT8/INT16 jobs use the same unmodified physical DMA.
module npu_resident_operand_adapter #(
 parameter bit PIPELINED_FILL=1'b1,
 parameter bit PREFETCH_A=1'b0,
 parameter logic [31:0] DRAM_BASE=32'h80000000,
 parameter logic [32:0] DRAM_BYTES=33'h004000000
)(
 input logic clk,rst,mode_resident,
 input logic [4:0] next_a_rows,
 input logic [31:0] model_epoch,frame_epoch,task_generation,a_generation,
 input logic [31:0] a_base,b_page_base,
 input logic [5:0] a_rows,input logic [8:0] b_columns,
 input logic [10:0] k_length,input logic [4:0] b_group,
 input logic sched_valid,output logic sched_ready,
 input npu_defs_pkg::npu_dma_job_t sched_job,
 output logic sched_done,sched_error,
 output npu_defs_pkg::npu_error_e sched_error_code,
 output logic physical_valid,input logic physical_ready,
 output npu_defs_pkg::npu_dma_job_t physical_job,
 input logic physical_done,physical_error,
 input npu_defs_pkg::npu_error_e physical_error_code,
 input logic [4:0] outstanding,input logic order_idle,order_poison,
 input logic unpack_valid,output logic unpack_ready,
 input logic [15:0] unpack_row,unpack_col,
 input logic [4:0] unpack_count,input logic [255:0] unpack_data,
 output logic legacy_unpack_enable,
 input logic claim,release_compute,read_valid,input logic [10:0] read_k,
 output logic committed_operands_ready,
 output logic vector_valid,output logic [255:0] a_vector,
 output logic [127:0] b_vector,output logic protocol_poison
);
 import npu_defs_pkg::*;
 typedef enum logic [2:0] {IDLE,LOOKUP,FILL_START,FILL_WAIT,RESPOND,RAW_WAIT,QUARANTINE} state_t;
 state_t state;
 logic selected_b,b_valid_q;
 logic [1:0] a_valid_q;
 logic [255:0] a_key_q[0:1],b_key_q;
 logic background,fill_slot,raw_is_store;
 logic [31:0] fill_a_base,fill_a_generation;
 logic [5:0] fill_a_rows;
 wire [255:0] a_key={model_epoch,frame_epoch,a_generation,task_generation,a_base,
                      32'(k_length),32'd0,32'(a_rows)};
 wire [255:0] b_key={model_epoch,frame_epoch,b_page_base,task_generation,b_page_base,
                      32'(k_length),32'(b_columns),32'd0};
 wire a_hit0=a_valid_q[0]&&a_key_q[0]==a_key;
 wire a_hit1=a_valid_q[1]&&a_key_q[1]==a_key;
 wire current_a_slot=!a_hit0&&a_hit1;
 wire hit=selected_b?(b_valid_q&&b_key_q==b_key):(a_hit0||a_hit1);
 wire [31:0] next_a_base=a_base+(32'(k_length)<<4);
 wire [255:0] next_a_key={model_epoch,frame_epoch,a_generation+32'd16,task_generation,
                         next_a_base,32'(k_length),32'd0,32'(next_a_rows)};
 wire next_a_cached=(a_valid_q[0]&&a_key_q[0]==next_a_key)||
                    (a_valid_q[1]&&a_key_q[1]==next_a_key);
 // Claim proves the current operands are committed and selects a read-only
 // bank. Only the other A slot may be filled. Epoch/base/shape remain exact.
 wire prefetch_launch=PREFETCH_A&&mode_resident&&claim&&
                      next_a_rows!=0&&next_a_rows<=16&&a_rows==16&&
                      !next_a_cached&&!sched_valid&&state==IDLE&&
                      physical_ready&&order_idle&&outstanding==0&&!protocol_poison;
 wire read_job=mode_resident&&sched_job.kind!=DMA_STORE_C;
 logic result_error;
 npu_error_e result_code;
 logic fill_start,fill_ready,fill_busy,fill_done,fill_reused,fill_cancelled,fill_poison;
 npu_error_e fill_error;
 logic fill_job_valid;
 npu_dma_job_t fill_job;
 logic a_begin,b_begin,a_slot,a_begin_ready,b_begin_ready,a_reuse_hit,b_reuse_hit;
 logic [255:0] bank_identity;
 logic [5:0] bank_rows;logic [8:0] bank_columns;logic [10:0] bank_k;
 logic a_commit,b_commit,real_retired,a_abort,b_abort,bank_poison;
 logic pack_start,pack_ready,pack_is_b,pack_abort,pack_abort_retire,pack_retired;
 logic [5:0] pack_rows;logic [8:0] pack_columns;logic [10:0] pack_k;
 logic pack_active,pack_done,pack_aborted,pack_poison;
 logic aw,awr,bw,bwr;logic [4:0] awrow,bwgroup;logic [10:0] awk,bwk;
 logic [127:0] awdata,bwdata,unpack_bytes;
 logic claim_ready,read_ready,compute_active;
 logic [3:0] a_owners;logic [1:0] b_owner;
 for(genvar lane=0;lane<16;lane++)assign unpack_bytes[8*lane+:8]=unpack_data[16*lane+:8];

 // PIPEOPT5: safe local reuse qualification for another N8 group in the
 // SAME descriptor. The actual bank checks READY ownership, full identity,
 // shape and group bounds. Outstanding/adapter checks exclude fills/stores.
 assign committed_operands_ready=mode_resident&&!rst&&
     ((state==IDLE&&physical_ready&&order_idle&&outstanding==0)||background||
      (state==RAW_WAIT&&raw_is_store))&&
     !protocol_poison&&(a_hit0||a_hit1)&&b_valid_q&&(b_key_q==b_key)&&claim_ready;
 assign sched_ready=!rst&&state==IDLE&&physical_ready&&order_idle&&!protocol_poison;
 assign physical_valid=(state==IDLE&&sched_valid&&!read_job&&order_idle&&!protocol_poison)||fill_job_valid;
 assign physical_job=fill_job_valid?fill_job:sched_job;
 assign sched_done=(state==RESPOND&&!result_error)||(state==RAW_WAIT&&physical_done);
 assign sched_error=(state==RESPOND&&result_error)||(state==RAW_WAIT&&physical_error);
 assign sched_error_code=state==RESPOND?result_code:physical_error_code;
 assign fill_start=state==FILL_START;
 assign legacy_unpack_enable=state==RAW_WAIT;
 assign unpack_ready=state==RAW_WAIT?1'b1:pack_input_ready;
 assign protocol_poison=fill_poison||pack_poison||bank_poison||order_poison||state==QUARANTINE;

 npu_resident_fill_owner #(.DRAM_BASE(DRAM_BASE),.DRAM_BYTES(DRAM_BYTES)) owner(
  .clk,.rst,.start_valid(fill_start),.start_ready(fill_ready),.start_is_b(selected_b),.start_a_slot(fill_slot),
  .start_base(selected_b?b_page_base:fill_a_base),.start_model_epoch(model_epoch),.start_frame_epoch(frame_epoch),
  .start_tensor(selected_b?b_page_base:fill_a_generation),.start_generation(task_generation),
  .start_A_rows(fill_a_rows),.start_B_columns(b_columns),.start_K(k_length),.cancel(1'b0),.DMA_exclusive_grant(1'b1),
  .dma_job_valid(fill_job_valid),.dma_job_ready(physical_ready),.dma_job(fill_job),
  .dma_job_done(physical_done),.dma_job_error(physical_error),.dma_error_code(physical_error_code),.dma_outstanding(outstanding),
  .response_order_idle(order_idle),.response_order_poison(order_poison),
  .pack_start,.pack_start_ready(pack_ready),.pack_is_b,.pack_A_rows(pack_rows),.pack_B_columns(pack_columns),.pack_K(pack_k),
  .pack_abort_request(pack_abort),.pack_abort_retire,.pack_real_retired(pack_retired),
  .pack_active,.pack_done,.pack_aborted,.pack_poison,
  .bank_a_begin(a_begin),.bank_b_begin(b_begin),.bank_a_slot(a_slot),.bank_identity,
  .bank_A_rows(bank_rows),.bank_B_columns(bank_columns),.bank_K(bank_k),
  .bank_a_begin_ready(a_begin_ready),.bank_b_begin_ready(b_begin_ready),.bank_a_reuse_hit(a_reuse_hit),.bank_b_reuse_hit(b_reuse_hit),
  .bank_a_commit(a_commit),.bank_b_commit(b_commit),.bank_real_retired(real_retired),.bank_a_abort(a_abort),.bank_b_abort(b_abort),.bank_poison,
  .busy(fill_busy),.done(fill_done),.reused(fill_reused),.cancelled(fill_cancelled),.protocol_poison(fill_poison),.error_code(fill_error));
 logic pack_input_ready;
 npu_resident_fill_pack #(.PIPELINED_FILL(PIPELINED_FILL)) packer(
  .clk,.rst,.start_valid(pack_start),.start_ready(pack_ready),.start_is_b(pack_is_b),
  .start_A_rows(pack_rows),.start_B_columns(pack_columns),.start_K(pack_k),
  .input_valid(unpack_valid&&state==FILL_WAIT),.input_ready(pack_input_ready),
  .input_row(unpack_row),.input_col(unpack_col),.input_count(unpack_count),.input_bytes(unpack_bytes),
  .a_valid(aw),.a_ready(awr),.a_row(awrow),.a_k(awk),.a_word(awdata),
  .b_valid(bw),.b_ready(bwr),.b_group(bwgroup),.b_k(bwk),.b_pair(bwdata),
  .abort_request(pack_abort),.abort_retire(pack_abort_retire),.real_DMA_responses_retired(pack_retired),
  .active(pack_active),.pack_done,.aborted(pack_aborted),.protocol_poison(pack_poison));
 npu_resident_ab #(.A_ROWS_PER_SLOT(16),.B_PAIR_ADDR_W(13)) operands(
  .clk,.rst,.a_begin,.a_slot,.a_identity(bank_identity),.a_rows(bank_rows),.a_k_length(bank_k),.a_begin_ready,.a_reuse_hit,
  .a_write_valid(aw),.a_write_row(awrow),.a_write_k(awk),.a_write_word(awdata),.a_write_ready(awr),
  .a_commit,.a_real_responses_retired(real_retired),.a_abort,
  .b_begin,.b_identity(bank_identity),.b_columns(bank_columns),.b_k_length(bank_k),.b_begin_ready,.b_reuse_hit,
  .b_write_valid(bw),.b_write_group(bwgroup),.b_write_k(bwk),.b_write_pair(bwdata),.b_write_ready(bwr),
  .b_commit,.b_real_responses_retired(real_retired),.b_abort,
  .invalidate_a(1'b0),.invalidate_a_slot(1'b0),.invalidate_b(1'b0),
  .claim,.claim_a_slot(current_a_slot),.claim_m16(1'b0),.claim_n8(b_group),
  // Legacy scratch cleanup walks EMPTY/FILL/READY/COMPUTE independently of
  // whether this physical resident bank was ever claimed. A failed read
  // can therefore clear a virtual B owner without a resident compute lease.
  // Release only an acquired physical lease; real DMA error retirement and
  // bank fill abort/poison rules above are unchanged.
  .expected_a_identity(a_key),.expected_b_identity(b_key),.claim_ready,
  .release_compute(release_compute&&compute_active),
  .read_valid,.read_k,.read_ready,.vector_valid,.a_vector,.b_vector,.compute_active,
  .protocol_poison(bank_poison),.a_owners,.b_owner,.a_words_written(),.b_words_written(),.a_reuse_count(),.b_reuse_count());

 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;selected_b<=0;a_valid_q<=0;b_valid_q<=0;
   a_key_q[0]<=0;a_key_q[1]<=0;b_key_q<=0;
   background<=0;fill_slot<=0;raw_is_store<=0;fill_a_base<=0;fill_a_generation<=0;fill_a_rows<=0;
   result_error<=0;result_code<=ERR_NONE;
  end else if(protocol_poison)state<=QUARANTINE;
  else case(state)
   IDLE:if(sched_valid&&sched_ready)begin
    background<=0;result_error<=0;result_code<=ERR_NONE;
    raw_is_store<=sched_job.kind==DMA_STORE_C;
    if(read_job)begin selected_b<=sched_job.kind==DMA_LOAD_B;state<=LOOKUP;end
    else state<=RAW_WAIT;
   end else if(prefetch_launch)begin
    background<=1;selected_b<=0;fill_slot<=~current_a_slot;
    fill_a_base<=next_a_base;fill_a_generation<=a_generation+32'd16;
    fill_a_rows<={1'b0,next_a_rows};state<=FILL_START;
   end
   LOOKUP:if(hit)state<=RESPOND;else begin
    fill_slot<=current_a_slot;fill_a_base<=a_base;
    fill_a_generation<=a_generation;fill_a_rows<=a_rows;state<=FILL_START;
   end
   FILL_START:if(fill_start&&fill_ready)begin
    if(selected_b)b_valid_q<=0;else a_valid_q[fill_slot]<=0;
    state<=FILL_WAIT;
   end
   FILL_WAIT:if(fill_done)begin
    result_error<=fill_error!=ERR_NONE||fill_cancelled;result_code<=fill_error;
    if(fill_error==ERR_NONE&&!fill_cancelled)begin
     if(selected_b)begin b_valid_q<=1;b_key_q<=b_key;end
     else begin a_valid_q[fill_slot]<=1;a_key_q[fill_slot]<=bank_identity;end
    end
    if(background)begin
     // A failed speculative fill has already drained its genuine responses.
     // Quarantine the enclosing command; never turn it into a cache hit or
     // expose an unsolicited foreground completion.
     background<=0;
     state<=(fill_error!=ERR_NONE||fill_cancelled)?QUARANTINE:IDLE;
    end else state<=RESPOND;
   end
   RESPOND:state<=IDLE;
   RAW_WAIT:if(physical_done||physical_error)state<=IDLE;
   default:state<=QUARANTINE;
  endcase
 end
 // synthesis translate_off
 always_ff @(posedge clk)if(!rst)begin
  if(background && compute_active && fill_slot==current_a_slot)
   $fatal(1,"RESIDENT_PREFETCH_ACTIVE_BANK_RED");
  if(prefetch_launch && !claim_ready)$fatal(1,"RESIDENT_PREFETCH_WITHOUT_CLAIM_RED");
  if(claim&&!claim_ready)$fatal(1,"RESIDENT_ADAPTER_UNCOMMITTED_CLAIM_RED");
  if(read_valid&&!read_ready)$fatal(1,"RESIDENT_ADAPTER_UNOWNED_READ_RED");
  if(mode_resident&&state==RAW_WAIT&&unpack_valid)$fatal(1,"RESIDENT_ADAPTER_RAW_READ_RED");
 end
 // synthesis translate_on
endmodule
