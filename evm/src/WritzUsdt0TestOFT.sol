// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/// @title USDT0 testnet token (Writz-deployed LayerZero OFT), Arbitrum Sepolia side
/// @notice No official USDT0 exists on any testnet. This is a test token Writz deploys so the
/// LayerZero OFT path between Stellar testnet and Arbitrum Sepolia can be exercised end to end.
/// It has no value and is not issued, endorsed or backed by USDT0 or Tether.
/// @dev Plain LayerZero V2 OFT: burns on send, mints on receive. It starts with zero supply;
/// every unit on this chain was burned on Stellar first, so the supply on both chains together
/// never exceeds what the Stellar side has issued. Six decimals, like USDT0, so the shared
/// decimals (6) equal the local decimals and no dust is removed on this side.
contract WritzUsdt0TestOFT is OFT {
    constructor(
        address _lzEndpoint,
        address _delegate
    ) OFT("USDT0 testnet token (Writz-deployed LayerZero OFT)", "USDT0", _lzEndpoint, _delegate) Ownable(_delegate) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
