// Combinational 2x bitmap label. The caller supplies the same vblank-latched
// metadata as its box. This adds no pixel latency and performs no DDR access.
// 架构导读：soc_gesture_label。
// 将手势类别和置信度字段转为屏幕标签所用的像素/字符信息。
module soc_gesture_label #(
 // 静态配置：parameter int X_MIN=20,X_LIMIT=700,Y_MIN=70,Y_LIMIT=410。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter int X_MIN=20,X_LIMIT=700,Y_MIN=70,Y_LIMIT=410
)(
 // 接口声明：input logic enable。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic enable,
 // 接口声明：input logic [31:0] class_id,score_q15。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [31:0] class_id,score_q15,
 // 接口声明：input logic [10:0] box_x1,pixel_x。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [10:0] box_x1,pixel_x,
 // 接口声明：input logic [9:0] box_y1,pixel_y。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [9:0] box_y1,pixel_y,
 // 接口声明：input logic [23:0] pixel_rgb。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [23:0] pixel_rgb,
 // 接口声明：output logic [23:0] label_rgb。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [23:0] label_rgb,
 // 接口声明：output logic label_active。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic label_active
);
 // 局部运算/辅助过程：function automatic logic [34:0] glyph(input logic [7:0] ch);。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
 function automatic logic [34:0] glyph(input logic [7:0] ch);
  // 按 ch 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
  case(ch)
    8'd65:glyph=35'b01110_10001_10001_11111_10001_10001_10001;
    8'd67:glyph=35'b01111_10000_10000_10000_10000_10000_01111;
    8'd69:glyph=35'b11111_10000_10000_11110_10000_10000_11111;
    8'd70:glyph=35'b11111_10000_10000_11110_10000_10000_10000;
    8'd72:glyph=35'b10001_10001_10001_11111_10001_10001_10001;
    8'd73:glyph=35'b11111_00100_00100_00100_00100_00100_11111;
    8'd76:glyph=35'b10000_10000_10000_10000_10000_10000_11111;
    8'd77:glyph=35'b10001_11011_10101_10101_10001_10001_10001;
    8'd78:glyph=35'b10001_11001_10101_10011_10001_10001_10001;
    8'd79:glyph=35'b01110_10001_10001_10001_10001_10001_01110;
    8'd80:glyph=35'b11110_10001_10001_11110_10000_10000_10000;
    8'd82:glyph=35'b11110_10001_10001_11110_10100_10010_10001;
    8'd83:glyph=35'b01111_10000_10000_01110_00001_00001_11110;
    8'd84:glyph=35'b11111_00100_00100_00100_00100_00100_00100;
    8'd85:glyph=35'b10001_10001_10001_10001_10001_10001_01110;
    8'd48:glyph=35'b01110_10001_10011_10101_11001_10001_01110;
    8'd49:glyph=35'b00100_01100_00100_00100_00100_00100_01110;
    8'd50:glyph=35'b01110_10001_00001_00010_00100_01000_11111;
    8'd51:glyph=35'b11110_00001_00001_01110_00001_00001_11110;
    8'd52:glyph=35'b00010_00110_01010_10010_11111_00010_00010;
    8'd53:glyph=35'b11111_10000_10000_11110_00001_00001_11110;
    8'd54:glyph=35'b01110_10000_10000_11110_10001_10001_01110;
    8'd55:glyph=35'b11111_00001_00010_00100_01000_01000_01000;
    8'd56:glyph=35'b01110_10001_10001_01110_10001_10001_01110;
    8'd57:glyph=35'b01110_10001_10001_01111_00001_00001_01110;
    8'd37:glyph=35'b11001_11010_00010_00100_01000_01011_10011;
    default:glyph=0;
  endcase
 endfunction
 // 局部运算/辅助过程：function automatic logic [39:0] class_text(input logic [2:0] id);。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
 function automatic logic [39:0] class_text(input logic [2:0] id);
  // 按 id 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
  case(id)
   0:class_text="FIST ";1:class_text="ONE  ";2:class_text="PEACE";
   3:class_text="THREE";4:class_text="FOUR ";5:class_text="PALM ";
   default:class_text="     ";
  endcase
 endfunction
 logic [39:0] name;
 logic [34:0] bits;
 logic [7:0] character;
 logic [21:0] scaled_score;
 logic [3:0] decimal_tens,decimal_ones;
 logic [7:0] local_x;
 integer name_len,percent,digits,text_len,panel_width;
 integer left,top,dx,dy,index,number_index,gx,gy;
 // 过程边界：always_comb begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_comb begin
  label_rgb=pixel_rgb;label_active=0;
  name=class_text(class_id[2:0]);
  name_len=(class_id==1)?3:((class_id==2||class_id==3)?5:4);
  scaled_score=22'(score_q15[15:0])*22'd100+22'd16384;
  percent=int'(scaled_score>>15);if(percent>100)percent=100;
  // PDS25 does not map signed DIV/REM. Decimal digits use parallel
  // constant comparisons; the 100-percent case has two trailing zeros.
  decimal_tens=0;decimal_ones=0;
  // 条件分支：检查 percent<100。
  if(percent<100)begin
   for(integer digit=1;digit<10;digit= digit+1)
    // 条件分支：检查 percent>=digit*10。
    if(percent>=digit*10)decimal_tens=4'(digit);
   decimal_ones=4'(percent-int'(decimal_tens)*10);
  end
  digits=(percent>=100)?3:((percent>=10)?2:1);
  text_len=name_len+1+digits+1;panel_width=4+text_len*12;
  left=int'(box_x1);if(left<X_MIN)left=X_MIN;
  // 条件分支：检查 left+panel_width>X_LIMIT。
  if(left+panel_width>X_LIMIT)left=X_LIMIT-panel_width;
  top=(int'(box_y1)>=Y_MIN+18)?int'(box_y1)-18:int'(box_y1)+2;
  // 条件分支：检查 top<Y_MIN。
  if(top<Y_MIN)top=Y_MIN;if(top+18>Y_LIMIT)top=Y_LIMIT-18;
  dx=int'(pixel_x)-left;dy=int'(pixel_y)-top;
  index=0;number_index=0;gx=0;gy=0;local_x=0;character=8'd32;bits=0;
  // 条件分支：检查 enable&&class_id<6&&score_q15<=32768&&X_LIMIT-X_MIN>=panel_width&&。
  if(enable&&class_id<6&&score_q15<=32768&&X_LIMIT-X_MIN>=panel_width&&
     pixel_x>=X_MIN&&pixel_x<X_LIMIT&&pixel_y>=Y_MIN&&pixel_y<Y_LIMIT&&
     dx>=0&&dx<panel_width&&dy>=0&&dy<18)begin
   label_active=1;label_rgb=24'h101010;
   // 条件分支：检查 dx>=2&&dx<panel_width-2&&dy>=2&&dy<16。
   if(dx>=2&&dx<panel_width-2&&dy>=2&&dy<16)begin
    local_x=8'(dx-2);
    for(integer cell_index=1;cell_index<10;cell_index=cell_index+1)
     // 条件分支：检查 local_x>=8'(cell_index*12)。
     if(local_x>=8'(cell_index*12))index=cell_index;
    gx=(int'(local_x)-index*12)>>1;gy=(dy-2)>>1;
    // 条件分支：检查 index<name_len。
    if(index<name_len)character=name[39-index*8-:8];
    // 条件分支：检查 index>name_len&&index<name_len+1+digits。
    else if(index>name_len&&index<name_len+1+digits)begin
     number_index=index-name_len-1;
     // 条件分支：检查 digits==3&&number_index==0。
     if(digits==3&&number_index==0)character=8'd49;
     // 条件分支：检查 number_index==digits-1。
     else if(number_index==digits-1)character=8'(48+decimal_ones);
     else character=8'(48+decimal_tens);
    // 条件分支：检查 index==text_len-1。
    end else if(index==text_len-1)character=8'd37;
    bits=glyph(character);
    if(gx<5&&gy<7&&bits[34-gy*5-gx])label_rgb=24'hffffff;
   end
  end
 end
endmodule
