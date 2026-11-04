"""Count physical comment/code lines and compare executable source tokens."""
from pathlib import Path
import ast
import hashlib
import io
import re
import tokenize


def scan_cstyle(text, verilog=False):
    """Keep strings intact; comments inside literals never count as comments."""
    lines=text.splitlines(keepends=True)
    if not lines:
        return [],[]
    kinds=[set() for _ in lines]
    tokens=[]
    i=line=0
    length=len(text)
    while i<length:
        ch=text[i]
        if ch.isspace():
            if ch=='\n':line+=1
            i+=1;continue
        if text.startswith('//',i):
            end=text.find('\n',i)
            if end<0:end=length
            kinds[line].add('comment');i=end;continue
        if text.startswith('/*',i):
            end=text.find('*/',i+2)
            if end<0:raise ValueError('Unterminated block comment')
            end+=2
            for part in text[i:end].splitlines(keepends=True):
                if part.strip():kinds[line].add('comment')
                if part.endswith('\n'):line+=1
            i=end;continue
        if ch=='"' or (ch=="'" and not verilog):
            quote=ch;j=i+1
            while j<length:
                if text[j]=='\\':j+=2;continue
                if text[j]==quote:j+=1;break
                j+=1
            token=text[i:j];tokens.append(token)
            for part in token.splitlines(keepends=True):
                if part.strip():kinds[line].add('code')
                if part.endswith('\n'):line+=1
            i=j;continue
        if verilog and ch=='\\':
            match=re.match(r'\\\S+',text[i:])
        else:
            match=re.match(r'[A-Za-z_$][A-Za-z0-9_$]*|(?:\d[\w\']*|\'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+)|===|!==|>>>|<<<|==|!=|<=|>=|&&|\|\||<<|>>|\+\+|--|\+=|-=|\*=|/=|::|->|=>|\*\*|##|\+:|-:|\S',text[i:])
        if not match:raise ValueError('Unrecognized source token')
        token=match.group(0);tokens.append(token);kinds[line].add('code');i+=len(token)
    return kinds,tokens


def scan_python(text):
    plain_lines=text.splitlines(keepends=True)
    kinds=[set() for _ in plain_lines]
    tokens=[]
    ignored={tokenize.ENCODING,tokenize.NL,tokenize.NEWLINE,tokenize.ENDMARKER}
    for token in tokenize.generate_tokens(io.StringIO(text).readline):
        if token.type==tokenize.COMMENT:
            kinds[token.start[0]-1].add('comment')
        elif token.type not in ignored and token.type not in (tokenize.INDENT,tokenize.DEDENT):
            tokens.append((token.type,token.string))
            for line in range(token.start[0]-1,min(token.end[0],len(kinds))):
                if plain_lines[line].strip():kinds[line].add('code')
    # The AST comparison below separately preserves the meaning of indentation.
    return kinds,tokens


def analyze(path):
    path=Path(path);text=path.read_text(encoding='utf-8-sig')
    if path.suffix=='.py':kinds,tokens=scan_python(text)
    else:kinds,tokens=scan_cstyle(text,verilog=path.suffix.lower() in ('.v','.sv','.vh','.svh'))
    code=sum('code' in x for x in kinds)
    comment=sum(x=={'comment'} for x in kinds)
    mixed=sum(x=={'comment','code'} for x in kinds)
    nonempty=code+comment
    return dict(code_lines=code,comment_lines=comment,mixed_lines=mixed,
                nonblank_lines=nonempty,blank_lines=len(kinds)-nonempty,
                comment_rate=comment/nonempty if nonempty else 0,
                token_sha256=hashlib.sha256(repr(tokens).encode('utf-8')).hexdigest(),tokens=tokens,kinds=kinds)


def equivalent(original,annotated):
    a=analyze(original);b=analyze(annotated)
    if a['tokens']!=b['tokens']:
        raise AssertionError('Executable tokens changed: '+str(annotated))
    if Path(original).suffix=='.py':
        assert ast.dump(ast.parse(Path(original).read_text(encoding='utf-8-sig')),include_attributes=False)==ast.dump(ast.parse(Path(annotated).read_text(encoding='utf-8-sig')),include_attributes=False)
    return a,b
