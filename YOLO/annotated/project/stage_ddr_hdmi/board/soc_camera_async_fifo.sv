// Pixel FIFO: common asynchronous reset, synchronous release in each domain.
// Gray pointers cross two synchronizers. The read port prefetches into a
// holding register, so capacity is DEPTH RAM entries plus that output word.
// Payload RAM has no reset and synchronous read/write ports; request block RAM
// inference. Actual Pango resource mapping must be verified after integration.
// Physical integration must bound Gray-bus skew/delay, not only cut clocks.
// 架构导读：soc_camera_async_fifo。
// 隔离摄像头像素域与接收消费域，传递数据及其有效边界。
module soc_camera_async_fifo #(
    // 静态配置：parameter int WIDTH=16, DEPTH=1024。
    parameter int WIDTH=16, DEPTH=1024
)(
    input logic wr_clk, rd_clk, arst,
    input logic in_valid,
    output logic in_ready,
    input logic [WIDTH-1:0] in_data,
    output logic out_valid,
    input logic out_ready,
    output logic [WIDTH-1:0] out_data
);
    timeunit 1ns; timeprecision 1ps;
    localparam int AW=$clog2(DEPTH), PW=AW+1;
    logic wr_rst, rd_rst;
    pg_reset_sync wr_release(.clk(wr_clk),.arst,.rst(wr_rst));
    pg_reset_sync rd_release(.clk(rd_clk),.arst,.rst(rd_rst));
    logic [PW-1:0] wbin, rbin, wgray, rgray, wnext, rnext, wgnext, rgnext;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic [PW-1:0] rg1,rg2,wg1,wg2;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic ru1,ru2,wu1,wu2;
    (* ram_style="block", syn_ramstyle="block_ram" *) logic [WIDTH-1:0] memory[DEPTH];
    logic full, empty, read_valid;
    logic [WIDTH-1:0] read_data;
    wire push=in_valid&&in_ready;
    wire load=!rd_rst&&wu2&&!empty&&(!read_valid||out_ready);
    assign in_ready=!wr_rst&&ru2&&!full;
    assign out_valid=!rd_rst&&wu2&&read_valid;
    assign out_data=read_data;
    assign wnext=wbin+PW'(push);
    assign rnext=rbin+PW'(load);
    assign wgnext=(wnext>>1)^wnext;
    assign rgnext=(rnext>>1)^rnext;
    // 过程边界：always_ff @(posedge wr_clk or posedge wr_rst) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge wr_clk or posedge wr_rst) begin
        // 复位相关判断：wr_rst；分支方向由信号极性与取反表达式决定。
        if (wr_rst) begin wbin<=0; wgray<=0; full<=0; rg1<=0; rg2<=0; ru1<=0; ru2<=0; end
        else begin
            rg1<=rgray; rg2<=rg1; ru1<=!rd_rst; ru2<=ru1;
            wbin<=wnext; wgray<=wgnext; full<=(wgnext==(rg2^(PW'(3)<<(PW-2))));
        end
    end
    // 过程边界：always_ff @(posedge rd_clk or posedge rd_rst) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge rd_clk or posedge rd_rst) begin
        // 复位相关判断：rd_rst；分支方向由信号极性与取反表达式决定。
        if (rd_rst) begin rbin<=0; rgray<=0; empty<=1; read_valid<=0; wg1<=0; wg2<=0; wu1<=0; wu2<=0; end
        else begin
            wg1<=wgray; wg2<=wg1; wu1<=!wr_rst; wu2<=wu1;
            rbin<=rnext; rgray<=rgnext; empty<=(rgnext==wg2);
            if (load) read_valid<=1;
            // 握手/背压判断：out_valid&&out_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            else if (out_valid&&out_ready) read_valid<=0;
        end
    end
    // 过程边界：always_ff @(posedge wr_clk) if(push) memory[wbin[AW-1:0]]<=in_data;。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge wr_clk) if(push) memory[wbin[AW-1:0]]<=in_data;
    // 过程边界：always_ff @(posedge rd_clk) if(load) read_data<=memory[rbin[AW-1:0]];。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge rd_clk) if(load) read_data<=memory[rbin[AW-1:0]];
    initial if(WIDTH<1||DEPTH<2||(DEPTH&(DEPTH-1))!=0) $fatal(1,"CAMERA_FIFO_PARAMETER");
endmodule
