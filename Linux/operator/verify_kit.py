# 完整运行包的本地校验入口，验证清单中的文件大小和 SHA256。
# 本次交付为源码包，缺少便携 Python 位流及固件，因此本工具作为参考源码保留。
# 当前交付入口是包根 verify_sources.py，它校验注释版清单和原始代码恢复关系。
# 校验只读取文件，不打开串口，不调用 JTAG，也不进行 FPGA 配置。
# 完整运行包成功校验只能证明交付完整性，功能结论仍需对应实板日志。
"""Validate all delivered files, bitstream and firmware without board access."""
import hashlib
import json
import sys
from pathlib import Path, PurePosixPath
sys.path.insert(0, str(Path(__file__).resolve().parent))
import backend

root = Path(__file__).resolve().parent
# 显式读取工程元数据或脚本，不修改来源文件。
listing = json.loads((root / 'FILES_SHA256.json').read_text(encoding='utf-8'))
for item in listing['files']:
    rel = PurePosixPath(item['path'])
    if rel.is_absolute() or '..' in rel.parts:
        raise ValueError('Unsafe manifest path')
    path = root.joinpath(*rel.parts)
    if not path.is_file() or path.is_symlink():
        raise ValueError('Missing file: ' + str(rel))
    h = hashlib.sha256()
    # stream 以二进制读取原文件，哈希与结构判断基于实际字节。
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    if path.stat().st_size != item['size'] or h.hexdigest() != item['sha256']:
        raise ValueError('Size or hash mismatch: ' + str(rel))
config, bit, manifest, images = backend.validate_kit()
# result 保存本阶段形成的结果记录，只有检查分支完成后才能据此报告成功。
result = {'passed': True, 'bitstream': bit.name, 'bitstream_sha256': config['bitstream_sha256'],
          'firmware_manifest_sha256': config['firmware_manifest_sha256'],
          'firmware_blocks': sum(item['padded_size'] // 16 for item in images),
          'files_verified': len(listing['files']), 'cpu_hz_configured': manifest['cpu_hz'],
          'board_access': False}
print(json.dumps(result, indent=2))
