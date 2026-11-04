// [ARCH] 聚合周期计时、GPIO 与 UART 的 MMIO 寄存器。
// [ARCH] 寄存器偏移需要与当前 game_regs.h 一致。
// [ARCH] UART 繁忙时可以背压软件写入，访问顺序不能省略。
// [ARCH] 分拆的 64 位计时需要一致读取，不能拼接回绕两侧数值。
// [ARCH] Mario 快速计时改用 CSR，本 MMIO 计时仍作为兼容接口。
// Single outstanding local MMIO. Side effects occur exactly at acceptance;
// the registered response remains stable until consumed. No DDR in this top.
module pg_cpu_peripherals #(
    parameter logic [31:0] CLOCK_HZ = 32'd100000000,
    parameter int UART_CLKS_PER_BIT = 868,
    parameter int UART_RX_DEPTH = 1
)(
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input logic clk, rst,
    // [ARCH] req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 accept 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic req_valid, output logic req_ready,
    // [ARCH] req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 addr_word 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [31:0] req_addr, req_wdata,
    // [ARCH] req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 tx_write, rx_ready, error_q, data_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic req_write, req_is_fetch, input logic [3:0] req_wstrb,
    // [ARCH] rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    output logic rsp_valid, input logic rsp_ready,
    // [ARCH] rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
    output logic [31:0] rsp_rdata, output logic rsp_error,
    input logic uart_rx, output logic uart_tx,
    input logic [31:0] gpio_in, output logic [31:0] gpio_out,
    output logic [31:0] diagnostic_mailbox,
    output logic [63:0] timer_gray
);
    logic pending, tx_valid, tx_ready, rx_valid, rx_ready;
    // [ARCH] frame_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 frame_sticky 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic frame_error, overrun, frame_sticky, overrun_sticky;
    // [ARCH] tx_data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 gpio_value, diagnostic_mailbox, tx_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [7:0] tx_data, rx_data;
    // [ARCH] rx_byte_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rx_valid, rx_data 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic rx_byte_valid,rx_byte_ready;
    // [ARCH] rx_byte_data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rx_valid, rx_data 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [7:0] rx_byte_data;
    // [ARCH] gpio_value：保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 diagnostic_mailbox, tx_valid, tx_data, data_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [31:0] gpio_value, gpio_sample, high_q, data_q;
    logic [63:0] ticks_q;
    // [ARCH] error_q：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_error, pending, data_q, ticks_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic error_q, tx_write, accept;
    initial if(CLOCK_HZ==0) $fatal(1,"PG_CLOCK_FREQUENCY_RED");
    // [ARCH] addr_word：地址与当前请求/响应归属配对，不能独立于有效条件使用。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 tx_write, rx_ready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    wire [31:0] addr_word = {req_addr[31:2],2'b00};
    function automatic logic [31:0] merge_bytes(input logic [31:0] oldword,newword,input logic [3:0] strobe);
        logic [31:0] v;
        v=oldword;
        for (int i=0;i<4;i++) if(strobe[i]) v[i*8+:8]=newword[i*8+:8];
        return v;
    endfunction
    assign tx_write = !req_is_fetch && req_write && req_wstrb[0] && addr_word==32'h30000020;
    assign req_ready = !rst && !pending && (!tx_write || !tx_valid);
    assign accept = req_valid && req_ready;
    assign rsp_valid = !rst && pending;
    assign rsp_rdata = data_q;
    assign rsp_error = error_q;
    assign rx_ready = accept && !req_is_fetch && !req_write && addr_word==32'h30000028;
    pg_uart #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) uart(
        .clk,.rst,.tx_valid,.tx_ready,.tx_data,.tx_pin(uart_tx),
        .rx_pin(uart_rx),.rx_valid(rx_byte_valid),.rx_ready(rx_byte_ready),
        .rx_data(rx_byte_data),.rx_frame_error(frame_error),.rx_overrun(overrun));
    // Buffer bounded control packets while CPU owns a complete inference.
    // The original pin receiver and its framing/overrun errors are retained.
    // A full queue stops draining its holding register; overflow is reported.
    generate if(UART_RX_DEPTH==1)begin:g_rx_legacy
        assign rx_valid=rx_byte_valid;assign rx_data=rx_byte_data;
        assign rx_byte_ready=rx_ready;
    end else begin:g_rx_buffered
        pg_sync_fifo #(.WIDTH(8),.DEPTH(UART_RX_DEPTH)) rx_fifo(
            .clk,.rst,.in_valid(rx_byte_valid),.in_ready(rx_byte_ready),.in_data(rx_byte_data),
            .out_valid(rx_valid),.out_ready(rx_ready),.out_data(rx_data),.level());
    end endgenerate
    pg_gpio gpio(.clk,.rst,.pins_in(gpio_in),.value_out(gpio_value),.pins_out(gpio_out),.sampled_in(gpio_sample));
    always_ff @(posedge clk) begin
        if(rst) begin
            pending<=0; data_q<=0; error_q<=0; ticks_q<=0; high_q<=0;timer_gray<=0;
            gpio_value<=0; diagnostic_mailbox<=0; tx_valid<=0; tx_data<=0;
            frame_sticky<=0; overrun_sticky<=0;
        end else begin
            ticks_q<=ticks_q+1'b1;
            // Registered Gray view of the same CP13 timer read at 0x60000000.
            // It trails ticks_q by one CPU clock; receivers report this bound.
            timer_gray<=(ticks_q>>1)^ticks_q;
            if(tx_valid && tx_ready) tx_valid<=0;
            if(pending && rsp_ready) pending<=0;
            if(accept) begin
                pending<=1; data_q<=0; error_q<=req_is_fetch;
                if(!req_is_fetch) case(addr_word)
                    32'h30000000: if(req_write) error_q<=1;
                        else begin data_q<=ticks_q[31:0]; high_q<=ticks_q[63:32]; end
                    32'h30000004: begin data_q<=high_q; if(req_write) error_q<=1; end
                    32'h30000008: begin data_q<=CLOCK_HZ; if(req_write) error_q<=1; end
                    32'h30000010: begin
                        data_q<=gpio_value;
                        if(req_write) gpio_value<=merge_bytes(gpio_value,req_wdata,req_wstrb);
                    end
                    32'h30000014: begin data_q<=gpio_sample; if(req_write) error_q<=1; end
                    32'h30000020: begin
                        data_q<={31'd0,!tx_valid};
                        if(tx_write) begin tx_data<=req_wdata[7:0]; tx_valid<=1; end
                    end
                    32'h30000024: begin
                        data_q<={28'd0,overrun_sticky,frame_sticky,!tx_valid,rx_valid};
                        if(req_write) error_q<=1;
                    end
                    32'h30000028: begin
                        data_q<=rx_valid?{24'd0,rx_data}:32'd0;
                        if(req_write) error_q<=1;
                    end
                    32'h3000002c: begin
                        data_q<={30'd0,overrun_sticky,frame_sticky};
                        if(req_write && req_wstrb[0]) begin
                            if(req_wdata[0]) frame_sticky<=0;
                            if(req_wdata[1]) overrun_sticky<=0;
                        end
                    end
                    32'h300000fc: begin
                        data_q<=diagnostic_mailbox;
                        if(req_write) diagnostic_mailbox<=merge_bytes(diagnostic_mailbox,req_wdata,req_wstrb);
                    end
                    default: error_q<=1;
                endcase
            end
            // Newly observed errors win over simultaneous software W1C.
            if(frame_error) frame_sticky<=1;
            if(overrun) overrun_sticky<=1;
        end
    end
endmodule
