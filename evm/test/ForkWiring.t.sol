// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Test } from "forge-std/Test.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import { WritzUsdt0TestOFT } from "../src/WritzUsdt0TestOFT.sol";
import { Usdt0TestOftBase } from "../script/Usdt0TestOft.s.sol";

/// Runs the Wire script's configuration against the live LayerZero contracts on a fork of
/// Arbitrum Sepolia, then quotes a send to Stellar. Skipped unless ARBITRUM_SEPOLIA_RPC_URL is set.
contract ForkWiringTest is Test, Usdt0TestOftBase {
    // The Stellar OFT on testnet, CDQLOSDFZKRZLHYHDGOPBNF2EW6ZW3YVOPROH2CVNMNEVR3CLWRDVFCC.
    bytes32 private constant STELLAR_OFT = 0xe0b74865caa3959f07199cf0b4ba25bd9b6f1573e2e3e8556b1a4ac7625da23a;

    WritzUsdt0TestOFT private oft;
    address private owner = makeAddr("owner");

    function setUp() public {
        string memory rpc = vm.envOr("ARBITRUM_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc);
        vm.prank(owner);
        oft = new WritzUsdt0TestOFT(ENDPOINT, owner);
    }

    function test_wiring_against_the_live_endpoint() public {
        vm.startPrank(owner);
        _wire(oft, STELLAR_OFT);
        vm.stopPrank();
        _checkWiring(oft, STELLAR_OFT);
    }

    function test_quotes_a_send_to_stellar_with_the_enforced_options() public {
        vm.startPrank(owner);
        _wire(oft, STELLAR_OFT);
        vm.stopPrank();
        SendParam memory sendParam = SendParam(STELLAR_EID, STELLAR_OFT, 1e6, 1e6, "", "", "");
        MessagingFee memory fee = oft.quoteSend(sendParam, false);
        assertGt(fee.nativeFee, 0, "the live executor and DVN price the Stellar pathway");
        emit log_named_uint("fee to Stellar (wei)", fee.nativeFee);
    }
}
