// [ARCH] 像素队列隔离 DDR 读时钟与视频像素时钟。
// [ARCH] 像素输出服从视频时序，不能因为上游背压随意暂停载波。
// [ARCH] 队列缺数属于实时输出故障，不是普通软件缓存未命中。
// [ARCH] 队列容量和预取策略共同吸收跨域延迟。
// Derived from production pg_async_fifo_dc: same Gray pointer, synchronous
// registered read and coordinated reset contract. RAM is a dual-clock block
// memory; Gray write-domain level is exposed for local watermarks only.
module soc_display_async_fifo #(parameter int WIDTH=44,DEPTH=4096)(
 // [ARCH] wr_clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 mem 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic wr_clk,rd_clk,arst,
 // [ARCH] in_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 push 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic in_valid,output logic in_ready,input logic[WIDTH-1:0] in_data,
 // [ARCH] out_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 out_data, valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic out_valid,input logic out_ready,output logic[WIDTH-1:0] out_data,
 output logic[$clog2(DEPTH):0] wr_level
);
 timeunit 1ns;timeprecision 1ps;
 localparam int AW=$clog2(DEPTH),PW=AW+1;
 // [ARCH] wr_rst：参与本域复位/就绪控制，释放条件与跨域同步链一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 in_ready, wb, wg, full 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic wr_rst,rd_rst;
 pg_reset_sync wr_release(.clk(wr_clk),.arst,.rst(wr_rst));
 pg_reset_sync rd_release(.clk(rd_clk),.arst,.rst(rd_rst));
 logic[PW-1:0] wb,rb,wg,rg,wn,rn,wgn,rgn,rb_sync;
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic[PW-1:0] rmeta,rsync,wmeta,wsync;
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic rumeta,rusync,wumeta,wusync;
 logic full,empty,push,load,valid;
 // [ARCH] data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 out_valid, out_data 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic[WIDTH-1:0] data;
 (* ram_style="block" *) logic[WIDTH-1:0] mem[0:DEPTH-1];
 assign in_ready=!wr_rst&&rusync&&!full;
 assign out_valid=!rd_rst&&wusync&&valid;assign out_data=data;
 assign push=in_valid&&in_ready;
 assign load=!rd_rst&&wusync&&!empty&&(!valid||out_ready);
 assign wn=wb+PW'(push);assign rn=rb+PW'(load);
 assign wgn=(wn>>1)^wn;assign rgn=(rn>>1)^rn;
 always_comb begin
  rb_sync[PW-1]=rsync[PW-1];
  for(integer i=PW-2;i>=0;i--)rb_sync[i]=rb_sync[i+1]^rsync[i];
 end
 assign wr_level=wb-rb_sync;
 always_ff @(posedge wr_clk or posedge wr_rst)begin
  if(wr_rst)begin wb<=0;wg<=0;full<=0;rmeta<=0;rsync<=0;rumeta<=0;rusync<=0;end
  else begin
   rmeta<=rg;rsync<=rmeta;rumeta<=!rd_rst;rusync<=rumeta;
   wb<=wn;wg<=wgn;full<=wgn==(rsync^(PW'(3)<<(PW-2)));
  end
 end
 always_ff @(posedge rd_clk or posedge rd_rst)begin
  if(rd_rst)begin rb<=0;rg<=0;empty<=1;valid<=0;wmeta<=0;wsync<=0;wumeta<=0;wusync<=0;end
  else begin
   wmeta<=wg;wsync<=wmeta;wumeta<=!wr_rst;wusync<=wumeta;
   rb<=rn;rg<=rgn;empty<=rgn==wsync;
   if(load)valid<=1;else if(out_valid&&out_ready)valid<=0;
  end
 end
 always_ff @(posedge wr_clk)if(push)mem[wb[AW-1:0]]<=in_data;
 always_ff @(posedge rd_clk)if(load)data<=mem[rb[AW-1:0]];
 initial if(DEPTH<2||(DEPTH&(DEPTH-1))!=0)$fatal(1,"DISPLAY_FIFO_PARAMETER");
endmodule
