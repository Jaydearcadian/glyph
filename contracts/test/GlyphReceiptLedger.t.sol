// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GlyphReceiptLedger} from "../src/GlyphReceiptLedger.sol";
import {IGlyphReceiptLedger} from "../src/interfaces/IGlyphReceiptLedger.sol";

contract GlyphReceiptLedgerTest is Test {
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
            privateContextHash: keccak256("context commitment"),
            expiry: uint64(block.timestamp + 1 days),
            nonce: nonce
        });
    }

    function _register(uint256 nonce) internal returns (bytes32 operationId) {
        vm.prank(initiator);
        operationId = ledger.registerOperation(_terms(nonce));
    }

    function _leg(bytes32 op, bytes32 legType, uint256 amount, address asset, address from, address to, uint32 logIndex)
        internal
        view
        returns (IGlyphReceiptLedger.ValueLegInput memory l)
    {
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

    function _appendRequired(bytes32 op, uint256 fee, uint256 residual) internal {
        vm.startPrank(writer);
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_AUTHORIZED(), 110, sourceAsset, payer, router, 1));
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 2));
        ledger.appendRemoteLeg(
            _remote(op, ledger.DESTINATION_DELIVERED(), 100, destinationAsset, vault, recipient, 3),
            keccak256(abi.encode("msg-delivered", op))
        );
        ledger.appendLocalLeg(_leg(op, ledger.PROVIDER_SETTLED(), 100, sourceAsset, router, address(0x9001), 4));
        ledger.appendLocalLeg(_leg(op, ledger.FEE_REALIZED(), fee, sourceAsset, router, address(0x9002), 5));
        ledger.appendLocalLeg(_leg(op, ledger.DELTA_RETURNED(), residual, sourceAsset, router, recovery, 6));
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_FINALIZED(), 0, sourceAsset, router, address(0), 7));
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_AUTHORIZED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.DESTINATION_SETTLED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_FINALIZED);
        vm.stopPrank();
    }

    function _sourceFinalizeTx(bytes32 op) internal pure returns (bytes32) {
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

    function _refundTx(bytes32 op) internal pure returns (bytes32) {
        return keccak256(abi.encode(op, keccak256("glyph.leg.full-refund.v1"), uint32(2)));
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
        l = _leg(op, legType, amount, asset, from, to, logIndex);
        l.chainId = 84532;
        l.proofKind = IGlyphReceiptLedger.ProofKind.AUTHENTICATED_ADAPTER;
    }

    function test_registerOperation_usesDeterministicDomainTermsAndRejectsDuplicates() public {
        IGlyphReceiptLedger.OperationTerms memory t = _terms(1);
        bytes32 expectedTermsHash = ledger.computeTermsHash(t);
        bytes32 expectedId = ledger.computeOperationId(t);
        vm.prank(initiator);
        bytes32 op = ledger.registerOperation(t);
        assertEq(op, expectedId);
        assertEq(ledger.getOperation(op).termsHash, expectedTermsHash);
        assertEq(ledger.operationParties(op).payer, payer);
        vm.prank(initiator);
        vm.expectRevert(abi.encodeWithSelector(IGlyphReceiptLedger.DuplicateOperationId.selector, op));
        ledger.registerOperation(t);
    }

    function test_registerOperation_rejectsNonInitiator() public {
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(IGlyphReceiptLedger.UnauthorizedInitiator.selector, payer, initiator));
        ledger.registerOperation(_terms(1));
    }

    function test_rolesAreNarrowAndAdminCannotBypassFinancialWriterChecks() public {
        bytes32 op = _register(1);
        bytes32 localRole = ledger.LOCAL_LEG_WRITER();
        bytes32 statusRole = ledger.STATUS_WRITER();
        bytes32 escrowed = ledger.SOURCE_ESCROWED();
        vm.prank(address(0xDEAD));
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.UnauthorizedFinancialWriter.selector, address(0xDEAD), localRole)
        );
        ledger.appendLocalLeg(_leg(op, escrowed, 110, sourceAsset, payer, router, 1));
        vm.prank(address(0xBADD));
        vm.expectRevert(
            abi.encodeWithSelector(
                IGlyphReceiptLedger.UnauthorizedFinancialWriter.selector, address(0xBADD), statusRole
            )
        );
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_AUTHORIZED);
    }

    function test_statusTransitionsRejectSkippedTerminalAndTerminalReentry() public {
        bytes32 op = _register(1);
        vm.startPrank(writer);
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_AUTHORIZED(), 110, sourceAsset, payer, router, 1));
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 2));
        ledger.appendRemoteLeg(
            _remote(op, ledger.DESTINATION_DELIVERED(), 100, destinationAsset, vault, recipient, 3), keccak256("sm-msg")
        );
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_FINALIZED(), 0, sourceAsset, router, address(0), 7));
        vm.expectRevert();
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_AUTHORIZED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.DESTINATION_SETTLED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_FINALIZED);
        vm.expectRevert();
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.RECONCILED);
        vm.stopPrank();
    }

    function test_legProofKindsMessageIdsAndIdsFailClosed() public {
        bytes32 op = _register(1);
        IGlyphReceiptLedger.ValueLegInput memory local =
            _leg(op, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 1);
        bytes32 expectedLegId =
            keccak256(abi.encode(op, local.chainId, local.transactionHash, local.logIndex, local.legType));
        vm.startPrank(writer);
        assertEq(ledger.appendLocalLeg(local), expectedLegId);
        vm.expectRevert(abi.encodeWithSelector(IGlyphReceiptLedger.DuplicateLegType.selector, op, local.legType));
        ledger.appendLocalLeg(local);
        bytes32 feeRealized = ledger.FEE_REALIZED();
        IGlyphReceiptLedger.ValueLegInput memory wrongLocalProof =
            _leg(op, feeRealized, 1, sourceAsset, payer, router, 9);
        wrongLocalProof.proofKind = IGlyphReceiptLedger.ProofKind.AUTHENTICATED_ADAPTER;
        vm.expectRevert();
        ledger.appendLocalLeg(wrongLocalProof);
        IGlyphReceiptLedger.ValueLegInput memory badRemote =
            _remote(op, ledger.DESTINATION_DELIVERED(), 100, destinationAsset, vault, recipient, 2);
        vm.expectRevert(IGlyphReceiptLedger.ZeroMessageId.selector);
        ledger.appendRemoteLeg(badRemote, bytes32(0));
        badRemote.proofKind = IGlyphReceiptLedger.ProofKind.LIGHT_CLIENT_VERIFIED;
        ledger.appendRemoteLeg(badRemote, keccak256("m1"));
        bytes32 destinationReserved = ledger.DESTINATION_RESERVED();
        vm.expectRevert(abi.encodeWithSelector(IGlyphReceiptLedger.DuplicateMessageId.selector, keccak256("m1")));
        ledger.appendRemoteLeg(
            _remote(op, destinationReserved, 100, destinationAsset, vault, recipient, 3), keccak256("m1")
        );
        vm.stopPrank();
    }

    function test_reconcile_conservesZeroMinimalAndNonzeroResiduals() public {
        (uint256[3] memory fees, uint256[3] memory residuals) = ([uint256(10), 9, 1], [uint256(0), 1, 9]);
        for (uint256 i; i < 3; i++) {
            bytes32 op = _register(i + 1);
            _appendRequired(op, fees[i], residuals[i]);
            vm.prank(writer);
            ledger.reconcile(op, _delta(op, 100, fees[i], residuals[i]));
            assertEq(uint256(ledger.getOperation(op).status), uint256(IGlyphReceiptLedger.OperationStatus.RECONCILED));
        }
    }

    function test_reconcileRejectsMissingMismatchedOverflowAndSecondTerminalOutcome() public {
        bytes32 op = _register(1);
        _appendRequired(op, 10, 0);
        vm.startPrank(writer);
        vm.expectRevert();
        IGlyphReceiptLedger.DeltaReconciliation memory badHuge = _delta(op, type(uint256).max, 1, 0);
        badHuge.sourceFinalizeTx = keccak256("bad");
        ledger.reconcile(op, badHuge);
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.RecoveryAddressMismatch.selector, recovery, recipient)
        );
        IGlyphReceiptLedger.DeltaReconciliation memory badRecovery = _delta(op, 100, 10, 0);
        badRecovery.recoveryAddress = recipient;
        badRecovery.sourceFinalizeTx = keccak256("bad2");
        ledger.reconcile(op, badRecovery);
        ledger.reconcile(op, _delta(op, 100, 10, 0));
        vm.expectRevert();
        ledger.recordRefund(
            op,
            IGlyphReceiptLedger.RefundReceipt(
                sourceAsset, recovery, 110, keccak256("refund"), IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED
            )
        );
        vm.stopPrank();
    }

    function test_refundRequiresRefundPendingAndMatchingFullRefund() public {
        bytes32 op = _register(1);
        vm.startPrank(writer);
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 1));
        ledger.appendLocalLeg(_leg(op, ledger.FULL_REFUND(), 110, sourceAsset, router, recovery, 2));
        vm.warp(_terms(1).expiry);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.EXPIRED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.REFUND_PENDING);
        ledger.recordRefund(
            op,
            IGlyphReceiptLedger.RefundReceipt(
                sourceAsset, recovery, 110, _refundTx(op), IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED
            )
        );
        vm.expectRevert();
        ledger.recordRefund(
            op,
            IGlyphReceiptLedger.RefundReceipt(
                sourceAsset, recovery, 110, keccak256("refund2"), IGlyphReceiptLedger.ProofKind.LOCAL_VERIFIED
            )
        );
        vm.stopPrank();
    }

    function test_forbiddenDirectRefundShortcutsRevertAndExpiredOrRouteFailedPathsReachRefundPending() public {
        IGlyphReceiptLedger.OperationStatus[5] memory fromStates = [
            IGlyphReceiptLedger.OperationStatus.REGISTERED,
            IGlyphReceiptLedger.OperationStatus.SOURCE_AUTHORIZED,
            IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED,
            IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING,
            IGlyphReceiptLedger.OperationStatus.DESTINATION_RESERVED
        ];
        for (uint256 i; i < fromStates.length; i++) {
            bytes32 op = _register(100 + i);
            vm.startPrank(writer);
            if (fromStates[i] != IGlyphReceiptLedger.OperationStatus.REGISTERED) {
                ledger.appendLocalLeg(_leg(op, ledger.SOURCE_AUTHORIZED(), 110, sourceAsset, payer, router, 1));
                ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_AUTHORIZED);
            }
            if (
                fromStates[i] == IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED
                    || fromStates[i] == IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING
                    || fromStates[i] == IGlyphReceiptLedger.OperationStatus.DESTINATION_RESERVED
            ) {
                ledger.appendLocalLeg(_leg(op, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 2));
                ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED);
            }
            if (
                fromStates[i] == IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING
                    || fromStates[i] == IGlyphReceiptLedger.OperationStatus.DESTINATION_RESERVED
            ) {
                ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING);
            }
            if (fromStates[i] == IGlyphReceiptLedger.OperationStatus.DESTINATION_RESERVED) {
                ledger.appendRemoteLeg(
                    _remote(op, ledger.DESTINATION_RESERVED(), 100, destinationAsset, vault, recipient, 3),
                    keccak256(abi.encode("reserve", i))
                );
                ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.DESTINATION_RESERVED);
            }
            vm.expectRevert();
            ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.REFUND_PENDING);
            vm.warp(_terms(100 + i).expiry);
            ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.EXPIRED);
            if (fromStates[i] == IGlyphReceiptLedger.OperationStatus.DESTINATION_RESERVED) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IGlyphReceiptLedger.UnsafeRefundEvidence.selector, op, ledger.DESTINATION_RESERVED()
                    )
                );
                ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.REFUND_PENDING);
            } else {
                ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.REFUND_PENDING);
            }
            vm.stopPrank();
        }

        bytes32 failed = _register(999);
        vm.startPrank(writer);
        ledger.advanceStatus(failed, IGlyphReceiptLedger.OperationStatus.ROUTE_FAILED);
        ledger.advanceStatus(failed, IGlyphReceiptLedger.OperationStatus.REFUND_PENDING);
        vm.stopPrank();
    }

    function test_reconcileRejectsMissingSourceFinalizedWrongDestinationChainWrongRouterAndFinalizeTxMismatch() public {
        bytes32 op = _register(1);
        vm.startPrank(writer);
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_AUTHORIZED(), 110, sourceAsset, payer, router, 1));
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 2));
        ledger.appendRemoteLeg(
            _remote(op, ledger.DESTINATION_DELIVERED(), 100, destinationAsset, vault, recipient, 3), keccak256("m-del")
        );
        ledger.appendLocalLeg(_leg(op, ledger.PROVIDER_SETTLED(), 100, sourceAsset, router, address(0x9001), 4));
        ledger.appendLocalLeg(_leg(op, ledger.FEE_REALIZED(), 10, sourceAsset, router, address(0x9002), 5));
        ledger.appendLocalLeg(_leg(op, ledger.DELTA_RETURNED(), 0, sourceAsset, router, recovery, 6));
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_AUTHORIZED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.DESTINATION_SETTLED);
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.MissingRequiredReceipt.selector, op, ledger.SOURCE_FINALIZED())
        );
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_FINALIZED);
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_FINALIZED(), 0, sourceAsset, router, address(0), 7));
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_FINALIZED);
        vm.expectRevert(abi.encodeWithSelector(IGlyphReceiptLedger.InvalidLeg.selector, bytes32("sourceFinalizeTx")));
        IGlyphReceiptLedger.DeltaReconciliation memory wrongFinal = _delta(op, 100, 10, 0);
        wrongFinal.sourceFinalizeTx = keccak256("wrong-final");
        ledger.reconcile(op, wrongFinal);
        vm.stopPrank();
    }

    function test_duplicateSemanticLegTypeWithDifferentLegIdReverts() public {
        bytes32 op = _register(1);
        vm.startPrank(writer);
        bytes32 legType = ledger.SOURCE_ESCROWED();
        ledger.appendLocalLeg(_leg(op, legType, 110, sourceAsset, payer, router, 1));
        vm.expectRevert(abi.encodeWithSelector(IGlyphReceiptLedger.DuplicateLegType.selector, op, legType));
        ledger.appendLocalLeg(_leg(op, legType, 110, sourceAsset, payer, router, 99));
        vm.stopPrank();
    }

    function test_expiredRequiresImmutableExpiryAndBoundaryAllowsRefundPending() public {
        bytes32 op = _register(77);
        vm.startPrank(writer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGlyphReceiptLedger.OperationNotExpired.selector, op, _terms(77).expiry, block.timestamp
            )
        );
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.EXPIRED);
        vm.warp(_terms(77).expiry);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.EXPIRED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.REFUND_PENDING);
        vm.stopPrank();
    }

    function test_refundRejectsDestinationDeliveredEvidenceBeforeExpiryRegardlessOfStatusOrder() public {
        bytes32 op = _register(78);
        vm.startPrank(writer);
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 1));
        ledger.appendRemoteLeg(
            _remote(op, ledger.DESTINATION_DELIVERED(), 100, destinationAsset, vault, recipient, 3),
            keccak256("del-before-refund")
        );
        ledger.appendLocalLeg(_leg(op, ledger.FULL_REFUND(), 110, sourceAsset, router, recovery, 2));
        vm.warp(_terms(78).expiry);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.EXPIRED);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGlyphReceiptLedger.UnsafeRefundEvidence.selector, op, ledger.DESTINATION_DELIVERED()
            )
        );
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.REFUND_PENDING);
        vm.stopPrank();
    }

    function test_reconcileRejectsUnderDeliveryAndStoresOverDeliveryRecipientRetainsPolicy() public {
        bytes32 under = _register(79);
        vm.startPrank(writer);
        ledger.appendLocalLeg(_leg(under, ledger.SOURCE_AUTHORIZED(), 110, sourceAsset, payer, router, 1));
        ledger.appendLocalLeg(_leg(under, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 2));
        ledger.appendRemoteLeg(
            _remote(under, ledger.DESTINATION_DELIVERED(), 99, destinationAsset, vault, recipient, 3),
            keccak256("under")
        );
        ledger.advanceStatus(under, IGlyphReceiptLedger.OperationStatus.SOURCE_AUTHORIZED);
        ledger.advanceStatus(under, IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED);
        ledger.advanceStatus(under, IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING);
        vm.expectRevert(
            abi.encodeWithSelector(IGlyphReceiptLedger.AmountMismatch.selector, ledger.DESTINATION_DELIVERED(), 100, 99)
        );
        ledger.advanceStatus(under, IGlyphReceiptLedger.OperationStatus.DESTINATION_SETTLED);
        vm.stopPrank();

        bytes32 op = _register(80);
        vm.startPrank(writer);
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_AUTHORIZED(), 110, sourceAsset, payer, router, 1));
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_ESCROWED(), 110, sourceAsset, payer, router, 2));
        ledger.appendRemoteLeg(
            _remote(op, ledger.DESTINATION_DELIVERED(), 105, destinationAsset, vault, recipient, 3), keccak256("over")
        );
        ledger.appendLocalLeg(_leg(op, ledger.PROVIDER_SETTLED(), 100, sourceAsset, router, address(0x9001), 4));
        ledger.appendLocalLeg(_leg(op, ledger.FEE_REALIZED(), 10, sourceAsset, router, address(0x9002), 5));
        ledger.appendLocalLeg(_leg(op, ledger.DELTA_RETURNED(), 0, sourceAsset, router, recovery, 6));
        ledger.appendLocalLeg(_leg(op, ledger.SOURCE_FINALIZED(), 0, sourceAsset, router, address(0), 7));
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_AUTHORIZED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_ESCROWED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.ROUTE_PENDING);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.DESTINATION_SETTLED);
        ledger.advanceStatus(op, IGlyphReceiptLedger.OperationStatus.SOURCE_FINALIZED);
        IGlyphReceiptLedger.DeltaReconciliation memory d = _delta(op, 100, 10, 0);
        d.actualDestinationDelivered = 105;
        d.excessDestinationDelivered = 5;
        ledger.reconcile(op, d);
        vm.stopPrank();
        IGlyphReceiptLedger.DeltaReconciliation memory stored = ledger.getReconciliation(op);
        assertEq(stored.expectedDestinationAmount, 100);
        assertEq(stored.actualDestinationDelivered, 105);
        assertEq(stored.excessDestinationDelivered, 5);
        assertEq(stored.destinationExcessPolicy, keccak256("glyph.destination.excess.recipient-retains.v1"));
    }

    function test_registerOperationAcceptsSourceRemoteDestinationLocalAndSourceLocalDestinationRemoteTopologies()
        public
    {
        IGlyphReceiptLedger.OperationTerms memory remoteSource = _terms(201);
        remoteSource.sourceChainId = 1;
        remoteSource.destinationChainId = uint64(block.chainid);
        vm.prank(initiator);
        bytes32 op = ledger.registerOperation(remoteSource);
        vm.startPrank(writer);
        ledger.appendRemoteLeg(
            _remote(op, ledger.SOURCE_AUTHORIZED(), 110, sourceAsset, payer, router, 1), keccak256("src-remote-auth")
        );
        ledger.appendLocalLeg(_leg(op, ledger.DESTINATION_DELIVERED(), 100, destinationAsset, vault, recipient, 2));
        vm.stopPrank();

        bytes32 localSource = _register(202);
        vm.startPrank(writer);
        ledger.appendLocalLeg(_leg(localSource, ledger.SOURCE_AUTHORIZED(), 110, sourceAsset, payer, router, 1));
        ledger.appendRemoteLeg(
            _remote(localSource, ledger.DESTINATION_DELIVERED(), 100, destinationAsset, vault, recipient, 2),
            keccak256("dst-remote-del")
        );
        vm.stopPrank();
    }
}
