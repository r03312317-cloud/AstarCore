from pathlib import Path
import argparse,json,struct
from make_workflow_config import make as legacy_make
CONFIG_ADDRESS=0x80fff000
ID=0x31563243
def make(package,frame_id,framebuffer,run_id=None,camera=True,window=False,concat=False,live_preview=False):
 _,words,m=legacy_make(package,frame_id,framebuffer,run_id)
 words[0]=ID;words[1]=1;words[21]=int(camera)
 if window:words[19]|=0x04000000
 if concat:words[19]|=0x02000000
 words[32:40]=[2560,0x35363552,1280,720,1280,680,340,int(live_preview)]
 if not 0<frame_id<2**32:raise ValueError('Nonzero uint32 frame ID required')
 if live_preview and (not camera or frame_id>=2**31):raise ValueError('Live preview requires a camera and 31-bit inference frame ID')
 if m['ddr_high_watermark']>=CONFIG_ADDRESS-0x80000000:raise ValueError('Configuration conflicts with model memory')
 return struct.pack('<40I',*words),words,m
def main():
 p=argparse.ArgumentParser();p.add_argument('--package',type=Path,required=True)
 p.add_argument('--frame-id',type=int,default=1);p.add_argument('--run-id',type=int,default=1)
 p.add_argument('--framebuffer',type=lambda x:int(x,0),default=0x82000000)
 p.add_argument('--replay',action='store_true')
 p.add_argument('--window',action=argparse.BooleanOptionalAction,default=True)
 p.add_argument('--concat',action=argparse.BooleanOptionalAction,default=True)
 p.add_argument('--live-preview',action=argparse.BooleanOptionalAction,default=None,
                help='Independent camera preview and latest detection overlay (default for camera; off for replay)')
 p.add_argument('--firmware-manifest',type=Path,
                default=Path(__file__).resolve().parent.parent/'firmware_build_01/manifest.json')
 p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 live_preview=(not a.replay) if a.live_preview is None else a.live_preview
 _,words,m=make(a.package,a.frame_id,a.framebuffer,a.run_id,not a.replay,a.window,a.concat,live_preview)
 build=json.loads(a.firmware_manifest.read_text(encoding='utf8'))['build_id']
 if not isinstance(build,str) or len(build)!=16:raise ValueError('Invalid current firmware build ID')
 words[30:32]=[int(build[:8],16),int(build[8:],16)]
 a.out.write_bytes(struct.pack('<40I',*words))
 a.out.with_suffix('.json').write_text(json.dumps(dict(config_address=hex(CONFIG_ADDRESS),firmware_build_id=build,
   model_package_build_id=m['firmware_build_id'],
   words=[hex(x) for x in words],scope='CMOS2 single view configuration only; no execution evidence'),indent=2)+'\n')
if __name__=='__main__':main()
