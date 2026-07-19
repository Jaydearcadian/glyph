// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {GlyphLayerZeroApplication} from "../src/GlyphLayerZeroApplication.sol";
import {TestToken} from "../src/TestToken.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";

/// @notice Split live Base Sepolia -> Monad Testnet Pull proof scripts.
/// Use runEscrow on Base, runRoute on Base, wait for ACK, then runFinalize on Base.
contract BaseMonadCrosschainPullProof is Script {
    SourceDeltaRouter constant BASE_ROUTER = SourceDeltaRouter(0xB28C11AE970D4bDDA4a221B9A5Ceb5d287d336f3);
    GlyphLayerZeroApplication constant BASE_APP =
        GlyphLayerZeroApplication(payable(0x689979129F4aD12dF09C0A48d7dD08af3b73fF5D));
    TestToken constant BASE_TOKEN = TestToken(0xc0d50bB3Aee4C7BF969d143fC8D8A78841Bc752f);

    address constant MONAD_VAULT = 0x5c9B29130A91c8419CCAa33D7fEBE6dE0B26824A;
    address constant MONAD_TOKEN = 0x1d482783316FdeF2e795A1C193ACE280660A887a;

    uint256 constant MAXIMUM_INPUT = 11 ether;
    uint256 constant DESTINATION_AMOUNT = 10 ether;
    uint256 constant PROVIDER_FEE = 1 ether;
    uint256 constant GAS_LIMIT = 500_000;
    uint256 constant FINALIZE_FEE_BUDGET = 0.01 ether;

    function runEscrow() external {
        require(block.chainid == 84532, "Base Sepolia only");
        uint256 pk = vm.envUint("BASE_PK");
        address payer = vm.addr(pk);
        uint256 nonce = BASE_ROUTER.actorNonce(payer);
        SourceDeltaRouter.Terms memory t = _terms(payer, nonce);
        vm.startBroadcast(pk);
        BASE_TOKEN.approve(address(BASE_ROUTER), MAXIMUM_INPUT);
        bytes32 op = BASE_ROUTER.escrow(t);
        vm.stopBroadcast();
        console2.log("CROSSCHAIN_ESCROW_COMPLETE", true);
        console2.log("payer", payer);
        console2.log("operation", vm.toString(op));
        console2.log("nonce", nonce);
    }

    function runRoute() external {
        require(block.chainid == 84532, "Base Sepolia only");
        uint256 pk = vm.envUint("BASE_PK");
        address owner = vm.addr(pk);
        bytes32 op = vm.envBytes32("OPERATION_ID");
        uint256 fee = BASE_APP.quoteRouteFromEscrow(op, GAS_LIMIT);
        vm.startBroadcast(pk);
        bytes32 messageId = BASE_APP.sendRouteFromEscrow{value: fee}(op, payable(owner), GAS_LIMIT);
        vm.stopBroadcast();
        console2.log("CROSSCHAIN_ROUTE_SENT", true);
        console2.log("operation", vm.toString(op));
        console2.log("route message", vm.toString(messageId));
        console2.log("fee", fee);
    }

    function runFinalize() external {
        require(block.chainid == 84532, "Base Sepolia only");
        uint256 pk = vm.envUint("BASE_PK");
        address owner = vm.addr(pk);
        bytes32 op = vm.envBytes32("OPERATION_ID");
        vm.startBroadcast(pk);
        bytes32 messageId = BASE_APP.finalizeAndSendReceipt{value: FINALIZE_FEE_BUDGET}(op, payable(owner), GAS_LIMIT);
        vm.stopBroadcast();
        console2.log("CROSSCHAIN_FINALIZE_SENT", true);
        console2.log("operation", vm.toString(op));
        console2.log("terminal receipt message", vm.toString(messageId));
        console2.log("fee budget", FINALIZE_FEE_BUDGET);
    }

    function _terms(address actor, uint256 nonce) internal view returns (SourceDeltaRouter.Terms memory) {
        return SourceDeltaRouter.Terms({
            mode: BASE_ROUTER.PULL(),
            programId: bytes32(0),
            payer: actor,
            recipient: actor,
            recovery: actor,
            sourceAsset: IERC20Minimal(address(BASE_TOKEN)),
            sourceChainId: 84532,
            destinationVault: MONAD_VAULT,
            destinationAsset: MONAD_TOKEN,
            destinationChainId: 10143,
            maximumInput: MAXIMUM_INPUT,
            destinationAmount: DESTINATION_AMOUNT,
            protocolFee: 0,
            providerFee: PROVIDER_FEE,
            referrerFee: 0,
            gasSponsorFee: 0,
            provider: actor,
            protocol: actor,
            referrer: actor,
            gasSponsor: actor,
            claimGatekeeper: address(0),
            expiry: uint64(block.timestamp + 1 days),
            nonce: nonce
        });
    }
}
