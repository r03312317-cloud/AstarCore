# 历史 headless 27 MHz 固件派生工具，保留它用于追踪时钟与设备树修改来源。
# 该工具把 framebuffer 改为 disabled；最新 HDMI 演示不用这个结果作为最终镜像。
# CPU 与 UART 两个 clock frequency 单元同时改为 27000000，mtime timebase 保持 1000000。
# OpenSBI 内嵌 DTB 与独立 DTB 必须保持相同，否则传入 Linux 的平台描述可能与上传文件不同。
# FDT 属性长度变化还会改变结构区偏移和总长，不能只改字符串内容而不改头部。
# 工具拒绝覆盖已有输出，生成新镜像后仍需单独进行仿真和实板验证。
# 当前注释版只保留代码供阅读，没有执行本脚本或生成替代固件。
"""Derive a 27 MHz headless board bundle from the frozen v4 images.

Only two FDT clock-frequency cells and the framebuffer status change.  The
standalone and embedded FDTs stay identical; firmware code is not rebuilt.
"""
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path('D:/workspace/riscv-fpga-soc/Soc_linux')
HERE = Path(__file__).resolve().parent
SRC = ROOT / 'RV32_RV32_Linux_GUI/firmware/boot-video-v4'
DEST = HERE / 'firmware/headless27'
BE = '>I'

# 计算内容的 SHA256，作为交付文件或固件身份依据；不修改来源内容。
def sha(data):
    return hashlib.sha256(data).hexdigest()

# 从给定偏移读取一个大端 32 位单元，FDT 字节序不能跟随 Windows 本机序。
def u32(data, at):
    return struct.unpack_from(BE, data, at)[0]

# 以大端读取 FDT 头部和结构 token，保留每个属性的原始字节及偏移。
# 节点栈构成完整路径，属性名从 strings 区按 name offset 解析。
# 记录偏移供后续定点修改使用，解析动作本身不改变 DTB。
# 节点名和属性名来自不同区段，不能用普通文本搜索替代结构 token 解析。
# 属性数据长度不一定是四的倍数，推进游标时需要向上对齐。
# 未知 token 直接报错，不继续沿错误偏移修改固件。
def parse_fdt(data):
    assert u32(data,0)==0xd00dfeed and u32(data,4)==len(data)
    off_struct,off_strings,size_strings,size_struct=(u32(data,i) for i in (8,12,32,36))
    assert off_struct+size_struct<=off_strings and off_strings+size_strings<=len(data)
    # pos 保存结构解析游标，每次推进要包含格式要求的头部和对齐填充。
    # end 保存当前边界或截止时刻，必须与同一路径使用的单位保持一致。
    # props 保存按节点路径和属性名索引的 FDT 字段，包含原始值及可修改偏移。
    pos=off_struct;end=off_struct+size_struct;stack=[];props={}
    while pos<end:
        token=u32(data,pos);pos+=4
        if token==1:
            stop=data.index(0,pos);name=bytes(data[pos:stop]).decode('ascii')
            stack.append(name);pos=(stop+4)&~3
        elif token==2:
            stack.pop()
        elif token==3:
            length=u32(data,pos);nameoff=u32(data,pos+4);pos+=8
            # start 保存本阶段的起始时刻或放置基址，具体单位以当前表达式及调用点为准。
            start=off_strings+nameoff;stop=data.index(0,start)
            prop=bytes(data[start:stop]).decode('ascii')
            node='/'+'/'.join(n for n in stack if n)
            props[(node,prop)]={'value':bytes(data[pos:pos+length]),'offset':pos,
                                'length_offset':pos-8,'length':length}
            pos=(pos+length+3)&~3
        elif token==4:
            pass
        elif token==9:
            break
        else:
            raise ValueError('Unknown FDT token %d at %d' % (token,pos-4))
    return props

# 组织命令行入口或窗口生命周期；模块被导入时不自动开始板卡启动。
def main():
    if DEST.exists():
        raise SystemExit('Refusing to overwrite an existing firmware bundle')
    # manifest 保存待校验的镜像元数据，不能把其中的名称当成内容已经可信。
    # 显式读取工程元数据或脚本，不修改来源文件。
    manifest=json.loads((SRC/'boot_manifest.json').read_text(encoding='utf-8'))
    # 逐份处理镜像 image，每份保留自己的物理地址 大小和哈希。
    # 只有整组镜像都完成当前校验阶段，外层流程才会继续启动。
    for image in manifest['images']:
        # data 保存本阶段处理的实际字节，是否为镜像或串口响应由调用接口决定。
        data=(SRC/image['file']).read_bytes()
        assert len(data)==image['size'] and sha(data)==image['sha256'],image['file']
    # original 保存修改前的完整字节，用于确认派生结果只改变允许的部分。
    original=(SRC/'rv32-rv32.dtb').read_bytes()
    firmware=(SRC/'fw_jump.bin').read_bytes()
    # offset 保存镜像内部或结构数据内部偏移，不是自动等于目标物理地址。
    offset=firmware.find(original)
    assert offset==0x21000 and firmware.find(original,offset+1)<0
    # readelf/nm for the delivered ELF put fw_fdt_bin at 0x80021000 and
    # the next symbol, _jump_addr, at 0x80021800: 2048 bytes allocated.
    # allocated 保存内嵌 FDT 预留空间的字节上限，派生 DTB 不能覆盖后续固件符号。
    allocated=0x800
    assert len(original)<=allocated and firmware[offset+len(original):offset+allocated]==bytes(allocated-len(original))
    props=parse_fdt(original)
    cpu=props[('/cpus/cpu@0','clock-frequency')]
    uart=props[('/soc/serial@10000000','clock-frequency')]
    display=props[('/soc/framebuffer@10001000','status')]
    assert cpu['value']==uart['value']==struct.pack(BE,100000000)
    assert display['value']==b'okay\0' and display['length']==5
    assert u32(props[('/cpus','timebase-frequency')]['value'],0)==1000000
    assert u32(props[('/chosen','linux,initrd-start')]['value'],0)==0x82400000
    assert u32(props[('/chosen','linux,initrd-end')]['value'],0)==0x82400000+(SRC/'rootfs.cpio').stat().st_size
    # result 保存本阶段形成的结果记录，只有检查分支完成后才能据此报告成功。
    result=bytearray(original)
    for p in (cpu,uart):
        result[p['offset']:p['offset']+4]=struct.pack(BE,27000000)
    # Property was 5 bytes padded to 8. "disabled\0" is 9 bytes padded to 12.
    start=display['offset'];old_pad=(display['length']+3)&~3
    struct.pack_into(BE,result,display['length_offset'],9)
    result[start:start+old_pad]=b'disabled\0'+b'\0'*3
    for header_at in (4,12,36):
        struct.pack_into(BE,result,header_at,u32(result,header_at)+4)
    # newdtb 保存派生出的完整 DTB，独立文件与固件内嵌副本必须一致。
    newdtb=bytes(result)
    assert len(newdtb)==len(original)+4 and len(newdtb)<=allocated
    newprops=parse_fdt(newdtb)
    assert newprops[('/cpus/cpu@0','clock-frequency')]['value']==struct.pack(BE,27000000)
    assert newprops[('/soc/serial@10000000','clock-frequency')]['value']==struct.pack(BE,27000000)
    assert newprops[('/soc/framebuffer@10001000','status')]['value']==b'disabled\0'
    assert newprops[('/chosen','linux,initrd-start')]['value']==props[('/chosen','linux,initrd-start')]['value']
    assert newprops[('/chosen','linux,initrd-end')]['value']==props[('/chosen','linux,initrd-end')]['value']
    # patched 保存定点修改后的固件，受保护的其他区域应与来源一致。
    patched=firmware[:offset]+newdtb+firmware[offset+len(newdtb):]
    assert len(patched)==len(firmware) and patched[offset+allocated:]==firmware[offset+allocated:]
    assert patched[offset:offset+len(newdtb)]==newdtb
    DEST.mkdir(parents=True,exist_ok=False)
    files={'fw_jump.bin':patched,'rv32-rv32.dtb':newdtb,
           'Image':(SRC/'Image').read_bytes(),'rootfs.cpio':(SRC/'rootfs.cpio').read_bytes()}
    # images 保存已经解析的镜像列表，包含放置地址 大小 哈希及真实数据。
    images=[]
    # 逐份处理镜像 original_image，每份保留自己的物理地址 大小和哈希。
    for original_image in manifest['images']:
        name=original_image['file'];contents=files[name]
        # f 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
        with (DEST/name).open('xb') as f:f.write(contents)
        images.append({'file':name,'address':original_image['address'],
                       'size':len(contents),'sha256':sha(contents)})
    receipt={'origin':'frozen boot-video-v4; embedded FDT adapted for headless 27 MHz board',
             'cpu_hz':27000000,'uart_hz':27000000,'timer_hz':1000000,
             'framebuffer':'disabled','embedded_fdt_offset':hex(offset),
             'fdt_allocation_bytes':allocated,'source_dtb_sha256':sha(original),
             'source_firmware_sha256':sha(firmware),'reset_pc':'0x80000000',
             'validated_on_board':False,'validated_in_rtl':False,'images':images}
    with (DEST/'boot_manifest.json').open('x',encoding='utf-8') as f:
        json.dump(receipt,f,indent=2);f.write('\n')
    print(json.dumps(receipt,indent=2))

if __name__=='__main__':main()
