"""Read-only inspection of this project's own live Verilator process.
Never writes or suspends the process. Uses the exact generated C++ layout.
"""
from pathlib import Path
import argparse,ctypes as c,datetime,json,re,subprocess
import psutil
def main():
 ap=argparse.ArgumentParser();ap.add_argument('evidence',type=Path);ap.add_argument('pid',type=int);a=ap.parse_args();e=a.evidence.resolve();obj=e/'obj'
 expected=(obj/'mario_rtl.exe').resolve()
 if Path(psutil.Process(a.pid).exe()).resolve()!=expected:raise RuntimeError('Not the requested Mario RTL simulator')
 header=(obj/'Vtb_game_bringup___024root.h').read_text()
 names=['rst_n','frames_o','presented_o','active_fb_o']
 for name in re.findall(r'(?:CData|SData|IData|QData)/\*[^*]*\*/ ([A-Za-z0-9_]+);',header):
  if '__V' not in name and (('__DOT__periph__DOT__' in name) or any(name.endswith('__DOT__'+s) for s in ['architectural_pc','lsu_pc','lsu_state','rob_head','rob_count','periph_gnt_i','periph_rvalid_i','periph_addr_o','periph_rdata_i','publish_q','active_fb_q','i_state','d_state','retire0','retire1','cycles','csr_exception_pc'])):names.append(name)
 memory='tb_game_bringup__DOT__dut__DOT__u_ddr__DOT__mem';names.append(memory)
 code='#include "Vtb_game_bringup___024root.h"\n#include <cstddef>\n#include <cstdio>\nint main(){\n'
 for n in names:code+=f'printf("{n} %zu %zu\\n",offsetof(Vtb_game_bringup___024root,{n}),sizeof(((Vtb_game_bringup___024root*)0)->{n}));\n'
 code+='}\n';source=e/'inspect_layout.cpp';source.write_text(code)
 exe=e/'inspect_layout.exe';cmd=['C:/Users/user/mingw64/bin/g++.exe','-std=c++17','-I'+str(obj),'-IC:/tools/msys64/mingw64/share/verilator/include','-IC:/tools/msys64/mingw64/share/verilator/include/vltstd',str(source),'-o',str(exe)]
 p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(e/'inspect_layout_build.log').write_bytes(p.stdout);p.check_returncode()
 offsets={n:(int(o),int(s)) for n,o,s in (line.split() for line in subprocess.check_output([str(exe)],text=True).splitlines())}
 k=c.WinDLL('kernel32',use_last_error=True)
 k.OpenProcess.argtypes=[c.c_uint32,c.c_int,c.c_uint32];k.OpenProcess.restype=c.c_void_p
 k.ReadProcessMemory.argtypes=[c.c_void_p,c.c_void_p,c.c_void_p,c.c_size_t,c.POINTER(c.c_size_t)];k.ReadProcessMemory.restype=c.c_int
 k.VirtualQueryEx.argtypes=[c.c_void_p,c.c_void_p,c.c_void_p,c.c_size_t];k.VirtualQueryEx.restype=c.c_size_t
 k.CloseHandle.argtypes=[c.c_void_p]
 class MBI(c.Structure):_fields_=[('base',c.c_void_p),('allocation',c.c_void_p),('allocation_protect',c.c_uint32),('partition',c.c_uint16),('size',c.c_size_t),('state',c.c_uint32),('protect',c.c_uint32),('kind',c.c_uint32)]
 h=k.OpenProcess(0x410,False,a.pid)
 if not h:raise c.WinError(c.get_last_error())
 def read(addr,size):
  b=c.create_string_buffer(size);n=c.c_size_t()
  if not k.ReadProcessMemory(h,addr,b,size,c.byref(n)):raise c.WinError(c.get_last_error())
  return b.raw[:n.value]
 try:
  program=json.loads((e/'firmware.json').read_text())['program'];needle=Path(program['binary']).read_bytes()[:128]
  addr=0;root=None
  while addr<0x7fffffff0000:
   m=MBI()
   if not k.VirtualQueryEx(h,addr,c.byref(m),c.sizeof(m)):break
   if m.state==0x1000 and m.protect==4 and m.size>100*1024*1024:
    data=read(m.base,m.size);pos=data.find(needle)
    if pos>=0:root=m.base+pos-offsets[memory][0]-0x4000000;break
   addr=(m.base or 0)+m.size
  if root is None:raise RuntimeError('Simulator DDR image not located')
  if int.from_bytes(read(root+offsets['rst_n'][0],1),'little')!=1:raise RuntimeError('Root layout validation failed')
  values={n:hex(int.from_bytes(read(root+o,s),'little')) for n,(o,s) in offsets.items() if s<=8}
  record={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'pid':a.pid,'read_only':True,'root_address':hex(root),'values':values}
  out=e/('live_'+datetime.datetime.now().strftime('%H%M%S_%f')+'.json');out.write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2))
 finally:k.CloseHandle(h)
if __name__=='__main__':main()
