// 架构导读：npu_resident_fill_pack。
// 把 DMA 返回元素打包为驻留存储的写入向量。
`timescale 1ns/1ps
// Adapter for the ONE existing DMA's ordered, genuine response-unpack stream.
// A: merge beat-split vectors into whole16byte K words (including K108).
// B: load originalpacked weights as one contiguous byte stream; pad lanes
// locally. EvenK/full8-column groups use wholeword pairs. OddK/tails use a
// bounded byte parser. This module issues noDDR request and acknowledges none.
// Bank commit is the enclosing owner's job AFTER both pack_done and actual
// DMA/response-order retirement. A cancel drains/discards the existing job.
module npu_resident_fill_pack #(parameter bit PIPELINED_FILL=1'b1)(
 // 接口声明：input logic clk,rst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic clk,rst,
 // 接口声明：input logic start_valid,output logic start_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic start_valid,output logic start_ready,
 // 接口声明：input logic start_is_b,input logic [5:0] start_A_rows。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic start_is_b,input logic [5:0] start_A_rows,
 // 接口声明：input logic [8:0] start_B_columns,input logic [10:0] start_K。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [8:0] start_B_columns,input logic [10:0] start_K,
 // 接口声明：input logic input_valid,output logic input_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic input_valid,output logic input_ready,
 // 接口声明：input logic [15:0] input_row,input_col。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [15:0] input_row,input_col,
 // 接口声明：input logic [4:0] input_count,input logic [127:0] input_bytes。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [4:0] input_count,input logic [127:0] input_bytes,
 // 接口声明：output logic a_valid,input logic a_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 output logic a_valid,input logic a_ready,
 // 接口声明：output logic [4:0] a_row,output logic [10:0] a_k。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [4:0] a_row,output logic [10:0] a_k,
 // 接口声明：output logic [127:0] a_word。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [127:0] a_word,
 // 接口声明：output logic b_valid,input logic b_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 output logic b_valid,input logic b_ready,
 // 接口声明：output logic [4:0] b_group,output logic [10:0] b_k。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [4:0] b_group,output logic [10:0] b_k,
 // 接口声明：output logic [127:0] b_pair。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [127:0] b_pair,
 input logic abort_request,abort_retire,real_DMA_responses_retired,
 output logic active,pack_done,aborted,protocol_poison
);
 logic mode_b,cancel_q,out_valid,out_final;
 logic [5:0] nr;
 logic [8:0] nc;
 logic [10:0] kl;
 logic [15:0] expected_row,expected_col;
 logic [127:0] a_partial,raw,pair_partial,out_word;
 logic [4:0] raw_count;
 logic [10:0] bk_row;
 logic [4:0] bg,out_row_or_group;
 logic [3:0] bc;
 logic [10:0] out_k;
 wire output_ready=mode_b?b_ready:a_ready;
 wire output_fire=out_valid&&output_ready;
 wire draining=cancel_q||abort_request||protocol_poison;
 assign start_ready=!rst&&!active&&!out_valid&&!protocol_poison;
 // Refill the existing output register on the same edge it retires.
 // Never admit an extra beat while a final output token is retiring.
 // No combinational payload bypass: output remains registered and stable
 // under bank backpressure, and all DMA responses still retire normally.
 wire output_space=!out_valid||(PIPELINED_FILL&&output_ready&&!out_final);
 assign input_ready=!rst&&active&&output_space&&(draining||!mode_b||raw_count==0);
 wire input_fire=input_valid&&input_ready;
 assign a_valid=!rst&&out_valid&&!mode_b;
 assign b_valid=!rst&&out_valid&&mode_b;
 assign a_row=out_row_or_group;assign b_group=out_row_or_group;
 assign a_k=out_k;assign b_k=out_k;
 assign a_word=out_word;assign b_pair=out_word;
 wire [5:0] a_end_in_word={2'd0,input_col[3:0]}+{1'b0,input_count};
 wire [16:0] a_next_col={1'b0,input_col}+17'(input_count);
 wire [8:0] b_remaining_columns=nc-{bg,3'd0};
 wire [3:0] b_group_columns=b_remaining_columns>8?4'd8:4'(b_remaining_columns);
 wire b_last_group=b_remaining_columns<=8;
 wire b_fast=b_group_columns==8&&!kl[0];
 wire [127:0] a_shifted=input_bytes<<{input_col[3:0],3'd0};
 logic [127:0] a_merged,pair_merged;
 // 过程边界：always_comb begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_comb begin
  a_merged=a_partial;
  // Only sixteen fixed destination bytes. No arbitrary payload RAM write
  // ports or wholebank clear. DMA vectors never cross a local16byte word.
  for(integer lane=0;lane<16;lane++)
   if(lane>=int'(input_col[3:0])&&lane<int'(a_end_in_word))
    a_merged[lane*8+:8]=a_shifted[lane*8+:8];
  pair_merged=pair_partial;
  pair_merged[{bk_row[0],bc[2:0],3'b000}+:8]=raw[7:0];
 end
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  pack_done<=0;aborted<=0;
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin
   active<=0;mode_b<=0;cancel_q<=0;out_valid<=0;out_final<=0;
   nr<=0;nc<=0;kl<=0;expected_row<=0;expected_col<=0;
   a_partial<=0;raw<=0;pair_partial<=0;raw_count<=0;bk_row<=0;bg<=0;bc<=0;
   out_word<=0;out_row_or_group<=0;out_k<=0;protocol_poison<=0;
  end else begin
   // 握手/背压判断：start_valid&&start_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(start_valid&&start_ready)begin
    if(start_K==0||start_K>1152||(!start_is_b&&(start_A_rows==0||start_A_rows>16))||
       (start_is_b&&(start_B_columns==0||start_B_columns>256)))protocol_poison<=1;
    else begin
     active<=1;mode_b<=start_is_b;nr<=start_A_rows;nc<=start_B_columns;kl<=start_K;
     cancel_q<=0;expected_row<=0;expected_col<=0;a_partial<=0;pair_partial<=0;
     raw_count<=0;bk_row<=0;bg<=0;bc<=0;out_final<=0;
    end
   end
   if(active&&abort_request)cancel_q<=1;
   if(output_fire)begin
    out_valid<=0;
    if(out_final&&!draining)begin active<=0;raw_count<=0;pack_done<=1;end
   end
   if(input_fire)begin
    if(draining)raw_count<=0;
    else if(mode_b)begin
     // The existing DMA loads rows of16bytes with stride16. Fullrow metadata
     // is observed BEFORE its oldscratch tuple is truncated. Lastbeat padding
     // is never consumed after the true N*K stream ends.
     if(input_col!=0||input_row!=expected_row||input_count!=16)begin
      protocol_poison<=1;cancel_q<=1;
     end else begin
      expected_row<=expected_row+1'b1;
      if(PIPELINED_FILL&&b_fast)begin
       // An aligned 16-byte full-eight-column / even-K vector is already
       // exactly one pair. Capture it directly, skipping the serial raw
       // register phase; tail columns and odd K retain the byte parser.
       if(bk_row[0]||bc!=0)begin protocol_poison<=1;cancel_q<=1;end
       else begin
        out_word<=input_bytes;out_row_or_group<=bg;out_k<=bk_row;out_valid<=1;
        out_final<=bk_row+12'd2>={1'b0,kl}&&b_last_group;raw_count<=0;
        if(bk_row+12'd2>={1'b0,kl})begin bk_row<=0;bg<=bg+1'b1;end
        else bk_row<=bk_row+11'd2;
       end
      end else begin raw<=input_bytes;raw_count<=16;end
     end
    end else begin
     if(input_row!=expected_row||input_col!=expected_col||input_count==0||
        input_count>16||a_end_in_word>16||a_next_col>{6'd0,kl})begin
      protocol_poison<=1;cancel_q<=1;
     end else begin
      a_partial<=a_merged;
      if(a_end_in_word==16||a_next_col=={6'd0,kl})begin
       out_word<=a_merged;out_row_or_group<=input_row[4:0];out_k<={input_col[10:4],4'd0};
       out_valid<=1;out_final<=a_next_col=={6'd0,kl}&&input_row+1'b1==nr;
       a_partial<=0;
      end
      if(a_next_col=={6'd0,kl})begin expected_col<=0;expected_row<=expected_row+1'b1;end
      else expected_col<=16'(a_next_col);
     end
    end
   end
   if(active&&mode_b&&output_space&&raw_count!=0&&!draining)begin
    if(b_fast)begin
     if(raw_count!=16||bk_row[0]||bc!=0)begin protocol_poison<=1;cancel_q<=1;end
     else begin
      out_word<=raw;out_row_or_group<=bg;out_k<=bk_row;out_valid<=1;
      out_final<=bk_row+12'd2>={1'b0,kl}&&b_last_group;raw_count<=0;
      if(bk_row+12'd2>={1'b0,kl})begin bk_row<=0;bg<=bg+1'b1;end
      else bk_row<=bk_row+11'd2;
     end
    end else begin
     // Fixed8bit shift and at most16byte pair register. This slow fallback
     // covers oddK and all narrow tails without reading fake8-column rows.
     raw<={8'd0,raw[127:8]};raw_count<=raw_count-1'b1;pair_partial<=pair_merged;
     if(bc+1'b1>=b_group_columns)begin
      bc<=0;
      if(bk_row[0]||bk_row+12'd1>={1'b0,kl})begin
       out_word<=pair_merged;out_row_or_group<=bg;out_k<={bk_row[10:1],1'b0};
       out_valid<=1;out_final<=bk_row+12'd1>={1'b0,kl}&&b_last_group;pair_partial<=0;
      end
      if(bk_row+12'd1>={1'b0,kl})begin bk_row<=0;bg<=bg+1'b1;end
      else bk_row<=bk_row+1'b1;
     end else bc<=bc+1'b1;
    end
   end
   // Abort may retire only after genuine DMA responses and any committed
   // bank token have drained. A malformed/unknownR/B remains sticky poison.
   if(abort_retire)begin
    // 握手/背压判断：!active||!draining||!real_DMA_responses_retired||(out_valid&&!output_ready)。
    // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
    if(!active||!draining||!real_DMA_responses_retired||(out_valid&&!output_ready))protocol_poison<=1;
    else begin active<=0;out_valid<=0;raw_count<=0;aborted<=1;end
   end
  end
 end
endmodule
