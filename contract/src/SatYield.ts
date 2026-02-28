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
