# gzip 根文件系统减少串口需要上传的总字节，不改变板上 DDR 回读协议。
# 压缩文件必须先能完整解压，解压结果仍需通过根文件系统结构与服务检查。
# 计划使用压缩后文件的真实大小，DTB 的 initrd end 必须与这份文件长度匹配。
# 解压发生在板上 Linux 启动过程中，电脑没有代替 FPGA 执行 Linux。
# checked plan 同时核验所有镜像的放置与身份，不能单独替换 gzip 后仍沿用旧清单。
"""Upload the optional gzip-initramfs candidate with existing batch transport.

This candidate is validated offline only. --dry-run never opens a serial port.
"""
import gzip
import json
import struct
import sys
from pathlib import Path

import upload_boot
import upload_boot_fast
from prepare_headless27 import parse_fdt

ROOT = Path(__file__).resolve().parent
BUNDLE = ROOT / 'firmware/headless27_nocron_gzip'
check_cpio = upload_boot.check_no_scheduled_services


# 先验证 gzip 封装可完整解压，再把解压归档交给内容校验流程。
# gzip 封装中的压缩数据和尾部校验都必须被解压器接受。
# 检查通过只证明固件可解析，不能代替真实 Linux 解包启动验证。
def check_gzip(data):
    if not data.startswith(b'\x1f\x8b\x08'):
        raise ValueError('Expected gzip-compressed initramfs')
    check_cpio(gzip.decompress(data))


# 核对固件清单 文件哈希 地址和对齐后生成实际上传顺序。
# 实际压缩镜像长度和文件哈希用于上传，解压后内容用于服务及归档校验。
# 内嵌 DTB 独立 DTB 和压缩根文件系统需要作为配套整体处理。
# 任何一个检查失败都不返回可继续上传的计划。
def checked_plan(bundle):
    upload_boot.check_no_scheduled_services = check_gzip
    manifest, images = upload_boot.plan(bundle)
    if manifest.get('rootfs_compression') != 'gzip':
        raise ValueError('Manifest must explicitly identify gzip rootfs')
    named = {i['file']:i for i in images}
    # dtb 保存当前设备树数据，修改长度或属性后仍需重新解析校验。
    dtb = named['rv32-rv32.dtb']['data']
    # offset 保存镜像内部或结构数据内部偏移，不是自动等于目标物理地址。
    offset = int(manifest['embedded_fdt_offset'], 0)
    if named['fw_jump.bin']['data'][offset:offset+len(dtb)] != dtb:
        raise ValueError('Embedded and standalone DTBs differ')
    # props 保存按节点路径和属性名索引的 FDT 字段，包含原始值及可修改偏移。
    props = parse_fdt(dtb)
    # start 保存本阶段的起始时刻或放置基址，具体单位以当前表达式及调用点为准。
    start = struct.unpack('>I', props[('/chosen','linux,initrd-start')]['value'])[0]
    # end 保存当前边界或截止时刻，必须与同一路径使用的单位保持一致。
    end = struct.unpack('>I', props[('/chosen','linux,initrd-end')]['value'])[0]
    if start != named['rootfs.cpio']['address'] or end != start+named['rootfs.cpio']['size']:
        raise ValueError('DTB initramfs range does not match compressed image')
    return manifest, images


if __name__ == '__main__':
    upload_boot_fast.BUNDLE = BUNDLE
    upload_boot_fast.plan = checked_plan
    if sys.argv[1:] == ['--dry-run']:
        manifest, images = checked_plan(BUNDLE)
        print(json.dumps({'bundle':str(BUNDLE), 'blocks':sum(i['padded_size']//16 for i in images),
                          'rootfs_compression':manifest['rootfs_compression'],
                          'hardware_access_requested':False,
                          'actual_rtl_or_board_boot':False}, indent=2))
    else:
        raise SystemExit(upload_boot_fast.main())
