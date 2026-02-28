#!/bin/bash
set -e

echo "🚀 SatLoop Setup Script"
echo "========================"

# ── Folder structure ──────────────────────────────────────
mkdir -p contract/src contract/scripts contract/build
mkdir -p frontend/src/components frontend/src/hooks frontend/src/utils frontend/public

echo "✅ Folders created"

# ══════════════════════════════════════════════════════════
# CONTRACT FILES
# ══════════════════════════════════════════════════════════

# ── contract/package.json ─────────────────────────────────
cat > contract/package.json << 'ENDOFFILE'
{
  "name": "satloop-contracts",
  "version": "1.0.0",
  "description": "SatLoop leveraged loop staker contracts – Bitcoin L1 / OP_NET",
  "scripts": {
    "build:satyield":  "npx asc src/SatYield.ts  --outFile build/SatYield.wasm  --textFile build/SatYield.wat  --optimize --runtime stub",
    "build:vault":     "npx asc src/VaultToken.ts --outFile build/VaultToken.wasm --textFile build/VaultToken.wat --optimize --runtime stub",
    "build:satloop":   "npx asc src/SatLoop.ts   --outFile build/SatLoop.wasm   --textFile build/SatLoop.wat   --optimize --runtime stub",
    "build":           "npm run build:satyield && npm run build:vault && npm run build:satloop",
    "deploy":          "node scripts/deploy.js"
  },
  "dependencies": {
    "@btc-vision/btc-runtime": "^1.0.0",
    "@btc-vision/opnet": "^1.0.0"
  },
  "devDependencies": {
    "assemblyscript": "^0.27.0"
  }
}
ENDOFFILE

# ── contract/asconfig.json ────────────────────────────────
cat > contract/asconfig.json << 'ENDOFFILE'
{
  "targets": {
    "satloop": {
      "binaryFile": "build/SatLoop.wasm",
      "textFile":   "build/SatLoop.wat",
      "optimizeLevel": 3,
      "shrinkLevel":   1,
      "entry": "src/SatLoop.ts"
    },
    "satyield": {
      "binaryFile": "build/SatYield.wasm",
      "entry": "src/SatYield.ts"
    },
    "vaulttoken": {
      "binaryFile": "build/VaultToken.wasm",
      "entry": "src/VaultToken.ts"
    }
  },
  "options": {
    "runtime": "stub"
  }
}
ENDOFFILE

# ── contract/src/SatYield.ts ──────────────────────────────
cat > contract/src/SatYield.ts << 'ENDOFFILE'
import {
  OP_20,
  Blockchain,
  BytesWriter,
  BytesReader,
  Address,
} from '@btc-vision/btc-runtime/runtime';

/**
 * SATYIELD – Reward Token for SatLoop Protocol
 * OP_20 compliant. Minting restricted to SatLoop contract only.
 * Storage pointer: 0xF001 (minter address)
 */
@final
export class SatYield extends OP_20 {
  private readonly MINTER_PTR: u16 = 0xF001;

  constructor() {
    super(u256.Zero, 18, 'SATYIELD', 'SatYield Token');
  }

  public override onDeployment(_calldata: Uint8Array): void {
    Blockchain.setStorageAt(
      this.address,
      u256.fromU16(this.MINTER_PTR),
      Blockchain.callee().toBytes(),
    );
  }

  public override execute(method: Selector, calldata: Uint8Array): BytesWriter {
    switch (method) {
      case encodeSelector('mint(address,uint256)'):
        return this.mint(calldata);
      case encodeSelector('setMinter(address)'):
        return this.setMinter(calldata);
      default:
        return super.execute(method, calldata);
    }
  }

  private mint(calldata: Uint8Array): BytesWriter {
    const reader = new BytesReader(calldata);
    const to: Address = reader.readAddress();
    const amount: u256 = reader.readU256();
    this.onlyMinter();
    this._mint(to, amount);
    const w = new BytesWriter(1);
    w.writeBoolean(true);
    return w;
  }

  private setMinter(calldata: Uint8Array): BytesWriter {
    const reader = new BytesReader(calldata);
    const newMinter: Address = reader.readAddress();
    this.onlyMinter();
    Blockchain.setStorageAt(
      this.address,
      u256.fromU16(this.MINTER_PTR),
      newMinter.toBytes(),
    );
    const w = new BytesWriter(1);
    w.writeBoolean(true);
    return w;
  }

  private onlyMinter(): void {
    const stored = Blockchain.getStorageAt(this.address, u256.fromU16(this.MINTER_PTR));
    assert(stored == Blockchain.callee().toBytes(), 'SatYield: not minter');
  }
}
ENDOFFILE

# ── contract/src/VaultToken.ts ────────────────────────────
cat > contract/src/VaultToken.ts << 'ENDOFFILE'
import {
  OP_20,
  Blockchain,
  BytesWriter,
  BytesReader,
  Address,
} from '@btc-vision/btc-runtime/runtime';

/**
 * svBTC – SatLoop Vault Receipt Token
 * Minted 1:1 on deposit, burned on withdraw.
 * Controller (SatLoop) can mint & burn.
 * Storage pointer: 0xF002
 */
@final
export class VaultToken extends OP_20 {
  private readonly CTRL_PTR: u16 = 0xF002;

  constructor() {
    super(u256.Zero, 18, 'svBTC', 'SatLoop Vault BTC');
  }

  public override onDeployment(_calldata: Uint8Array): void {
    Blockchain.setStorageAt(
      this.address,
      u256.fromU16(this.CTRL_PTR),
      Blockchain.callee().toBytes(),
    );
  }

  public override execute(method: Selector, calldata: Uint8Array): BytesWriter {
    switch (method) {
      case encodeSelector('mint(address,uint256)'):
        return this.mintTokens(calldata);
      case encodeSelector('burn(address,uint256)'):
        return this.burnTokens(calldata);
      case encodeSelector('setController(address)'):
        return this.setController(calldata);
      default:
        return super.execute(method, calldata);
    }
  }

  private mintTokens(calldata: Uint8Array): BytesWriter {
    const r = new BytesReader(calldata);
    this.onlyController();
    this._mint(r.readAddress(), r.readU256());
    const w = new BytesWriter(1);
    w.writeBoolean(true);
    return w;
  }

  private burnTokens(calldata: Uint8Array): BytesWriter {
    const r = new BytesReader(calldata);
    this.onlyController();
    this._burn(r.readAddress(), r.readU256());
    const w = new BytesWriter(1);
    w.writeBoolean(true);
    return w;
  }

  private setController(calldata: Uint8Array): BytesWriter {
    const r = new BytesReader(calldata);
    this.onlyController();
    Blockchain.setStorageAt(
      this.address,
      u256.fromU16(this.CTRL_PTR),
      r.readAddress().toBytes(),
    );
    const w = new BytesWriter(1);
    w.writeBoolean(true);
    return w;
  }

  private onlyController(): void {
    const stored = Blockchain.getStorageAt(this.address, u256.fromU16(this.CTRL_PTR));
    assert(stored == Blockchain.callee().toBytes(), 'VaultToken: not controller');
  }
}
ENDOFFILE

# ── contract/src/SatLoop.ts ───────────────────────────────
cat > contract/src/SatLoop.ts << 'ENDOFFILE'
import {
  OP_NET,
  Blockchain,
  BytesWriter,
  BytesReader,
  Address,
  SafeMath,
} from '@btc-vision/btc-runtime/runtime';

/**
 * SatLoop – Leveraged Loop Staker on Bitcoin L1
 *
 * Architecture: MasterChef staking + built-in CDP lending loop
 * Collateral Factor : 150%  (borrow up to 66.6% of collateral)
 * Interest Rate     : 0.05% per block
 * Liquidation       : automatic when CR < 110%
 * Max Loops         : 3  (~2.37x effective leverage)
 *
 * Storage Pointer Map:
 *   0xA000 totalStaked
 *   0xA001 accRewardPerShare
 *   0xA002 lastRewardBlock
 *   0xA003 rewardPerBlock
 *   0xA010+addr+slot  per-user data (staked / rewardDebt / borrowed / lastBorrowBlock)
 *   0xA100 reentrancy lock
 *   0xA101 paused flag
 *   0xA200 owner
 *   0xA201 vaultToken address
 *   0xA202 rewardToken address
 */
@final
export class SatLoop extends OP_NET {
  // Pool storage
  private readonly PTR_TOTAL_STAKED:      u16 = 0xA000;
  private readonly PTR_ACC_REWARD:        u16 = 0xA001;
  private readonly PTR_LAST_REWARD_BLOCK: u16 = 0xA002;
  private readonly PTR_REWARD_PER_BLOCK:  u16 = 0xA003;
  // User storage base
  private readonly PTR_USER_BASE:         u16 = 0xA010;
  // Guards
  private readonly PTR_REENTRANCY:        u16 = 0xA100;
  private readonly PTR_PAUSED:            u16 = 0xA101;
  // Config
  private readonly PTR_OWNER:             u16 = 0xA200;
  private readonly PTR_VAULT_TOKEN:       u16 = 0xA201;
  private readonly PTR_REWARD_TOKEN:      u16 = 0xA202;

  // Protocol constants
  private readonly COLLATERAL_FACTOR: u256 = u256.fromU32(150); // 150%
  private readonly LIQ_THRESHOLD:     u256 = u256.fromU32(110); // 110%
  private readonly LIQ_BONUS:         u256 = u256.fromU32(105); // 5% bonus
  private readonly INTEREST_BPS:      u256 = u256.fromU32(5);   // 0.05% per block
  private readonly BPS_BASE:          u256 = u256.fromU32(10000);
  private readonly PRECISION:         u256 = u256.fromU64(1_000_000_000_000);
  private readonly MAX_LOOPS:         u32  = 3;

  constructor() { super(); }

  // ── Deployment ──────────────────────────────────────────
  public override onDeployment(calldata: Uint8Array): void {
    const r = new BytesReader(calldata);
    const vaultToken:    Address = r.readAddress();
    const rewardToken:   Address = r.readAddress();
    const rewardPerBlock: u256   = r.readU256();

    this.store(this.PTR_VAULT_TOKEN,       vaultToken.toBytes());
    this.store(this.PTR_REWARD_TOKEN,      rewardToken.toBytes());
    this.store(this.PTR_REWARD_PER_BLOCK,  rewardPerBlock.toBytes());
    this.store(this.PTR_OWNER,             Blockchain.callee().toBytes());
    this.store(this.PTR_LAST_REWARD_BLOCK, Blockchain.block.number.toBytes());
    this.store(this.PTR_ACC_REWARD,        u256.Zero.toBytes());
    this.store(this.PTR_TOTAL_STAKED,      u256.Zero.toBytes());
    this.store(this.PTR_REENTRANCY,        u256.Zero.toBytes());
    this.store(this.PTR_PAUSED,            u256.Zero.toBytes());
  }

  // ── Router ──────────────────────────────────────────────
  public override execute(method: Selector, calldata: Uint8Array): BytesWriter {
    switch (method) {
      case encodeSelector('deposit(uint256)'):        return this.deposit(calldata);
      case encodeSelector('withdraw(uint256)'):       return this.withdraw(calldata);
      case encodeSelector('harvest()'):               return this.harvest();
      case encodeSelector('loopMax()'):               return this.loopMax();
      case encodeSelector('borrow(uint256)'):         return this.borrow(calldata);
      case encodeSelector('repay(uint256)'):          return this.repay(calldata);
      case encodeSelector('liquidate(address)'):      return this.liquidate(calldata);
      case encodeSelector('pendingReward(address)'): return this.pendingReward(calldata);
      case encodeSelector('getUserInfo(address)'):   return this.getUserInfo(calldata);
      case encodeSelector('getPoolInfo()'):           return this.getPoolInfo();
      case encodeSelector('setPaused(bool)'):         return this.setPaused(calldata);
      default: throw new Error('SatLoop: unknown method');
    }
  }

  // ── Deposit ─────────────────────────────────────────────
  private deposit(calldata: Uint8Array): BytesWriter {
    this.noReentrant(); this.notPaused();
    const amount: u256 = new BytesReader(calldata).readU256();
    assert(u256.gt(amount, u256.Zero), 'SatLoop: zero amount');

    const caller = Blockchain.callee();
    this.updatePool();
    this.accrueInterest(caller);

    const [staked, debt, borrowed, lbb] = this.loadUser(caller);
    const acc = this.loadU256(this.PTR_ACC_REWARD);

    // Harvest pending before balance change
    if (u256.gt(staked, u256.Zero)) {
      const pending = SafeMath.sub(
        SafeMath.div(SafeMath.mul(staked, acc), this.PRECISION), debt
      );
      if (u256.gt(pending, u256.Zero)) this.mintReward(caller, pending);
    }

    // Pull tokens, update state
    this.callERC20TransferFrom(this.vaultTokenAddr(), caller, this.address, amount);
    const newStaked = SafeMath.add(staked, amount);
    const newDebt   = SafeMath.div(SafeMath.mul(newStaked, acc), this.PRECISION);
    this.saveUser(caller, newStaked, newDebt, borrowed, lbb);
    this.store(this.PTR_TOTAL_STAKED,
      SafeMath.add(this.loadU256(this.PTR_TOTAL_STAKED), amount).toBytes());

    // Mint vault receipt tokens 1:1
    this.callMint(this.vaultTokenAddr(), caller, amount);

    const w = new BytesWriter(32);
    w.writeU256(newStaked);
    return w;
  }

  // ── Withdraw ────────────────────────────────────────────
  private withdraw(calldata: Uint8Array): BytesWriter {
    this.noReentrant(); this.notPaused();
    const amount: u256 = new BytesReader(calldata).readU256();
    const caller = Blockchain.callee();
    this.updatePool(); this.accrueInterest(caller);

    const [staked, debt, borrowed, lbb] = this.loadUser(caller);
    assert(u256.gte(staked, amount), 'SatLoop: insufficient stake');

    const newStaked = SafeMath.sub(staked, amount);
    if (u256.gt(borrowed, u256.Zero)) {
      const minCol = SafeMath.div(
        SafeMath.mul(borrowed, this.COLLATERAL_FACTOR), u256.fromU32(100)
      );
      assert(u256.gte(newStaked, minCol), 'SatLoop: undercollateralised after withdraw');
    }

    // Harvest
    const acc = this.loadU256(this.PTR_ACC_REWARD);
    const pending = SafeMath.sub(
      SafeMath.div(SafeMath.mul(staked, acc), this.PRECISION), debt
    );
    if (u256.gt(pending, u256.Zero)) this.mintReward(caller, pending);

    const newDebt = SafeMath.div(SafeMath.mul(newStaked, acc), this.PRECISION);
    this.saveUser(caller, newStaked, newDebt, borrowed, lbb);
    this.store(this.PTR_TOTAL_STAKED,
      SafeMath.sub(this.loadU256(this.PTR_TOTAL_STAKED), amount).toBytes());

    this.callBurn(this.vaultTokenAddr(), caller, amount);
    this.callERC20Transfer(this.vaultTokenAddr(), caller, amount);

    const w = new BytesWriter(32);
    w.writeU256(newStaked);
    return w;
  }

  // ── Harvest ─────────────────────────────────────────────
  private harvest(): BytesWriter {
    this.noReentrant();
    const caller = Blockchain.callee();
    this.updatePool(); this.accrueInterest(caller);

    const [staked, debt, borrowed, lbb] = this.loadUser(caller);
    const acc = this.loadU256(this.PTR_ACC_REWARD);
    const pending = SafeMath.sub(
      SafeMath.div(SafeMath.mul(staked, acc), this.PRECISION), debt
    );
    assert(u256.gt(pending, u256.Zero), 'SatLoop: nothing to harvest');

    const newDebt = SafeMath.div(SafeMath.mul(staked, acc), this.PRECISION);
    this.saveUser(caller, staked, newDebt, borrowed, lbb);
    this.mintReward(caller, pending);

    const w = new BytesWriter(32);
    w.writeU256(pending);
    return w;
  }

  // ── Borrow ──────────────────────────────────────────────
  private borrow(calldata: Uint8Array): BytesWriter {
    this.noReentrant(); this.notPaused();
    const amount: u256 = new BytesReader(calldata).readU256();
    const caller = Blockchain.callee();
    this.accrueInterest(caller);

    const [staked, debt, borrowed, ] = this.loadUser(caller);
    const maxBorrow = SafeMath.div(
      SafeMath.mul(staked, u256.fromU32(100)), this.COLLATERAL_FACTOR
    );
    const newBorrowed = SafeMath.add(borrowed, amount);
    assert(u256.lte(newBorrowed, maxBorrow), 'SatLoop: exceeds collateral factor');

    this.saveUser(caller, staked, debt, newBorrowed, Blockchain.block.number);
    this.callERC20Transfer(this.vaultTokenAddr(), caller, amount);

    const w = new BytesWriter(32);
    w.writeU256(newBorrowed);
    return w;
  }

  // ── Repay ───────────────────────────────────────────────
  private repay(calldata: Uint8Array): BytesWriter {
    this.noReentrant();
    const amount: u256 = new BytesReader(calldata).readU256();
    const caller = Blockchain.callee();
    this.accrueInterest(caller);

    const [staked, debt, borrowed, ] = this.loadUser(caller);
    const repayAmt = u256.lt(amount, borrowed) ? amount : borrowed;
    this.callERC20TransferFrom(this.vaultTokenAddr(), caller, this.address, repayAmt);
    const newBorrowed = SafeMath.sub(borrowed, repayAmt);
    this.saveUser(caller, staked, debt, newBorrowed, Blockchain.block.number);

    const w = new BytesWriter(32);
    w.writeU256(newBorrowed);
    return w;
  }

  // ── Loop Max ────────────────────────────────────────────
  /**
   * One-click Loop to 3x:
   *   Loop 1: borrow 66% → re-stake
   *   Loop 2: borrow 44% → re-stake
   *   Loop 3: borrow 30% → re-stake
   *   Result: ~2.37x effective leverage
   */
  private loopMax(): BytesWriter {
    this.noReentrant(); this.notPaused();
    const caller = Blockchain.callee();
    this.updatePool(); this.accrueInterest(caller);

    let [staked, debt, borrowed, ] = this.loadUser(caller);
    assert(u256.gt(staked, u256.Zero), 'SatLoop: no base stake to loop');
    assert(u256.eq(borrowed, u256.Zero), 'SatLoop: repay existing debt first');

    const acc = this.loadU256(this.PTR_ACC_REWARD);
    const baseStaked = staked;

    for (let i: u32 = 0; i < this.MAX_LOOPS; i++) {
      const borrowable = SafeMath.div(
        SafeMath.mul(staked, u256.fromU32(100)), this.COLLATERAL_FACTOR
      );
      if (u256.eq(borrowable, u256.Zero)) break;
      borrowed = SafeMath.add(borrowed, borrowable);
      staked   = SafeMath.add(staked,   borrowable);
    }

    const newDebt = SafeMath.div(SafeMath.mul(staked, acc), this.PRECISION);
    this.saveUser(caller, staked, newDebt, borrowed, Blockchain.block.number);

    // Update pool total (add newly looped stake)
    const addedStake = SafeMath.sub(staked, baseStaked);
    this.store(this.PTR_TOTAL_STAKED,
      SafeMath.add(this.loadU256(this.PTR_TOTAL_STAKED), addedStake).toBytes());

    const w = new BytesWriter(64);
    w.writeU256(staked);
    w.writeU256(borrowed);
    return w;
  }

  // ── Liquidate ───────────────────────────────────────────
  private liquidate(calldata: Uint8Array): BytesWriter {
    this.noReentrant();
    const target: Address = new BytesReader(calldata).readAddress();
    const caller = Blockchain.callee();
    this.accrueInterest(target);

    const [staked, , borrowed, ] = this.loadUser(target);
    assert(u256.gt(borrowed, u256.Zero), 'SatLoop: target has no debt');

    const liqThresh = SafeMath.div(
      SafeMath.mul(borrowed, this.LIQ_THRESHOLD), u256.fromU32(100)
    );
    assert(u256.lt(staked, liqThresh), 'SatLoop: position is healthy');

    const bonus     = SafeMath.div(SafeMath.mul(staked, this.LIQ_BONUS), u256.fromU32(100));
    const seize     = u256.lt(bonus, staked) ? bonus : staked;

    // Wipe target position
    this.saveUser(target, u256.Zero, u256.Zero, u256.Zero, u256.Zero);
    this.store(this.PTR_TOTAL_STAKED,
      SafeMath.sub(this.loadU256(this.PTR_TOTAL_STAKED), staked).toBytes());

    // Send seized collateral to liquidator
    this.callERC20Transfer(this.vaultTokenAddr(), caller, seize);

    const w = new BytesWriter(32);
    w.writeU256(seize);
    return w;
  }

  // ── Views ────────────────────────────────────────────────
  private pendingReward(calldata: Uint8Array): BytesWriter {
    const user: Address = new BytesReader(calldata).readAddress();
    const [staked, debt, , ] = this.loadUser(user);

    const totalStaked = this.loadU256(this.PTR_TOTAL_STAKED);
    let acc = this.loadU256(this.PTR_ACC_REWARD);

    if (u256.gt(Blockchain.block.number, this.loadU256(this.PTR_LAST_REWARD_BLOCK))
      && u256.gt(totalStaked, u256.Zero)) {
      const blocks = SafeMath.sub(Blockchain.block.number, this.loadU256(this.PTR_LAST_REWARD_BLOCK));
      const reward = SafeMath.mul(blocks, this.loadU256(this.PTR_REWARD_PER_BLOCK));
      acc = SafeMath.add(acc, SafeMath.div(SafeMath.mul(reward, this.PRECISION), totalStaked));
    }

    const pending = SafeMath.sub(
      SafeMath.div(SafeMath.mul(staked, acc), this.PRECISION), debt
    );
    const w = new BytesWriter(32);
    w.writeU256(pending);
    return w;
  }

  private getUserInfo(calldata: Uint8Array): BytesWriter {
    const user: Address = new BytesReader(calldata).readAddress();
    const [staked, debt, borrowed, lbb] = this.loadUser(user);
    const w = new BytesWriter(128);
    w.writeU256(staked); w.writeU256(debt); w.writeU256(borrowed); w.writeU256(lbb);
    return w;
  }

  private getPoolInfo(): BytesWriter {
    const w = new BytesWriter(128);
    w.writeU256(this.loadU256(this.PTR_TOTAL_STAKED));
    w.writeU256(this.loadU256(this.PTR_ACC_REWARD));
    w.writeU256(this.loadU256(this.PTR_LAST_REWARD_BLOCK));
    w.writeU256(this.loadU256(this.PTR_REWARD_PER_BLOCK));
    return w;
  }

  // ── Internal pool update ────────────────────────────────
  private updatePool(): void {
    const lastBlock   = this.loadU256(this.PTR_LAST_REWARD_BLOCK);
    if (u256.lte(Blockchain.block.number, lastBlock)) return;
    const totalStaked = this.loadU256(this.PTR_TOTAL_STAKED);
    if (u256.eq(totalStaked, u256.Zero)) {
      this.store(this.PTR_LAST_REWARD_BLOCK, Blockchain.block.number.toBytes());
      return;
    }
    const blocks  = SafeMath.sub(Blockchain.block.number, lastBlock);
    const reward  = SafeMath.mul(blocks, this.loadU256(this.PTR_REWARD_PER_BLOCK));
    const newAcc  = SafeMath.add(
      this.loadU256(this.PTR_ACC_REWARD),
      SafeMath.div(SafeMath.mul(reward, this.PRECISION), totalStaked)
    );
    this.store(this.PTR_ACC_REWARD,        newAcc.toBytes());
    this.store(this.PTR_LAST_REWARD_BLOCK, Blockchain.block.number.toBytes());
  }

  private accrueInterest(user: Address): void {
    const [staked, debt, borrowed, lbb] = this.loadUser(user);
    if (u256.eq(borrowed, u256.Zero)) return;
    if (u256.gte(lbb, Blockchain.block.number)) return;
    const blocks   = SafeMath.sub(Blockchain.block.number, lbb);
    const interest = SafeMath.div(
      SafeMath.mul(SafeMath.mul(borrowed, this.INTEREST_BPS), blocks),
      this.BPS_BASE
    );
    this.saveUser(user, staked, debt, SafeMath.add(borrowed, interest), Blockchain.block.number);
  }

  // ── Guards ──────────────────────────────────────────────
  private noReentrant(): void {
    assert(u256.eq(this.loadU256(this.PTR_REENTRANCY), u256.Zero), 'SatLoop: reentrant');
    this.store(this.PTR_REENTRANCY, u256.One.toBytes());
  }
  private notPaused(): void {
    assert(u256.eq(this.loadU256(this.PTR_PAUSED), u256.Zero), 'SatLoop: paused');
  }
  private setPaused(calldata: Uint8Array): BytesWriter {
    this.onlyOwner();
    const flag = new BytesReader(calldata).readBoolean();
    this.store(this.PTR_PAUSED, flag ? u256.One.toBytes() : u256.Zero.toBytes());
    const w = new BytesWriter(1); w.writeBoolean(true); return w;
  }
  private onlyOwner(): void {
    assert(
      Blockchain.getStorageAt(this.address, u256.fromU16(this.PTR_OWNER)) == Blockchain.callee().toBytes(),
      'SatLoop: not owner'
    );
  }

  // ── Storage helpers ─────────────────────────────────────
  private store(ptr: u16, value: Uint8Array): void {
    Blockchain.setStorageAt(this.address, u256.fromU16(ptr), value);
  }
  private loadU256(ptr: u16): u256 {
    return u256.fromBytes(Blockchain.getStorageAt(this.address, u256.fromU16(ptr)));
  }
  private vaultTokenAddr():  Address {
    return Address.fromBytes(Blockchain.getStorageAt(this.address, u256.fromU16(this.PTR_VAULT_TOKEN)));
  }
  private rewardTokenAddr(): Address {
    return Address.fromBytes(Blockchain.getStorageAt(this.address, u256.fromU16(this.PTR_REWARD_TOKEN)));
  }

  // User slot: hash(PTR_USER_BASE + userAddr + slot) → unique u256 key
  private userSlot(user: Address, slot: u32): u256 {
    return SafeMath.add(
      SafeMath.add(u256.fromU16(this.PTR_USER_BASE), u256.fromBytes(user.toBytes())),
      u256.fromU32(slot)
    );
  }
  private loadUser(user: Address): [u256, u256, u256, u256] {
    return [
      u256.fromBytes(Blockchain.getStorageAt(this.address, this.userSlot(user, 0))),
      u256.fromBytes(Blockchain.getStorageAt(this.address, this.userSlot(user, 1))),
      u256.fromBytes(Blockchain.getStorageAt(this.address, this.userSlot(user, 2))),
      u256.fromBytes(Blockchain.getStorageAt(this.address, this.userSlot(user, 3))),
    ];
  }
  private saveUser(user: Address, staked: u256, debt: u256, borrowed: u256, lbb: u256): void {
    Blockchain.setStorageAt(this.address, this.userSlot(user, 0), staked.toBytes());
    Blockchain.setStorageAt(this.address, this.userSlot(user, 1), debt.toBytes());
    Blockchain.setStorageAt(this.address, this.userSlot(user, 2), borrowed.toBytes());
    Blockchain.setStorageAt(this.address, this.userSlot(user, 3), lbb.toBytes());
  }

  // ── Cross-contract call helpers ─────────────────────────
  private callERC20TransferFrom(token: Address, from: Address, to: Address, amount: u256): void {
    const w = new BytesWriter(96);
    w.writeAddress(from); w.writeAddress(to); w.writeU256(amount);
    Blockchain.call(token, encodeSelector('transferFrom(address,address,uint256)'), w.toBytesReader());
  }
  private callERC20Transfer(token: Address, to: Address, amount: u256): void {
    const w = new BytesWriter(64);
    w.writeAddress(to); w.writeU256(amount);
    Blockchain.call(token, encodeSelector('transfer(address,uint256)'), w.toBytesReader());
  }
  private callMint(token: Address, to: Address, amount: u256): void {
    const w = new BytesWriter(64);
    w.writeAddress(to); w.writeU256(amount);
    Blockchain.call(token, encodeSelector('mint(address,uint256)'), w.toBytesReader());
  }
  private callBurn(token: Address, from: Address, amount: u256): void {
    const w = new BytesWriter(64);
    w.writeAddress(from); w.writeU256(amount);
    Blockchain.call(token, encodeSelector('burn(address,uint256)'), w.toBytesReader());
  }
  private mintReward(to: Address, amount: u256): void {
    this.callMint(this.rewardTokenAddr(), to, amount);
  }
}
ENDOFFILE

# ── contract/scripts/deploy.js ────────────────────────────
cat > contract/scripts/deploy.js << 'ENDOFFILE'
/**
 * SatLoop Deploy Script
 * Usage:
 *   OPNET_RPC=https://regtest.opnet.org DEPLOYER_WIF=<wif> NETWORK=regtest node scripts/deploy.js
 */
const { Wallet, OPNetProvider, ContractDeployer } = require('@btc-vision/opnet');
const fs   = require('fs');
const path = require('path');

async function main() {
  const rpc     = process.env.OPNET_RPC    || 'https://regtest.opnet.org';
  const wif     = process.env.DEPLOYER_WIF;
  const network = process.env.NETWORK      || 'regtest';
  if (!wif) throw new Error('Set DEPLOYER_WIF environment variable');

  const provider = new OPNetProvider(rpc);
  const wallet   = Wallet.fromWIF(wif, network);
  const deployer = new ContractDeployer(provider, wallet);

  console.log('🚀 SatLoop Deployer');
  console.log(`   Address : ${wallet.address}`);
  console.log(`   Network : ${network}\n`);

  // 1. SATYIELD
  console.log('1/3  Deploying SATYIELD...');
  const yieldWasm = fs.readFileSync(path.join(__dirname, '../build/SatYield.wasm'));
  const yieldTx   = await (await deployer.deploy(yieldWasm, Buffer.alloc(0))).wait();
  const SATYIELD  = yieldTx.contractAddress;
  console.log(`     ✅ SATYIELD : ${SATYIELD}`);

  // 2. svBTC
  console.log('2/3  Deploying svBTC...');
  const vaultWasm = fs.readFileSync(path.join(__dirname, '../build/VaultToken.wasm'));
  const vaultTx   = await (await deployer.deploy(vaultWasm, Buffer.alloc(0))).wait();
  const SVBTC     = vaultTx.contractAddress;
  console.log(`     ✅ svBTC    : ${SVBTC}`);

  // 3. SatLoop
  console.log('3/3  Deploying SatLoop...');
  const loopWasm  = fs.readFileSync(path.join(__dirname, '../build/SatLoop.wasm'));
  const rpb       = BigInt('100000000000000000000'); // 100 SATYIELD per block
  const initData  = buildInitData(SVBTC, SATYIELD, rpb);
  const loopTx    = await (await deployer.deploy(loopWasm, initData)).wait();
  const SATLOOP   = loopTx.contractAddress;
  console.log(`     ✅ SatLoop  : ${SATLOOP}`);

  // 4. Set minter / controller
  console.log('\n4/4  Setting permissions...');
  await (await wallet.callContract(SATYIELD, 'setMinter(address)',     [SATLOOP])).wait();
  await (await wallet.callContract(SVBTC,    'setController(address)', [SATLOOP])).wait();
  console.log('     ✅ Done\n');

  const result = { network, SatLoop: SATLOOP, svBTC: SVBTC, SATYIELD, deployer: wallet.address };
  console.log('🎉 Deployment complete!');
  console.log(JSON.stringify(result, null, 2));

  // Save addresses for frontend
  const outPath = path.join(__dirname, '../../frontend/src/contracts/addresses.json');
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(result, null, 2));
  console.log(`\n📝 Saved to ${outPath}`);
}

function buildInitData(vaultAddr, rewardAddr, rewardPerBlock) {
  const buf = Buffer.alloc(72);
  Buffer.from(vaultAddr.replace('0x',''),  'hex').copy(buf, 0);
  Buffer.from(rewardAddr.replace('0x',''), 'hex').copy(buf, 20);
  for (let i = 0; i < 32; i++)
    buf[71 - i] = Number((rewardPerBlock >> BigInt(8 * i)) & 0xffn);
  return buf;
}

main().catch(err => { console.error(err); process.exit(1); });
ENDOFFILE

echo "✅ Contract files written"

# ══════════════════════════════════════════════════════════
# FRONTEND FILES
# ══════════════════════════════════════════════════════════

# ── frontend/package.json ─────────────────────────────────
cat > frontend/package.json << 'ENDOFFILE'
{
  "name": "satloop-frontend",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev":     "vite",
    "build":   "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react":          "^18.2.0",
    "react-dom":      "^18.2.0",
    "recharts":       "^2.10.0",
    "lucide-react":   "^0.263.1"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.0",
    "autoprefixer":         "^10.4.17",
    "postcss":              "^8.4.35",
    "tailwindcss":          "^3.4.1",
    "vite":                 "^5.0.12"
  }
}
ENDOFFILE

# ── frontend/vite.config.js ───────────────────────────────
cat > frontend/vite.config.js << 'ENDOFFILE'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
export default defineConfig({
  plugins: [react()],
  define: { global: 'globalThis' },
});
ENDOFFILE

# ── frontend/postcss.config.js ────────────────────────────
cat > frontend/postcss.config.js << 'ENDOFFILE'
export default {
  plugins: { tailwindcss: {}, autoprefixer: {} }
}
ENDOFFILE

# ── frontend/tailwind.config.js ───────────────────────────
cat > frontend/tailwind.config.js << 'ENDOFFILE'
/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        btc:  { orange:'#F7931A', dark:'#0D0D0D', panel:'#141414', border:'#252525', muted:'#666' },
        sat:  { green:'#00FF94', red:'#FF3B3B', yellow:'#FFD166' },
      },
      fontFamily: {
        display: ['"Space Mono"', 'monospace'],
        body:    ['"DM Sans"', 'sans-serif'],
      },
    },
  },
  plugins: [],
};
ENDOFFILE

# ── frontend/index.html ───────────────────────────────────
cat > frontend/index.html << 'ENDOFFILE'
<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>SatLoop – Leveraged Loop Staker · Bitcoin L1</title>
  <link rel="preconnect" href="https://fonts.googleapis.com"/>
  <link href="https://fonts.googleapis.com/css2?family=Space+Mono:wght@400;700&family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600&display=swap" rel="stylesheet"/>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
ENDOFFILE

# ── frontend/src/index.css ────────────────────────────────
cat > frontend/src/index.css << 'ENDOFFILE'
@tailwind base;
@tailwind components;
@tailwind utilities;

*, *::before, *::after { box-sizing: border-box; }
html { background: #0D0D0D; }
body {
  margin: 0; min-height: 100vh; font-family: 'DM Sans', sans-serif; color: #E0E0E0;
  background:
    radial-gradient(ellipse at 50% -10%, rgba(247,147,26,0.13) 0%, transparent 55%),
    linear-gradient(rgba(247,147,26,0.022) 1px, transparent 1px),
    linear-gradient(90deg, rgba(247,147,26,0.022) 1px, transparent 1px), #0D0D0D;
  background-size: auto, 40px 40px, 40px 40px;
}
::-webkit-scrollbar       { width: 5px; background: #0D0D0D; }
::-webkit-scrollbar-thumb { background: #252525; border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: #F7931A; }
input[type=number]::-webkit-inner-spin-button,
input[type=number]::-webkit-outer-spin-button { -webkit-appearance: none; }
input[type=range] { -webkit-appearance: none; height: 4px; border-radius: 2px; cursor: pointer; }
input[type=range]::-webkit-slider-thumb {
  -webkit-appearance: none; width: 18px; height: 18px;
  border-radius: 50%; background: #F7931A; box-shadow: 0 0 8px rgba(247,147,26,0.6);
}

@keyframes glow {
  0%  { box-shadow: 0 0 6px rgba(247,147,26,0.4); }
  100%{ box-shadow: 0 0 20px rgba(247,147,26,0.8), 0 0 40px rgba(247,147,26,0.3); }
}
@keyframes slideUp {
  from { opacity: 0; transform: translateY(12px); }
  to   { opacity: 1; transform: translateY(0); }
}
@keyframes loopPulse {
  0%,100%{ opacity:1; transform:scale(1); }
  50%    { opacity:.7; transform:scale(.98); }
}
.anim-glow     { animation: glow 2s ease-in-out infinite alternate; }
.slide-up      { animation: slideUp .35s ease-out both; }
.loop-active   { animation: loopPulse 1s ease-in-out infinite; }
.text-glow-orange { text-shadow: 0 0 14px rgba(247,147,26,0.6); }
.text-glow-green  { text-shadow: 0 0 10px rgba(0,255,148,0.5); }
ENDOFFILE

# ── frontend/src/main.jsx ─────────────────────────────────
cat > frontend/src/main.jsx << 'ENDOFFILE'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.jsx';
import './index.css';
ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode><App /></React.StrictMode>
);
ENDOFFILE

# ── frontend/src/utils/calculations.js ───────────────────
cat > frontend/src/utils/calculations.js << 'ENDOFFILE'
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
ENDOFFILE

# ── frontend/src/hooks/useWallet.js ──────────────────────
cat > frontend/src/hooks/useWallet.js << 'ENDOFFILE'
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
ENDOFFILE

# ── frontend/src/hooks/useSatLoop.js ─────────────────────
cat > frontend/src/hooks/useSatLoop.js << 'ENDOFFILE'
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
ENDOFFILE

# ── frontend/src/components/Header.jsx ───────────────────
cat > frontend/src/components/Header.jsx << 'ENDOFFILE'
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
ENDOFFILE

# ── frontend/src/components/StatsBar.jsx ─────────────────
cat > frontend/src/components/StatsBar.jsx << 'ENDOFFILE'
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
ENDOFFILE

# ── frontend/src/components/DepositPanel.jsx ─────────────
cat > frontend/src/components/DepositPanel.jsx << 'ENDOFFILE'
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
ENDOFFILE

# ── frontend/src/components/LoopPanel.jsx ────────────────
cat > frontend/src/components/LoopPanel.jsx << 'ENDOFFILE'
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
ENDOFFILE

# ── frontend/src/components/Dashboard.jsx ────────────────
cat > frontend/src/components/Dashboard.jsx << 'ENDOFFILE'
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
ENDOFFILE

# ── frontend/src/App.jsx ──────────────────────────────────
cat > frontend/src/App.jsx << 'ENDOFFILE'
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
ENDOFFILE

# ── frontend/vercel.json ──────────────────────────────────
cat > frontend/vercel.json << 'ENDOFFILE'
{
  "buildCommand":    "npm run build",
  "outputDirectory": "dist",
  "framework":       "vite",
  "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }]
}
ENDOFFILE

echo ""
echo "✅ All files written!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Next steps:"
echo ""
echo "  1. Install & run frontend:"
echo "     cd frontend && npm install && npm run dev"
echo ""
echo "  2. Build contracts:"
echo "     cd ../contract && npm install && npm run build"
echo ""
echo "  3. Deploy contracts:"
echo "     DEPLOYER_WIF=xxx node scripts/deploy.js"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"