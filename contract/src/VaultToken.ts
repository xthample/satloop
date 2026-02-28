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
