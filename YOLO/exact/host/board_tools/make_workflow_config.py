"""Offline configuration for the CPU-owned one-START DISPLAY_READY chain."""
from pathlib import Path
import argparse
import json
import struct
import sys
CANDIDATE=Path(__file__).resolve().parents[1]
WORKSPACE=CANDIDATE.parents[1]
sys.path.insert(0,str(CANDIDATE/'tools/graph_pack_dependencies'))
from run_graph_package import validate_package
CONFIG_ADDRESS=0x83ff0000
MODEL_SHA256='97da0db6ca09dfc726b6bb41e93cc9a5c7f0f4690f46502d43eb467f803b8a52'
def make(package,frame_id,framebuffer,run_id=None,software_v2=False):
    m,assets,runs=validate_package(package)
    first=runs[0];descriptor=assets[first['descriptor_asset']]['address'];count=0
    for run in runs:
        assert assets[run['descriptor_asset']]['address']==descriptor+count*96
        assert run['trace_base']==first['trace_base']+count*24
        count+=run['count']
    assert count==204 and assets['input_hwc_i8']['address']==0x80100000
    det=m['detection'];options=det['options']
    assert (options['image_w'],options['image_h'])==(320,320)
    assert m['ddr_high_watermark']<0x1000000
    if m['model_sha256']!=MODEL_SHA256:raise ValueError('Different model requires an audited firmware compatibility update')
    build=m['firmware_build_id']
    if run_id is None:run_id=frame_id
    if not 0<run_id<2**32:raise ValueError('run_id must be nonzero uint32')
    words=[0x31524456,2,0x81000000,assets['input_hwc_i8']['address'],framebuffer,frame_id,
           descriptor,first['trace_base'],runs[-1]['final_output'],runs[-1]['final_bytes'],
           det['descriptor_address'],det['result_address'],det['scratch_address'],
           options['class_count'],options['score_threshold_q15'],options['iou_threshold_q15'],
           options['max_candidates'],options['max_results'],det['class_names'].index('palm'),
           0xb8000000,run_id,int(software_v2),
           *[int(MODEL_SHA256[i:i+8],16) for i in range(0,64,8)],
           int(build[:8],16),int(build[8:],16),5184,0x35363552,2592,1944,1280,640,480,0]
    assert framebuffer in (0x82000000,0x82100000) and 0<=frame_id<2**32
    assert len(words)==40
    return struct.pack('<40I',*words),words,m
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True)
    p.add_argument('--frame-id',type=int,default=1);p.add_argument('--framebuffer',type=lambda x:int(x,0),default=0x82000000)
    p.add_argument('--run-id',type=int);p.add_argument('--software-v2',action='store_true')
    p.add_argument('--out',type=Path,required=True);a=p.parse_args()
    raw,words,m=make(a.package,a.frame_id,a.framebuffer,a.run_id,a.software_v2);a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_bytes(raw)
    a.out.with_suffix('.json').write_text(json.dumps({'config_address':hex(CONFIG_ADDRESS),
        'firmware_build_id':m['firmware_build_id'],'words':[hex(x) for x in words],
        'mode':('explicit software V2 fallback' if a.software_v2 else 'hardware V2')+'; CPU single START; real 204 graph and NMS; software display resize; shared-DDR HDMI scanout',
        'status':'configuration only, not an execution result'},indent=2)+'\n')
    print(a.out)
if __name__=='__main__':main()
