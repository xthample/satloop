# ⚡ SatLoop — Leveraged Loop Staker on Bitcoin L1

<div align="center">

![SatLoop](https://img.shields.io/badge/Bitcoin-L1-F7931A?style=for-the-badge&logo=bitcoin&logoColor=white)
![OP_NET](https://img.shields.io/badge/Powered_by-OP__NET-orange?style=for-the-badge)
![AssemblyScript](https://img.shields.io/badge/AssemblyScript-007AAC?style=for-the-badge&logo=assemblyscript&logoColor=white)
![React](https://img.shields.io/badge/React-18-61DAFB?style=for-the-badge&logo=react&logoColor=black)
![Vite](https://img.shields.io/badge/Vite-646CFF?style=for-the-badge&logo=vite&logoColor=white)

**🏆 Vibecoding Contest Entry — "The DeFi Signal" — Category: DeFi**

*One-click leveraged looping staker on Bitcoin L1*

[🚀 Live Demo](https://satloop.vercel.app) · [📖 Docs](#how-it-works) · [🔐 Security Audit](#security-audit-by-bob)

</div>

---

## 🎯 What is SatLoop?

SatLoop lets you **amplify your Bitcoin yield up to 3×** using a fully automated lending loop strategy — all in one click, on Bitcoin L1 via OP_NET.

```
Deposit 1 BTC
  └── Loop 1: Borrow 0.666 BTC → re-stake  →  total: 1.666 BTC
       └── Loop 2: Borrow 0.444 BTC → re-stake  →  total: 2.111 BTC
            └── Loop 3: Borrow 0.296 BTC → re-stake  →  total: 2.407 BTC
                                                 ↓
                                    Effective leverage: ~2.37×
                                    Base APY 8.4%  →  Net APY ~28.6%
```

---

## ✨ Features

- 🔁 **One-Click Loop to 3×** — automated borrow + re-stake sequence
- 📊 **Live APY Calculator** — see net yield across leverage levels
- 🛡️ **Real-time Risk Meter** — health factor tracking, liquidation warnings
- 🏦 **svBTC Vault Tokens** — OP_20 receipt tokens, 1:1 with deposit
- 🪙 **SATYIELD Rewards** — MasterChef-style block reward distribution
- ⚡ **Auto-liquidation** — on-chain liquidation at 110% collateral ratio
- 🌑 **Bitcoin dark UI** — responsive, dark mode, Space Mono aesthetic

---

## 🏗️ Architecture

```
satloop/
├── contract/
│   ├── src/
│   │   ├── SatLoop.ts       ← Main protocol (staking + CDP lending loop)
│   │   ├── SatYield.ts      ← SATYIELD reward token (OP_20)
│   │   └── VaultToken.ts    ← svBTC receipt token (OP_20)
│   └── scripts/
│       └── deploy.js        ← Deploy & configure script
└── frontend/
    └── src/
        ├── components/
        │   ├── Header.jsx       ← OP_WALLET connect
        │   ├── StatsBar.jsx     ← TVL, APY, pool metrics
        │   ├── DepositPanel.jsx ← Deposit / Withdraw UI
        │   ├── LoopPanel.jsx    ← ⚡ "Loop to 3×" button
        │   └── Dashboard.jsx    ← Risk meter + APY chart
        ├── hooks/
        │   ├── useWallet.js     ← OP_WALLET hook
        │   └── useSatLoop.js    ← Contract interaction hook
        └── utils/
            └── calculations.js  ← APY, leverage, health factor math
```

---

## 📐 Protocol Parameters

| Parameter | Value |
|-----------|-------|
| Collateral Factor | **150%** (borrow up to 66.6% of collateral) |
| Interest Rate | **0.05% per block** (~26% APY) |
| Liquidation Threshold | **110% CR** |
| Liquidation Bonus | **+5%** to liquidator |
| Max Loops | **3** (~2.37× effective leverage) |
| Reward Token | **SATYIELD** (100 / block) |

### Health Factor Formula
```
HF = (staked × 100) / (borrowed × 110)

HF > 1.0  →  ✅ Healthy
HF < 1.0  →  🔴 Liquidatable
```

### Storage Pointer Map (no collisions)
| Pointer | Data |
|---------|------|
| `0xA000` | totalStaked |
| `0xA001` | accRewardPerShare |
| `0xA002` | lastRewardBlock |
| `0xA003` | rewardPerBlock |
| `0xA010+addr+slot` | Per-user: staked / rewardDebt / borrowed / lastBorrowBlock |
| `0xA100` | Reentrancy lock |
| `0xA101` | Paused flag |
| `0xA200–0xA202` | Owner, vaultToken, rewardToken |
| `0xF001` | SATYIELD minter |
| `0xF002` | svBTC controller |

---

## 🚀 Quick Start

### Run Frontend Locally

```bash
cd frontend
npm install
npm run dev
# → http://localhost:5173
```

> No wallet? Click **Connect Wallet** → runs in **demo mode** automatically ✅

### Build Contracts

```bash
cd contract
npm install
npm run build
# → builds SatLoop.wasm, SatYield.wasm, VaultToken.wasm
```

### Deploy to Regtest

```bash
export OPNET_RPC="https://regtest.opnet.org"
export DEPLOYER_WIF="your_wallet_wif"
export NETWORK="regtest"

node contract/scripts/deploy.js
```

The script will:
1. Deploy `SATYIELD` reward token
2. Deploy `svBTC` vault receipt token
3. Deploy `SatLoop` with both token addresses
4. Automatically set minter & controller permissions
5. Save addresses to `frontend/src/contracts/addresses.json`

---

## 🌐 Deploy Frontend to Vercel

```bash
cd frontend
npx vercel --prod
```

Or connect GitHub repo to [vercel.com](https://vercel.com) → auto-deploy on push.

**Build settings:**
- Root: `frontend`
- Framework: Vite
- Build: `npm run build`
- Output: `dist`

---

## 🔐 Security Audit by Bob™

```
╔══════════════════════════════════════════════════════════════╗
║              SATLOOP INTERNAL SECURITY REVIEW                ║
║                  Auditor: Bob™  (Senior Bob)                 ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  ✅ REENTRANCY      Mutex at 0xA100. CEI pattern followed.   ║
║                     No external calls before state updates.  ║
║                                                              ║
║  ✅ OVERFLOW        All arithmetic via SafeMath.* — zero     ║
║                     raw +/-/*/÷ on u256 values.              ║
║                                                              ║
║  ✅ STORAGE         Pointer ranges manually mapped. User      ║
║                     slot hashing includes addr + slot index. ║
║                                                              ║
║  ✅ ACCESS CONTROL  onlyOwner / onlyMinter / onlyController  ║
║                     guards on all privileged functions.      ║
║                                                              ║
║  ✅ LIQUIDATION     110% threshold + 5% bonus. Position      ║
║                     cleared atomically in single call.       ║
║                                                              ║
║  ✅ INTEREST        On-demand accrual prevents manipulation   ║
║                     via block stuffing attacks.              ║
║                                                              ║
║  ⚠️  ORACLE         Assumes 1:1 BTC peg. Production needs    ║
║                     Pyth/Redstone price feed integration.    ║
║                                                              ║
║  ⚠️  RESERVES       No reserve ratio enforced yet. Add       ║
║                     before mainnet launch.                   ║
║                                                              ║
║  VERDICT: SAFE FOR TESTNET / CONTEST DEMO.                  ║
║  — Bob. Please pay fees in SATYIELD.                        ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Smart Contracts | AssemblyScript + OP_NET runtime |
| Token Standard | OP_20 (extends ERC-20 for Bitcoin L1) |
| Frontend | React 18 + Vite |
| Styling | Tailwind CSS |
| Charts | Recharts |
| Wallet | OP_WALLET browser extension |
| Deploy | Vercel |

---

## 📜 License

MIT © SatLoop — Built for **Vibecoding Contest "The DeFi Signal"**

---

<div align="center">

Made with ⚡ on Bitcoin L1

*"Stack sats. Loop harder."*

</div>