"""Build Graph204 CMOS2 v1/v2 frame-pipeline candidate from source.

Run under WSL/Linux with the RV32 GCC toolchain. The staged RTL, board
wrappers/constraints, and vendor IP manifest contents participate in the
16-hex build identity, including the external memory path absent from the
SoC-only sources_pango.f list.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import subprocess

ROOT=Path(__file__).resolve().parent
CPU_HZ=70000000
NPU_HZ=100000000


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    tool=parser.add_mutually_exclusive_group(required=True)
    tool.add_argument('--toolchain-bin',type=Path)
    tool.add_argument('--compiler',type=Path,help='Explicit GCC executable; output remains RV32IM/Zicsr ILP32')
    parser.add_argument('--legacy-isa-spelling',action='store_true',
        help='GCC10 and older name the pre-split CSR-capable ISA rv32im; do not use with current GCC')
    args=parser.parse_args()
    stage=args.stage.resolve();out=args.out.resolve()
    cfg=json.loads((stage/'board/clock_config.json').read_text())
    if (cfg['cpu_clock_hz'],cfg['npu_clock_hz'])!=(CPU_HZ,NPU_HZ):raise ValueError('Clock identity mismatch')
    if 'soc_cpu70_pll_probe u_cpu_pll' not in (stage/'board/soc_board_camera_top.sv').read_text():raise ValueError('CPU70 PLL is not bound')
    out.mkdir(parents=True,exist_ok=False)
    cc=args.compiler.resolve() if args.compiler else args.toolchain_bin.resolve()/'riscv32-unknown-elf-gcc'
    if not cc.is_file():raise FileNotFoundError(cc)
    src=ROOT/'firmware_displayready_src'
    source_files=[src/x for x in ('main.c','preprocess_rgb565.c','preprocess320_i8.c','conv2d_int8.c',
        'requant_i32_i8.c','tensor_ops_int8.c','yolov5_postprocess.c',
        'preprocess5mp_v2.c','display_resize.c','display_cmos2.c','memory_helpers.c')]
    header_files=list(src.glob('*.h'))
    port=ROOT/'reference/v15/sw/coremark/port'
    stage_names=[x.strip() for x in (stage/'sources_pango.f').read_text().splitlines()
                 if x.strip()]
    stage_files=[stage/x for x in stage_names]
    board_files=sorted(path for path in (stage/'board').rglob('*')
                       if path.is_file() and path.suffix in
                       {'.sv','.v','.fdc','.f','.json','.py'})
    vendor_list=stage/'board/vendor_sources.f'
    vendor_files=[stage/line.strip() for line in vendor_list.read_text().splitlines()
                  if line.strip() and not line.lstrip().startswith('#')]
    stage_files += board_files+vendor_files+[stage/'ipcore/soc_cpu100_pll_probe/soc_cpu100_pll_probe.v',
        stage/'ipcore/soc_cpu70_pll_probe/soc_cpu70_pll_probe.v',stage/'sources_pango.f',
        stage/'ipcore/soc_ddr800/pnr/soc_ddr800.rcf']
    all_files=list(dict.fromkeys(source_files+header_files+
               [port/'start.S',port/'link.ld',Path(__file__).resolve()]+stage_files))
    hashes={('stage/' + str(path.relative_to(stage)).replace('\\','/')
             if path.is_relative_to(stage) else
             str(path.relative_to(ROOT)).replace('\\','/')):sha(path)
            for path in all_files}
    compiler_hash=sha(cc)
    compiler_version=subprocess.check_output([str(cc),'--version'],text=True).splitlines()[0]
    march='rv32im' if args.legacy_isa_spelling else 'rv32im_zicsr'
    identity=dict(cpu_clock_hz=CPU_HZ,npu_clock_hz=NPU_HZ,source_sha256=hashes,
                  compiler_sha256=compiler_hash,compiler_isa_spelling=march,
                  abi='ilp32',optimization='control-and-software-fallbacks-Os;yolov5-postprocess-and-requant-O2;function-sections;gc-sections')
    build_id=hashlib.sha256(json.dumps(identity,sort_keys=True).encode()).hexdigest()[:16]
    common=[str(cc),'-march='+march,'-mabi=ilp32',
        '-ffreestanding','-fno-builtin','-fno-common','-fno-pic','-mno-relax',
        '-ffunction-sections',
        '-mcmodel=medany','-msmall-data-limit=0','-Wall','-Wextra','-Werror',
        '-DBOARD_BUILD_ID="'+build_id+'"',f'-DBOARD_CPU_HZ={CPU_HZ}u',
        f'-DBOARD_CPU_HZ_TEXT="{CPU_HZ}"',f'-DBOARD_NPU_HZ={NPU_HZ}u']
    objects=[];commands=[];output=[]
    for file in [port/'start.S']+source_files:
        obj=out/(file.stem+'.o')
        # Live tensor arithmetic is hardware. Keep CPU NMS at its original O2
        # tier; size-optimize control and retained legacy software fallbacks.
        # Full graph and fallback unit checks still require bit-exact results.
        opt='-O2' if file.name in ('yolov5_postprocess.c','requant_i32_i8.c') else '-Os'
        cmd=[*common,opt,'-c',str(file),'-o',str(obj)]
        r=subprocess.run(cmd,capture_output=True,text=True)
        output.append(f'$ {" ".join(cmd)}\n'+r.stdout+r.stderr)
        (out/'build.log').write_text('\n'.join(output))
        if r.returncode:print(r.stderr,flush=True)
        r.check_returncode()
        objects.append(str(obj));commands.append(cmd)
    command=[*common,'-O2','-nostdlib','-nostartfiles',
        '-T'+str(port/'link.ld'),'-Wl,--build-id=none','-Wl,--gc-sections',
        '-Wl,-Map='+str(out/'monitor.map'),*objects,
        '-o',str(out/'monitor.elf')]
    process=subprocess.run(command,capture_output=True,text=True)
    output.append(f'$ {" ".join(command)}\n'+process.stdout+process.stderr)
    (out/'build.log').write_text('\n'.join(output))
    process.check_returncode()
    helper=ROOT/'reference/v15/scripts/build-coremark-image.py'
    spec=importlib.util.spec_from_file_location('elf_helper',helper)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    entry,segments=module.parse_load_segments(out/'monitor.elf')
    if entry!=0x10000000:raise ValueError('Unexpected RV32 reset entry')
    for name,base in (('itcm',0x10000000),('dtcm',0x20000000)):
        module.write_mem(out/f'coremark-{name}.mem',
                         module.materialize_region(segments,base,65536,name))
    record=dict(type='BOARD_CMOS2_GRAPH_EXECUTOR_CANDIDATE_NOT_ROUTED',
        startup_diagnostics_enabled=True,
        scope='Candidate21 live mode compiles the validated Graph204 once per ARM into on-chip GRAPH_EXECUTOR1 command RAM. Hardware dispatches all Conv/S3/Concat/shared-tensor nodes; CPU runs a cooperative capture/preprocess/graph/NMS frame state machine. The existing three-slot raw pool and independent preview remain active across inference completions. Normal frames do not drain preview or wait for HDMI; explicit STOP finishes the current graph and drains preview. Legacy non-live paths retain software graph dispatch. Hardware trace bit29 marks graph-executor records; unavailable per-node NPU active/DMA counters remain zero. Requires independent full-graph, PDS 2025.2 timing and board qualification; board testing is explicitly deferred.',
        build_id=build_id,cpu_clock_hz=CPU_HZ,npu_clock_hz=NPU_HZ,stage=str(stage),
        source_sha256=hashes,compiler_sha256=compiler_hash,
        compiler_version=compiler_version,compiler_isa_spelling=march,
        command=command,compile_commands=commands,entry=hex(entry),
        image_sha256={path.name:sha(path) for path in out.glob('*.mem')})
    (out/'manifest.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(dict(build_id=build_id,stage=str(stage),
                          image_sha256=record['image_sha256']),indent=2))


if __name__=='__main__':
    main()
