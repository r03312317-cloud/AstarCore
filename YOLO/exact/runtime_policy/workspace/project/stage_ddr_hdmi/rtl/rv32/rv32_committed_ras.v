// Small prediction-only return stack. Only architecturally retired control
// instructions update it, in lane0 then lane1 order. No speculative state,
// recovery side effect, ISA-visible state, or benchmark-dependent behavior.
module rv32_committed_ras #(
    parameter DEPTH=16,
    parameter POINTER_BITS=$clog2(DEPTH)
)(
    input clk,reset,
    input train0,train1,
    input [31:0] instruction0,instruction1,pc0,pc1,
    output valid,
    output [31:0] top,
    output [POINTER_BITS:0] occupancy
);
    // The two ordered training events either push adjacent entries, or a
    // lane1 pop+push replaces lane0's just-pushed entry. Thus same-bank
    // writes always share one address and retain the younger lane1 value.
    (* syn_ramstyle="distributed_ram" *) reg [31:0] entries_even[0:DEPTH/2-1];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] entries_odd[0:DEPTH/2-1];
    reg [POINTER_BITS-1:0] pointer;
    reg [POINTER_BITS:0] count;
    reg [POINTER_BITS-1:0] pointer_next,write_index0,write_index1;
    reg [POINTER_BITS:0] count_next;
    reg write0,write1;
    wire [POINTER_BITS-1:0] top_index=pointer-1'b1;
    assign valid=count!=0;
    assign top=valid?(top_index[0]?entries_odd[top_index>>1]:entries_even[top_index>>1]):32'b0;
    assign occupancy=count;

    // RISC-V implicit RAS hints: JAL rd=x1/x5 pushes. JALR with a link
    // source pops unless rd is that SAME link; any link destination pushes.
    // Different link registers therefore pop then push (coroutines).
    function [1:0] action;
        input [31:0] instruction;
        reg destination_link,source_link;
        begin
            destination_link=instruction[11:7]==1||instruction[11:7]==5;
            source_link=instruction[19:15]==1||instruction[19:15]==5;
            action=0;
            if(instruction[6:0]==7'b1101111)action[1]=destination_link;
            else if(instruction[6:0]==7'b1100111&&instruction[14:12]==0)begin
                action[0]=source_link&&(!destination_link||instruction[11:7]!=instruction[19:15]);
                action[1]=destination_link;
            end
        end
    endfunction
    wire [1:0] action0=action(instruction0),action1=action(instruction1);
    always @*begin
        pointer_next=pointer;count_next=count;
        write0=0;write1=0;write_index0=0;write_index1=0;
        if(train0)begin
            if(action0[0]&&count_next!=0)begin
                pointer_next=pointer_next-1'b1;count_next=count_next-1'b1;
            end
            if(action0[1])begin
                write0=1;write_index0=pointer_next;pointer_next=pointer_next+1'b1;
                if(count_next<DEPTH)count_next=count_next+1'b1;
            end
        end
        if(train1)begin
            if(action1[0]&&count_next!=0)begin
                pointer_next=pointer_next-1'b1;count_next=count_next-1'b1;
            end
            if(action1[1])begin
                write1=1;write_index1=pointer_next;pointer_next=pointer_next+1'b1;
                if(count_next<DEPTH)count_next=count_next+1'b1;
            end
        end
    end
    always @(posedge clk)begin
        if(reset)begin pointer<=0;count<=0;end
        else begin
            pointer<=pointer_next;count<=count_next;
        end
    end
    // One dynamic write port per parity bank; payload remains unreset.
    // A saturated push still replaces the oldest retained entry.
    always @(posedge clk)if(!reset)begin
        if(write1&&!write_index1[0])entries_even[write_index1>>1]<=pc1+32'd4;
        else if(write0&&!write_index0[0])entries_even[write_index0>>1]<=pc0+32'd4;
        if(write1&&write_index1[0])entries_odd[write_index1>>1]<=pc1+32'd4;
        else if(write0&&write_index0[0])entries_odd[write_index0>>1]<=pc0+32'd4;
    end
`ifdef VERILATOR
    initial if(DEPTH!=8&&DEPTH!=16)$fatal(1,"Committed RAS supports depth 8 or 16");
    always @(posedge clk)if(!reset&&count>DEPTH)$fatal(1,"Committed RAS count overflow");
`endif
endmodule
