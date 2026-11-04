// For a level that remains asserted until software acknowledges it, NOT pulses.
// 单比特状态通过本域同步链进入逻辑，只适用于足够稳定的电平信号。
// 窄脉冲或多位总线不能直接套用此模块，前者可能丢失，后者可能得到不一致快照。
// 异步输入与第一同步级之间仍有亚稳态可能，后续级用于降低传播概率。
module soc_level_sync(input logic clk,rst,async_level,output logic level);
    (* PAP_ASYNC_REG=1, syn_preserve=1 *) logic meta_q,sync_q;
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin meta_q<=0;sync_q<=0;end
        else begin meta_q<=async_level;sync_q<=meta_q;end
    end
    assign level=sync_q;
endmodule
