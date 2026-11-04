"""One real-board fixed-frame Graph204 replay, exact readback, no FPS claim."""
from pathlib import Path
import json,struct,time
import board_common as b
from cmos2_protocol import decode

def expected_display(raw):
 out=bytearray(680*340*2)
 for y in range(340):
  sy=(36*y+18)//17
  for x in range(680):
   sx=(32*x+16)//17;a=(sy*1280+sx)*2;c=(y*680+x)*2;out[c:c+2]=raw[a:a+2]
 return bytes(out)

def run(mon,model,report,save,out,query):
 folder=out/'fixed_palm_replay';folder.mkdir();rec={'scope':'Fixed reference RGB565 replay on the programmed board; not a camera image or continuous FPS','checks':[],'pass':False};report['fixed_palm']=rec;report['phase']='fixed_palm_replay';save()
 ref=model['ref'];frame_bytes=Path(ref['frame_file']).read_bytes();b.require(b.sha_bytes(frame_bytes)==ref['frame_sha256'],'Raw fixture identity mismatch')
 print(json.dumps({'stage':'fixed_frame_upload','bytes':len(frame_bytes)}),flush=True)
 rec['frame_upload']=b.upload(mon,Path(ref['frame_file']),0x81000000,ref['frame_sha256']);save()
 frame,run_id,fb=b.session_start(query,80000,1000)
 words=list(struct.unpack('<40I',b.make_config(model['package'],frame,fb,run_id,camera=False)));words[1]=2;words[18]=0xffffffff
 cfg=struct.pack('<40I',*words);(folder/'config.bin').write_bytes(cfg);mon.write_memory(0x80100000,bytes([0xa5])*307200);mon.write_memory(b.CONFIG_ADDRESS,cfg)
 mon.request(17,1);mon.request(18,1);_,before=mon.request(27,0)
 started=time.monotonic();status,raw=mon.request(25,b.CONFIG_ADDRESS,allow_status=tuple(range(1,64)));rec['command_host_seconds']=time.monotonic()-started;(folder/'workflow.bin').write_bytes(raw);row=decode(raw,status);rec['workflow']=row;save()
 b.require(row['pass_result'] and row['pipeline_v2'] and row['source']=='explicit DDR replay' and row['graph_ops']==204,'Fixed replay workflow did not complete')
 _,after=mon.request(27,0);rec['window_delta']=b.window_delta_05(b.decode_window(before),b.decode_window(after),model['window_expected']);_,prof=mon.request(18,0);rec['profile']=b.decode_profile(prof)
 b.require((rec['profile']['ops'],rec['profile']['batches'],rec['profile']['errors'])==(204,1,0),'Fixed replay graph profile mismatch')
 model_dir=Path(__file__).resolve().parent.parent/'model/palm';targets=[('input',0x80100000,(model_dir/'input_320x320_hwc_i8_v1.bin').read_bytes()),('framebuffer',fb,expected_display(frame_bytes))]
 for x in model['manifest']['model_outputs']:
  stride={'head_s8_logits':'s8','head_s16_logits':'s16','head_s32_logits':'s32'}[x['name']];targets.append((x['name'],x['address'],(model_dir/('head_'+stride+'_logits_hwc_i8.bin')).read_bytes()))
 for name,address,expected in targets:
  print(json.dumps({'stage':'fixed_readback','name':name,'bytes':len(expected)}),flush=True)
  got=mon.read_memory(address,len(expected));(folder/(name+'.bin')).write_bytes(got);item={'name':name,'address':hex(address),'bytes':len(expected),'expected_sha256':b.sha_bytes(expected),'actual_sha256':b.sha_bytes(got),'exact':got==expected};rec['checks'].append(item);save();b.require(item['exact'],'Fixed replay mismatch: '+name)
 fields=('x1_q16','y1_q16','x2_q16','y2_q16','score_q15','class_id');expected=b''.join(struct.pack('<6I',*[d[k] for k in fields]) for d in ref['detections']);got=mon.read_memory(model['manifest']['detection']['result_address'],len(expected)) if expected else b'';(folder/'nms.bin').write_bytes(got)
 rec['nms']={'expected_count':ref['NMS_count'],'actual_count':row['NMS_count'],'expected_sha256':b.sha_bytes(expected),'actual_sha256':b.sha_bytes(got),'exact':got==expected};b.require(got==expected and row['NMS_count']==ref['NMS_count'],'Fixed NMS mismatch')
 b.require(row['palm_count']==1 and row['class_id']==5 and row['score_q15']==21286,'Expected palm selection mismatch')
 rec['pass']=True;save();print(json.dumps({'stage':'fixed_replay_pass','frame_id':frame,'class_id':row['class_id'],'ready_ms':row['START_to_READY_seconds']*1000}),flush=True)
 _,raw=mon.request(22,0);return b.decode_query(raw)
