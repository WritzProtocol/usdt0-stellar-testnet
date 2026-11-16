// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Script, console2 } from "forge-std/Script.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import { ExecutorConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import { WritzUsdt0TestOFT } from "../src/WritzUsdt0TestOFT.sol";

/// Arbitrum Sepolia side of the USDT0 testnet token (Writz-deployed LayerZero OFT).
///
/// Without --broadcast, forge simulates every call against the live chain and sends nothing.
/// The deployer key is read from the EVM_TESTNET_DEPLOYER_KEY environment variable, never passed on the
/// command line. It is a testnet-only key.
abstract contract Usdt0TestOftBase is Script {
    using OptionsBuilder for bytes;

    // LayerZero V2 on Arbitrum Sepolia (metadata.layerzero-api.com, arbsep-testnet).
    uint32 internal constant LOCAL_EID = 40231;
    address internal constant ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address internal constant SEND_ULN302 = 0x4f7cd4DA19ABB31b0eC98b9066B9e857B1bf9C0E;
    address internal constant RECEIVE_ULN302 = 0x75Db67CDab2824970131D5aa9CECfC9F69c69636;
    address internal constant EXECUTOR = 0x5Df3a1cEbBD9c8BA7F8dF51Fd632A9aef8308897;
    // The endpoint's default required DVN for the Stellar pathway (LayerZero Labs).
    address internal constant DVN = 0x53f488E93b4f1b60E8E83aa374dBe1780A1EE8a8;

    // The remote side: Stellar testnet.
    uint32 internal constant STELLAR_EID = 40600;
    uint64 internal constant SEND_CONFIRMATIONS = 5; // what Stellar's receive config waits for
    uint64 internal constant RECEIVE_CONFIRMATIONS = 1; // what Stellar's send config gives
    // Toward Stellar, LayerZero's executor turns this gas into a budget of stroops for the lz_receive
    // transaction. USDT0 enforces 500,000 toward Stellar mainnet; on Stellar testnet, where state rent is
    // priced far higher, a receive and mint cost about 11.5 million stroops against the 2.3 million that
    // 500,000 buys, and the executor refused to deliver. 4,000,000 buys about 18 million stroops.
    uint128 internal constant STELLAR_LZ_RECEIVE_GAS = 4_000_000;

    uint16 internal constant MSG_TYPE_SEND = 1;
    uint32 internal constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 internal constant CONFIG_TYPE_ULN = 2;
    uint32 internal constant MAX_MESSAGE_SIZE = 10_000;

    function _deployerKey() internal view returns (uint256) {
        return vm.envUint("EVM_TESTNET_DEPLOYER_KEY");
    }

    function _uln(uint64 confirmations) internal pure returns (bytes memory) {
        address[] memory required = new address[](1);
        required[0] = DVN;
        return abi.encode(UlnConfig(confirmations, 1, 0, 0, required, new address[](0)));
    }

    function _enforcedOptions() internal pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(STELLAR_LZ_RECEIVE_GAS, 0);
    }

    /// Peer, libraries, executor and DVN config, and enforced options for Stellar. Caller must be the owner.
    function _wire(WritzUsdt0TestOFT oft, bytes32 stellarPeer) internal {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(ENDPOINT);
        SetConfigParam[] memory sendConfig = new SetConfigParam[](2);
        sendConfig[0] = SetConfigParam(STELLAR_EID, CONFIG_TYPE_EXECUTOR, abi.encode(ExecutorConfig(MAX_MESSAGE_SIZE, EXECUTOR)));
        sendConfig[1] = SetConfigParam(STELLAR_EID, CONFIG_TYPE_ULN, _uln(SEND_CONFIRMATIONS));
        SetConfigParam[] memory receiveConfig = new SetConfigParam[](1);
        receiveConfig[0] = SetConfigParam(STELLAR_EID, CONFIG_TYPE_ULN, _uln(RECEIVE_CONFIRMATIONS));
        EnforcedOptionParam[] memory enforced = new EnforcedOptionParam[](1);
        enforced[0] = EnforcedOptionParam(STELLAR_EID, MSG_TYPE_SEND, _enforcedOptions());

        // Safe to re-run: the endpoint rejects setting a library that is already set (LZ_SameValue).
        if (oft.peers(STELLAR_EID) != stellarPeer) oft.setPeer(STELLAR_EID, stellarPeer);
        if (endpoint.isDefaultSendLibrary(address(oft), STELLAR_EID) || endpoint.getSendLibrary(address(oft), STELLAR_EID) != SEND_ULN302) {
            endpoint.setSendLibrary(address(oft), STELLAR_EID, SEND_ULN302);
        }
        (address receiveLib, bool receiveIsDefault) = endpoint.getReceiveLibrary(address(oft), STELLAR_EID);
        if (receiveIsDefault || receiveLib != RECEIVE_ULN302) endpoint.setReceiveLibrary(address(oft), STELLAR_EID, RECEIVE_ULN302, 0);
        endpoint.setConfig(address(oft), SEND_ULN302, sendConfig);
        endpoint.setConfig(address(oft), RECEIVE_ULN302, receiveConfig);
        oft.setEnforcedOptions(enforced);
    }

    function _checkWiring(WritzUsdt0TestOFT oft, bytes32 stellarPeer) internal view {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(ENDPOINT);
        require(oft.peers(STELLAR_EID) == stellarPeer, "peer not set");
        require(endpoint.getSendLibrary(address(oft), STELLAR_EID) == SEND_ULN302, "send library not set");
        (address receiveLib, bool isDefault) = endpoint.getReceiveLibrary(address(oft), STELLAR_EID);
        require(receiveLib == RECEIVE_ULN302 && !isDefault, "receive library not set");
        require(
            keccak256(endpoint.getConfig(address(oft), SEND_ULN302, STELLAR_EID, CONFIG_TYPE_EXECUTOR))
                == keccak256(abi.encode(ExecutorConfig(MAX_MESSAGE_SIZE, EXECUTOR))),
            "executor config"
        );
        require(keccak256(endpoint.getConfig(address(oft), SEND_ULN302, STELLAR_EID, CONFIG_TYPE_ULN)) == keccak256(_uln(SEND_CONFIRMATIONS)), "send ULN config");
        require(keccak256(endpoint.getConfig(address(oft), RECEIVE_ULN302, STELLAR_EID, CONFIG_TYPE_ULN)) == keccak256(_uln(RECEIVE_CONFIRMATIONS)), "receive ULN config");
        require(keccak256(oft.enforcedOptions(STELLAR_EID, MSG_TYPE_SEND)) == keccak256(_enforcedOptions()), "enforced options");
    }
}

/// forge script script/Usdt0TestOft.s.sol:Deploy --rpc-url arbitrum_sepolia [--broadcast]
contract Deploy is Usdt0TestOftBase {
    function run() external returns (WritzUsdt0TestOFT oft) {
        uint256 key = _deployerKey();
        address owner = vm.addr(key);
        console2.log("owner and delegate", owner);
        vm.startBroadcast(key);
        oft = new WritzUsdt0TestOFT(ENDPOINT, owner);
        vm.stopBroadcast();
        console2.log("WritzUsdt0TestOFT", address(oft));
    }
}

/// EVM_OFT=0x... STELLAR_OFT_BYTES32=0x... forge script script/Usdt0TestOft.s.sol:Wire --rpc-url arbitrum_sepolia [--broadcast]
///
/// STELLAR_OFT_BYTES32 is the 32-byte contract ID of the Stellar OFT, which
/// `node stellar/oft.mjs status` prints.
contract Wire is Usdt0TestOftBase {
    function run() external {
        WritzUsdt0TestOFT oft = WritzUsdt0TestOFT(vm.envAddress("EVM_OFT"));
        bytes32 stellarPeer = vm.envBytes32("STELLAR_OFT_BYTES32");
        vm.startBroadcast(_deployerKey());
        _wire(oft, stellarPeer);
        vm.stopBroadcast();
        _checkWiring(oft, stellarPeer);
        console2.log("wired to Stellar EID", STELLAR_EID);
    }
}

/// EVM_OFT=0x... STELLAR_RECIPIENT_BYTES32=0x... AMOUNT=<6-decimal units> forge script script/Usdt0TestOft.s.sol:SendToStellar --rpc-url arbitrum_sepolia [--broadcast]
///
/// The recipient is the raw 32 bytes of a Stellar account (G...) or contract (C...).
/// A Stellar account must hold a USDT0 trustline first, or the mint on Stellar fails
/// and the message waits on the endpoint until it is retried.
contract SendToStellar is Usdt0TestOftBase {
    function run() external {
        WritzUsdt0TestOFT oft = WritzUsdt0TestOFT(vm.envAddress("EVM_OFT"));
        uint256 amount = vm.envUint("AMOUNT");
        SendParam memory sendParam = SendParam({
            dstEid: STELLAR_EID,
            to: vm.envBytes32("STELLAR_RECIPIENT_BYTES32"),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = oft.quoteSend(sendParam, false);
        console2.log("LayerZero fee (wei)", fee.nativeFee);

        uint256 key = _deployerKey();
        vm.startBroadcast(key);
        oft.send{ value: fee.nativeFee }(sendParam, fee, vm.addr(key));
        vm.stopBroadcast();
    }
}
