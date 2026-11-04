"""Candidate-08 PDS2025 exclusive SRAM startup, DDR selftest and fixed-image replay.

No hardware is touched by --help. Physical execution requires the complete
FPSV2_08_BITGEN_V1 receipt and creates a new evidence directory. No Flash.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, math, msvcrt, re, shutil, socket, statistics, struct, subprocess, sys, time, traceback, zlib
from serial.tools import list_ports
from board_monitor import Monitor
from run_graph_package import validate_package
from make_cmos2_workflow_config import make, CONFIG_ADDRESS
from cmos2_protocol import decode, session_start, continuous_snapshot
from ddr_hdmi_protocol import decode_query, decode_profile
from rv32_performance_protocol import decode_cpu, decode_layers
from window_protocol import decode_window
from concat_protocol import decode_concat, graph_delta as concat_delta
from continuous_fps import measured_interval

ROOT=Path('D:/workspace/riscv-fpga-soc')
CANDIDATE=Path(__file__).resolve().parent.parent
NATIVE=None  # selected explicitly from the verified 08 receipt
FW=CANDIDATE/'fw_build_final'
MODEL=ROOT/'model/cmos2_concat_diag_eb1fbf30aa8f08e1_v1_20261003'
LOCK=ROOT/'docs/BOARD_RESOURCE.lock'
STATUS=ROOT/'docs/BOARD_RESOURCE_STATUS.md'
PDS=Path('D:/PDS_2025.2-ads-win64/pango/PDS_2025.2-ads/bin')
BUILD='bf14ac1a71cc694c'
MODEL_SHA='97da0db6ca09dfc726b6bb41e93cc9a5c7f0f4690f46502d43eb467f803b8a52'
CPU_HZ=70000000
MARKER='FINAL_INITIALIZED_BITSTREAM_COMPLETE'
PHASES={'synthesis':'FINAL_NATIVE_MAPPING_COMPLETE','placement':'FINAL_NATIVE_PLACEMENT_COMPLETE',
        'physical':'FINAL_NATIVE_ROUTE_COMPLETE','physical/fresh_sta':'FINAL_NATIVE_STA_COMPLETE'}

def require(condition, message):
 if not condition: raise ValueError(message)
def sha_bytes(data): return hashlib.sha256(data).hexdigest()
def sha_file(path):
 h=hashlib.sha256()
 with Path(path).open('rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 return h.hexdigest()
def utc(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def path_ref(item):
 require(isinstance(item,dict) and set(('path','sha256'))<=item.keys(),'invalid artifact reference')
 path=Path(item['path']).resolve(); digest=item['sha256']
 require(path.is_file() and isinstance(digest,str) and len(digest)==64,'missing artifact or malformed SHA')
 require(sha_file(path)==digest.lower(),f'artifact SHA mismatch: {path}')
 return path

def qualify(receipt_path,native_name):
 from pds25_guard import validate_receipt
 return validate_receipt(receipt_path,native_name)

def window_contract(assets,runs):
 """Derive 05 conv_service 64-row/page job and scratch-byte totals from descriptors."""
 result={'jobs':0,'hardware_layers':0,'direct_layers':0,'software_layers':0,'DDR_write_bytes':0};conv=0
 for run in runs:
  raw=assets[run['descriptor_asset']]['path'].read_bytes()
  for offset in range(0,len(raw),96):
   w=struct.unpack_from('<24I',raw,offset)
   if w[0]!=10:continue
   conv+=1;v=w[4:22];ih,iw,ic,oc,kh,kw,sh,sw,dh,dw,pt,pl,pb,pr,tile=v[3:18]
   require(all((ih,iw,ic,oc,kh,kw,sh,sw,dh,dw)) and tile==64,'invalid convolution shape in model')
   oh=(ih+pt+pb-((kh-1)*dh+1))//sh+1;ow=(iw+pl+pr-((kw-1)*dw+1))//sw+1;rows=oh*ow;k=kh*kw*ic
   require(oh>0 and ow>0 and 0<k<=1152 and rows<=65535,'unsupported conv-service geometry')
   direct=kh==kw==sh==sw==1 and pt==pl==pb==pr==0
   if direct:result['direct_layers']+=1;continue
   limit=256 if k<=512 else 224 if k<=576 else 192 if k<=682 else 160 if k<=818 else 128 if k<=1024 else 112
   pages=(oc+limit-1)//limit;result['hardware_layers']+=1;result['jobs']+=((rows+63)//64)*pages;result['DDR_write_bytes']+=rows*k*pages
 require(conv==60,'wrong convolution layer count')
 return result

def window_delta_05(before,after,expected,graphs=1):
 keys=('jobs','hardware_layers','direct_layers','software_layers','failures','CPU_wait_ticks','DDR_read_bytes','DDR_write_bytes','cache_hits','cache_misses','UI_active_cycles','UI_stall_cycles')
 delta={k:after[k]-before[k] for k in keys};require(all(v>=0 for v in delta.values()),'Window counters reset or wrapped')
 require(all(delta[k]==v*graphs for k,v in expected.items()),'05 descriptor-derived Window job/layer/byte counts differ')
 require(delta['failures']==0 and not after['timeout_latched'],'Window fault or timeout')
 delta.update(CPU_wait_seconds=delta['CPU_wait_ticks']/CPU_HZ,UI_active_seconds=delta['UI_active_cycles']/93750000,UI_stall_seconds=delta['UI_stall_cycles']/93750000,
  scope='Descriptor-derived GEX2 64-row conv-service counters; CPU70 and fabric93.75MHz intervals overlap')
 return delta

def concat_timing(delta):
 delta.update(CPU_wait_seconds=delta['CPU_wait_ticks']/CPU_HZ,UI_active_seconds=delta['UI_active_cycles']/93750000,UI_stall_seconds=delta['UI_stall_cycles']/93750000)
 return delta
def verify_models(model_root=MODEL):
 refroot=model_root/'MODEL_V1_REFERENCES.json'; allref=json.loads(refroot.read_text(encoding='utf-8'))
 require(allref['model_sha256']==MODEL_SHA,'reference model SHA differs')
 result={}
 for case in ('palm','empty'):
  folder=model_root/case; refpath=folder/'reference.json'; ref=json.loads(refpath.read_text(encoding='utf-8'))
  canonical=next((x for x in allref['frames'] if x['name']==case),None)
  require(ref==canonical,'reference does not match canonical metadata')
  compat=json.loads((folder/'package/MODEL_COMPAT.json').read_text(encoding='utf-8'))
  require(compat['frame_reference_sha256']==sha_file(refpath) and compat['model_sha256']==MODEL_SHA,'reference compatibility SHA mismatch')
  package=folder/'package/manifest.json'; m,assets,runs=validate_package(package)
  require(m['firmware_build_id']=='eb1fbf30aa8f08e1' and m['model_sha256']==MODEL_SHA and m['descriptors']==204 and sum(x['count'] for x in runs)==204 and m['ddr_high_watermark']<0x01000000,'historical package identity or low DDR watermark mismatch')
  for asset in assets.values():require(0x80000000<=asset['address'] and asset['address']+asset['bytes']<=0x84000000,'model asset outside S3 low 64 MiB')
  for run in runs:
   descriptor_bytes=assets[run['descriptor_asset']]['path'].read_bytes()
   for word, in struct.iter_unpack('<I',descriptor_bytes):require(not 0x84000000<=word<0x88000000,'descriptor contains address-like word in unsupported upper DDR aperture')
   require(0x80000000<=run['trace_base'] and run['trace_base']+run['count']*24<=0x84000000,'trace outside low 64 MiB')
   require(0x80000000<=run['final_output'] and run['final_output']+run['final_bytes']<=0x84000000,'output outside low 64 MiB')
  for key in ('frame','input','display'):
   f=(folder/Path(ref[key+'_file'].replace('\\','/')).name).resolve();require(f.parent==folder.resolve() and f.is_file() and f.stat().st_size==ref[key+'_bytes'] and sha_file(f)==ref[key+'_sha256'],f'{case} {key} golden mismatch')
  require(len(ref['heads'])==3 and {h['name'] for h in ref['heads']}=={h['name'] for h in m['model_outputs']},'head metadata mismatch')
  for head in ref['heads']:
   f=(folder/Path(head['file'].replace('\\','/')).name).resolve();require(f.parent==folder.resolve() and f.is_file() and f.stat().st_size==head['bytes'] and sha_file(f)==head['sha256'],'head golden mismatch')
  result[case]=dict(folder=folder,ref=ref,manifest=m,assets=assets,package=package,package_sha256=sha_file(package),reference_sha256=sha_file(refpath),window_expected=window_contract(assets,runs))
 # The independent reference uses palm constants; empty may only change input bytes.
 left=result['palm']['assets'];right=result['empty']['assets'];require(set(left)==set(right),'model package asset names differ')
 require({k:v for k,v in result['palm']['manifest'].items() if k!='assets'}=={k:v for k,v in result['empty']['manifest'].items() if k!='assets'},'non-asset package contract differs')
 for name in left:
  if name!='input_hwc_i8':require(all(left[name][k]==right[name][k] for k in ('address','bytes','sha256')),'non-input model assets differ: '+name)
 return result

def prepare_integer_references(models,out,reference=None):
 if reference is None:
  from live_reference_02 import LiveReference02
  reference=LiveReference02()
 target=out/'integer_reference';target.mkdir();summary={}
 for case,model in models.items():
  raw=Path(model['ref']['frame_file']).read_bytes();began=time.monotonic();golden=reference.calculate(raw,mode='packed_integer')
  require(golden.get('reference_mode')=='packed_integer' and golden['frame_sha256']==sha_bytes(raw),'integer reference identity mismatch')
  require(len(golden['input'])==307200 and len(golden['display'])==462400 and len(golden['detections'])==golden['NMS_count']<=64,'integer reference geometry mismatch')
  expected_heads={h['name']:h for h in model['manifest']['model_outputs']};require(set(golden['heads'])==set(expected_heads),'integer reference head names mismatch')
  for name,h in expected_heads.items():require(len(golden['heads'][name])==h['bytes'],'integer reference head size mismatch')
  directory=target/case;directory.mkdir();source={'input':Path(model['ref']['input_file']),'display':Path(model['ref']['display_file'])}
  source.update({h['name']:Path(h['file']) for h in model['ref']['heads']})
  packed={'input':golden['input'],'display':golden['display'],**golden['heads']};compare=[]
  for name,data in packed.items():
   (directory/(name+'.bin')).write_bytes(data);old=source[name].read_bytes()
   compare.append({'name':name,'packed_sha256':sha_bytes(data),'historical_ORT_fixture_sha256':sha_bytes(old),'differing_bytes':sum(a!=b for a,b in zip(data,old)) if len(data)==len(old) else None,'same_length':len(data)==len(old)})
  meta={k:v for k,v in golden.items() if k not in ('input','display','heads')};meta['comparison_with_historical_fixture']=compare;meta['reference_calculation_host_seconds']=time.monotonic()-began
  (directory/'reference.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8');summary[case]=meta;model['golden']=golden
 return summary

def make_config(package,frame,fb,run,camera=False,live_preview=False):
 _,words,_=make(package,frame,fb,run,camera=camera,window=True,concat=True,live_preview=live_preview)
 words[30:32]=[int(BUILD[:8],16),int(BUILD[8:],16)]
 return struct.pack('<40I',*words)

def check_identity(identity):
 require(identity['build_id']==BUILD and identity['cpu_hz']==CPU_HZ and identity['nonce_echo_matched'], 'firmware identity/nonce/clock mismatch')
 require(identity['ddr_base']==0x80000000 and identity['ddr_end']==0x88000000,'AST1 DDR declaration mismatch')
 require(identity['gpio_status']&15==3 and not identity['uart_errors'] and not identity['npu_errors'],'DDR/NPU/UART readiness failure')

def display_colorbars(mon,out,report,save,already_confirmed=False):
 """Select the existing scanout-generated color bars and ask about the panel."""
 status,raw=mon.request(22,0) if already_confirmed else mon.request(22,1,struct.pack('<I',1));(out/'colorbars_reply.bin').write_bytes(raw)
 query=decode_query(raw);require(status==0 and query['requested_pattern']==1 and query['cpu_hz']==CPU_HZ and not query['video_fault'],'scanout colorbar selection failed')
 report['display_preflight']={'diagnostic':'existing scanout-generated eight color bars via opcode22 mode1; no DDR/IMG frame claimed','video_query':query,'physical_panel_verified':False,'awaiting_user_observation':True};save()
 if already_confirmed:answer='VISIBLE';report['display_preflight']['confirmation_source']='user confirmed 08 current color bars and no out-of-range message after the prior session'
 else:
  print(json.dumps({'stage':'awaiting_panel_observation','message':'Report the actual 480p color bars; send VISIBLE only after the user confirms the screen.'}),flush=True)
  answer=sys.stdin.readline().strip()
 require(answer=='VISIBLE','panel observation missing or reports a failure')
 report['display_preflight']['user_reported_colorbars_visible']=True;report['display_preflight']['awaiting_user_observation']=False;report['physical_panel_verified']=False;report['physical_panel_scope']='color bars visible; camera processing image not yet visually confirmed';save()

def confirm_processed_camera_frame(report,save):
 report['phase']='awaiting_processed_camera_observation';save()
 print(json.dumps({'stage':'awaiting_processed_camera_observation','message':'Report whether the captured processed camera frame is visible; send VISIBLE or NOT_VISIBLE according to user observation.'}),flush=True)
 answer=sys.stdin.readline().strip();require(answer in ('VISIBLE','NOT_VISIBLE'),'processed camera image observation missing')
 visible=answer=='VISIBLE';report['physical_panel_verified']=visible;report['physical_panel_scope']='user reports color bars and processed camera frame visible' if visible else 'user reports color bars visible but processed camera frame not visible';report['camera']['user_reported_processed_frame_visible']=visible;save()

def ddr_test(mon, on_row=lambda row: None):
 rows=[]
 for addr,size in ((0x83ff0000,1),(0x83ff0004,4),(0x83ff001c,16),(0x83ff0100,1024),(0x83fefdfd,1024),(0x80000000,1024),(0x83fffc00,1024)):
  expected=bytes(((i*37+size)^(i>>3))&255 for i in range(size));mon.write_memory(addr,expected);actual=mon.read_memory(addr,size)
  rows.append({'phase':'small','address':hex(addr),'bytes':size,'expected_sha256':sha_bytes(expected),'actual_sha256':sha_bytes(actual),'passed':actual==expected})
  on_row(rows[-1]);require(actual==expected,f'DDR selftest mismatch at {addr:#x}')
 patterns={addr:hashlib.shake_256(addr.to_bytes(4,'little')+b'RV32_DDR_ADDRESS_SELFTEST').digest(2048) for addr in (0x80000000,0x80800000,0x83000000,0x83fff800)}
 for addr,data in patterns.items():mon.write_memory(addr,data)
 for addr,data in patterns.items():
  actual=mon.read_memory(addr,len(data));rows.append({'phase':'simultaneous_address_signatures','address':hex(addr),'bytes':len(data),'expected_sha256':sha_bytes(data),'actual_sha256':sha_bytes(actual),'passed':actual==data})
  on_row(rows[-1]);require(actual==data,f'DDR address alias or mismatch at {addr:#x}')
 return rows

def upload(mon,path,address,expected_sha256):
 data=path.read_bytes();require(sha_bytes(data)==expected_sha256,'asset changed after preflight: '+str(path));started=time.monotonic();mon.write_memory(address,data);write_end=time.monotonic();actual=mon.read_memory(address,len(data));ended=time.monotonic()
 row={'path':str(path),'address':hex(address),'bytes':len(data),'sha256':sha_bytes(data),'readback_sha256':sha_bytes(actual),'passed':data==actual,'upload_host_seconds':write_end-started,'readback_host_seconds':ended-write_end}
 require(row['passed'],f'full asset readback differs: {path}')
 return row

def verify_outputs(mon,model,row,folder):
 require(not row.get('live_preview',False),'Same-frame framebuffer comparison is invalid for asynchronous live preview')
 ref=model['golden'];manifest=model['manifest'];checks=[]
 targets=[('input',0x80100000,ref['input']),('framebuffer',int(row['framebuffer'],16),ref['display'])]
 targets += [(x['name'],x['address'],ref['heads'][x['name']]) for x in manifest['model_outputs']]
 for name,addr,expected in targets:
  actual=mon.read_memory(addr,len(expected));(folder/(name+'.bin')).write_bytes(actual)
  checks.append({'name':name,'address':hex(addr),'bytes':len(actual),'expected_sha256':sha_bytes(expected),'actual_sha256':sha_bytes(actual),'expected_crc32':f'{zlib.crc32(expected):08x}','actual_crc32':f'{zlib.crc32(actual):08x}','exact':actual==expected})
 selected=ref['selected_palm']; box=selected['display_680x340_xyxy'] if selected else [0]*4
 nmsmeta=(row['NMS_count'],row['palm_count'],row['bbox_compact_xyxy'])==(ref['NMS_count'],int(bool(selected)),box)
 if selected:nmsmeta=nmsmeta and (row['score_q15'],row['class_id'])==(selected['score_q15'],selected['class_id'])
 fields=('x1_q16','y1_q16','x2_q16','y2_q16','score_q15','class_id')
 expected=b''.join(struct.pack('<6I',*[d[k] for k in fields]) for d in ref['detections'])
 actual=mon.read_memory(manifest['detection']['result_address'],len(expected)) if expected else b''
 (folder/'NMS.bin').write_bytes(actual)
 result={'checks':checks,'nms_metadata_exact':nmsmeta,'nms_bytes':len(actual),'nms_expected_sha256':sha_bytes(expected),'nms_actual_sha256':sha_bytes(actual),'nms_byte_exact':actual==expected}
 result['passed']=all(x['exact'] for x in checks) and nmsmeta and actual==expected
 (folder/'comparison.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
 require(result['passed'],'input/head/NMS/framebuffer golden mismatch')
 return result

def execute_fixed(mon,model,query,case,repeats,out,save,report):
 frame,run,firstfb=session_start(query,10000,2*repeats+20);case_out=out/case;case_out.mkdir()
 case_result={'case':case,'package_sha256':model['package_sha256'],'reference_sha256':model['reference_sha256'],'asset_receipts':[],'runs':[]}
 report['cases'].append(case_result);save()
 upload_start=time.monotonic()
 constants={name:(asset['address'],asset['bytes'],asset['sha256']) for name,asset in model['assets'].items() if name!='input_hwc_i8'}
 previous=getattr(mon,'_loaded_constants',None)
 if case=='empty' and previous and previous['case']=='palm' and previous['constants']==constants and len(previous['receipts'])==len(constants) and {x['name'] for x in previous['receipts']}==set(constants) and all(x['passed'] and int(x['address'],16)==constants[x['name']][0] and x['bytes']==constants[x['name']][1] and x['sha256']==x['readback_sha256']==constants[x['name']][2] for x in previous['receipts']):
  case_result['model_reuse']={'source_case':'palm','source_receipt_count':len(previous['receipts']),'same_monitor_session':True,'new_upload_performed':False,'same_address_size_sha256':True,'scope':'same loaded immutable assets; no reprogram/reconnect; refers to palm receipts in this result'};save()
 else:
  for name,asset in model['assets'].items():
   if name=='input_hwc_i8':continue
   receipt=upload(mon,asset['path'],asset['address'],asset['sha256']);require(receipt['sha256']==asset['sha256'],'asset changed after preflight')
   case_result['asset_receipts'].append(dict(name=name,**receipt));save()
   if len(case_result['asset_receipts'])%32==0:print(json.dumps({'stage':'asset_upload','case':case,'verified':len(case_result['asset_receipts'])}),flush=True)
  mon._loaded_constants={'case':case,'constants':constants,'receipts':list(case_result['asset_receipts'])}
 case_result['model_upload_and_readback_host_seconds']=time.monotonic()-upload_start
 case_result['frame_receipt']=upload(mon,Path(model['ref']['frame_file']),0x81000000,model['ref']['frame_sha256']);save()
 for index in range(repeats):
  fb=firstfb^((index&1)*0x100000);folder=case_out/f'run_{index:04d}';folder.mkdir()
  config=make_config(model['package'],frame+index,fb,run+index);(folder/'config.bin').write_bytes(config)
  mon.write_memory(0x80100000,bytes([0xa5])*307200)
  mon.write_memory(CONFIG_ADDRESS,config);mon.request(17,1);mon.request(18,1)
  _,wb=mon.request(27,0);_,cb=mon.request(29,0);(folder/'window_before.bin').write_bytes(wb);(folder/'concat_before.bin').write_bytes(cb)
  start=time.monotonic();status,raw=mon.request(25,CONFIG_ADDRESS,allow_status=tuple(range(1,64)));command_wall=time.monotonic()-start
  (folder/'workflow.bin').write_bytes(raw);row=decode(raw,status)
  require(row['pass_result'] and row['source']=='explicit DDR replay' and row['window_requested'] and row['concat_requested'],'fixed replay failed or requested mode differs')
  require((row['frame_id'],row['run_id'],row['framebuffer'])==(frame+index,run+index,hex(fb)),'fresh frame/run/framebuffer mismatch')
  t=row['timestamps_CPU64'];row['phase_CPU_ticks']={'capture_or_replay_setup':t['TP0']-t['T0'],'preprocess':t['TP1']-t['TP0'],'graph':t['TG1']-t['TG0'],'NMS':t['TB']-t['TG1'],'display_and_commit':t['TR']-t['TB'],'START_to_READY':t['TR']-t['T0'],'START_to_complete_TX_input':t['TE_TX_INPUT']-t['T0']}
  row['host_command_wall_seconds']=command_wall
  _,raw=mon.request(17,0);(folder/'s3.bin').write_bytes(raw);row['S3']=s3_counts(raw);require((row['S3']['jobs'],row['S3']['fallbacks'],row['S3']['LUT_jobs'])==(60,0,57),'S3 graph counts differ')
  _,raw=mon.request(27,0);(folder/'window_after.bin').write_bytes(raw);row['Window']=window_delta_05(decode_window(wb),decode_window(raw),model['window_expected'])
  _,raw=mon.request(29,0);(folder/'concat_after.bin').write_bytes(raw);row['Concat']=concat_timing(concat_delta(decode_concat(cb),decode_concat(raw),True))
  _,raw=mon.request(31,0);(folder/'CPU.bin').write_bytes(raw);row['CPU']=decode_cpu(raw)
  require((row['CPU']['frame_id'],row['CPU']['run_id'],row['CPU']['CPU_Hz'])==(frame+index,run+index,CPU_HZ),'CPU counter identity mismatch')
  _,raw=mon.request(18,0);(folder/'profile.bin').write_bytes(raw);row['profile']=decode_profile(raw)
  require((row['profile']['ops'],row['profile']['batches'],row['profile']['errors'])==(204,1,0),'graph profile failed')
  row['profile']['preprocess_counter_scope']='CMOS2 V1 image_preprocess320; inherited V2 ordinal, hardware capability/fallback determined by firmware'
  layers=[]
  for start_index in range(0,204,32):
   _,raw=mon.request(32,start_index);(folder/f'layers_{start_index:03d}.bin').write_bytes(raw);result=decode_layers(raw)
   require(result['completed']==204 and all(x['valid'] and not x['status'] for x in result['records']),'logical layer profile invalid');layers+=result['records']
  require(len(layers)==204,'missing layer records');(folder/'layers.json').write_text(json.dumps(layers,indent=2)+'\n',encoding='utf-8')
  compare_start=time.monotonic();row['comparison']=verify_outputs(mon,model,row,folder);row['verification_readback_host_seconds']=time.monotonic()-compare_start
  case_result['runs'].append(row);save();print(json.dumps({'stage':'fixed_complete','case':case,'frame_id':row['frame_id'],'START_to_READY_seconds':row['START_to_READY_seconds'],'host_command_wall_seconds':command_wall}),flush=True)
 values=[x['START_to_READY_seconds'] for x in case_result['runs']];avg=sum(values)/len(values)
 case_result['performance_summary']={'mean_START_to_READY_seconds':avg,'median_START_to_READY_seconds':statistics.median(values),'minimum_START_to_READY_seconds':min(values),'maximum_START_to_READY_seconds':max(values),'reciprocal_mean_one_shot_FPS':1/avg if avg>0 else None,'scope':'Per-frame 70MHz CPU64 START-to-READY processing reciprocal; separate host commands and full validation readbacks, not autonomous camera FPS'};save()
 _,raw=mon.request(22,0);after=decode_query(raw)
 require(after['cpu_hz']==CPU_HZ and not after['video_fault'],'post-run video query failure')
 return after

def save_live_golden(golden,folder):
 folder.mkdir()
 for name,data in {'input':golden['input'],'display':golden['display'],**golden['heads']}.items():
  (folder/(name+'.bin')).write_bytes(data)
 meta={k:v for k,v in golden.items() if k not in ('input','display','heads')}
 meta['files_sha256']={name:sha_bytes(data) for name,data in {'input':golden['input'],'display':golden['display'],**golden['heads']}.items()}
 (folder/'reference.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8')
 return meta

def capture_comparison(mon,model,reference,row,folder):
 started=time.monotonic();captured=mon.read_memory(0x81000000,1843200);(folder/'captured_rgb565le.bin').write_bytes(captured)
 capture_readback_seconds=time.monotonic()-started;started=time.monotonic()
 golden=reference.calculate(captured,mode='packed_integer')
 require(golden.get('reference_mode')=='packed_integer' and golden['frame_sha256']==sha_bytes(captured),'same-frame integer reference mismatch')
 golden_meta=save_live_golden(golden,folder/'integer_reference');reference_seconds=time.monotonic()-started
 same_model=dict(model);same_model['golden']=golden;started=time.monotonic()
 comparison=verify_outputs(mon,same_model,row,folder)
 return {'captured_frame_sha256':sha_bytes(captured),'reference':golden_meta,'comparison':comparison,'capture_readback_host_seconds':capture_readback_seconds,'reference_host_seconds':reference_seconds,'comparison_readback_host_seconds':time.monotonic()-started}

def run_payload(mon,raw,status,folder,frame,run,fb):
 (folder/'workflow.bin').write_bytes(raw);row=decode(raw,status)
 require(row['pass_result'] and row['source']=='real CMOS2 capture' and row['window_requested'] and row['concat_requested'],'real camera workflow or requested mode failed')
 require((row['frame_id'],row['run_id'],row['framebuffer'])==(frame,run,hex(fb)),'camera frame/run/framebuffer mismatch')
 ticks=row['timestamps_CPU64'];row['phase_CPU_ticks']={'capture':ticks['TP0']-ticks['T0'],'preprocess':ticks['TP1']-ticks['TP0'],'graph':ticks['TG1']-ticks['TG0'],'NMS':ticks['TB']-ticks['TG1'],'display_and_commit':ticks['TR']-ticks['TB'],'START_to_READY':ticks['TR']-ticks['T0'],'START_to_complete_TX_input':ticks['TE_TX_INPUT']-ticks['T0']}
 return row

def execute_camera(mon,model,reference,query,out,save,report):
 folder=out/'camera_once';folder.mkdir();frame,run,fb=session_start(query,20000,100000)
 config=make_config(model['package'],frame,fb,run,camera=True);(folder/'config.bin').write_bytes(config)
 mon.write_memory(0x80100000,bytes([0xa5])*307200);mon.write_memory(CONFIG_ADDRESS,config);mon.request(17,1);mon.request(18,1)
 _,wb=mon.request(27,0);_,cb=mon.request(29,0);(folder/'window_before.bin').write_bytes(wb);(folder/'concat_before.bin').write_bytes(cb)
 report['camera']={'frame_id':frame,'run_id':run,'pass_result':False};save()
 report['real_camera_capture_called']=True;save();began=time.monotonic();status,raw=mon.request(25,CONFIG_ADDRESS,allow_status=tuple(range(1,64)));elapsed=time.monotonic()-began
 row=run_payload(mon,raw,status,folder,frame,run,fb);row['host_command_wall_seconds']=elapsed
 _,raw=mon.request(17,0);(folder/'s3.bin').write_bytes(raw);row['S3']=s3_counts(raw);require((row['S3']['jobs'],row['S3']['fallbacks'],row['S3']['LUT_jobs'])==(60,0,57),'camera S3 counts differ')
 _,raw=mon.request(27,0);(folder/'window_after.bin').write_bytes(raw);row['Window']=window_delta_05(decode_window(wb),decode_window(raw),model['window_expected'])
 _,raw=mon.request(29,0);(folder/'concat_after.bin').write_bytes(raw);row['Concat']=concat_timing(concat_delta(decode_concat(cb),decode_concat(raw),True))
 _,raw=mon.request(31,0);(folder/'CPU.bin').write_bytes(raw);row['CPU']=decode_cpu(raw)
 require((row['CPU']['frame_id'],row['CPU']['run_id'],row['CPU']['CPU_Hz'])==(frame,run,CPU_HZ),'camera CPU counter identity mismatch')
 _,raw=mon.request(18,0);(folder/'profile.bin').write_bytes(raw);row['profile']=decode_profile(raw)
 require((row['profile']['ops'],row['profile']['batches'],row['profile']['errors'])==(204,1,0),'camera graph profile failed')
 report['camera']['row']=row;save();report['camera']['same_frame']=capture_comparison(mon,model,reference,row,folder)
 report['camera']['pass_result']=True;report['real_camera_capture_called']=True;save()
 _,raw=mon.request(22,0);query=decode_query(raw);require(query['cpu_hz']==CPU_HZ and not query['video_fault'],'post-camera video query failed')
 print(json.dumps({'stage':'camera_once_complete','frame_id':frame,'START_to_READY_seconds':row['START_to_READY_seconds']}),flush=True)
 return query

def s3_counts(raw):
 require(len(raw)==48,'S3 counter ABI length mismatch');w=struct.unpack('<12I',raw);require(w[0]==0x33515253,'S3 counter ABI identity mismatch')
 return {'jobs':w[1],'fallbacks':w[2],'LUT_jobs':w[3]}

def execute_continuous(mon,model,reference,query,seconds,out,save,report,warmup_seconds=5):
 folder=out/'camera_continuous';folder.mkdir();continuous={'pass_result':False,'ARM_commands':0,'STOP_commands':0,'STOP_confirmed':False,'host_per_frame_STARTs':0,'requested_observation_seconds':seconds,'requested_warmup_seconds':warmup_seconds};report['continuous']=continuous;save()
 _,raw=mon.request(26,0xffffffff);(folder/'pre_arm_status.bin').write_bytes(raw);require(not continuous_snapshot(raw)['active'],'existing autonomous frame loop')
 frame,run,fb=session_start(query,30000,100000);config=make_config(model['package'],frame,fb,run,camera=True);(folder/'config.bin').write_bytes(config)
 identity_before=mon.ping(BUILD);continuous['identity_before']=identity_before;check_identity(identity_before)
 mon.write_memory(CONFIG_ADDRESS,config);mon.request(17,1);mon.request(18,1);_,raw=mon.request(17,0);(folder/'s3_before.bin').write_bytes(raw);before=s3_counts(raw)
 _,wb=mon.request(27,0);_,cb=mon.request(29,0);(folder/'window_before.bin').write_bytes(wb);(folder/'concat_before.bin').write_bytes(cb)
 armed=False;arm_attempted=False;stop_attempted=False
 try:
  continuous.update(frame_id=frame,run_id=run,first_framebuffer=hex(fb),ARM_commands=1);save();began=time.monotonic();arm_attempted=True
  mon.request(26,CONFIG_ADDRESS);armed=True;arm_ack=time.monotonic();continuous['ARM_reply_received']=True;continuous['ARM_request_to_reply_host_seconds']=arm_ack-began;save()
  warmup_start=time.monotonic();deadline=warmup_start+warmup_seconds
  while time.monotonic()<deadline:time.sleep(min(.5,max(0,deadline-time.monotonic())))
  snapshot_request=time.monotonic();_,raw=mon.request(26,0xffffffff);snapshot_reply=time.monotonic();(folder/'warmup_status.bin').write_bytes(raw)
  ident,active,count,status=struct.unpack_from('<4I',raw);continuous['warmup_snapshot_header']={'abi_id':hex(ident),'active':active,'completed':count,'last_status':status};continuous['warmup_wait_host_seconds']=snapshot_request-warmup_start;continuous['warmup_status_query_host_seconds']=snapshot_reply-snapshot_request;save()
  first=continuous_snapshot(raw);continuous['warmup_snapshot']=first;save()
  require(first['active'] and first['completed']>0 and not first['last_status'] and first['last_run'] is not None and first['last_run']['pass_result'],'warmup did not yield an active completed camera frame')
  wait_start=time.monotonic();deadline=wait_start+seconds
  while time.monotonic()<deadline:time.sleep(min(.5,max(0,deadline-time.monotonic())))
  stop_request=time.monotonic();continuous['observation_wait_host_seconds']=stop_request-wait_start;continuous['STOP_commands']=1;save();stop_attempted=True
  mon.request(26,0);armed=False;stop_reply=time.monotonic();continuous['STOP_confirmed']=True
  continuous['STOP_request_to_reply_host_seconds']=stop_reply-stop_request;continuous['ARM_request_to_STOP_reply_host_seconds']=stop_reply-began;save()
  _,raw=mon.request(26,0xffffffff);(folder/'continuous_status.bin').write_bytes(raw)
  ident,active,count,status=struct.unpack_from('<4I',raw);continuous['stop_snapshot_header']={'abi_id':hex(ident),'active':active,'completed':count,'last_status':status};save()
  snapshot=continuous_snapshot(raw);continuous['stop_snapshot']=snapshot;save()
  require(not snapshot['active'] and snapshot['completed']>0 and not snapshot['last_status'] and snapshot['last_run'] is not None,'continuous completion/STOP failed')
  interval=measured_interval(first,snapshot,frame,run,fb);continuous['measured_interval']=interval;save()
  n=snapshot['completed'];last=snapshot['last_run'];lastfb=fb^(((n-1)&1)*0x100000)
  row=run_payload(mon,raw[16:],snapshot['last_status'],folder,frame+n-1,run+n-1,lastfb)
  _,raw=mon.request(31,0);(folder/'CPU.bin').write_bytes(raw);row['CPU']=decode_cpu(raw)
  require((row['CPU']['frame_id'],row['CPU']['run_id'],row['CPU']['CPU_Hz'])==(frame+n-1,run+n-1,CPU_HZ),'continuous final CPU identity mismatch')
  _,raw=mon.request(17,0);(folder/'s3_after.bin').write_bytes(raw);after=s3_counts(raw)
  delta={k:(after[k]-before[k])&0xffffffff for k in ('jobs','fallbacks','LUT_jobs')}
  require(n<2**32//60 and (delta['jobs'],delta['fallbacks'],delta['LUT_jobs'])==(60*n,0,57*n),'continuous S3 job counts differ')
  _,raw=mon.request(27,0);(folder/'window_after.bin').write_bytes(raw);continuous['Window']=window_delta_05(decode_window(wb),decode_window(raw),model['window_expected'],n)
  _,raw=mon.request(29,0);(folder/'concat_after.bin').write_bytes(raw);continuous['Concat']=concat_timing(concat_delta(decode_concat(cb),decode_concat(raw),True,n))
  _,raw=mon.request(18,0);(folder/'profile.bin').write_bytes(raw);profile=decode_profile(raw)
  require((profile['ops'],profile['batches'],profile['errors'])==(204*n,n,0),'continuous aggregate graph count mismatch')
  graph=profile['counters']['Graph204'];graph_average=graph['seconds']/n if graph['available'] and graph['seconds'] is not None else None
  continuous.update(completed_frames_including_warmup=n,last_run=row,S3_job_delta=delta,profile=profile,mean_graph_service_seconds_all_frames_including_warmup=graph_average,
   graph_service_scope='Profile Graph204 CPU ticks divided by all successful ARM-to-STOP graphs, including warmup; not the continuous throughput denominator')
  identity_after=mon.ping(BUILD);continuous['identity_after']=identity_after;continuous['error_counters']={'uart_before':identity_before['uart_errors'],'uart_after':identity_after['uart_errors'],'npu_before':identity_before['npu_errors'],'npu_after':identity_after['npu_errors'],'profile_errors':profile['errors'],'last_frame_capture_errors':row['capture_errors'],'last_frame_video_fault':row['video_fault'],'autonomous_last_status':snapshot['last_status'],'S3_fallbacks':delta['fallbacks'],'window_failures':continuous['Window']['failures'],'concat_failures':continuous['Concat']['failures']};save();check_identity(identity_after)
  continuous['same_final_frame']=capture_comparison(mon,model,reference,row,folder);continuous['pass_result']=True;save()
  _,raw=mon.request(22,0);query=decode_query(raw);require(query['cpu_hz']==CPU_HZ and not query['video_fault'],'post-continuous video query failed')
  return query
 finally:
  if armed and not stop_attempted:
   continuous['STOP_commands']+=1;save()
   try:mon.request(26,0);continuous['STOP_confirmed']=True
   except Exception as exc:continuous['stop_error']=f'{type(exc).__name__}: {exc}'
  elif armed and stop_attempted:continuous['stop_state_unknown']=True
  elif arm_attempted and not continuous.get('ARM_reply_received'):continuous['arm_state_unknown']=True
  save()
def port_in_use():
 with socket.socket() as sock:sock.settimeout(.3);return sock.connect_ex(('127.0.0.1',65420))==0

def enumerate_devices(explicit):
 ports=[p for p in list_ports.comports() if (p.vid,p.pid)==(0x10c4,0xea60)]
 require(len(ports)==1,'need exactly one present CP210x 10c4:ea60 UART')
 if explicit:require(ports[0].device.casefold()==explicit.casefold(),'specified port differs from sole CP210x')
 ps="@(Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'USB\\VID_0403&PID_6010\\*' } | Select-Object Status,FriendlyName,InstanceId) | ConvertTo-Json -Compress"
 shell=shutil.which('pwsh') or shutil.which('powershell');require(shell is not None,'PowerShell not available for PnP enumeration')
 process=subprocess.run([shell,'-NoProfile','-NonInteractive','-Command',ps],capture_output=True,text=True,timeout=60)
 require(process.returncode==0,'FTDI PnP enumeration failed: '+process.stderr)
 devices=json.loads(process.stdout or '[]');devices=devices if isinstance(devices,list) else [devices]
 require(len(devices)==1 and devices[0]['Status']=='OK','need exactly one healthy physical FTDI 0403:6010')
 return {'uart':{'port':ports[0].device,'vid':ports[0].vid,'pid':ports[0].pid,'serial':ports[0].serial_number,'hwid':ports[0].hwid},'jtag':devices[0]}

def main():
 if not __debug__:raise RuntimeError('Do not run with Python optimization: legacy config generator uses assertions')
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--native',choices=('native_pds25_02',),default='native_pds25_02');p.add_argument('--bitgen-receipt',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--port',help='Freshly enumerated CP210x port; omitted requires one unambiguous CP210x');p.add_argument('--repeats',type=int,default=1);p.add_argument('--timeout',type=float,default=180);p.add_argument('--camera',action='store_true',help='After fixed checks, capture and verify one real CMOS2 frame');p.add_argument('--continuous-seconds',type=float,default=0,help='After camera verification, one autonomous ARM/STOP observation, 20..300 seconds');p.add_argument('--warmup-seconds',type=float,default=5,help='Continuous camera warmup before first completed-frame boundary, 1..30 seconds');p.add_argument('--resume-from',type=Path,help='Resume from the immediately preceding confirmed startup without reprogramming');p.add_argument('--confirmed-colorbars',action='store_true',help='Record the user observation of the prior still-active 08 color bars');a=p.parse_args()
 if bool(a.resume_from)!=a.confirmed_colorbars:p.error('--resume-from and --confirmed-colorbars must be supplied together')
 if not 1<=a.repeats<=100 or a.timeout<=0:p.error('repeats 1..100 and positive timeout required')
 if a.continuous_seconds and (not a.camera or not 20<=a.continuous_seconds<=300):p.error('--continuous-seconds requires --camera and a 20..300 second interval')
 if not 1<=a.warmup_seconds<=30:p.error('--warmup-seconds must be 1..30 seconds')
 out=a.out.resolve();require(out.is_relative_to(CANDIDATE.resolve()) and out!=CANDIDATE.resolve(),'evidence must be inside this candidate')
 require(out.relative_to(CANDIDATE.resolve()).parts[0] not in ('project','native_01','native_pds25_01','native_pds25_02','native_pds25_03','native_pds25_04','native_pds25_05','fw_build_final','sim'),'evidence cannot be in frozen inputs/builds')
 out.mkdir(parents=True,exist_ok=False)
 sources=out/'runner_sources';sources.mkdir();source_hashes={}
 for name in ('run_board_session_08.py','program_window_sram_70.py','startup_diag_contract.py','board_monitor.py','run_graph_package.py','graph_descriptor.py','make_workflow_config.py','make_cmos2_workflow_config.py','cmos2_protocol.py','ddr_hdmi_protocol.py','rv32_performance_protocol.py','window_protocol.py','concat_protocol.py','live_reference_02.py','pds25_guard.py','continuous_fps.py'):
  raw=(Path(__file__).resolve().parent/name).read_bytes();(sources/name).write_bytes(raw);source_hashes[name]=sha_bytes(raw)
 profile_path=CANDIDATE/'VIDEO_PROFILE.json';video_profile=json.loads(profile_path.read_text(encoding='utf-8-sig'))
 report={'display_mode':{'carrier':video_profile['carrier'],'framebuffer':video_profile['framebuffer_rgb565'],'profile_sha256':sha_file(profile_path),'scope':'display timing; recognition FPS is independently measured by continuous CPU64 event completion delta'},'runner_sources_sha256':source_hashes,'started_utc':utc(),'passed':False,'phase':'offline_preflight','physical_panel_verified':False,'real_camera_capture_called':False,'Flash_written':False,'cases':[],'IMG1_direct_MMIO_telemetry':'not exposed by firmware AST1; execution inferred from exact bitstream/firmware binding and timing, not directly measured','command':sys.argv,'script_sha256':sha_file(Path(__file__))}
 def save():(out/'result.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 save();claimed=False;lock=None
 try:
  report['qualification']=q=qualify(a.bitgen_receipt,a.native);models=verify_models();report['model_preflight']={k:{'package_sha256':v['package_sha256'],'reference_sha256':v['reference_sha256'],'assets':len(v['assets']),'window_expected':v['window_expected']} for k,v in models.items()};save()
  report['phase']='integer_reference';save()
  from live_reference_02 import LiveReference02
  reference=LiveReference02();report['integer_reference']=prepare_integer_references(models,out,reference);save()
  report['phase']='acquire_global_lock';save();lock=LOCK.open('r+b');lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
  try:
   report['phase']='device_preflight';save();require(not port_in_use(),'existing JTAG server at 65420')
   devices=enumerate_devices(a.port);report['devices']=devices
   old=STATUS.read_text(encoding='utf-8');(out/'previous_board_status.md').write_text(old,encoding='utf-8')
   report['prior_status_header']='\n'.join(old.splitlines()[:4]);report['prior_status_note']='Historical header is advisory; current exclusive OS lock and JTAG availability determine ownership.'
   if a.resume_from:
    previous_path=a.resume_from.resolve();require(previous_path.is_relative_to((CANDIDATE/'board_tools').resolve()) and previous_path.name=='result.json','prior result outside candidate')
    previous=json.loads(previous_path.read_text(encoding='utf-8'));prior_header=report['prior_status_header'];require('已释放' in prior_header and str(previous_path.parent) in prior_header,'prior session is not latest recorded board owner')
    require(previous.get('phase')=='failed' and previous.get('phase_at_error')=='display_colorbars' and previous['qualification']['bitstream_sha256']==q['bitstream_sha256'] and previous['startup']['pass'] is True and previous['startup']['monitor_challenge']['valid'] is True and previous['startup']['startup_diagnostic']['pass_result'] is True,'prior startup or exact bitstream not established')
    require(previous['devices']==devices,'present USB devices differ from preceding session')
    report['startup']=previous['startup'];report['resume']={'previous_result':str(previous_path),'previous_result_sha256':sha_file(previous_path),'bitstream_sha256':q['bitstream_sha256'],'reprogrammed':False,'scope':'prior successful SRAM programming plus fresh nonce in current session; no independent hardware bitstream readback across released lock interval'};save()
   header=f'# 板卡使用与交接状态\n\n更新时间UTC：{utc()}；当前使用权：**FPS_V2 / Vision5MP / DDR_HDMI_STARTUP_02**。本进程持有原共享 BOARD_RESOURCE.lock；08 {BUILD}，仅SRAM，证据 {out}。\n\n'
   STATUS.write_text(header+old,encoding='utf-8');claimed=True
   if not a.resume_from:
    report['phase']='SRAM_program_and_startup';save()
    command=[sys.executable,'-B','-X','utf8',str(CANDIDATE/'board_tools/program_window_sram_70.py'),'--bitstream',q['bitstream'],'--expected-sha256',q['bitstream_sha256'],'--lease-record',str(STATUS),'--out',str(out/'startup'),'--port',devices['uart']['port'],'--cpu-hz',str(CPU_HZ),'--expected-build',BUILD,'--startup-diagnostic-firmware',str(FW/'manifest.json'),'--pds-bin',str(PDS),'--seconds','45','--program-timeout','240']
    report['startup_command']=command;save()
    with (out/'startup_console.log').open('xb') as log: code=subprocess.call(command,cwd=CANDIDATE/'board_tools',stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    startup=json.loads((out/'startup/result.json').read_text(encoding='utf-8'));report['startup']=startup;save()
    require(code==0 and startup.get('pass') is True and startup.get('monitor_challenge',{}).get('valid') is True and startup.get('startup_diagnostic',{}).get('pass_result') is True,'SRAM startup/identity proof failed')
   report['phase']='DDR_selftest';save()
   with Monitor.open(devices['uart']['port'],out/'serial',timeout=a.timeout) as mon:
    identity=mon.ping(BUILD);check_identity(identity);report['identity']=identity;save()
    report['DDR_tests']=[]
    def record_ddr(row):report['DDR_tests'].append(row);save()
    ddr_test(mon,record_ddr);save()
    report['phase']='display_colorbars';save();display_colorbars(mon,out,report,save,a.confirmed_colorbars)
    _,raw=mon.request(22,0);query=decode_query(raw);require(query['cpu_hz']==CPU_HZ and not query['video_fault'],'initial video query failure')
    report['phase']='fixed_replay';report['before_video']=query;save()
    for case in ('palm','empty'):query=execute_fixed(mon,models[case],query,case,a.repeats,out,save,report)
    if a.camera:
     report['phase']='camera_once';save();query=execute_camera(mon,models['empty'],reference,query,out,save,report)
     confirm_processed_camera_frame(report,save)
     if a.continuous_seconds:
      report['phase']='camera_continuous';save();query=execute_continuous(mon,models['empty'],reference,query,a.continuous_seconds,out,save,report,a.warmup_seconds)
    report['after_video']=query;identity=mon.ping(BUILD);check_identity(identity);report['identity_after']=identity
   report['phase']='complete';report['passed']=True;save()
  finally:
   if claimed:
    existing=STATUS.read_text(encoding='utf-8');header=f'# 板卡使用与交接状态\n\n更新时间UTC：{utc()}；当前使用权：**FPS_V2 已释放**。08 本会话结果 {report["phase"]}；本进程释放租约，UART/JTAG 关闭情况以进程和端口实查为准；仅SRAM；证据 {out}。\n\n'
    STATUS.write_text(header+existing,encoding='utf-8')
   lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1);lock.close();lock=None
 except BaseException as exc:
  report['passed']=False;report['error']={'type':type(exc).__name__,'message':str(exc),'traceback':traceback.format_exc()};report['phase_at_error']=report['phase'];report['phase']='failed';save()
 finally:
  if lock is not None:lock.close()
  report['finished_utc']=utc();save()
 print(json.dumps({'passed':report['passed'],'phase':report['phase'],'error':report.get('error')}),flush=True)
 return 0 if report['passed'] else 1
if __name__=='__main__':raise SystemExit(main())



















