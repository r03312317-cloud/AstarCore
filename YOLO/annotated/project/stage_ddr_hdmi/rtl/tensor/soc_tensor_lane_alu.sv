// Shared fixed16byte datapath. Exact signedINT8 max and saturating addition.
// 架构导读：soc_tensor_lane_alu。
// 可综合数据/控制组件；接口含义和更新条件以下面的局部注释及原始表达式为准。
module soc_tensor_lane_alu(
 // 接口声明：input logic add_mode。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic add_mode,
 input logic [127:0] a,b,
 output logic [127:0] result
);
 // 局部运算/辅助过程：function automatic logic [7:0] calculate(input logic do_add,。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
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
