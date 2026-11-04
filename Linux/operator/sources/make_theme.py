# 离线主题素材生成器把图形和文字制作成 psplash 使用的图像资源。
# 此程序在电脑构建阶段运行，板上的 Linux psplash 读取生成后的资源显示启动画面。
# 主题采用 RV32 自定义标识，不能把它称为 Ubuntu 官方桌面。
# 素材图本身不能证明 Linux 已启动，证据仍来自内核串口及实时系统查询。
# 颜色 分辨率 字体和居中位置由下列绘图代码决定，新增注释没有替换原图。
# 生成素材不需要打开 JTAG 或串口，也不会把镜像写入板卡。
"""Create a compact psplash theme using the Linux 6.12.9 kernel logo asset."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
FONT = ROOT / 'NotoSansSC.ttf'
if not FONT.is_file():
    FONT = ROOT.parent / 'linux_uart_hdmi_demo_20261031_01/deps/NotoSansSC.ttf'
TARGET = ROOT / 'psplash_adapted/base-images/psplash-poky.png'
BG = (0x1b, 0x10, 0x20)

logo = Image.open(ROOT / 'logo_linux_clut224.ppm').convert('RGB')
logo = logo.resize((60, 60), Image.Resampling.LANCZOS)
# Blend the logo's black backdrop into the theme without modifying its source.
logo = Image.frombytes('RGB', logo.size, bytes(
    bg + (pixel * (255 - bg) + 127) // 255
    for rgb in logo.getdata() for pixel, bg in zip(rgb, BG)))
canvas = Image.new('RGB', (320, 120), BG)
canvas.paste(logo, ((320 - logo.width) // 2, 2))
draw = ImageDraw.Draw(canvas)
font_title = ImageFont.truetype(str(FONT), 24)
font_label = ImageFont.truetype(str(FONT), 10)
font_title.set_variation_by_axes([600])
font_label.set_variation_by_axes([500])


# 按真实字体测量结果定位主题文字，不通过空格数量猜测显示居中位置。
def center(y, text, font, fill):
    bounds = draw.textbbox((0, 0), text, font=font)
    draw.text(((320 - (bounds[2] - bounds[0])) // 2, y), text, font=font, fill=fill)


center(61, 'Linux', font_title, (246, 244, 247))
center(96, 'RV32 RV32  |  BUILDROOT', font_label, (178, 163, 185))
canvas.save(TARGET)

# Preview reproduces the position used by psplash; status is illustrative.
preview = Image.new('RGB', (320, 180), BG)
preview.paste(canvas, (0, 15))
draw = ImageDraw.Draw(preview)
center_y = 138
label = 'Starting Linux userspace'
font = ImageFont.truetype(str(FONT), 10)
font.set_variation_by_axes([500])
box = draw.textbbox((0, 0), label, font=font)
draw.text(((320 - (box[2] - box[0])) // 2, center_y), label, fill=(230, 224, 234), font=font)
preview.resize((960, 540), Image.Resampling.NEAREST).save(ROOT / 'theme_preview.png')
print('Created psplash theme and illustrative preview.')
