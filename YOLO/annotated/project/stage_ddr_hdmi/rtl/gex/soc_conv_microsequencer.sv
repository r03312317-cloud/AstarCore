// 架构导读：soc_conv_microsequencer。
// 卷积微序列控制，推进行块与通道页，跟踪 Window/NPU 请求完成和 scratch 所有权。
`timescale 1ns/1ps
// Unmerged static-Graph building block. This replaces CPU perM64/N8 command
// preparation; it does not add an array, NPU Scheduler, DMA or DDR interface.
// Existing NPU completion must already imply retirement of every real R/B.
// Window requests use the original eleven configuration words and two slots.
// PIPEOPT4: one Window producer lease may cover four M16 NPU commands.
// Scratch slots are released only after the final consumer completion.
module soc_conv_microsequencer #(
 // 静态配置：parameter integer WINDOW_BATCH_ROWS=64。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer WINDOW_BATCH_ROWS=64
)(
 // 接口声明：input logic clk,rst,start,cancel。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic clk,rst,start,cancel,
 // 接口声明：input logic [31:0] model_epoch,frame_epoch,total_rows。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [31:0] model_epoch,frame_epoch,total_rows,
 // 接口声明：input logic [15:0] columns,k_length,output_width。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [15:0] columns,k_length,output_width,
 // 接口声明：input logic use_window,input_int16。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic use_window,input_int16,
 // 接口声明：input logic [31:0] a_base,b_base,c_base,a_stride,c_stride。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [31:0] a_base,b_base,c_base,a_stride,c_stride,
 // 接口声明：input logic [31:0] a_block_step,c_block_step,b_group_step。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [31:0] a_block_step,c_block_step,b_group_step,
 // 接口声明：input logic [31:0] scratch_base,scratch_stride。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [31:0] scratch_base,scratch_stride,
 // 接口声明：input logic [351:0] window_template。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [351:0] window_template,
 // 接口声明：output logic [31:0] resident_a_generation,resident_b_base。
 // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
 output logic [31:0] resident_a_generation,resident_b_base,
 // 接口声明：output logic [4:0] resident_next_a_rows。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [4:0] resident_next_a_rows,
 // 接口声明：output logic [8:0] resident_b_columns,output logic [4:0] resident_b_group。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [8:0] resident_b_columns,output logic [4:0] resident_b_group,
 // 接口声明：output logic ready,busy,done_pulse,partial_output,protocol_poison,rejected_busy。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic ready,busy,done_pulse,partial_output,protocol_poison,rejected_busy,
 // 接口声明：output logic [7:0] error_code。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 output logic [7:0] error_code,
 // 接口声明：output logic [2:0] error_source,。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 output logic [2:0] error_source, // 0none,1NPU,2Window,3cancel,4plan,5protocol
 // 接口声明：output logic [63:0] completed_MACs。
 // 表达本地完成/结束条件，系统退休还需满足上层接口契约。
 output logic [63:0] completed_MACs,
 // 接口声明：output logic [31:0] command_count,Window_count。
 // 记录数量或剩余进度，位宽限定可表达范围。
 output logic [31:0] command_count,Window_count,
 // 接口声明：output logic npu_cmd_valid,input logic npu_cmd_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 output logic npu_cmd_valid,input logic npu_cmd_ready,
 // 接口声明：output npu_defs_pkg::npu_cmd_t npu_cmd。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output npu_defs_pkg::npu_cmd_t npu_cmd,
 // 接口声明：input logic npu_comp_valid,output logic npu_comp_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic npu_comp_valid,output logic npu_comp_ready,
 // 接口声明：input npu_defs_pkg::npu_completion_t npu_comp。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input npu_defs_pkg::npu_completion_t npu_comp,
 // 接口声明：output logic Window_req_valid,input logic Window_req_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 output logic Window_req_valid,input logic Window_req_ready,
 // 接口声明：output logic [351:0] Window_req_data,output logic [31:0] Window_req_cookie。
 // 把返回信息关联到对应的已接受请求。
 output logic [351:0] Window_req_data,output logic [31:0] Window_req_cookie,
 // 接口声明：input logic Window_rsp_valid,output logic Window_rsp_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic Window_rsp_valid,output logic Window_rsp_ready,
 // 接口声明：input logic [31:0] Window_rsp_cookie,input logic [7:0] Window_rsp_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 input logic [31:0] Window_rsp_cookie,input logic [7:0] Window_rsp_error,
 // 接口声明：input logic Window_rsp_partial。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic Window_rsp_partial
);
 import npu_defs_pkg::*;
 typedef enum logic [3:0] {IDLE,BEGIN_TASK,WAIT_CURRENT,PREP_NEXT,FOLD_X,
   ISSUE,WAIT_COMP,WAIT_NEXT,STEP_M,NEXT_PAGE,DRAIN,FINISH,POISON} state_t;
 state_t state;
 logic [31:0] model_q,frame_q,rows_q,first_q,next_first_q;
 logic [15:0] page_first,page_columns;
 logic [31:0] page_b,page_c,initial_a,initial_c;
 // 局部运算/辅助过程：function automatic logic [15:0] page_limit(input logic [15:0] k,n);。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
 function automatic logic [15:0] page_limit(input logic [15:0] k,n);
  logic [15:0] cap;
  // 条件分支：检查 k<=512。
  if(k<=512)cap=256;else if(k<=576)cap=224;else if(k<=682)cap=192;
  // 条件分支：检查 k<=818。
  else if(k<=818)cap=160;else if(k<=1024)cap=128;else cap=112;
  return n<cap?n:cap;
 endfunction
 assign resident_a_generation=first_q+1;
 assign resident_b_base=page_b;
 assign resident_b_columns=9'(page_columns);
 assign resident_b_group=5'((col_q-page_first)>>3);
 logic [15:0] n_q,k_q,ow_q,count_q,next_count_q,col_q;
 logic [15:0] oy_q,ox_q,next_oy_q;
 logic [31:0] next_ox_q;
 logic window_q,int16_q,slot_q,abort_q,current_ready,next_ready;
 logic [31:0] a_q,b_q,c_q,as_q,cs_q,ab_step_q,cb_step_q,bg_step_q;
 logic [31:0] scratch_q,scratch_step_q,group_b_q,group_c_q;
 logic [351:0] template_q;
 logic batch_q;
 logic [15:0] batch_rows_q,batch_offset_q,next_batch_rows_q;
 logic [31:0] batch_byte_offset_q,next_batch_first_q;
 wire batch_last = !batch_q || (batch_offset_q+count_q>=batch_rows_q);
 // Only prefetch a consumer inside this already completed, still leased
 // Window batch. Never cross into a producer's unfinished scratch slot.
 wire [15:0] rows_in_batch_after=batch_rows_q-batch_offset_q-count_q;
 assign resident_next_a_rows=(batch_q && !batch_last && count_q==16 &&
     !int16_q && !abort_q && !cancel && as_q==32'(k_q)) ?
     (rows_in_batch_after>16?5'd16:5'(rows_in_batch_after)) : 5'd0;
 wire producer_has_next = batch_q ? next_batch_first_q<rows_q : has_next;
 // 局部运算/辅助过程：function automatic logic [15:0] window_rows(input logic [31:0] left_rows);。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
 function automatic logic [15:0] window_rows(input logic [31:0] left_rows);
  return batch_q ? (left_rows>64?16'd64:16'(left_rows)) : limit64(left_rows);
 endfunction
 logic npu_live,Window_live,Window_is_next,cmd_presented;
 logic [31:0] npu_expected_cookie,Window_expected_cookie;
 logic [31:0] npu_sequence,Window_sequence;
 logic any_output_written;
 wire has_next=next_first_q<rows_q;
 // INT8 submits one bounded channel page. The existing single Scheduler
 // executes its N8 groups and owns result capture/real Store retirement.
 // Legacy INT16 retains the original N8 command and scalar result path.
 wire [15:0] group_n=int16_q ? ((n_q-col_q)>16'd8 ? 16'd8 : n_q-col_q) : page_columns;
 wire cmd_fire=npu_cmd_valid&&npu_cmd_ready;
 wire comp_fire=npu_comp_valid&&npu_comp_ready;
 wire Window_response=Window_rsp_valid&&Window_rsp_ready;
 wire known_comp=npu_comp.user_tag==npu_expected_cookie;
 // 局部运算/辅助过程：function automatic logic [15:0] limit64(input logic [31:0] count);。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
 function automatic logic [15:0] limit64(input logic [31:0] count);
  return count>(int16_q?64:16)?(int16_q?16'd64:16'd16):16'(count);
 endfunction
 // 局部运算/辅助过程：function automatic logic [351:0] make_window(input logic [351:0] template_data,。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
 function automatic logic [351:0] make_window(input logic [351:0] template_data,
  // 接口声明：input logic [31:0] scratch,first,input logic [15:0] count,oy,ox。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input logic [31:0] scratch,first,input logic [15:0] count,oy,ox,
  // 接口声明：input logic flush)。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input logic flush);
  logic [351:0] result;
  result=template_data;
  result[1*32+:32]=scratch;result[2*32+:32]=first;
  result[5*32+16+:16]=oy;
  result[6*32+:32]={count,ox};result[10*32+:32]={31'd0,flush};
  return result;
 endfunction
 assign ready=!rst&&state==IDLE&&!protocol_poison&&!npu_comp_valid&&!Window_rsp_valid;
 assign busy=state!=IDLE||protocol_poison;
 // Once presented, a command is held through cancellation until accepted.
 assign npu_cmd_valid=state==ISSUE&&(!abort_q||cmd_presented);
 assign npu_comp_ready=npu_live&&!protocol_poison;
 assign Window_rsp_ready=Window_live&&!protocol_poison;
 // 过程边界：always_comb begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_comb begin
  npu_cmd='0;
  npu_cmd.a_base=window_q?scratch_q+(slot_q?scratch_step_q:32'd0)+batch_byte_offset_q:a_q;
  npu_cmd.b_base=group_b_q;npu_cmd.c_base=group_c_q;
  npu_cmd.m=count_q;npu_cmd.n=group_n;npu_cmd.k=k_q;
  npu_cmd.input_int16=int16_q;npu_cmd.a_stride=as_q;
  npu_cmd.b_stride=32'(group_n)<<(int16_q?1:0);npu_cmd.c_stride=cs_q;
  npu_cmd.output_fmt=2;npu_cmd.clamp_min=32'sh80000000;npu_cmd.clamp_max=32'sh7fffffff;
  npu_cmd.user_tag=npu_sequence;
 end
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  done_pulse<=0;
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin
   batch_q<=0;batch_rows_q<=0;batch_offset_q<=0;next_batch_rows_q<=0;
   batch_byte_offset_q<=0;next_batch_first_q<=0;
   page_first<=0;page_columns<=0;page_b<=0;page_c<=0;initial_a<=0;initial_c<=0;
   state<=IDLE;partial_output<=0;protocol_poison<=0;rejected_busy<=0;
   error_code<=0;error_source<=0;completed_MACs<=0;command_count<=0;Window_count<=0;
   model_q<=0;frame_q<=0;rows_q<=0;first_q<=0;next_first_q<=0;
   n_q<=0;k_q<=0;ow_q<=0;count_q<=0;next_count_q<=0;col_q<=0;
   oy_q<=0;ox_q<=0;next_oy_q<=0;next_ox_q<=0;
   window_q<=0;int16_q<=0;slot_q<=0;abort_q<=0;current_ready<=0;next_ready<=0;
   a_q<=0;b_q<=0;c_q<=0;as_q<=0;cs_q<=0;ab_step_q<=0;cb_step_q<=0;bg_step_q<=0;
   scratch_q<=0;scratch_step_q<=0;group_b_q<=0;group_c_q<=0;template_q<=0;
   npu_live<=0;Window_live<=0;Window_is_next<=0;cmd_presented<=0;
   npu_expected_cookie<=0;Window_expected_cookie<=0;npu_sequence<=1;Window_sequence<=1;
   Window_req_valid<=0;Window_req_data<=0;Window_req_cookie<=0;any_output_written<=0;
  end else begin
   // 条件分支：检查 start&&!ready。
   if(start&&!ready)rejected_busy<=1;
   // 条件分支：检查 cancel&&busy&&!abort_q。
   if(cancel&&busy&&!abort_q)begin
    abort_q<=1;
    // 条件分支：检查 error_source==0。
    if(error_source==0)begin error_source<=3;error_code<=8'he0;end
   end
   // 条件分支：检查 state!=ISSUE。
   if(state!=ISSUE)cmd_presented<=0;
   // 条件分支：检查 npu_cmd_valid。
   else if(npu_cmd_valid)cmd_presented<=1;
   // 握手/背压判断：Window_req_valid&&Window_req_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(Window_req_valid&&Window_req_ready)begin
    // 条件分支：检查 Window_live。
    if(Window_live)begin protocol_poison<=1;state<=POISON;error_source<=5;error_code<=8'he1;end
    Window_req_valid<=0;Window_live<=1;Window_expected_cookie<=Window_req_cookie;
    Window_count<=Window_count+1'b1;
   end
   // 条件分支：检查 Window_response。
   if(Window_response)begin
    // 条件分支：检查 Window_rsp_cookie!=Window_expected_cookie。
    if(Window_rsp_cookie!=Window_expected_cookie)begin
     protocol_poison<=1;state<=POISON;error_source<=5;error_code<=8'he2;
    end else begin
     Window_live<=0;
     // 条件分支：检查 Window_is_next。
     if(Window_is_next)next_ready<=1;else current_ready<=1;
     // 条件分支：检查 Window_rsp_error!=0。
     if(Window_rsp_error!=0)begin
      error_source<=2;error_code<=Window_rsp_error;abort_q<=1;
     end
    end
   end
   if(comp_fire)begin
    if(!known_comp)begin protocol_poison<=1;state<=POISON;error_source<=5;error_code<=8'he3;end
    else begin
     npu_live<=0;
     if(npu_comp.error==ERR_NONE)begin
      completed_MACs<=completed_MACs+npu_comp.macs;any_output_written<=1;
     end else begin
      error_source<=1;error_code<=8'(npu_comp.error);abort_q<=1;
      any_output_written<=any_output_written|npu_comp.partial_output;
     end
    end
   end
   // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case(state)
    // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
    IDLE:if(start&&ready)begin
     model_q<=model_epoch;frame_q<=frame_epoch;rows_q<=total_rows;
     batch_q<=WINDOW_BATCH_ROWS==64&&use_window&&!input_int16&&
              scratch_stride>=(32'(k_length)<<6);
     n_q<=columns;k_q<=k_length;ow_q<=output_width;window_q<=use_window;int16_q<=input_int16;
     initial_a<=a_base;initial_c<=c_base;a_q<=a_base;b_q<=b_base;c_q<=c_base;as_q<=a_stride;cs_q<=c_stride;
     ab_step_q<=a_block_step;cb_step_q<=c_block_step;bg_step_q<=b_group_step;
     scratch_q<=scratch_base;scratch_step_q<=scratch_stride;template_q<=window_template;
     abort_q<=0;partial_output<=0;error_code<=0;error_source<=0;rejected_busy<=0;
     completed_MACs<=0;command_count<=0;Window_count<=0;any_output_written<=0;
     state<=BEGIN_TASK;
    end
    // 状态/选择分支 BEGIN_TASK：本分支规定该编码下的寄存器更新和下一步动作。
    BEGIN_TASK:begin
     if(rows_q==0||rows_q>65535||n_q==0||k_q==0||k_q>1152||
        as_q!=(32'(k_q)<<(int16_q?1:0))||cs_q!=(32'(n_q)<<2)||
        ab_step_q!=(as_q<<6)||cb_step_q!=(cs_q<<6)||bg_step_q!=(32'(k_q)<<(int16_q?4:3))||
        (window_q&&(ow_q==0||int16_q||scratch_q[5:0]!=0||scratch_step_q[5:0]!=0||scratch_step_q<(32'(k_q)<<4))))begin
      error_source<=4;error_code<=8'he4;state<=FINISH;
     end else if(abort_q||cancel)state<=DRAIN;
     else begin
      batch_rows_q<=window_rows(rows_q);batch_offset_q<=0;batch_byte_offset_q<=0;
      first_q<=0;count_q<=limit64(rows_q);col_q<=0;oy_q<=0;ox_q<=0;slot_q<=0;
      page_first<=0;page_columns<=int16_q?n_q:page_limit(k_q,n_q);page_b<=b_q;page_c<=c_q;
      group_b_q<=b_q;group_c_q<=c_q;next_ready<=0;current_ready<=!window_q;
      if(window_q)begin
       Window_req_valid<=1;Window_req_data<=make_window(template_q,scratch_q,0,window_rows(rows_q),0,0,1);
       Window_req_cookie<=Window_sequence;Window_sequence<=Window_sequence+1'b1;
       Window_is_next<=0;state<=WAIT_CURRENT;
      end else state<=PREP_NEXT;
     end
    end
    // 状态/选择分支 WAIT_CURRENT：本分支规定该编码下的寄存器更新和下一步动作。
    WAIT_CURRENT:if(abort_q||cancel)state<=DRAIN;else if(current_ready)state<=PREP_NEXT;
    // 状态/选择分支 PREP_NEXT：本分支规定该编码下的寄存器更新和下一步动作。
    PREP_NEXT:if(abort_q||cancel)state<=DRAIN;else begin
     next_first_q<=first_q+32'(count_q);
     next_count_q<=limit64(rows_q-first_q-32'(count_q));
     if(!batch_q||batch_offset_q==0)begin
      next_batch_first_q<=first_q+32'(batch_rows_q);
      next_batch_rows_q<=window_rows(rows_q-first_q-32'(batch_rows_q));
      next_oy_q<=oy_q;
      next_ox_q<=32'(ox_q)+(batch_q?32'(batch_rows_q):32'(count_q));state<=FOLD_X;
     end else state<=ISSUE;
    end
    // 状态/选择分支 FOLD_X：本分支规定该编码下的寄存器更新和下一步动作。
    FOLD_X:if(abort_q||cancel)state<=DRAIN;
     else if(window_q&&next_ox_q>=32'(ow_q))begin next_ox_q<=next_ox_q-32'(ow_q);next_oy_q<=next_oy_q+1'b1;end
     else state<=ISSUE;
    // 状态/选择分支 ISSUE：本分支规定该编码下的寄存器更新和下一步动作。
    ISSUE:begin
     if(abort_q&&!cmd_presented)state<=DRAIN;
     else if(cmd_fire)begin
      npu_live<=1;npu_expected_cookie<=npu_sequence;npu_sequence<=npu_sequence+1'b1;
      command_count<=command_count+1'b1;state<=(abort_q||cancel)?DRAIN:WAIT_COMP;
      // 握手/背压判断：window_q&&producer_has_next&&(!batch_q||batch_offset_q==0)&&!next_ready&&!Window_live&&!Window_req_valid&&!...。
      // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
      if(window_q&&producer_has_next&&(!batch_q||batch_offset_q==0)&&!next_ready&&!Window_live&&!Window_req_valid&&!abort_q&&!cancel)begin
       Window_req_valid<=1;
       Window_req_data<=make_window(template_q,scratch_q+(slot_q?32'd0:scratch_step_q),batch_q?next_batch_first_q:next_first_q,batch_q?next_batch_rows_q:next_count_q,next_oy_q,16'(next_ox_q),0);
       Window_req_cookie<=Window_sequence;Window_sequence<=Window_sequence+1'b1;Window_is_next<=1;
      end
     end
    end
    // 状态/选择分支 WAIT_COMP：本分支规定该编码下的寄存器更新和下一步动作。
    WAIT_COMP:begin
     if(abort_q||cancel)state<=DRAIN;
     else if(comp_fire&&known_comp)begin
      if(npu_comp.error!=ERR_NONE)state<=DRAIN;
      // 复位相关判断：col_q+group_n<page_first+page_columns；分支方向由信号极性与取反表达式决定。
      else if(col_q+group_n<page_first+page_columns)begin
       col_q<=col_q+group_n;group_b_q<=group_b_q+bg_step_q;group_c_q<=group_c_q+32'd32;state<=ISSUE;
      end else if(has_next)state<=window_q&&batch_last&&!next_ready?WAIT_NEXT:STEP_M;
      // 复位相关判断：page_first+page_columns<n_q；分支方向由信号极性与取反表达式决定。
      else if(page_first+page_columns<n_q)state<=NEXT_PAGE;
      else state<=FINISH;
     end
    end
    // 状态/选择分支 WAIT_NEXT：本分支规定该编码下的寄存器更新和下一步动作。
    WAIT_NEXT:if(abort_q||cancel)state<=DRAIN;else if(next_ready)state<=STEP_M;
    // 状态/选择分支 STEP_M：本分支规定该编码下的寄存器更新和下一步动作。
    STEP_M:if(abort_q||cancel)state<=DRAIN;else begin
     first_q<=next_first_q;count_q<=next_count_q;
     if(batch_q&&!batch_last)begin
      batch_offset_q<=batch_offset_q+count_q;
      batch_byte_offset_q<=batch_byte_offset_q+(as_q<<4);
     end else begin
      oy_q<=next_oy_q;ox_q<=16'(next_ox_q);slot_q<=!slot_q;
      batch_offset_q<=0;batch_byte_offset_q<=0;batch_rows_q<=next_batch_rows_q;
      next_ready<=0;
     end
     a_q<=a_q+(int16_q?ab_step_q:(ab_step_q>>2));
     c_q<=c_q+(int16_q?cb_step_q:(cb_step_q>>2));
     group_c_q<=c_q+(int16_q?cb_step_q:(cb_step_q>>2))+(32'(page_first)<<2);
     group_b_q<=page_b;col_q<=page_first;
     state<=PREP_NEXT;
    end
    // 状态/选择分支 NEXT_PAGE：本分支规定该编码下的寄存器更新和下一步动作。
    NEXT_PAGE:if(abort_q||cancel)state<=DRAIN;else begin
     page_first<=page_first+page_columns;
     page_columns<=page_limit(k_q,n_q-page_first-page_columns);
     page_b<=page_b+32'(page_columns)*32'(k_q);
     page_c<=page_c+(32'(page_columns)<<2);
     group_b_q<=page_b+32'(page_columns)*32'(k_q);
     group_c_q<=page_c+(32'(page_columns)<<2);
     a_q<=initial_a;c_q<=initial_c;first_q<=0;count_q<=limit64(rows_q);
     batch_rows_q<=window_rows(rows_q);batch_offset_q<=0;batch_byte_offset_q<=0;
     col_q<=page_first+page_columns;oy_q<=0;ox_q<=0;slot_q<=0;
     next_ready<=0;current_ready<=!window_q;
     if(window_q)begin
      Window_req_valid<=1;Window_req_data<=make_window(template_q,scratch_q,0,window_rows(rows_q),0,0,1);
      Window_req_cookie<=Window_sequence;Window_sequence<=Window_sequence+1'b1;
      Window_is_next<=0;state<=WAIT_CURRENT;
     end else state<=PREP_NEXT;
    end
    // 状态/选择分支 DRAIN：本分支规定该编码下的寄存器更新和下一步动作。
    DRAIN:if(!npu_live&&!Window_live&&!Window_req_valid)begin partial_output<=any_output_written;state<=FINISH;end
    // 状态/选择分支 FINISH：本分支规定该编码下的寄存器更新和下一步动作。
    FINISH:begin
     if(npu_live||Window_live||Window_req_valid||npu_comp_valid||Window_rsp_valid)begin protocol_poison<=1;state<=POISON;error_source<=5;error_code<=8'he5;end
     else begin done_pulse<=1;partial_output<=error_source!=0&&any_output_written;state<=IDLE;end
    end
    POISON:;
    default:begin protocol_poison<=1;error_source<=5;error_code<=8'he6;state<=POISON;end
   endcase
   // A protocol mismatch can never be overwritten by a normal-state step.
   if((Window_response&&Window_rsp_cookie!=Window_expected_cookie)||(comp_fire&&!known_comp))begin state<=POISON;done_pulse<=0;end
   if(busy&&state!=POISON&&((npu_comp_valid&&!npu_live&&!cmd_fire)||
      (Window_rsp_valid&&!Window_live&&!(Window_req_valid&&Window_req_ready))))begin
    protocol_poison<=1;state<=POISON;done_pulse<=0;error_source<=5;error_code<=8'he7;
   end
  end
 end
 // Simulation assertions only, absent from PDS logic.
 // synthesis translate_off
 initial if(WINDOW_BATCH_ROWS!=16&&WINDOW_BATCH_ROWS!=64)$fatal(1,"GEX_BAD_BATCH_ROWS");
 // 过程边界：always_ff @(posedge clk)if(!rst)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)if(!rst)begin
  if(cmd_fire&&batch_q&&(count_q>16||batch_offset_q+count_q>batch_rows_q||batch_byte_offset_q!=32'(batch_offset_q)*32'(k_q)))
   $fatal(1,"GEX_BATCH_CONSUMER_RANGE_RED");
  if(state==STEP_M&&window_q&&batch_last&&!next_ready&&!abort_q&&!cancel)
   $fatal(1,"GEX_BATCH_SWAP_BEFORE_PRODUCER_RETIRED_RED");
  if(cmd_fire&&npu_live)$fatal(1,"GEX_DUPLICATE_NPU_OWNER_RED");
  // 握手/背压判断：Window_req_valid&&Window_req_ready&&Window_live。
  // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
  if(Window_req_valid&&Window_req_ready&&Window_live)$fatal(1,"GEX_DUPLICATE_WINDOW_OWNER_RED");
  if(done_pulse&&(npu_live||Window_live||Window_req_valid))$fatal(1,"GEX_COMPLETED_WITH_LIVE_OWNER_RED");
 end
 // synthesis translate_on
endmodule
