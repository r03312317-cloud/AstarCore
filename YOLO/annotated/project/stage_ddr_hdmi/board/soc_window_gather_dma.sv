// 架构导读：soc_window_gather_dma。
// 从输入张量采集卷积窗口并写入 scratch，维护边界填充和传输完成。
`timescale 1ns/1ps
// Model-oriented HWC im2col gather into the existing A scratch tile.
//
// One 128-bit native request may be outstanding. A 16 KiB direct-mapped
// source cache reuses pixels across neighboring windows; zero-pad tokens never
// touch DDR. The caller holds all shape/address inputs stable while busy and
// asserts flush_cache on the first tile whenever the input layer changes.
// A later integration stage arbitrates this port with S3 before rq_to_axi.
module soc_window_gather_dma #(
    // 静态配置：parameter logic [31:0] DDR_BASE=32'h8000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BASE=32'h8000_0000,
    // 静态配置：parameter logic [31:0] DDR_BYTES=32'h0400_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BYTES=32'h0400_0000,
    // 静态配置：parameter bit VECTOR16_ENABLE=1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit VECTOR16_ENABLE=1'b1,
    // 静态配置：parameter bit RGB6_SPAN_ENABLE=1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit RGB6_SPAN_ENABLE=1'b1,
    // 静态配置：parameter bit EARLY_CACHE_LOOKUP=1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit EARLY_CACHE_LOOKUP=1'b1,
    // 静态配置：parameter bit WRITE_BURST_ENABLE=1'b0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit WRITE_BURST_ENABLE=1'b0,
    // PIPEOPT4: native-burst capability is tied to the existing board switch.
    parameter bit CACHE_FILL_BURST_ENABLE=1'b1,
    // 静态配置：parameter bit VECTOR_DIRECT_ENABLE=1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit VECTOR_DIRECT_ENABLE=1'b1,
    // 静态配置：parameter bit RGB_SPAN_PACK_ENABLE=1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit RGB_SPAN_PACK_ENABLE=1'b1,
    // 静态配置：parameter bit INCREMENTAL_ADDR_ENABLE=1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit INCREMENTAL_ADDR_ENABLE=1'b1
)(
    // 接口声明：input logic clk,rst,start,flush_cache。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic clk,rst,start,flush_cache,
    // 接口声明：input logic [31:0] input_base,scratch_base,first_row。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic [31:0] input_base,scratch_base,first_row,
    // 接口声明：input logic [15:0] input_h,input_w,input_c,output_h,output_w。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [15:0] input_h,input_w,input_c,output_h,output_w,
    // 接口声明：input logic [15:0] first_oy,first_ox。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic [15:0] first_oy,first_ox,
    // 接口声明：input logic [7:0] kernel_h,kernel_w,stride_h,stride_w。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [7:0] kernel_h,kernel_w,stride_h,stride_w,
    // 接口声明：input logic [7:0] dilation_h,dilation_w。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [7:0] dilation_h,dilation_w,
    // 接口声明：input logic [7:0] pad_top,pad_left,pad_bottom,pad_right。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [7:0] pad_top,pad_left,pad_bottom,pad_right,
    // 接口声明：input logic [15:0] row_count。
    // 记录数量或剩余进度，位宽限定可表达范围。
    input logic [15:0] row_count,
    // 接口声明：output logic ready,busy,done_pulse,partial_output。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic ready,busy,done_pulse,partial_output,
    // 接口声明：output logic [7:0] error_sticky。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [7:0] error_sticky,
    // 接口声明：output logic [31:0] source_read_bytes,scratch_write_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] source_read_bytes,scratch_write_bytes,
    // 接口声明：output logic [31:0] cache_hits,cache_misses。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] cache_hits,cache_misses,
    // 接口声明：output logic [31:0] active_cycles,stall_cycles。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] active_cycles,stall_cycles,
    // 接口声明：output logic dma_req_valid,input logic dma_req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic dma_req_valid,input logic dma_req_ready,
    // 接口声明：output logic dma_req_write,output logic [31:0] dma_req_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic dma_req_write,output logic [31:0] dma_req_addr,
    // 接口声明：output logic [127:0] dma_req_wdata,output logic [15:0] dma_req_wstrb。
    // 按字节选择本次写入生效的 lane。
    output logic [127:0] dma_req_wdata,output logic [15:0] dma_req_wstrb,
    // 接口声明：output logic [3:0] dma_req_id,output logic [3:0] dma_req_len。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [3:0] dma_req_id,output logic [3:0] dma_req_len,
    // 接口声明：input logic dma_rsp_last,。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic dma_rsp_last, // final read beat; write packet completes on one real B
    // 接口声明：input logic dma_rsp_valid,output logic dma_rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic dma_rsp_valid,output logic dma_rsp_ready,
    // 接口声明：input logic dma_rsp_write,input logic [3:0] dma_rsp_id。
    // 把返回信息关联到对应的已接受请求。
    input logic dma_rsp_write,input logic [3:0] dma_rsp_id,
    // 接口声明：input logic [127:0] dma_rsp_rdata,input logic dma_rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    input logic [127:0] dma_rsp_rdata,input logic dma_rsp_error
);
    wire line_fill=WRITE_BURST_ENABLE && CACHE_FILL_BURST_ENABLE;
    wire direct_vector=WRITE_BURST_ENABLE && VECTOR_DIRECT_ENABLE && vector16;
    logic [31:0] source_low_q,source_high_q;
    logic [31:0] fill_base_q,fill_addr_q;
    logic [2:0] fill_words_q;
    wire [31:0] line64_start={source_addr_q[31:6],6'b0};
    wire [31:0] refill_start=line64_start<source_low_q?source_low_q:line64_start;
    wire [31:0] refill_end=(line64_start+32'd64)>source_high_q?source_high_q:(line64_start+32'd64);
    wire cache_hit=cache_valid_q && cache_tag_q==source_tag;
    wire read_ok=dma_rsp_valid && !dma_rsp_write && dma_rsp_id==TAG && !dma_rsp_error;
    wire read_last=!line_fill || dma_rsp_last;
    wire [127:0] fetched_word=(fill_addr_q==cache_line_addr)?dma_rsp_rdata:cache_word_q;
    wire vector_commit=direct_vector && gen_valid &&
        ((state==TOKEN && gen_zero && gen_scratch==scratch_base+emitted_q) ||
         (state==DECIDE && cache_hit) ||
         (state==READ_RSP && read_ok && read_last));
    wire vector16=VECTOR16_ENABLE && input_c[3:0]==0 && input_base[3:0]==0;
    wire rgb_span=RGB6_SPAN_ENABLE && input_c==3 && kernel_h==6 && kernel_w==6 &&
        stride_h==2 && stride_w==2 && dilation_h==1 && dilation_w==1 &&
        pad_top==2 && pad_left==2 && pad_bottom==2 && pad_right==2 &&
        input_w[0]==0 && input_h[0]==0 && input_base[3:0]==0 && scratch_base[3:0]==0;
    wire span_active=vector16||rgb_span;
    wire rgb_direct=WRITE_BURST_ENABLE && RGB_SPAN_PACK_ENABLE && rgb_span;
    wire rgb_commit=rgb_direct && gen_valid &&
        ((state==TOKEN && gen_zero && gen_scratch==scratch_base+emitted_q) ||
         (state==DECIDE && cache_hit) ||
         (state==READ_RSP && read_ok && read_last));
    wire [4:0] next_write_count={1'b0,write_lane}+gen_bytes;
    wire [2:0] rotate_pairs=source_addr_q[3:1]-write_lane[3:1];
    wire [255:0] doubled_cache_word={cache_word_q,cache_word_q};
    logic [127:0] rotated_word_q;
    logic [4:0] gen_bytes;
    // 静态配置：localparam int CACHE_LINES=1024。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam int CACHE_LINES=1024;
    // 静态配置：localparam logic [3:0] TAG=4'h1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [3:0] TAG=4'h1;
    typedef enum logic [3:0] {
        IDLE,CLEAR,LAUNCH,TOKEN,LOOKUP,DECIDE,READ_REQ,READ_RSP,
        COLLECT,WRITE_REQ,WRITE_RSP,ROTATE,QUEUE_WORD,BURST_LOAD,BURST_SEND
    } state_t;
    state_t state;
    (* ram_style="block", syn_ramstyle="block_ram" *) logic [127:0] cache_data [0:CACHE_LINES-1];
    (* ram_style="block", syn_ramstyle="block_ram" *) logic [17:0] cache_tag [0:CACHE_LINES-1];
    logic cache_valid [0:CACHE_LINES-1];
    logic [9:0] clear_index;
    logic clear_launch_q;
    logic cache_layer_ok_q;
    logic [127:0] cache_word_q;
    logic [17:0] cache_tag_q;
    logic cache_valid_q;
    logic [31:0] source_addr_q,write_addr_q,emitted_q;
    logic [7:0] byte_q;
    logic [127:0] write_buffer;
    logic [15:0] write_strobe_q;
    logic [4:0] write_count_q;
    logic [3:0] write_lane;
    logic write_last_q;
    // Stage a complete contiguous write packet before reserving native bus.
    // A cache miss can therefore never deadlock behind a half-filled packet.
    logic [127:0] burst_words[0:15];
    logic [15:0] burst_masks[0:15];
    logic [3:0] queued_words,send_word;
    logic [4:0] burst_count;
    logic [8:0] queued_bytes,burst_bytes;
    logic [31:0] burst_base;
    logic burst_last;
    logic [127:0] burst_data_q;
    logic [15:0] burst_mask_q;
    logic gen_ready,gen_busy,gen_done,gen_valid,gen_zero,gen_last;
    // One-entry elastic token register cuts the measured address-generator
    // to RGB pack/DDR burst-RAM setup path. The slot can pop and refill on
    // the same cycle; under backpressure the complete token remains stable.
    logic agen_valid,agen_ready,agen_zero,agen_last;
    logic [31:0] agen_source,agen_scratch;
    logic [4:0] agen_bytes;
    logic gen_reset_q;
    logic [7:0] gen_error;
    logic [31:0] gen_source,gen_scratch;
    logic gen_out_ready;
    logic [31:0] cache_line_addr;
    logic [9:0] cache_index;
    logic [17:0] source_tag;

    // 组合连接 ready：表达接口或资源就绪；需结合相应有效/完成条件解释。
    assign ready=!rst && state==IDLE && gen_ready;
    // 组合连接 busy：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign busy=state!=IDLE;
    // 组合连接 cache_line_addr：用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    assign cache_line_addr={source_addr_q[31:4],4'b0};
    // 组合连接 cache_index：选择队列、数组或数据片段的位置，更新条件见对应赋值。
    assign cache_index=source_addr_q[13:4];
    // 组合连接 source_tag：把返回信息关联到对应的已接受请求。
    assign source_tag=source_addr_q[31:14];
    assign gen_out_ready=state==COLLECT || vector_commit || rgb_commit;
    assign dma_req_valid=state==READ_REQ || state==WRITE_REQ || state==BURST_SEND;
    assign dma_req_write=state==WRITE_REQ || state==BURST_SEND;
    assign dma_req_addr=state==BURST_SEND?burst_base+{24'd0,send_word,4'd0}:
        (state==WRITE_REQ?write_addr_q:(line_fill?fill_base_q:cache_line_addr));
    assign dma_req_wdata=state==BURST_SEND?burst_data_q:write_buffer;
    assign dma_req_wstrb=state==BURST_SEND?burst_mask_q:(state==WRITE_REQ?write_strobe_q:16'd0);
    assign dma_req_len=state==READ_REQ && line_fill ? 4'(fill_words_q-1'b1) :
        (state==BURST_SEND&&send_word==0?4'(burst_count-1'b1):4'd0);
    assign dma_req_id=TAG;
    assign dma_rsp_ready=state==READ_RSP || state==WRITE_RSP;

    soc_window_address_gen #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES),.VECTOR16_ENABLE(VECTOR16_ENABLE),.RGB6_SPAN_ENABLE(RGB6_SPAN_ENABLE),.INCREMENTAL_PIXEL_INDEX(INCREMENTAL_ADDR_ENABLE))
        address_gen(
            .clk,.rst(rst || gen_reset_q),.start(state==LAUNCH),
            .input_base,.scratch_base,.first_row,
            .input_h,.input_w,.input_c,.output_h,.output_w,
            .first_oy,.first_ox,.kernel_h,.kernel_w,.stride_h,.stride_w,
            .dilation_h,.dilation_w,
            .pad_top,.pad_left,.pad_bottom,.pad_right,.row_count,
            .ready(gen_ready),.busy(gen_busy),.done_pulse(gen_done),
            .error_sticky(gen_error),.out_valid(agen_valid),
            .out_ready(agen_ready),.out_zero(agen_zero),
            .out_source_addr(agen_source),.out_scratch_addr(agen_scratch),
            .out_bytes(agen_bytes),.out_last(agen_last)
        );

    assign agen_ready=!gen_valid || gen_out_ready;
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst || gen_reset_q；分支方向由信号极性与取反表达式决定。
        if(rst || gen_reset_q) begin
            gen_valid<=1'b0;
            gen_zero<=1'b0;gen_last<=1'b0;
            gen_source<=0;gen_scratch<=0;gen_bytes<=0;
        // 条件分支：检查 agen_ready。
        end else if(agen_ready) begin
            gen_valid<=agen_valid;
            // 条件分支：检查 agen_valid。
            if(agen_valid) begin
                gen_zero<=agen_zero;gen_last<=agen_last;
                gen_source<=agen_source;gen_scratch<=agen_scratch;gen_bytes<=agen_bytes;
            end
        end
    end

    // Full vector tokens already have the final 16-byte layout. Append them
    // directly instead of COLLECT -> QUEUE_WORD. The native bus is reserved
    // only AFTER a packet is complete, so a cache refill cannot deadlock it.
    task automatic enqueue_vector(input logic [127:0] data);
        burst_words[queued_words]<=data;
        burst_masks[queued_words]<=16'hffff;
        // 条件分支：检查 queued_words==0。
        if(queued_words==0)burst_base<=gen_scratch;
        queued_bytes<=queued_bytes+9'd16;
        emitted_q<=emitted_q+32'd16;
        // 条件分支：检查 queued_words==15 || gen_last || gen_scratch[11:4]==8'hff。
        if(queued_words==15 || gen_last || gen_scratch[11:4]==8'hff)begin
            burst_count<={1'b0,queued_words}+5'd1;
            burst_bytes<=queued_bytes+9'd16;
            burst_last<=gen_last;send_word<=0;state<=BURST_LOAD;
        end else begin
            queued_words<=queued_words+1'b1;state<=TOKEN;
        end
    endtask

    // PIPEOPT5: the RGB6 generator proves that a token is even-sized and
    // lies within one source and one destination word. A bounded 16-bit-lane
    // rotate plus mask merges it on the cache hit/last-refill edge. The
    // resulting complete word is queued immediately (no ROTATE/COLLECT/
    // QUEUE_WORD bubbles). Native bus is still reserved only for full packets.
    task automatic collect_rgb(input logic [127:0] data, input logic zero);
        logic [255:0] doubled;
        logic [127:0] rotated,merged;
        logic [15:0] mask;
        doubled={data,data};
        rotated=doubled[16*rotate_pairs+:128];
        merged=write_buffer;
        for(integer lane=0;lane<8;lane++)
            // 条件分支：检查 5'(lane*2)>={1'b0,write_lane} && 5'(lane*2)<next_write_count。
            if(5'(lane*2)>={1'b0,write_lane} && 5'(lane*2)<next_write_count)
                merged[lane*16+:16]=zero?16'd0:rotated[lane*16+:16];
        emitted_q<=emitted_q+32'(gen_bytes);
        // 条件分支：检查 next_write_count==16 || gen_last。
        if(next_write_count==16 || gen_last) begin
            mask=16'hffff>>(5'd16-next_write_count);
            burst_words[queued_words]<=merged;burst_masks[queued_words]<=mask;
            // 条件分支：检查 queued_words==0。
            if(queued_words==0)burst_base<={gen_scratch[31:4],4'b0};
            queued_bytes<=queued_bytes+9'(next_write_count);
            write_buffer<=0;write_lane<=0;
            // 条件分支：检查 queued_words==15 || gen_last || gen_scratch[11:4]==8'hff。
            if(queued_words==15 || gen_last || gen_scratch[11:4]==8'hff) begin
                burst_count<={1'b0,queued_words}+5'd1;
                burst_bytes<=queued_bytes+9'(next_write_count);
                burst_last<=gen_last;send_word<=0;state<=BURST_LOAD;
            end else begin queued_words<=queued_words+1'b1;state<=TOKEN;end
        end else begin write_buffer<=merged;write_lane<=next_write_count[3:0];state<=TOKEN;end
    endtask

    // Only the cache-valid plane needs initialization. Data/tag RAM contents
    // are never examined unless that line has been filled since the sweep.
    always_ff @(posedge clk) begin
        done_pulse<=1'b0;
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst) begin
            state<=CLEAR;clear_index<=0;clear_launch_q<=0;
            source_low_q<=0;source_high_q<=0;fill_base_q<=0;fill_addr_q<=0;fill_words_q<=1;
            cache_layer_ok_q<=0;gen_reset_q<=0;
            error_sticky<=0;partial_output<=0;source_read_bytes<=0;
            scratch_write_bytes<=0;cache_hits<=0;cache_misses<=0;
            active_cycles<=0;stall_cycles<=0;
            cache_word_q<=0;cache_tag_q<=0;cache_valid_q<=0;
            source_addr_q<=0;write_addr_q<=0;emitted_q<=0;byte_q<=0;
            write_buffer<=0;write_strobe_q<=0;write_count_q<=0;
            write_lane<=0;write_last_q<=0;
            queued_words<=0;send_word<=0;burst_count<=0;queued_bytes<=0;burst_bytes<=0;
            burst_base<=0;burst_last<=0;burst_data_q<=0;burst_mask_q<=0;
        end else begin
            gen_reset_q<=0;
            // 条件分支：检查 start && !ready。
            if(start && !ready) error_sticky[4]<=1'b1;
            // 条件分支：检查 state!=IDLE && state!=CLEAR。
            if(state!=IDLE && state!=CLEAR) active_cycles<=active_cycles+1'b1;
            // 复位相关判断：((state==READ_REQ || state==WRITE_REQ || state==BURST_SEND) && !dma_req_ready) ||；分支方向由信号极性与取反表达式决定。
            if(((state==READ_REQ || state==WRITE_REQ || state==BURST_SEND) && !dma_req_ready) ||
               ((state==READ_RSP || state==WRITE_RSP) && !dma_rsp_valid))
                stall_cycles<=stall_cycles+1'b1;
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case(state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: if(start && ready) begin
                    // Rounded to the same 16-byte envelope used by the original
                    // single-beat cache. No read crosses into another tensor's
                    // next aligned word. Address-gen validation precedes all DMA.
                    source_low_q<={input_base[31:4],4'b0};
                    source_high_q<=(input_base+32'(input_h)*32'(input_w)*32'(input_c)+32'd15)&32'hfffffff0;
                    error_sticky<=0;
                    partial_output<=0;
                    source_read_bytes<=0;scratch_write_bytes<=0;
                    cache_hits<=0;cache_misses<=0;
                    active_cycles<=0;stall_cycles<=0;
                    source_addr_q<=0;write_addr_q<=0;emitted_q<=0;
                    write_buffer<=0;write_strobe_q<=0;write_count_q<=0;
                    write_lane<=0;write_last_q<=0;
            queued_words<=0;send_word<=0;burst_count<=0;queued_bytes<=0;burst_bytes<=0;
            burst_base<=0;burst_last<=0;burst_data_q<=0;burst_mask_q<=0;
                    // 条件分支：检查 !flush_cache && !cache_layer_ok_q。
                    if(!flush_cache && !cache_layer_ok_q)begin
                        error_sticky[5]<=1'b1;done_pulse<=1'b1;
                    // 条件分支：检查 flush_cache。
                    end else if(flush_cache)begin
                        clear_index<=0;clear_launch_q<=1'b1;state<=CLEAR;
                        cache_layer_ok_q<=1'b1;
                    end
                    else state<=LAUNCH;
                end
                // 状态/选择分支 CLEAR：本分支规定该编码下的寄存器更新和下一步动作。
                CLEAR:begin
                    cache_valid[clear_index]<=1'b0;
                    clear_index<=clear_index+1'b1;
                    // 条件分支：检查 clear_index==10'd1023。
                    if(clear_index==10'd1023)
                        state<=clear_launch_q?LAUNCH:IDLE;
                end
                // 状态/选择分支 LAUNCH：本分支规定该编码下的寄存器更新和下一步动作。
                LAUNCH:state<=TOKEN;
                // 状态/选择分支 TOKEN：本分支规定该编码下的寄存器更新和下一步动作。
                TOKEN:begin
                    // 条件分支：检查 gen_done && gen_error!=0。
                    if(gen_done && gen_error!=0)begin
                        error_sticky[0]<=1'b1;done_pulse<=1'b1;
                        cache_layer_ok_q<=0;state<=IDLE;
                    // 条件分支：检查 gen_valid。
                    end else if(gen_valid)begin
                        // 条件分支：检查 gen_scratch!=scratch_base+emitted_q。
                        if(gen_scratch!=scratch_base+emitted_q)begin
                            error_sticky[3]<=1'b1;done_pulse<=1'b1;
                            cache_layer_ok_q<=0;gen_reset_q<=1'b1;state<=IDLE;
                        // 条件分支：检查 gen_zero。
                        end else if(gen_zero)begin
                            byte_q<=0;
                            // 条件分支：检查 span_active。
                            if(span_active)cache_word_q<=0;
                            // 条件分支：检查 direct_vector。
                            if(direct_vector)enqueue_vector(128'd0);
                            // 条件分支：检查 rgb_direct。
                            else if(rgb_direct)collect_rgb(128'd0,1'b1);
                            else state<=COLLECT;
                        end else begin
                            source_addr_q<=gen_source;
                            // 条件分支：检查 EARLY_CACHE_LOOKUP。
                            if(EARLY_CACHE_LOOKUP)begin
                                // NPUOPT1: launch the synchronous cache read at
                                // token capture, instead of spending a separate
                                // LOOKUP cycle after registering its address.
                                // No asynchronous RAM read and no new request.
                                cache_word_q<=cache_data[gen_source[13:4]];
                                cache_tag_q<=cache_tag[gen_source[13:4]];
                                cache_valid_q<=cache_valid[gen_source[13:4]];
                                state<=DECIDE;
                            end else state<=LOOKUP;
                        end
                    end
                end
                // 状态/选择分支 LOOKUP：本分支规定该编码下的寄存器更新和下一步动作。
                LOOKUP:begin
                    cache_word_q<=cache_data[cache_index];
                    cache_tag_q<=cache_tag[cache_index];
                    cache_valid_q<=cache_valid[cache_index];
                    state<=DECIDE;
                end
                // 状态/选择分支 DECIDE：本分支规定该编码下的寄存器更新和下一步动作。
                DECIDE:begin
                    // 条件分支：检查 cache_valid_q && cache_tag_q==source_tag。
                    if(cache_valid_q && cache_tag_q==source_tag)begin
                        byte_q<=cache_word_q[8*source_addr_q[3:0] +:8];
                        cache_hits<=cache_hits+1'b1;
                        // 条件分支：检查 direct_vector。
                        if(direct_vector)enqueue_vector(cache_word_q);
                        // 条件分支：检查 rgb_direct。
                        else if(rgb_direct)collect_rgb(cache_word_q,1'b0);
                        else state<=rgb_span?ROTATE:COLLECT;
                    end else begin
                        fill_base_q<=line_fill?refill_start:cache_line_addr;
                        fill_addr_q<=line_fill?refill_start:cache_line_addr;
                        fill_words_q<=line_fill?3'((refill_end-refill_start)>>4):3'd1;
                        cache_misses<=cache_misses+1'b1;state<=READ_REQ;
                    end
                end
                // 状态/选择分支 READ_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                READ_REQ:if(dma_req_ready)state<=READ_RSP;
                // 状态/选择分支 READ_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                READ_RSP:if(dma_rsp_valid)begin
                    // 条件分支：检查 dma_rsp_write || dma_rsp_id!=TAG || dma_rsp_error。
                    if(dma_rsp_write || dma_rsp_id!=TAG || dma_rsp_error)begin
                        error_sticky[1]<=1'b1;done_pulse<=1'b1;
                        cache_layer_ok_q<=0;gen_reset_q<=1'b1;state<=IDLE;
                    end else begin
                        cache_data[fill_addr_q[13:4]]<=dma_rsp_rdata;
                        cache_tag[fill_addr_q[13:4]]<=fill_addr_q[31:14];
                        cache_valid[fill_addr_q[13:4]]<=1'b1;
                        // 条件分支：检查 fill_addr_q==cache_line_addr。
                        if(fill_addr_q==cache_line_addr)begin
                            byte_q<=dma_rsp_rdata[8*source_addr_q[3:0]+:8];
                            // 条件分支：检查 span_active。
                            if(span_active)cache_word_q<=dma_rsp_rdata;
                        end
                        source_read_bytes<=source_read_bytes+32'd16;
                        fill_addr_q<=fill_addr_q+32'd16;
                        // 条件分支：检查 read_last。
                        if(read_last)begin
                            // 条件分支：检查 direct_vector。
                            if(direct_vector)enqueue_vector(fetched_word);
                            // 条件分支：检查 rgb_direct。
                            else if(rgb_direct)collect_rgb(fetched_word,1'b0);
                            else state<=rgb_span?ROTATE:COLLECT;
                        end
                    end
                end
                // 状态/选择分支 ROTATE：本分支规定该编码下的寄存器更新和下一步动作。
                ROTATE:begin
                    rotated_word_q<=doubled_cache_word[16*rotate_pairs+:128];
                    state<=COLLECT;
                end
                // 状态/选择分支 COLLECT：本分支规定该编码下的寄存器更新和下一步动作。
                COLLECT:if(gen_valid)begin
                    // 条件分支：检查 span_active。
                    if(span_active)begin
                        // Fixed eight16bit lanes, one bounded128bit rotate.
                        // This span never crosses source/destination word or
                        // kernel-row/padding boundaries. No payloadcrossbar.
                        for(integer lane=0;lane<8;lane++)
                            // 条件分支：检查 5'(lane*2)>={1'b0,write_lane} && 5'(lane*2)<next_write_count。
                            if(5'(lane*2)>={1'b0,write_lane} && 5'(lane*2)<next_write_count)
                                write_buffer[lane*16+:16]<=gen_zero ? 16'd0 : vector16 ? cache_word_q[lane*16+:16] : rotated_word_q[lane*16+:16];
                        emitted_q<=emitted_q+32'(gen_bytes);
                        // 条件分支：检查 next_write_count==16 || gen_last。
                        if(next_write_count==16 || gen_last)begin
                            write_addr_q<={gen_scratch[31:4],4'b0};
                            write_strobe_q<=16'hffff>>(5'd16-next_write_count);
                            write_count_q<=next_write_count;write_last_q<=gen_last;state<=WRITE_BURST_ENABLE?QUEUE_WORD:WRITE_REQ;
                        end else begin write_lane<=next_write_count[3:0];state<=TOKEN;end
                    end else begin
                    write_buffer[8*write_lane +:8]<=byte_q;
                    emitted_q<=emitted_q+1'b1;
                    // 条件分支：检查 write_lane==4'd15 || gen_last。
                    if(write_lane==4'd15 || gen_last)begin
                        write_addr_q<={gen_scratch[31:4],4'b0};
                        write_strobe_q<=16'hffff>>(15-write_lane);
                        write_count_q<={1'b0,write_lane}+5'd1;
                        write_last_q<=gen_last;
                        state<=WRITE_BURST_ENABLE?QUEUE_WORD:WRITE_REQ;
                    end else begin
                        write_lane<=write_lane+1'b1;
                        state<=TOKEN;
                    end
                    end
                end
                // 状态/选择分支 QUEUE_WORD：本分支规定该编码下的寄存器更新和下一步动作。
                QUEUE_WORD:begin
                    burst_words[queued_words]<=write_buffer;
                    burst_masks[queued_words]<=write_strobe_q;
                    // 条件分支：检查 queued_words==0。
                    if(queued_words==0)burst_base<=write_addr_q;
                    queued_bytes<=queued_bytes+9'(write_count_q);
                    // 条件分支：检查 queued_words==15||write_last_q||write_addr_q[11:4]==8'hff。
                    if(queued_words==15||write_last_q||write_addr_q[11:4]==8'hff)begin
                        burst_count<={1'b0,queued_words}+5'd1;
                        burst_bytes<=queued_bytes+9'(write_count_q);
                        burst_last<=write_last_q;send_word<=0;state<=BURST_LOAD;
                    end else begin
                        queued_words<=queued_words+1'b1;
                        write_buffer<=0;write_lane<=0;state<=TOKEN;
                    end
                end
                // 状态/选择分支 BURST_LOAD：本分支规定该编码下的寄存器更新和下一步动作。
                BURST_LOAD:begin
                    burst_data_q<=burst_words[0];burst_mask_q<=burst_masks[0];state<=BURST_SEND;
                end
                // 状态/选择分支 BURST_SEND：本分支规定该编码下的寄存器更新和下一步动作。
                BURST_SEND:if(dma_req_ready)begin
                    partial_output<=1'b1;
                    // 复位相关判断：{1'b0,send_word}+5'd1==burst_count；分支方向由信号极性与取反表达式决定。
                    if({1'b0,send_word}+5'd1==burst_count)state<=WRITE_RSP;
                    else begin
                        send_word<=send_word+1'b1;
                        burst_data_q<=burst_words[send_word+4'd1];burst_mask_q<=burst_masks[send_word+4'd1];
                    end
                end
                // 状态/选择分支 WRITE_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                WRITE_REQ:if(dma_req_ready)begin
                    partial_output<=1'b1;state<=WRITE_RSP;
                end
                // 状态/选择分支 WRITE_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                WRITE_RSP:if(dma_rsp_valid)begin
                    // 条件分支：检查 !dma_rsp_write || dma_rsp_id!=TAG || dma_rsp_error。
                    if(!dma_rsp_write || dma_rsp_id!=TAG || dma_rsp_error)begin
                        error_sticky[2]<=1'b1;done_pulse<=1'b1;
                        cache_layer_ok_q<=0;gen_reset_q<=1'b1;state<=IDLE;
                    end else begin
                        scratch_write_bytes<=scratch_write_bytes+
                            (WRITE_BURST_ENABLE?{23'd0,burst_bytes}:{27'd0,write_count_q});
                        queued_words<=0;queued_bytes<=0;
                        write_buffer<=0;write_lane<=0;
                        // 复位相关判断：WRITE_BURST_ENABLE?burst_last:write_last_q；分支方向由信号极性与取反表达式决定。
                        if(WRITE_BURST_ENABLE?burst_last:write_last_q)begin done_pulse<=1'b1;state<=IDLE;end
                        else state<=TOKEN;
                    end
                end
                default:begin
                    error_sticky[7]<=1'b1;done_pulse<=1'b1;
                    cache_layer_ok_q<=0;gen_reset_q<=1'b1;state<=IDLE;
                end
            endcase
        end
    end
    // synthesis translate_off
    always_ff @(posedge clk)if(!rst && state==COLLECT && gen_valid && span_active)begin
        // 条件分支：检查 gen_bytes==0 || gen_bytes[0] || write_lane[0] || next_write_count>16 ||。
        if(gen_bytes==0 || gen_bytes[0] || write_lane[0] || next_write_count>16 ||
           (!gen_zero && source_addr_q[0]))$fatal(1,"WINDOW_SPAN_ALIGNMENT_RED");
    end
    // 过程边界：always_ff @(posedge clk)if(!rst)begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk)if(!rst)begin
        // 条件分支：检查 rgb_commit && (gen_bytes==0 || gen_bytes[0] || write_lane[0] || next_write_count>16 ||。
        if(rgb_commit && (gen_bytes==0 || gen_bytes[0] || write_lane[0] || next_write_count>16 ||
           (!gen_zero && source_addr_q[0])))$fatal(1,"WINDOW_RGB_DIRECT_ALIGNMENT");
        // 条件分支：检查 vector_commit && (gen_bytes!=16 || write_lane!=0 || gen_scratch[3:0]!=0)。
        if(vector_commit && (gen_bytes!=16 || write_lane!=0 || gen_scratch[3:0]!=0))
            $fatal(1,"WINDOW_DIRECT_VECTOR_ALIGNMENT");
        // 条件分支：检查 state==READ_REQ && line_fill && (fill_words_q==0 || fill_words_q>4 ||。
        if(state==READ_REQ && line_fill && (fill_words_q==0 || fill_words_q>4 ||
            fill_base_q<source_low_q || fill_base_q+(32'(fill_words_q)<<4)>source_high_q))
            $fatal(1,"WINDOW_REFILL_RANGE");
    end
    // synthesis translate_on

endmodule
