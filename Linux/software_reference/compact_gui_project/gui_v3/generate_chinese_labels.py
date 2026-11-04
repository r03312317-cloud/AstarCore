# 中文标签在构建阶段栅格化为 LVGL 可引用的像素资源，减少运行时字体需求。
# 生成的 C 文件是图像数组，不是内核版本或运行时间的预录输出。
# 首页 uname uptime 和内存仍由主程序在板上 Linux 实时读取。
# 字体路径和输出位置保持原构建配置，源码包不承诺其他电脑具有相同字体环境。
# 生成数组按既定颜色格式及行布局输出，修改色深需要与 LVGL 配置同时核对。
"""Rasterize two fixed labels from OFL-licensed Noto Sans SC for LVGL RGB565."""
import hashlib,json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

HERE=Path(__file__).resolve().parent
FONT=HERE.parent.parent/'linux_uart_hdmi_demo_20261031_01/deps/NotoSansSC.ttf'
OUT=HERE/'generated_labels.c'
if OUT.exists():raise SystemExit('Refusing to overwrite generated font assets')
bg=(16,25,37);fg=(225,238,243)
labels=[('soc_subtitle','运行于 FPGA 自研 RISC-V CPU',12),
        ('soc_footer','UART 命令交互 · LVGL 图形界面',11)]
chunks=['/* Generated from Noto Sans SC, SIL Open Font License 1.1. */', '#include "lvgl.h"']
# audit 保存可独立检查的派生过程摘要，记录哈希和修改范围但不冒充实板结果。
audit=[]
for symbol,text,size in labels:
    font=ImageFont.truetype(str(FONT),size)
    box=font.getbbox(text)
    w=box[2]-box[0]+8;h=box[3]-box[1]+8
    img=Image.new('RGB',(w,h),bg)
    ImageDraw.Draw(img).text((4-box[0],4-box[1]),text,font=font,fill=fg)
    img.save(HERE/(symbol+'.png'))
    # raw 保存解压后的归档或原始数据，内容检查应针对这一实际字节序列。
    raw=bytearray()
    for r,g,b in img.getdata():
        value=((r>>3)<<11)|((g>>2)<<5)|(b>>3)
        raw.extend((value&255,value>>8))
    values=[','.join('0x%02x'%x for x in raw[i:i+24]) for i in range(0,len(raw),24)]
    chunks.append('static const uint8_t %s_pixels[] = {\n%s\n};'%(symbol,',\n'.join(values)))
    chunks.append('const lv_img_dsc_t %s = { .header = { .cf = LV_IMG_CF_TRUE_COLOR, .always_zero = 0, .w = %d, .h = %d }, .data_size = sizeof(%s_pixels), .data = %s_pixels };'%(symbol,w,h,symbol,symbol))
    audit.append({'symbol':symbol,'text':text,'width':w,'height':h,'bytes':len(raw)})
OUT.write_text('\n'.join(chunks)+'\n',encoding='utf-8')
(HERE/'label_assets.json').write_text(json.dumps({'font':'Noto Sans SC','license':'SIL OFL 1.1',
    'font_sha256':hashlib.sha256(FONT.read_bytes()).hexdigest(),'labels':audit},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(audit,ensure_ascii=False))
