# 架构导读：make_cmos2_workflow_config。
# 主机侧工程工具，管理本文件定义的数据解析、检查或运行流程。
from pathlib import Path
import argparse,json,struct
from make_workflow_config import make as legacy_make
CONFIG_ADDRESS=0x80fff000
ID=0x31563243
# 接口 make，显式输入字段：package, frame_id, framebuffer, run_id, camera, window, concat, live_preview。
# 本函数调用入口包括 legacy_make, int, ValueError, struct.pack。
def make(package,frame_id,framebuffer,run_id=None,camera=True,window=False,concat=False,live_preview=False):
 _,words,m=legacy_make(package,frame_id,framebuffer,run_id)
 words[0]=ID;words[1]=1;words[21]=int(camera)
 # 按条件 window 选择后续流程，保留原有异常和退出分支。
 if window:words[19]|=0x04000000
 # 按条件 concat 选择后续流程，保留原有异常和退出分支。
 if concat:words[19]|=0x02000000
 words[32:40]=[2560,0x35363552,1280,720,1280,680,340,int(live_preview)]
 # 按条件 not 0 < frame_id < 2 ** 32 选择后续流程，保留原有异常和退出分支。
 if not 0<frame_id<2**32:raise ValueError('Nonzero uint32 frame ID required')
 # 按条件 live_preview and (not camera or frame_id >= 2 ** 31) 选择后续流程，保留原有异常和退出分支。
 if live_preview and (not camera or frame_id>=2**31):raise ValueError('Live preview requires a camera and 31-bit inference frame ID')
 if m['ddr_high_watermark']>=CONFIG_ADDRESS-0x80000000:raise ValueError('Configuration conflicts with model memory')
 return struct.pack('<40I',*words),words,m
# 接口 main，显式输入字段：无位置参数。
# 本函数调用入口包括 argparse.ArgumentParser, p.add_argument, p.parse_args, make, a.out.write_bytes。
def main():
 p=argparse.ArgumentParser();p.add_argument('--package',type=Path,required=True)
 p.add_argument('--frame-id',type=int,default=1);p.add_argument('--run-id',type=int,default=1)
 p.add_argument('--framebuffer',type=lambda x:int(x,0),default=0x82000000)
 p.add_argument('--replay',action='store_true');p.add_argument('--window',action='store_true');p.add_argument('--concat',action='store_true');p.add_argument('--live-preview',action='store_true');p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 raw,words,m=make(a.package,a.frame_id,a.framebuffer,a.run_id,not a.replay,a.window,a.concat,a.live_preview);a.out.write_bytes(raw)
 a.out.with_suffix('.json').write_text(json.dumps(dict(config_address=hex(CONFIG_ADDRESS),firmware_build_id=m['firmware_build_id'],
   words=[hex(x) for x in words],scope='CMOS2 single view configuration only; no execution evidence'),indent=2)+'\n')
if __name__=='__main__':main()
