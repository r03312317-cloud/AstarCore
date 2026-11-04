// Original RV32 combinational JALR prediction check.
// A predicted sum bit implies carry-in A^B^P. The preceding bit implies
// carry-out (A&B)|((A|B)&~P). Check all adjacent-bit agreements in parallel.
// JALR clears sum bit 0; its carry into bit 1 is A[0]&B[0]. The top carry
// wraps modulo 2^32. There is no pipeline stage or change to the real target.
module rv32_jalr_target_match(
    input [31:0] base,offset,expected,
    output match_ok
);
    wire [31:1] agreements;
    assign agreements[1]=(base[1]^offset[1]^expected[1])==(base[0]&offset[0]);
    genvar bit_position;
    generate for(bit_position=2;bit_position<32;bit_position=bit_position+1)begin:local_carry_check
        assign agreements[bit_position]=(base[bit_position]^offset[bit_position]^expected[bit_position])==
            ((base[bit_position-1]&offset[bit_position-1])|
             ((base[bit_position-1]|offset[bit_position-1])&!expected[bit_position-1]));
    end endgenerate
    assign match_ok=!expected[0]&&(&agreements);
endmodule
