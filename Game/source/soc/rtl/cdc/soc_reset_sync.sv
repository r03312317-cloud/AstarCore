// [ARCH] 异步进入复位、在目标时钟域同步释放。
// [ARCH] 同步链传播期间保持复位有效，不能用组合连线代替。
// [ARCH] 时钟尚未运行时不会完成同步释放。
// [ARCH] PLL/DDR 就绪条件由上层额外提供。
// One COMMON asynchronous reset must reach ALL three domains and the DDR AXI
// slave. Asynchronous assertion, synchronous release after three local edges.
// Independent/warm domain resets with transactions in flight are unsupported.
module soc_reset_sync(input logic clk, arst, output logic rst);
    (* ASYNC_REG="TRUE", syn_preserve=1 *) logic [2:0] release_pipe;
    always_ff @(posedge clk or posedge arst) begin
        if(arst) release_pipe<=3'b111;
        else release_pipe<={release_pipe[1:0],1'b0};
    end
    assign rst=release_pipe[2];
endmodule
