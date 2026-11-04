"""Recompute the disclosed source comment metrics; read-only, no hardware."""
from pathlib import Path
import ast,io,json,re,token,tokenize

def language(path):
    if path.suffix == '.py':return 'python'
    if path.suffix in ('.sh','.tcl','.fdc') or path.read_bytes().startswith(b'#!'):return 'hash'
    return 'c'


def c_scan(text):
    """Keep separate code/comment occupancy, ignoring delimiters in strings.

    This scanner preserves token boundaries for Verilog/C/DTS including escaped
    identifiers.  Nonempty comment text counts; delimiter-only separators do not.
    Comments containing PDS/Verilator directives remain in equivalence tokens.
    """
    code, comment, items, directives = set(), set(), [], []
    i=0; line=1; n=len(text)
    while i<n:
        ch=text[i]
        if ch.isspace():line+=ch=='\n';i+=1;continue
        if text.startswith('//',i) or text.startswith('/*',i):
            start_line=line;is_line=text.startswith('//',i)
            end=text.find('\n',i+2) if is_line else text.find('*/',i+2)
            end=n if end<0 else end+(0 if is_line else 2)
            raw=text[i:end]
            body=raw[2:] if is_line else raw[2:-2]
            for offset,row in enumerate(body.split('\n')):
                if re.search(r'[\w\u3400-\u9fff]',row):comment.add(start_line+offset)
            if re.search(r'\b(synthesis|synopsys|verilator|pragma|syn_\w+|translate_off|translate_on)\b',body,re.I):
                directives.append(raw)
            line+=raw.count('\n');i=end;continue
        start=i
        if ch=='"':
            i+=1
            while i<n:
                if text[i]=='\\':i+=2
                elif text[i]=='"':i+=1;break
                else:i+=1
        elif ch=='\\':
            i+=1
            while i<n and not text[i].isspace():i+=1
        elif ch.isalnum() or ch in '_$':
            i+=1
            while i<n and (text[i].isalnum() or text[i] in '_$'):i+=1
        else:
            # Longest operators are retained; unlike whitespace removal this
            # detects a comment inserted between '+' and '+' or other tokens.
            op=next((x for x in ('===','!==','>>>','<<<','<<=','>>=','::','<=','>=','==','!=','&&','||','<<','>>','++','--','+=','-=','*=','/=','->','=>','~^','^~','**','+:','-:') if text.startswith(x,i)),None)
            i+=len(op) if op else 1
        raw=text[start:i];items.append(raw)
        for k,row in enumerate(raw.split('\n')):
            if row.strip():code.add(line+k)
        line+=raw.count('\n')
    return code,comment,items,directives


def py_scan(text):
    code,comment,items=set(),set(),[]
    for t in tokenize.generate_tokens(io.StringIO(text).readline):
        if t.type == tokenize.COMMENT:
            if t.start[0]!=1 or not t.string.startswith('#!'):
                if re.search(r'\w',t.string[1:]):comment.add(t.start[0])
        elif t.type not in (tokenize.NL,tokenize.NEWLINE,tokenize.COMMENT,tokenize.ENCODING,tokenize.ENDMARKER,tokenize.INDENT,tokenize.DEDENT):
            items.append((t.type,t.string))
            code.update(range(t.start[0],t.end[0]+1))
    return code,comment,items,[]


def hash_scan(text):
    # Metrics only for shell/Tcl.  Annotation integrity uses exact insertion
    # recovery, and annotations are restricted to safe prologue positions.
    code,comment=set(),set()
    for i,row in enumerate(text.splitlines(),1):
        if not row.strip():continue
        if row.lstrip().startswith('#') and not row.startswith('#!'):
            if re.search(r'\w',row.lstrip()[1:]):comment.add(i)
        else:code.add(i)
    return code,comment,[],[]


def metrics(path, text=None):
    if text is None:text=path.read_text(encoding='utf-8-sig')
    lang=language(path)
    c,m,_,_=({'python':py_scan,'hash':hash_scan,'c':c_scan}[lang])(text)
    # A mixed code/comment line is one nonempty line in the denominator and
    # counts as a comment-bearing line in the numerator. Empty /* */ is ignored.
    total=len(c|m)
    return {'code_lines':len(c),'comment_lines':len(m),'mixed_lines':len(c&m),
            'nonempty_source_lines':total,'comment_percent':round(100*len(m)/total,4) if total else 0}


def aggregate(rows):
    result={}
    for name in sorted({x['group'] for x in rows}|{'project_production_total'}):
        subset=[r for r in rows if r['group']==name or name=='project_production_total' and r['group'].startswith('project_')]
        sums={k:sum(r[k] for r in subset) for k in ('code_lines','comment_lines','mixed_lines','nonempty_source_lines')}
        sums.update(files=len(subset),comment_percent=round(100*sums['comment_lines']/sums['nonempty_source_lines'],4) if sums['nonempty_source_lines'] else 0)
        result[name]=sums
    return result


def measure(root):
    expected=json.loads((root/'documentation/comment_metrics.json').read_text(encoding='utf-8'))
    rows=[]
    for record in expected['files']:
        p=root/record['path']
        rows.append({'path':record['path'],'group':record['group'],**metrics(p)})
    return {'files':rows,'groups':aggregate(rows)}

if __name__=='__main__':
    root=Path(__file__).resolve().parents[1]
    print(json.dumps(measure(root)['groups'],ensure_ascii=True,indent=2))
