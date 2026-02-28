import React, { useState } from 'react';
import { ArrowDownToLine, ArrowUpFromLine, Loader2 } from 'lucide-react';
import { fmtBTC } from '../utils/calculations';

export default function DepositPanel({ satloop, wallet }) {
  const [tab, setTab]       = useState('deposit');
  const [amount, setAmount] = useState('');
  const [status, setStatus] = useState(null);

  const submit = async () => {
    if (!amount || isNaN(amount) || +amount <= 0) return;
    setStatus('pending');
    try {
      tab === 'deposit' ? await satloop.deposit(amount) : await satloop.withdraw(amount);
      setStatus('success'); setAmount('');
      setTimeout(() => setStatus(null), 3000);
    } catch { setStatus('error'); setTimeout(() => setStatus(null), 3000); }
  };

  const tabs = [
    { k:'deposit',  label:'DEPOSIT',  Icon:ArrowDownToLine },
    { k:'withdraw', label:'WITHDRAW', Icon:ArrowUpFromLine  },
  ];

  return (
    <div className="slide-up bg-btc-panel rounded-2xl border border-btc-border overflow-hidden">
      <div className="flex border-b border-btc-border">
        {tabs.map(({ k, label, Icon }) => (
          <button key={k} onClick={() => setTab(k)}
            className={`flex-1 flex items-center justify-center gap-2 py-3.5 text-xs font-display font-bold tracking-widest transition-colors ${tab===k?'text-btc-orange border-b-2 border-btc-orange bg-btc-orange/5':'text-btc-muted hover:text-white'}`}>
            <Icon className="w-3.5 h-3.5"/>{label}
          </button>
        ))}
      </div>
      <div className="p-5">
        <div className="mb-4">
          <div className="flex justify-between text-[10px] font-display text-btc-muted uppercase tracking-widest mb-2">
            <span>Amount</span>
            {tab==='withdraw' && satloop.userInfo && (
              <button onClick={() => setAmount(satloop.userInfo.staked.toString())} className="text-btc-orange hover:underline">
                MAX: {fmtBTC(satloop.userInfo.staked)} BTC
              </button>
            )}
          </div>
          <div className="flex items-center gap-3 bg-btc-dark rounded-xl border border-btc-border focus-within:border-btc-orange/50 transition-colors px-4 py-3">
            <span className="text-btc-orange font-display font-bold text-lg">₿</span>
            <input type="number" value={amount} onChange={e => setAmount(e.target.value)}
              placeholder="0.00000000" min="0" step="0.001"
              className="flex-1 bg-transparent text-white font-display text-base outline-none placeholder:text-btc-border"/>
            <span className="text-btc-muted text-[10px] font-display">BTC</span>
          </div>
        </div>
        <div className="mb-4 p-3 rounded-xl bg-btc-dark border border-btc-border space-y-1.5 text-[11px] font-display">
          {tab==='deposit' ? (<>
            <div className="flex justify-between"><span className="text-btc-muted">You receive</span><span className="text-white">{amount ? `${parseFloat(amount).toFixed(4)} svBTC` : '—'}</span></div>
            <div className="flex justify-between"><span className="text-btc-muted">Vault token</span><span className="text-btc-orange">svBTC (1:1)</span></div>
          </>) : (<>
            <div className="flex justify-between"><span className="text-btc-muted">Your stake</span><span className="text-white">{fmtBTC(satloop.userInfo?.staked)} BTC</span></div>
            <div className="flex justify-between"><span className="text-btc-muted">Outstanding debt</span><span className="text-sat-yellow">{fmtBTC(satloop.userInfo?.borrowed)} BTC</span></div>
          </>)}
        </div>
        <button onClick={submit} disabled={!wallet.connected || !amount || satloop.txPending}
          className={`w-full py-3.5 rounded-xl font-display font-bold tracking-widest text-xs transition-all active:scale-95 disabled:opacity-40 disabled:cursor-not-allowed ${
            status==='success'?'bg-sat-green text-black':status==='error'?'bg-sat-red text-white':
            tab==='deposit'?'bg-btc-orange text-black hover:shadow-[0_0_20px_rgba(247,147,26,0.4)]':'bg-btc-border text-white'}`}>
          {satloop.txPending?<span className="flex items-center justify-center gap-2"><Loader2 className="w-4 h-4 animate-spin"/>Confirming...</span>:
           status==='success'?'✓ Confirmed':status==='error'?'✗ Failed':
           tab==='deposit'?'DEPOSIT BTC':'WITHDRAW BTC'}
        </button>
        {!wallet.connected && <p className="text-center text-[10px] text-btc-muted font-display mt-3">Connect wallet to interact</p>}
      </div>
    </div>
  );
}
