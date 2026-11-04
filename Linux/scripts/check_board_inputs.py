#!/usr/bin/env python3
"""Fail-closed physical-input checker. Does not invoke PDS or program hardware."""
import argparse,hashlib,json,pathlib,sys
REQUIRED=['ddr_rtl','ddr_constraints','pin_constraints','clock_constraints','tmds_rtl','board_top','pds_project']
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest',type=pathlib.Path,required=True)
    p.add_argument('--report',type=pathlib.Path)
    a=p.parse_args();errors=[];found=[]
    try:
        data=json.loads(a.manifest.read_text())
        if not isinstance(data,dict):raise ValueError('manifest must be a JSON object')
    except (OSError,ValueError) as e:
        print(f'BLOCKED: cannot read manifest: {e}');return 2
    root=a.manifest.resolve().parent
    for key in REQUIRED:
        entries=data.get(key)
        if isinstance(entries,str):entries=[entries]
        if not isinstance(entries,list) or not entries:
            errors.append(f'{key}: absent');continue
        for entry in entries:
            if not isinstance(entry,str) or not entry.strip():errors.append(f'{key}: invalid path');continue
            f=pathlib.Path(entry);f=f if f.is_absolute() else root/f
            if not f.is_file():errors.append(f'{key}: file missing: {entry}');continue
            found.append({'kind':key,'path':str(f.resolve()),'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
    result={'status':'BLOCKED' if errors else 'INPUTS_EXIST_ONLY','errors':errors,'files':found,
            'pds_run':False,'timing_pass':False,'bitstream_generated':False,'board_validated':False}
    if a.report:
        a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(result,indent=2)+'\n')
    print('BLOCKED: missing actual board inputs: '+', '.join(errors) if errors else 'Input files exist only; this is NOT PDS or timing acceptance.')
    return 2 if errors else 0
if __name__=='__main__':sys.exit(main())
