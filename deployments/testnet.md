# Testnet deployments

USDT0 testnet token (Writz-deployed LayerZero OFT). Not USDT0; see the [README](../README.md).

## Stellar testnet (LayerZero EID 40600)

Network passphrase `Test SDF Network ; September 2015`, RPC `https://soroban-testnet.stellar.org`.

### Token (issued 2026-10-26)

| Field | Value |
|---|---|
| Classic asset | `USDT0:GCZS6UMPQDE5QVDFCJWRKLM3NR77IT7KSGEH3THSZNTWOH53E66KZ2CC` |
| SAC | `CBBUGWDNLXMEFRECTRWUE2AV7VISS5ICC5OKPKY3B4ZEYXSQE2LTVKN6` |
| Decimals | 7 |
| Issued | 1,000,000 to the liquidity account `GCTZKGWAKFFZTGZYDJIEVC2HNBGPPKHWWFGLN5QNZ7AM67YAA2SCHTOS` |
| Soroswap pool | Circle USDC / USDT0 testnet token, seeded 1,000 / 1,000 |
| Issuer | Not yet locked; locked after the first round trip (see below) |

### OFT and SAC Manager (2026-11-14)

LayerZero Stellar contracts 4.0.4 (source commit `c7bd283934993d6a60c642c7831d3d7662200a68` of `LayerZero-Labs/monorepo-external`), built with `stellar/build.sh`, deployed by `writz-deployer` (`GB2BSYQS3FRJ5LZSSIDF3ZCSG5MKWJT5SZ3OZO4QRCAMCR357YAVPTWT`), which is owner and LayerZero delegate of both.

| Field | Value |
|---|---|
| **OFT** | `CDQLOSDFZKRZLHYHDGOPBNF2EW6ZW3YVOPROH2CVNMNEVR3CLWRDVFCC` |
| OFT as a LayerZero peer (bytes32) | `0xe0b74865caa3959f07199cf0b4ba25bd9b6f1573e2e3e8556b1a4ac7625da23a` |
| OFT wasm sha256 | `d1e65a46e87f02032880485b4f43e916d3fc72dad7641de38962542dc9d74a0a` (122,660 bytes) |
| OFT constructor | `token` the SAC, `shared_decimals` 6, `oft_type` `MintBurn(<SAC Manager>)`, `endpoint` `CALTBA5S…`, `delegate` `writz-deployer` |
| **SAC Manager** | `CADASTNHPST6XBYXR5A5Y56BSOHLEC3TXO355EMCUAF54QGELAY3H2TO` |
| SAC Manager wasm sha256 | `db6b8e6083fc4054aca637788be6e714d29284c7ae850980b6480abc13631854` (40,886 bytes) |
| `MINTER_ROLE` | the OFT only |
| SAC admin | the SAC Manager (was the issuer until 2026-11-14) |

| Step | Transaction |
|---|---|
| Upload SAC Manager wasm | [`6d450a6f62…`](https://stellar.expert/explorer/testnet/tx/6d450a6f6206db1a8df887deca96aace105618ab27380c8f21a061092e60fa30) |
| Deploy SAC Manager | [`53f14274f4…`](https://stellar.expert/explorer/testnet/tx/53f14274f425af75105ed190d2eee646c1a696631cb6fd1bc791b68b01ab25e3) |
| Upload OFT wasm | [`5ca2075e79…`](https://stellar.expert/explorer/testnet/tx/5ca2075e794dcdf190ba1a01c44d997eab9a90b4c246fea86040cc2a2ad32a9e) |
| Deploy OFT | [`e74f3d4e57…`](https://stellar.expert/explorer/testnet/tx/e74f3d4e5782c7ee0ac5e4655d239c91b03e625513e68d382ef874794ac9b2cc) |
| Grant `MINTER_ROLE` to the OFT | [`32760e7ca8…`](https://stellar.expert/explorer/testnet/tx/32760e7ca8c3d2b84c0588efe1231c7506e9a62f74eadcb3e13b6377b6a3333d) |
| SAC `set_admin` to the SAC Manager (signed by the issuer) | [`9a2a4f64e4…`](https://stellar.expert/explorer/testnet/tx/9a2a4f64e42cec70ff712adba5a3c3df2c71e98653b555c8e7acfc259b6bccd2) |
| Wire to Arbitrum Sepolia | Pending the Arbitrum Sepolia deployment |
| Lock the issuer | Pending the first round trip |

### LayerZero on Stellar testnet

| Contract | Address |
|---|---|
| EndpointV2 | `CALTBA5S6GRJEHAXFP45LGGLKWWAF7HTZCPNUBUJF2HWWRRLQNV35AIV` |
| ULN302 (send and receive) | `CCMLPCAWCPIIMXOHJJKU3NZLOFTT2O6QTB2UUFPN6SEHLK35QRHVKKMB` |
| Executor | `CCAVZ7ESAV3PDJ6PISRCXVZCXFFH4NGI7K7MVMZZDR33LC5AD3UPZATT` |
| DVN (LayerZero Labs) | `CB7EWGPRGD3R3CD2DIYIVXMOEFDINVBGBFFQLFMEMXFWJFJIMHA7ZLSA` |

## Arbitrum Sepolia (LayerZero EID 40231)

Pending.

| Contract | Address |
|---|---|
| EndpointV2 | `0x6EDCE65403992e310A62460808c4b910D972f10f` |
| SendUln302 | `0x4f7cd4DA19ABB31b0eC98b9066B9e857B1bf9C0E` |
| ReceiveUln302 | `0x75Db67CDab2824970131D5aa9CECfC9F69c69636` |
| Executor | `0x5Df3a1cEbBD9c8BA7F8dF51Fd632A9aef8308897` |
| DVN (the endpoint's default for Stellar, LayerZero Labs) | `0x53f488E93b4f1b60E8E83aa374dBe1780A1EE8a8` |
