// One COMMON asynchronous reset must reach ALL three domains and the DDR AXI
// slave. Asynchronous assertion, synchronous release after three local edges.
// Independent/warm domain resets with transactions in flight are unsupported.
// 复位同步器允许异步请求复位，并在目标时钟域按寄存链同步释放。
// 上游复位极性在实例端转换，本模块输出语义以端口及赋值为准。
// 每个独立时钟域需要自己的释放链，不能把某个域的同步完成直接分给所有域。
module soc_reset_sync(input logic clk, arst, output logic rst);
    (* PAP_ASYNC_REG=1, syn_preserve=1 *) logic [2:0] release_pipe;
    always_ff @(posedge clk or posedge arst) begin
        if(arst) release_pipe<=3'b111;
        else release_pipe<={release_pipe[1:0],1'b0};
    end
    assign rst=release_pipe[2];
endmodule
