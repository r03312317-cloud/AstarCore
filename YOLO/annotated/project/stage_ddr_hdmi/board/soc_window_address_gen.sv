// 架构导读：soc_window_address_gen。
// 根据卷积坐标、步幅、膨胀和填充生成 Window 读取地址。
`timescale 1ns/1ps
// S4 address/order phase of HWC im2col. It emits row-major [M,K] requests,
// including zero-padding tokens; a later gather DMA must fetch/pack these
// bytes into the existing A scratch bank or a validated on-chip FIFO.
module soc_window_address_gen #(
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
    // 静态配置：parameter bit INCREMENTAL_PIXEL_INDEX=1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit INCREMENTAL_PIXEL_INDEX=1'b1
)(
    // 接口声明：input logic clk,rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic clk,rst,
    // 接口声明：input logic start。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic start,
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
    // 接口声明：output logic ready,busy,done_pulse。
    // 表达本地完成/结束条件，系统退休还需满足上层接口契约。
    output logic ready,busy,done_pulse,
    // 接口声明：output logic [7:0] error_sticky。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [7:0] error_sticky,
    // 接口声明：output logic out_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic out_valid,
    // 接口声明：input logic out_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic out_ready,
    // 接口声明：output logic out_zero。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic out_zero,
    // 接口声明：output logic [31:0] out_source_addr,out_scratch_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] out_source_addr,out_scratch_addr,
    // 接口声明：output logic [4:0] out_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [4:0] out_bytes,
    // 接口声明：output logic out_last。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic out_last
);
    // 局部字段 wire vector16=VECTOR16_ENABLE && input_c[3:0]==0 && input_base[3:0]==0。
    wire vector16=VECTOR16_ENABLE && input_c[3:0]==0 && input_base[3:0]==0;
    wire rgb_span=RGB6_SPAN_ENABLE && input_c==3 && kernel_h==6 && kernel_w==6 &&
        stride_h==2 && stride_w==2 && dilation_h==1 && dilation_w==1 &&
        pad_top==2 && pad_left==2 && pad_bottom==2 && pad_right==2 &&
        input_w[0]==0 && input_h[0]==0 && input_base[3:0]==0 && scratch_base[3:0]==0;
    logic [4:0] token_bytes;
    logic rgb_channel_end;
    logic signed [32:0] rgb_x_bytes;
    logic [31:0] rgb_row_bytes;
    logic rgb_y_zero;
    // (x - pad_left)*3 modulo 2^33, the exact expression the RGB6 token cone
    // previously rebuilt combinationally from pad_left on every token.
    function automatic logic signed [32:0] px_bytes_of(input logic [31:0] x);
        logic signed [32:0] d;
        d=$signed({1'b0,x})-$signed({25'd0,pad_left});
        px_bytes_of=d+(d<<<1);
    endfunction
    // px_bytes_q advances in lockstep with px_q, so rgb_x_bytes keeps the same
    // value in every cycle that can emit a token. rgb_row_bytes_q removes the
    // input_w*3 multiplier from the same compare cone.
    (* keep="true" *) logic signed [32:0] px_bytes_q;
    (* keep="true" *) logic [31:0] rgb_row_bytes_q;
    // Same constant3 scaling applied to one dilation_w step, so a kx advance
    // updates the byte offset incrementally instead of rebuilding it.
    wire signed [32:0] dilation_w_x3=
        ($signed({25'd0,dilation_w})<<<1)+$signed({25'd0,dilation_w});
    // 组合连接 rgb_row_bytes：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign rgb_row_bytes=rgb_row_bytes_q;
    // Exact modulo2^33 constant3 arithmetic; preserve signed padding tests.
    assign rgb_x_bytes=px_bytes_q+$signed({17'd0,c_q});
    // 组合连接 rgb_y_zero：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign rgb_y_zero=py_q<pad_top || py_q-32'(pad_top)>=32'(input_h);
    // 组合连接 out_bytes：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign out_bytes=token_bytes;
    // Every limit term is evaluated in parallel and saturated to 5'd31, then
    // combined by a balanced min tree. 31 can never win because the widest
    // candidate is 16, so saturation reproduces the old "limit[31:5]==0" guard
    // exactly. Terms the original if/else chain skipped contribute 5'd31.
    function automatic logic [4:0] sat5(input logic [31:0] v);
        sat5=(v[31:5]==27'd0) ? v[4:0] : 5'd31;
    endfunction
    // 局部运算/辅助过程：function automatic logic [4:0] min5(input logic [4:0] a,input logic [4:0] b);。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function automatic logic [4:0] min5(input logic [4:0] a,input logic [4:0] b);
        min5=(a<b) ? a : b;
    endfunction
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
      // amount starts at1/16 (RGB16-low4) and unsigned min only reduces it.
      logic [4:0] a_cap,a_chan,a_pad,a_row,a_align,a_kernel;
      logic [4:0] m_head,m_tail;
      logic in_row;
      a_cap=vector16?5'd16:5'd1;
      a_chan=5'd16-{1'b0,emitted_q[3:0]};
      in_row=(rgb_x_bytes>=0)&&(rgb_x_bytes<$signed({1'b0,rgb_row_bytes}));
      a_align=(rgb_span&&!rgb_y_zero&&in_row) ? sat5(32'd16-{28'd0,out_source_addr[3:0]}) : 5'd31;
      a_row=(rgb_span&&!rgb_y_zero&&in_row) ? sat5(rgb_row_bytes-32'(rgb_x_bytes)) : 5'd31;
      a_pad=(rgb_span&&!rgb_y_zero&&rgb_x_bytes<0) ? sat5(32'(-rgb_x_bytes)) : 5'd31;
      a_kernel=sat5(32'd18-32'(c_q));
      m_head=min5(a_chan,a_kernel);
      m_tail=min5(min5(a_pad,a_row),a_align);
      token_bytes=rgb_span ? min5(m_head,m_tail) : a_cap;
      // The minimum equals the kernel remainder exactly when every other
      // limit is at least that remainder. Compute this alongside the min
      // tree, rather than feeding token_bytes back through a wide adder and
      // comparison into the coordinate register enables.
      rgb_channel_end=(a_kernel<=a_chan) && (a_kernel<=a_pad) &&
                      (a_kernel<=a_row) && (a_kernel<=a_align);
    end
    logic running;
    logic [15:0] oy_q,ox_q,ky_q,kx_q,c_q;
    logic [31:0] oy_base_q,ox_base_q,py_q,px_q;
    logic [31:0] emitted_q,total_q;
    logic [31:0] k_count,output_pixels,kernel_extent_h,kernel_extent_w;
    logic [31:0] padded_h,padded_w;
    logic dimension_h_ok,dimension_w_ok;
    logic [63:0] input_bytes,scratch_bytes,src_end,dst_end;
    logic valid_config;
    logic [31:0] src_y,src_x;
    logic [31:0] pixel_index_q;
    // PIPEOPT5: shape products are job-constant. Advance a validated HWC
    // pixel address by precomputed deltas instead of reprime/multiply after
    // every spatial token. All arithmetic preserves original uint32 wrap.
    logic [31:0] origin_index_q,kernel_row_step_q,kernel_x_span_q;
    logic [31:0] output_row_step_q,output_x_span_q,ky_delta_q,oy_delta_q;
    logic address_ready_q;
    // START captures each dependent product at a distinct clock boundary.
    // In the previous version input_h*input_w*input_c and the range compare
    // formed a four-APM path into hundreds of register enables.
    logic [2:0] validation_q;
    (* keep="true" *) logic [31:0] input_pixels_q;
    (* keep="true" *) logic [15:0] kernel_pixels_q;
    (* keep="true" *) logic valid_config_q;
    // The measured output_h -> subtract -> two APMs -> add -> compare
    // path had 15 logic levels. Register products before any subtraction,
    // then bounds before comparison. Preserve the original unsigned
    // 32/64-bit arithmetic, including rejected zero/oversized requests.
    (* keep="true" *) logic [15:0] kernel_h_dilation_q,kernel_w_dilation_q;
    (* keep="true" *) logic [63:0] output_h_stride_q,output_w_stride_q;
    (* keep="true" *) logic [63:0] last_h_stride_q,last_w_stride_q;
    (* keep="true" *) logic [63:0] dimension_h_min_q,dimension_h_max_q;
    (* keep="true" *) logic [63:0] dimension_w_min_q,dimension_w_max_q;
    (* keep="true" *) logic [31:0] first_row_product_q,first_row_expected_q;
    (* keep="true" *) logic [63:0] first_row_limit_q;
    // output = floor((padded - extent)/stride) + 1, validated without
    // a combinational divider. Widen products so invalid shapes cannot wrap.
    assign valid_config=input_h!=0 && input_w!=0 && input_c!=0 &&
        output_h!=0 && output_w!=0 && kernel_h!=0 && kernel_w!=0 &&
        stride_h!=0 && stride_w!=0 && dilation_h!=0 && dilation_w!=0 &&
        row_count!=0 && row_count<=16'd64 && k_count!=0 && k_count<=32'd65535 &&
        dimension_h_ok && dimension_w_ok &&
        first_oy<output_h && first_ox<output_w &&
        first_row_expected_q==first_row &&
        first_row<output_pixels && first_row_limit_q<=64'(output_pixels) &&
        input_base>=DDR_BASE && scratch_base>=DDR_BASE &&
        scratch_base[5:0]==0 &&
        src_end<=64'(DDR_BASE)+64'(DDR_BYTES) &&
        dst_end<=64'(DDR_BASE)+64'(DDR_BYTES) &&
        (src_end<=64'(scratch_base) || dst_end<=64'(input_base));
    // 组合连接 ready：表达接口或资源就绪；需结合相应有效/完成条件解释。
    assign ready=!rst && !running && validation_q==0;
    // 组合连接 busy：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign busy=running || validation_q!=0;
    // 组合连接 out_valid：标识这一路负载有效；是否接收还需检查对应的消费条件。
    assign out_valid=running && address_ready_q;
    // 组合连接 out_zero：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign out_zero=rgb_span ? (rgb_y_zero || rgb_x_bytes<0 ||
        rgb_x_bytes>=$signed({1'b0,rgb_row_bytes})) :
        (py_q<pad_top || px_q<pad_left || py_q-32'(pad_top)>=32'(input_h) ||
         px_q-32'(pad_left)>=32'(input_w));
    // 组合连接 src_y：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign src_y=py_q-32'(pad_top);
    // 组合连接 src_x：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign src_x=px_q-32'(pad_left);
    // 组合连接 out_source_addr：用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    assign out_source_addr=out_zero ? 32'd0 :
        input_base+(pixel_index_q*32'(input_c))+32'(c_q);
    // 组合连接 out_scratch_addr：用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    assign out_scratch_addr=scratch_base+emitted_q;
    // Precompare high27bits before late token_bytes; retain modulo2^32 wrap.
    wire [5:0] last_low_sum={1'b0,emitted_q[4:0]}+{1'b0,token_bytes};
    wire [26:0] last_high_inc=emitted_q[31:5]+27'd1;
    wire last_high_match=last_low_sum[5] ?
        (last_high_inc==total_q[31:5]) : (emitted_q[31:5]==total_q[31:5]);
    // Identical-operand XOR is hardware0. In four-state RTL it preserves
    // the original full-width arithmetic X/Z pollution, even if an early
    // partial compare could otherwise decide0. No synthesis-only branch.
    wire last_arithmetic_unknown=(^{emitted_q,token_bytes}) ^ (^{emitted_q,token_bytes});
    // 组合连接 out_last：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign out_last=running && (((last_low_sum[4:0]==total_q[4:0]) &&
        last_high_match) ^ last_arithmetic_unknown);
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        done_pulse<=0;
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst) begin
            running<=0;error_sticky<=0;
            oy_q<=0;ox_q<=0;ky_q<=0;kx_q<=0;c_q<=0;
            oy_base_q<=0;ox_base_q<=0;py_q<=0;px_q<=0;
            px_bytes_q<=0;rgb_row_bytes_q<=0;
            emitted_q<=0;total_q<=0;
            pixel_index_q<=0;address_ready_q<=0;
            origin_index_q<=0;kernel_row_step_q<=0;kernel_x_span_q<=0;
            output_row_step_q<=0;output_x_span_q<=0;ky_delta_q<=0;oy_delta_q<=0;
            validation_q<=0;input_pixels_q<=0;kernel_pixels_q<=0;
            input_bytes<=0;k_count<=0;scratch_bytes<=0;valid_config_q<=0;
            output_pixels<=0;kernel_extent_h<=0;kernel_extent_w<=0;
            padded_h<=0;padded_w<=0;dimension_h_ok<=0;dimension_w_ok<=0;
            src_end<=0;dst_end<=0;
            kernel_h_dilation_q<=0;kernel_w_dilation_q<=0;
            output_h_stride_q<=0;output_w_stride_q<=0;
            last_h_stride_q<=0;last_w_stride_q<=0;
            dimension_h_min_q<=0;dimension_h_max_q<=0;
            dimension_w_min_q<=0;dimension_w_max_q<=0;
            first_row_product_q<=0;first_row_expected_q<=0;first_row_limit_q<=0;
        end else begin
            // Split the measured py -> two multiplies -> source register
            // path. Coordinates stay stable until the token handshake.
            // Channel advances reuse the same pixel index; a coordinate
            // advance inserts one bubble so no previous pixel is emitted.
            if(running && (!INCREMENTAL_PIXEL_INDEX || !address_ready_q))begin
                pixel_index_q<=src_y*32'(input_w)+src_x;
                origin_index_q<=src_y*32'(input_w)+src_x;
                address_ready_q<=1'b1;
            end
            // 条件分支：检查 start && busy。
            if(start && busy) error_sticky[1]<=1;
            // 条件分支：检查 start && ready。
            if(start && ready) begin
                error_sticky<=0;
                validation_q<=1;
                input_pixels_q<=32'(input_h)*32'(input_w);
                kernel_pixels_q<=16'(kernel_h)*16'(kernel_w);
                output_pixels<=32'(output_h)*32'(output_w);
                padded_h<=32'(input_h)+32'(pad_top)+32'(pad_bottom);
                padded_w<=32'(input_w)+32'(pad_left)+32'(pad_right);
                kernel_h_dilation_q<=16'(kernel_h)*16'(dilation_h);
                kernel_w_dilation_q<=16'(kernel_w)*16'(dilation_w);
                output_h_stride_q<=64'(output_h)*64'(stride_h);
                output_w_stride_q<=64'(output_w)*64'(stride_w);
                first_row_product_q<=32'(first_oy)*32'(output_w);
                first_row_limit_q<=64'(first_row)+64'(row_count);
                address_ready_q<=0;
            // 条件分支：检查 validation_q!=0。
            end else if(validation_q!=0)begin
                // 按 validation_q 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                case(validation_q)
                 1:begin
                    kernel_row_step_q<=32'(input_w)*32'(dilation_h);
                    kernel_x_span_q<=(32'(kernel_w)-1)*32'(dilation_w);
                    output_row_step_q<=32'(input_w)*32'(stride_h);
                    output_x_span_q<=(32'(output_w)-1)*32'(stride_w);
                    input_bytes<=64'(input_pixels_q)*64'(input_c);
                    k_count<=32'(kernel_pixels_q)*32'(input_c);
                    kernel_extent_h<=32'(kernel_h_dilation_q)-32'(dilation_h)+1;
                    kernel_extent_w<=32'(kernel_w_dilation_q)-32'(dilation_w)+1;
                    last_h_stride_q<=output_h_stride_q-64'(stride_h);
                    last_w_stride_q<=output_w_stride_q-64'(stride_w);
                    first_row_expected_q<=first_row_product_q+32'(first_ox);
                    validation_q<=2;
                 end
                 2:begin
                    ky_delta_q<=kernel_row_step_q-kernel_x_span_q;
                    oy_delta_q<=output_row_step_q-output_x_span_q;
                    scratch_bytes<=64'(row_count)*64'(k_count);
                    dimension_h_min_q<=last_h_stride_q+64'(kernel_extent_h);
                    dimension_h_max_q<=output_h_stride_q+64'(kernel_extent_h);
                    dimension_w_min_q<=last_w_stride_q+64'(kernel_extent_w);
                    dimension_w_max_q<=output_w_stride_q+64'(kernel_extent_w);
                    validation_q<=3;
                 end
                 3:begin
                    src_end<=64'(input_base)+input_bytes;
                    dst_end<=64'(scratch_base)+scratch_bytes;
                    dimension_h_ok<=padded_h>=kernel_extent_h && stride_h!=0 &&
                        output_h!=0 && dimension_h_min_q<=64'(padded_h) &&
                        dimension_h_max_q>64'(padded_h);
                    dimension_w_ok<=padded_w>=kernel_extent_w && stride_w!=0 &&
                        output_w!=0 && dimension_w_min_q<=64'(padded_w) &&
                        dimension_w_max_q>64'(padded_w);
                    validation_q<=4;
                 end
                 4:begin
                    valid_config_q<=valid_config;
                    validation_q<=5;
                 end
                 5:begin
                  validation_q<=0;
                  // 条件分支：检查 !valid_config_q。
                  if(!valid_config_q) begin
                    error_sticky[0]<=1;done_pulse<=1;
                  end else begin
                    running<=1;
                    address_ready_q<=0;
                    oy_q<=first_oy;
                    ox_q<=first_ox;
                    oy_base_q<=32'(first_oy)*32'(stride_h);
                    ox_base_q<=32'(first_ox)*32'(stride_w);
                    py_q<=32'(first_oy)*32'(stride_h);
                    px_q<=32'(first_ox)*32'(stride_w);
                    px_bytes_q<=px_bytes_of(32'(first_ox)*32'(stride_w));
                    rgb_row_bytes_q<=32'(input_w)*32'd3;
                    ky_q<=0;kx_q<=0;c_q<=0;
                    emitted_q<=0;
                    total_q<=32'(scratch_bytes);
                  end
                 end
                 default:begin
                    validation_q<=0;error_sticky[0]<=1;done_pulse<=1;
                 end
                endcase
            // 握手/背压判断：out_valid && out_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            end else if(out_valid && out_ready) begin
                emitted_q<=emitted_q+32'(token_bytes);
                // 条件分支：检查 out_last。
                if(out_last) begin
                    running<=0;done_pulse<=1;
                // 条件分支：检查 rgb_span ? !rgb_channel_end :。
                end else if(rgb_span ? !rgb_channel_end :
                            (c_q+(vector16?16'd16:16'd1)<input_c)) c_q<=c_q+16'(token_bytes);
                else begin
                    c_q<=0;
                    address_ready_q<=INCREMENTAL_PIXEL_INDEX;
                    // 条件分支：检查 !rgb_span && kx_q+1<kernel_w。
                    if(!rgb_span && kx_q+1<kernel_w) begin
                        // 条件分支：检查 INCREMENTAL_PIXEL_INDEX。
                        if(INCREMENTAL_PIXEL_INDEX)pixel_index_q<=pixel_index_q+32'(dilation_w);
                        kx_q<=kx_q+1;px_q<=px_q+32'(dilation_w);
                        px_bytes_q<=px_bytes_q+dilation_w_x3;
                    end else begin
                        kx_q<=0;px_q<=ox_base_q;
                        px_bytes_q<=px_bytes_of(ox_base_q);
                        // 条件分支：检查 ky_q+1<kernel_h。
                        if(ky_q+1<kernel_h) begin
                            // 条件分支：检查 INCREMENTAL_PIXEL_INDEX。
                            if(INCREMENTAL_PIXEL_INDEX)pixel_index_q<=pixel_index_q+(rgb_span?kernel_row_step_q:ky_delta_q);
                            ky_q<=ky_q+1;py_q<=py_q+32'(dilation_h);
                        end else begin
                            ky_q<=0;
                            // 条件分支：检查 ox_q+1<output_w。
                            if(ox_q+1<output_w) begin
                                // 条件分支：检查 INCREMENTAL_PIXEL_INDEX。
                                if(INCREMENTAL_PIXEL_INDEX)begin
                                    pixel_index_q<=origin_index_q+32'(stride_w);
                                    origin_index_q<=origin_index_q+32'(stride_w);
                                end
                                ox_q<=ox_q+1;
                                ox_base_q<=ox_base_q+32'(stride_w);
                                px_q<=ox_base_q+32'(stride_w);
                                px_bytes_q<=px_bytes_of(ox_base_q+32'(stride_w));
                                py_q<=oy_base_q;
                            end else begin
                                // 条件分支：检查 INCREMENTAL_PIXEL_INDEX。
                                if(INCREMENTAL_PIXEL_INDEX)begin
                                    pixel_index_q<=origin_index_q+oy_delta_q;
                                    origin_index_q<=origin_index_q+oy_delta_q;
                                end
                                ox_q<=0;oy_q<=oy_q+1;
                                ox_base_q<=0;px_q<=0;
                                px_bytes_q<=px_bytes_of(32'd0);
                                oy_base_q<=oy_base_q+32'(stride_h);
                                py_q<=oy_base_q+32'(stride_h);
                            end
                        end
                    end
                end
            end
        end
    end
    // synthesis translate_off
    always_ff @(posedge clk)if(!rst && out_valid && INCREMENTAL_PIXEL_INDEX)
        // 条件分支：检查 pixel_index_q !== (src_y*32'(input_w)+src_x)。
        if(pixel_index_q !== (src_y*32'(input_w)+src_x))
            $fatal(1,"WINDOW_INCREMENTAL_ADDRESS_EQUIVALENCE");
    // synthesis translate_on
    initial if(DDR_BYTES<256 || DDR_BASE[5:0]!=0)
        $fatal(1,"WINDOW_GEN_REGION_PARAMETER");
endmodule
