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
