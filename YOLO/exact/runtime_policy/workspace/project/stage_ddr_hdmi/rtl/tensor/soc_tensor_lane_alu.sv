// Shared fixed16byte datapath. Exact signedINT8 max and saturating addition.
module soc_tensor_lane_alu(
 input logic add_mode,
 input logic [127:0] a,b,
 output logic [127:0] result
);
 function automatic logic [7:0] calculate(input logic do_add,
   input logic signed [7:0] av,bv);
  logic signed [8:0] sum;
  sum=$signed({av[7],av})+$signed({bv[7],bv});
  if(!do_add)return av>bv ? av : bv;
  if(sum>9'sd127)return 8'h7f;
  if(sum< -9'sd128)return 8'h80;
  return sum[7:0];
 endfunction
 for(genvar lane=0;lane<16;lane++)begin:g_lane
  assign result[lane*8+:8]=calculate(add_mode,$signed(a[lane*8+:8]),$signed(b[lane*8+:8]));
 end
endmodule
