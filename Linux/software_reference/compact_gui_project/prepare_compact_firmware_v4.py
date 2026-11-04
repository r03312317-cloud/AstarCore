# 此历史打包工具在已验证的 gzip 根文件系统中替换 GUI 和后台计数脚本。
# 替换按 CPIO 成员精确名称匹配，必须恰好命中一个普通非链接成员。
# 成员名称及数据均按四字节边界推进，最终归档补齐到 512 字节。
# GUI 必须是 32 位 ELF，不能误把 Windows 或宿主架构可执行文件写入根文件系统。
# gzip 的 mtime 固定为零以便复现；压缩后先反解并逐字节核对新归档。
# 根文件系统长度变化后同步更新独立 DTB 及 OpenSBI 内嵌 DTB 的 initrd end。
# 内核 Image 本身保持不变，工具最后记录其余镜像的新哈希与放置地址。
# 输出的 validated 标志起初为假，不能把完成打包当作已经通过实板测试。
"""Replace the GUI and counter in the verified gzip-initramfs bundle."""
import gzip
import hashlib
import json
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OLD = ROOT.parent / 'linux_uart_hdmi_demo_20261031_01/firmware/gui27_demo_v2_gzip'
BOARD = ROOT.parent / 'linux_board_20261031_01'
DEST = ROOT / 'firmware/compact_gui27_v4_gzip'
sys.path.insert(0, str(BOARD))
import upload_boot
from prepare_headless27 import parse_fdt
from upload_boot_gzip_fast import checked_plan


# 计算内容的 SHA256，作为交付文件或固件身份依据；不修改来源内容。
def sha(data):
    return hashlib.sha256(data).hexdigest()


# 把归档偏移向上对齐到四字节边界，CPIO 名称和数据均使用这一规则。
def align4(value):
    return (value + 3) & ~3


# 仅替换指定名称的一份 CPIO 成员，其余成员字节原样保留。
# 拒绝带链接数或校验格式不符的特殊成员，防止不完整重建归档。
# 写入新文件长度后分别补齐成员与归档末尾对齐。
# 归档其他成员连同填充字节保持原样，避免为替换一个程序而意外重排整个 rootfs。
# 文件长度写入 CPIO 头后，再按四字节规则补齐新数据。
# 没有 trailer 或同名成员出现多次都拒绝产出新镜像。
def replace_one(source, name, replacement):
    # pos 保存结构解析游标，每次推进要包含格式要求的头部和对齐填充。
    pos = 0
    found = 0
    # records 保存逐个保留的 CPIO 成员记录，未替换的成员保持原始字节。
    records = []
    while pos + 110 <= len(source):
        if source[pos:pos + 6] not in (b'070701', b'070702'):
            raise ValueError('Invalid CPIO header')
        fields = [int(source[pos + 6 + i * 8:pos + 14 + i * 8], 16) for i in range(13)]
        name_start = pos + 110
        filename = source[name_start:name_start + fields[11] - 1].decode('utf-8').removeprefix('./')
        data_start = align4(name_start + fields[11])
        # end 保存当前边界或截止时刻，必须与同一路径使用的单位保持一致。
        end = align4(data_start + fields[6])
        if end > len(source):
            raise ValueError('Truncated CPIO member')
        if filename == name:
            if fields[4] != 1 or source[pos:pos + 6] != b'070701':
                raise ValueError('Cannot replace a linked or checksum CPIO member')
            header = bytearray(source[pos:data_start])
            header[54:62] = ('%08x' % len(replacement)).encode('ascii')
            header.extend(replacement)
            header.extend(b'\0' * ((-len(header)) % 4))
            records.append(bytes(header))
            found += 1
        else:
            records.append(source[pos:end])
        pos = end
        if filename == 'TRAILER!!!':
            break
    if found != 1 or filename != 'TRAILER!!!':
        raise ValueError('Expected exactly one GUI binary and a trailer')
    # result 保存本阶段形成的结果记录，只有检查分支完成后才能据此报告成功。
    result = b''.join(records)
    return result + b'\0' * ((-len(result)) % 512)


# 组织命令行入口或窗口生命周期；模块被导入时不自动开始板卡启动。
def main():
    if DEST.exists():
        raise SystemExit('Refusing to overwrite candidate firmware')
    check_raw_initramfs = upload_boot.check_no_scheduled_services
    manifest, images = checked_plan(OLD)
    # original 保存修改前的完整字节，用于确认派生结果只改变允许的部分。
    original = {entry['file']: entry['data'] for entry in images}
    app = (ROOT / 'gui_v3/rv32-gui-rv32-stripped').read_bytes()
    if app[:5] != b'\x7fELF\x01':
        raise ValueError('GUI application is not an ELF32 binary')
    # raw 保存解压后的归档或原始数据，内容检查应针对这一实际字节序列。
    raw = gzip.decompress(original['rootfs.cpio'])
    # updated 保存精确替换成员后的归档，压缩前仍检查服务内容及结构完整性。
    updated = replace_one(raw, 'usr/bin/rv32-gui', app)
    counter = (ROOT / 'gui_v3/rv32-counter').read_bytes()
    updated = replace_one(updated, 'usr/bin/rv32-counter', counter)
    check_raw_initramfs(updated)
    # compressed 保存准备上传的 gzip 字节，DTB initrd end 应按这一长度计算。
    compressed = gzip.compress(updated, compresslevel=9, mtime=0)
    if gzip.decompress(compressed) != updated:
        raise ValueError('Compressed initramfs did not round-trip')
    # old_dtb 保存固件原有 DTB，需要和 OpenSBI 内嵌副本比较后再派生新版本。
    old_dtb = original['rv32-rv32.dtb']
    # props 保存按节点路径和属性名索引的 FDT 字段，包含原始值及可修改偏移。
    props = parse_fdt(old_dtb)
    # start 保存本阶段的起始时刻或放置基址，具体单位以当前表达式及调用点为准。
    start = struct.unpack('>I', props[('/chosen', 'linux,initrd-start')]['value'])[0]
    if start != 0x82400000 or start + len(compressed) > 0x83f00000:
        raise ValueError('Unexpected or overflowing initramfs placement')
    # dtb 保存当前设备树数据，修改长度或属性后仍需重新解析校验。
    dtb = bytearray(old_dtb)
    struct.pack_into('>I', dtb, props[('/chosen', 'linux,initrd-end')]['offset'], start + len(compressed))
    dtb = bytes(dtb)
    # changed 保存派生前后不同的属性或路径集合，用于拒绝超出预期的修改。
    changed = [key for key in props if props[key]['value'] != parse_fdt(dtb)[key]['value']]
    if changed != [('/chosen', 'linux,initrd-end')]:
        raise ValueError('Unexpected FDT property change: ' + repr(changed))
    old_fw = original['fw_jump.bin']
    # offset 保存镜像内部或结构数据内部偏移，不是自动等于目标物理地址。
    offset = int(manifest['embedded_fdt_offset'], 0)
    if old_fw[offset:offset + len(old_dtb)] != old_dtb:
        raise ValueError('Old embedded and standalone DTBs differ')
    # fw 保存当前固件字节，更新内嵌 DTB 不等于重新编译了 OpenSBI 代码。
    fw = old_fw[:offset] + dtb + old_fw[offset + len(old_dtb):]
    content = dict(original, **{'fw_jump.bin': fw, 'rv32-rv32.dtb': dtb, 'rootfs.cpio': compressed})
    result = dict(manifest, origin='320x180 GUI in the validated 27MHz gzip bundle',
                  gui_sha256=sha(app), uncompressed_rootfs_sha256=sha(updated),
                  initrd_end=hex(start + len(compressed)), validated_in_rtl=False,
                  validated_on_board=False)
    result['images'] = [{'file': entry['file'], 'address': hex(entry['address']),
                         'size': len(content[entry['file']]), 'sha256': sha(content[entry['file']])}
                        for entry in images]
    DEST.mkdir(parents=True)
    for name, data in content.items():
        # f 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
        with (DEST / name).open('xb') as f:
            f.write(data)
    with (DEST / 'boot_manifest.json').open('x', encoding='utf-8') as f:
        json.dump(result, f, indent=2)
        f.write('\n')
    checked_plan(DEST)
    # audit 保存可独立检查的派生过程摘要，记录哈希和修改范围但不冒充实板结果。
    audit = {'gui_sha256': sha(app), 'counter_sha256': sha(counter), 'raw_rootfs_sha256': sha(updated),
             'compressed_bytes': len(compressed), 'old_compressed_bytes': len(original['rootfs.cpio']),
             'other_cpio_records_preserved': True, 'only_fdt_change': changed,
             'linux_image_unchanged': content['Image'] == original['Image'],
             'checks_passed': True, 'board_access': False}
    with (DEST / 'audit.json').open('x', encoding='utf-8') as f:
        json.dump(audit, f, indent=2)
        f.write('\n')
    print(json.dumps(audit, indent=2))


if __name__ == '__main__':
    main()
