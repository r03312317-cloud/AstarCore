"""Compile, route and build the compact GUI bitstream without board access."""
import hashlib
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OLD = ROOT.parent / 'linux_uart_hdmi_demo_20261031_01'
OUT = ROOT / 'pds_build_01'
PDS = Path('D:/PDS_2025.2-ads-win64/pango/PDS_2025.2-ads/bin/pds_shell.exe')
LICENSE = Path('D:/PDS_2025.2-ads-win64/licences/new_pds_F4A80DA47D72.lic')
TOP = 'soc_linux_gui_top'


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def save(path, obj):
    with path.open('x', encoding='utf-8') as f:
        json.dump(obj, f, indent=2)
        f.write('\n')


def tcl(path):
    text = path.resolve().as_posix()
    if any(c in text for c in '{}\r\n'):
        raise ValueError('Unsupported Tcl path: ' + text)
    return '{' + text + '}'


def write(path, content):
    with path.open('x', encoding='utf-8', newline='\n') as f:
        f.write(content)


def verify_inputs(manifest):
    changed = [name for name, digest in manifest['files_sha256'].items()
               if not (ROOT / name).is_file() or sha(ROOT / name) != digest]
    if changed:
        raise ValueError('Frozen candidate inputs changed: ' + repr(changed[:8]))


def run(stage, script, marker, output, manifest):
    verify_inputs(manifest)
    env = dict(os.environ, PANGO_LICENSE_FILE=str(LICENSE), TEMP=str(OUT), TMP=str(OUT))
    logpath = OUT / (stage + '.log')
    start = time.monotonic()
    print('PDS', stage, 'started;', logpath, flush=True)
    with logpath.open('xb') as log:
        process = subprocess.Popen([str(PDS), '-file', str(script), '-work_dir', str(OUT)],
                                   cwd=OUT, env=env, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        code = process.wait()
    data = logpath.read_text(encoding='utf-8', errors='replace')
    errors = re.findall(r'(?m)^\s*(?:E:|ERROR\b|FATAL\b)[^\r\n]*', data)
    verify_inputs(manifest)
    completed = code == 0 and not errors and marker in data and (output is None or output.is_file())
    result = {'completed': completed, 'exit_code': code, 'marker': marker in data,
              'native_errors': errors[:30], 'seconds': time.monotonic() - start,
              'output': str(output) if output else None,
              'output_sha256': sha(output) if output and output.is_file() else None,
              'log_sha256': sha(logpath), 'board_access': False}
    save(OUT / (stage + '_result.json'), result)
    print('PDS', stage, 'completed:', completed, '%.1fs' % result['seconds'], flush=True)
    if not completed:
        raise RuntimeError('PDS ' + stage + ' failed; inspect ' + str(logpath))


def source_script(project, manifest, action, marker):
    lines = ['create_project ' + tcl(project) + ' -project_type rtl -syn_tool ads -force -in_process',
             'set_option -options {max_threads 2 max_parallel_jobs 1} [current_project]']
    lines += ['add_design ' + tcl(ROOT / name) + ' -library work' for name in manifest['source_order']]
    lines += ['add_constraint ' + tcl(ROOT / 'inputs/gui/soc_linux_gui.fdc'),
              'add_constraint ' + tcl(ROOT / 'inputs/ipcore/soc_ddr800/pnr/soc_ddr800.rcf'),
              'set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676',
              'set_option -options {top_module soc_linux_gui_top verilog_standard SystemVerilog} [get_filesets design_1]',
              'launch_tasks [get_tasks {syn_1}] -to_action ' + action,
              'wait_on_tasks [get_tasks {syn_1}] -to_action ' + action,
              'puts "' + marker + '"']
    return '\n'.join(lines) + '\n'


def check_netlist(path):
    data = path.read_text(encoding='utf-8', errors='replace')
    if data.count('PAP_ASYNC_REG="TRUE"') < 30:
        raise ValueError('Insufficient preserved async synchronizer attributes')
    if data.count('\\rx_sync[0] ') != 2 or data.count('\\rx_sync[1] ') != 2:
        raise ValueError('UART synchronizer chains missing')
    if not re.search(r'\bsoc_video_serial_reset\w*\s+u_serial_control\s*\(', data):
        raise ValueError('Serial reset synchronizer missing')
    for bit in range(4):
        if not re.search(r'PAP_PRESERVE="TRUE"[^\n]*\\local_reset\[' + str(bit) + r'\]', data):
            raise ValueError('Missing local DDR reset register ' + str(bit))
    return {'async_reg_attributes': data.count('PAP_ASYNC_REG="TRUE"'),
            'uart_synchronizers': 2, 'local_reset_registers': 4, 'serial_reset_preserved': True}


def check_ports(impl):
    def sections(path):
        text = path.read_text(encoding='utf-8', errors='replace')
        return {m.group(1): sorted(x.strip() for x in m.group(2).splitlines() if x.strip())
                for m in re.finditer(r"(?ms)^Port 'p:([^']+)':\s*\n(.*?)(?=\n\s*\n|\Z)", text)}
    current_path = impl / 'project/prj_tasks/pnr_1/place_route/ports_defalut_attribute.txt'
    reference_path = OLD / 'pds_impl_03/project/prj_tasks/pnr_1/place_route/ports_defalut_attribute.txt'
    current, reference = sections(current_path), sections(reference_path)
    names = sorted(x for x in current if x.startswith(('mem_', 'tmds_')))
    different = {x: {'current': current[x], 'reference': reference.get(x)}
                 for x in names if current[x] != reference.get(x)}
    result = {'passed': len([x for x in names if x.startswith('mem_')]) == 71 and
                        len([x for x in names if x.startswith('tmds_')]) == 8 and not different,
              'compared_ports': len(names), 'differences': different,
              'scope': 'Default IO attribute comparison; not board timing or signal integrity'}
    save(OUT / 'port_default_audit.json', result)
    if not result['passed']:
        raise ValueError('Default DDR or HDMI port attributes differ from prior board candidate')


def check_timing(impl):
    base = impl / 'project/prj_tasks/pnr_1/report_timing'
    report = base / (TOP + '.rtr')
    data = report.read_text(encoding='utf-8', errors='replace')
    warnings = (base / 'run.log').read_text(encoding='utf-8', errors='replace')
    exception = (base / (TOP + '_exception.rtr')).read_text(encoding='utf-8', errors='replace')
    sections = {}
    for kind in ('Setup', 'Hold'):
        for corner in ('Slow', 'Fast'):
            key = f'{kind} Summary({corner} Corner):'
            if key not in data:
                continue
            body = data.split(key, 1)[1].split('====', 1)[0]
            rows = re.findall(r'^\s*(\S+)\s+(\S+)\s+([-\d.]+)\s+([-\d.]+)\s+(\d+)\s+(\d+)\s*$', body, re.M)
            sections[key] = [{'source': a, 'destination': b, 'failing_endpoints': int(e), 'endpoints': int(f)}
                             for a, b, _c, _d, e, f in rows]
    performance = {}
    clocks = ('sys_clk', 'ddrphy_sysclk', 'hdmi_pixel_clk', 'hdmi_serial_clk')
    for clock in clocks:
        m = re.search(r'^\s*' + re.escape(clock) + r'\s+([\d.]+) MHz\s+([\d.]+) MHz\s+([\d.]+)\s+([\d.]+)\s+([-\d.]+)', data, re.M)
        if m:
            performance[clock] = dict(zip(('requested_mhz', 'estimated_mhz', 'period_ns', 'estimated_period_ns', 'setup_slack_ns'), map(float, m.groups())))
    exceptions = [s for s in re.split(r'(?=\| Exception type\s+:)', exception) if s.startswith('| Exception type  : set_max_delay')]
    crossing = bool(re.search(r'Startpoint\s*:\s*ddr_ready_mem/[^\r\n]*\nEndpoint\s*:\s*u_serial_control/ready_meta/[^\r\n]*', '\n'.join(exceptions)))
    unconstrained = sorted(set(re.findall(r"Timing-408[67]: Port '([^']+)' is not constrained", warnings)))
    result = {'report_sha256': sha(report), 'multi_corner': 'Timing analysis mode : multi corner' in data,
              'all_constraints_met': 'Design Summary : All Constraints Met.' in data,
              'ddr_to_serial_crossing_reported': crossing, 'performance': performance,
              'summaries': sections, 'unconstrained_ports': unconstrained,
              'ddr_unconstrained_count': sum(x.startswith('mem_') for x in unconstrained),
              'hdmi_unconstrained_count': sum(x.startswith('tmds_') for x in unconstrained),
              'scope': 'Internal reported timing; DDR/HDMI external IO timing and board behavior remain unverified'}
    required_sections = ('Setup Summary(Slow Corner):', 'Hold Summary(Fast Corner):')
    valid = result['multi_corner'] and result['all_constraints_met'] and crossing and len(performance) == len(clocks)
    for key in required_sections:
        rows = sections.get(key, [])
        valid = valid and bool(rows) and all(x['failing_endpoints'] == 0 for x in rows)
        for clock in ('sys_clk', 'ddrphy_sysclk', 'hdmi_pixel_clk'):
            valid = valid and any(x['source'] == clock and x['destination'] == clock and x['endpoints'] > 0 for x in rows)
    result['passed'] = bool(valid)
    save(OUT / 'timing_audit.json', result)
    if not valid:
        raise ValueError('PDS timing audit failed; inspect timing_audit.json')


def main():
    if OUT.exists():
        raise SystemExit('Refusing to overwrite PDS evidence')
    if not PDS.is_file() or not LICENSE.is_file():
        raise SystemExit('PDS executable or configured license is unavailable')
    for log, marker in (('sim_scaled_01/latency32.log', 'PASS scaled 480p'),
                        ('sim_scaled_01/latency64.log', 'PASS scaled 480p'),
                        ('sim_scaled_01/latency80.log', 'PASS scaled 480p'),
                        ('sim_scaled_01/ownership64.log', 'PASS full 480p RAM ownership'),
                        ('sim_commit_01/result.log', 'PASS asynchronous vblank commit')):
        if marker not in (ROOT / log).read_text(encoding='utf-8'):
            raise ValueError('Required simulation missing: ' + log)
    base = json.loads((ROOT / 'base_compile_manifest.json').read_text(encoding='utf-8'))
    actual = {name: sha(ROOT / name) for name in base['files_sha256']}
    changed = sorted(name for name, digest in actual.items() if digest != base['files_sha256'][name])
    expected = sorted(['inputs/gui/rv32_framebuffer_scanout_128.sv', 'inputs/gui/soc_linux_gui_top.sv'])
    if changed != expected:
        raise ValueError('Unexpected changed frozen source list: ' + repr(changed))
    manifest = {'source_count': base['source_count'], 'source_order': base['source_order'],
                'files_sha256': actual, 'changed_from_board_version': changed,
                'pds_sha256': sha(PDS), 'board_access': False}
    OUT.mkdir()
    save(OUT / 'inputs_manifest.json', manifest)
    comp = OUT / 'compile'; syn = OUT / 'synth'; impl = OUT / 'impl'
    comp.mkdir(); syn.mkdir(); impl.mkdir()
    compile_script = comp / 'compile.tcl'
    synth_script = syn / 'synth.tcl'
    write(compile_script, source_script(comp / 'project/gui27.pds', manifest, 'compile', 'COMPACT_COMPILE_COMPLETE'))
    write(synth_script, source_script(syn / 'project/gui27.pds', manifest, 'synthesize', 'COMPACT_SYNTH_COMPLETE'))
    run('compile', compile_script, 'COMPACT_COMPILE_COMPLETE', comp / 'project/gui27.pds', manifest)
    adf = syn / ('project/prj_tasks/syn_1/synthesize/' + TOP + '_syn.adf')
    run('synth', synth_script, 'COMPACT_SYNTH_COMPLETE', adf, manifest)
    save(OUT / 'netlist_audit.json', check_netlist(adf.with_suffix('.vm')))
    (impl / 'inputs').mkdir()
    for src, name in ((adf, 'design_syn.adf'),
                      (ROOT / 'inputs/gui/soc_linux_gui.fdc', 'soc_linux_gui.fdc'),
                      (ROOT / 'inputs/ipcore/soc_ddr800/pnr/soc_ddr800.rcf', 'soc_ddr800.rcf')):
        shutil.copyfile(src, impl / 'inputs' / name)
        if sha(src) != sha(impl / 'inputs' / name):
            raise ValueError('Implementation input copy hash mismatch: ' + name)
    outputs = {'map': impl / ('project/prj_tasks/pnr_1/device_map/' + TOP + '_map.adf'),
               'place': impl / ('project/prj_tasks/pnr_1/place_route/' + TOP + '_plc.adf'),
               'route': impl / ('project/prj_tasks/pnr_1/place_route/' + TOP + '_pnr.adf'),
               'bitstream': impl / ('project/prj_tasks/pnr_1/generate_bitstream/' + TOP + '.sbit')}
    old_impl = (OLD / 'pds_impl_03').as_posix()
    for stage in ('map', 'place', 'route', 'bitstream'):
        if stage == 'bitstream':
            check_ports(impl)
            check_timing(impl)
        content = (OLD / ('pds_impl_03/run_' + stage + '.tcl')).read_text(encoding='utf-8')
        if old_impl not in content:
            raise ValueError('Unexpected implementation Tcl template ' + stage)
        content = content.replace(old_impl, impl.as_posix())
        script = impl / ('run_' + stage + '.tcl')
        write(script, content)
        run(stage, script, 'LINUX_GUI_NATIVE_' + stage.upper() + '_COMPLETE', outputs[stage], manifest)
    print('PDS candidate bitstream:', outputs['bitstream'], flush=True)
    print('SHA256:', sha(outputs['bitstream']), flush=True)


if __name__ == '__main__':
    main()
