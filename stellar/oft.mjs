#!/usr/bin/env node
/**
 * Stellar side of the USDT0 testnet token (Writz-deployed LayerZero OFT).
 *
 * No official USDT0 exists on any testnet. The token is the classic asset
 * USDT0:GCZS6UMP... that Writz issued on Stellar testnet on 2026-10-26, with
 * its SAC and a Soroswap pool against Circle USDC. This script turns it into a
 * LayerZero V2 OFT the way USDT0 itself runs on Stellar mainnet: LayerZero's
 * SAC Manager becomes the SAC admin, LayerZero's OFT burns on send and mints
 * through the SAC Manager on receive, and the issuer account is locked so the
 * only way to mint is the OFT. The peer is WritzUsdt0TestOFT on Arbitrum
 * Sepolia (evm/ in this repository).
 *
 * Both contracts are LayerZero's, unmodified, built by
 * stellar/build.sh. Every call is signed by a Stellar CLI
 * identity (`--source`), so no secret passes through this script.
 *
 * Steps, in order (each checks its result on chain and is safe to re-run):
 *   deploy       upload and deploy the SAC Manager and the OFT (MintBurn),
 *                grant the OFT MINTER_ROLE on the SAC Manager
 *   upgrade      move both contracts to the wasm in WASM_DIR, keeping their IDs
 *   handover     SAC set_admin to the SAC Manager (signed by the issuer)
 *   wire         peer, send and receive library, executor and DVN config,
 *                enforced options, all for Arbitrum Sepolia (EID 40231)
 *   lock-issuer  issuer master weight to 0. Irreversible
 *   send         send tokens to an Arbitrum Sepolia address
 *   status       read everything back (read-only, always safe)
 *
 * Without --execute a step prints what it would send and sends nothing.
 *
 * Usage (from stellar/, after `bun install` and ./build.sh):
 *   node oft.mjs deploy [--execute]
 *   node oft.mjs upgrade --oft C... --sac-manager C... [--execute]
 *   node oft.mjs handover --sac-manager C... [--execute]
 *   node oft.mjs wire --oft C... --evm-peer 0x... [--execute]
 *   node oft.mjs lock-issuer --oft C... --sac-manager C... [--execute]
 *   node oft.mjs send --oft C... --to 0x... --amount 1.5 [--from <identity>] [--execute]
 *   node oft.mjs status --oft C... --sac-manager C...
 *
 * Environment (defaults in brackets):
 *   STELLAR_SOURCE         identity that owns both contracts [writz-deployer]
 *   USDT0_ISSUER_SOURCE    identity of the issuer [writz-usdt0-issuer]
 *   WASM_DIR               build output [stellar/out]
 */
import * as StellarSdk from '@stellar/stellar-sdk';
import { execFileSync } from 'child_process';
import crypto from 'crypto';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

const { Address, StrKey, xdr } = StellarSdk;

const HERE = path.dirname(fileURLToPath(import.meta.url));
const NETWORK = 'testnet';
const HORIZON = 'https://horizon-testnet.stellar.org';

// The token: the classic asset issued on 2026-10-26 and its SAC.
const ASSET = { code: 'USDT0', issuer: 'GCZS6UMPQDE5QVDFCJWRKLM3NR77IT7KSGEH3THSZNTWOH53E66KZ2CC' };
const SAC = 'CBBUGWDNLXMEFRECTRWUE2AV7VISS5ICC5OKPKY3B4ZEYXSQE2LTVKN6';
const SHARED_DECIMALS = 6; // the asset has 7 decimals; the EVM side has 6

// LayerZero V2 on Stellar testnet (metadata.layerzero-api.com, stellar-testnet).
const LZ = {
  eid: 40600,
  endpoint: 'CALTBA5S6GRJEHAXFP45LGGLKWWAF7HTZCPNUBUJF2HWWRRLQNV35AIV',
  uln302: 'CCMLPCAWCPIIMXOHJJKU3NZLOFTT2O6QTB2UUFPN6SEHLK35QRHVKKMB',
  executor: 'CCAVZ7ESAV3PDJ6PISRCXVZCXFFH4NGI7K7MVMZZDR33LC5AD3UPZATT',
  dvn: 'CB7EWGPRGD3R3CD2DIYIVXMOEFDINVBGBFFQLFMEMXFWJFJIMHA7ZLSA', // LayerZero Labs, active
};

// The remote side: Arbitrum Sepolia.
const REMOTE = {
  eid: 40231,
  sendConfirmations: 1n, // what Arbitrum Sepolia's receive config expects from Stellar
  receiveConfirmations: 5n, // what Arbitrum Sepolia's send config waits before Stellar accepts
  lzReceiveGas: 80_000n, // the value USDT0 enforces from Stellar mainnet to EVM chains
};

const MSG_TYPE_SEND = 1;
const CONFIG_TYPE_EXECUTOR = 1;
const CONFIG_TYPE_SEND_ULN = 2;
const CONFIG_TYPE_RECEIVE_ULN = 3;
const MAX_MESSAGE_SIZE = 10_000;
const MINTER_ROLE = 'MINTER_ROLE';
const UPGRADER_ROLE = 'UPGRADER_ROLE';
const VOID_XDR_HEX = xdr.ScVal.scvVoid().toXDR('hex'); // MigrationData is () for these contracts

const SOURCE = process.env.STELLAR_SOURCE || 'writz-deployer';
const ISSUER_SOURCE = process.env.USDT0_ISSUER_SOURCE || 'writz-usdt0-issuer';
const WASM_DIR = process.env.WASM_DIR || path.join(HERE, 'out');

const argv = process.argv.slice(2);
const command = argv[0];
const EXECUTE = argv.includes('--execute');
const arg = (flag) => {
  const i = argv.indexOf(flag);
  return i === -1 ? undefined : argv[i + 1];
};

function fail(msg) {
  console.error(`oft.mjs: ${msg}`);
  process.exit(1);
}

// ------------------------------------------------------------------ helpers

function stellar(args, { source = SOURCE, send = true } = {}) {
  // Global flags go right after the subcommand: `contract invoke`, `contract deploy`, `tx new set-options`.
  const head = args[0] === 'tx' ? 3 : 2;
  const full = [...args.slice(0, head), '--network', NETWORK, '--source', source, ...(send ? [] : ['--send=no']), ...args.slice(head)];
  try {
    return execFileSync('stellar', full, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch (e) {
    const err = (e.stderr || '').split('\n').filter((l) => l && !/local config|config migrate/.test(l)).slice(-6).join('\n');
    throw new Error(`stellar ${args.slice(0, 2).join(' ')} failed:\n${err}`);
  }
}

const invoke = (id, fn, params = [], opts = {}) => stellar(['contract', 'invoke', '--id', id, '--', fn, ...params], opts);
const read = (id, fn, params = []) => {
  const out = invoke(id, fn, params, { send: false });
  return out === '' ? null : JSON.parse(out);
};
const address = (identity) =>
  execFileSync('stellar', ['keys', 'address', identity], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim().split('\n').pop();

function contractIdOf(value, name) {
  if (!value || !StrKey.isValidContract(value)) fail(`${name} must be a contract ID (C...)`);
  return value;
}

function evmAddress(value, name) {
  if (!/^0x[0-9a-fA-F]{40}$/.test(value || '')) fail(`${name} must be a 20-byte EVM address (0x...)`);
  return value;
}

/** A 20-byte EVM address as the 32-byte peer or recipient LayerZero expects. */
const evmToBytes32 = (addr) => addr.toLowerCase().replace(/^0x/, '').padStart(64, '0');

function step(label, run) {
  if (!EXECUTE) {
    console.log(`  plan  ${label}`);
    return undefined;
  }
  const out = run();
  console.log(`  done  ${label}`);
  return out;
}

function check(ok, label) {
  console.log(`  ${ok ? 'ok   ' : 'FAIL '} ${label}`);
  if (!ok) process.exitCode = 1;
  return ok;
}

// ---------------------------------------------------- ScVal and option bytes

const sym = (s) => xdr.ScVal.scvSymbol(s);
const u32 = (n) => xdr.ScVal.scvU32(Number(n));
const u64 = (n) => xdr.ScVal.scvU64(new xdr.Uint64(BigInt(n)));
const bool = (b) => xdr.ScVal.scvBool(b);
const addr = (a) => new Address(a).toScVal();
const vec = (items) => xdr.ScVal.scvVec(items);

/** A #[contracttype] struct: a map with its field names sorted, as Soroban requires. */
function struct(fields) {
  const entries = Object.keys(fields)
    .sort()
    .map((k) => new xdr.ScMapEntry({ key: sym(k), val: fields[k] }));
  return xdr.ScVal.scvMap(entries);
}

/** XDR of uln-302's OAppUlnConfig with explicit confirmations and required DVN. */
function ulnConfig(confirmations) {
  return struct({
    use_default_confirmations: bool(false),
    use_default_required_dvns: bool(false),
    use_default_optional_dvns: bool(true),
    uln_config: struct({
      confirmations: u64(confirmations),
      required_dvns: vec([addr(LZ.dvn)]),
      optional_dvns: vec([]),
      optional_dvn_threshold: u32(0),
    }),
  }).toXDR('hex');
}

/** XDR of uln-302's OAppExecutorConfig. */
const executorConfig = () => struct({ max_message_size: u32(MAX_MESSAGE_SIZE), executor: addr(LZ.executor) }).toXDR('hex');

/** Type 3 options with one executor lzReceive option: gas only, no native value. */
function lzReceiveOptions(gas) {
  return '0003' + '01' + '0011' + '01' + gas.toString(16).padStart(32, '0');
}

/** Decode get_config bytes (an ScVal map) into plain values. */
function decodeConfig(hex) {
  return StellarSdk.scValToNative(xdr.ScVal.fromXDR(hex, 'hex'));
}

// ------------------------------------------------------------------- steps

function deploy() {
  const owner = address(SOURCE);
  const wasm = { oft: path.join(WASM_DIR, 'oft.wasm'), sacManager: path.join(WASM_DIR, 'sac_manager.wasm') };
  for (const [name, file] of Object.entries(wasm)) {
    if (!fs.existsSync(file)) fail(`${file} not found; run ./build.sh first`);
    console.log(`  ${name} wasm sha256 ${crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}`);
  }
  console.log(`  owner and delegate: ${SOURCE} (${owner})`);

  // In plan mode the IDs do not exist yet; placeholders keep the printed plan readable.
  const sacManager = step(`deploy SAC Manager (sac_token ${SAC}, owner ${owner})`, () =>
    stellar(['contract', 'deploy', '--wasm', wasm.sacManager, '--', '--sac_token', SAC, '--owner', owner]).split('\n').pop()) ?? '<SAC Manager>';
  const oft = step(`deploy OFT (token ${SAC}, shared_decimals ${SHARED_DECIMALS}, MintBurn through ${sacManager}, endpoint ${LZ.endpoint})`, () =>
    stellar([
      'contract', 'deploy', '--wasm', wasm.oft, '--',
      '--token', SAC,
      '--shared_decimals', String(SHARED_DECIMALS),
      '--oft_type', JSON.stringify({ MintBurn: sacManager }),
      '--endpoint', LZ.endpoint,
      '--delegate', owner,
    ]).split('\n').pop()) ?? '<OFT>';
  step(`grant ${MINTER_ROLE} on ${sacManager} to ${oft}`, () =>
    invoke(sacManager, 'grant_role', ['--account', oft, '--role', MINTER_ROLE, '--caller', owner]));

  if (EXECUTE) {
    console.log(`\nSAC Manager ${sacManager}\nOFT         ${oft}`);
    check(read(sacManager, 'underlying_sac') === SAC, 'SAC Manager manages the USDT0 SAC');
    check(read(sacManager, 'has_role', ['--account', oft, '--role', MINTER_ROLE]) !== null, 'OFT holds MINTER_ROLE');
    check(read(oft, 'token') === SAC, 'OFT token is the USDT0 SAC');
    check(read(oft, 'shared_decimals') === SHARED_DECIMALS, `OFT shared decimals ${SHARED_DECIMALS}`);
    check(JSON.stringify(read(oft, 'oft_type')) === JSON.stringify({ MintBurn: sacManager }), 'OFT type is MintBurn through the SAC Manager');
  }
}

/** sha256 of the wasm a contract runs, read from the chain. */
function onChainWasmSha256(id) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'oft-fetch-'));
  try {
    const file = path.join(tmp, 'code.wasm');
    execFileSync('stellar', ['contract', 'fetch', '--network', NETWORK, '--id', id, '--out-file', file], { stdio: ['ignore', 'ignore', 'ignore'] });
    return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

/**
 * Moves both contracts to the wasm in WASM_DIR without changing their IDs or storage:
 * grant UPGRADER_ROLE to the owner, upload, upgrade, migrate (a no-op for these
 * contracts that clears the migrating flag), revoke the role, and compare the code
 * running on chain with the local file.
 */
function upgrade() {
  const owner = address(SOURCE);
  const targets = [
    { name: 'SAC Manager', id: contractIdOf(arg('--sac-manager'), '--sac-manager'), file: path.join(WASM_DIR, 'sac_manager.wasm') },
    { name: 'OFT', id: contractIdOf(arg('--oft'), '--oft'), file: path.join(WASM_DIR, 'oft.wasm') },
  ];
  for (const t of targets) {
    if (!fs.existsSync(t.file)) fail(`${t.file} not found; run ./build.sh first`);
    const want = crypto.createHash('sha256').update(fs.readFileSync(t.file)).digest('hex');
    const have = onChainWasmSha256(t.id);
    console.log(`  ${t.name} ${t.id}\n    on chain ${have}\n    local    ${want}`);
    if (have === want) {
      console.log('    already running the local wasm; nothing to do');
      continue;
    }
    const holds = read(t.id, 'has_role', ['--account', owner, '--role', UPGRADER_ROLE]) !== null;
    if (!holds) step(`grant ${UPGRADER_ROLE} to ${owner}`, () => invoke(t.id, 'grant_role', ['--account', owner, '--role', UPGRADER_ROLE, '--caller', owner]));
    const hash = step(`upload ${path.basename(t.file)}`, () => stellar(['contract', 'upload', '--wasm', t.file]).split('\n').pop()) ?? want;
    step(`upgrade to ${hash}`, () => invoke(t.id, 'upgrade', ['--new_wasm_hash', hash, '--operator', owner]));
    step('migrate (no-op, clears the migrating flag)', () => invoke(t.id, 'migrate', ['--migration_data', VOID_XDR_HEX, '--operator', owner]));
    if (!holds) step(`revoke ${UPGRADER_ROLE} from ${owner}`, () => invoke(t.id, 'revoke_role', ['--account', owner, '--role', UPGRADER_ROLE, '--caller', owner]));
    if (EXECUTE) check(onChainWasmSha256(t.id) === want, `${t.name} runs the local wasm`);
  }
}

function handover() {
  const sacManager = contractIdOf(arg('--sac-manager'), '--sac-manager');
  const before = read(SAC, 'admin');
  console.log(`  SAC admin now: ${before}`);
  if (before === sacManager) {
    console.log('  the SAC Manager is already the admin; nothing to do');
    return;
  }
  if (before !== ASSET.issuer) fail(`the SAC admin is ${before}, not the issuer; refusing to guess`);
  step(`SAC set_admin to the SAC Manager ${sacManager} (signed by ${ISSUER_SOURCE})`, () =>
    invoke(SAC, 'set_admin', ['--new_admin', sacManager], { source: ISSUER_SOURCE }));
  if (EXECUTE) check(read(SAC, 'admin') === sacManager, 'the SAC Manager is the SAC admin');
}

async function wire() {
  const oft = contractIdOf(arg('--oft'), '--oft');
  const peer = evmAddress(arg('--evm-peer'), '--evm-peer');
  const owner = address(SOURCE);
  const params = [
    { eid: REMOTE.eid, config_type: CONFIG_TYPE_EXECUTOR, config: executorConfig() },
    { eid: REMOTE.eid, config_type: CONFIG_TYPE_SEND_ULN, config: ulnConfig(REMOTE.sendConfirmations) },
    { eid: REMOTE.eid, config_type: CONFIG_TYPE_RECEIVE_ULN, config: ulnConfig(REMOTE.receiveConfirmations) },
  ];
  const enforced = [{ eid: REMOTE.eid, msg_type: MSG_TYPE_SEND, options: lzReceiveOptions(REMOTE.lzReceiveGas) }];

  step(`set_peer ${REMOTE.eid} -> ${peer}`, () =>
    invoke(oft, 'set_peer', ['--eid', String(REMOTE.eid), '--peer', JSON.stringify(evmToBytes32(peer)), '--operator', owner]));
  step(`send library for ${REMOTE.eid}: ULN302 ${LZ.uln302}`, () =>
    invoke(LZ.endpoint, 'set_send_library', ['--caller', owner, '--sender', oft, '--dst_eid', String(REMOTE.eid), '--new_lib', JSON.stringify(LZ.uln302)]));
  step(`receive library for ${REMOTE.eid}: ULN302, no grace period`, () =>
    invoke(LZ.endpoint, 'set_receive_library', ['--caller', owner, '--receiver', oft, '--src_eid', String(REMOTE.eid), '--new_lib', JSON.stringify(LZ.uln302), '--grace_period', '0']));
  step(`executor ${LZ.executor}; send ${REMOTE.sendConfirmations} and receive ${REMOTE.receiveConfirmations} confirmations; required DVN ${LZ.dvn}`, () =>
    invoke(LZ.endpoint, 'set_config', ['--caller', owner, '--oapp', oft, '--lib', LZ.uln302, '--params', JSON.stringify(params)]));
  step(`enforced options for ${REMOTE.eid}: lzReceive gas ${REMOTE.lzReceiveGas}`, () =>
    invoke(oft, 'set_enforced_options', ['--options', JSON.stringify(enforced), '--operator', owner]));

  if (EXECUTE) await status({ oft, sacManager: arg('--sac-manager') });
}

async function lockIssuer() {
  const oft = contractIdOf(arg('--oft'), '--oft');
  const sacManager = contractIdOf(arg('--sac-manager'), '--sac-manager');
  // Locking is irreversible, so everything that minting will depend on is checked first.
  const ready = [
    check(read(SAC, 'admin') === sacManager, 'the SAC Manager is the SAC admin'),
    check(read(sacManager, 'has_role', ['--account', oft, '--role', MINTER_ROLE]) !== null, 'the OFT holds MINTER_ROLE'),
    check(read(oft, 'peer', ['--eid', String(REMOTE.eid)]) !== null, `the OFT has a peer on ${REMOTE.eid}`),
  ].every(Boolean);
  if (!ready) fail('not locking the issuer until every check above passes');

  const account = await (await fetch(`${HORIZON}/accounts/${ASSET.issuer}`)).json();
  const others = account.signers.filter((s) => s.key !== ASSET.issuer && s.weight > 0);
  if (others.length) fail(`the issuer has other signers (${others.map((s) => s.key).join(', ')}); remove them first`);
  const master = account.signers.find((s) => s.key === ASSET.issuer)?.weight ?? 0;
  if (master === 0) {
    console.log('  the issuer is already locked (master weight 0)');
    return;
  }
  step(`issuer ${ASSET.issuer}: master weight ${master} -> 0 (irreversible)`, () =>
    stellar(['tx', 'new', 'set-options', '--master-weight', '0'], { source: ISSUER_SOURCE }));
  if (EXECUTE) {
    const after = await (await fetch(`${HORIZON}/accounts/${ASSET.issuer}`)).json();
    check(after.signers.every((s) => s.weight === 0), 'the issuer is locked: no signer has weight');
  }
}

function send() {
  const oft = contractIdOf(arg('--oft'), '--oft');
  const to = evmAddress(arg('--to'), '--to');
  const from = arg('--from') || SOURCE;
  const amount = arg('--amount');
  if (!/^\d+(\.\d{1,6})?$/.test(amount || '')) fail('--amount must be a positive number with at most 6 decimals (the shared decimals)');
  const [whole, frac = ''] = amount.split('.');
  const amountLd = BigInt(whole) * 10_000_000n + BigInt(frac.padEnd(7, '0'));
  if (amountLd <= 0n) fail('--amount must be greater than zero');

  const sender = address(from);
  const sendParam = {
    dst_eid: REMOTE.eid,
    to: evmToBytes32(to),
    amount_ld: amountLd.toString(),
    min_amount_ld: amountLd.toString(),
    extra_options: '',
    compose_msg: '',
    oft_cmd: '',
  };
  const fee = read(oft, 'quote_send', ['--from', sender, '--send_param', JSON.stringify(sendParam), '--pay_in_zro', 'false']);
  console.log(`  ${amount} USDT0 testnet token from ${from} (${sender}) to ${to} on ${REMOTE.eid}`);
  console.log(`  LayerZero fee: ${Number(fee.native_fee) / 1e7} XLM`);
  const out = step('send', () =>
    invoke(oft, 'send', ['--from', sender, '--send_param', JSON.stringify(sendParam), '--fee', JSON.stringify(fee), '--refund_address', sender], { source: from }));
  if (out) console.log(`  receipt: ${out}`);
}

async function status({ oft = arg('--oft'), sacManager = arg('--sac-manager') } = {}) {
  console.log('\nStatus (read-only)');
  if (sacManager) {
    contractIdOf(sacManager, '--sac-manager');
    check(read(SAC, 'admin') === sacManager, `SAC admin is the SAC Manager (${read(SAC, 'admin')})`);
    if (oft) check(read(sacManager, 'has_role', ['--account', oft, '--role', MINTER_ROLE]) !== null, 'OFT holds MINTER_ROLE');
  }
  if (!oft) return;
  contractIdOf(oft, '--oft');
  console.log(`  OFT as a LayerZero peer (STELLAR_OFT_BYTES32): 0x${Buffer.from(StrKey.decodeContract(oft)).toString('hex')}`);
  const peer = read(oft, 'peer', ['--eid', String(REMOTE.eid)]);
  console.log(`  peer ${REMOTE.eid}: ${peer ? '0x' + peer.slice(24) : 'none'}`);
  const sendLib = read(LZ.endpoint, 'get_send_library', ['--sender', oft, '--dst_eid', String(REMOTE.eid)]);
  const recvLib = read(LZ.endpoint, 'get_receive_library', ['--receiver', oft, '--src_eid', String(REMOTE.eid)]);
  check(sendLib?.lib === LZ.uln302 && sendLib?.is_default === false, 'send library pinned to ULN302');
  check(recvLib?.lib === LZ.uln302 && recvLib?.is_default === false, 'receive library pinned to ULN302');
  const cfg = (type) => decodeConfig(read(LZ.endpoint, 'get_config', ['--oapp', oft, '--lib', LZ.uln302, '--eid', String(REMOTE.eid), '--config_type', String(type)]));
  const exec = cfg(CONFIG_TYPE_EXECUTOR);
  const sendUln = cfg(CONFIG_TYPE_SEND_ULN);
  const recvUln = cfg(CONFIG_TYPE_RECEIVE_ULN);
  check(exec.executor === LZ.executor, `executor ${exec.executor}, max message ${exec.max_message_size} bytes`);
  check(sendUln.required_dvns.length === 1 && sendUln.required_dvns[0] === LZ.dvn && BigInt(sendUln.confirmations) === REMOTE.sendConfirmations,
    `send: ${sendUln.confirmations} confirmations, required DVN ${sendUln.required_dvns.join(', ')}`);
  check(recvUln.required_dvns.length === 1 && recvUln.required_dvns[0] === LZ.dvn && BigInt(recvUln.confirmations) === REMOTE.receiveConfirmations,
    `receive: ${recvUln.confirmations} confirmations, required DVN ${recvUln.required_dvns.join(', ')}`);
  const enforced = read(oft, 'enforced_options', ['--eid', String(REMOTE.eid), '--msg_type', String(MSG_TYPE_SEND)]);
  check(enforced === lzReceiveOptions(REMOTE.lzReceiveGas), `enforced options ${enforced}`);
  const asset = await (await fetch(`${HORIZON}/assets?asset_code=${ASSET.code}&asset_issuer=${ASSET.issuer}`)).json();
  const record = asset._embedded?.records?.[0];
  if (record) console.log(`  supply on Stellar: ${record.balances?.authorized ?? record.amount} in accounts, ${record.contracts_amount ?? 0} in contracts`);
}

// --------------------------------------------------------------------- main

const commands = { deploy, upgrade, handover, wire, 'lock-issuer': lockIssuer, send, status };
if (!commands[command]) fail(`usage: oft.mjs <${Object.keys(commands).join('|')}> [flags] [--execute]`);
if (!EXECUTE && command !== 'status') console.log('Plan only: nothing is sent without --execute.\n');
await commands[command]();
