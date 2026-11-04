// SPDX-License-Identifier: MIT
// Serial DDR loader. CPU remains reset until a host explicitly sends B and
// the K reply has fully left the UART. W packets carry one 16-byte aligned
// block and CRC32(address_le || data); every write is read back before ACK.
// This loads volatile DDR only; it does not write configuration flash.
// 串口加载器在 CPU 保持复位时把 OpenSBI Linux DTB 及根文件系统写入 DDR。
// W 包携带 16 字节对齐地址和数据，并以 CRC32 校验地址及 payload。
// 每块先完成 DDR 写响应，再读回比对，成功后才向主机发送 K。
// B 命令只在合法加载状态释放 CPU，且等待启动 K 的串口发送完整结束。
// 超时 非法包 地址错误或回读不符会走故障处理，不能继续冒充上传成功。
// 本版主机先进行 120 块试写，再上传 308423 块固件；这是主机策略而非 RTL 常量。
module rv32_uart_ddr_loader #(
    parameter integer UART_DIV=234,
    parameter integer PACKET_TIMEOUT=13500000,
    parameter [31:0] RAM_BASE=32'h80000000,
    parameter [31:0] RAM_LIMIT=32'h84000000
)(
    // ddr_ready 保存接收或操作数就绪资格，须结合对应的有效位使用。
    input wire clk,reset,ddr_ready,input wire uart_rx,output wire uart_tx,
    // boot_release 加载器完成启动应答后的 CPU 运行许可，同时选择 UART TX 的拥有者。
    output reg boot_release,output reg loader_fault,
    // mem_req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output wire mem_req_valid,input wire mem_req_ready,output wire mem_req_write,
    // mem_req_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    output wire [31:0] mem_req_addr,output wire [127:0] mem_req_wdata,
    // mem_req_wstrb 保存逐字节写使能，未使能的字节保持原值。
    output wire [15:0] mem_req_wstrb,output wire [3:0] mem_req_tag,
    // mem_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    input wire mem_rsp_valid,output wire mem_rsp_ready,input wire mem_rsp_write,
    // mem_rsp_rdata 保存读响应 payload，须在响应有效时才能使用。
    input wire [127:0] mem_rsp_rdata,input wire [3:0] mem_rsp_tag,input wire mem_rsp_error
);
    localparam [4:0] POLL_REQ=0,POLL_WAIT=1,RX_REQ=2,RX_WAIT=3,
                     MEM_W_REQ=4,MEM_W_WAIT=5,MEM_R_REQ=6,MEM_R_WAIT=7,
                     TX_POLL_REQ=8,TX_POLL_WAIT=9,TX_WRITE_REQ=10,TX_WRITE_WAIT=11,
                     TX_DONE_REQ=12,TX_DONE_WAIT=13,FINISHED=14;
    // state 保存协议或执行状态，决定本周期允许的阶段与握手动作。
    reg [4:0] state;
    reg packet_active,boot_after_tx;
    // byte_index 保存表或队列的索引，须配合有效位与对应所有者使用。
    reg [4:0] byte_index;
    // timeout_count 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
    reg [31:0] timeout_count,address_q,crc_q,received_crc;
    reg [127:0] payload_q;
    reg [7:0] response_byte;
    // uart_req_ready 保存接收或操作数就绪资格，须结合对应的有效位使用。
    wire uart_req_ready,uart_rsp_valid,uart_rsp_error;
    wire [31:0] uart_rsp_data;
    // uart_req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    // uart_req_valid 的资格组合为 (state==POLL_REQ && ddr_ready) || state==RX_REQ || state==TX_POLL_REQ || state==TX_WRITE_REQ || state==TX_DONE_REQ。
    // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
    wire uart_req_valid=(state==POLL_REQ && ddr_ready) || state==RX_REQ ||
                        // state 的资格组合为 =TX_POLL_REQ || state==TX_WRITE_REQ || state==TX_DONE_REQ。
                        state==TX_POLL_REQ || state==TX_WRITE_REQ || state==TX_DONE_REQ;
    // uart_write 由比较式 state==TX_WRITE_REQ 产生；该结果是条件判断，不是被比较的数据。
    wire uart_write=state==TX_WRITE_REQ;
    // uart_address 保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
    // uart_address 按 (state==RX_REQ) 进行来源选择。
    // 真分支取 8'h04；其余情况取 (state==TX_WRITE_REQ)?8'h00:8'h10。
    wire [7:0] uart_address=(state==RX_REQ)?8'h04:(state==TX_WRITE_REQ)?8'h00:8'h10;
    // rx_event 的资格组合为 state==RX_WAIT && uart_rsp_valid && !uart_rsp_error。
    wire rx_event=state==RX_WAIT && uart_rsp_valid && !uart_rsp_error;
    // rx_byte 读取 uart_rsp_data[7:0] 所选位域；位索引按声明中的高低位顺序解释。
    wire [7:0] rx_byte=uart_rsp_data[7:0];

    // 子模块 rv32_uart 的职责：UART 用输入时钟分频生成串行节拍，对外为 8N1 字节流。
    // 下列命名端口把本层信号连接到该模块，参数覆盖以实例中的原代码为准。
    rv32_uart #(.RESET_DIVISOR(UART_DIV)) serial(
        .clk(clk),.reset(reset),.rx(uart_rx),.tx(uart_tx),
        .req_valid(uart_req_valid),.req_ready(uart_req_ready),.req_write(uart_write),
        .req_addr(uart_address),.req_wdata({24'd0,response_byte}),.req_wstrb(4'hf),
        .rsp_valid(uart_rsp_valid),.rsp_ready(1'b1),.rsp_rdata(uart_rsp_data),
        .rsp_error(uart_rsp_error),.irq());

    function [31:0] crc32_byte;
        input [31:0] crc;
        input [7:0] value;
        reg [31:0] c;
        integer k;
        begin
            // c 对 crc ^ {24'd0,value} 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
            c=crc ^ {24'd0,value};
            for(k=0;k<8;k=k+1) c=c[0] ? (c>>1)^32'hedb88320 : c>>1;
            // crc32_byte 连接到 c，两者在此路径上保持字段对应。
            crc32_byte=c;
        end
    endfunction
    // mem_req_valid 的资格组合为 (state==MEM_W_REQ || state==MEM_R_REQ) && ddr_ready。
    assign mem_req_valid=(state==MEM_W_REQ || state==MEM_R_REQ) && ddr_ready;
    // mem_req_write 由比较式 state==MEM_W_REQ 产生；该结果是条件判断，不是被比较的数据。
    assign mem_req_write=state==MEM_W_REQ;
    // mem_req_addr 连接到 address_q，两者在此路径上保持字段对应。
    assign mem_req_addr=address_q;
    // mem_req_wdata 连接到 payload_q，两者在此路径上保持字段对应。
    assign mem_req_wdata=payload_q;
    // mem_req_wstrb 按 state==MEM_W_REQ 选择候选来源；各分支结果仍属于当前组合路径。
    // mem_req_wstrb 按 state==MEM_W_REQ 进行来源选择。
    // 真分支取 16'hffff；其余情况取 16'h0000。
    assign mem_req_wstrb=state==MEM_W_REQ ? 16'hffff : 16'h0000;
    // mem_req_tag 按 state==MEM_W_REQ 选择候选来源；各分支结果仍属于当前组合路径。
    // mem_req_tag 按 state==MEM_W_REQ 进行来源选择。
    // 真分支取 4'hc；其余情况取 4'hd。
    assign mem_req_tag=state==MEM_W_REQ ? 4'hc : 4'hd;
    // mem_rsp_ready 的资格组合为 state==MEM_W_WAIT || state==MEM_R_WAIT。
    assign mem_rsp_ready=state==MEM_W_WAIT || state==MEM_R_WAIT;

    always @(posedge clk) begin
        // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
        if(reset) begin
            // state 在此时钟更新路径捕获 POLL_REQ，该更新仍受外层条件与后续同块赋值优先级限定。
            // 本时钟边界的 state 捕获 POLL_REQ，两者在此路径上保持字段对应。
            state<=POLL_REQ;packet_active<=0;boot_release<=0;loader_fault<=0;
            byte_index<=0;timeout_count<=0;address_q<=0;payload_q<=0;
            crc_q<=32'hffffffff;received_crc<=0;response_byte<=0;boot_after_tx<=0;
        end else begin
            if(!packet_active || rx_event) timeout_count<=0;
            else if(timeout_count<PACKET_TIMEOUT) timeout_count<=timeout_count+1'b1;
            if(packet_active && !rx_event && timeout_count>=PACKET_TIMEOUT-1 && state<=RX_WAIT) begin
                packet_active<=0;response_byte<=8'h45;boot_after_tx<=0;state<=TX_POLL_REQ;
            end else case(state)
              POLL_REQ: if(ddr_ready && uart_req_ready) state<=POLL_WAIT;
              POLL_WAIT: if(uart_rsp_valid) begin
                  if(uart_rsp_error) begin loader_fault<=1;state<=POLL_REQ;end
                  else state<=uart_rsp_data[0] ? RX_REQ : POLL_REQ;
              end
              RX_REQ: if(uart_req_ready) state<=RX_WAIT;
              RX_WAIT: if(uart_rsp_valid) begin
                  if(uart_rsp_error) begin loader_fault<=1;packet_active<=0;response_byte<=8'h45;state<=TX_POLL_REQ;end
                  else if(!packet_active) begin
                      case(rx_byte)
                        8'h50: begin response_byte<=8'h70;boot_after_tx<=0;state<=TX_POLL_REQ;end // P -> p
                        8'h57: begin packet_active<=1;byte_index<=0;address_q<=0;payload_q<=0;
                                     crc_q<=32'hffffffff;received_crc<=0;state<=POLL_REQ;end
                        8'h42: begin response_byte<=8'h4b;boot_after_tx<=1;state<=TX_POLL_REQ;end // B -> K
                        default: begin response_byte<=8'h45;boot_after_tx<=0;state<=TX_POLL_REQ;end
                      endcase
                  end else if(byte_index<4) begin
                      // 本时钟边界的 address_q[byte_index*8 +: 8] 捕获 rx_byte，两者在此路径上保持字段对应。
                      address_q[byte_index*8 +: 8]<=rx_byte;
                      crc_q<=crc32_byte(crc_q,rx_byte);byte_index<=byte_index+1'b1;state<=POLL_REQ;
                  end else if(byte_index<20) begin
                      // 本时钟边界的 payload_q[(byte_index-4)*8 +: 8] 捕获 rx_byte，两者在此路径上保持字段对应。
                      payload_q[(byte_index-4)*8 +: 8]<=rx_byte;
                      crc_q<=crc32_byte(crc_q,rx_byte);byte_index<=byte_index+1'b1;state<=POLL_REQ;
                  end else if(byte_index<23) begin
                      // 本时钟边界的 received_crc[(byte_index-20)*8 +: 8] 捕获 rx_byte，两者在此路径上保持字段对应。
                      received_crc[(byte_index-20)*8 +: 8]<=rx_byte;
                      // byte_index 在此时钟更新路径捕获 byte_index+1'b1，该更新仍受外层条件与后续同块赋值优先级限定。
                      // 本时钟边界的 byte_index 按 byte_index+1'b1 计算，运算位宽与有无符号以原声明和显式扩展为准。
                      byte_index<=byte_index+1'b1;state<=POLL_REQ;
                  end else begin
                      packet_active<=0;boot_after_tx<=0;
                      if({rx_byte,received_crc[23:0]}!=~crc_q || address_q[3:0]!=0 ||
                         address_q<RAM_BASE || address_q>RAM_LIMIT-32'd16) begin
                          response_byte<=8'h45;state<=TX_POLL_REQ;
                      end else state<=MEM_W_REQ;
                  end
              end
              MEM_W_REQ: if(mem_req_valid && mem_req_ready) state<=MEM_W_WAIT;
              MEM_W_WAIT: if(mem_rsp_valid) begin
                  if(mem_rsp_error || !mem_rsp_write || mem_rsp_tag!=4'hc) begin
                      loader_fault<=1;response_byte<=8'h45;state<=TX_POLL_REQ;
                  end else state<=MEM_R_REQ;
              end
              MEM_R_REQ: if(mem_req_valid && mem_req_ready) state<=MEM_R_WAIT;
              MEM_R_WAIT: if(mem_rsp_valid) begin
                  if(mem_rsp_error || mem_rsp_write || mem_rsp_tag!=4'hd || mem_rsp_rdata!=payload_q) begin
                      loader_fault<=1;response_byte<=8'h45;
                  end else response_byte<=8'h4b;
                  // state 在此时钟更新路径捕获 TX_POLL_REQ，该更新仍受外层条件与后续同块赋值优先级限定。
                  // 本时钟边界的 state 捕获 TX_POLL_REQ，两者在此路径上保持字段对应。
                  state<=TX_POLL_REQ;
              end
              TX_POLL_REQ: if(uart_req_ready) state<=TX_POLL_WAIT;
              TX_POLL_WAIT: if(uart_rsp_valid) begin
                  if(uart_rsp_error) begin loader_fault<=1;state<=TX_POLL_REQ;end
                  else state<=uart_rsp_data[1] ? TX_WRITE_REQ : TX_POLL_REQ;
              end
              TX_WRITE_REQ: if(uart_req_ready) state<=TX_WRITE_WAIT;
              TX_WRITE_WAIT: if(uart_rsp_valid) begin
                  if(uart_rsp_error) begin loader_fault<=1;state<=TX_POLL_REQ;end
                  else state<=TX_DONE_REQ;
              end
              TX_DONE_REQ: if(uart_req_ready) state<=TX_DONE_WAIT;
              TX_DONE_WAIT: if(uart_rsp_valid) begin
                  if(uart_rsp_error) begin loader_fault<=1;state<=TX_DONE_REQ;end
                  else if(uart_rsp_data[1]) begin
                      if(boot_after_tx) begin boot_release<=1;state<=FINISHED;end
                      else state<=POLL_REQ;
                  end else state<=TX_DONE_REQ;
              end
              FINISHED: state<=FINISHED;
              default: begin loader_fault<=1;state<=POLL_REQ;end
            endcase
        end
    end
endmodule
