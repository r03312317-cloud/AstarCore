"""Package source-only files from the sealed Linux project; no hardware access."""
from pathlib import Path,PurePosixPath
import csv,gzip,hashlib,io,json,os,re,struct,subprocess,sys,zipfile

ROOT=Path('D:/workspace/riscv-fpga-soc');BASE=ROOT/'Soc_linux'
F=ROOT/'XXX/RV32-Linux_01';W=F/'workspace'
NAME='RV32-Linux_01_Source_20261103_01'
ARCHIVE=BASE/'deliveries'/(NAME+'.zip')
AUDIT=BASE/'reports/source_package_20261103_01'
REPORT=BASE/'reports/RV32-Linux_01_架构源码工作流_20261102/RV32-Linux_01_工程架构源码与工作流报告.zip'
REPORT_SHA='a228ace70ee2e0cd2c2c861a2423e44ba26d8e4d532f5ea4e92c2d9a3a123331'
FREEZE_SHA='c680148b98356762c4fd8ffd2fda1680a0916ee689f95e8b30789e3641136e9d'
digest=lambda data:hashlib.sha256(data).hexdigest()
load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda:f.read(1048576),b''):h.update(block)
    return h.hexdigest()
def write_new(p,data):
    p.parent.mkdir(parents=True,exist_ok=True)
    with p.open('xb') as f:f.write(data)

VERIFY='''"""Verify this source package only; never open serial/JTAG or launch PDS."""
from pathlib import Path,PurePosixPath
import hashlib,json
r=Path(__file__).resolve().parent
m=json.loads((r/'SOURCE_PACKAGE_MANIFEST.json').read_text(encoding='utf-8'))
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
for row in m['files']:
 rel=PurePosixPath(row['path']);assert not rel.is_absolute() and '..' not in rel.parts
 p=r.joinpath(*rel.parts)
 assert p.resolve().is_relative_to(r) and p.is_file() and not p.is_symlink(),str(p)
 assert p.stat().st_size==row['bytes'] and sha(p)==row['sha256'],str(p)
src=json.loads((r/'source_manifest.json').read_text(encoding='utf-8'))
for path,expected in src['files_sha256'].items():assert sha(r/path)==expected,path
imp=json.loads((r/'provenance/import_result.json').read_text(encoding='utf-8'))
for row in imp['files']:assert sha(r/'provenance/core01_original'/row['file'])==row['sealed_sha256'],row['file']
print(json.dumps({'passed':True,'package_files':len(m['files']),'pds_inputs':len(src['files_sha256']),
 'ordered_hdl_sources':len(src['source_order']),'core01_originals':len(imp['files']),
 'cpu_configured_hz':m['cpu_configured_hz'],'source_only':True,'hardware_access':False},indent=2))
'''

def export_dts(data):
    head=struct.unpack_from('>10I',data);assert head[0]==0xd00dfeed
    total,structoff,stringoff,resoff=head[1:5];strings=data[stringoff:stringoff+head[8]]
    lines=['/dts-v1/;','', '// Generated from the exact board27 DTB, not the legacy reference DTS.',
           '// Source DTB SHA-256: '+digest(data[:total]),'']
    pos=resoff
    while True:
        address,size=struct.unpack_from('>QQ',data,pos);pos+=16
        if address==0 and size==0:break
        lines.append('/memreserve/ 0x%x 0x%x;'%(address,size))
    pos=structoff;depth=0;property_count=0
    while True:
        token=struct.unpack_from('>I',data,pos)[0];pos+=4
        if token==1:
            stop=data.index(0,pos);name=data[pos:stop].decode();pos=(stop+4)&~3
            lines.append('    '*depth+(name or '/')+' {');depth+=1
        elif token==2:depth-=1;lines.append('    '*depth+'};')
        elif token==3:
            length,nameoff=struct.unpack_from('>II',data,pos);pos+=8
            name=strings[nameoff:strings.index(0,nameoff)].decode();value=data[pos:pos+length];pos=(pos+length+3)&~3
            prefix='    '*depth+name;property_count+=1
            if not value:lines.append(prefix+';');continue
            if value[-1]==0 and any(32<=c<127 for c in value) and all(c==0 or 32<=c<127 for c in value):
                chunks=value[:-1].decode().split('\0');assert b'\0'.join(x.encode() for x in chunks)+b'\0'==value
                rhs=', '.join(json.dumps(x,ensure_ascii=True) for x in chunks)
            elif length%4==0:
                cells=struct.unpack('>'+str(length//4)+'I',value)
                assert struct.pack('>'+str(len(cells))+'I',*cells)==value
                rhs='<'+ ' '.join('0x%08x'%n for n in cells)+'>'
            else:
                assert bytes.fromhex(value.hex())==value
                rhs='['+' '.join('%02x'%n for n in value)+']'
            lines.append(prefix+' = '+rhs+';')
        elif token==4:pass
        elif token==9:break
        else:raise ValueError(token)
    assert depth==0
    return ('\n'.join(lines)+'\n').encode(),property_count

def main():
    assert not ARCHIVE.exists() and not AUDIT.exists(),'Never overwrite existing delivery/evidence'
    assert sha(F/'FREEZE_MANIFEST.json')==FREEZE_SHA and sha(REPORT)==REPORT_SHA
    freeze=load(F/'FREEZE_MANIFEST.json');version=load(F/'FROZEN_VERSION.json');source=load(W/'source_manifest.json')
    assert len(source['files_sha256'])==145 and len(source['source_order'])==136
    assert all(sha(W/name)==expected for name,expected in source['files_sha256'].items())
    AUDIT.mkdir(parents=True)
    staging=AUDIT/'staging'/NAME;staging.mkdir(parents=True)
    entries={};skipped=[]
    def add(name,data,origin):
        p=PurePosixPath(name)
        assert not p.is_absolute() and '..' not in p.parts and '\\' not in name
        assert name.casefold() not in {k.casefold() for k in entries},name
        write_new(staging/name,data)
        entries[name]={'path':name,'bytes':len(data),'sha256':digest(data),'origin':origin}
    def original(p,name=None):
        assert not p.is_symlink() and not p.is_junction()
        rel=p.relative_to(F).as_posix();data=p.read_bytes()
        record=freeze['files'][rel]
        assert len(data)==record['bytes'] and digest(data)==record['sha256'],str(p)
        add(name or p.relative_to(W).as_posix(),data,str(p))
    def tree(name,filtered=False):
        for p in sorted((W/name).rglob('*')):
            if p.is_symlink() or p.is_junction():raise ValueError('Unexpected link: '+str(p))
            if not p.is_file():continue
            raw=p.read_bytes()
            omit=(p.suffix.lower() in ('.log','.elf','.o','.obj','.a','.so','.dll','.exe','.pyd','.pyc')
                  or raw.startswith((b'\x7fELF',b'MZ')))
            if filtered and omit:skipped.append(p.relative_to(W).as_posix());continue
            original(p)
    for name in ('rtl','inputs','provenance','sim','scripts','tools'):tree(name)
    tree('software_reference',filtered=True)
    for name in ('sources','support','vendor'):
        tree('operator/'+name,filtered=True)
    # Keep host application sources and reference configuration, without the
    # portable Python runtime, bitstream, firmware or full-kit hash inventory.
    for name in ('backend.py','start_linux.py','preflight.py','Start_Linux.cmd','verify_kit.py','kit.json'):
        original(W/'operator'/name)
    for p in sorted(W.glob('*.py')):
        if p.name=='verify_candidate.py':original(p,'docs/reference_verification/verify_candidate.py')
        else:original(p)
    for p in sorted(W.glob('*.sh')):original(p)
    for name in ('source_manifest.json','BOARD_VALIDATION.json','BOARD_VALIDATION.md','CPU替换验证报告_20261102.md'):
        original(W/name,('docs/'+name if name!='source_manifest.json' else name))
    crypto=W/'build/crypto/crypto_vectors.h'
    if crypto.exists():original(crypto)
    bundle=W/'operator/firmware_splash';boot=load(bundle/'boot_manifest.json')
    dt=(bundle/'rv32-rv32.dtb').read_bytes()
    assert digest(dt)==next(x['sha256'] for x in boot['images'] if x['file']=='rv32-rv32.dtb')
    dts,count=export_dts(dt);add('software_current/rv32-rv32-board27.dts',dts,'derived from verified runtime DTB '+digest(dt))
    raw=(bundle/'rootfs.cpio').read_bytes();raw=gzip.decompress(raw);pos=0;runtime_rows=[]
    configs={'etc/inittab','etc/fstab','etc/hostname','etc/issue','etc/profile'}
    while pos+110<=len(raw):
        assert raw[pos:pos+6] in (b'070701',b'070702')
        fields=[int(raw[pos+6+i*8:pos+14+i*8],16) for i in range(13)]
        start=pos+110;name=raw[start:start+fields[11]-1].decode().removeprefix('./')
        start=(start+fields[11]+3)&~3;end=start+fields[6];data=raw[start:end];pos=(end+3)&~3
        if name=='TRAILER!!!':break
        if fields[1]&0o170000==0o100000 and (data.startswith(b'#!') or name in configs):
            add('software_current/rootfs_overlay/'+name,data,'verified runtime initramfs member '+name)
            runtime_rows.append({'path':name,'bytes':len(data),'sha256':digest(data)})
    runtime={'source_dtb_sha256':digest(dt),'dts_properties_preserved':count,'rootfs_scripts_and_configs':runtime_rows,
             'source_rootfs_sha256':next(x['sha256'] for x in boot['images'] if x['file']=='rootfs.cpio'),
             'cpu_configured_hz':27000000,'framebuffer_enabled':True,'source_only':True}
    add('software_current/runtime_source_manifest.json',(json.dumps(runtime,ensure_ascii=False,indent=2)+'\n').encode(),'runtime source extraction')
    # The previously delivered report already carries its relative source
    # browser links and diagrams. Include it without internal render QA files.
    with zipfile.ZipFile(REPORT) as z:
        seen=set()
        for info in z.infolist():
            if info.is_dir():continue
            p=PurePosixPath(info.filename)
            assert not p.is_absolute() and '..' not in p.parts and len(p.parts)>1
            assert info.filename.casefold() not in seen;seen.add(info.filename.casefold())
            assert ((info.external_attr>>16)&0o170000)!=0o120000
            add('docs/architecture/'+PurePosixPath(*p.parts[1:]).as_posix(),z.read(info),'verified architecture report archive '+REPORT_SHA)
    info=dict(version,package_kind='source_only',linux_upstream_source_archive_included=False,
              portable_python_runtime_included=False,bitstream_included=False,runtime_images_included=False,
              pds_inputs=145,ordered_hdl_sources=136,source_freeze_manifest_sha256=FREEZE_SHA)
    add('SOURCE_VERSION.json',(json.dumps(info,ensure_ascii=False,indent=2)+'\n').encode(),'sealed identity plus source package scope')
    add('verify_sources.py',VERIFY.encode(),'source-only verifier')
    readme='''# RV32 Linux 01 源码包

基于永久封存的 RV32-Linux_01，CPU 为 Core_01 的 Linux 适配版，配置 27 MHz。

## 包含范围

- rtl/、inputs/：全部 145 个原始 FPGA 输入，136 个有序 HDL 源，含 CPU、Sv32、cache、外设、DDR/HDMI 集成、CDC、约束和所需 Pango 受保护 IP 源文件。
- software_reference/：Linux BSP 驱动与配置、Buildroot/OpenSBI 适配、GUI/LVGL 8.3.11 源码归档、图形/字体素材和许可证。
- software_current/：从实际上板镜像导出的 27 MHz 且 framebuffer 已启用的 DTS，以及实际 rootfs 启动脚本、计数与切页脚本。DTS 各属性按原字节保留；来源和哈希见 runtime_source_manifest.json。
- operator/：Windows 串口控制台、下载和上传工具的源程序、psplash 适配源码、相关第三方源码和许可证。
- sim/、scripts/、tools/、provenance/：仿真、验证脚本、PDS 重建辅助、原核与 Linux 移植差异。
- docs/architecture/：18 页架构源码工作流报告及可点击源码的离线阅读版。打开其中的 HTML 报告即可阅读。

按此前要求，不包含 Linux 上游源码原件；不包含位流、运行镜像、便携 Python 运行库、已编译 GUI、原生 PDS 网表/数据库或大型仿真缓存。Linux 完整软件重建仍需对应上游源码、交叉工具链及依赖。Pango 商业工具和许可不在包内。

## 源码校验与硬件工程重建

在解压后的本包根目录，用本机 Python 3.9 或以上版本运行：

```text
python -B verify_sources.py
python -B rebuild_fpga.py --prepare-only --output fpga_prepare_NEW
python -B rebuild_fpga.py --output fpga_rebuild_NEW
```

第一项核对本包文件、145 个 FPGA 输入和 14 份原核源文件；第二项只生成本地 PDS 工程；第三项执行完整原生 PDS 构建，需自行安装 PDS 2025.2 和合法许可，可用 --pds 与 --license 指定路径。每个输出目录必须尚不存在，禁止在 XXX 封存目录内构建。

## 软件参考与实际配置

software_reference/linux/rv32-rv32.dts 保留早期 100 MHz、framebuffer disabled 的参考内容；本版实际上板配置请以 software_current/rv32-rv32-board27.dts 为准。software_current/rootfs_overlay 保存运行镜像中的实际脚本，旧 Buildroot overlay 仅为参考。构建设备树需要 dtc；导出的源与原 DTB 属性字节一致，不承诺 dtc 重新排列后的 DTB 二进制哈希与原件相同。

本包保留历史软件构建脚本中的原始绝对路径。修改前应准备独立工作目录，核对工具链、上游源码与 sysroot，再调整路径。完整 Linux 仿真另需运行镜像；本次仅打包源码，没有重新综合、运行 Linux 或进行上板。

## 与完整演示工程的关系

operator/ 内是源程序，未配套运行位流、固件和 Python，因此不应把本包当作可直接一键上板的运行包。直接演示请使用此前的完整上板工程，或从 XXX/RV32-Linux_01 恢复的可写演示副本。

本包使用 verify_sources.py 校验。docs/reference_verification/verify_candidate.py 和 operator/verify_kit.py 保留原验证代码供阅读，它们针对完整运行工程的文件布局，不是本源码包的入口。

本版实板已完成 Linux 启动、root 串口命令及用户确认 HDMI 正常；切页和计数启停本轮未继续复测。各文件原有版权、许可证与第三方声明完整保留，不能将全部文件统一宣称为同一许可证。
'''
    add('README.md',readme.encode(),'source package instructions')
    add('package_sources.py',Path(__file__).read_bytes(),'packaging script provenance; not a build entry')
    exclusions={'excluded_source_files':skipped,'excluded_trees':['operator/runtime','operator/bitstream','operator/firmware_splash','native_pds','large RTL build caches'],
                'linux_upstream_sources_included':False,'hardware_access':False,'scheduled_tasks_created':False}
    add('PACKAGE_SCOPE.json',(json.dumps(exclusions,ensure_ascii=False,indent=2)+'\n').encode(),'scope inventory')
    # Forbid accidentally carrying runtime executables/images or Linux tarballs.
    forbidden=[]
    for name,row in entries.items():
        p=staging/name
        if name.startswith('docs/'):continue
        if p.suffix.lower() in ('.sbit','.bit','.elf','.exe','.dll','.pyd','.dtb','.cpio','.o','.obj','.a','.so'):forbidden.append(name)
        if p.read_bytes()[:4] in (b'\x7fELF',) or p.read_bytes()[:2]==b'MZ':forbidden.append(name)
        if re.search(r'(^|/)linux[-_]\d.*\.(tar\.(xz|gz|bz2)|zip)$',name,re.I):forbidden.append(name)
    assert not forbidden,forbidden
    metadata={'name':NAME,'package_kind':'source_only','cpu_configured_hz':27000000,'cpu_build_id':version['build_id'],
              'files':list(entries.values()),'source_freeze_manifest_sha256':FREEZE_SHA,
              'linux_upstream_source_archive_included':False,'runtime_images_included':False}
    write_new(staging/'SOURCE_PACKAGE_MANIFEST.json',(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n').encode())
    with zipfile.ZipFile(ARCHIVE,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as z:
        for p in sorted(staging.rglob('*')):
            if not p.is_file():continue
            data=p.read_bytes();name=NAME+'/'+p.relative_to(staging).as_posix()
            item=zipfile.ZipInfo(name);item.compress_type=zipfile.ZIP_STORED if p.name.endswith(('.tar.gz','.png','.docx')) else zipfile.ZIP_DEFLATED
            item.create_system=3;item.external_attr=(0o100755 if data.startswith(b'#!') or p.suffix=='.sh' else 0o100644)<<16
            z.writestr(item,data)
    # Extract independently and verify the exact archive bytes and local PDS
    # preparation. This never calls PDS, the serial backend or JTAG.
    dest=AUDIT/'unpacked'
    with zipfile.ZipFile(ARCHIVE) as z:
        for row in metadata['files']:
            data=z.read(NAME+'/'+row['path']);assert len(data)==row['bytes'] and digest(data)==row['sha256']
        assert len(z.infolist())==len(entries)+1
        z.extractall(dest)
    checked=dest/NAME
    with (AUDIT/'verification.log').open('xb') as log:
        for args in ([sys.executable,'-B',str(checked/'verify_sources.py')],
                     [sys.executable,'-B',str(checked/'rebuild_fpga.py'),'--prepare-only','--output','fpga_prepare_check']):
            subprocess.run(args,cwd=checked,stdout=log,stderr=subprocess.STDOUT,check=True)
    assert sha(F/'FREEZE_MANIFEST.json')==FREEZE_SHA
    result={'archive':str(ARCHIVE),'sha256':sha(ARCHIVE),'bytes':ARCHIVE.stat().st_size,'files_verified':len(entries),
            'pds_inputs_verified':145,'ordered_hdl_sources':136,'source_only':True,'includes_architecture_report':True,
            'actual_runtime_sources_exported':len(runtime_rows),'dts_properties_preserved':count,
            'unpacked_source_verification_passed':True,'pds_prepare_only_passed':True,
            'linux_upstream_source_archive_included':False,'runtime_images_included':False,
            'sealed_source_unchanged':True,'native_pds_or_hardware_launched':False,'audit':str(AUDIT)}
    write_new(AUDIT/'result.json',(json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode())
    write_new(ARCHIVE.with_suffix('.zip.sha256'),(result['sha256']+'  '+ARCHIVE.name+'\n').encode())
    print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
