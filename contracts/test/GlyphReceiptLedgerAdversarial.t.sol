// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Gate 1 adversarial closure for P1-R3-001 (ledger accounting/authority branches).
// Adds isolated, branch-reaching evidence for review3's ledger gaps.
import {Test} from "forge-std/Test.sol";
import {GlyphReceiptLedger} from "../src/GlyphReceiptLedger.sol";
import {IGlyphReceiptLedger} from "../src/interfaces/IGlyphReceiptLedger.sol";

contract GlyphReceiptLedgerAdversarialTest is Test {
    GlyphReceiptLedger ledger;

    address admin = address(this);
    address initiator = address(0x1001);
    address payer = address(0x1002);
    address recipient = address(0x1003);
    address recovery = address(0x1004);
    address router = address(0x1005);
    address vault = address(0x1006);
    address sourceAsset = address(0x2001);
    address destinationAsset = address(0x2002);
    address writer = address(0x3001);
    bytes32 purpose = keccak256("glyph.purpose.bill.v1");

    function setUp() public {
        ledger = new GlyphReceiptLedger(admin);
        ledger.configureWriterAuthorization(writer, true, ledger.STATUS_WRITER());
        ledger.configureWriterAuthorization(writer, true, ledger.LOCAL_LEG_WRITER());
        ledger.configureWriterAuthorization(writer, true, ledger.REMOTE_LEG_WRITER());
        ledger.configureWriterAuthorization(writer, true, ledger.SOURCE_FINALIZATION_WRITER());
    }

    function _terms(uint256 nonce) internal view returns (IGlyphReceiptLedger.OperationTerms memory t) {
        t = IGlyphReceiptLedger.OperationTerms({
            operationType: keccak256("glyph.operation.pull.v1"),
            proposedPurposeCode: purpose,
            initiator: initiator,
            payer: payer,
            recipient: recipient,
            recoveryAddress: recovery,
            sourceRouter: router,
            destinationVault: vault,
            sourceChainId: uint64(block.chainid),
            destinationChainId: 84532,
            sourceAsset: sourceAsset,
            destinationAsset: destinationAsset,
            maximumInput: 110,
            destinationAmount: 100,
            maximumFee: 10,
            claimantRule: keccak256("glyph.claimant.exact-recipient.v1"),
            privateContextHash: keccak256("context"),
            expiry: uint64(block.timestamp + 1 days),
            nonce: nonce
        });
    }

    function _register(uint256 nonce) internal returns (bytes32 operationId) {
        vm.prank(initiator);
        operationId = ledger.registerOperation(_terms(nonce));
    }

    function _localLeg(
        bytes32 op,
        bytes32 legType,
        uint256 amount,
        address asset,
        address from,
        address to,
        uint32 logIndex
    ) internal view returns (IGlyphReceiptLedger.ValueLegInput memory l) {
        l = IGlyphReceiptLedger.ValueLegInput({
            operationId: op,
            chainId: uint64(block.chainid),
            transactionHash: keccak256(abi.encode(op, legType, logIndex)),
            logIndex: logIndex,
            asset: asset,
            from: from,
            to: to,
            amount: amount,
            legType: legType,
            proofKind: IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED,
            proofReference: keccak256("proof")
        });
    }

    function _remote(
        bytes32 op,
        bytes32 legType,
        uint256 amount,
        address asset,
        address from,
        address to,
        uint32 logIndex
    ) internal view returns (IGlyphReceiptLedger.ValueLegInput memory l) {
        l = _localLeg(op, legType, amount, asset, from, to, logIndex);
        l.chainId = 84532;
        l.proofKind = IGlyphReceiptLedger.ProofKind.AUTHENTICATED_ADAPTER;
    }

    function _sourceFinalizeTx(bytes32 op) internal view returns (bytes32) {
        return keccak256(abi.encode(op, keccak256("glyph.leg.source-finalized.v1"), uint32(7)));
    }

    function _delta(bytes32 op, uint256 principal, uint256 fee, uint256 residual)
        internal
        view
        returns (IGlyphReceiptLedger.DeltaReconciliation memory)
    {
        return IGlyphReceiptLedger.DeltaReconciliation({
            sourceAsset: sourceAsset,
            maximumInput: 110,
            realizedPrincipal: principal,
            realizedFees: fee,
            residualReturned: residual,
            recoveryAddress: recovery,
            sourceFinalizeTx: _sourceFinalizeTx(op),
            expectedDestinationAmount: 100,
            actualDestinationDelivered: 100,
            excessDestinationDelivered: 0,
            destinationExcessPolicy: keccak256("glyph.destination.excess.recipient-retains.v1")
        });
    }

    function _appendAllAndFinalize(bytes32 op, uint256 principal, uint256 fee, uint256 residual) internal {
        vm.startPrank(writer);
        ledger.appendLocalLeg(_localLeg(op, ledger.SOURCE_AUTHORIZED(), 110, sourceAsset, payer, router, 1));
        ledger.appendLocalLeg(_localLeg(op, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 2));
        ledger.appendRemoteLeg(
            _remote(op, ledger.DESTINATION_DELIVERED(), 100, destinationAsset, vault, recipient, 3),
            keccak256(abi.encode("del", op))
        );
        ledger.appendLocalLeg(
            _localLeg(op, ledger.PROVIDER_SETTLED(), principal, sourceAsset, router, address(0x9001), 4)
        );
        ledger.appendLocalLeg(_localLeg(op, ledger.FEE_REALIZED(), fee, sourceAsset, router, address(0x9002), 5));
        ledger.appendLocalLeg(_localLeg(op, ledger.DELTA_RETURNED(), residual, sourceAsset, router, recovery, 6));
        ledger.appendLocalLeg(_localLeg(op, ledger.SOURCE_FINALIZED(), 0, sourceAsset, router, address(0), 7));
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_AUTHORIZED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.DESTINATION_SETTLED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_FINALIZED);
        vm.stopPrank();
    }

    function _advanceToRoutePending(bytes32 op) internal {
        vm.startPrank(writer);
        ledger.appendLocalLeg(_localLeg(op, ledger.SOURCE_AUTHORIZED(), 110, sourceAsset, payer, router, 1));
        ledger.appendLocalLeg(_localLeg(op, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 2));
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_AUTHORIZED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING);
        vm.stopPrank();
    }

    function test_termsHashChangesWhenEachLockedFieldMutates() public {
        IGlyphReceiptLedger.OperationTerms memory base = _terms(1);
        bytes32 h = ledger.computeTermsHash(base);
        bytes32 id = ledger.computeOperationId(base);
        IGlyphReceiptLedger.OperationTerms memory m;

        m = base;
        m.operationType = keccak256("glyph.operation.push.v1");
        _assertChanged(m, h, id);
        m = base;
        m.proposedPurposeCode = keccak256("glyph.purpose.other.v1");
        _assertChanged(m, h, id);
        m = base;
        m.initiator = address(0xAAAA);
        _assertChanged(m, h, id);
        m = base;
        m.payer = address(0xBBBB);
        _assertChanged(m, h, id);
        m = base;
        m.recipient = address(0xCCCC);
        _assertChanged(m, h, id);
        m = base;
        m.recoveryAddress = address(0xDDDD);
        _assertChanged(m, h, id);
        m = base;
        m.sourceRouter = address(0xEEEE);
        _assertChanged(m, h, id);
        m = base;
        m.destinationVault = address(0xFFFF);
        _assertChanged(m, h, id);
        m = base;
        m.sourceChainId = 999;
        _assertChanged(m, h, id);
        m = base;
        m.destinationChainId = 42161;
        _assertChanged(m, h, id);
        m = base;
        m.sourceAsset = address(0x3201);
        _assertChanged(m, h, id);
        m = base;
        m.destinationAsset = address(0x3202);
        _assertChanged(m, h, id);
        m = base;
        m.maximumInput = 220;
        _assertChanged(m, h, id);
        m = base;
        m.destinationAmount = 200;
        _assertChanged(m, h, id);
        m = base;
        m.maximumFee = 9;
        _assertChanged(m, h, id);
        m = base;
        m.claimantRule = keccak256("glyph.claimant.other.v1");
        _assertChanged(m, h, id);
        m = base;
        m.privateContextHash = keccak256("other-context");
        _assertChanged(m, h, id);
        m = base;
        m.expiry = uint64(block.timestamp + 2 days);
        _assertChanged(m, h, id);
        m = base;
        m.nonce = 2;
        _assertChanged(m, h, id);
    }

    function _assertChanged(IGlyphReceiptLedger.OperationTerms memory m, bytes32 h, bytes32 id) internal view {
        assertTrue(ledger.computeTermsHash(m) != h, "mutated termsHash must differ");
        assertTrue(ledger.computeOperationId(m) != id, "mutated operationId must differ");
    }

    function test_unauthorizedConfigureWriterAndAdminFinancialWriteReverts() public {
        bytes32 statusRole = ledger.STATUS_WRITER();
        bytes32 localRole = ledger.LOCAL_LEG_WRITER();
        bytes32 sourceAuthorized = ledger.SOURCE_AUTHORIZED();
        vm.prank(address(0xDEAD));
        vm.expectRevert(abi.encodeWithSelector(IGlyphReceiptLedger.UnauthorizedAdmin.selector, address(0xDEAD)));
        ledger.configureWriterAuthorization(writer, true, statusRole);

        bytes32 op = _register(1);
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.UnauthorizedFinancialWriter.selector, admin, localRole)
        );
        ledger.appendLocalLeg(_localLeg(op, sourceAuthorized, 110, sourceAsset, payer, router, 1));
    }

    function test_terminalReentryAfterReconciledAndAfterRefunded() public {
        bytes32 op = _register(1);
        _appendAllAndFinalize(op, 100, 10, 0);
        vm.prank(writer);
        ledger.reconcile(op, _delta(op, 100, 10, 0));

        vm.startPrank(writer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGlyphReceiptLedger.TerminalOperation.selector, op, IGlyphReceiptLedger.OperationStatus.RECONCILED
            )
        );
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.REGISTERED);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGlyphReceiptLedger.TerminalOperation.selector, op, IGlyphReceiptLedger.OperationStatus.RECONCILED
            )
        );
        ledger.recordRefund(
            op,
            IGlyphReceiptLedger.RefundReceipt(
                sourceAsset, recovery, 110, keccak256("r"), IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IGlyphReceiptLedger.TerminalOperation.selector, op, IGlyphReceiptLedger.OperationStatus.RECONCILED
            )
        );
        ledger.reconcile(op, _delta(op, 100, 10, 0));
        vm.stopPrank();

        bytes32 rOp = _register(2);
        vm.startPrank(writer);
        ledger.appendLocalLeg(_localLeg(rOp, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 1));
        ledger.appendLocalLeg(_localLeg(rOp, ledger.FULL_REFUND(), 110, sourceAsset, router, recovery, 2));
        vm.warp(_terms(2).expiry);
        ledger.advanceStatus(rOp, IGlyphReceiptLedger.OperationStatus.EXPIRED);
        ledger.advanceStatus(rOp, IGlyphReceiptLedger.OperationStatus.REFUND_PENDING);
        ledger.recordRefund(
            rOp,
            IGlyphReceiptLedger.RefundReceipt(
                sourceAsset,
                recovery,
                110,
                keccak256(abi.encode(rOp, ledger.FULL_REFUND(), uint32(2))),
                IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IGlyphReceiptLedger.TerminalOperation.selector, rOp, IGlyphReceiptLedger.OperationStatus.REFUNDED
            )
        );
        ledger.advanceStatus(rOp, IGlyphReceiptLedger.OperationStatus.REGISTERED);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGlyphReceiptLedger.TerminalOperation.selector, rOp, IGlyphReceiptLedger.OperationStatus.REFUNDED
            )
        );
        ledger.reconcile(rOp, _delta(rOp, 100, 10, 0));
        vm.stopPrank();
    }

    function test_reconcileRejectsEveryMissingLegBeforeConservation() public {
        bytes32 op = _register(1);
        _advanceToRoutePending(op);
        vm.startPrank(writer);
        ledger.appendRemoteLeg(
            _remote(op, ledger.DESTINATION_DELIVERED(), 100, destinationAsset, vault, recipient, 3),
            keccak256("delivered")
        );
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.DESTINATION_SETTLED);
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.MissingRequiredReceipt.selector, op, ledger.SOURCE_FINALIZED())
        );
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_FINALIZED);
        ledger.appendLocalLeg(_localLeg(op, ledger.SOURCE_FINALIZED(), 0, sourceAsset, router, address(0), 7));
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_FINALIZED);
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.MissingRequiredReceipt.selector, op, ledger.PROVIDER_SETTLED())
        );
        ledger.reconcile(op, _delta(op, 100, 10, 0));
        vm.stopPrank();
    }

    function test_reconcileHugeValueCasesReachConservationGuard() public {
        bytes32 pTooBig = _register(1);
        _appendAllAndFinalize(pTooBig, 111, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.InvalidConservationEquation.selector, 110, 111, 0, 0)
        );
        vm.prank(writer);
        ledger.reconcile(pTooBig, _delta(pTooBig, 111, 0, 0));

        bytes32 feeTooBigForRemaining = _register(2);
        _appendAllAndFinalize(feeTooBigForRemaining, 105, 6, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.InvalidConservationEquation.selector, 110, 105, 6, 0)
        );
        vm.prank(writer);
        ledger.reconcile(feeTooBigForRemaining, _delta(feeTooBigForRemaining, 105, 6, 0));

        bytes32 residualMismatch = _register(3);
        _appendAllAndFinalize(residualMismatch, 100, 9, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.InvalidConservationEquation.selector, 110, 100, 9, 0)
        );
        vm.prank(writer);
        ledger.reconcile(residualMismatch, _delta(residualMismatch, 100, 9, 0));
    }

    function test_destinationDeliveryWrongChainAssetRecipientAmountRejectsAtTransition() public {
        bytes32 wrongRecipient = _register(1);
        _advanceToRoutePending(wrongRecipient);
        vm.startPrank(writer);
        ledger.appendRemoteLeg(
            _remote(wrongRecipient, ledger.DESTINATION_DELIVERED(), 100, destinationAsset, vault, address(0xBEEF), 3),
            keccak256("wrong-recipient")
        );
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.RecipientMismatch.selector, recipient, address(0xBEEF))
        );
        ledger.advanceStatus(wrongRecipient, IGlyphReceiptLedger.OperationStatus.DESTINATION_SETTLED);
        vm.stopPrank();

        bytes32 wrongAsset = _register(2);
        _advanceToRoutePending(wrongAsset);
        vm.startPrank(writer);
        ledger.appendRemoteLeg(
            _remote(wrongAsset, ledger.DESTINATION_DELIVERED(), 100, sourceAsset, vault, recipient, 3),
            keccak256("wrong-asset")
        );
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.AssetMismatch.selector, destinationAsset, sourceAsset)
        );
        ledger.advanceStatus(wrongAsset, IGlyphReceiptLedger.OperationStatus.DESTINATION_SETTLED);
        vm.stopPrank();

        bytes32 wrongAmount = _register(3);
        _advanceToRoutePending(wrongAmount);
        vm.startPrank(writer);
        ledger.appendRemoteLeg(
            _remote(wrongAmount, ledger.DESTINATION_DELIVERED(), 50, destinationAsset, vault, recipient, 3),
            keccak256("wrong-amount")
        );
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.AmountMismatch.selector, ledger.DESTINATION_DELIVERED(), 100, 50)
        );
        ledger.advanceStatus(wrongAmount, IGlyphReceiptLedger.OperationStatus.DESTINATION_SETTLED);
        vm.stopPrank();
    }

    function test_refundRejectsMismatchedFieldsAndProofKind() public {
        bytes32 op = _register(1);
        vm.startPrank(writer);
        ledger.appendLocalLeg(_localLeg(op, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 1));
        ledger.appendLocalLeg(_localLeg(op, ledger.FULL_REFUND(), 110, sourceAsset, router, recovery, 2));
        vm.warp(_terms(1).expiry);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.EXPIRED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.REFUND_PENDING);
        bytes32 refundTx = keccak256(abi.encode(op, ledger.FULL_REFUND(), uint32(2)));
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.RecoveryAddressMismatch.selector, recovery, recipient)
        );
        ledger.recordRefund(
            op,
            IGlyphReceiptLedger.RefundReceipt(
                sourceAsset, recipient, 110, refundTx, IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.AssetMismatch.selector, sourceAsset, destinationAsset)
        );
        ledger.recordRefund(
            op,
            IGlyphReceiptLedger.RefundReceipt(
                destinationAsset, recovery, 110, refundTx, IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IGlyphReceiptLedger.AmountMismatch.selector, bytes32("refund"), uint256(110), uint256(109)
            )
        );
        ledger.recordRefund(
            op,
            IGlyphReceiptLedger.RefundReceipt(
                sourceAsset, recovery, 109, refundTx, IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED
            )
        );
        vm.expectRevert(abi.encodeWithSelector(IGlyphReceiptLedger.InvalidLeg.selector, bytes32("refundTx")));
        ledger.recordRefund(
            op,
            IGlyphReceiptLedger.RefundReceipt(
                sourceAsset, recovery, 110, keccak256("bad"), IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IGlyphReceiptLedger.UnsupportedProofKind.selector, IGlyphReceiptLedger.ProofKind.NONE
            )
        );
        ledger.recordRefund(
            op,
            IGlyphReceiptLedger.RefundReceipt(sourceAsset, recovery, 110, refundTx, IGlyphReceiptLedger.ProofKind.NONE)
        );
        ledger.recordRefund(
            op,
            IGlyphReceiptLedger.RefundReceipt(
                sourceAsset, recovery, 110, refundTx, IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED
            )
        );
        vm.stopPrank();
        assertEq(uint256(ledger.getOperation(op).status), uint256(IGlyphReceiptLedger.OperationStatus.REFUNDED));
    }
}
