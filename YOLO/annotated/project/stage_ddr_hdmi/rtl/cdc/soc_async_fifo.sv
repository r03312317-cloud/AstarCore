// Dual-clock FIFO, binary local pointers and two-stage Gray-pointer crossings.
// Storage is intentionally small FF/LUT RAM with asynchronous read (not BRAM).
// Data is stable BEFORE the synchronized write pointer exposes it to the reader.
// CDC PHYSICAL REQUIREMENT: constrain Gray Q->first synchronizer D max delay and
// bus skew to the smaller clock period. See docs/CDC_AND_RESET.md.
// Reset contract: w_rst and r_rst assert together (common system reset), release
// synchronously in their local clocks. Never reset only one side while active.
// 架构导读：soc_async_fifo。
// FIFO 缓冲模块，隔离生产者与消费者，满/空条件由指针和容量关系决定。
module soc_async_fifo #(
    // 静态配置：parameter integer WIDTH=32。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter integer WIDTH=32,
    parameter integer ADDR_BITS=4
)(
    input logic w_clk,w_rst,w_valid,output logic w_ready,input logic [WIDTH-1:0] w_data,
    input logic r_clk,r_rst,output logic r_valid,input logic r_ready,output logic [WIDTH-1:0] r_data
);
    localparam integer DEPTH=1<<ADDR_BITS;
    localparam integer PW=ADDR_BITS+1;
    (* syn_ramstyle="registers" *) logic [WIDTH-1:0] storage[0:DEPTH-1];
    logic [PW-1:0] wbin,wgray,rbin,rgray,wbin_next,wgray_next,rbin_next,rgray_next;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) logic [PW-1:0] rgray_w1,rgray_w2,wgray_r1,wgray_r2;
    logic full,empty;
    initial if(ADDR_BITS<2||WIDTH<1) $fatal(1,"SOC_ASYNC_FIFO_PARAMETERS");
    assign w_ready=!w_rst&&!full;
    assign r_valid=!r_rst&&!empty;
    assign r_data=storage[rbin[ADDR_BITS-1:0]];
    assign wbin_next=wbin+{{(PW-1){1'b0}},(w_valid&&w_ready)};
    assign rbin_next=rbin+{{(PW-1){1'b0}},(r_valid&&r_ready)};
    assign wgray_next=(wbin_next>>1)^wbin_next;
    assign rgray_next=(rbin_next>>1)^rbin_next;
    // 过程边界：always_ff @(posedge w_clk or posedge w_rst) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge w_clk or posedge w_rst) begin
        // 复位相关判断：w_rst；分支方向由信号极性与取反表达式决定。
        if(w_rst) begin wbin<='0;wgray<='0;full<=0;rgray_w1<='0;rgray_w2<='0;end
        else begin
            rgray_w1<=rgray;rgray_w2<=rgray_w1;
            wbin<=wbin_next;wgray<=wgray_next;
            full<=wgray_next=={~rgray_w2[PW-1:PW-2],rgray_w2[PW-3:0]};
        end
    end
    // No reset loop on payload RAM; pointers make stale payload inaccessible.
    always_ff @(posedge w_clk) begin
        // 握手/背压判断：w_valid&&w_ready。
        // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
        if(w_valid&&w_ready) storage[wbin[ADDR_BITS-1:0]]<=w_data;
    end
    // 过程边界：always_ff @(posedge r_clk or posedge r_rst) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge r_clk or posedge r_rst) begin
        // 复位相关判断：r_rst；分支方向由信号极性与取反表达式决定。
        if(r_rst) begin rbin<='0;rgray<='0;empty<=1;wgray_r1<='0;wgray_r2<='0;end
        else begin
            wgray_r1<=wgray;wgray_r2<=wgray_r1;
            rbin<=rbin_next;rgray<=rgray_next;
            empty<=rgray_next==wgray_r2;
        end
    end
`ifdef DC_RT_VERIFICATION
    assert property (@(posedge w_clk) disable iff(w_rst) w_valid&&!w_ready |=> w_valid&&$stable(w_data))
        else $fatal(1,"ASYNC_FIFO_WRITER_CHANGED_HELD_REQUEST");
    assert property (@(posedge r_clk) disable iff(r_rst) r_valid&&!r_ready |=> r_valid&&$stable(r_data))
        else $fatal(1,"ASYNC_FIFO_READER_RESPONSE_NOT_HELD");
`endif
endmodule
