from pathlib import Path
import subprocess,os,json,hashlib
r=Path(__file__).resolve().parents[1]
sources=sorted((r/'rtl').glob('*.v'))+[r/'board'/n for n in ['rv32_coremark_system_boot.v','rv32_board_memory.v','uart_loader.v']]
env=dict(os.environ,VERILATOR_ROOT='C:/tools/msys64/mingw64/share/verilator',TEMP=str(r/'verification/temp'),TMP=str(r/'verification/temp'))
(r/'verification/temp').mkdir(exist_ok=True)
cmd=['C:/tools/msys64/mingw64/bin/verilator_bin.exe','--lint-only','--assert','--unroll-count','1024','--unroll-stmts','100000','-Wno-fatal','--top-module','rv32_coremark_system_boot','-GUART_DIV=4','-GBOOT_TIMEOUT_CYCLES=8',*[str(p) for p in sources]]
(r/'verification/lint_command.json').write_text(json.dumps(cmd,indent=2))
with (r/'verification/verilator_lint.log').open('wb') as log:p=subprocess.run(cmd,cwd=r,env=env,stdout=log,stderr=subprocess.STDOUT)
s=(r/'verification/verilator_lint.log').read_text(errors='replace')
result={'exit_code':p.returncode,'error_lines':[x for x in s.splitlines() if x.startswith('%Error')],'warning_count':sum(x.startswith('%Warning') for x in s.splitlines()),'scope':'All 17 annotated architectural RTL files plus exact board-system/SRAM/loader; FPGA PLL/IO primitives are excluded from this functional-RTL lint.'}
import re,collections
original_cmd=[arg.replace(str(r/'rtl'),str(r/'original/rtl')).replace(str(r/'board'),str(r/'original/board')) for arg in cmd]
with (r/'verification/original_verilator_lint.log').open('wb') as log:original=subprocess.run(original_cmd,cwd=r,env=env,stdout=log,stderr=subprocess.STDOUT)
old=(r/'verification/original_verilator_lint.log').read_text(errors='replace')
categories=lambda text:dict(collections.Counter(re.findall(r'^%Warning-([^:]+):',text,re.M)))
result.update(original_exit_code=original.returncode,original_warning_categories=categories(old),annotated_warning_categories=categories(s),warning_categories_unchanged=categories(old)==categories(s))
(r/'verification/lint_result.json').write_text(json.dumps(result,indent=2));print(result)
assert p.returncode==0 and original.returncode==0 and not result['error_lines'] and result['warning_categories_unchanged']
