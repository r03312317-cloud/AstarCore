from pathlib import Path
import os,json,re,hashlib,collections
r=Path(__file__).resolve().parents[1]
os.environ['MPLCONFIGDIR']=str(r/'analysis/mpl_cache')
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

v=json.loads((r/'analysis/profile/run/validation.json').read_text())
assert v['exit_code']==0 and v['same_uart_as_previous_exact_rtl'] and v['serial_matches_accepted']
d=pd.read_csv(r/'analysis/profile/run/algorithm_cycles.csv',dtype=np.uint32)
assert len(d)==1342928
symbols=[]
for line in (r/'analysis/performance10_symbols.txt').read_text().splitlines():
 m=re.fullmatch(r'([0-9a-f]+) ([0-9a-f]+) [tT] (.+)',line.strip())
 if m and int(m[2],16):symbols.append({'start':int(m[1],16),'size':int(m[2],16),'name':m[3]})
by_start={}
for x in symbols:by_start.setdefault(x['start'],[]).append(x)
sym=sorted([{'start':k,'size':max(x['size'] for x in a),'name':'/'.join(x['name'] for x in a)} for k,a in by_start.items()],key=lambda x:x['start'])
starts=np.array([x['start'] for x in sym],dtype=np.uint32)
ends=np.array([x['start']+x['size'] for x in sym],dtype=np.uint64)
names=np.array([x['name'] for x in sym],dtype=object)
def lookup(pcs):
 a=np.asarray(pcs,dtype=np.uint32);idx=np.searchsorted(starts,a,side='right')-1
 assert (idx>=0).all()
 assert (a<ends[idx]).all(),np.unique(a[~(a<ends[idx])])
 return names[idx]
def group(name):
 if 'matrix' in name:return '矩阵'
 if name.startswith(('core_bench_state','core_state_')):return '状态机'
 if name.startswith(('core_bench_list','core_list_','cmp_','calc_func','copy_info')):return '链表'
 if name.startswith(('crc','crcu')):return 'CRC'
 return '驱动与计时'

program=np.frombuffer((r/'software/builds/performance10/firmware.bin').read_bytes(),dtype='<u4')
base=0x10000000
for prefix,mask in [('head',d.rob_count>0),('second',d.retire1_raw>0),('ex0',d.ex_valid0>0),('ex1',d.ex_valid1>0)]:
 pc_col={'ex0':'ex_pc0','ex1':'ex_pc1'}.get(prefix,prefix+'_pc')
 ins_col={'ex0':'ex_instruction0','ex1':'ex_instruction1'}.get(prefix,prefix+'_instruction')
 pcs=d.loc[mask,pc_col].to_numpy()
 assert (pcs%4==0).all() and (pcs>=base).all()
 assert np.array_equal(program[(pcs-base)//4],d.loc[mask,ins_col].to_numpy()),prefix

head_names=np.full(len(d),'ROB为空',dtype=object)
live=d.rob_count>0
head_names[live]=lookup(d.loc[live,'head_pc'])
d['head_function']=head_names
d['head_group']=[group(x) if x!='ROB为空' else x for x in head_names]
d['issue_count']=d.issue0_accept+d.issue1_accept
d['retire_count']=d.retire0_raw+d.retire1_raw
d['dual_issue']=(d.issue_count==2).astype(np.uint32)
d['dual_retire']=(d.retire_count==2).astype(np.uint32)
pcs=np.r_[d.loc[d.retire0_raw>0,'head_pc'].to_numpy(),d.loc[d.retire1_raw>0,'second_pc'].to_numpy()]
ins=np.r_[d.loc[d.retire0_raw>0,'head_instruction'].to_numpy(),d.loc[d.retire1_raw>0,'second_instruction'].to_numpy()]
ret=pd.DataFrame({'pc':pcs,'instruction':ins,'function':lookup(pcs)})
ret['group']=[group(x) for x in ret.function]
assert len(ret)==1994683
def kind(w):
 op=w&127; f3=(w>>12)&7;f7=w>>25
 if op==3:return 'Load'
 if op==35:return 'Store'
 if op==99:return '条件分支'
 if op in [103,111]:return '跳转调用返回'
 if op==51 and f7==1:return 'MUL低位' if f3==0 else 'MUL高位' if f3<4 else 'DIV与REM'
 if op==51 and f7==5 and f3 in [1,2,3]:return 'CLMUL'
 if op in [15,115]:return '系统与CSR'
 return '整数ALU与位运算'
ret['kind']=[kind(int(w)) for w in ret.instruction]
func_ret=ret.groupby(['function','group'],sort=False).size().rename('retired_instructions').reset_index().sort_values('retired_instructions',ascending=False)
func_ret.to_csv(r/'analysis/function_retirement.csv',index=False,encoding='utf-8-sig')
mix=pd.crosstab(ret.group,ret.kind)
mix.to_csv(r/'analysis/algorithm_instruction_mix.csv',encoding='utf-8-sig')
retired_group=ret.groupby('group').size().to_dict()
cohort=[]
for name,q in d.groupby('head_group',sort=False):
 n=len(q)
 row={'group':name,'head_owned_cycles':n,'cycle_share_percent':100*n/len(d),
 'retired_instructions_by_exact_pc':int(retired_group.get(name,0)),
 'retired_during_head_cohort':int(q.retire_count.sum()),
 'cohort_retired_per_cycle':float(q.retire_count.mean()),
 'dual_issue_cycles':int(q.dual_issue.sum()),'dual_issue_percent':100*float(q.dual_issue.mean()),
 'dual_retire_cycles':int(q.dual_retire.sum()),'dual_retire_percent':100*float(q.dual_retire.mean()),
 'frontend_empty_cycles':int(q.frontend_empty.sum()),'frontend_empty_percent':100*float(q.frontend_empty.mean()),
 'dispatch_stall_cycles':int(q.dispatch_stall.sum()),'dispatch_stall_percent':100*float(q.dispatch_stall.mean()),
 'commit_wait_cycles':int(q.rob_commit_wait.sum()),'commit_wait_percent':100*float(q.rob_commit_wait.mean()),
 'recovery_cycles':int(q.recovery.sum()),'recovery_percent':100*float(q.recovery.mean()),
 'ex_hold_cycles':int(q.ex_hold.sum()),'mean_rob':float(q.rob_count.mean()),'max_rob':int(q.rob_count.max())}
 cohort.append(row)
cohort.sort(key=lambda x:x['head_owned_cycles'],reverse=True)
pd.DataFrame(cohort).to_csv(r/'analysis/algorithm_pipeline_statistics.csv',index=False,encoding='utf-8-sig')
function_cycles=d.groupby('head_function').agg(cycles=('cycle','size'),dual_issue=('dual_issue','sum'),dual_retire=('dual_retire','sum'),commit_wait=('rob_commit_wait','sum'),recovery=('recovery','sum'),dispatch_stall=('dispatch_stall','sum')).reset_index().sort_values('cycles',ascending=False)
function_cycles.to_csv(r/'analysis/function_head_cohorts.csv',index=False,encoding='utf-8-sig')
event_counts=[int(((d.counter_events.to_numpy()>>i)&1).sum()) for i in range(4)]
assert event_counts==[293,1,0,21229]
wait=d.loc[d.rob_commit_wait!=0,['head_group','head_instruction']].copy()
wait['head_kind']=[kind(int(w)) for w in wait.head_instruction]
wait_table=pd.crosstab(wait.head_group,wait.head_kind)
wait_table.to_csv(r/'analysis/commit_wait_by_head_instruction.csv',encoding='utf-8-sig')
result={'method':'Partition every timed cycle by live ROB head PC and ELF symbol; record each actually retired instruction by its own PC. Cross-function dual commits and out-of-order overlap are retained, not attributed as isolated function execution time.',
 'measured_cycles':len(d),'retired':len(ret),'source':'new read-only observer of same last-board RTL model; performance10 firmware',
 'cohorts':cohort,'instruction_mix':mix.to_dict(orient='index'),'function_retirement':func_ret.to_dict(orient='records'),
 'event_counts':dict(zip(['icache_refill','dcache_refill','dcache_writeback','conditional_branch_miss'],event_counts)),
 'retired_conditional_branches':int((ret.kind=='条件分支').sum()),
 'commit_wait_by_head_kind':wait_table.to_dict(orient='index'),
 'validation':{'uart_unchanged':True,'every_sampled_pc_instruction_matches_loaded_binary':True,'retired_sum_matches_timer_snapshots':True,'all_cycles_partitioned':sum(x['head_owned_cycles'] for x in cohort)==len(d)},
 'limitations':['Cohort IPC is global retirement throughput during cycles whose live ROB head belongs to a symbol group; it is not separately timed algorithm IPC or CPI.',
 'Inlining moves subkernel instructions into matrix_test and other callers. ELF symbols cannot separate their source-level subloops.',
 'Helper CRC is kept as its own group, not redistributed to call sites. Functions inlined into callers are counted at their containing symbol.',
 'Only 10-iteration RTL simulation is profiled by algorithm. The physical 512-sample CoreMark ILA window covers matrix_test only.',
 'Wait predicates overlap. Cache refill counts are not cache miss rates. Event timing has registered/boundary offsets.']}
(r/'analysis/algorithm_summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')

plt.rcParams.update({'font.family':'Microsoft YaHei','axes.unicode_minus':False,'font.size':10,'svg.fonttype':'none','axes.spines.right':False,'axes.spines.top':False})
groups=[x for x in cohort if x['group'] in ['链表','矩阵','状态机','CRC']]
fig,axes=plt.subplots(1,3,figsize=(15,4.9))
labels=[x['group'] for x in groups];colors=['#087e8b','#4b62c2','#aa6034','#7c5c9a']
bars=axes[0].bar(labels,[x['cycle_share_percent'] for x in groups],color=colors,width=.6)
for bar,x in zip(bars,groups):axes[0].text(bar.get_x()+bar.get_width()/2,bar.get_height()+1,f'{x["cycle_share_percent"]:.1f}%\n{x["head_owned_cycles"]:,}',ha='center',fontsize=9)
axes[0].set_ylim(0,max(x['cycle_share_percent'] for x in groups)*1.3);axes[0].set_ylabel('全部计时周期 / %');axes[0].set_title('ROB 队头归属周期占比')
x=np.arange(len(groups));w=.35
axes[1].bar(x-w/2,[a['dual_issue_percent'] for a in groups],w,label='同拍接收两条',color='#087e8b')
axes[1].bar(x+w/2,[a['dual_retire_percent'] for a in groups],w,label='同拍提交两条',color='#4b62c2')
axes[1].set_xticks(x,labels);axes[1].set_ylim(0,100);axes[1].set_ylabel('该队头分组内周期 / %');axes[1].set_title('双发射与双提交');axes[1].legend(fontsize=9)
axes[2].bar(x-w/2,[a['commit_wait_percent'] for a in groups],w,label='ROB等待提交',color='#aa6034')
axes[2].bar(x+w/2,[a['recovery_percent'] for a in groups],w,label='恢复清空',color='#a04453')
axes[2].set_xticks(x,labels);axes[2].set_ylim(0,max(35,max(a['commit_wait_percent'] for a in groups)*1.2));axes[2].set_ylabel('该队头分组内周期 / %');axes[2].set_title('等待与恢复');axes[2].legend(fontsize=9)
for ax in axes:ax.grid(axis='y',alpha=.15);ax.set_axisbelow(True)
fig.suptitle('同版 RTL CoreMark 关键算法的流水线观测',fontsize=16,fontweight='bold');fig.tight_layout()
for ext in ['png','svg']:fig.savefig(r/f'docs/figures/algorithm_pipeline.{ext}',dpi=190,bbox_inches='tight')
plt.close(fig)
for name in ['链表','矩阵','状态机']:
 candidates=np.flatnonzero((d.head_group==name).to_numpy())
 start=int(candidates[len(candidates)//2]);start=min(start,len(d)-64)
 q=d.iloc[start:start+64]
 q.to_csv(r/f'analysis/{name}_sample64.csv',index=False,encoding='utf-8-sig')
 fig,axes=plt.subplots(6,1,figsize=(12,5),sharex=True,gridspec_kw={'hspace':.1})
 series=[('新接收数','issue_count','#087e8b'),('提交数','retire_count','#4b62c2'),('ROB占用','rob_count','#39475e'),('等待提交','rob_commit_wait','#aa6034'),('分配阻塞','dispatch_stall','#8560a6'),('恢复清空','recovery','#a04453')]
 for ax,(label,col,color) in zip(axes,series):
  ax.step(q.window_index,q[col],where='post',color=color,lw=1.1);ax.set_ylabel(label,rotation=0,ha='right',va='center');ax.grid(alpha=.12);ax.set_ylim(-.1,max(1,int(q[col].max()))+.25)
 axes[-1].set_xlabel('CoreMark计时窗口周期序号');fig.suptitle(f'{name}算法队头分组的局部流水线窗口  周期 {start} 至 {start+63}',fontsize=13)
 fig.subplots_adjust(left=.13,top=.89,bottom=.12)
 for ext in ['png','svg']:fig.savefig(r/f'docs/figures/{name}_pipeline64.{ext}',dpi=180,bbox_inches='tight')
 plt.close(fig)
print(json.dumps({'cohorts':cohort,'events':event_counts,'branches':result['retired_conditional_branches'],'top_functions':func_ret.head(12).to_dict(orient='records')},ensure_ascii=False,indent=2))
