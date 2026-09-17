#!/usr/bin/env python3
"""Summarize real device JSON; missing measurements stay missing, never zero."""
import argparse, csv, json, statistics
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('recording',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
d=json.loads(a.recording.read_text());rows=d['samples'];a.output.mkdir(parents=True,exist_ok=True)
if not rows: raise SystemExit('No recorded samples')
with (a.output/'samples.csv').open('w') as f:
 w=csv.DictWriter(f,fieldnames=list(dict.fromkeys(k for r in rows for k in r)));w.writeheader();w.writerows(rows)
def values(rs,key): return [r[key] for r in rs if isinstance(r.get(key),(float,int))]
def mean(v): return statistics.mean(v) if v else None
def p95(v): return sorted(v)[min(len(v)-1,int((len(v)-1)*.95))] if v else None
def fmt(v): return '—' if v is None else f'{v:.1f}'
stages=[]
for name in dict.fromkeys(r['stage'] for r in rows):
 rs=[r for r in rows if r['stage']==name and 10<=r['stageElapsed']<=({'首页静置':35,'内联播放':40,'横屏全屏':40,'缩略音频 A':40,'缩略视频开启 对照':40,'缩略音频 B':40,'重新展开':20,'关闭后静置':50}.get(name,float('inf'))) and r['appState']==0]
 cpu=values(rs,'cpuPercentOneCore');mem=values(rs,'footprintMiB')
 stages.append(dict(stage=name,n=len(rs),cpuMean=mean(cpu),cpuP95=p95(cpu),memoryMean=mean(mem),memoryPeak=max(mem) if mem else None,memoryLast=mem[-1] if mem else None,thermalMax=max(values(rs,'thermal'),default=None),playingSamples=sum(r['playing'] for r in rs),landscapeSamples=sum(r['landscape'] for r in rs),videoOutputSamples=sum(r.get('videoOutputRequested') is True for r in rs)))
summary={'started':d['started'],'finished':d.get('finished'),'notes':d['notes'],'sampleCount':len(rows),'elapsed':rows[-1]['elapsed'],'stages':stages,'batteryStart':rows[0].get('batteryLevel'),'batteryEnd':rows[-1].get('batteryLevel'),'batteryStates':sorted(set(r['batteryState'] for r in rows))}
(a.output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
lines=['# NeoBili 真机性能采集','',f"采样时间：{d['started']}；记录 {len(rows)} 个样本，跨度 {rows[-1]['elapsed']:.0f} 秒。结束标记：{d.get('finished') or '未收到，记录不完整'}。",'', '仅统计各阶段开始 10 秒后的前台样本。CPU 100% 表示占满一个核心，可超过 100%。内存使用 phys_footprint，单位 MiB。','', '| 阶段 | 样本 | CPU 均值 | CPU P95 | 内存均值 | 内存峰值 | 末尾内存 | 最高热状态 |','|---|---:|---:|---:|---:|---:|---:|---:|']
for s in stages:
 lines.append('| '+ ' | '.join([s['stage'],str(s['n']),fmt(s['cpuMean'])+'%',fmt(s['cpuP95'])+'%',fmt(s['memoryMean']),fmt(s['memoryPeak']),fmt(s['memoryLast']),str(s['thermalMax'])])+' |')
lines += ['', '热状态：0 正常，1 轻度，2 严重，3 临界。', '', '## 判断边界', '', '- 此处 CPU、内存为应用进程实测，包含轻量采样器自身开销。', '- 电量分辨率较低，短时变化不能推算瓦数；连接电脑或充电时尤其不能据此推算耗电。', '- 真实功耗结论须结合本轮 Power Profiler；其系统功耗不能全部归因于当前 App。', '- 单次关闭后的内存未完全回落可能来自缓存，不能单独证明泄漏。', '- 自动测试没有模拟滚动和手势压力，也不代表所有视频编码、画质、直播或长时发热表现。', '', '## 采集备注', '']+[f'- {n}' for n in d['notes']]
(a.output/'report.md').write_text('\n'.join(lines)+'\n')
print(json.dumps(summary,ensure_ascii=False,indent=2))
