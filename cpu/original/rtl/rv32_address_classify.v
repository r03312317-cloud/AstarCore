// Exact S6 effective-address region classification, independent of full32-bit sum.
module rv32_address_classify(input [31:0] base,input [11:0] offset,output peripheral);
    wire [5:0] high=base[31:26];
    wire [12:0] low_sum={1'b0,base[11:0]}+{1'b0,offset};
    wire positive_cross=!offset[11]&&(&base[25:12])&&low_sum[12];
    wire negative_cross=offset[11]&&!(|base[25:12])&&!low_sum[12];
    // Original two contiguous ranges are exactly high6 in[12,32]. A signed
    //12-bit offset can cross at most one64-MiB boundary. Only four boundary
    // high values can change region membership; all comparisons are parallel.
    wire base_inside=high>=6'd12&&high<=6'd32;
    wire change=(positive_cross&&(high==6'd11||high==6'd32))||
                (negative_cross&&(high==6'd12||high==6'd33));
    assign peripheral=base_inside^change;
endmodule
