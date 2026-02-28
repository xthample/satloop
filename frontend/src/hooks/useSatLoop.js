import { useState, useCallback, useEffect } from 'react';

const delay = ms => new Promise(r => setTimeout(r, ms));

export function useSatLoop(wallet) {
  const [userInfo,  setUserInfo]  = useState(null);
  const [poolInfo,  setPoolInfo]  = useState(null);
  const [txPending, setTxPending] = useState(false);
  const [txHash,    setTxHash]    = useState(null);
  const [loopState, setLoopState] = useState('idle');

  useEffect(() => {
    if (!wallet.connected) return;
    delay(400).then(() => setUserInfo({ staked:1.5, borrowed:0.65, leverage:1.43, pendingYield:14.72 }));
    delay(300).then(() => setPoolInfo({ totalStaked:845.23, tvl:42650000, apy:{ base:8.4, leveraged:28.6 } }));
  }, [wallet.connected]);

  const runTx = useCallback(async fn => {
    setTxPending(true); setTxHash(null);
    try { const r = await fn(); setTxHash(typeof r === 'string' ? r : r?.tx); return r; }
    finally { setTxPending(false); }
  }, []);

  const deposit  = useCallback(amt => runTx(async () => {
    await delay(1400);
    setUserInfo(p => ({ ...p, staked: p.staked + parseFloat(amt) }));
    return '0xdeposit_tx';
  }), [runTx]);

  const withdraw = useCallback(amt => runTx(async () => {
    await delay(1400);
    setUserInfo(p => ({ ...p, staked: Math.max(0, p.staked - parseFloat(amt)) }));
    return '0xwithdraw_tx';
  }), [runTx]);

  const harvest = useCallback(() => runTx(async () => {
    await delay(1200);
    const h = userInfo?.pendingYield || 0;
    setUserInfo(p => ({ ...p, pendingYield: 0 }));
    return { tx: '0xharvest_tx', amount: h };
  }), [runTx, userInfo]);

  const loopMax = useCallback(async (loops = 3) => {
    setLoopState('running'); setTxPending(true); setTxHash(null);
    try {
      for (let i = 1; i <= loops; i++) { await delay(900); setLoopState(`loop_${i}`); }
      await delay(400);
      const base = userInfo?.staked || 1;
      let s = base, b = 0;
      for (let i = 0; i < loops; i++) { const bw = s * 2/3; b += bw; s += bw; }
      setUserInfo(p => ({ ...p, staked: s, borrowed: b, leverage: parseFloat((s/base).toFixed(2)) }));
      setLoopState('done'); setTxHash('0xloopmax_tx');
      setTimeout(() => setLoopState('idle'), 5000);
    } finally { setTxPending(false); }
  }, [userInfo]);

  return { userInfo, poolInfo, txPending, txHash, loopState, deposit, withdraw, harvest, loopMax };
}
