from pathlib import Path
import json,re,hashlib,zipfile,argparse,collections,xml.etree.ElementTree as ET
r=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def tokens(s):return [x for x in re.findall(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/|\\[^\s]+|[A-Za-z_$][\w$]*|[^\s]',s,re.S) if not x.startswith(('//','/*'))]
identity=json.loads((r/'evidence/source_identity.json').read_text(encoding='utf-8'))
checked=[]
for oldpath,h in identity['source_hashes'].items():
 rel=oldpath.replace('\\','/').removeprefix('snapshot/')
 a=r/'original'/rel;b=r/rel
 assert a.exists() and b.exists()
 assert sha(a)==h,rel
 src=a.read_text(encoding='utf-8');new=b.read_text(encoding='utf-8')
 assert tokens(src)==tokens(new),rel
 syn=lambda text:[x for x in re.findall(r'/\*.*?\*/|//[^\n]*',text,re.S) if re.search('synthesis|syn_|translate_',x)]
 assert syn(src)==syn(new),rel
 checked.append({'file':rel,'original_sha256':h,'annotated_sha256':sha(b),'tokens_equal':True,'synthesis_comments_equal':True})
mods=json.loads((r/'docs/module_inventory.json').read_text(encoding='utf-8'))
for m in mods:
 lines=(r/m['file']).read_text(encoding='utf-8').splitlines()
 assert re.match(r'\s*module\s+'+re.escape(m['module'])+r'\b',lines[m['annotated_line']-1]),m
assert len(mods)==31
assert sha(r/'implementation_reference/last_board_130MHz.sbit')=='eef99a0318d65129ced86535464fbe26d7210ae82dcfdf9a2279f77037235aef'
profile=json.loads((r/'analysis/algorithm_summary.json').read_text(encoding='utf-8'))
assert profile['retired']==1994683 and profile['measured_cycles']==1342928
assert all(profile['validation'].values())
assert sum(x['head_owned_cycles'] for x in profile['cohorts'])==1342928
assert sum(x['retired_instructions_by_exact_pc'] for x in profile['cohorts'])==1994683
assert json.loads((r/'verification/lint_result.json').read_text(encoding='utf-8'))['exit_code']==0
with zipfile.ZipFile(r/'docs/RV32_CPU架构与CoreMark性能分析.docx') as z:
 assert z.testzip() is None
 for name in ['word/document.xml','word/styles.xml']:
  root=ET.fromstring(z.read(name));assert not list(root.iter('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}pBdr'))
doc=json.loads((r/'docs/report_content.json').read_text(encoding='utf-8'))
assert len(doc['pages'])==18
result={'passed':True,'rtl_and_board_files':len(checked),'modules_documented':len(mods),'original_hash_and_noncomment_token_checks':checked,
 'physical_bitstream_identity_matches':True,'algorithm_cycle_and_retirement_sums_match':True,'docx_zip_valid':True,'document_sections':18,
 'comment_statistics':json.loads((r/'verification/comment_and_equivalence.json').read_text(encoding='utf-8'))['rtl_after']}
parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
if args.out:args.out.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='original_hash_and_noncomment_token_checks'},ensure_ascii=True,indent=2))
