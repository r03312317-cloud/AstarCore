// SPDX-License-Identifier: MIT
// Pixel vblank -> CPU commit -> stable framebuffer snapshot -> pixel domain.
// Only one transaction is sent per frame; an unfinished transaction is an
// error, not silently converted into an asynchronous multibit sample.
// 显示提交通过 toggle 请求与确认在时钟域之间传递稳定的地址和使能快照。
// 源端在等待确认期间保持 payload 稳定，避免对多位地址逐位同步造成撕裂快照。
// 目标端确认消费后才允许源端开始下一次提交，busy 是所有权转移的一部分。
// 复位使两端握手状态重新一致，不能只清除 payload 而保留旧 toggle。
module soc_fb_commit_cdc(
    // cpu_reset 综合系统复位 DDR 就绪 启动许可及致命故障后的 CPU 复位条件。
    input wire cpu_clk,cpu_reset,pixel_clk,pixel_reset,
    input wire pixel_vblank,output wire cpu_vblank,
    // cpu_active_enable 保存功能或输出使能，控制资格而非实际吞吐测量值。
    input wire [31:0] cpu_active_base,input wire cpu_active_enable,
    // pixel_active_enable 保存功能或输出使能，控制资格而非实际吞吐测量值。
    output reg [31:0] pixel_active_base,output reg pixel_active_enable,
    output reg pixel_commit,output reg missed_vblank
);
    reg request_toggle,ack_toggle;
    (* PAP_ASYNC_REG=1,syn_preserve=1 *) reg req_meta,req_sync;
    (* PAP_ASYNC_REG=1,syn_preserve=1 *) reg ack_meta,ack_sync;
    reg cpu_seen,cpu_pulse,need_snapshot;
    reg [31:0] snapshot_base;reg snapshot_enable;
    reg pixel_wait;
    // cpu_vblank 连接到 cpu_pulse，两者在此路径上保持字段对应。
    assign cpu_vblank=cpu_pulse;
    always @(posedge cpu_clk)begin
      // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
      if(cpu_reset)begin
        req_meta<=0;req_sync<=0;cpu_seen<=0;cpu_pulse<=0;need_snapshot<=0;
        snapshot_base<=32'h83f00000;snapshot_enable<=0;ack_toggle<=0;
      end else begin
        // 本时钟边界的 req_meta 捕获 request_toggle，两者在此路径上保持字段对应。
        req_meta<=request_toggle;req_sync<=req_meta;cpu_pulse<=0;
        if(req_sync!=cpu_seen)begin cpu_seen<=req_sync;cpu_pulse<=1;end
        if(cpu_pulse)need_snapshot<=1;
        if(need_snapshot)begin
          // 本时钟边界的 snapshot_base 捕获 cpu_active_base，两者在此路径上保持字段对应。
          snapshot_base<=cpu_active_base;snapshot_enable<=cpu_active_enable;
          // 本时钟边界的 ack_toggle 捕获 cpu_seen，两者在此路径上保持字段对应。
          ack_toggle<=cpu_seen;need_snapshot<=0;
        end
      end
    end
    always @(posedge pixel_clk)begin
      if(pixel_reset)begin
        request_toggle<=0;ack_meta<=0;ack_sync<=0;pixel_wait<=0;
        pixel_active_base<=32'h83f00000;pixel_active_enable<=0;
        pixel_commit<=0;missed_vblank<=0;
      end else begin
        // 本时钟边界的 ack_meta 捕获 ack_toggle，两者在此路径上保持字段对应。
        ack_meta<=ack_toggle;ack_sync<=ack_meta;pixel_commit<=0;
        if(pixel_vblank)begin
          if(pixel_wait)missed_vblank<=1;
          else begin request_toggle<=~request_toggle;pixel_wait<=1;end
        end
        if(pixel_wait&&ack_sync==request_toggle)begin
          // 本时钟边界的 pixel_active_base 捕获 snapshot_base，两者在此路径上保持字段对应。
          pixel_active_base<=snapshot_base;pixel_active_enable<=snapshot_enable;
          pixel_commit<=1;pixel_wait<=0;
        end
      end
    end
endmodule
