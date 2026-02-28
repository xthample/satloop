import React from 'react';
import { useWallet }    from './hooks/useWallet';
import { useSatLoop }   from './hooks/useSatLoop';
import Header           from './components/Header';
import StatsBar         from './components/StatsBar';
import DepositPanel     from './components/DepositPanel';
import LoopPanel        from './components/LoopPanel';
import Dashboard        from './components/Dashboard';

export default function App() {
  const wallet  = useWallet();
  const satloop = useSatLoop(wallet);

  return (
    <div className="min-h-screen">
      <Header wallet={wallet}/>
      <main className="max-w-6xl mx-auto px-4 pt-24 pb-16">
        {/* Hero */}
        <div className="slide-up text-center mb-10 mt-4">
          <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full border border-btc-orange/25 bg-btc-orange/5 text-btc-orange text-[10px] font-display mb-5 tracking-widest uppercase">
            <span className="w-1.5 h-1.5 rounded-full bg-btc-orange animate-pulse inline-block"/>
            Powered by OP_NET · Bitcoin L1
          </div>
          <h1 className="text-5xl lg:text-6xl font-display font-bold text-white leading-none mb-4 tracking-tight">
            Sat<span className="text-btc-orange text-glow-orange">Loop</span>
          </h1>
          <p className="text-btc-muted text-base max-w-lg mx-auto leading-relaxed">
            One-click leveraged loop staking on Bitcoin L1. Deposit → Stake → Borrow → Re-stake,
            up to <span className="text-btc-orange font-semibold">3× leverage</span> automatically.
          </p>
        </div>

        <StatsBar poolInfo={satloop.poolInfo}/>

        <div className="grid lg:grid-cols-3 gap-5">
          <div className="lg:col-span-2 space-y-5">
            <DepositPanel satloop={satloop} wallet={wallet}/>
            <LoopPanel    satloop={satloop} wallet={wallet}/>
          </div>
          <div className="lg:col-span-1">
            <Dashboard satloop={satloop} wallet={wallet}/>
          </div>
        </div>

        <footer className="mt-16 pt-8 border-t border-btc-border text-center">
          <div className="flex justify-center gap-6 mb-2 text-[11px] font-display text-btc-muted">
            {[['OP_NET Docs','https://opnet.org'],['GitHub','#'],['vibecode.finance','https://vibecode.finance']].map(([l,h],i) => (
              <a key={i} href={h} target="_blank" rel="noopener noreferrer" className="hover:text-btc-orange transition-colors">{l}</a>
            ))}
          </div>
          <div className="text-[10px] font-display text-btc-muted/50">SatLoop v1.0 · Vibecoding Contest "The DeFi Signal" · Audited by Bob™</div>
        </footer>
      </main>
    </div>
  );
}
