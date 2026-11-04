"""Build a new, separately named RV32 CoreMark serial-output firmware image."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
DESIGN_ID = json.loads((ROOT.parent / 'design_identity.json').read_text(encoding='utf-8'))['build_id']
FILES = ('core_list_join.c', 'core_main.c', 'core_matrix.c', 'core_state.c', 'core_util.c')
FLAGS = ['-O3', '-funroll-loops', '-funroll-all-loops', '-mbranch-cost=1', '--param', 'max-inline-insns-auto=200', '-march=rv32im_zicsr_zba_zbb_zbc_zbs', '-mabi=ilp32', '-mno-relax', '-ffreestanding', '-fno-builtin', '-fno-common', '-fno-pic', '-fno-stack-protector', '-nostdlib', '-static', '-mrelax', '-mtune=sifive-7-series', '-falign-functions=32', '-falign-loops=4', '-falign-jumps=4', '-falign-labels=4', '-mbranch-cost=2', '-mbranch-cost=1', '-msmall-data-limit=16', '-O2', '--param=max-inline-insns-auto=80', '-falign-jumps=8', '-falign-functions=16']

parser = argparse.ArgumentParser()
parser.add_argument('--mode', choices=['performance', 'validation'], required=True)
parser.add_argument('--iterations', type=int, required=True)
parser.add_argument('--clock-hz', type=int, required=True)
parser.add_argument('--name', required=True)
parser.add_argument('--legacy-isa', action='store_true')
args = parser.parse_args()
if args.legacy_isa:
    FLAGS = [x.replace('_zbb_zbc_zbs','_zbb_zbs') for x in FLAGS]
if args.iterations <= 0 or args.clock_hz <= 0 or not args.name.replace('_', '').isalnum():
    raise SystemExit('Invalid iterations, clock, or output name')
out = ROOT / 'builds' / args.name
out.mkdir(parents=True, exist_ok=False)
gcc = shutil.which('riscv-none-elf-gcc')
if not gcc:
    raise SystemExit('riscv-none-elf-gcc was not found')
tool = Path(gcc)
prefix = tool.name.lower().removesuffix('.exe').removesuffix('gcc')
objcopy = str(tool.with_name(prefix + 'objcopy.exe'))
size = str(tool.with_name(prefix + 'size.exe'))
compiler = subprocess.check_output([gcc, '--version'], text=True).splitlines()[0]
defines = {'ITERATIONS': args.iterations, 'CPU_HZ': args.clock_hz,
           'TIMER_HZ': args.clock_hz, 'MMIO_BASE': 0x30000000,
           'TOTAL_DATA_SIZE': 2000, 'PERFORMANCE_RUN': int(args.mode == 'performance'),
           'VALIDATION_RUN': int(args.mode == 'validation'), 'PROFILE_RUN': 0,
           'PRINT_DERIVED_SCORES': 1}
strings = {'BUILD_ID': DESIGN_ID, 'FLAGS_STR': ' '.join(FLAGS),
           'COMPILER_VERSION': compiler,
           'MEMORY_DESCRIPTION': '64KiB SRAM; I16KiB/2way; D8KiB/2way               ',
           'CPU_DESCRIPTION': 'RV32 RV32 130 H12/I12 RV32IM_Zicsr_Zba_Zbb_Zbc_Zbs'}
header = ''.join(f'#define {k} {v}\n' for k, v in defines.items())
header += ''.join(f'#define {k} {json.dumps(v)}\n' for k, v in strings.items())
(out / 'build_config.h').write_text(header, encoding='utf-8')
src = ROOT / 'src'
cmd = [gcc, *FLAGS, '-include', str(out / 'build_config.h'),
       '-I' + str(src / 'platform'), '-I' + str(src / 'coremark'),
       *[str(src / 'coremark' / n) for n in FILES],
       str(src / 'platform/core_portme.c'), str(src / 'platform/runtime.c'),
       str(src / 'platform/start.S'), '-T' + str(ROOT / 'link.ld'),
       '-Wl,-Map,' + str(out / 'firmware.map'), '-lgcc', '-o', str(out / 'firmware.elf')]
(out / 'build_plan.json').write_text(json.dumps({'command': cmd, 'mode': args.mode,
    'iterations': args.iterations, 'clock_hz': args.clock_hz, 'compiler': compiler},
    indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
with (out / 'build.log').open('wb') as log:
    subprocess.run(cmd, cwd=out, stdout=log, stderr=subprocess.STDOUT, check=True)
subprocess.run([objcopy, '-O', 'binary', str(out / 'firmware.elf'), str(out / 'firmware.bin')], check=True)
with (out / 'size.txt').open('wb') as report:
    subprocess.run([size, str(out / 'firmware.elf')], stdout=report, check=True)
blob = (out / 'firmware.bin').read_bytes()
if len(blob) >= 65536 - 8192:
    raise SystemExit('Image leaves insufficient SRAM for the stack')
blob = blob.ljust(65536, b'\0')
(out / 'firmware.hex').write_text(''.join(f'{int.from_bytes(blob[i:i+8], "little"):016x}\n'
    for i in range(0, len(blob), 8)), encoding='ascii')
digests = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
           (out / 'firmware.elf', out / 'firmware.bin', out / 'firmware.hex')}
(out / 'sha256.json').write_text(json.dumps(digests, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'output': str(out), 'mode': args.mode, 'iterations': args.iterations,
                  'clock_hz': args.clock_hz, 'sha256': digests}, indent=2))
