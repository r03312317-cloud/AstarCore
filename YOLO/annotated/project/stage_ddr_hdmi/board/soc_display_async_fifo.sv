// Derived from production pg_async_fifo_dc: same Gray pointer, synchronous
// registered read and coordinated reset contract. RAM is a dual-clock block
// memory; Gray write-domain level is exposed for local watermarks only.
// 架构导读：soc_display_async_fifo。
// 跨显示相关时钟域缓存像素和有效信息。
module soc_display_async_fifo #(parameter int WIDTH=44,DEPTH=4096)(
 // 接口声明：input logic wr_clk,rd_clk,arst。
 input logic wr_clk,rd_clk,arst,
 input logic in_valid,output logic in_ready,input logic[WIDTH-1:0] in_data,
 output logic out_valid,input logic out_ready,output logic[WIDTH-1:0] out_data,
 output logic[$clog2(DEPTH):0] wr_level
);
 timeunit 1ns;timeprecision 1ps;
 // 静态配置：localparam int AW=$clog2(DEPTH),PW=AW+1。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam int AW=$clog2(DEPTH),PW=AW+1;
 logic wr_rst,rd_rst;
 pg_reset_sync wr_release(.clk(wr_clk),.arst,.rst(wr_rst));
 pg_reset_sync rd_release(.clk(rd_clk),.arst,.rst(rd_rst));
 logic[PW-1:0] wb,rb,wg,rg,wn,rn,wgn,rgn,rb_sync;
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic[PW-1:0] rmeta,rsync,wmeta,wsync;
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic rumeta,rusync,wumeta,wusync;
 logic full,empty,push,load,valid;
 logic[WIDTH-1:0] data;
 (* ram_style="block" *) logic[WIDTH-1:0] mem[0:DEPTH-1];
 assign in_ready=!wr_rst&&rusync&&!full;
 assign out_valid=!rd_rst&&wusync&&valid;assign out_data=data;
 assign push=in_valid&&in_ready;
 assign load=!rd_rst&&wusync&&!empty&&(!valid||out_ready);
 assign wn=wb+PW'(push);assign rn=rb+PW'(load);
 assign wgn=(wn>>1)^wn;assign rgn=(rn>>1)^rn;
 // 过程边界：always_comb begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_comb begin
  rb_sync[PW-1]=rsync[PW-1];
  for(integer i=PW-2;i>=0;i--)rb_sync[i]=rb_sync[i+1]^rsync[i];
 end
 assign wr_level=wb-rb_sync;
 // 过程边界：always_ff @(posedge wr_clk or posedge wr_rst)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge wr_clk or posedge wr_rst)begin
  // 复位相关判断：wr_rst；分支方向由信号极性与取反表达式决定。
  if(wr_rst)begin wb<=0;wg<=0;full<=0;rmeta<=0;rsync<=0;rumeta<=0;rusync<=0;end
  else begin
   rmeta<=rg;rsync<=rmeta;rumeta<=!rd_rst;rusync<=rumeta;
   wb<=wn;wg<=wgn;full<=wgn==(rsync^(PW'(3)<<(PW-2)));
  end
 end
 // 过程边界：always_ff @(posedge rd_clk or posedge rd_rst)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge rd_clk or posedge rd_rst)begin
  // 复位相关判断：rd_rst；分支方向由信号极性与取反表达式决定。
  if(rd_rst)begin rb<=0;rg<=0;empty<=1;valid<=0;wmeta<=0;wsync<=0;wumeta<=0;wusync<=0;end
  else begin
   wmeta<=wg;wsync<=wmeta;wumeta<=!wr_rst;wusync<=wumeta;
   rb<=rn;rg<=rgn;empty<=rgn==wsync;
   if(load)valid<=1;else if(out_valid&&out_ready)valid<=0;
  end
 end
 // 过程边界：always_ff @(posedge wr_clk)if(push)mem[wb[AW-1:0]]<=in_data;。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge wr_clk)if(push)mem[wb[AW-1:0]]<=in_data;
 // 过程边界：always_ff @(posedge rd_clk)if(load)data<=mem[rb[AW-1:0]];。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge rd_clk)if(load)data<=mem[rb[AW-1:0]];
 initial if(DEPTH<2||(DEPTH&(DEPTH-1))!=0)$fatal(1,"DISPLAY_FIFO_PARAMETER");
endmodule
