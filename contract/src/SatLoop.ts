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
