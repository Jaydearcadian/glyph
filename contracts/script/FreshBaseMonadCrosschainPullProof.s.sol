// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {GlyphLayerZeroApplication} from "../src/GlyphLayerZeroApplication.sol";
import {TestToken} from "../src/TestToken.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";

/// @notice Env-configurable live Base Sepolia -> Monad Testnet Pull proof for a fresh LZ lane.
contract FreshBaseMonadCrosschainPullProof is Script {
    uint256 constant MAXIMUM_INPUT = 11 ether;
    uint256 constant DESTINATION_AMOUNT = 10 ether;
    uint256 constant PROVIDER_FEE = 1 ether;
    uint256 constant GAS_LIMIT = 500_000;
    uint256 constant FINALIZE_FEE_BUDGET = 0.01 ether;

    function runEscrow() external {
        require(block.chainid == 84532, "Base Sepolia only");
        uint256 pk = vm.envUint("BASE_PK");
        address payer = vm.addr(pk);
        SourceDeltaRouter router = SourceDeltaRouter(vm.envAddress("BASE_ROUTER"));
        TestToken token = TestToken(vm.envAddress("BASE_TOKEN"));
        uint256 nonce = router.actorNonce(payer);
        SourceDeltaRouter.Terms memory t = _terms(router, token, payer, nonce);
        vm.startBroadcast(pk);
        token.approve(address(router), MAXIMUM_INPUT);
        bytes32 op = router.escrow(t);
        vm.stopBroadcast();
        console2.log("FRESH_CROSSCHAIN_ESCROW_COMPLETE", true);
        console2.log("payer", payer);
        console2.log("operation", vm.toString(op));
        console2.log("nonce", nonce);
    }

    function runRoute() external {
        require(block.chainid == 84532, "Base Sepolia only");
        uint256 pk = vm.envUint("BASE_PK");
        address owner = vm.addr(pk);
        bytes32 op = vm.envBytes32("OPERATION_ID");
        GlyphLayerZeroApplication app = GlyphLayerZeroApplication(payable(vm.envAddress("BASE_APP")));
        uint256 fee = app.quoteRouteFromEscrow(op, GAS_LIMIT);
        vm.startBroadcast(pk);
        bytes32 messageId = app.sendRouteFromEscrow{value: fee}(op, payable(owner), GAS_LIMIT);
        vm.stopBroadcast();
        console2.log("FRESH_CROSSCHAIN_ROUTE_SENT", true);
        console2.log("operation", vm.toString(op));
        console2.log("route message", vm.toString(messageId));
        console2.log("fee", fee);
    }

    function runFinalize() external {
        require(block.chainid == 84532, "Base Sepolia only");
        uint256 pk = vm.envUint("BASE_PK");
        address owner = vm.addr(pk);
        bytes32 op = vm.envBytes32("OPERATION_ID");
        GlyphLayerZeroApplication app = GlyphLayerZeroApplication(payable(vm.envAddress("BASE_APP")));
        vm.startBroadcast(pk);
        bytes32 messageId = app.finalizeAndSendReceipt{value: FINALIZE_FEE_BUDGET}(op, payable(owner), GAS_LIMIT);
        vm.stopBroadcast();
        console2.log("FRESH_CROSSCHAIN_FINALIZE_SENT", true);
        console2.log("operation", vm.toString(op));
        console2.log("terminal receipt message", vm.toString(messageId));
    }

    function _terms(SourceDeltaRouter router, TestToken token, address actor, uint256 nonce)
        internal
        view
        returns (SourceDeltaRouter.Terms memory)
    {
        return SourceDeltaRouter.Terms({
            mode: router.PULL(),
            programId: bytes32(0),
            payer: actor,
            recipient: actor,
            recovery: actor,
            sourceAsset: IERC20Minimal(address(token)),
            sourceChainId: 84532,
            destinationVault: vm.envAddress("MONAD_VAULT"),
            destinationAsset: vm.envAddress("MONAD_TOKEN"),
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
