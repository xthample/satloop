import React from 'react';
import { Wallet } from 'lucide-react';
import { shortAddr } from '../utils/calculations';

export default function Header({ wallet }) {
  return (
    <header className="fixed top-0 left-0 right-0 z-50 border-b border-btc-border bg-btc-dark/90 backdrop-blur-xl">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="anim-glow w-9 h-9 rounded-full bg-btc-orange flex items-center justify-center font-display font-bold text-black text-sm">₿</div>
          <div>
            <div className="font-display font-bold text-white text-lg leading-none">SAT<span className="text-btc-orange">LOOP</span></div>
            <div className="text-[10px] text-btc-muted font-display tracking-widest">LEVERAGED LOOP STAKER</div>
          </div>
        </div>
        <div className="flex items-center gap-3">
          {wallet.connected && (
            <span className="hidden sm:flex items-center gap-2 px-3 py-1 rounded-full bg-btc-panel border border-btc-border text-xs font-display text-btc-muted">
              <span className="w-1.5 h-1.5 rounded-full bg-sat-green animate-pulse"/>
              {wallet.network.toUpperCase()}
            </span>
          )}
          {wallet.connected ? (
            <div className="flex items-center gap-2">
              <span className="hidden sm:block px-3 py-2 rounded-xl bg-btc-panel border border-btc-border text-xs font-display text-btc-muted">{shortAddr(wallet.address)}</span>
              <button onClick={wallet.disconnect} className="px-4 py-2 rounded-xl border border-btc-border text-xs font-display text-btc-muted hover:border-sat-red hover:text-sat-red transition-colors">Disconnect</button>
            </div>
          ) : (
            <button onClick={wallet.connect} disabled={wallet.loading}
              className="flex items-center gap-2 px-5 py-2.5 rounded-xl bg-btc-orange text-black font-display font-bold text-sm tracking-wide hover:bg-orange-400 transition-all hover:shadow-[0_0_20px_rgba(247,147,26,0.5)] disabled:opacity-50">
              {wallet.loading ? <><span className="w-3.5 h-3.5 rounded-full border-2 border-black/30 border-t-black animate-spin"/>Connecting...</> : <><Wallet className="w-3.5 h-3.5"/>Connect Wallet</>}
            </button>
          )}
        </div>
      </div>
    </header>
  );
}
