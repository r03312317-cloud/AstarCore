"""Rebuild this exact candidate from local inputs; never accesses serial or JTAG."""
import argparse,hashlib,importlib.util,json,re,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parent
TOP='soc_linux_gui_top'

def check_ports(h,impl):
    def sections(path):
        data=path.read_text(encoding='utf-8',errors='replace')
        return {m[1]:sorted(x.strip() for x in m[2].splitlines() if x.strip()) for m in
                re.finditer(r"(?ms)^Port 'p:([^']+)':\s*\n(.*?)(?=\n\s*\n|\Z)",data)}
    ref=sections(ROOT/'provenance/physical_port_reference.txt')
    actual=sections(impl/'project/prj_tasks/pnr_1/place_route/ports_defalut_attribute.txt')
    names=sorted(x for x in actual if x.startswith(('mem_','tmds_')))
    differences={x:{'current':actual[x],'reference':ref.get(x)} for x in names if actual[x]!=ref.get(x)}
    result={'passed':len([x for x in names if x.startswith('mem_')])==71 and
             len([x for x in names if x.startswith('tmds_')])==8 and not differences,
            'compared_ports':len(names),'differences':differences,
            'scope':'Default IO attribute comparison; not board timing or signal integrity'}
    h.save(h.OUT/'port_default_audit.json',result)
    if not result['passed']:raise ValueError('Physical port reference mismatch')

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',default='fpga_rebuild_02')
    ap.add_argument('--prepare-only',action='store_true',help='Check inputs and generate local Tcl without running PDS')
    ap.add_argument('--pds',default='D:/PDS_2025.2-ads-win64/pango/PDS_2025.2-ads/bin/pds_shell.exe')
    ap.add_argument('--license',default='D:/PDS_2025.2-ads-win64/licences/new_pds_F4A80DA47D72.lic')
    args=ap.parse_args()
    out=(ROOT/args.output).resolve()
    if not out.is_relative_to(ROOT.resolve()) or out==ROOT.resolve() or out.exists():
        raise SystemExit('Choose a new build directory inside this workspace')
    spec=importlib.util.spec_from_file_location('local_pds_helpers',ROOT/'tools/pds_helpers.py')
    h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
    h.OUT=out;h.ROOT=out/'snapshot';h.PDS=Path(args.pds);h.LICENSE=Path(args.license)
    manifest=json.loads((ROOT/'source_manifest.json').read_text(encoding='utf-8'))
    for name,digest in manifest['files_sha256'].items():
        p=(ROOT/name).resolve()
        if not p.is_relative_to(ROOT.resolve()) or hashlib.sha256(p.read_bytes()).hexdigest()!=digest:
            raise ValueError('Source differs from verified candidate: '+name)
    if not args.prepare_only and (not h.PDS.is_file() or not h.LICENSE.is_file()):
        raise SystemExit('PDS executable or license unavailable; specify --pds and --license')
    out.mkdir(parents=True)
    for name in manifest['files_sha256']:
        target=h.ROOT/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,target)
    h.save(out/'inputs_manifest.json',manifest)
    syn=out/'synth';syn.mkdir()
    impl=out/'impl';(impl/'inputs').mkdir(parents=True)
    synth_tcl=syn/'synth.tcl'
    h.write(synth_tcl,h.source_script(syn/'project/core01_linux.pds',manifest,'synthesize','CORE01_LINUX_SYNTH_COMPLETE'))
    for stage in ('map','place','route','bitstream'):
        text=(ROOT/f'tools/pds_templates/run_{stage}.tcl').read_text(encoding='utf-8')
        if '@IMPL@' not in text:raise ValueError('Missing build template token')
        h.write(impl/f'run_{stage}.tcl',text.replace('@IMPL@',impl.as_posix()))
    for source,dest in ((h.ROOT/'inputs/gui/soc_linux_gui.fdc','soc_linux_gui.fdc'),
                         (h.ROOT/'inputs/ipcore/soc_ddr800/pnr/soc_ddr800.rcf','soc_ddr800.rcf')):
        shutil.copyfile(source,impl/'inputs'/dest)
    h.verify_inputs(manifest)
    if args.prepare_only:
        print('Verified',len(manifest['files_sha256']),'files;',len(manifest['source_order']),'ordered sources; prepared',out)
        return
    adf=syn/f'project/prj_tasks/syn_1/synthesize/{TOP}_syn.adf'
    h.run('synth',synth_tcl,'CORE01_LINUX_SYNTH_COMPLETE',adf,manifest)
    h.save(out/'netlist_audit.json',h.check_netlist(adf.with_suffix('.vm')))
    shutil.copyfile(adf,impl/'inputs/design_syn.adf')
    outputs={'map':f'device_map/{TOP}_map.adf','place':f'place_route/{TOP}_plc.adf',
             'route':f'place_route/{TOP}_pnr.adf','bitstream':f'generate_bitstream/{TOP}.sbit'}
    for stage in outputs:
        if stage=='bitstream':check_ports(h,impl);h.check_timing(impl)
        h.run(stage,impl/f'run_{stage}.tcl','LINUX_GUI_NATIVE_'+stage.upper()+'_COMPLETE',
              impl/'project/prj_tasks/pnr_1'/outputs[stage],manifest)

if __name__=='__main__':main()
