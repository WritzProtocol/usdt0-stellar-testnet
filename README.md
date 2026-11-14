# USDT0 testnet token (Writz-deployed LayerZero OFT)

A USDT0 test token that moves between Stellar testnet and Arbitrum Sepolia over LayerZero V2, deployed and operated by [Writz Protocol](https://github.com/WritzProtocol/writz).

**This is not USDT0.** No official USDT0 exists on any testnet, so this token stands in for it while testing. It has no value and is not issued, endorsed or backed by USDT0 or Tether. Wherever it appears it is named "USDT0 testnet token (Writz-deployed LayerZero OFT)", never "USDT0" alone.

## Why it exists

USDT0 runs on Stellar mainnet as a LayerZero OFT. The Writz testnet app lets a borrower receive a loan as USDT0, which needs a USDT0 on testnet that behaves like the real one: a Stellar classic asset with its Stellar Asset Contract (SAC), and a LayerZero OFT that burns it on one chain and mints it on the other. This repository builds, deploys, wires and checks that token, so the cross-chain path can be exercised end to end before mainnet.

## How it works

It follows the setup USDT0 itself uses on Stellar mainnet.

| Piece | Chain | What it is |
|---|---|---|
| `USDT0:GCZS6UMP…` and its SAC | Stellar testnet | The token: a classic asset, 7 decimals, issued by Writz on 2026-10-26 |
| SAC Manager | Stellar testnet | LayerZero's contract that is the SAC admin; mints only for addresses holding `MINTER_ROLE` |
| OFT (MintBurn) | Stellar testnet | LayerZero's Stellar OFT: burns on send, mints through the SAC Manager on receive |
| `WritzUsdt0TestOFT` | Arbitrum Sepolia | A plain LayerZero V2 OFT, 6 decimals, zero initial supply |

- **Supply.** Every unit on Arbitrum Sepolia was burned on Stellar first. The supply on both chains together never exceeds what the Stellar side issued.
- **Issuer.** Once the round trip works, the issuer account is locked (master weight 0). After that the only way to mint is the OFT through the SAC Manager, which is the trust model LayerZero's SAC Manager requires.
- **Decimals.** Shared decimals are 6. Amounts sent from Stellar lose anything below the sixth decimal (the dust stays with the sender).
- **Security.** LayerZero Labs DVN required on both pathways, set explicitly rather than inherited from defaults. Confirmations: 1 from Stellar, 5 from Arbitrum Sepolia, matching what each side's endpoint expects.
- **Enforced options.** `lzReceive` gas of 80,000 toward Arbitrum Sepolia and 500,000 toward Stellar, the values USDT0 enforces on mainnet.

Writz does not modify LayerZero's contracts. The Stellar side is LayerZero's published code, built reproducibly; the EVM side is LayerZero's `OFT` with a name and six decimals.

## Deployments

Contract IDs, transactions and wasm hashes: [`deployments/testnet.md`](deployments/testnet.md).

## Repository layout

```
stellar/   build.sh (reproducible wasm build), oft.mjs (deploy, wire, send, status), locks/
evm/       Foundry project: src/, test/, script/
deployments/testnet.md
```

## Build and verify

### Stellar contracts

```
stellar/build.sh
```

Fetches LayerZero's npm packages at a pinned version without running any of their scripts, checks each against a pinned sha512 integrity, builds with LayerZero's `Cargo.lock` files and the Rust toolchain their packages pin, and fails unless the wasm sha256 matches the hash recorded in the script and in [`deployments/testnet.md`](deployments/testnet.md). Requires `npm`, `rustup` and `openssl`.

The recorded hashes come from an x86_64 Linux host, and CI rebuilds and compares them on every push. Cargo hashes the host platform into symbol metadata, so on macOS or ARM the same source gives a different wasm; to reproduce the recorded hashes there, build in a linux/amd64 container:

```
docker run --rm --platform linux/amd64 -v "$PWD":/repo -w /repo/stellar rust:1.90.0 \
  bash -c 'apt-get update -qq && apt-get install -y -qq npm >/dev/null && ./build.sh'
```

The code each contract runs on chain can be compared with `node oft.mjs upgrade --oft C... --sac-manager C...`, which prints both hashes and, without `--execute`, changes nothing.

### EVM contract

```
cd evm
bun install
forge test
```

Unit tests run against LayerZero's test endpoints. Setting `ARBITRUM_SEPOLIA_RPC_URL` also runs the fork tests, which apply the wiring to the live LayerZero contracts on Arbitrum Sepolia and quote a send to Stellar.

## Operate

Stellar side, from `stellar/` after `bun install` and `./build.sh`. Calls are signed by Stellar CLI identities (`STELLAR_SOURCE`, default `writz-deployer`; `USDT0_ISSUER_SOURCE`, default `writz-usdt0-issuer`), so no secret passes through the script. Every step prints a plan and sends nothing without `--execute`:

```
node oft.mjs status --oft C... --sac-manager C...
node oft.mjs send --oft C... --to 0x... --amount 1.5 --from <identity> --execute
```

EVM side, from `evm/`. The key is read from `EVM_TESTNET_DEPLOYER_KEY`, never from the command line; without `--broadcast` forge only simulates:

```
EVM_OFT=0x... STELLAR_RECIPIENT_BYTES32=0x... AMOUNT=1000000 \
  forge script script/Usdt0TestOft.s.sol:SendToStellar --rpc-url arbitrum_sepolia --broadcast
```

A Stellar account that receives the token must hold a USDT0 trustline first. Without it, the mint on Stellar fails and the message waits on the LayerZero endpoint until it is retried. A Stellar contract address needs no trustline.

The full sequence used for the deployment (`deploy`, `handover`, `wire`, `lock-issuer` on Stellar; `Deploy`, `Wire` on Arbitrum Sepolia) is recorded step by step in [`deployments/testnet.md`](deployments/testnet.md).

## License

MIT. LayerZero's contracts are MIT licensed by LayerZero Labs.
