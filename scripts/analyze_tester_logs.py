"""Read-only MT5 agent-log analysis; outputs local JSON evidence, no trading."""
import os, re, json, statistics
from pathlib import Path
from datetime import datetime

root=Path(__file__).resolve().parent.parent
default=Path(os.environ['APPDATA'])/'MetaQuotes/Tester/12FE2A177E39CFD95D50E79D01391499/Agent-127.0.0.1-3001/logs/20260909.log'
path=Path(os.environ.get('DHANU_TESTER_LOG',default))
lines=path.read_text(encoding='utf-16').splitlines()
stamp=r'(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2})'
dt=lambda s: datetime.strptime(s,'%Y.%m.%d %H:%M:%S')
runs=[]; run=None
for number,line in enumerate(lines,1):
    if 'testing of Experts\\DhanuFX\\DhanuFX.ex5' in line:
        run={'start_line':number,'header':line,'inputs':{},'entries':[],'areas':{},'outcomes':{},'fills':{},'warnings':[]}
        runs.append(run)
    if run is None: continue
    m=re.search(r'\t  (\w+)=(.*)$',line)
    if m: run['inputs'][m[1]]=m[2]
    if 'Signal evidence |' in line:
        m=re.search(stamp+r'   Signal evidence \| candle\[2\] O/H/L/C=([\d./-]+) \| candle\[1\] O/H/L/C=([\d./-]+) \| directional wick %=([\d.]+)',line)
        if m: run['areas'][m[1][:16]]={'older':list(map(float,m[2].split('/'))),'previous':list(map(float,m[3].split('/'))),'wick_pct':float(m[4])}
    if 'LTF entry |' in line and 'Entry filter skipped' not in line:
        m=re.search(stamp+r'   LTF entry \| (\w+) \| (BUY|SELL) \| zone=([\d. :]+) \| (?:stop mode=(\w+) \| )?SL=([\d.]+) TP=([\d.]+).*?\| deal=(\d+) \| fill=([\d.]+)',line)
        if m:
            risk=re.search(r'estimated risk=([\d.]+)',line)
            extra={}
            if m[5]: extra['stop_mode']=m[5]
            f=re.search(r'entry spread=([\d.]+) \| zone age min=([\d.]+) \| chase R=([\d.]+) \| HTF body %=([\d.]+)',line)
            if f:
                extra['entry_spread']=float(f[1]); extra['logged_age_min']=float(f[2]); extra['logged_chase_r']=float(f[3]); extra['logged_body_pct']=float(f[4])
            run['entries'].append(dict({'time':m[1],'direction':m[3],'zone':m[4],'sl':float(m[6]),'tp':float(m[7]),'deal':int(m[8]),'entry':float(m[9]),'risk':float(risk[1]) if risk else None,'line':number},**extra))
    if 'Entry filter skipped |' in line:
        run['filter_skips']=run.get('filter_skips',0)+1
    m=re.search(stamp+r'   (stop loss|take profit) triggered #(\d+) (buy|sell) ([\d.]+) XAUUSD ([\d.]+) sl: ([\d.]+) tp: ([\d.]+)',line)
    if m:
        closing=re.search(r'\[#(\d+) ',line)
        run['outcomes'][int(m[3])]={'exit_time':m[1],'outcome':'win' if m[2]=='take profit' else 'loss','exit_line':number,'lots':float(m[5]),'exit_order':int(closing[1])}
    m=re.search(r'deal #(\d+) (?:buy|sell) [\d.]+ XAUUSD at ([\d.]+) done \(based on order #(\d+)\)',line)
    if m: run['fills'][int(m[3])]=float(m[2])
    if any(s in line.lower() for s in ['real ticks absent','real ticks discarded','no real ticks','history quality','tick generation','real ticks begin','testing on real ticks']): run['warnings'].append(line)
    m=re.search(r'final balance ([\d.]+) USD',line)
    if m: run['final_balance']=float(m[1]); run['end_line']=number

def stats(trades):
    closed=[t for t in trades if 'outcome' in t]
    w=sum(t['outcome']=='win' for t in closed)
    pnl=sum(t['gross_pnl'] for t in closed)
    wins=sum(max(0,t['gross_pnl']) for t in closed); losses=-sum(min(0,t['gross_pnl']) for t in closed)
    equity=peak=10000.; dd=0.; streak=longest=0
    for t in closed:
        equity+=t['gross_pnl']; peak=max(peak,equity); dd=max(dd,peak-equity)
        streak=streak+1 if t['outcome']=='loss' else 0; longest=max(longest,streak)
    return dict(n=len(closed),wins=w,losses=len(closed)-w,win_pct=round(100*w/len(closed),2) if closed else None,
                gross_pnl=round(pnl,2),gross_pf=round(wins/losses,3) if losses else None,estimated_closed_balance_dd=round(dd,2),max_loss_streak=longest)

for r in runs:
    for t in r['entries']:
        outcome=r['outcomes'].get(t['deal'])
        if not outcome: continue
        t.update(outcome)
        t['age_minutes']=(dt(t['time'])-dt(t['zone']+':00')).total_seconds()/60
        t['stop_distance']=abs(t['entry']-t['sl'])
        close=r['fills'][t['exit_order']]
        t['exit_price']=close
        # XAUUSD contract is inferred from log risk amounts, checked against balance.
        t['gross_pnl']=(close-t['entry'])*(1 if t['direction']=='BUY' else -1)*t['lots']*100
        a=r['areas'].get(t['zone'])
        if a:
            o,h,l,c=a['older']; po,ph,pl,pc=a['previous']
            t['htf_wick_pct']=a['wick_pct']; t['body_fraction']=abs(c-o)/(h-l) if h>l else 0
            t['zone_width']=abs(c-o)
            t['distance_from_zone']=max(min(o,c)-t['entry'],t['entry']-max(o,c),0)
            t['chase_r']=t['distance_from_zone']/t['stop_distance'] if t['stop_distance'] else 0
        if 'logged_age_min' in t: t['age_minutes']=t['logged_age_min']
        if 'logged_chase_r' in t: t['chase_r']=t['logged_chase_r']
        if 'logged_body_pct' in t: t['body_fraction']=t['logged_body_pct']/100
    r['stats']=stats(r['entries']); r['rejected']=sum(t['deal']==0 for t in r['entries'])
    r['unmatched']=sum(t['deal']>0 and 'outcome' not in t for t in r['entries'])
    r['filters']=tuple(float(r['inputs'].get(k,0)) for k in ['Min_HTF_Source_Body_Percent','Max_Entry_Distance_R','Min_Zone_Age_Minutes'])
    r.pop('areas'); r.pop('outcomes'); r.pop('fills')

latest=runs[-1]; trades=[t for t in latest['entries'] if 'outcome' in t]

def period_splits(trades):
    closed=[t for t in trades if 'outcome' in t]
    closed.sort(key=lambda t:t['time'])
    n=len(closed)
    if n<8: return {'whole':stats(closed)}
    half=n//2
    return {'whole':stats(closed),'first_half':stats(closed[:half]),
            'second_half':stats(closed[half:]),
            'last_3y':stats([t for t in closed if t['time']>='2023.01.01'])}

experiments={}
for r in runs:
    r['period_stats']=period_splits(r['entries'])
    key=r['filters']
    experiments.setdefault(key,[]).append(r)

experiment_table=[]
for key in sorted(experiments,key=lambda k:(-k[0],-k[1],-k[2])):
    for r in experiments[key]:
        experiment_table.append({'filters':{'source_body':key[0],'entry_distance_r':key[1],'zone_age_min':key[2]},
                                 'rr':r['inputs'].get('Take_Profit_RR','?'),'risk_money':r['inputs'].get('Risk_Money'),
                                 'final_balance':r.get('final_balance'),'rejected':r['rejected'],
                                 'skips':r.get('filter_skips',0),'period_stats':r['period_stats']})

groups={}
for label,key in [('direction',lambda t:t['direction']),('year',lambda t:t['time'][:4]),
                  ('hour',lambda t:t['time'][11:13]),('age',lambda t:'0-90m' if t['age_minutes']<=90 else '90-180m' if t['age_minutes']<=180 else '>180m'),
                  ('HTF wick',lambda t:'<10%' if t.get('htf_wick_pct',20)<10 else '10-20%'),
                  ('source body/range',lambda t:'<20%' if t.get('body_fraction',1)<.2 else '>=20%'),
                  ('chase risk fraction',lambda t:'<=0.25R' if t.get('chase_r',1)<=.25 else '>0.25R')]:
    buckets={}
    for t in trades: buckets.setdefault(key(t),[]).append(t)
    groups[label]={k:stats(v) for k,v in sorted(buckets.items())}
output={'source':str(path),'note':'Gross P/L inferred using 100 oz/lot; excludes costs and intratrade equity drawdown. Filters are retrospective subsets, not rerun backtests.','runs':runs,'latest_groups':groups,'experiment_table':experiment_table}
(root/'docs/tester_analysis.json').write_text(json.dumps(output,indent=2),encoding='utf-8')
print(json.dumps({'runs':[{'start_line':r['start_line'],'filters':r['filters'],'rr':r['inputs'].get('Take_Profit_RR'),'final_balance':r.get('final_balance'),'skips':r.get('filter_skips',0),'unmatched':r['unmatched'],'stats':r['stats']} for r in runs],'experiment_table':experiment_table,'latest_groups':groups},indent=2))
