// Original RV32 combinational payload factoring, Soc02 round 2.
// Ownership, issue masks, order, and cycle boundaries are unchanged.
module rv32_issue_payload_mux #(
    parameter WIDTH=91,
    parameter ENABLE_PAIRING=1
)(
    input reset,ex_hold,
    input [7:0] first_integer,second_integer,
    input [3:0] first_complex,
    input choose_complex,
    input [12*WIDTH-1:0] payload,
    output [WIDTH-1:0] value0,value1
);
    // Retain the completed bank reads before the late bank selector.
    reg [WIDTH-1:0] first_data /* synthesis syn_keep = 1 */;
    reg [WIDTH-1:0] second_data /* synthesis syn_keep = 1 */;
    reg [WIDTH-1:0] complex_data /* synthesis syn_keep = 1 */;
    integer k;
    always @*begin
        first_data=0;second_data=0;complex_data=0;
        for(k=0;k<8;k=k+1)begin
            first_data=first_data|({WIDTH{first_integer[k]}}&payload[k*WIDTH+:WIDTH]);
            second_data=second_data|({WIDTH{second_integer[k]}}&payload[k*WIDTH+:WIDTH]);
        end
        for(k=0;k<4;k=k+1)
            complex_data=complex_data|({WIDTH{first_complex[k]}}&payload[(8+k)*WIDTH+:WIDTH]);
    end
    assign value0=reset||ex_hold?{WIDTH{1'b0}}:(choose_complex?complex_data:first_data);
    assign value1=reset||!ENABLE_PAIRING?{WIDTH{1'b0}}:
        (ex_hold||choose_complex?first_data:second_data);
endmodule
