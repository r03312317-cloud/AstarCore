// For a level that remains asserted until software acknowledges it, NOT pulses.
module soc_level_sync(input logic clk,rst,async_level,output logic level);
    (* ASYNC_REG="TRUE", syn_preserve=1 *) logic meta_q,sync_q;
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin meta_q<=0;sync_q<=0;end
        else begin meta_q<=async_level;sync_q<=meta_q;end
    end
    assign level=sync_q;
endmodule
