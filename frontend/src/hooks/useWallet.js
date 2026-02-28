import { useState, useCallback, useEffect } from 'react';

export function useWallet() {
  const [address,   setAddress]   = useState(null);
  const [connected, setConnected] = useState(false);
  const [loading,   setLoading]   = useState(false);
  const [error,     setError]     = useState(null);
  const [network,   setNetwork]   = useState('regtest');

  const getProvider = () => window?.opnet || window?.OPNet || null;

  const connect = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const p = getProvider();
      if (!p) {
        await new Promise(r => setTimeout(r, 700));
        setAddress('bc1pdemo4satloop9xvf3k8qj7');
        setConnected(true);
        return;
      }
      const accounts = await p.requestAccounts();
      if (accounts?.length) {
        setAddress(accounts[0]); setConnected(true);
        setNetwork((await p.getNetwork())?.name || 'mainnet');
      }
    } catch (e) { setError(e.message); }
    finally { setLoading(false); }
  }, []);

  const disconnect = useCallback(() => { setAddress(null); setConnected(false); }, []);

  useEffect(() => {
    const p = getProvider();
    if (p?.selectedAccount) { setAddress(p.selectedAccount); setConnected(true); }
    const onChange = accs => accs?.length ? setAddress(accs[0]) : (setAddress(null), setConnected(false));
    p?.on?.('accountsChanged', onChange);
    return () => p?.removeListener?.('accountsChanged', onChange);
  }, []);

  return { address, connected, loading, error, network, connect, disconnect };
}
