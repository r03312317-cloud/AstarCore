"""Create a CPU/Linux fixture using the unchanged compact board scanout RTL."""
from pathlib import Path
import re

r=Path(__file__).resolve().parent
out=r/'sim/compact_boot'
out.mkdir()
top=(r/'rtl/rv32_linux_video_top.v').read_text()
top=top.replace('module rv32_linux_video_top','module rv32_linux_compact_sim_top')
top=top.replace('parameter TIMER_DIV=100,UART_DIV=868','parameter TIMER_DIV=27,UART_DIV=234')
top=top.replace('input [31:0] display_rsp_data','input [127:0] display_rsp_data')
start=top.index(' rv32_framebuffer_scanout scanout(')
top=top[:start]+''' wire pixel_vblank,pixel_commit,pixel_enable,missed_vblank;
 wire [31:0] pixel_base;
 soc_fb_commit_cdc commit_cdc(.cpu_clk(clk),.cpu_reset(reset),
  .pixel_clk(clk),.pixel_reset(reset),.pixel_vblank(pixel_vblank),
  .cpu_vblank(vblank),.cpu_active_base(framebuffer_base),.cpu_active_enable(framebuffer_enable),
  .pixel_active_base(pixel_base),.pixel_active_enable(pixel_enable),
  .pixel_commit(pixel_commit),.missed_vblank(missed_vblank));
 rv32_framebuffer_scanout_128 #(.SRC_WIDTH(320),.SRC_HEIGHT(180),
  .SRC_STRIDE_BYTES(1280),.X_SCALE_SHIFT(1),.Y_SCALE_SHIFT(1)) scanout(
  .clk(clk),.reset(reset),.active_base(pixel_base),.active_enable(pixel_enable),.frame_latch(pixel_commit),
  .vblank(pixel_vblank),.de(video_de),.hsync(video_hsync),.vsync(video_vsync),.pixel_rgb565(video_rgb565),.pixel_x(video_x),.pixel_y(video_y),
  .mem_req_valid(display_req_valid),.mem_req_ready(display_req_ready),.mem_req_addr(display_req_addr),
  .mem_rsp_valid(display_rsp_valid),.mem_rsp_ready(display_rsp_ready),.mem_rsp_data(display_rsp_data),.mem_rsp_error(display_rsp_error),
  .frame_count(video_frame_count),.underflow_rows(video_underflow_rows),.dma_errors(video_dma_errors),.bounds_errors(video_bounds_errors));
endmodule
'''
(out/'compact_top.sv').write_text(top,encoding='utf-8')
header=(r/'sim/uart_terminal.h').read_text().replace('bit_ticks=868, gap_ticks=8680','bit_ticks=234, gap_ticks=2340').replace('max_stages=128','max_stages=2048')
(out/'uart_terminal_compact.h').write_text(header,encoding='utf-8')
src=(r/'sim/linux_video_boot_main.cpp').read_text().replace('"uart_terminal.h"','"uart_terminal_compact.h"').replace('"video_checkpoint.h"','"../video_checkpoint.h"').replace('Vrv32_linux_video_top','Vrv32_linux_compact_sim_top')
src=re.sub(r'\b(1280|720)\b',lambda m:{'1280':'720','720':'480'}[m.group()],src)
src=src.replace('txcount=868+434','txcount=234+117').replace('txcount=868','txcount=234')
src=src.replace('d.display_rsp_data=uint32_t(rd64(da));','uint64_t dl=rd64(da),dh=rd64(da+8);d.display_rsp_data[0]=uint32_t(dl);d.display_rsp_data[1]=uint32_t(dl>>32);d.display_rsp_data[2]=uint32_t(dh);d.display_rsp_data[3]=uint32_t(dh>>32);')
src=src.replace('uint64_t(da)+4','uint64_t(da)+16').replace('(da&3)','(da&15)').replace('uint64_t(dqa)+4','uint64_t(dqa)+16').replace('(dqa&3)','(dqa&15)')
src=src.replace(' unsigned traps=0;',' unsigned traps=0;std::string terminal_tail;uint64_t done_cycle=0;')
src=src.replace('a.pod(traps);','a.pod(traps);a.str(terminal_tail);a.pod(done_cycle);')
needle='terminal.observe(txbyte);'
assert src.count(needle)==1
src=src.replace(needle,needle+'''terminal_tail+=char(txbyte);if(terminal_tail.size()>256)terminal_tail.erase(0,terminal_tail.size()-256);if(!done_cycle&&(terminal_tail.find("\\nCORE01_LINUX_TEST_DONE\\r\\n")!=std::string::npos||terminal_tail.find("\\nCORE01_LINUX_TEST_DONE\\n")!=std::string::npos))done_cycle=cycle;''')
src=src.replace('  if(Verilated::gotFinish())break;', '''  if(done_cycle&&cycle>done_cycle+1000000){std::cerr<<"LINUX_SCRIPT_COMPLETE cycles="<<cycle<<" frames="<<complete_frames<<" reads="<<display_reads<<" underflow="<<d.video_underflow_rows<<" dma_errors="<<d.video_dma_errors<<" bounds_errors="<<d.video_bounds_errors<<"\\n";d.final();return 0;}
  if(Verilated::gotFinish())break;''')
(out/'main.cpp').write_text(src,encoding='utf-8')
commands=[('rv32 login:', 'root\n'),('# ', 'uname -a\n'),('# ', 'cat /proc/cpuinfo\n'),('# ', 'ps\n'),('# ', 'n=0; while [ ! -p /run/rv32-gui/commands ] && [ "$n" -lt 20 ]; do sleep 1; n=$((n+1)); done; gui-command status; echo PAGE_RC=$?\n'),('# ', 'rv32-counter start; sleep 3; echo COUNT_A=$(cat /run/rv32-demo/counter); sleep 2; echo COUNT_B=$(cat /run/rv32-demo/counter)\n'),('# ', 'rv32-counter stop; echo COUNT_STOP=$(cat /run/rv32-demo/counter); sleep 2; echo COUNT_AFTER=$(cat /run/rv32-demo/counter)\n'),('# ', 'gui-command home; echo CORE01_LINUX_TEST_DONE\n')]
def esc(s):return s.replace('\\','\\\\').replace('\n','\\n').replace('\r','\\r').replace('\t','\\t')
stages=[]
for trigger,payload in commands:
 for i,ch in enumerate(payload):stages.append((trigger if i==0 else payload[i-1],ch))
(out/'commands.tsv').write_text(''.join(esc(t)+'\t'+esc(p)+'\n' for t,p in stages),encoding='utf-8')
print('Created compact shared-clock host-RAM fixture and',len(stages),'echo-paced UART stages.')
