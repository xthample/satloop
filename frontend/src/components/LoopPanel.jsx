import React, { useState } from 'react';
import { Zap, CheckCircle, Loader2, AlertTriangle } from 'lucide-react';
import { calcLeverage, calcLeveragedAPY, fmtBTC } from '../utils/calculations';

export default function LoopPanel({ satloop, wallet }) {
  const [loops, setLoops] = useState(3);
  const lev  = calcLeverage(loops);
  const apy  = calcLeveragedAPY(loops);
  const base = satloop.userInfo?.staked || 0;
  const projStaked = base * lev;
  const projBorrow = projStaked - base;
  const ls   = satloop.loopState;

  const stepState = s => {
    if (ls==='idle') return 'idle';
    if (ls==='done') return 'done';
    if (ls==='error') return 'error';
    const n = parseInt(ls.split('_')[1]);
    return s < n ? 'done' : s === n ? 'active' : 'idle';
  };

  const stepBg = {
    idle:   'border-btc-border bg-btc-dark/30',
    active: 'border-btc-orange/50 bg-btc-orange/8 loop-active',
    done:   'border-sat-green/30 bg-sat-green/5',
    error:  'border-sat-red/30 bg-sat-red/5',
  };
  const dotBg = { idle:'bg-btc-border', active:'bg-btc-orange', done:'bg-sat-green', error:'bg-sat-red' };

  return (
    <div className="slide-up bg-btc-panel rounded-2xl border border-btc-orange/30 overflow-hidden" style={{animationDelay:'80ms',boxShadow:'0 0 30px rgba(247,147,26,0.07)'}}>
      <div className="px-5 pt-5 pb-4 border-b border-btc-border flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <Zap className="w-4 h-4 text-btc-orange"/>
            <span className="font-display font-bold text-white text-sm tracking-widest">LEVERAGE LOOP</span>
          </div>
          <p className="text-[10px] text-btc-muted font-display tracking-wider">One-click multi-loop compounding</p>
        </div>
        <div className="text-right">
          <div className="text-2xl font-display font-bold text-btc-orange text-glow-orange">{lev.toFixed(2)}×</div>
          <div className="text-[10px] font-display text-btc-muted">leverage</div>
        </div>
      </div>

      <div className="p-5">
        <div className="mb-5">
          <div className="flex justify-between text-[10px] font-display text-btc-muted uppercase tracking-widest mb-2">
            <span>Loops: {loops}</span>
            <span className="text-sat-green">{apy.toFixed(1)}% Net APY</span>
          </div>
          <input type="range" min="1" max="3" step="1" value={loops} onChange={e => setLoops(+e.target.value)}
            className="w-full" style={{background:`linear-gradient(to right,#F7931A ${((loops-1)/2)*100}%,#252525 ${((loops-1)/2)*100}%)`}}/>
          <div className="flex justify-between text-[9px] font-display text-btc-muted mt-1.5">
            <span>1.67×</span><span>2.11×</span><span>2.37×</span>
          </div>
        </div>

        {base > 0 && (
          <div className="grid grid-cols-3 gap-2 mb-4">
            {[['Base', fmtBTC(base)+' BTC','text-white'],['After Loop',fmtBTC(projStaked)+' BTC','text-btc-orange'],['Debt',fmtBTC(projBorrow)+' BTC','text-sat-yellow']].map(([l,v,c],i)=>(
              <div key={i} className="bg-btc-dark rounded-xl p-2.5 border border-btc-border text-center">
                <div className={`font-display font-bold text-xs ${c}`}>{v}</div>
                <div className="text-[9px] font-display text-btc-muted mt-0.5">{l}</div>
              </div>
            ))}
          </div>
        )}

        <div className="mb-4 space-y-2">
          {[1,2,3].slice(0,loops).map(s => {
            const st = stepState(s);
            return (
              <div key={s} className={`flex items-center gap-3 p-3 rounded-xl border transition-all ${stepBg[st]} ${st==='active'?'loop-active':''}`}>
                <div className={`w-6 h-6 rounded-full flex items-center justify-center flex-shrink-0 ${dotBg[st]}`}>
                  {st==='done'   && <CheckCircle className="w-3.5 h-3.5 text-black"/>}
                  {st==='active' && <Loader2 className="w-3.5 h-3.5 text-black animate-spin"/>}
                  {st==='idle'   && <span className="text-btc-muted text-[10px] font-display">{s}</span>}
                </div>
                <div>
                  <div className="text-[11px] font-display font-bold text-white">Loop {s}</div>
                  <div className="text-[9px] font-display text-btc-muted">Borrow {['66','44','30'][s-1]}% → re-stake automatically</div>
                </div>
              </div>
            );
          })}
        </div>

        {loops === 3 && (
          <div className="flex items-start gap-2 p-3 rounded-xl bg-sat-yellow/5 border border-sat-yellow/20 mb-4">
            <AlertTriangle className="w-3.5 h-3.5 text-sat-yellow flex-shrink-0 mt-0.5"/>
            <span className="text-[10px] font-display text-sat-yellow">3× increases liquidation risk. Keep Health Factor &gt; 1.3</span>
          </div>
        )}

        <button onClick={() => satloop.loopMax(loops)}
          disabled={!wallet.connected || ls==='running' || !satloop.userInfo?.staked}
          className={`w-full py-4 rounded-xl font-display font-bold text-sm tracking-widest flex items-center justify-center gap-2 transition-all active:scale-95 disabled:opacity-40 disabled:cursor-not-allowed ${
            ls==='done'    ? 'bg-sat-green text-black' :
            ls==='running' ? 'bg-btc-orange/15 text-btc-orange border border-btc-orange/30 cursor-wait' :
            'bg-btc-orange text-black hover:shadow-[0_0_30px_rgba(247,147,26,0.55)]'}`}>
          {ls==='running' ? <><Loader2 className="w-5 h-5 animate-spin"/>LOOPING... ({ls.includes('_')?ls.split('_')[1]:0}/{loops})</> :
           ls==='done'    ? <><CheckCircle className="w-5 h-5"/>LOOP COMPLETE ✓</> :
           <><Zap className="w-5 h-5"/>LOOP TO {lev.toFixed(2)}×</>}
        </button>
        {satloop.txHash && ls==='done' && (
          <div className="mt-2.5 text-center text-[10px] font-display text-btc-muted">tx: <span className="text-btc-orange">{satloop.txHash}</span></div>
        )}
      </div>
    </div>
  );
}
