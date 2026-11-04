from pathlib import Path
import re,json,hashlib,sys,unicodedata
sys.path.insert(0,str(Path(__file__).resolve().parent))
from annotation_spec import MODULES,FUNCTIONS,PARAMETERS,SECTIONS,PROTOCOLS
r=Path(__file__).resolve().parents[1]

def note_lines(lines):
    result=[]
    for line in lines:
        m=re.match(r'(\s*)//\s?(.*)',line.rstrip('\n'));assert m,line
        prefix=m[1]+'// ';body=m[2]
        limit=80-len(prefix)
        while body:
            col=0;end=0
            for pos,ch in enumerate(body):
                col+=2 if unicodedata.east_asian_width(ch) in ['W','F'] else 1
                if col>limit:break
                end=pos+1
            if end>=len(body):result.append(prefix+body+'\n');break
            cut=end
            for j in range(end-1,max(end//2,0),-1):
                if body[j] in '，。；、 ：,; ':cut=j+1;break
            result.append(prefix+body[:cut].rstrip()+'\n');body=body[cut:].lstrip()
    return result

def code_tokens(s):
    tokens=re.findall(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/|\\[^\s]+|[A-Za-z_$][\w$]*|[^\s]',s,re.S)
    return [t for t in tokens if not t.startswith(('//','/*'))]
def comment_stats(s):
    state=False;comment_only=code=mixed=blank=0
    for line in s.splitlines():
        i=0;has_c=False;has_code=False;quote=False
        while i<len(line):
            if state:
                has_c=True;j=line.find('*/',i)
                if j<0:break
                i=j+2;state=False;continue
            if line[i:i+2]=='//':has_c=True;break
            if line[i:i+2]=='/*':state=True;has_c=True;i+=2;continue
            if line[i]=='"':
                has_code=True;i+=1
                while i<len(line):
                    if line[i]=='\\':i+=2;continue
                    if line[i]=='"':i+=1;break
                    i+=1
                continue
            if not line[i].isspace():has_code=True
            i+=1
        if has_c and has_code:mixed+=1
        elif has_c:comment_only+=1
        elif has_code:code+=1
        else:blank+=1
    nonblank=code+mixed+comment_only
    return {'physical_lines':len(s.splitlines()),'nonblank_lines':nonblank,'code_only_lines':code,'comment_only_lines':comment_only,'mixed_code_comment_lines':mixed,'blank_lines':blank,
        'comment_only_percent_of_nonblank':100*comment_only/nonblank if nonblank else 0,
        'comment_bearing_percent_of_nonblank':100*(comment_only+mixed)/nonblank if nonblank else 0}

def port_meaning(module,line):
    low=line.lower()
    if 'clk' in low or 'reset' in low or 'cancel' in low:
        return '时钟/复位/取消控制。同步状态在指定边界更新；cancel清除所有权而非创造成功响应。'
    if 'debug_' in low or 'trace_' in low:return '观测接口。有效门控由对应assign决定，不作为功能事务接收条件。'
    if any(x in low for x in ['request_valid','request_ready','response_valid','response_ready','u_valid','u_ready','m_valid','m_ready']):
        return '事务握手。valid与对应ready同边界才接收；背压期间有主状态的载荷必须保持。'
    if any(x in low for x in ['gnt','rvalid','rready','bvalid','req_o','req_i']):
        return '外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；数据变化不等于完成。'
    if 'train' in low:return '按提交顺序的预测训练或其信用。只采纳有资格的已提交控制流，不把推测执行当训练完成。'
    if 'history' in low or 'context' in low:return '预测与恢复上下文。保存预测时信息，恢复和训练必须使用对应指令所有者。'
    if 'broadcast' in low:return '真实完成旁路的valid、标签或数值。必须同时验证标签和valid，未就绪数值不可使用。'
    if any(x in low for x in ['occupied','eligible','ready','issue_allowed','mask','ages','older']):
        return '队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。'
    if any(x in low for x in ['error','err_i','fault','illegal']):return '错误或非法资格。需随相应有效指令/事务传播，最终在精确提交边界处理。'
    if 'irq_' in low or 'mtime' in low:return '中断或时间输入。板级是否真实连接需另查system实例，通用端口不等于实板覆盖。'
    if any(x in low for x in ['pc','prediction','target','redirect']):return '控制流地址或恢复信息。顺序地址、预测地址和实际恢复地址具有不同来源，不能互换。'
    if any(x in low for x in ['source','destination','instruction','csr','operation']):return '指令编码、寄存器类别或控制字段。静态译码仅给建议，实际副作用由核心有效所有权控制。'
    if any(x in low for x in ['address','addr','wstrb','wdata','rdata','size','be_o','write']):
        return '访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。'
    if any(x in low for x in ['token','tag']):return '生产者或事务标签。只关联所有者，不代表算术值，也不能单凭标签判断已完成。'
    if any(x in low for x in ['left','right','result','value','product','payload']):return '数据计算或选择载荷。输入数据与有效许可分开，未拥有请求的数据不产生架构副作用。'
    if 'retire' in low:return '按程序顺序的提交观测；组合资格与寄存位图相差一个边界，分析时保留采样相位。'
    if 'uart' in low or 'tx' in low or 'rx' in low:return 'UART串行通信或接收发送状态；串口传输耗时不作为CoreMark算法计时分母。'
    if any(x in low for x in ['occupancy','count','pop']):return '有效数量或消费数量。索引编码只有对应有效/计数许可时才表示存活所有者。'
    if 'fence' in low or 'maintenance' in low:return 'Cache维护请求或忙状态。脏行写回及外部确认完成前不能提前结束维护。'
    if 'done' in low or 'exit_code' in low:return '程序结束观测及退出码。需结合真实UART和CRC判断运行是否成功。'
    return MODULES.get(module,'').splitlines()[0]

inventory=[];rows=[];unmapped_functions=[];anchor_found=[]
for src in sorted((r/'original').rglob('*.v')):
    rel=src.relative_to(r/'original');text=src.read_text();lines=text.splitlines(keepends=True)
    if src.name=='rv32_board_pll_130.v':
        (r/rel).write_bytes(src.read_bytes())
        pll_name='rv32_board_pll_130';pll_line=text[:text.index('module '+pll_name)].count('\n')+1
        inventory.append({'module':pll_name,'file':rel.as_posix(),'original_line':pll_line,'annotated_line':pll_line,'purpose':MODULES[pll_name].splitlines()[0],'notes':MODULES[pll_name].splitlines(),'generated_vendor_reference':True})
        rows.append({'file':rel.as_posix(),'generated_vendor_reference':True,'before':comment_stats(text),'after':comment_stats(text),'noncomment_token_equal':True})
        continue
    out=[];module='';header=False;func_depth=False
    specs=SECTIONS.get(src.name,[]);used=set();module_starts=[]
    for i,line in enumerate(lines):
        m=re.match(r'\s*module\s+(\w+)',line)
        if m:
            module=m[1];assert module in MODULES,module
            facts=MODULES[module].splitlines()
            out+=note_lines(['// 中文架构说明  与上次130MHz实板源保持同一逻辑版本\n'])
            out += note_lines(['// '+fact+'\n' for fact in facts])
            if module in PROTOCOLS:
                out+=note_lines(['// 接口契约与阅读示例\n']+['// '+fact+'\n' for fact in PROTOCOLS[module].splitlines()])
            inventory.append({'module':module,'file':rel.as_posix(),'original_line':i+1,'annotated_line':len(out)+1,'purpose':facts[0],'notes':facts})
            header=True
        for j,(anchor,notes) in enumerate(specs):
            if j not in used and anchor in line:
                # Keep the original source untouched in original/, including all synthesis directives.
                out+=note_lines(['    // '+t+'\n' for t in notes]);used.add(j)
                anchor_found.append({'file':rel.as_posix(),'anchor':anchor,'original_line':i+1})
        f=re.match(r'\s*(function|task)\s+(?:\[[^\]]+\]\s+)?(?:(?:integer|automatic)\s+)?(\w+)',line)
        if f:
            name=f[2];desc=FUNCTIONS.get(name)
            if not desc:unmapped_functions.append((src.name,name));desc='按调用处定义执行组合字段处理，具体输入和更新对象见紧随的声明。'
            out+=note_lines(['    // '+('函数 ' if f[1]=='function' else '任务 ')+name+'：'+desc+'\n'])
            sig=[]
            for nxt in lines[i+1:i+14]:
                if re.search(r'\b(begin|endfunction|endtask)\b',nxt):break
                if re.match(r'\s*input\b',nxt):sig.append(nxt.strip().rstrip(';'))
            if sig:out+=note_lines(['    // 调用字段：'+'；'.join(sig)+'。\n'])
            if f[1]=='function':out+=note_lines(['    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。\n'])
            else:out+=note_lines(['    // 本任务写私有执行/分配载荷，实际valid、重命名和计数更新由主状态块负责。\n'])
        if header and not m:
            p=re.search(r'\bparameter\s+(?:\[[^\]]+\]\s+)?(\w+)',line)
            if p:
                name=p[1];desc=PARAMETERS.get(name)
                if desc:out+=note_lines(['    // 参数 '+name+'：'+desc+'\n'])
            if re.match(r'\s*(input|output|inout)\b',line):
                decl=re.sub(r'/\*.*?\*/','',re.sub(r'//.*','',line)).strip().rstrip(',;')
                out+=note_lines(['    // 接口字段：'+decl+'。\n','    // '+port_meaning(module,decl)+'\n'])
        out.append(line if line.endswith('\n') else line+'\n')
        if header and (');' in line):header=False
    annotated=''.join(out)
    assert code_tokens(text)==code_tokens(annotated),rel
    directives=lambda s:[x for x in re.findall(r'/\*.*?\*/|//[^\n]*',s,re.S) if re.search(r'synthesis|syn_|translate_',x)]
    assert directives(text)==directives(annotated),('synthesis comments',rel,[x for x in directives(annotated) if x not in directives(text)])
    (r/rel).write_text(annotated,encoding='utf-8')
    rows.append({'file':rel.as_posix(),'generated_vendor_reference':False,'before':comment_stats(text),'after':comment_stats(annotated),
        'noncomment_token_equal':True,'synthesis_directives_preserved':True,'original_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'annotated_sha256':hashlib.sha256((r/rel).read_bytes()).hexdigest(),
        'unmatched_optional_anchors':[a for j,(a,_) in enumerate(specs) if j not in used]})
assert not unmapped_functions,unmapped_functions
rtl=[x for x in rows if x['file'].startswith('rtl/')]
def aggregate(key):
    n=sum(x[key]['nonblank_lines'] for x in rtl);c=sum(x[key]['comment_only_lines'] for x in rtl);m=sum(x[key]['mixed_code_comment_lines'] for x in rtl)
    return {'nonblank_lines':n,'comment_only_lines':c,'mixed_comment_lines':m,'comment_only_percent':100*c/n,'comment_bearing_percent':100*(c+m)/n}
report={'definition':'Comment-only lines / nonblank physical lines; mixed code/comment lines reported separately. No count target is padded with blank or repeated banner lines. Generated PLL is excluded from architecture RTL ratio.',
 'rtl_before':aggregate('before'),'rtl_after':aggregate('after'),'files':rows,'all_noncomment_tokens_identical':True,'all_original_synthesis_directives_preserved':True}
(r/'verification/comment_and_equivalence.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
(r/'docs/module_inventory.json').write_text(json.dumps(inventory,ensure_ascii=False,indent=2),encoding='utf-8')
(r/'verification/annotation_anchors.json').write_text(json.dumps(anchor_found,ensure_ascii=False,indent=2),encoding='utf-8')
(r/'rtl_filelist.f').write_text('\n'.join('rtl/'+p.name for p in sorted((r/'rtl').glob('*.v')))+'\n')
(r/'board_filelist.f').write_text((r/'rtl_filelist.f').read_text()+'\n'.join('board/'+p.name for p in sorted((r/'board').glob('*.v')))+'\n')
print(json.dumps({'before':report['rtl_before'],'after':report['rtl_after'],'modules':len(inventory),'unmatched_anchors':{x['file']:x['unmatched_optional_anchors'] for x in rows if x.get('unmatched_optional_anchors')}},ensure_ascii=False,indent=2))
