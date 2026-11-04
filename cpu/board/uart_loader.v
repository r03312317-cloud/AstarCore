// UART boot loader: receives a raw binary (64-byte padded) at 115200-8N1 from
// the board UART and writes it into the board SRAM via the writeback channel.
// CPU stays in reset until the host link goes idle or the image is complete.
// If no byte arrives within AUTOBOOT_CYCLES the CPU boots the BRAM-initialized
// image instead. After a UART load it sends "BOOT"+count32 before releasing.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// UART 固件装载状态机，在 CPU 启动前把收到的字节组成 SRAM 写数据。
// 接收与发送使用 UART_DIV，真实板卡按 130MHz 和 115200 波特率配置。
// 装载期通过 loading 选择存储通道所有者，CPU 持续复位，避免同时写存储。
// 可等待写响应并经读回校验；loader 协议日志与应用程序的 CoreMark
// 输出属于不同阶段。
// AUTOBOOT_CYCLES 允许超时后运行已有初始化固件；仿真只缩短此启动等待。
// 写请求与读回确认需遵守 ready/gnt/rvalid，不在本模块识别或计算 CoreMark 算法。
// 复位恢复协议接收和传输状态，已收到的载荷本身不构成应用固件验证通过。
// 接口契约与阅读示例
// loader装载过程与CoreMark运行过程分开，下载字节数不能当成CPU退休数量。
// CPU保持复位期间的写回路径由loader选择，
// 已载入的存储内容需要读回或哈希证据核验。
// 协议同步字、长度和校验状态决定何时退出loading，不能仅因串口有字节就启动CPU。
// 若主机错过装载窗口，自动启动可能运行旧初始化固件，
// 因此实板记录需要绑定固件哈希。
// 本交付保留原板级loader，不更改其握手、超时和波特率行为。
module uart_loader #(
    // 参数 UART_DIV：UART位周期的CPU时钟分频，
    // 板卡115200波特率与仿真加速配置需区分。
    parameter UART_DIV=1042,
    // 参数 AUTOBOOT_CYCLES：loader自动启动等待；
    // 仿真缩短它只加速计时窗口外的启动。
    parameter [31:0] AUTOBOOT_CYCLES=32'd2400000000
)(
    // 接口字段：input clk, reset。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input clk, reset,
    // 接口字段：input uart_rx。
    // UART串行通信或接收发送状态；串口传输耗时不作为CoreMark算法计时分母。
    input uart_rx,
    // 接口字段：output reg loading。
    // UART 固件装载状态机，在 CPU 启动前把收到的字节组成 SRAM 写数据。
    output reg loading,
    // 接口字段：output reg [31:0] loaded_bytes。
    // UART 固件装载状态机，在 CPU 启动前把收到的字节组成 SRAM 写数据。
    output reg [31:0] loaded_bytes,
    // 接口字段：output reg w_req, input w_gnt。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    output reg w_req, input w_gnt,
    // 接口字段：output reg [31:0] w_addr, output reg [63:0] w_data。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
    output reg [31:0] w_addr, output reg [63:0] w_data,
    // 接口字段：output reg w_last, output w_id。
    // UART 固件装载状态机，在 CPU 启动前把收到的字节组成 SRAM 写数据。
    output reg w_last, output w_id,
    // 接口字段：input b_valid, input b_error。
    // 错误或非法资格。需随相应有效指令/事务传播，最终在精确提交边界处理。
    input b_valid, input b_error,
    // 接口字段：output reg tx, output reg tx_busy。
    // UART串行通信或接收发送状态；串口传输耗时不作为CoreMark算法计时分母。
    output reg tx, output reg tx_busy,
    // read-back verify channel (board-memory data port, used while loading)
    // 接口字段：output reg d_req, input d_gnt, output reg [31:0] d_addr。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    output reg d_req, input d_gnt, output reg [31:0] d_addr,
    // 接口字段：input d_valid, input [63:0] d_data, input d_error。
    // 错误或非法资格。需随相应有效指令/事务传播，最终在精确提交边界处理。
    input d_valid, input [63:0] d_data, input d_error
);
    assign w_id=1'b0;
    localparam [23:0] GAP_CYCLES=24'd10066330; // ~84 ms idle ends the load

    // ---- UART RX ----
    reg [1:0] rx_sync;
    always @(posedge clk) rx_sync<={rx_sync[0],uart_rx};
    wire rx=rx_sync[1];
    reg [10:0] rx_baud; reg [3:0] rx_bit; reg [7:0] rx_byte;
    reg rx_active; reg rx_valid;
    always @(posedge clk) begin
        if(reset) begin rx_baud<=0; rx_bit<=0; rx_active<=0; rx_valid<=0; rx_byte<=0; end
        else begin
            rx_valid<=0;
            if(!rx_active) begin
                if(!rx) begin rx_active<=1; rx_baud<=(UART_DIV>>1); rx_bit<=0; end
            end else if(rx_baud==UART_DIV-1) begin
                rx_baud<=0;
                if(rx_bit==0) begin
                    if(rx) rx_active<=0;          // false start
                    else rx_bit<=1;
                end else if(rx_bit<=8) begin
                    rx_byte<={rx,rx_byte[7:1]}; rx_bit<=rx_bit+1'b1;
                end else begin
                    rx_active<=0;
                    if(rx) rx_valid<=1;           // stop bit present
                end
            end else rx_baud<=rx_baud+1'b1;
        end
    end

    // ---- control + write channel + TX message (single process) ----
    localparam L_WAIT=0,L_RX=1,L_WRITE=2,L_MSG=3,L_DONE=4,
               L_VREQ=5,L_VRECV=6,L_VMSG=7;
    reg [12:0] v_line; reg [2:0] v_beat; reg [63:0] checksum;
    reg [2:0] st;
    reg [2:0] byte_idx, beat_idx;
    reg [63:0] beat_shift;
    reg [31:0] wait_count; reg [23:0] gap_count;
    // TX serializer
    reg [10:0] tx_baud; reg [3:0] tx_bit; reg [7:0] tx_cur; reg tx_send;
    reg [4:0] msg_idx;

    // message: "BOOT" count32 | "VRFY" checksum64  (20 bytes)
    wire [4:0] mi=msg_idx;
    wire [7:0] msg_byte =
        (mi==0)?8'h42:(mi==1)?8'h4F:(mi==2)?8'h4F:(mi==3)?8'h54:
        (mi==4)?loaded_bytes[7:0]:(mi==5)?loaded_bytes[15:8]:
        (mi==6)?loaded_bytes[23:16]:(mi==7)?loaded_bytes[31:24]:
        (mi==8)?8'h56:(mi==9)?8'h52:(mi==10)?8'h46:(mi==11)?8'h59:
        checksum[8*(mi-12) +: 8];

    always @(posedge clk) begin
        if(reset) begin
            st<=L_WAIT; loading<=1; loaded_bytes<=0;
            byte_idx<=0; beat_idx<=0; beat_shift<=0;
            w_req<=0; w_last<=0; w_addr<=32'h10000000; w_data<=0;
            wait_count<=0; gap_count<=0;
            tx<=1; tx_busy<=0; tx_send<=0; tx_baud<=0; tx_bit<=0; tx_cur<=0; msg_idx<=0;
            d_req<=0; d_addr<=32'h10000000; v_line<=0; v_beat<=0; checksum<=0;
        end else begin
            case(st)
                L_WAIT: begin
                    if(rx_valid) begin
                        st<=L_RX; loaded_bytes<=1;
                        beat_shift<={rx_byte,56'd0}; byte_idx<=1;
                        wait_count<=0; gap_count<=0;
                    end else if(wait_count==AUTOBOOT_CYCLES) begin
                        loading<=0; st<=L_DONE;
                    end else wait_count<=wait_count+1'b1;
                end
                L_RX: begin
                    if(rx_valid) begin
                        gap_count<=0;
                        loaded_bytes<=loaded_bytes+1'b1;
                        if(byte_idx==7) begin
                            w_data<={rx_byte,beat_shift[63:8]};
                            w_req<=1; w_last<=(beat_idx==7);
                            st<=L_WRITE;
                        end else begin
                            beat_shift<={rx_byte,beat_shift[63:8]};
                            byte_idx<=byte_idx+1'b1;
                        end
                    end else if(gap_count==GAP_CYCLES) begin
                        st<=L_MSG; msg_idx<=0; tx_busy<=1;
                    end else gap_count<=gap_count+1'b1;
                end
                L_WRITE: begin
                    if(w_req && w_gnt) begin
                        w_req<=0; w_last<=0;
                        if(beat_idx==7) begin
                            beat_idx<=0; w_addr<=w_addr+32'd64;
                        end else beat_idx<=beat_idx+1'b1;
                        st<=L_RX; byte_idx<=0;
                    end
                end
                L_MSG: begin
                    if(!tx_send) begin
                        if(msg_idx==8) begin
                            // BOOT message done; verify what landed in SRAM.
                            st<=L_VREQ; v_line<=0; checksum<=0;
                            d_addr<=32'h10000000;
                        end
                        else begin
                            tx_send<=1; tx_cur<=msg_byte;
                            tx_bit<=0; tx_baud<=0; tx<=0;   // start bit now
                        end
                    end else if(tx_baud==UART_DIV-1) begin
                        tx_baud<=0;
                        if(tx_bit<8) begin tx<=tx_cur[tx_bit]; tx_bit<=tx_bit+1'b1; end
                        else if(tx_bit==8) begin tx<=1; tx_bit<=9; end
                        else begin tx_send<=0; msg_idx<=msg_idx+1'b1; end
                    end else tx_baud<=tx_baud+1'b1;
                end
                L_VREQ: begin
                    if(loaded_bytes==0) begin st<=L_DONE; loading<=0; end
                    else if(!d_req) d_req<=1;
                    else if(d_gnt) begin d_req<=0; v_beat<=0; st<=L_VRECV; end
                end
                L_VRECV: begin
                    if(d_valid) begin
                        checksum<=checksum^d_data;
                        if(v_beat==7) begin
                            if(d_addr==32'h10000000+{loaded_bytes[31:6],6'b0}-32'd64)
                                begin st<=L_VMSG; msg_idx<=8; end
                            else begin d_addr<=d_addr+32'd64; st<=L_VREQ; end
                        end else v_beat<=v_beat+1'b1;
                    end
                end
                L_VMSG: begin
                    if(!tx_send) begin
                        if(msg_idx==20) begin tx_busy<=0; loading<=0; st<=L_DONE; end
                        else begin
                            tx_send<=1; tx_cur<=msg_byte;
                            tx_bit<=0; tx_baud<=0; tx<=0;
                        end
                    end else if(tx_baud==UART_DIV-1) begin
                        tx_baud<=0;
                        if(tx_bit<8) begin tx<=tx_cur[tx_bit]; tx_bit<=tx_bit+1'b1; end
                        else if(tx_bit==8) begin tx<=1; tx_bit<=9; end
                        else begin tx_send<=0; msg_idx<=msg_idx+1'b1; end
                    end else tx_baud<=tx_baud+1'b1;
                end
                default: begin loading<=0; st<=L_DONE; end
            endcase
        end
    end
endmodule
