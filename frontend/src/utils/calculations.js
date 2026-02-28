export const BASE_APY        = 8.4;
export const BORROW_APY      = 0.0005 * 144 * 365 * 100; // ~26.28%
export const COLLATERAL_FACTOR = 1.5;

export function calcLeverage(loops = 0) {
  let lev = 1;
  for (let i = 0; i < loops; i++) lev += (1 / COLLATERAL_FACTOR) ** (i + 1);
  return parseFloat(lev.toFixed(4));
}
export function calcLeveragedAPY(loops = 0) {
  const lev = calcLeverage(loops);
  return Math.max(0, lev * BASE_APY - (lev - 1) * BORROW_APY);
}
export function calcHealthFactor(staked, borrowed) {
  if (!borrowed) return Infinity;
  return (staked * 100) / (borrowed * 110);
}
export function calcRisk(hf) {
  if (!isFinite(hf) || hf > 5) return 0;
  return Math.min(100, Math.max(0, Math.round((1 / hf) * 100)));
}
export function riskLabel(risk) {
  if (risk < 20) return { label: 'SAFE',      color: '#00FF94' };
  if (risk < 45) return { label: 'LOW RISK',  color: '#FFD166' };
  if (risk < 70) return { label: 'MEDIUM',    color: '#F7931A' };
  return                 { label: 'HIGH RISK', color: '#FF3B3B' };
}
export function generateApyChartData() {
  return [0,1,2,3].map(loops => ({
    loops,
    leverage: parseFloat(calcLeverage(loops).toFixed(2)),
    apy:      parseFloat(calcLeveragedAPY(loops).toFixed(2)),
    base:     BASE_APY,
  }));
}
export const fmtBTC = (v, d=4) => v == null ? '—' : parseFloat(v).toFixed(d);
export const fmtUSD = v => new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0}).format(v);
export const shortAddr = a => a ? `${a.slice(0,7)}…${a.slice(-5)}` : '';
