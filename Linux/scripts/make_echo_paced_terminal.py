#!/usr/bin/env python3
"""Generate external RX-only echo pacing; never edits guest/model/checkpoints."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
commands = ['uname -a', 'ps', 'ls -l /dev/fb0', 'echo RV32S',
            'gui-command status', 'sleep 1', 'gui-command settings', 'sleep 1',
            'gui-command home', 'echo RV32G']
def escaped(s):
    return s.replace('\\', '\\\\').replace('\t', '\\t').replace('\r', '\\r').replace('\n', '\\n')
stages = []
for trigger, line in [('rv32 login:', 'root')] + [('# ', c) for c in commands]:
    for char in line + '\n':
        stages.append((trigger, char))
        trigger = char
if len(stages) > 128:
    raise SystemExit('Too many terminal stages')
path = ROOT / 'sim/linux_echo_paced_commands.tsv'
path.write_text(''.join(escaped(t) + '\t' + escaped(p) + '\n' for t, p in stages))
print(f'Generated {path.name}: {len(stages)} one-character stages; ordinary root login then {len(commands)} shell lines')
