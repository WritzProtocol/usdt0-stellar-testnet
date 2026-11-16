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
| Issuer | Locked on 2026-11-16 (master weight 0, no other signer): the only way to mint is the OFT through the SAC Manager |

### OFT and SAC Manager (2026-11-14)

LayerZero Stellar contracts 4.0.4 (source commit `c7bd283934993d6a60c642c7831d3d7662200a68` of `LayerZero-Labs/monorepo-external`), built with `stellar/build.sh` on x86_64 Linux, deployed by `writz-deployer` (`GB2BSYQS3FRJ5LZSSIDF3ZCSG5MKWJT5SZ3OZO4QRCAMCR357YAVPTWT`), which is owner and LayerZero delegate of both.

| Field | Value |
|---|---|
| **OFT** | `CDQLOSDFZKRZLHYHDGOPBNF2EW6ZW3YVOPROH2CVNMNEVR3CLWRDVFCC` |
| OFT as a LayerZero peer (bytes32) | `0xe0b74865caa3959f07199cf0b4ba25bd9b6f1573e2e3e8556b1a4ac7625da23a` |
| OFT wasm sha256 | `c0db29f9951192ff2adaf05e1eb8ad71ac46dfb752161a6bacf85e2426fa3010` (122,772 bytes) |
| OFT constructor | `token` the SAC, `shared_decimals` 6, `oft_type` `MintBurn(<SAC Manager>)`, `endpoint` `CALTBA5S…`, `delegate` `writz-deployer` |
| **SAC Manager** | `CADASTNHPST6XBYXR5A5Y56BSOHLEC3TXO355EMCUAF54QGELAY3H2TO` |
| SAC Manager wasm sha256 | `ca5c6eba1a430851bc5e82d3ea77e1484f6e4f94f784703d67a95ac932b208f9` (40,934 bytes) |
| `UPGRADER_ROLE` | nobody (granted to the owner only for the upgrade below, then revoked) |
| `MINTER_ROLE` | the OFT only |
| Peer on Arbitrum Sepolia (EID 40231) | `0x21a5553a83655d024361E510f32Da165bDd7758D` |
| Pathway to EID 40231 | ULN302 for send and receive (pinned); executor `CCAVZ7ES…`; send 1 confirmation, receive 5; required DVN `CB7EWGPR…`; enforced `lzReceive` gas 80,000 |
| SAC admin | the SAC Manager (was the issuer until 2026-11-14) |

Both contracts were first deployed from a macOS build of the same source (wasm sha256 `d1e65a46…` and `db6b8e60…`), then upgraded in place the same day to the x86_64 Linux build that CI reproduces, so the code on chain can be checked against `stellar/build.sh`. Contract IDs and storage did not change.

| Step | Transaction |
|---|---|
| Upload SAC Manager wasm | [`6d450a6f62…`](https://stellar.expert/explorer/testnet/tx/6d450a6f6206db1a8df887deca96aace105618ab27380c8f21a061092e60fa30) |
| Deploy SAC Manager | [`53f14274f4…`](https://stellar.expert/explorer/testnet/tx/53f14274f425af75105ed190d2eee646c1a696631cb6fd1bc791b68b01ab25e3) |
| Upload OFT wasm | [`5ca2075e79…`](https://stellar.expert/explorer/testnet/tx/5ca2075e794dcdf190ba1a01c44d997eab9a90b4c246fea86040cc2a2ad32a9e) |
| Deploy OFT | [`e74f3d4e57…`](https://stellar.expert/explorer/testnet/tx/e74f3d4e5782c7ee0ac5e4655d239c91b03e625513e68d382ef874794ac9b2cc) |
| Grant `MINTER_ROLE` to the OFT | [`32760e7ca8…`](https://stellar.expert/explorer/testnet/tx/32760e7ca8c3d2b84c0588efe1231c7506e9a62f74eadcb3e13b6377b6a3333d) |
| SAC `set_admin` to the SAC Manager (signed by the issuer) | [`9a2a4f64e4…`](https://stellar.expert/explorer/testnet/tx/9a2a4f64e42cec70ff712adba5a3c3df2c71e98653b555c8e7acfc259b6bccd2) |
| Upgrade SAC Manager to the Linux build (grant role, upload, upgrade, migrate, revoke) | [`124e814f75…`](https://stellar.expert/explorer/testnet/tx/124e814f75f68e97219b3e2d78413c39239ede1f2e403c62cc8e236cd4bba07d), [`428fa22907…`](https://stellar.expert/explorer/testnet/tx/428fa229079140f9725800ff4d1c3c511520f858e27c4adc6b736a3278a547f2), [`2dc4fb001c…`](https://stellar.expert/explorer/testnet/tx/2dc4fb001c160069768a77ac90fe3c71039dd1ee54b5fb7fab195aaa029aa52f), [`133e25d49e…`](https://stellar.expert/explorer/testnet/tx/133e25d49e8b80755d9c20730a4ddb89e91da79c76632ff2437ea5dc1ac02b2d), [`a1d1cba85f…`](https://stellar.expert/explorer/testnet/tx/a1d1cba85f9597cef574ac67eb74bcadc257f91f0a641065e6ff4125a9c2007a) |
| Upgrade OFT to the Linux build (same steps) | [`0cc3d46e3a…`](https://stellar.expert/explorer/testnet/tx/0cc3d46e3ab160958c77b6904cae6ed2c1359d9c2162e85b057bbf8c3b8fb2b6), [`92597be20c…`](https://stellar.expert/explorer/testnet/tx/92597be20c0caf6ed763b2e2943c870b0950b7cf1bc19634f68ea18cf4924d53), [`69acbf7b52…`](https://stellar.expert/explorer/testnet/tx/69acbf7b526289d1ad6eef2e735a82015753b64158e3a57c1ad661ef16d58b17), [`89e8e18b15…`](https://stellar.expert/explorer/testnet/tx/89e8e18b1507d0fe6abfbdea0588f644e0a987052d40b859bc3a9122dcd6d804), [`39ebdc7029…`](https://stellar.expert/explorer/testnet/tx/39ebdc7029bf93527bbd3b93613ded27a47f8afcf3019b71a5fcc5dbc85016ba) |
| Wire to Arbitrum Sepolia: peer, send library, receive library, executor and DVN config, enforced options | [`be568eb5a4…`](https://stellar.expert/explorer/testnet/tx/be568eb5a4b320ec53d0d318bea0ea6fa4cfb7c9725115ec256843dc9c04777b), [`fee7c1638a…`](https://stellar.expert/explorer/testnet/tx/fee7c1638a720d1f0a88de9d32728425c0fe45e58f8815eb322f831ecc5cac70), [`aee7dbd07a…`](https://stellar.expert/explorer/testnet/tx/aee7dbd07a551f4da40d5d28db2f77624d2ea6cb8e58a36198c1952df8ced2f9), [`e5673b19df…`](https://stellar.expert/explorer/testnet/tx/e5673b19df34e7c2dd15ef55c3ac2768da8f4c7b42f8916d23edfabfdde59f04), [`e468fc2876…`](https://stellar.expert/explorer/testnet/tx/e468fc2876e5903b02182d5108250dfd05a04fcb3dc12f52fdbd7d8b8a8b9e23) |
| Lock the issuer (master weight 1 to 0, after the round trip below) | [`d34628a470…`](https://stellar.expert/explorer/testnet/tx/d34628a4706072d6305dd91a533fc1fac0aedab167e6c13ea2b70dbb8e138554) |

### LayerZero on Stellar testnet

| Contract | Address |
|---|---|
| EndpointV2 | `CALTBA5S6GRJEHAXFP45LGGLKWWAF7HTZCPNUBUJF2HWWRRLQNV35AIV` |
| ULN302 (send and receive) | `CCMLPCAWCPIIMXOHJJKU3NZLOFTT2O6QTB2UUFPN6SEHLK35QRHVKKMB` |
| Executor | `CCAVZ7ESAV3PDJ6PISRCXVZCXFFH4NGI7K7MVMZZDR33LC5AD3UPZATT` |
| DVN (LayerZero Labs) | `CB7EWGPRGD3R3CD2DIYIVXMOEFDINVBGBFFQLFMEMXFWJFJIMHA7ZLSA` |

## Arbitrum Sepolia (LayerZero EID 40231)

Deployed 2026-11-16 by `0xb22518ee93aC3adBb287970DaEFA7c92a1aC4769`, which is owner and LayerZero delegate. Built with Foundry 1.5.1 (solc 0.8.22, optimizer 20,000 runs, `evm_version` paris) and verified on Sourcify (exact match).

| Field | Value |
|---|---|
| **WritzUsdt0TestOFT** | [`0x21a5553a83655d024361E510f32Da165bDd7758D`](https://sepolia.arbiscan.io/address/0x21a5553a83655d024361E510f32Da165bDd7758D) |
| Name, symbol, decimals | USDT0 testnet token (Writz-deployed LayerZero OFT), USDT0, 6 (shared decimals 6) |
| Initial supply | 0 |
| Peer on Stellar (EID 40600) | the Stellar OFT, `0xe0b74865…5da23a` |
| Pathway to EID 40600 | ULN302 for send and receive (pinned); executor `0x5Df3a1cE…`; send 5 confirmations, receive 1; required DVN `0x53f488E9…`; enforced `lzReceive` gas 4,000,000 (500,000 until 2026-11-16, see below) |

| Step | Transaction |
|---|---|
| Deploy | [`0x63018b14…`](https://sepolia.arbiscan.io/tx/0x63018b143669ae8fef5ef9cd12c64f99565bcc13d947b5a1b3fbdc9654e3a010) |
| Wire to Stellar: `setPeer`, `setSendLibrary`, `setReceiveLibrary`, `setConfig` (send), `setConfig` (receive), `setEnforcedOptions` | [`0xc4573ed9…`](https://sepolia.arbiscan.io/tx/0xc4573ed9edac65901ab1ee31235e694a3329f2d3484bbf59af945689d09dab52), [`0x513f4cc4…`](https://sepolia.arbiscan.io/tx/0x513f4cc4b372850e69886e4dca17b3dde7c6226641e7d6ffb5e16cb4129670eb), [`0xad80e86b…`](https://sepolia.arbiscan.io/tx/0xad80e86bd9ead6b1a4f061e947195eaa5581657ca4264fe01c489ffe5256c81b), [`0xa9e72536…`](https://sepolia.arbiscan.io/tx/0xa9e725368e2b7f4ee38a10d42d493785e22a6978e11e1765f142c7a2324e55a9), [`0x7fa7fcd6…`](https://sepolia.arbiscan.io/tx/0x7fa7fcd693984e0cf1edb8e5ca3bbf2368c1e13e24b4f20ea787bfb427f4c61e), [`0x6d4e4add…`](https://sepolia.arbiscan.io/tx/0x6d4e4addd814082071fe76ca7f1cdfe9263a75d116f342c5425a7be0624454e8) |

| Raise the enforced `lzReceive` gas toward Stellar to 4,000,000 (the run also re-applies the send and receive config) | [`0xaf6daacd…`](https://sepolia.arbiscan.io/tx/0xaf6daacd5bbbb878843cfb21669fad4f3d855218243c4a6a7428dcf96d1f64e2), [`0xa47bcaf9…`](https://sepolia.arbiscan.io/tx/0xa47bcaf97f3beb9d00354d918f0e6d777f5770405babd98201e9f532f9363f60), [`0xa726811d…`](https://sepolia.arbiscan.io/tx/0xa726811d89ca1fac7e495173450fe49863f40b4bb7caff307640e55074d04fcc) |

## Round trip (2026-11-16)

| # | Direction | Amount | Source transaction | LayerZero message | Delivery |
|---|---|---|---|---|---|
| 1 | Stellar to Arbitrum Sepolia, from `GCTZKGWA…` to `0xb22518ee…` | 10 | [`f9c1fc15f7…`](https://stellar.expert/explorer/testnet/tx/f9c1fc15f7ab3a714aadd398d7f4639233a82b9dc8f5e95c36231eb6b2980d1c) | [`0x12e5baee…`](https://testnet.layerzeroscan.com/tx/0x12e5baee8ccb290ac2f8c4043ec8b5945bd0cae585d6c0dfe1bc7ba29714d4ed) | [`0xf43613f9…`](https://sepolia.arbiscan.io/tx/0xf43613f974eda603829640c18ce31cd4fbba1459b34ee851d47539bdf346b837), by the LayerZero executor, about 40 seconds |
| 2 | Arbitrum Sepolia to Stellar, back to `GCTZKGWA…` | 4 | [`0x65c86689…`](https://sepolia.arbiscan.io/tx/0x65c8668909d000b6a220720ab2641ec323dfbaf4c5810f8ada4d719fa5cf2e93) | [`0xe9f6476d…`](https://testnet.layerzeroscan.com/tx/0xe9f6476d3afaf684557f06d44598e628312b17ddd1d0673898cbd65c59c189d5) | [`84a89e91ee…`](https://stellar.expert/explorer/testnet/tx/84a89e91eec244cef8dccb740d2b7da30b450353425331ea2d361afc4309bf04), executed by `writz-deployer` (see below) |
| 3 | Arbitrum Sepolia to Stellar, back to `GCTZKGWA…` | 1 | [`0x9e3acbba…`](https://sepolia.arbiscan.io/tx/0x9e3acbba973ba52850d8eafcc6cfc98d45cd888316ac18a5f1ccd866db937573) | [`0xcac19983…`](https://testnet.layerzeroscan.com/tx/0xcac19983995c0a155aa955cb1bf2b70e17fc818ff0e848e11373c147aa6fb0b5) | [`a758c4da9d…`](https://stellar.expert/explorer/testnet/tx/a758c4da9db2dbb7133aff6915dc450978ae7b2d59ad87080a081d3c9cd498a3), by the LayerZero executor, about 40 seconds |

After the three transfers: 5 on Arbitrum Sepolia (`totalSupply`) and 999,995 on Stellar (998,999.9602730 in accounts, 995.0397270 in contracts, the Soroswap pool among them), 1,000,000 in total, the amount issued on 2026-10-26. The liquidity account went from 999,000 to 998,995.

**Why message 2 needed a manual execution.** It was sent with the enforced `lzReceive` gas of 500,000, the value USDT0 uses toward Stellar mainnet. Toward Stellar the executor turns that gas into a budget of stroops, about 2.3 million, while the receive and mint cost about 11.5 million stroops on testnet, where state rent is priced far higher; the executor's simulation failed (`Gas limit exceeded: simulated 11509976 stroops > profiled 2300760 stroops`). The DVN had verified the message, so `writz-deployer` executed `lz_receive` on the Stellar OFT with the verified GUID and payload (`keccak256(guid || message)` matched the verified payload hash), paying about 1.15 XLM. The enforced gas was then raised to 4,000,000, and message 3 was delivered by the executor with no intervention.

Ethereum Sepolia was considered and dropped: since its 2026 gas repricing, deploying this contract needs about 23.9 million gas, above Sepolia's per-transaction cap of 16,777,216. On Arbitrum Sepolia it takes about 3.4 million.


| Contract | Address |
|---|---|
| EndpointV2 | `0x6EDCE65403992e310A62460808c4b910D972f10f` |
| SendUln302 | `0x4f7cd4DA19ABB31b0eC98b9066B9e857B1bf9C0E` |
| ReceiveUln302 | `0x75Db67CDab2824970131D5aa9CECfC9F69c69636` |
| Executor | `0x5Df3a1cEbBD9c8BA7F8dF51Fd632A9aef8308897` |
| DVN (the endpoint's default for Stellar, LayerZero Labs) | `0x53f488E93b4f1b60E8E83aa374dBe1780A1EE8a8` |
