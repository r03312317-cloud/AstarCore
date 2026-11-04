from pathlib import Path
import json,csv,html,shutil,subprocess
from PIL import Image,ImageDraw,ImageFont
r=Path(__file__).resolve().parents[1]
font_path='C:/Windows/Fonts/msyh.ttc'
def font(s):return ImageFont.truetype(font_path,s)
def centered(draw,box,text,size=29,fill='#1f2b38'):
    x0,y0,x1,y1=box;lines=text.split('\n');f=font(size)
    heights=[draw.textbbox((0,0),line,font=f)[3] for line in lines]
    total=sum(heights)+10*(len(lines)-1);y=(y0+y1-total)/2
    for line,h in zip(lines,heights):
        w=draw.textlength(line,font=f);draw.text(((x0+x1-w)/2,y),line,font=f,fill=fill);y+=h+10
im=Image.new('RGB',(1500,800),'white');draw=ImageDraw.Draw(im)
boxes=[((60,70,490,220),'取指与方向预测\n8 项队列  2 笔取指信用'),((550,70,980,220),'分配与重命名\n16 项 ROB  7 个有效 IQ 槽'),((1040,70,1450,220),'双槽位执行\nEX0 复杂和整数  EX1 整数'),
 ((1040,300,1450,450),'结果银行和按序提交\n每拍最多两条  精确恢复'),((550,300,980,450),'LSU 与非对齐适配\nMUL 两信用  通用 MDU'),
 ((60,300,490,450),'两路 I cache  16 KiB\n两路 D cache  8 KiB'),((310,560,1190,730),'外部行通道  64 位乘 8 拍\n64 KiB SRAM  UART  计时器  退出寄存器')]
for box,text in boxes:
    draw.rounded_rectangle(box,14,fill='#f1f5f7',outline='#596a78',width=3);centered(draw,box,text,28)
def arrow(a,b,color='#536a7a'):
    draw.line([a,b],fill=color,width=4)
    import math
    angle=math.atan2(b[1]-a[1],b[0]-a[0]);ln=17
    pts=[b,(b[0]-ln*math.cos(angle-.5),b[1]-ln*math.sin(angle-.5)),(b[0]-ln*math.cos(angle+.5),b[1]-ln*math.sin(angle+.5))]
    draw.polygon(pts,fill=color)
edges=[((490,145),(550,145)),((980,145),(1040,145)),((1245,220),(1245,300)),((550,375),(490,375)),((980,375),(1040,375)),((275,300),(275,220)),((275,450),(485,560)),((1040,205),(980,320))]
for a,b in edges:arrow(a,b)
im.save(r/'docs/figures/architecture.png')
# Editable simple SVG of the same architecture, without external assets.
svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1500" height="800" viewBox="0 0 1500 800">','<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#536a7a"/></marker></defs>','<rect width="1500" height="800" fill="white"/>']
for (x0,y0,x1,y1),text in boxes:
 svg.append(f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" rx="14" fill="#f1f5f7" stroke="#596a78" stroke-width="3"/>')
 for j,line in enumerate(text.split('\n')):svg.append(f'<text x="{(x0+x1)/2}" y="{(y0+y1)/2-10+j*42}" text-anchor="middle" font-family="Microsoft YaHei" font-size="28">{html.escape(line)}</text>')
for a,b in edges:svg.append(f'<line x1="{a[0]}" y1="{a[1]}" x2="{b[0]}" y2="{b[1]}" stroke="#536a7a" stroke-width="3" marker-end="url(#arrow)"/>')
svg+=['</svg>'];(r/'docs/figures/architecture.svg').write_text('\n'.join(svg),encoding='utf-8')
# A single compact chart sized for a readable 6-inch document figure.
s=json.loads((r/'analysis/algorithm_summary.json').read_text(encoding='utf-8'));rows=[next(x for x in s['cohorts'] if x['group']==name) for name in ['链表','矩阵','状态机','CRC']]
im=Image.new('RGB',(1500,770),'white');dr=ImageDraw.Draw(im)
dr.text((100,12),'按 ROB 队头 PC 分组的流水线效率',font=font(37),fill='black')
left,top,bottom,right=130,120,650,1440
for val in range(0,101,20):
 y=bottom-(bottom-top)*val/100;dr.line((left,y,right,y),fill='#e3e8ec',width=2);dr.text((40,y-18),str(val)+'%',font=font(28),fill='#35424f')
palette=['#087e8b','#4b62c2','#aa6034'];fields=['dual_issue_percent','dual_retire_percent','commit_wait_percent']
for j,row in enumerate(rows):
 center=left+165+j*320
 for k,key in enumerate(fields):
  x=center-105+k*70;y=bottom-(bottom-top)*row[key]/100
  dr.rectangle((x,y,x+52,bottom),fill=palette[k]);dr.text((x-5,y-37),f'{row[key]:.1f}',font=font(23),fill='#27313c')
 dr.text((center-50,670),row['group'],font=font(32),fill='black')
for j,label in enumerate(['双发射接收','双提交','ROB 等待提交']):
 x=200+j*390;dr.rectangle((x,730,x+25,755),fill=palette[j]);dr.text((x+40,723),label,font=font(28),fill='#27313c')
im.save(r/'docs/figures/algorithm_comparison_doc.png')
# Charts in the existing CSV windows, with document-sized labels.
for name in ['链表','矩阵','状态机']:
 with (r/f'analysis/{name}_sample64.csv').open(encoding='utf-8-sig') as f:raw=list(csv.DictReader(f))
 raw=raw[:32]
 im=Image.new('RGB',(1500,850),'white');dr=ImageDraw.Draw(im)
 start=int(raw[0]['window_index']);dr.text((55,10),f'{name}局部窗口  周期 {start} 至 {start+31}',font=font(34),fill='black')
 tracks=[('新接收数','issue_count','#087e8b',2),('提交数','retire_count','#4b62c2',2),('ROB 占用','rob_count','#39475e',16),('等待提交','rob_commit_wait','#aa6034',1),('恢复清空','recovery','#a04453',1)]
 x0,x1=230,1450
 for j,(label,col,color,maxval) in enumerate(tracks):
  ytop=100+j*135;ybase=ytop+90
  dr.text((20,ytop+23),label,font=font(29),fill='black')
  dr.line((x0,ybase,x1,ybase),fill='#abb7c0',width=2)
  for tick in range(0,33,8):
   x=x0+(x1-x0)*tick/32;dr.line((x,ytop-5,x,ybase),fill='#edf0f2',width=2)
   if j==len(tracks)-1:
    tick_label=str(start+tick);tick_font=font(25)
    label_x=x-dr.textlength(tick_label,font=tick_font) if tick==32 else x-15
    dr.text((label_x,ybase+15),tick_label,font=tick_font,fill='#35424f')
  dr.text((180,ytop-10),str(maxval),font=font(24),fill='#5a6875')
  dr.text((195,ybase-15),'0',font=font(24),fill='#5a6875')
  pts=[]
  for k,row in enumerate(raw):
   x=x0+(x1-x0)*k/32;xx=x0+(x1-x0)*(k+1)/32;y=ybase-90*int(row[col])/maxval
   if pts:pts.append((x,y))
   pts.extend([(x,y),(xx,y)])
  dr.line(pts,fill=color,width=4)
 dr.text((235,805),'局部图只说明逐拍关系  分算法比例使用完整计时窗口',font=font(25),fill='#596879')
 im.save(r/f'docs/figures/{name}_doc32.png')

base=Path(json.loads((r/'evidence/source_identity.json').read_text(encoding='utf-8'))['base'])
dest=r/'implementation_reference';dest.mkdir(exist_ok=True)
shutil.copy2(base/'prj_tasks/pnr_1/report_timing/rv32_coremark_top_boot.rtr',dest/'native_routed_timing.rtr')
shutil.copy2(base/'prj_tasks/pnr_1/device_map/run.log',dest/'native_device_map.log')
shutil.copy2(base/'bitstream_01/prj_tasks/pnr_1/generate_bitstream/rv32_coremark_top_boot.sbit',dest/'last_board_130MHz.sbit')
for n in ['resume_v2.tcl','ila117.fic','probe117.csv']:shutil.copy2(base/n,dest/n)
objdump='C:/Users/user/AppData/Roaming/xPacks/riscv-none-elf-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objdump.exe'
with (r/'analysis/performance10_disassembly.txt').open('wb') as f:
 p=subprocess.run([objdump,'-d','-M','no-aliases',str(r/'software/builds/performance10/firmware.elf')],stdout=f);assert not p.returncode
print('Document assets and physical reference ready')
