"""Archive the independently reproducible Mario project and checked evidence.
Does not acquire or program the FPGA. Reopens ZIP and verifies every hash.
"""
from pathlib import Path
import datetime,hashlib,json,subprocess,sys,zipfile
from build_mario import ROOT
from board_artifacts import qualify
def sha(data):return hashlib.sha256(data).hexdigest()
def main():
 q=qualify();stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f');project=ROOT.name;name=project+'_PREBOARD_'+stamp
 evidence=ROOT/'build/releases'/name;evidence.mkdir(parents=True)
 (ROOT/'build/QUALIFICATION.json').write_text(json.dumps(q,indent=2)+'\n')
 files=set()
 for folder in ['soc','boot','port','src','upstream','tools','tests','docs','platform']:
  for p in (ROOT/folder).rglob('*'):
   rel=p.relative_to(ROOT)
   if p.is_file() and 'build' not in rel.parts and '__pycache__' not in rel.parts and p.suffix!='.pyc':files.add(p)
 for n in ['README.md','THIRD_PARTY.md','build/LATEST_MARIO.json','build/LATEST_HOST_GAMEPLAY.json','build/LATEST_RTL.json','build/LATEST_RENDER.json','build/LATEST_VIDEO_QUEUE.json','build/QUALIFICATION.json']:files.add(ROOT/n)
 native=json.loads((ROOT/'build/LATEST_HOST_GAMEPLAY.json').read_text())
 folders=[Path(q['binary']).parent,Path(q['native_gameplay_evidence']),ROOT/'build'/Path(q['mario_rtl']['evidence']).name,Path(q['renderer_evidence']),Path(q['video_queue_evidence'])]
 tested_program=json.loads((folders[2]/'firmware.json').read_text())['program']
 tested_build=ROOT/'build'/Path(tested_program['binary']).parent.name
 if tested_build not in folders:folders.append(tested_build)
 for folder in folders:
  for p in folder.rglob('*'):
   rel=p.relative_to(folder)
   if p.is_file() and '__pycache__' not in rel.parts and ('obj' not in rel.parts or p.name=='mario_rtl.exe'):files.add(p)
 manifest={'created_local':datetime.datetime.now().astimezone().isoformat(),'status':'OFFLINE_VALIDATED_BOARD_TEST_PENDING','physical_board_verified':False,'firmware_sha256':q['binary_sha256'],'files':{}}
 dest=ROOT.parent/'deliverables';dest.mkdir(exist_ok=True);archive=dest/(name+'.zip')
 with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for p in sorted(files):
   rel=p.relative_to(ROOT).as_posix();data=p.read_bytes();manifest['files'][rel]={'sha256':sha(data),'bytes':len(data)};z.writestr(project+'/'+rel,data)
  z.writestr(project+'/PACKAGE_MANIFEST.json',json.dumps(manifest,indent=2)+'\n')
 verify=evidence/'verify'
 with zipfile.ZipFile(archive) as z:
  if z.testzip() is not None:raise RuntimeError('ZIP CRC error')
  for rel,item in manifest['files'].items():
   data=z.read(project+'/'+rel)
   if len(data)!=item['bytes'] or sha(data)!=item['sha256']:raise RuntimeError('Archive hash mismatch: '+rel)
  z.extractall(verify)
 extracted=verify/project
 p=subprocess.run([sys.executable,'-B','-X','utf8',str(extracted/'tools/program_mario.py'),'--qualify-only'],cwd=extracted,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (evidence/'extracted_qualification.log').write_bytes(p.stdout)
 if p.returncode:raise RuntimeError('Extracted project qualification failed')
 result={'status':manifest['status'],'archive':str(archive),'archive_bytes':archive.stat().st_size,'archive_sha256':sha(archive.read_bytes()),'files':len(files),'crc_and_all_payload_sha256_verified':True,'extracted_project_qualification_passed':True,'physical_board_verified':False,'evidence':str(evidence)}
 archive.with_suffix('.zip.sha256').write_text(result['archive_sha256']+'  '+archive.name+'\n')
 (evidence/'result.json').write_text(json.dumps(result,indent=2)+'\n');(ROOT/'build/LATEST_RELEASE.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':main()
