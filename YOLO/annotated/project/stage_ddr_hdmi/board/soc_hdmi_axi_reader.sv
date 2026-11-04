// 架构导读：soc_hdmi_axi_reader。
// 从 DDR 读取显示像素，向显示路径提供带背压的数据。
`timescale 1ns/1ps
// Full-size replay from the reserved low-DDR video region. The entire 16-beat
// AXI burst is captured before pixel emission. This guarantees RREADY until
// RLAST even when the downstream writer must obtain the same shared AXI port.
// A caller must treat pixels as uncommitted until frame_valid.
module soc_hdmi_axi_reader #(
    // 静态配置：parameter logic [31:0] VIDEO_BASE=32'h8100_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] VIDEO_BASE=32'h8100_0000,
    // 静态配置：parameter logic [31:0] VIDEO_BYTES=32'h0200_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] VIDEO_BYTES=32'h0200_0000,
    // 静态配置：parameter int MAX_PIXELS=2592*1944。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int MAX_PIXELS=2592*1944,
    // 静态配置：parameter bit ENABLE_ABORT=0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit ENABLE_ABORT=0,
    // 静态配置：parameter int WAIT_LIMIT=0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int WAIT_LIMIT=0
)(
    // 接口声明：input logic clk,rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic clk,rst,
    // 接口声明：input logic start,abort。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic start,abort,
    // 接口声明：input logic [31:0] frame_base,frame_pixels。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [31:0] frame_base,frame_pixels,
    // 接口声明：output logic ready,busy,done_pulse,frame_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic ready,busy,done_pulse,frame_valid,
    // 接口声明：output logic [7:0] error_sticky。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [7:0] error_sticky,
    // 接口声明：output logic [31:0] pixels_emitted。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] pixels_emitted,
    // 接口声明：output logic [31:0] max_wait_cycles。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] max_wait_cycles,
    // 接口声明：output logic pixel_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic pixel_valid,
    // 接口声明：input logic pixel_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic pixel_ready,
    // 接口声明：output logic [15:0] pixel_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [15:0] pixel_data,
    // 接口声明：output logic pixel_last。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic pixel_last,
    // 接口声明：output logic [3:0] m_arid。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [3:0] m_arid,
    // 接口声明：output logic [31:0] m_araddr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] m_araddr,
    // 接口声明：output logic [7:0] m_arlen。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [7:0] m_arlen,
    output logic [2:0] m_arsize,
    output logic [1:0] m_arburst,
    output logic m_arvalid,
    input logic m_arready,
    input logic [3:0] m_rid,
    input logic [127:0] m_rdata,
    input logic [1:0] m_rresp,
    input logic m_rlast,m_rvalid,
    output logic m_rready
);
    typedef enum logic [2:0] {IDLE,ADDR,READ,EMIT,DRAIN} state_t;
    state_t state;
    logic [31:0] base_q,target_q;
    (* ram_style="distributed" *) logic [127:0] burst_data[0:15];
    logic [4:0] burst_beats_q,beat_index_q,emit_index_q;
    logic [3:0] lane_q,beat_pixels_q;
    logic [33:0] frame_end;
    logic valid_config;
    logic [31:0] remaining;
    logic [4:0] next_burst_beats;
    logic cancelled;
    logic [31:0] wait_cycles;
    wire do_abort=ENABLE_ABORT&&abort;
    assign frame_end={2'b0,frame_base}+{1'b0,frame_pixels,1'b0};
    assign valid_config=frame_base[3:0]==0 && frame_pixels!=0 &&
        frame_pixels<=32'(MAX_PIXELS) && frame_base>=VIDEO_BASE &&
        frame_end<={2'b0,VIDEO_BASE}+{2'b0,VIDEO_BYTES};
    assign remaining=target_q-pixels_emitted;
    // A 680-pixel RGB565 row starts on 16-byte, not necessarily 256-byte,
    // boundaries. Never issue a burst across a 4 KiB AXI boundary.
    wire [12:0] bytes_to_page=13'd4096-{1'b0,m_araddr[11:0]};
    wire [8:0] beats_to_page=9'(bytes_to_page>>4);
    wire [4:0] beats_for_pixels=remaining>=32'd128 ? 5'd16 : 5'((remaining+7)>>3);
    assign next_burst_beats=(beats_to_page<9'(beats_for_pixels)) ? 5'(beats_to_page) : beats_for_pixels;
    assign ready=state==IDLE && !rst;
    assign busy=state!=IDLE;
    assign m_arid=4'hd;
    assign m_araddr=base_q+(pixels_emitted<<1);
    assign m_arlen=8'(next_burst_beats-1'b1);
    assign m_arsize=3'd4;
    assign m_arburst=2'b01;
    assign m_arvalid=state==ADDR;
    assign m_rready=state==READ || state==DRAIN;
    assign pixel_valid=state==EMIT;
    assign pixel_data=burst_data[emit_index_q[3:0]][16*lane_q[2:0] +:16];
    assign pixel_last=pixel_valid && pixels_emitted+1==target_q;
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        done_pulse<=0;
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst) begin
            state<=IDLE;base_q<=0;target_q<=0;
            burst_beats_q<=0;beat_index_q<=0;emit_index_q<=0;lane_q<=0;
            beat_pixels_q<=0;
            pixels_emitted<=0;error_sticky<=0;frame_valid<=0;
            cancelled<=0;wait_cycles<=0;max_wait_cycles<=0;
        end else begin
            if(state!=IDLE&&do_abort)cancelled<=1;
            // 握手/背压判断：(state==ADDR&&!m_arready)||((state==READ||state==DRAIN)&&!m_rvalid)。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if((state==ADDR&&!m_arready)||((state==READ||state==DRAIN)&&!m_rvalid))begin
                if(wait_cycles!=32'hffffffff)wait_cycles<=wait_cycles+1'b1;
                if(wait_cycles>=max_wait_cycles)max_wait_cycles<=wait_cycles+1'b1;
                if(WAIT_LIMIT>0&&wait_cycles>=WAIT_LIMIT-1)error_sticky[3]<=1;
            end else wait_cycles<=0;
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case(state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: if(start) begin
                    base_q<=frame_base;target_q<=frame_pixels;
                    pixels_emitted<=0;error_sticky<=0;frame_valid<=0;
                    beat_index_q<=0;emit_index_q<=0;lane_q<=0;
                    cancelled<=0;
                    if(valid_config)state<=ADDR;
                    else begin error_sticky[0]<=1;done_pulse<=1;end
                end
                // 状态/选择分支 ADDR：本分支规定该编码下的寄存器更新和下一步动作。
                ADDR: if(m_arready) begin
                    burst_beats_q<=next_burst_beats;
                    beat_index_q<=0;
                    state<=(cancelled||do_abort)?DRAIN:READ;
                end
                // 状态/选择分支 READ：本分支规定该编码下的寄存器更新和下一步动作。
                READ: if(m_rvalid) begin
                    if(cancelled||do_abort)begin
                        if(m_rlast)begin done_pulse<=1;state<=IDLE;end
                        else state<=DRAIN;
                    end else if(m_rid!=4'hd || m_rresp!=2'b00 ||
                       m_rlast!=(beat_index_q+1==burst_beats_q)) begin
                        error_sticky[1]<=m_rid!=4'hd || m_rresp!=2'b00;
                        error_sticky[2]<=m_rlast!=(beat_index_q+1==burst_beats_q);
                        if(m_rlast)begin done_pulse<=1;state<=IDLE;end
                        else state<=DRAIN;
                    end else begin
                        burst_data[beat_index_q[3:0]]<=m_rdata;
                        // 复位相关判断：beat_index_q+1==burst_beats_q；分支方向由信号极性与取反表达式决定。
                        if(beat_index_q+1==burst_beats_q) begin
                            emit_index_q<=0;lane_q<=0;
                            beat_pixels_q<=remaining>=32'd8 ? 4'd8 : 4'(remaining);
                            state<=EMIT;
                        end else beat_index_q<=beat_index_q+1;
                    end
                end
                // 状态/选择分支 EMIT：本分支规定该编码下的寄存器更新和下一步动作。
                EMIT: if(cancelled||do_abort)begin done_pulse<=1;state<=IDLE;end
                else if(pixel_ready) begin
                    pixels_emitted<=pixels_emitted+1;
                    if(lane_q+1==beat_pixels_q) begin
                        if(pixels_emitted+1==target_q) begin
                            frame_valid<=1;done_pulse<=1;state<=IDLE;
                        // 复位相关判断：emit_index_q+1==burst_beats_q；分支方向由信号极性与取反表达式决定。
                        end else if(emit_index_q+1==burst_beats_q) state<=ADDR;
                        else begin
                            emit_index_q<=emit_index_q+1;lane_q<=0;
                            beat_pixels_q<=remaining>32'd9 ? 4'd8 :
                                           4'(remaining-1'b1);
                        end
                    end else lane_q<=lane_q+1;
                end
                // 状态/选择分支 DRAIN：本分支规定该编码下的寄存器更新和下一步动作。
                DRAIN: if(m_rvalid && m_rlast) begin
                    done_pulse<=1;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
    initial if(VIDEO_BASE[7:0]!=0 || VIDEO_BYTES<256 || MAX_PIXELS<1)
        $fatal(1,"VIDEO_REPLAY_PARAMETER");
endmodule
