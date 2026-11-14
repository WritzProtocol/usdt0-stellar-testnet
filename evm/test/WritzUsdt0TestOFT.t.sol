// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

import { WritzUsdt0TestOFT } from "../src/WritzUsdt0TestOFT.sol";

/// Stands in for the Stellar side, which holds the issued supply: same contract plus a mint.
contract SupplySideOFT is WritzUsdt0TestOFT {
    constructor(address _lzEndpoint, address _delegate) WritzUsdt0TestOFT(_lzEndpoint, _delegate) {}

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}

contract WritzUsdt0TestOFTTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private constant A_EID = 1;
    uint32 private constant B_EID = 2;
    uint128 private constant LZ_RECEIVE_GAS = 80_000;

    SupplySideOFT private aOFT;
    WritzUsdt0TestOFT private bOFT;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");
    address private stranger = makeAddr("stranger");

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        vm.startPrank(owner);
        aOFT = new SupplySideOFT(address(endpoints[A_EID]), owner);
        bOFT = new WritzUsdt0TestOFT(address(endpoints[B_EID]), owner);
        vm.stopPrank();

        address[] memory oapps = new address[](2);
        oapps[0] = address(aOFT);
        oapps[1] = address(bOFT);
        vm.prank(owner);
        aOFT.transferOwnership(address(this));
        vm.prank(owner);
        bOFT.transferOwnership(address(this));
        wireOApps(oapps);

        // Enforced options, as on testnet: every send to the peer carries lzReceive gas.
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(LZ_RECEIVE_GAS, 0);
        EnforcedOptionParam[] memory toB = new EnforcedOptionParam[](1);
        toB[0] = EnforcedOptionParam(B_EID, 1, options);
        aOFT.setEnforcedOptions(toB);
        EnforcedOptionParam[] memory toA = new EnforcedOptionParam[](1);
        toA[0] = EnforcedOptionParam(A_EID, 1, options);
        bOFT.setEnforcedOptions(toA);

        aOFT.mint(user, 1_000e6);
        vm.deal(user, 10 ether);
    }

    function test_metadata_names_whose_token_it_is() public view {
        assertEq(bOFT.name(), "USDT0 testnet token (Writz-deployed LayerZero OFT)");
        assertEq(bOFT.symbol(), "USDT0");
        assertEq(bOFT.decimals(), 6);
        assertEq(bOFT.sharedDecimals(), 6);
        assertEq(bOFT.token(), address(bOFT));
        assertFalse(bOFT.approvalRequired());
    }

    function test_starts_with_zero_supply() public {
        WritzUsdt0TestOFT fresh = new WritzUsdt0TestOFT(address(endpoints[B_EID]), owner);
        assertEq(fresh.totalSupply(), 0);
        assertEq(fresh.owner(), owner);
    }

    function test_send_burns_on_source_and_mints_on_destination() public {
        uint256 amount = 25e6;
        SendParam memory sendParam = _sendParam(B_EID, user, amount);
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        vm.prank(user);
        (, OFTReceipt memory receipt) = aOFT.send{ value: fee.nativeFee }(sendParam, fee, user);
        verifyPackets(B_EID, addressToBytes32(address(bOFT)));

        assertEq(receipt.amountSentLD, amount);
        assertEq(receipt.amountReceivedLD, amount);
        assertEq(aOFT.balanceOf(user), 1_000e6 - amount);
        assertEq(bOFT.balanceOf(user), amount);
        assertEq(aOFT.totalSupply() + bOFT.totalSupply(), 1_000e6, "supply across both sides is conserved");
    }

    function test_round_trip_returns_the_supply() public {
        uint256 amount = 40e6;
        SendParam memory out = _sendParam(B_EID, user, amount);
        MessagingFee memory outFee = aOFT.quoteSend(out, false);
        vm.prank(user);
        aOFT.send{ value: outFee.nativeFee }(out, outFee, user);
        verifyPackets(B_EID, addressToBytes32(address(bOFT)));

        SendParam memory back = _sendParam(A_EID, user, amount);
        MessagingFee memory backFee = bOFT.quoteSend(back, false);
        vm.prank(user);
        bOFT.send{ value: backFee.nativeFee }(back, backFee, user);
        verifyPackets(A_EID, addressToBytes32(address(aOFT)));

        assertEq(bOFT.totalSupply(), 0);
        assertEq(aOFT.balanceOf(user), 1_000e6);
    }

    function test_enforced_options_apply_when_the_caller_passes_none() public view {
        bytes memory combined = aOFT.combineOptions(B_EID, 1, "");
        assertEq(combined, OptionsBuilder.newOptions().addExecutorLzReceiveOption(LZ_RECEIVE_GAS, 0));
    }

    function test_slippage_floor_is_enforced() public {
        SendParam memory sendParam = _sendParam(B_EID, user, 10e6);
        sendParam.minAmountLD = 10e6 + 1;
        MessagingFee memory fee = MessagingFee(1 ether, 0);
        vm.prank(user);
        vm.expectRevert();
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, user);
    }

    function test_only_the_owner_wires_the_token() public {
        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        bOFT.setPeer(A_EID, bytes32(uint256(1)));

        EnforcedOptionParam[] memory params = new EnforcedOptionParam[](1);
        params[0] = EnforcedOptionParam(A_EID, 1, OptionsBuilder.newOptions().addExecutorLzReceiveOption(1, 0));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        bOFT.setEnforcedOptions(params);
        vm.stopPrank();
    }

    function _sendParam(uint32 dstEid, address to, uint256 amount) private pure returns (SendParam memory) {
        return SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(to))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
    }
}
