"""Bind the unchanged, timed hardware image to the Mario test evidence."""
from pathlib import Path
import csv,hashlib,json,xml.etree.ElementTree as ET
from build_mario import ROOT
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,message):
 if not ok:raise RuntimeError(message)
def qualify():
 platform=ROOT/'platform';manifest=json.loads((platform/'manifest.json').read_text())
 for name,item in manifest['files'].items():require(sha(platform/name)==item['sha256'],'Platform artifact changed: '+name)
 origin=json.loads((platform/'qualification_origin.json').read_text())
 require(sha(platform/'game_board_top.sbit')==origin['sha256'],'Qualified bitstream mismatch')
 sources=json.loads((platform/'loader_source_sha256.json').read_text())
 hardware={name:digest for name,digest in sources.items() if name.startswith('rtl/') and not name.startswith('rtl/sim/')}
 require(bool(hardware),'No hardware source hashes')
 for name,digest in hardware.items():require(sha(ROOT/'soc'/name)==digest,'Hardware changed since PDS: '+name)
 cpu=json.loads((ROOT/'soc/docs/cpu_rv32_import_manifest.json').read_text())
 for name,digest in cpu['copied_cpu_sha256'].items():require(sha(ROOT/'soc/rtl/rv32/core'/name)==digest,'Selected CPU differs: '+name)
 timing={}
 for corner in ['fast','slow']:
  for kind in ['setup','hold','recovery','removal','mpw']:
   table=ET.parse(platform/'timing'/f'report_timing_{corner}_{kind}.db').getroot().find('table')
   require(table is not None,'Missing timing table');rows=[[d.text or '' for d in row.findall('data')] for row in table.findall('row')]
   require(bool(rows),'Empty timing report');sc,fc=(1,3) if kind=='mpw' else (2,4)
   slack=min(float(row[sc]) for row in rows);failed=sum(int(row[fc]) for row in rows)
   require(slack>=0 and failed==0,'Timing failure: '+corner+' '+kind);timing[corner+'_'+kind]={'worst_slack_ns':slack,'failing_endpoints':failed}
 check=ET.parse(platform/'timing/check_timing_summary.db').getroot().find('table')
 checks={r.findall('data')[0].text:r.findall('data')[1].text for r in check.findall('row') if len(r.findall('data'))>=2}
 require(checks.get('no_clock')=='0','Unassigned clocks')
 program=json.loads((ROOT/'build/LATEST_MARIO.json').read_text());host=json.loads((ROOT/'build/LATEST_HOST_GAMEPLAY.json').read_text());rtl=json.loads((ROOT/'build/LATEST_RTL.json').read_text())
 binary=ROOT/'build'/Path(program['binary']).parent.name/'mario.bin';build=binary.parent
 require(sha(binary)==program['binary_sha256']==rtl['program_sha256'],'Deployable firmware is not the RTL-tested image')
 for record in json.loads((build/'sources.json').read_text()):require(sha(ROOT/record['source'])==record['sha256'],'Firmware source changed: '+record['source'])
 for name,digest in json.loads((build/'input_sha256.json').read_text()).items():
  require(sha(ROOT/name)==digest,'Firmware input changed: '+name)
  require(sha(build/'source'/name)==digest,'Frozen firmware input changed: '+name)
 require(host['passed'] and rtl['passed'],'Mario verification incomplete')
 require(rtl.get('prefilled_front_frame_matches_reference') and len(rtl.get('nonzero_framebuffer_prefills',[]))==2,'Framebuffer visibility check incomplete')
 require(rtl.get('complete_hdmi_frames_presented',0)>0,'No complete HDMI frames in RTL evidence')
 proof=ROOT/'build'/Path(rtl['evidence']).name
 require(rtl.get('timer64_monotonic_across_low_word_rollover'),'RV32 cycle counter rollover not verified')
 require(sha(proof/'source/tests/entry_ddr.c')==rtl['timer_test_source_sha256'],'Timer test snapshot changed')
 require(not (proof/'ACCEPTANCE_REJECTED.json').exists(),'RTL run has a rejected acceptance audit')
 tested=json.loads((proof/'source_sha256.json').read_text())
 for name,digest in tested.items():
  require(sha(proof/'source'/name)==digest,'RTL evidence snapshot changed: '+name)
  if name.startswith('rtl/') and not name.startswith('rtl/sim/'):require(hardware.get(name)==digest,'PDS/RTL-test source mismatch: '+name)
 native=ROOT/'build'/Path(host['evidence']).name
 for name,digest in json.loads((native/'sources.json').read_text()).items():require(sha(ROOT/name)==digest,'Native-tested source changed: '+name)
 render=json.loads((ROOT/'build/LATEST_RENDER.json').read_text());require(render['passed'],'Incremental renderer verification incomplete')
 render_dir=ROOT/'build'/Path(render['evidence']).name
 for name,digest in json.loads((render_dir/'sources.json').read_text()).items():require(sha(ROOT/name)==digest,'Renderer-tested source changed: '+name)
 video=json.loads((ROOT/'build/LATEST_VIDEO_QUEUE.json').read_text())
 require(video['passed'] and video.get('accepted_error_bug_detected_by_negative_control'),'Async video ownership verification incomplete')
 video_dir=ROOT/'build'/Path(video['evidence']).name
 for name,digest in json.loads((video_dir/'sources.json').read_text()).items():require(sha(ROOT/name)==digest,'Video-driver tested source changed: '+name)
 row=list(csv.DictReader((native/'trace.csv').open()))[3]
 checkpoint=f"MARIO_CHECKPOINT RAM={int(row['ram_crc']):08x} PC={int(row['cpu_pc']):04x}"
 return {'bitstream':str(platform/'game_board_top.sbit'),'sha256':origin['sha256'],'stage2':str(platform/'stage2.bin'),'stage2_sha256':sha(platform/'stage2.bin'),'binary':str(binary),'binary_sha256':sha(binary),'expected_checkpoint':checkpoint,'cpu_hz':100000000,'cpu_files_verified':len(cpu['copied_cpu_sha256']),'hardware_files_verified':len(hardware),'timing':timing,'check_timing':checks,'native_gameplay_evidence':str(native),'renderer_evidence':str(render_dir),'video_queue_evidence':str(video_dir),'mario_rtl':rtl,'scope':'reused qualified hardware; first-four-frame Mario RTL, timer carry, native gameplay, double-buffer pixel and ownership tests; physical Mario acceptance still required'}
