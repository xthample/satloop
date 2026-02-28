import React, { useMemo } from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts';
import { Loader2 } from 'lucide-react';
import { calcHealthFactor, calcRisk, riskLabel, generateApyChartData, fmtBTC, fmtUSD, BASE_APY } from '../utils/calculations';

export default function Dashboard({ satloop, wallet }) {
  const chartData = useMemo(() => generateApyChartData(), []);
  const u  = satloop.userInfo;
  const hf = u ? calcHealthFactor(u.staked, u.borrowed) : null;
  const risk = hf ? calcRisk(hf) : 0;
  const tier = riskLabel(risk);

  const CT = ({ active, payload }) => !active || !payload?.length ? null : (
    <div className="bg-btc-panel border border-btc-border rounded-xl p-2.5 font-display text-[10px]">
      <div className="text-btc-muted mb-1">{payload[0]?.payload?.loops} Loops</div>
      <div className="text-sat-green">{payload[0]?.value?.toFixed(1)}% Net APY</div>
      <div className="text-btc-orange">{payload[0]?.payload?.leverage}× Leverage</div>
    </div>
  );

  return (
    <div className="space-y-4">
      {/* Position */}
      <div className="slide-up bg-btc-panel rounded-2xl border border-btc-border p-5" style={{animationDelay:'160ms'}}>
        <div className="text-[10px] font-display text-btc-muted uppercase tracking-widest mb-4">Your Position</div>
        {!wallet.connected ? (
          <div className="text-center py-8 text-btc-muted font-display text-xs">Connect wallet to view position</div>
        ) : !u ? (
          <div className="text-center py-8"><Loader2 className="w-5 h-5 animate-spin text-btc-orange mx-auto"/></div>
        ) : (
          <>
            <div className="grid grid-cols-2 gap-2.5 mb-3">
              {[['Staked',`${fmtBTC(u.staked)} BTC`,'text-white'],['Borrowed',`${fmtBTC(u.borrowed)} BTC`,'text-sat-yellow'],['Eff. Leverage',`${u.leverage}×`,'text-btc-orange'],['Pending SATYIELD',u.pendingYield.toFixed(2),'text-sat-green']].map(([l,v,c],i)=>(
                <div key={i} className="bg-btc-dark rounded-xl p-3 border border-btc-border">
                  <div className="text-[9px] font-display text-btc-muted mb-1">{l}</div>
                  <div className={`font-display font-bold text-sm ${c}`}>{v}</div>
                </div>
              ))}
            </div>
            {u.pendingYield > 0 && (
              <button onClick={satloop.harvest} disabled={satloop.txPending}
                className="w-full py-2.5 rounded-xl border border-sat-green/30 text-sat-green text-[11px] font-display font-bold tracking-widest hover:bg-sat-green/8 transition-colors disabled:opacity-40">
                {satloop.txPending ? 'Harvesting...' : `Harvest ${u.pendingYield.toFixed(2)} SATYIELD`}
              </button>
            )}
          </>
        )}
      </div>

      {/* Risk meter */}
      {wallet.connected && u && (
        <div className="slide-up bg-btc-panel rounded-2xl border border-btc-border p-5" style={{animationDelay:'200ms'}}>
          <div className="flex justify-between items-center mb-4">
            <div className="text-[10px] font-display text-btc-muted uppercase tracking-widest">Risk Meter</div>
            <span className="text-[10px] font-display font-bold px-2 py-0.5 rounded-full border"
              style={{color:tier.color,borderColor:`${tier.color}40`,background:`${tier.color}10`}}>{tier.label}</span>
          </div>
          <div className="h-2.5 bg-btc-dark rounded-full overflow-hidden border border-btc-border mb-2">
            <div className="h-full rounded-full transition-all duration-700"
              style={{width:`${risk}%`,background:'linear-gradient(to right,#00FF94,#FFD166,#FF3B3B)'}}/>
          </div>
          <div className="flex justify-between text-[9px] font-display text-btc-muted mb-3">
            <span className="text-sat-green">SAFE</span><span>MEDIUM</span><span className="text-sat-red">LIQ RISK</span>
          </div>
          <div className="space-y-1.5">
            {[['Health Factor', isFinite(hf)?hf.toFixed(3):'∞', tier.color],['Liquidated when HF','< 1.000','#FF3B3B']].map(([l,v,c],i)=>(
              <div key={i} className="flex justify-between text-[10px] font-display">
                <span className="text-btc-muted">{l}</span><span style={{color:c}} className="font-bold">{v}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* APY Chart */}
      <div className="slide-up bg-btc-panel rounded-2xl border border-btc-border p-5" style={{animationDelay:'240ms'}}>
        <div className="text-[10px] font-display text-btc-muted uppercase tracking-widest mb-4">APY vs Loops</div>
        <div className="h-36">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={chartData} margin={{top:4,right:4,left:-24,bottom:0}}>
              <defs>
                <linearGradient id="apyG" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%"  stopColor="#00FF94" stopOpacity={0.3}/>
                  <stop offset="95%" stopColor="#00FF94" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#1E1E1E"/>
              <XAxis dataKey="loops" tick={{fill:'#555',fontSize:9,fontFamily:'Space Mono'}} tickLine={false} axisLine={{stroke:'#252525'}}/>
              <YAxis tick={{fill:'#555',fontSize:9,fontFamily:'Space Mono'}} tickLine={false} axisLine={false} tickFormatter={v=>`${v}%`}/>
              <Tooltip content={<CT/>}/>
              <ReferenceLine y={BASE_APY} stroke="#F7931A" strokeDasharray="4 2" strokeWidth={1}/>
              <Area type="monotone" dataKey="apy" stroke="#00FF94" strokeWidth={2} fill="url(#apyG)" dot={{fill:'#00FF94',r:3,strokeWidth:0}}/>
            </AreaChart>
          </ResponsiveContainer>
        </div>
        <div className="flex gap-4 mt-2 text-[9px] font-display text-btc-muted">
          <span className="flex items-center gap-1.5"><span className="w-3 h-0.5 bg-sat-green rounded inline-block"/>Net APY</span>
          <span className="flex items-center gap-1.5"><span className="w-3 h-0.5 bg-btc-orange rounded inline-block"/>Base</span>
        </div>
      </div>
    </div>
  );
}
