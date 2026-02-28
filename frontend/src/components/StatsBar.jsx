import React from 'react';
import { fmtUSD } from '../utils/calculations';

export default function StatsBar({ poolInfo }) {
  const s = [
    { label:'TVL',            value: poolInfo ? fmtUSD(poolInfo.tvl) : '—',                    change:'+12.4%', gold:false, green:false },
    { label:'Total Staked',   value: poolInfo ? `${poolInfo.totalStaked.toFixed(1)} BTC` : '—', change:'+3.1 BTC' },
    { label:'Base APY',       value: poolInfo ? `${poolInfo.apy.base}%` : '—',                  green:true },
    { label:'Max APY (3× Loop)', value: poolInfo ? `${poolInfo.apy.leveraged}%` : '—',          gold:true },
  ];
  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
      {s.map((x,i) => (
        <div key={i} className="slide-up bg-btc-panel rounded-2xl p-4 border border-btc-border" style={{animationDelay:`${i*60}ms`}}>
          <div className="text-[10px] font-display text-btc-muted uppercase tracking-widest mb-2">{x.label}</div>
          <div className={`text-xl font-display font-bold ${x.gold?'text-btc-orange text-glow-orange':x.green?'text-sat-green text-glow-green':'text-white'}`}>{x.value}</div>
          {x.change && <div className="text-xs font-display text-sat-green mt-1">{x.change} 24h</div>}
        </div>
      ))}
    </div>
  );
}
