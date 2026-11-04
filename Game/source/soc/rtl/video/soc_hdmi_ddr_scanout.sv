// [ARCH] 在显示帧边界接纳描述符，从 DDR 读取当前活动图像。
// [ARCH] 当前合法视频窗口为 0x82000000..0x823fffff，软件不可随意迁移地址。
// [ARCH] 640×360 RGB565 放进 720×480p60 载波，NES 内容另外经软件缩放。
// [ARCH] 描述符排队、真正发布和完整帧读出是三个不同观察点。
// [ARCH] DDR 读取经 FIFO 与像素域解耦，缺数/错误需要观察故障标志。
// [ARCH] 确认发布时同时检查计数和活动地址。
// [ARCH] 非零缓冲预填测试避免把黑色故障回退误判成正确画面。
`timescale 1ns/1ps
// Continuous 480p60 scanout of a centred compact 680x340 RGB565 framebuffer.
// A two-bank row cache reads each RGB565 source row and emits it once.
// Loading the next row overlaps emission of the current row; the previous
// implementation serialized two identical DDR fetches into the pixel stream.
// Reader, registered async FIFO and OSD reuse the Vision5MP contracts. Every
// FIFO pixel carries refresh epoch and scan index. Late or stale pixels are
// discarded; video timing never depends on DDR ready.
// [ARCH] 实时像素消费不能等待 CPU。
// [ARCH] DDR 延迟通过预取和显示 FIFO 吸收，缺数时需要保留故障观察。
// [ARCH] 完整 HDMI 帧计数不等于软件生成了同样多张不同图像。
// [ARCH] 报告因此单列确认发布速率与 60 Hz 载波。
module soc_hdmi_ddr_scanout #(
 parameter bit SINGLE_VIEW=1,
 parameter int FIFO_DEPTH=4096, WAIT_LIMIT=1048576,TX_EXTRA_CYCLES=0,
 parameter int W=680,H=340,H_ACTIVE=720,H_FP=16,H_SYNC=62,H_BP=60,
 parameter int V_ACTIVE=480,V_FP=9,V_SYNC=6,V_BP=30,X_START=20,Y_START=70,
 parameter bit HS_NEGATIVE=1,VS_NEGATIVE=1
)(
 input logic ui_clk,ui_rst,pix_clk,pix_rst,
 input logic [63:0] cpu_time_gray,
 input logic [1:0] test_pattern,
 // [ARCH] publish_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 input logic publish_valid,output logic publish_ready,
 input logic [31:0] publish_fb,publish_frame,publish_run,publish_xy1,publish_xy2,
 input logic [31:0] publish_score,publish_class,publish_count,publish_sequence,
 // [ARCH] pending_valid（尚未完成的事务）：标记本槽/载荷是否属于一个有效所有者；数据 RAM 的残留值本身不能代替有效位。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 publish_ready, publication, pub_toggle, ack_meta 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic pending_valid,output logic [31:0] pending_fb,
 // [ARCH] presented_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 presented_fb, presented_frame, presented_run 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic presented_valid,output logic [31:0] presented_fb,presented_frame,presented_run,
 // [ARCH] m_arid：读事务身份，R 通道需要依据它保持主机/事务归属。
 output logic [3:0] m_arid,output logic [31:0] m_araddr,
 // [ARCH] m_arlen：请求的读 beat 数编码，接收方用它核对边界和 RLAST。
 output logic [7:0] m_arlen,output logic [2:0] m_arsize,
 // [ARCH] m_arburst：读突发的地址递增/固定方式，不能仅改变数据宽度而丢失。
 output logic [1:0] m_arburst,output logic m_arvalid,input logic m_arready,
 // [ARCH] m_rid：返回数据的事务 ID，用于检查和路由先前接纳的读请求。
 input logic [3:0] m_rid,input logic [127:0] m_rdata,
 // [ARCH] m_rresp：读 beat 响应状态，错误需累计到对应行/突发。
 input logic [1:0] m_rresp,input logic m_rlast,m_rvalid,output logic m_rready,
 output logic [23:0] video_rgb,output logic video_de,video_hs,video_vs,
 output logic event_tc,event_th,event_te,te_good,
 output logic [63:0] tc_ticks,th_ticks,te_ticks,tc_pixel_ticks,th_pixel_ticks,te_pixel_ticks,
 output logic [31:0] tc_frame,tc_run,th_frame,th_run,te_frame,te_run,
 output logic [31:0] stat_underflow,stat_mismatch,stat_presented,
 output logic [31:0] stat_max_ddr_wait,stat_fifo_high,stat_fifo_low,
 // [ARCH] video_fault：错误事实应记录到所属指令/事务，再在允许的精确边界处理。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 feed_enabled 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic [7:0] video_fault
);
 localparam int HT=H_ACTIVE+H_FP+H_SYNC+H_BP,VT=V_ACTIVE+V_FP+V_SYNC+V_BP;
 localparam int EMIT_PER_ROW=SINGLE_VIEW?W:2*W;
 localparam int OUTPUT_HEIGHT=H;
 localparam int FW=68,LP=$clog2(FIFO_DEPTH)+1,PIPE=1+TX_EXTRA_CYCLES;
 typedef struct packed {
  logic [31:0] fb,frame_id,run_id,xy1,xy2,score,class_id,count,sequence_id;
 } meta_t;
 meta_t publication,active;
 logic pub_toggle,ack_toggle;
 (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) logic pub_meta,pub_sync,ack_meta,ack_sync;
 logic [11:0] x,y;
 wire vblank=x==0&&y==V_ACTIVE;
 wire de_raw=x<H_ACTIVE&&y<V_ACTIVE;
 wire hs_pulse=x>=H_ACTIVE+H_FP&&x<H_ACTIVE+H_FP+H_SYNC;
 wire vs_pulse=y>=V_ACTIVE+V_FP&&y<V_ACTIVE+V_FP+V_SYNC;
 wire hs_raw=HS_NEGATIVE?!hs_pulse:hs_pulse;
 wire vs_raw=VS_NEGATIVE?!vs_pulse:vs_pulse;
 wire image_slot=de_raw&&x>=X_START&&x<X_START+EMIT_PER_ROW&&y>=Y_START&&y<Y_START+OUTPUT_HEIGHT;
 // [ARCH] active_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 rgb_raw, pub_meta, pub_sync, ack_toggle 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic active_valid;
 logic [1:0] mode_active,mode_hold;
 // [ARCH] mode_request：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 mode_hold, mode_wait, mode_ack_meta, mode_ack_sync 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic mode_request,mode_ack,mode_wait;
 (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) logic mode_meta,mode_sync,mode_ack_meta,mode_ack_sync;
 wire [1:0] next_mode=(mode_sync!=mode_ack)?mode_hold:mode_active;
 logic [31:0] epoch,scan_epoch,scan_fb;
 // [ARCH] scan_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 feed_enabled, scan_epoch, scan_fb, scan_toggle 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic scan_valid,scan_toggle,scan_ui_seen,scan_abort;
 (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) logic scan_meta,scan_sync;
 // Pixel-domain packet is held for a whole refresh, far longer than the
 // two-flop control crossing. No unsynchronised pulse is used as a start.
 logic [31:0] reader_epoch,reader_fb,reader_index,row;
 logic side,feed_enabled,reader_start,reader_busy,reader_done,reader_ready;
 // [ARCH] reader_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 video_fault, feed_enabled, reader_start 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic [7:0] reader_error;
 // [ARCH] reader_frame_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 feed_enabled 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic reader_frame_valid,pv,pr,plast;
 logic [15:0] pdata;
 logic [31:0] reader_pixels;
 // [ARCH] row_addr：地址与当前请求/响应归属配对，不能独立于有效条件使用。
 logic [31:0] row_addr;
 (* ram_style="block",syn_ramstyle="block_ram" *) logic [15:0] row_cache[0:2047];
 // [ARCH] row_ready：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 row_read_issue, pr, load_bank, emit_bank 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic [1:0] row_ready;
 logic load_bank,emit_bank,load_complete;
 logic [9:0] load_column;
 logic [11:0] emit_column;
 // [ARCH] issue_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 load_column, emit_column, row_out_index 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic [31:0] issue_index;
 // [ARCH] row_out_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 row_out_fire, fifo_push, row_out_last, row_out_index 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic row_out_valid,row_out_last;
 logic [15:0] row_out_pixel;
 // [ARCH] row_out_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 row_out_valid, row_out_last, issue_index 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic [19:0] row_out_index;
 // [ARCH] row_out_fire：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
 wire row_out_fire=row_out_valid&&fifo_accept&&feed_enabled&&!scan_abort;
 wire row_read_issue=feed_enabled&&!scan_abort&&row_ready[emit_bank]&&
                    (!row_out_valid||fifo_accept)&&!(row_out_valid&&row_out_last);
 wire [9:0] cache_read_column=SINGLE_VIEW?10'(emit_column):10'((emit_column>=W)?emit_column-W:emit_column);
 // [ARCH] cache_read_address：保持当前事务地址，等待/背压期间不能换成下一请求的地址。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 row_out_pixel 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire [10:0] cache_read_address={emit_bank,cache_read_column};
 wire cache_write=pv&&pr&&feed_enabled&&!scan_abort;
 // One synchronous read and one write port. The loader owns a non-ready bank,
 // while the emitter owns a ready bank until its last pixel enters the FIFO.
 // An accepted old-epoch burst is still drained by the original AXI reader.
 always_ff @(posedge ui_clk)begin
  if(cache_write)row_cache[{load_bank,load_column}]<=pdata;
  if(row_read_issue)row_out_pixel<=row_cache[cache_read_address];
 end
 // [ARCH] fifo_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 match_pixel, stale_pixel 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic fifo_valid,fifo_ready,fifo_push,fifo_accept;
 // [ARCH] fifo_data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
 logic [FW-1:0] fifo_data;
 logic [LP-1:0] fifo_level;
 // [ARCH] expect_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 match_pixel 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic [19:0] expect_index;
 logic [31:0] fifo_epoch;
 // [ARCH] fifo_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 match_pixel 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic [19:0] fifo_index;
 logic [15:0] fifo_pixel;
 logic match_pixel,stale_pixel;
 logic [23:0] rgb_raw,bars;
 // [ARCH] osd_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 logic osd_valid,box_active,osd_error;
 logic [PIPE-1:0] hs_pipe,vs_pipe,de_pipe,th_pipe,te_pipe;
 // [ARCH] underflow_count：统计已接受的有效占用/事件；同时增减时要保留净变化。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 mismatch_count, presented_count, frame_bad, th_delivered 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic [31:0] underflow_count,mismatch_count,presented_count;
 logic frame_bad,th_delivered;
 logic [63:0] pixel_ticks,cpu_ticks;
 (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) logic [63:0] cpu_gray_meta,cpu_gray_sync;
 logic [63:0] cpu_binary;
 logic tc_toggle,th_toggle,te_toggle;
 (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) logic [2:0] evt_meta,evt_sync;
 logic [2:0] evt_seen;
 typedef struct packed {
  logic [63:0] cpu,pixel;
  logic [31:0] frame_id,run_id,fb,underflows,mismatches,presented;
 } event_t;
 event_t tc_hold,th_hold,te_hold;
 logic te_good_hold;
 assign publish_ready=!pending_valid;
 assign pending_fb=publication.fb;
 // The publisher must hold its packet stable until this ready/valid transfer.
 // A pending slot remains protected until pixel-domain vblank acknowledgement.
 always_ff @(posedge ui_clk)begin
  if(ui_rst)begin
   publication<='0;pub_toggle<=0;pending_valid<=0;ack_meta<=0;ack_sync<=0;
   mode_hold<=1;mode_request<=0;mode_wait<=0;mode_ack_meta<=0;mode_ack_sync<=0;
  end else begin
   ack_meta<=ack_toggle;ack_sync<=ack_meta;
   mode_ack_meta<=mode_ack;mode_ack_sync<=mode_ack_meta;
   if(mode_wait&&mode_ack_sync==mode_request)mode_wait<=0;
   if(!mode_wait&&test_pattern!=mode_hold)begin
    mode_hold<=test_pattern;mode_request<=~mode_request;mode_wait<=1;
   end
   if(pending_valid&&ack_sync==pub_toggle)pending_valid<=0;
   if(publish_valid&&publish_ready)begin
    publication<='{publish_fb,publish_frame,publish_run,publish_xy1,publish_xy2,
                   publish_score,publish_class,publish_count,publish_sequence};
    pending_valid<=1;pub_toggle<=~pub_toggle;
   end
  end
 end
 assign expect_index=20'((y-Y_START)*EMIT_PER_ROW+(x-X_START));
 assign {fifo_epoch,fifo_index,fifo_pixel}=fifo_data;
 assign match_pixel=fifo_valid&&fifo_epoch==epoch&&fifo_index==expect_index;
 assign stale_pixel=fifo_valid&&(fifo_epoch!=epoch ||
                         (image_slot&&fifo_index<expect_index));
 // Blank consumes only stale data. A current-epoch prefetch stays resident
 // until its exact scan position; a missing slot cannot shift the next row.
 assign fifo_ready=stale_pixel||(image_slot&&match_pixel);
 assign fifo_push=row_out_valid&&feed_enabled&&!scan_abort;
 assign pr=!feed_enabled||scan_abort||!row_ready[load_bank];
 soc_display_async_fifo #(.WIDTH(FW),.DEPTH(FIFO_DEPTH)) display_fifo(
  .wr_clk(ui_clk),.rd_clk(pix_clk),.arst(ui_rst||pix_rst),
  .in_valid(fifo_push),.in_ready(fifo_accept),.in_data({reader_epoch,row_out_index,row_out_pixel}),
  .out_valid(fifo_valid),.out_ready(fifo_ready),.out_data(fifo_data),.wr_level(fifo_level));
 assign row_addr=reader_fb+32'(row*(W*2));
 soc_hdmi_axi_reader #(.VIDEO_BASE(32'h82000000),.VIDEO_BYTES(32'h00400000),
  .MAX_PIXELS(W),.ENABLE_ABORT(1),.WAIT_LIMIT(WAIT_LIMIT)) reader(
  .clk(ui_clk),.rst(ui_rst),.start(reader_start),.abort(scan_abort),
  .frame_base(row_addr),.frame_pixels(32'(W)),.ready(reader_ready),
  .busy(reader_busy),.done_pulse(reader_done),.frame_valid(reader_frame_valid),
  .error_sticky(reader_error),.pixels_emitted(reader_pixels),.max_wait_cycles(stat_max_ddr_wait),
  .pixel_valid(pv),.pixel_ready(pr),.pixel_data(pdata),.pixel_last(plast),
  .m_arid,.m_araddr,.m_arlen,.m_arsize,.m_arburst,.m_arvalid,.m_arready,
  .m_rid,.m_rdata,.m_rresp,.m_rlast,.m_rvalid,.m_rready);
 // New refresh stops the old producer, then drains its already accepted AXI
 // burst before restarting. Never reset a live AXI transaction or forge RLAST.
 always_ff @(posedge ui_clk)begin
  if(ui_rst)begin
   scan_meta<=0;scan_sync<=0;scan_ui_seen<=0;scan_abort<=0;
   reader_epoch<=0;reader_fb<=0;reader_index<=0;row<=0;side<=0;
   row_ready<=0;load_bank<=0;emit_bank<=0;load_complete<=0;
   load_column<=0;emit_column<=0;issue_index<=0;
   row_out_valid<=0;row_out_last<=0;row_out_index<=0;
   feed_enabled<=0;reader_start<=0;stat_fifo_high<=0;stat_fifo_low<=FIFO_DEPTH;
   video_fault<=0;
  end else begin
   scan_meta<=scan_toggle;scan_sync<=scan_meta;reader_start<=0;
   if(fifo_level>stat_fifo_high)stat_fifo_high<=32'(fifo_level);
   if(feed_enabled&&fifo_level<stat_fifo_low)stat_fifo_low<=32'(fifo_level);
   if(reader_error!=0)begin video_fault<=video_fault|reader_error;feed_enabled<=0;end
   if(scan_sync!=scan_ui_seen)begin scan_abort<=1;feed_enabled<=0;end
   if(scan_abort&&reader_ready&&!reader_start)begin
    scan_ui_seen<=scan_sync;scan_abort<=0;
    reader_epoch<=scan_epoch;reader_fb<=scan_fb;row<=0;side<=0;reader_index<=0;
    row_ready<=0;load_bank<=0;emit_bank<=0;load_complete<=0;
    load_column<=0;emit_column<=0;issue_index<=0;
    row_out_valid<=0;row_out_last<=0;row_out_index<=0;
    feed_enabled<=scan_valid&&video_fault==0&&reader_error==0;
   end else if(scan_sync==scan_ui_seen&&!scan_abort&&feed_enabled)begin
    if(cache_write)load_column<=load_column+1'b1;
    if(row_out_fire)begin
     reader_index<=reader_index+1'b1;row_out_valid<=0;
     if(row_out_last)begin
      row_ready[emit_bank]<=0;emit_bank<=~emit_bank;side<=0;
      if(reader_index==EMIT_PER_ROW*OUTPUT_HEIGHT-1)feed_enabled<=0;
     end
    end
    if(row_read_issue)begin
     row_out_valid<=1;row_out_last<=emit_column==EMIT_PER_ROW-1;
     row_out_index<=20'(issue_index);issue_index<=issue_index+1'b1;
     if(emit_column==EMIT_PER_ROW-1)emit_column<=0;
     else emit_column<=emit_column+1'b1;
     side<=emit_column>=W;
    end
    if(reader_done)begin
     if(!reader_frame_valid)feed_enabled<=0;
     else begin
      row_ready[load_bank]<=1;load_bank<=~load_bank;
      if(row==H-1)load_complete<=1;
      else row<=row+1'b1;
     end
    end else if(reader_ready&&!reader_start&&!load_complete&&!row_ready[load_bank])begin
     reader_start<=1;load_column<=0;
    end
   end
   if(reader_error!=0)begin feed_enabled<=0;reader_start<=0;end
  end
 end
 always_comb begin
  cpu_binary[63]=cpu_gray_sync[63];
  for(integer i=62;i>=0;i--)cpu_binary[i]=^(cpu_gray_sync>>i);
  case((32'(x)*8)/H_ACTIVE)
   0:bars=24'hffffff;1:bars=24'hffff00;2:bars=24'h00ffff;3:bars=24'h00ff00;
   4:bars=24'hff00ff;5:bars=24'hff0000;6:bars=24'h0000ff;default:bars=0;
  endcase
  rgb_raw=0;
  if(de_raw)begin
   if(!active_valid||mode_active!=2)rgb_raw=bars;
   else if(image_slot&&match_pixel)
    rgb_raw={fifo_pixel[15:11],fifo_pixel[15:13],fifo_pixel[10:5],fifo_pixel[10:9],
             fifo_pixel[4:0],fifo_pixel[4:2]};
  end
 end
 // Existing right-only OSD latches descriptor and IDs together at vblank.
 soc_stereo_osd #(.X_MIN(SINGLE_VIEW?X_START:W),.X_LIMIT(SINGLE_VIEW?X_START+W:2*W),.Y_MIN(Y_START),.Y_LIMIT(Y_START+OUTPUT_HEIGHT)) osd(.clk(pix_clk),.rst(pix_rst),.vblank,
  .displayed_left_id((pub_sync!=ack_toggle)?publication.frame_id:active.frame_id),
  .displayed_right_id((pub_sync!=ack_toggle)?publication.frame_id:active.frame_id),
  .cfg_valid(pub_sync!=ack_toggle),.cfg_enable(publication.count!=0),
  .cfg_left_id(publication.frame_id),.cfg_right_id(publication.frame_id),
  .cfg_x1(11'(publication.xy1[15:0]+(SINGLE_VIEW?X_START:W))),.cfg_x2(11'(publication.xy2[15:0]+(SINGLE_VIEW?X_START:W))),
  .cfg_y1(10'(publication.xy1[31:16]+Y_START)),.cfg_y2(10'(publication.xy2[31:16]+Y_START)),
  .pixel_valid(de_raw),.pixel_x(11'(x)),.pixel_y(10'(y)),.pixel_rgb(rgb_raw),
  .pixel_out_valid(osd_valid),.pixel_out_rgb(video_rgb),.box_active,.cfg_error(osd_error));
 assign video_de=de_pipe[0];assign video_hs=hs_pipe[0];assign video_vs=vs_pipe[0];
 // OSD contributes one output register. Event pipeline includes that register
 // plus the separately audited external TX latency; RGB is not double delayed.
 always_ff @(posedge pix_clk)begin
  if(pix_rst)begin
   x<=0;y<=0;pixel_ticks<=0;cpu_gray_meta<=0;cpu_gray_sync<=0;cpu_ticks<=0;
   pub_meta<=0;pub_sync<=0;ack_toggle<=0;active<='0;active_valid<=0;
   mode_meta<=0;mode_sync<=0;mode_ack<=0;mode_active<=1;te_good_hold<=0;
   scan_epoch<=0;scan_fb<=0;scan_valid<=0;scan_toggle<=0;epoch<=0;
   hs_pipe<=0;vs_pipe<=0;de_pipe<=0;th_pipe<=0;te_pipe<=0;
   underflow_count<=0;mismatch_count<=0;presented_count<=0;frame_bad<=0;th_delivered<=0;
   tc_toggle<=0;th_toggle<=0;te_toggle<=0;tc_hold<='0;th_hold<='0;te_hold<='0;
  end else begin
   pixel_ticks<=pixel_ticks+1'b1;cpu_gray_meta<=cpu_time_gray;cpu_gray_sync<=cpu_gray_meta;
   cpu_ticks<=cpu_binary;pub_meta<=pub_toggle;pub_sync<=pub_meta;
   mode_meta<=mode_request;mode_sync<=mode_meta;
   if(x==HT-1)begin x<=0;if(y==VT-1)y<=0;else y<=y+1'b1;end else x<=x+1'b1;
   hs_pipe<=(hs_pipe<<1)|PIPE'(hs_raw);vs_pipe<=(vs_pipe<<1)|PIPE'(vs_raw);
   de_pipe<=(de_pipe<<1)|PIPE'(de_raw);
   th_pipe<=(th_pipe<<1)|PIPE'(active_valid&&mode_active==2&&image_slot&&x==X_START&&y==Y_START&&!th_delivered);
   te_pipe<=(te_pipe<<1)|PIPE'(active_valid&&mode_active==2&&image_slot&&x==X_START+EMIT_PER_ROW-1&&y==Y_START+OUTPUT_HEIGHT-1);
   if(vblank)begin
    epoch<=epoch+1'b1;scan_epoch<=epoch+1'b1;scan_toggle<=~scan_toggle;
    scan_fb<=(pub_sync!=ack_toggle)?publication.fb:active.fb;
    scan_valid<=(active_valid||pub_sync!=ack_toggle)&&next_mode==2;frame_bad<=0;
    mode_active<=next_mode;mode_ack<=mode_sync;
    if(pub_sync!=ack_toggle)begin
     active<=publication;active_valid<=1;ack_toggle<=pub_sync;th_delivered<=0;
     tc_toggle<=~tc_toggle;
     tc_hold<='{cpu_ticks,pixel_ticks,publication.frame_id,publication.run_id,publication.fb,
                underflow_count,mismatch_count,presented_count};
    end
   end
   if(active_valid&&mode_active==2&&image_slot&&!match_pixel)begin
    underflow_count<=underflow_count+1'b1;frame_bad<=1;
   end
   if(stale_pixel)begin mismatch_count<=mismatch_count+1'b1;end
   if(th_pipe[PIPE-1])begin
    th_delivered<=1;th_toggle<=~th_toggle;
    th_hold<='{cpu_ticks,pixel_ticks,active.frame_id,active.run_id,active.fb,
               underflow_count,mismatch_count,presented_count};
   end
   if(te_pipe[PIPE-1])begin
    if(!frame_bad)presented_count<=presented_count+1'b1;
    te_good_hold<=!frame_bad;te_toggle<=~te_toggle;
    te_hold<='{cpu_ticks,pixel_ticks,active.frame_id,active.run_id,active.fb,
               underflow_count,mismatch_count,presented_count+32'(!frame_bad)};
   end
  end
 end
 // Event records are held until the next event of that kind (> a frame for
 // TH/TE, TC needs vblank); two-flop toggles safely snapshot their payload.
 always_ff @(posedge ui_clk)begin
  if(ui_rst)begin
   evt_meta<=0;evt_sync<=0;evt_seen<=0;event_tc<=0;event_th<=0;event_te<=0;te_good<=0;
   tc_ticks<=0;th_ticks<=0;te_ticks<=0;tc_pixel_ticks<=0;th_pixel_ticks<=0;te_pixel_ticks<=0;
   tc_frame<=0;tc_run<=0;th_frame<=0;th_run<=0;te_frame<=0;te_run<=0;
   presented_valid<=0;presented_fb<=0;presented_frame<=0;presented_run<=0;
   stat_underflow<=0;stat_mismatch<=0;stat_presented<=0;
  end else begin
   evt_meta<={te_toggle,th_toggle,tc_toggle};evt_sync<=evt_meta;evt_seen<=evt_sync;
   event_tc<=evt_sync[0]!=evt_seen[0];event_th<=evt_sync[1]!=evt_seen[1];event_te<=evt_sync[2]!=evt_seen[2];
   if(evt_sync[0]!=evt_seen[0])begin
    tc_ticks<=tc_hold.cpu;tc_pixel_ticks<=tc_hold.pixel;tc_frame<=tc_hold.frame_id;tc_run<=tc_hold.run_id;
    presented_valid<=1;presented_fb<=tc_hold.fb;presented_frame<=tc_hold.frame_id;presented_run<=tc_hold.run_id;
    stat_underflow<=tc_hold.underflows;stat_mismatch<=tc_hold.mismatches;stat_presented<=tc_hold.presented;
   end
   if(evt_sync[1]!=evt_seen[1])begin
    th_ticks<=th_hold.cpu;th_pixel_ticks<=th_hold.pixel;th_frame<=th_hold.frame_id;th_run<=th_hold.run_id;
   end
   if(evt_sync[2]!=evt_seen[2])begin
    te_good<=te_good_hold;
    te_ticks<=te_hold.cpu;te_pixel_ticks<=te_hold.pixel;te_frame<=te_hold.frame_id;te_run<=te_hold.run_id;
    stat_underflow<=te_hold.underflows;stat_mismatch<=te_hold.mismatches;stat_presented<=te_hold.presented;
   end
  end
 end
 initial begin
  // Geometry sanity only: the 480p60 carrier is fixed by the board constraints,
  // the framebuffer size is a per-project choice (640x360 here, 680x340 in the
  // camera project this module came from).
  if(!SINGLE_VIEW||W<1||H<1||X_START<0||Y_START<0||
     X_START+W>H_ACTIVE||Y_START+H>V_ACTIVE||HT>4096||VT>4096||TX_EXTRA_CYCLES<0)
   $fatal(1,"DISPLAY_SCANOUT_GEOMETRY");
 end
endmodule
