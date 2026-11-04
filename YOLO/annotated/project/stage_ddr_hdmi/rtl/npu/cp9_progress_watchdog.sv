// Exact consecutive-no-progress counter with a one-bit lazy-clear tag.
// Current progress goes to zero_q, not to reset/enable on all counter bits.
// 架构导读：cp9_progress_watchdog。
// 记录任务进展并检测被启用的硬件进展超时条件。
module cp9_progress_watchdog #(parameter integer LIMIT=4096,
 // 静态配置：parameter integer W=(LIMIT>1)?$clog2(64'(LIMIT)+64'd1):1)(。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer W=(LIMIT>1)?$clog2(64'(LIMIT)+64'd1):1)(
 input logic clk,rst,job_accept,active,pending,progress,
 output logic[W-1:0] effective_count,output logic expired
);
 timeunit 1ns;timeprecision 1ps;
 if(LIMIT==0)begin:g_disabled
  assign effective_count='0;
  assign expired=1'b0;
 end else begin:g_enabled
  // 静态配置：localparam logic[W-1:0] L=W'(LIMIT)。
  localparam logic[W-1:0] L=W'(LIMIT);
  logic zero_q;logic[W-1:0] count_q;
  assign effective_count=zero_q?'0:count_q;
  if(LIMIT==1)begin:g_one
   assign expired=pending&&!progress&&(zero_q||(count_q=='0));
  end else begin:g_more
   assign expired=pending&&!progress&&!zero_q&&(count_q==(L-1'b1));
  end
  // zero_q is the original reset/job-accept/progress visibility tag.
  // count_q is private payload: while zero_q=1 its old value is invisible.
  // The next active edge writes1 before zero_q may expose the counter.
  always_ff @(posedge clk)begin
   // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
   if(rst)zero_q<=1'b1;
   else if(job_accept)zero_q<=1'b1;
   else if(active)zero_q<=progress||!pending;
  end
  // 过程边界：always_ff @(posedge clk)begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk)begin
   if(active)begin
    if(zero_q)count_q<=W'(1);
    else if(count_q<L)count_q<=count_q+1'b1;
   end
  end
 end
endmodule
