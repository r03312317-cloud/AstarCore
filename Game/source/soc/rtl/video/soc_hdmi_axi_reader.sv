// [ARCH] 为扫描输出生成 AXI 突发读，把返回数据送往显示队列。
// [ARCH] AR 接纳后 R 数据的 ID、长度、最后一拍和错误属于该突发。
// [ARCH] 没有 rvalid 的周期不能消费总线上的旧值。
// [ARCH] 预取数量要能吸收 DDR 延迟，又不能超过队列可容纳容量。
// [ARCH] 地址和步幅遵守 RGB565 字节布局。
`timescale 1ns/1ps
// Full-size replay from the reserved low-DDR video region. The entire 16-beat
// AXI burst is captured before pixel emission. This guarantees RREADY until
// RLAST even when the downstream writer must obtain the same shared AXI port.
// A caller must treat pixels as uncommitted until frame_valid.
module soc_hdmi_axi_reader #(
    parameter logic [31:0] VIDEO_BASE=32'h8100_0000,
    parameter logic [31:0] VIDEO_BYTES=32'h0200_0000,
    parameter int MAX_PIXELS=2592*1944,
    // [ARCH] ENABLE_ABORT：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 do_abort 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter bit ENABLE_ABORT=0,
    parameter int WAIT_LIMIT=0
)(
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input logic clk,rst,
    input logic start,abort,
    input logic [31:0] frame_base,frame_pixels,
    // [ARCH] ready：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。
    output logic ready,busy,done_pulse,frame_valid,
    // [ARCH] error_sticky：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pixels_emitted, frame_valid, done_pulse 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [7:0] error_sticky,
    output logic [31:0] pixels_emitted,
    output logic [31:0] max_wait_cycles,
    // [ARCH] pixel_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pixel_last 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic pixel_valid,
    // [ARCH] pixel_ready：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。
    input logic pixel_ready,
    // [ARCH] pixel_data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    output logic [15:0] pixel_data,
    output logic pixel_last,
    // [ARCH] m_arid：读事务身份，R 通道需要依据它保持主机/事务归属。
    output logic [3:0] m_arid,
    // [ARCH] m_araddr：读突发起始字节地址，响应阶段继续使用已保存的归属。
    output logic [31:0] m_araddr,
    // [ARCH] m_arlen：请求的读 beat 数编码，接收方用它核对边界和 RLAST。
    output logic [7:0] m_arlen,
    // [ARCH] m_arsize：读 beat 大小编码，需与总线宽度和地址对齐一致。
    output logic [2:0] m_arsize,
    // [ARCH] m_arburst：读突发的地址递增/固定方式，不能仅改变数据宽度而丢失。
    output logic [1:0] m_arburst,
    // [ARCH] m_arvalid：读地址有效，未获 ARREADY 前保持地址和突发属性。
    output logic m_arvalid,
    // [ARCH] m_arready：读地址接纳条件，与 ARVALID 共同形成一次读命令。
    input logic m_arready,
    // [ARCH] m_rid：返回数据的事务 ID，用于检查和路由先前接纳的读请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 error_sticky 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [3:0] m_rid,
    // [ARCH] m_rdata：当前读返回载荷，与 RVALID、ID、错误和最后一拍共同解释。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 burst_data 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [127:0] m_rdata,
    // [ARCH] m_rresp：读 beat 响应状态，错误需累计到对应行/突发。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 error_sticky 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] m_rresp,
    // [ARCH] m_rlast：当前为本突发最后一个返回 beat，必须与保存的长度一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 done_pulse, state, error_sticky 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_rlast,m_rvalid,
    // [ARCH] m_rready：接收方允许消费当前返回 beat，背压时保持未消费响应。
    output logic m_rready
);
    typedef enum logic [2:0] {IDLE,ADDR,READ,EMIT,DRAIN} state_t;
    state_t state;
    logic [31:0] base_q,target_q;
    // [ARCH] burst_data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pixel_data 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    (* ram_style="distributed" *) logic [127:0] burst_data[0:15];
    logic [4:0] burst_beats_q,beat_index_q,emit_index_q;
    logic [3:0] lane_q,beat_pixels_q;
    logic [33:0] frame_end;
    // [ARCH] valid_config：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic valid_config;
    logic [31:0] remaining;
    logic [4:0] next_burst_beats;
    logic cancelled;
    logic [31:0] wait_cycles;
    wire do_abort=ENABLE_ABORT&&abort;
    assign frame_end={2'b0,frame_base}+{1'b0,frame_pixels,1'b0};
    assign valid_config=frame_base[7:0]==0 && frame_pixels!=0 &&
        frame_pixels<=32'(MAX_PIXELS) && frame_base>=VIDEO_BASE &&
        frame_end<={2'b0,VIDEO_BASE}+{2'b0,VIDEO_BYTES};
    assign remaining=target_q-pixels_emitted;
    assign next_burst_beats=remaining>=32'd128 ? 5'd16 : 5'((remaining+7)>>3);
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
    always_ff @(posedge clk) begin
        done_pulse<=0;
        if(rst) begin
            state<=IDLE;base_q<=0;target_q<=0;
            burst_beats_q<=0;beat_index_q<=0;emit_index_q<=0;lane_q<=0;
            beat_pixels_q<=0;
            pixels_emitted<=0;error_sticky<=0;frame_valid<=0;
            cancelled<=0;wait_cycles<=0;max_wait_cycles<=0;
        end else begin
            if(state!=IDLE&&do_abort)cancelled<=1;
            if((state==ADDR&&!m_arready)||((state==READ||state==DRAIN)&&!m_rvalid))begin
                if(wait_cycles!=32'hffffffff)wait_cycles<=wait_cycles+1'b1;
                if(wait_cycles>=max_wait_cycles)max_wait_cycles<=wait_cycles+1'b1;
                if(WAIT_LIMIT>0&&wait_cycles>=WAIT_LIMIT-1)error_sticky[3]<=1;
            end else wait_cycles<=0;
            case(state)
                IDLE: if(start) begin
                    base_q<=frame_base;target_q<=frame_pixels;
                    pixels_emitted<=0;error_sticky<=0;frame_valid<=0;
                    beat_index_q<=0;emit_index_q<=0;lane_q<=0;
                    cancelled<=0;
                    if(valid_config)state<=ADDR;
                    else begin error_sticky[0]<=1;done_pulse<=1;end
                end
                ADDR: if(m_arready) begin
                    burst_beats_q<=next_burst_beats;
                    beat_index_q<=0;
                    state<=(cancelled||do_abort)?DRAIN:READ;
                end
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
                        if(beat_index_q+1==burst_beats_q) begin
                            emit_index_q<=0;lane_q<=0;
                            beat_pixels_q<=remaining>=32'd8 ? 4'd8 : 4'(remaining);
                            state<=EMIT;
                        end else beat_index_q<=beat_index_q+1;
                    end
                end
                EMIT: if(cancelled||do_abort)begin done_pulse<=1;state<=IDLE;end
                else if(pixel_ready) begin
                    pixels_emitted<=pixels_emitted+1;
                    if(lane_q+1==beat_pixels_q) begin
                        if(pixels_emitted+1==target_q) begin
                            frame_valid<=1;done_pulse<=1;state<=IDLE;
                        end else if(emit_index_q+1==burst_beats_q) state<=ADDR;
                        else begin
                            emit_index_q<=emit_index_q+1;lane_q<=0;
                            beat_pixels_q<=remaining>32'd9 ? 4'd8 :
                                           4'(remaining-1'b1);
                        end
                    end else lane_q<=lane_q+1;
                end
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
