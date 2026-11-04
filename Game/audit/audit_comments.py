"""Audit production source comments and exact recovery of the accepted originals.
Uses Pygments only to classify source, comments and compiler directives. Build
artifacts, ROM byte arrays, vendor IP, test fixtures and historical mirrors are
listed explicitly outside the production architecture metric.
"""
from pathlib import Path
import argparse,hashlib,json,re,zipfile
from pygments import lex
from pygments.lexers import VerilogLexer,SystemVerilogLexer,CLexer
from pygments.token import Token
ROOT=Path(__file__).resolve().parents[1]

def decode(data):
 for encoding in ('utf-8','gb18030'):
  try:return data.decode(encoding),encoding
  except UnicodeDecodeError:pass
 raise ValueError('Unsupported source encoding')

def is_comment(token):
 return token in Token.Comment.Single or token in Token.Comment.Multiline or token in Token.Comment.Special or token==Token.Comment

def analyze(data,name):
 source,_=decode(data);flags=[[False,False] for _ in range(source.count('\n')+2)]
 lexer=SystemVerilogLexer() if name.endswith('.sv') else VerilogLexer() if name.endswith('.v') else CLexer()
 line=0;code_tokens=[]
 for token,value in lex(source,lexer):
  comment=is_comment(token)
  pragma=comment and bool(re.match(r'^(?://|/\*)\s*(?:synthesis|synopsys|verilator|(?:pragma\s+)?translate_(?:off|on))\b',value,re.I))
  if (not comment or pragma) and not value.isspace():code_tokens.append((str(token),value))
  for i,part in enumerate(value.split('\n')):
   if i:line+=1
   if part.strip():flags[line][0 if comment else 1]=True
 pure=sum(c and not code for c,code in flags);code=sum(code for c,code in flags);mixed=sum(c and code for c,code in flags)
 return {'comment_only_lines':pure,'code_lines_including_mixed':code,'mixed_comment_code_lines':mixed,'nonblank_lines':pure+code,'comment_ratio':pure/(pure+code) if pure+code else 0,'tokens_sha256':hashlib.sha256(json.dumps(code_tokens,ensure_ascii=False).encode()).hexdigest()}

def original_from_annotated(data):
 return b''.join(line for line in data.splitlines(keepends=True) if not re.match(rb'^\s*(?:// \[ARCH\]|/\* \[ARCH\])',line))

def main():
 p=argparse.ArgumentParser();p.add_argument('--verify',action='store_true');args=p.parse_args()
 scope=json.loads((ROOT/'audit/SOURCE_SCOPE.json').read_text());files={};totals={}
 with zipfile.ZipFile(ROOT/'baseline/original_preboard.zip') as archive:
  for group,names in [('hardware',scope['hardware_rtl']),('firmware',scope['firmware_source'])]:
   count={'files':len(names),'comment_only_lines':0,'code_lines_including_mixed':0,'mixed_comment_code_lines':0}
   for name in names:
    original=archive.read('rv32_soc_Mario_V03/'+name);current=(ROOT/'source'/name).read_bytes()
    before=analyze(original,name);after=analyze(current,name)
    exact=original_from_annotated(current)==original
    token_equal=before['tokens_sha256']==after['tokens_sha256']
    if not exact or not token_equal:raise RuntimeError('Executable source or compiler directive changed: '+name)
    files[name]={'group':group,'original_sha256':hashlib.sha256(original).hexdigest(),'annotated_sha256':hashlib.sha256(current).hexdigest(),'exact_original_recovery':exact,'code_tokens_and_synthesis_directives_equal':token_equal,'before':before,'after':after}
    for key in ('comment_only_lines','code_lines_including_mixed','mixed_comment_code_lines'):count[key]+=after[key]
   count['comment_ratio']=count['comment_only_lines']/(count['comment_only_lines']+count['code_lines_including_mixed']);totals[group]=count
 all_counts={key:sum(g[key] for g in totals.values()) for key in ('files','comment_only_lines','code_lines_including_mixed','mixed_comment_code_lines')}
 all_counts['comment_ratio']=all_counts['comment_only_lines']/(all_counts['comment_only_lines']+all_counts['code_lines_including_mixed']);totals['all_production_source']=all_counts
 report={'metric':'comment-only physical lines / (comment-only lines + code lines), excluding blank lines; mixed lines count as code','compiler_directives_are_code':True,'synthesis_pragma_comments_preserved_in_token_audit':True,'scope':'audit/SOURCE_SCOPE.json','all_files_recover_original_bytes':True,'all_code_tokens_and_compiler_pragmas_equal':True,'totals':totals,'files':files}
 if args.verify:
  for group in ('hardware','firmware','all_production_source'):
   if not .29<=totals[group]['comment_ratio']<=.31:raise RuntimeError('Comment ratio outside 29-31%: '+group)
 (ROOT/'audit/COMMENT_AUDIT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(totals,indent=2))
if __name__=='__main__':main()
