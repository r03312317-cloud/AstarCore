from pathlib import Path
import hashlib,json,sys
r=Path(__file__).resolve().parent;m=json.loads((r/"SOURCE_FILES_SHA256.json").read_text(encoding="utf-8"));bad=[]
for a in m["files"]:
 p=r/a["path"]
 if not p.is_file():bad.append(a["path"]);continue
 h=hashlib.sha256()
 with p.open("rb") as f:
  for b in iter(lambda:f.read(1048576),b""):h.update(b)
 if p.stat().st_size!=a["bytes"] or h.hexdigest()!=a["sha256"]:bad.append(a["path"])
print("PASS: "+str(len(m["files"]))+" files verified" if not bad else "FAIL\n"+"\n".join(bad));sys.exit(bool(bad))
