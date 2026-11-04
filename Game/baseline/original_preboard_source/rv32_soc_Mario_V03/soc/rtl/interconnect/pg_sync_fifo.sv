// Registered-occupancy FIFO; no out_ready -> in_ready combinational path.
module pg_sync_fifo #(
    parameter int WIDTH=32, DEPTH=16
)(
    input logic clk,rst,
    input logic in_valid, output logic in_ready, input logic [WIDTH-1:0] in_data,
    output logic out_valid, input logic out_ready, output logic [WIDTH-1:0] out_data,
    output logic [$clog2(DEPTH+1)-1:0] level
);
    localparam int CW=$clog2(DEPTH+1);
    localparam int PW=(DEPTH<2)?1:$clog2(DEPTH);
    logic [PW-1:0] rp,wp;
    logic [WIDTH-1:0] data[DEPTH];
    logic push,pop;
    assign in_ready=!rst&&(level<CW'(DEPTH));
    assign out_valid=!rst&&(level!=0);
    assign out_data=out_valid?data[rp]:'0;
    assign push=in_valid&&in_ready;
    assign pop=out_valid&&out_ready;
    function automatic logic [PW-1:0] inc(input logic [PW-1:0] p);
        return (p==PW'(DEPTH-1))?'0:p+1'b1;
    endfunction
    initial if(WIDTH<1||DEPTH<1) $fatal(1,"PG_FIFO_PARAMETER_RED");
    always_ff @(posedge clk) begin
        if(rst) begin rp<='0;wp<='0;level<='0;end
        else begin
            case({push,pop})
                2'b10:level<=level+1'b1;
                2'b01:level<=level-1'b1;
                default:begin end
            endcase
            if(push)begin data[wp]<=in_data;wp<=inc(wp);end
            if(pop)rp<=inc(rp);
        end
    end
endmodule
