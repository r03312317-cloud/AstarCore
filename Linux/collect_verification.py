"""Collate original test evidence; retain failed setup attempts and raw logs."""
from pathlib import Path
import datetime,difflib,hashlib,json,re
R=Path(__file__).resolve().parent
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest()
def text(p):return (R/p).read_text(encoding='utf-8',errors='replace')
def load(p):return json.loads(text(p))
def save(p,obj):(R/p).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main():
    manifest=load('source_manifest.json')
    for name,digest in manifest['files_sha256'].items():
        assert sha(R/name)==digest,name
        assert sha(R/'fpga_build_01/snapshot'/name)==digest,name
    imported=load('provenance/import_result.json')
    sealed=Path(imported['source'])
    delta=[]
    for item in imported['files']:
        name=item['file'];original=R/'provenance/core01_original'/name
        assert sha(original)==item['sealed_sha256']
        assert sha(sealed/name)==item['sealed_sha256'],'Sealed source changed: '+name
        before=original.read_text().splitlines(True);after=(R/'rtl'/name).read_text().splitlines(True)
        patch=list(difflib.unified_diff(before,after))
        delta.append({'file':name,'sealed_sha256':sha(original),'adapted_sha256':sha(R/'rtl'/name),
                      'unchanged_after_newline_normalization':before==after,
                      'added_lines':sum(x.startswith('+') and not x.startswith('+++') for x in patch),
                      'removed_lines':sum(x.startswith('-') and not x.startswith('---') for x in patch)})
    for p in (R/'rtl').glob('*.v'):
        assert not re.search(r'(?m)^(<<<<<<<|=======|>>>>>>>)',p.read_text()),p
    source={'sealed_sources_verified':len(delta),'pds_inputs_verified':len(manifest['files_sha256']),
            'ordered_hdl_sources':len(manifest['source_order']),'modules':delta,
            'source_build_id':imported['source_build_id'],'source_directory_preserved':True}
    boot=R/'reports/compact_boot/run_01'
    simfiles=[]
    for line in (boot/'inputs.sha256').read_text().splitlines():
        digest,name=line.split('  ',1);p=R/name
        assert sha(p)==digest,'Boot input changed: '+name
        simfiles.append(name)
    source['boot_inputs_and_model_verified']=len(simfiles)
    tests=[]
    def require(name,path,needle):
        data=text(path)
        tests.append({'test':name,'passed':needle in data,'evidence':path,'marker':needle})
    require('privilege_M_S_U','reports/privilege/run.log','PRIVILEGE PASS checks=22')
    require('mip_seip','reports/mip_seip/run.log','MIP SEIP PASS checks=10')
    require('counter_access_matrix','reports/counter_matrix/run.log','COUNTER MATRIX PASS cases=1296 allowed=672 denied=624')
    require('sv32','reports/tool_recheck_02/sv32_tb_test.log','SV32 PASS checks=1557 PTW reads=3098')
    require('sv32_bridge','reports/sv32_bridge_test.log','PASS')
    require('sv32_cache_fence','reports/sv32_cache_fence_test.log','PASS')
    require('peripherals','reports/regression_01.log','PASS peripherals checks=2526')
    require('plic','reports/regression_01.log','PASS PLIC checks=1182')
    require('scanout','reports/regression_01.log','PASS scanout checks=3110407 reads=345600')
    require('scanout_fault_injection','reports/regression_01.log','PASS scanout fault checks=774 reads=65 bounds=2 underflow=16')
    require('atomic_directed','reports/regression_02.log','PASS atomic 20 checks writes=11')
    require('atomic_random_icarus','reports/regression_02.log','PASS atomic randomized checks=2541 reads=1928 writes=2079')
    require('atomic_aqrl_actual_core','reports/regression_02.log','PASS actual core atomic aqrl ordering retire_checks=5 physical_transactions=7')
    require('atomic_random_verilator','reports/tool_recheck_02/atomic_random_tb_test.log','PASS atomic randomized checks=2542 reads=1946 writes=2116')
    require('cpu_video_ownership','reports/regression_02.log','PASS CPU video ownership pixels=1843200 display_reads=230400 retired=535903')
    require('uart_pin_terminal','reports/regression_01.log','PASS UART terminal checks=1652174')
    require('uart_checkpoint','reports/regression_01.log','PASS UART checkpoint checks=803014')
    require('uart_echo_pacing','reports/regression_01.log','PASS echo pacing stages=125 pin_checks=6286344')
    require('host_utilities','reports/regression_01.log','PASS local utilities checks=10')
    capture=load('reports/uart_capture_checks/result.json')
    assert capture['passed']
    for row in capture['tests']:
        tests.append({'test':'raw_uart_'+row['test'],'passed':row['passed'],
                      'evidence':'reports/uart_capture_checks/'+row['test']+'/result.json'})
    for path in ('reports/lint_02.log','reports/soc_build.log','reports/uart_capture_build.log'):
        assert '%Error' not in text(path),path
    stages={stage:load('fpga_build_01/'+stage+'_result.json') for stage in ('synth','map','place','route','bitstream')}
    assert all(x['completed'] and not x['native_errors'] for x in stages.values())
    timing=load('fpga_build_01/timing_audit.json');ports=load('fpga_build_01/port_default_audit.json')
    assert timing['passed'] and ports['passed']
    bit=Path(stages['bitstream']['output'])
    assert sha(bit)==stages['bitstream']['output_sha256']
    report=text('fpga_build_01/impl/project/prj_tasks/pnr_1/report_timing/soc_linux_gui_top.rtr')
    holds=report.split('Hold Summary(Fast Corner):',1)[1].split('====',1)[0]
    hold=re.search(r'^\s*sys_clk\s+sys_clk\s+([\d.]+)',holds,re.M)
    resources=text('fpga_build_01/impl/project/prj_tasks/pnr_1/place_route/soc_linux_gui_top.ror')
    hierarchy={}
    for line in resources.splitlines():
        cells=[x.strip() for x in line.split('|')]
        if len(cells)>7 and cells[1] in ('soc_linux_gui_top','+ cpu(rv32_linux_soc_top)','+ processor(rv32_ooo_core)','+ cache(rv32_memory_system)'):
            hierarchy[cells[1]]={'lut_logical':int(cells[2]),'ff_logical':int(cells[3]),'distributed_ram':int(cells[4]),'apm':int(cells[5]),'drm':int(cells[6])}
    uart=(boot/'uart.log').read_text(errors='replace').replace('\r','')
    trace=(boot/'trace.log').read_text(errors='replace')
    counts={key:[int(x) for x in re.findall(r'^'+key+r'=(\d+)\s*$',uart,re.M)] for key in ('COUNT_A','COUNT_B','COUNT_STOP','COUNT_AFTER')}
    done=bool(re.search(r'^CORE01_LINUX_TEST_DONE\s*$',uart,re.M))
    errors=bool(re.search(r'Kernel panic|Unable to handle kernel|Oops:|BUG:|Counter did not stop|Segmentation fault|Bus error',uart))
    finish=re.search(r'LINUX_SCRIPT_COMPLETE cycles=(\d+) frames=(\d+) reads=(\d+) underflow=(\d+) dma_errors=(\d+) bounds_errors=(\d+)',trace)
    end=(boot/'exit_code.txt')
    final_exit=int(end.read_text().strip()) if end.exists() else None
    full_pass=done and not errors and bool(finish) and final_exit==0
    if full_pass:
        full_pass=(all(len(x)==1 for x in counts.values()) and
                   counts['COUNT_B'][0]>counts['COUNT_A'][0]>=0 and
                   counts['COUNT_STOP']==counts['COUNT_AFTER'] and counts['COUNT_STOP'][0]>=counts['COUNT_B'][0])
        full_pass=full_pass and bool(re.search(r'^PAGE_RC=0\s*$',uart,re.M)) and bool(re.search(r'^Linux rv32 6\.12\.9 .*riscv32',uart,re.M))
        full_pass=full_pass and int(finish[2])>0 and all(int(finish[x])==0 for x in (4,5,6))
    frames=[]
    for p in sorted((boot/'captures').glob('*.json')):
        m=json.loads(p.read_text())
        frames.append({'path':str(p.relative_to(R)),'frame_number':m['frame_number'],'cycle':m['cycle'],
                       'underflow_rows_delta':m['underflow_rows_delta'],'dma_errors_delta':m['dma_errors_delta'],
                       'bounds_errors_delta':m['bounds_errors_delta']})
    program_pass=bool(full_pass)
    selected_path=R/'reports/selected_captures.json'
    selected=json.loads(selected_path.read_text(encoding='utf-8')) if selected_path.exists() else {'reviewed':[]}
    reviewed={row['stage'] for row in selected['reviewed'] if row.get('complete')}
    visual_pass={'psplash','home','status','counter_running','counter_stopped'}.issubset(reviewed)
    full_pass=program_pass and visual_pass
    system={'state':'passed' if full_pass else ('awaiting_visual_review' if program_pass else ('failed' if final_exit is not None or errors else 'running')),
            'program_verification_passed':program_pass,'visual_scanout_review_passed':visual_pass,
            'reviewed_visual_stages':sorted(reviewed),
            'kernel_entered':'Linux version 6.12.9' in uart,'rootfs_unpack_started':'Unpacking initramfs...' in uart,
            'command_marker_seen':done,'counter_values':counts,'exit_code':final_exit,
            'finish_metrics':list(map(int,finish.groups())) if finish else None,'captures':frames,
            'physical_ddr_or_hdmi_validated':False,'board_access':False}
    result={'generated_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_identity':source,
            'directed_tests_passed':all(x['passed'] for x in tests),'directed_tests':tests,
            'pds_internal_timing_passed':timing['passed'],'pds_port_attributes_match':ports['passed'],
            'cpu_configured_mhz':27,'cpu_setup_slack_ns':timing['performance']['sys_clk']['setup_slack_ns'],
            'cpu_fast_hold_slack_ns':float(hold[1]),'bitstream':str(bit),'bitstream_sha256':sha(bit),
            'resources_hierarchical_logical':hierarchy,'linux_full_system':system,'board_validated':False,
            'all_offline_checks_passed':all(x['passed'] for x in tests) and full_pass}
    save('reports/offline_verification.json',result)
    print(json.dumps({k:result[k] for k in ('directed_tests_passed','pds_internal_timing_passed','cpu_setup_slack_ns','cpu_fast_hold_slack_ns','all_offline_checks_passed')},indent=2))
    print('Full Linux RTL:',system['state'])
    missing=[x for x in tests if not x['passed']]
    if missing:raise SystemExit('Missing test evidence: '+repr(missing))

if __name__=='__main__':main()
