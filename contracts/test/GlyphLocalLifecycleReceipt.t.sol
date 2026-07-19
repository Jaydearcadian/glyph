// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {GlyphReceiptLedger} from "../src/GlyphReceiptLedger.sol";
import {MockGlyphMessengerAdapter} from "../src/MockGlyphMessengerAdapter.sol";
import {IGlyphReceiptLedger} from "../src/interfaces/IGlyphReceiptLedger.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";
import {TestToken} from "./mocks/TestToken.sol";

contract GlyphLocalLifecycleReceiptTest is Test {
    SourceDeltaRouter router;
    DestinationGlyphVault vault;
    GlyphReceiptLedger ledger;
    MockGlyphMessengerAdapter messenger;
    TestToken token;

    uint256 payerPk = 0xA11CE;
    uint256 claimantPk = 0xC1A1;
    uint256 gatekeeperPk = 0xBEEF;
    address payer;
    address claimant;
    address gatekeeper;
    address recipient = address(0xB0B);
    address recovery = address(0xCAFE);
    address provider = address(0xF00D);
    address protocol = address(0x1000);
    address referrer = address(0x2000);
    address sponsor = address(0x3000);
    address app = address(0xA99);
    address writer = address(0x3001);

    function setUp() public {
        payer = vm.addr(payerPk);
        claimant = vm.addr(claimantPk);
        gatekeeper = vm.addr(gatekeeperPk);
        router = new SourceDeltaRouter();
        vault = new DestinationGlyphVault();
        ledger = new GlyphReceiptLedger(address(this));
        messenger = new MockGlyphMessengerAdapter();
        token = new TestToken();

        ledger.configureWriterAuthorization(writer, true, ledger.STATUS_WRITER());
        ledger.configureWriterAuthorization(writer, true, ledger.LOCAL_LEG_WRITER());
        ledger.configureWriterAuthorization(writer, true, ledger.SOURCE_FINALIZATION_WRITER());

        token.mint(payer, 10_000 ether);
        token.mint(provider, 10_000 ether);
        vm.prank(payer);
        token.approve(address(router), type(uint256).max);
        vm.prank(provider);
        token.approve(address(vault), type(uint256).max);
        vm.prank(provider);
        vault.provideLiquidity(IERC20Minimal(address(token)), 2_000 ether);

        vault.setAuthorizedApplication(app, true);
        router.setMessengerAdapter(address(messenger), true);
        router.setMessengerProcessorForAdapter(app, address(messenger), true);
    }

    function _terms(bytes32 mode, uint256 nonce, address recip)
        internal
        view
        returns (SourceDeltaRouter.Terms memory t)
    {
        t = SourceDeltaRouter.Terms({
            mode: mode,
            programId: bytes32(0),
            payer: payer,
            recipient: recip,
            recovery: recovery,
            sourceAsset: IERC20Minimal(address(token)),
            sourceChainId: uint64(block.chainid),
            destinationVault: address(vault),
            destinationAsset: address(token),
            destinationChainId: uint64(block.chainid),
            maximumInput: 110 ether,
            destinationAmount: 100 ether,
            protocolFee: 1 ether,
            providerFee: 2 ether,
            referrerFee: 3 ether,
            gasSponsorFee: 4 ether,
            provider: provider,
            protocol: protocol,
            referrer: referrer,
            gasSponsor: sponsor,
            claimGatekeeper: mode == router.PUSH() ? gatekeeper : address(0),
            expiry: uint64(block.timestamp + 1 days),
            nonce: nonce
        });
    }

    function _ledgerTerms(
        SourceDeltaRouter.Terms memory t,
        bytes32 operationType,
        address finalRecipient,
        uint256 nonce
    ) internal view returns (IGlyphReceiptLedger.OperationTerms memory lt) {
        lt = IGlyphReceiptLedger.OperationTerms({
            operationType: operationType,
            proposedPurposeCode: keccak256("glyph.purpose.local.mvp.v1"),
            initiator: payer,
            payer: t.payer,
            recipient: finalRecipient,
            recoveryAddress: t.recovery,
            sourceRouter: address(router),
            destinationVault: address(vault),
            sourceChainId: t.sourceChainId,
            destinationChainId: t.destinationChainId,
            sourceAsset: address(t.sourceAsset),
            destinationAsset: t.destinationAsset,
            maximumInput: t.maximumInput,
            destinationAmount: t.destinationAmount,
            maximumFee: t.protocolFee + t.providerFee + t.referrerFee + t.gasSponsorFee,
            claimantRule: t.mode == router.PUSH()
                ? keccak256("glyph.claimant.gatekeeper-signed.v1")
                : keccak256("glyph.claimant.exact-recipient.v1"),
            privateContextHash: keccak256("local lifecycle private context"),
            expiry: t.expiry,
            nonce: nonce
        });
    }

    function _leg(bytes32 op, bytes32 legType, uint256 amount, address asset, address from, address to, uint32 logIndex)
        internal
        view
        returns (IGlyphReceiptLedger.ValueLegInput memory l)
    {
        l = IGlyphReceiptLedger.ValueLegInput({
            operationId: op,
            chainId: uint64(block.chainid),
            transactionHash: keccak256(abi.encode("local-leg", op, legType, logIndex)),
            logIndex: logIndex,
            asset: asset,
            from: from,
            to: to,
            amount: amount,
            legType: legType,
            proofKind: IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED,
            proofReference: keccak256("local-same-chain-proof")
        });
    }

    function _sourceFinalizeTx(bytes32 op) internal pure returns (bytes32) {
        return keccak256(abi.encode("local-leg", op, keccak256("glyph.leg.source-finalized.v1"), uint32(7)));
    }

    function _receipt(bytes32 op) internal view returns (IGlyphReceiptLedger.DeltaReconciliation memory d) {
        d = IGlyphReceiptLedger.DeltaReconciliation({
            sourceAsset: address(token),
            maximumInput: 110 ether,
            realizedPrincipal: 100 ether,
            realizedFees: 10 ether,
            residualReturned: 0,
            recoveryAddress: recovery,
            sourceFinalizeTx: _sourceFinalizeTx(op),
            expectedDestinationAmount: 100 ether,
            actualDestinationDelivered: 100 ether,
            excessDestinationDelivered: 0,
            destinationExcessPolicy: keccak256("glyph.destination.excess.recipient-retains.v1")
        });
    }

    function _registerReceipt(
        SourceDeltaRouter.Terms memory t,
        bytes32 operationType,
        address destinationRecipient,
        uint256 nonce
    ) internal returns (bytes32 receiptOp) {
        IGlyphReceiptLedger.OperationTerms memory lt = _ledgerTerms(t, operationType, destinationRecipient, nonce);
        vm.startPrank(payer);
        receiptOp = ledger.registerOperation(lt);
        vm.stopPrank();
        vm.startPrank(writer);
        ledger.appendLocalLeg(
            _leg(receiptOp, ledger.SOURCE_AUTHORIZED(), 110 ether, address(token), payer, address(router), 1)
        );
        ledger.appendLocalLeg(
            _leg(receiptOp, ledger.SOURCE_ESCROWED(), 110 ether, address(token), payer, address(router), 2)
        );
        ledger.appendLocalLeg(
            _leg(
                receiptOp,
                ledger.DESTINATION_DELIVERED(),
                100 ether,
                address(token),
                address(vault),
                destinationRecipient,
                3
            )
        );
        ledger.appendLocalLeg(
            _leg(receiptOp, ledger.PROVIDER_SETTLED(), 100 ether, address(token), address(router), provider, 4)
        );
        ledger.appendLocalLeg(
            _leg(receiptOp, ledger.FEE_REALIZED(), 10 ether, address(token), address(router), address(0x9002), 5)
        );
        ledger.appendLocalLeg(_leg(receiptOp, ledger.DELTA_RETURNED(), 0, address(token), address(router), recovery, 6));
        ledger.appendLocalLeg(
            _leg(receiptOp, ledger.SOURCE_FINALIZED(), 0, address(token), address(router), address(0), 7)
        );
        ledger.advanceStatus(receiptOp, IGlyphReceiptLedger.OperationStatus.SOURCE_AUTHORIZED);
        ledger.advanceStatus(receiptOp, IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED);
        ledger.advanceStatus(receiptOp, IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING);
        ledger.advanceStatus(receiptOp, IGlyphReceiptLedger.OperationStatus.DESTINATION_SETTLED);
        ledger.advanceStatus(receiptOp, IGlyphReceiptLedger.OperationStatus.SOURCE_FINALIZED);
        ledger.reconcile(receiptOp, _receipt(receiptOp));
        vm.stopPrank();
    }

    function _claimSig(bytes32 op, bytes32 nullifier, uint64 deadline) internal view returns (bytes memory sig) {
        bytes32 digest = keccak256(
            abi.encode(
                "GLYPH_CLAIM_INTENT_V1", block.chainid, address(vault), op, claimant, 100 ether, nullifier, deadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimantPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _gateSig(bytes32 op, bytes32 nullifier, uint64 deadline) internal view returns (bytes memory sig) {
        bytes32 digest = keccak256(
            abi.encode(
                "GLYPH_CLAIM_AUTH_V1",
                block.chainid,
                address(vault),
                op,
                claimant,
                address(token),
                100 ether,
                nullifier,
                deadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(gatekeeperPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function test_localPullSameChainFullLifecycleBalancesAndReceipt() public {
        SourceDeltaRouter.Terms memory t = _terms(router.PULL(), 0, recipient);
        vm.prank(payer);
        bytes32 op = router.escrow(t);

        bytes32 route = keccak256("pull-local-route");
        bytes32 ack = keccak256("pull-local-ack");
        bytes32 termsHash = router.hashTerms(t);
        vm.startPrank(app);
        router.recordRouteFromAdapter(op, route, 1, termsHash, address(messenger));
        vault.reservePull(
            op, provider, address(token), recipient, 100 ether, t.sourceChainId, address(router), t.expiry
        );
        vault.deliverPull(op, t.sourceChainId, address(router));
        router.recordDestinationDeliveryFromAdapter(
            op, ack, route, 1, termsHash, recipient, provider, address(token), 100 ether, address(messenger)
        );
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), 100 ether);
        router.finalize(op);
        assertEq(token.balanceOf(provider), 10_000 ether - 2_000 ether + 102 ether);
        assertEq(token.balanceOf(protocol), 1 ether);
        assertEq(token.balanceOf(referrer), 3 ether);
        assertEq(token.balanceOf(sponsor), 4 ether);
        assertEq(token.balanceOf(address(router)), 0);
        (,,,,,, SourceDeltaRouter.Status status) = router.sourceReceiptFacts(op);
        assertEq(uint256(status), uint256(SourceDeltaRouter.Status.RECONCILED));

        bytes32 receiptOp = _registerReceipt(t, keccak256("glyph.operation.pull.v1"), recipient, 0);
        assertEq(
            uint256(ledger.getOperation(receiptOp).status), uint256(IGlyphReceiptLedger.OperationStatus.RECONCILED)
        );
        IGlyphReceiptLedger.DeltaReconciliation memory stored = ledger.getReconciliation(receiptOp);
        assertEq(stored.maximumInput, 110 ether);
        assertEq(stored.realizedPrincipal, 100 ether);
        assertEq(stored.realizedFees, 10 ether);
        assertEq(stored.actualDestinationDelivered, 100 ether);
    }

    function test_localPushSameChainFullLifecycleBalancesAndReceipt() public {
        SourceDeltaRouter.Terms memory t = _terms(router.PUSH(), 0, recipient);
        vm.prank(payer);
        bytes32 op = router.escrow(t);

        bytes32 route = keccak256("push-local-route");
        bytes32 termsHash = router.hashTerms(t);
        vm.startPrank(app);
        router.recordRouteFromAdapter(op, route, 1, termsHash, address(messenger));
        vault.reservePush(
            op, provider, address(token), recipient, 100 ether, t.sourceChainId, address(router), t.expiry, gatekeeper
        );
        router.recordDestinationReservedFromAdapter(
            op, keccak256("reserve"), route, 1, termsHash, provider, address(messenger)
        );
        vm.stopPrank();

        bytes32 nullifier = keccak256("claim-local-push-1");
        uint64 deadline = uint64(block.timestamp + 1 hours);
        vault.claimPush(
            op, claimant, nullifier, deadline, _claimSig(op, nullifier, deadline), _gateSig(op, nullifier, deadline)
        );
        vm.prank(app);
        router.recordDestinationDeliveryFromAdapter(
            op,
            keccak256("push-delivered"),
            route,
            1,
            termsHash,
            claimant,
            provider,
            address(token),
            100 ether,
            address(messenger)
        );

        assertEq(token.balanceOf(claimant), 100 ether);
        router.finalize(op);
        assertEq(token.balanceOf(provider), 10_000 ether - 2_000 ether + 102 ether);
        assertEq(token.balanceOf(protocol), 1 ether);
        assertEq(token.balanceOf(referrer), 3 ether);
        assertEq(token.balanceOf(sponsor), 4 ether);
        assertEq(token.balanceOf(address(router)), 0);
        assertTrue(vault.nullifierUsed(nullifier));
        (,,,,,, SourceDeltaRouter.Status status) = router.sourceReceiptFacts(op);
        assertEq(uint256(status), uint256(SourceDeltaRouter.Status.RECONCILED));

        bytes32 receiptOp = _registerReceipt(t, keccak256("glyph.operation.push.v1"), claimant, 0);
        assertEq(
            uint256(ledger.getOperation(receiptOp).status), uint256(IGlyphReceiptLedger.OperationStatus.RECONCILED)
        );
        IGlyphReceiptLedger.DeltaReconciliation memory stored = ledger.getReconciliation(receiptOp);
        assertEq(stored.maximumInput, 110 ether);
        assertEq(stored.realizedPrincipal, 100 ether);
        assertEq(stored.realizedFees, 10 ether);
        assertEq(stored.actualDestinationDelivered, 100 ether);
    }
}
