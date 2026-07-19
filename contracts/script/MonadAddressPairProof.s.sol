// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {GlyphLayerZeroApplication} from "../src/GlyphLayerZeroApplication.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {TestToken} from "../src/TestToken.sol";
import {LocalLoopbackGlyphAdapter} from "../src/LocalLoopbackGlyphAdapter.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";

/// @notice One-shot Monad testnet address-pair proof:
/// deploy fresh current-source loopback stack, then execute local Pull + Push
/// from funded payer to a separate claimant/recipient address.
/// Requires env MONAD_PK and CLAIMANT_PK. Testnet only.
contract MonadAddressPairProof is Script {
    SourceDeltaRouter router = SourceDeltaRouter(0xC71C119B91Fa1F1861626843Fa653F41cEF9101A);
    TestToken token = TestToken(0x1d482783316FdeF2e795A1C193ACE280660A887a);
    bytes32 policyHash = 0x9f2b1c4e7a3d5f6082b4c9e1d7a0f3b6c5e8d2a4b7c9e1f3a5b7c9d1e3f5a7b9;

    uint256 constant VAULT_SEED = 100 ether;
    uint256 constant SOURCE_TOP_UP = 50 ether;
    uint256 constant MAXIMUM_INPUT = 11 ether;
    uint256 constant DESTINATION_AMOUNT = 10 ether;
    uint256 constant PROVIDER_FEE = 1 ether;
    uint256 constant GAS_LIMIT = 300_000;

    struct Stack {
        DestinationGlyphVault vault;
        LocalLoopbackGlyphAdapter adapter;
        GlyphLayerZeroApplication srcApp;
        GlyphLayerZeroApplication dstApp;
    }

    function run() external {
        uint256 payerPk = vm.envUint("MONAD_PK");
        uint256 claimantPk = vm.envUint("CLAIMANT_PK");
        address payer = vm.addr(payerPk);
        address claimant = vm.addr(claimantPk);

        vm.startBroadcast(payerPk);

        Stack memory stack = _deployStack(payer);
        token.mint(payer, SOURCE_TOP_UP);
        console2.log("payer", payer);
        console2.log("claimant/recipient", claimant);
        console2.log("router", address(router));
        console2.log("token", address(token));
        console2.log("vault", address(stack.vault));
        console2.log("adapter", address(stack.adapter));
        console2.log("source app", address(stack.srcApp));
        console2.log("dest app", address(stack.dstApp));

        bytes32 pullOp = _executePull(stack, payer, claimant);
        bytes32 pushOp = _executePush(stack, payerPk, claimantPk, payer, claimant);

        console2.log("ADDRESS-PAIR-PROOF COMPLETE", true);
        console2.log("pull op", vm.toString(pullOp));
        console2.log("pull destination receipt", vm.toString(stack.dstApp.sourceTerminalReceipt(pullOp)));
        console2.log("push op", vm.toString(pushOp));
        console2.log("push destination receipt", vm.toString(stack.dstApp.sourceTerminalReceipt(pushOp)));
        console2.log("payer gTST", token.balanceOf(payer) / 1e18);
        console2.log("claimant gTST", token.balanceOf(claimant) / 1e18);
        vm.stopBroadcast();
    }

    function _deployStack(address owner) internal returns (Stack memory stack) {
        stack.vault = new DestinationGlyphVault();
        token.mint(owner, VAULT_SEED);
        token.approve(address(stack.vault), VAULT_SEED);
        stack.vault.provideLiquidity(IERC20Minimal(address(token)), VAULT_SEED);

        stack.adapter = new LocalLoopbackGlyphAdapter();
        stack.srcApp = new GlyphLayerZeroApplication(
            GlyphLayerZeroApplication.Side.SOURCE, 10143, 10143, router, stack.vault, owner
        );
        stack.dstApp = new GlyphLayerZeroApplication(
            GlyphLayerZeroApplication.Side.DESTINATION, 10143, 10143, router, stack.vault, owner
        );

        router.setMessengerAdapter(address(stack.adapter), true);
        router.setMessengerProcessorForAdapter(address(stack.srcApp), address(stack.adapter), true);
        router.setMessengerProcessorForAdapter(address(stack.dstApp), address(stack.adapter), true);

        stack.srcApp.setAdapter(stack.adapter);
        stack.srcApp.setRemoteApplication(address(stack.dstApp));
        stack.srcApp.freezeConfig(policyHash);

        stack.dstApp.setAdapter(stack.adapter);
        stack.dstApp.setRemoteApplication(address(stack.srcApp));
        stack.dstApp.freezeConfig(policyHash);

        stack.vault.setAuthorizedApplication(address(stack.dstApp), true);
    }

    function _executePull(Stack memory stack, address payer, address recipient) internal returns (bytes32 op) {
        SourceDeltaRouter.Terms memory t = _terms(router.PULL(), payer, recipient, address(0), stack);
        token.approve(address(router), MAXIMUM_INPUT);
        op = router.escrow(t);
        bytes32 routeId = stack.srcApp.sendRouteFromEscrow(op, payable(payer), GAS_LIMIT);
        stack.adapter.deliver(routeId);
        bytes32 deliveredAckId = stack.adapter.lastMessageId();
        stack.adapter.deliver(deliveredAckId);
        bytes32 receiptId = stack.srcApp.finalizeAndSendReceipt(op, payable(payer), GAS_LIMIT);
        stack.adapter.deliver(receiptId);
        require(stack.dstApp.sourceTerminalReceipt(op) != bytes32(0), "pull receipt missing");
        console2.log("pull delivered to", recipient);
        console2.log("pull op", vm.toString(op));
    }

    function _executePush(Stack memory stack, uint256 payerPk, uint256 claimantPk, address payer, address claimant)
        internal
        returns (bytes32 op)
    {
        SourceDeltaRouter.Terms memory t = _terms(router.PUSH(), payer, payer, payer, stack);
        token.approve(address(router), MAXIMUM_INPUT);
        op = router.escrow(t);
        bytes32 reserveRouteId = stack.srcApp.sendRouteFromEscrow(op, payable(payer), GAS_LIMIT);
        stack.adapter.deliver(reserveRouteId);
        bytes32 reservedAckId = stack.adapter.lastMessageId();
        stack.adapter.deliver(reservedAckId);

        bytes32 nullifier = keccak256(abi.encode("glyph.live.monad.address-pair.push.nullifier.v1", op, claimant));
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory claimantSig = _claimantSig(claimantPk, address(stack.vault), op, claimant, nullifier, deadline);
        bytes memory gatekeeperSig = _gatekeeperSig(payerPk, address(stack.vault), op, claimant, nullifier, deadline);
        stack.dstApp.claimPushAndAck(op, claimant, nullifier, deadline, claimantSig, gatekeeperSig);
        bytes32 deliveredAckId = stack.adapter.lastMessageId();
        stack.adapter.deliver(deliveredAckId);

        bytes32 receiptId = stack.srcApp.finalizeAndSendReceipt(op, payable(payer), GAS_LIMIT);
        stack.adapter.deliver(receiptId);
        require(stack.dstApp.sourceTerminalReceipt(op) != bytes32(0), "push receipt missing");
        console2.log("push claimed by", claimant);
        console2.log("push op", vm.toString(op));
    }

    function _terms(bytes32 mode, address payer, address recipient, address gatekeeper, Stack memory stack)
        internal
        view
        returns (SourceDeltaRouter.Terms memory)
    {
        return SourceDeltaRouter.Terms({
            mode: mode,
            programId: bytes32(0),
            payer: payer,
            recipient: recipient,
            recovery: payer,
            sourceAsset: IERC20Minimal(address(token)),
            sourceChainId: 10143,
            destinationVault: address(stack.vault),
            destinationAsset: address(token),
            destinationChainId: 10143,
            maximumInput: MAXIMUM_INPUT,
            destinationAmount: DESTINATION_AMOUNT,
            protocolFee: 0,
            providerFee: PROVIDER_FEE,
            referrerFee: 0,
            gasSponsorFee: 0,
            provider: payer,
            protocol: payer,
            referrer: payer,
            gasSponsor: payer,
            claimGatekeeper: gatekeeper,
            expiry: uint64(block.timestamp + 1 days),
            nonce: router.actorNonce(payer)
        });
    }

    function _claimantSig(
        uint256 claimantPk,
        address vault,
        bytes32 op,
        address claimant,
        bytes32 nullifier,
        uint64 deadline
    ) internal returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encode(
                "GLYPH_CLAIM_INTENT_V1", block.chainid, vault, op, claimant, DESTINATION_AMOUNT, nullifier, deadline
            )
        );
        return _sign(claimantPk, digest);
    }

    function _gatekeeperSig(
        uint256 gatekeeperPk,
        address vault,
        bytes32 op,
        address claimant,
        bytes32 nullifier,
        uint64 deadline
    ) internal returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encode(
                "GLYPH_CLAIM_AUTH_V1",
                block.chainid,
                vault,
                op,
                claimant,
                address(token),
                DESTINATION_AMOUNT,
                nullifier,
                deadline
            )
        );
        return _sign(gatekeeperPk, digest);
    }

    function _sign(uint256 pk, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
