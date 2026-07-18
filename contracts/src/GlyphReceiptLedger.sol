// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGlyphReceiptLedger} from "./interfaces/IGlyphReceiptLedger.sol";

contract GlyphReceiptLedger is IGlyphReceiptLedger {
    bytes32 public constant TERMS_DOMAIN = keccak256("glyph.operation.terms.v1");
    bytes32 public constant OPERATION_DOMAIN = keccak256("glyph.operation.id.v1");
    bytes32 public constant STATUS_WRITER = keccak256("glyph.writer.status.v1");
    bytes32 public constant LOCAL_LEG_WRITER = keccak256("glyph.writer.local-leg.v1");
    bytes32 public constant REMOTE_LEG_WRITER = keccak256("glyph.writer.remote-leg.v1");
    bytes32 public constant SOURCE_FINALIZATION_WRITER = keccak256("glyph.writer.source-finalization.v1");

    bytes32 public constant SOURCE_AUTHORIZED = keccak256("glyph.leg.source-authorized.v1");
    bytes32 public constant SOURCE_ESCROWED = keccak256("glyph.leg.source-escrowed.v1");
    bytes32 public constant DESTINATION_RESERVED = keccak256("glyph.leg.destination-reserved.v1");
    bytes32 public constant DESTINATION_DELIVERED = keccak256("glyph.leg.destination-delivered.v1");
    bytes32 public constant PROVIDER_SETTLED = keccak256("glyph.leg.provider-settled.v1");
    bytes32 public constant FEE_REALIZED = keccak256("glyph.leg.fee-realized.v1");
    bytes32 public constant DELTA_RETURNED = keccak256("glyph.leg.delta-returned.v1");
    bytes32 public constant SOURCE_FINALIZED = keccak256("glyph.leg.source-finalized.v1");
    bytes32 public constant FULL_REFUND = keccak256("glyph.leg.full-refund.v1");
    bytes32 public constant RECIPIENT_RETAINS = keccak256("glyph.destination.excess.recipient-retains.v1");

    address public immutable admin;
    mapping(address => mapping(bytes32 => bool)) public writerAuthorization;
    mapping(bytes32 => OperationRecord) internal operations;
    mapping(bytes32 => OperationTerms) internal termsByOperation;
    mapping(bytes32 => bool) internal operationExists;
    mapping(bytes32 => ValueLeg) internal legs;
    mapping(bytes32 => bool) internal legExists;
    mapping(bytes32 => bool) internal messageUsed;
    mapping(bytes32 => mapping(bytes32 => bytes32)) internal legByType;
    mapping(bytes32 => DeltaReconciliation) internal reconciliations;

    event OperationRegistered(
        bytes32 indexed operationId,
        bytes32 indexed operationType,
        bytes32 indexed proposedPurposeCode,
        address initiator,
        address payer,
        address recipient,
        bytes32 termsHash,
        bytes32 privateContextHash,
        uint64 createdAt,
        uint64 expiry
    );
    event OperationStatusAdvanced(
        bytes32 indexed operationId, OperationStatus previousStatus, OperationStatus nextStatus, address actor
    );
    event ValueLegAppended(
        bytes32 indexed legId,
        bytes32 indexed operationId,
        uint64 chainId,
        bytes32 indexed legType,
        address asset,
        address from,
        address to,
        uint256 amount,
        ProofKind proofKind,
        bytes32 proofReference
    );
    event OperationReconciled(
        bytes32 indexed operationId,
        address sourceAsset,
        uint256 maximumInput,
        uint256 realizedPrincipal,
        uint256 realizedFees,
        uint256 residualReturned,
        address recoveryAddress,
        bytes32 sourceFinalizeTx,
        uint256 expectedDestinationAmount,
        uint256 actualDestinationDelivered,
        uint256 excessDestinationDelivered,
        bytes32 destinationExcessPolicy
    );
    event OperationRefunded(
        bytes32 indexed operationId,
        address sourceAsset,
        address recoveryAddress,
        uint256 amount,
        bytes32 refundTx,
        ProofKind proofKind
    );
    event WriterAuthorizationChanged(
        address indexed writer, bool allowed, bytes32 indexed writerRole, address indexed admin
    );

    constructor(address admin_) {
        if (admin_ == address(0)) revert UnauthorizedAdmin(address(0));
        admin = admin_;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert UnauthorizedAdmin(msg.sender);
        _;
    }
    modifier onlyRole(bytes32 role) {
        if (!writerAuthorization[msg.sender][role]) revert UnauthorizedFinancialWriter(msg.sender, role);
        _;
    }

    function configureWriterAuthorization(address writer, bool allowed, bytes32 writerRole) external onlyAdmin {
        writerAuthorization[writer][writerRole] = allowed;
        emit WriterAuthorizationChanged(writer, allowed, writerRole, msg.sender);
    }

    function hasOperation(bytes32 operationId) external view returns (bool) {
        return operationExists[operationId];
    }

    function getOperation(bytes32 operationId) external view returns (OperationRecord memory) {
        return operations[operationId];
    }

    function getValueLeg(bytes32 legId) external view returns (ValueLeg memory) {
        return legs[legId];
    }

    function getReconciliation(bytes32 operationId) external view returns (DeltaReconciliation memory) {
        return reconciliations[operationId];
    }

    function operationParties(bytes32 operationId) external view returns (OperationParties memory p) {
        OperationTerms storage t = termsByOperation[operationId];
        return OperationParties(t.initiator, t.payer, t.recipient);
    }

    function computeTermsHash(OperationTerms calldata terms) external view returns (bytes32) {
        return _computeTermsHash(terms);
    }

    function computeOperationId(OperationTerms calldata terms) external view returns (bytes32) {
        return _computeOperationId(_computeTermsHash(terms));
    }

    function registerOperation(OperationTerms calldata terms) external returns (bytes32 operationId) {
        _validateTerms(terms);
        if (msg.sender != terms.initiator) revert UnauthorizedInitiator(msg.sender, terms.initiator);
        bytes32 termsHash = _computeTermsHash(terms);
        operationId = _computeOperationId(termsHash);
        if (operationExists[operationId]) revert DuplicateOperationId(operationId);
        operationExists[operationId] = true;
        termsByOperation[operationId] = terms;
        operations[operationId] = OperationRecord(
            operationId,
            terms.operationType,
            terms.proposedPurposeCode,
            terms.initiator,
            terms.payer,
            terms.recipient,
            termsHash,
            terms.privateContextHash,
            uint64(block.timestamp),
            terms.expiry,
            OperationStatus.REGISTERED
        );
        emit OperationRegistered(
            operationId,
            terms.operationType,
            terms.proposedPurposeCode,
            terms.initiator,
            terms.payer,
            terms.recipient,
            termsHash,
            terms.privateContextHash,
            uint64(block.timestamp),
            terms.expiry
        );
    }

    function appendLocalLeg(ValueLegInput calldata leg) external onlyRole(LOCAL_LEG_WRITER) returns (bytes32 legId) {
        if (leg.proofKind != ProofKind.LOCAL_VERIFIED) {
            revert ProofKindMismatch(leg.proofKind, ProofKind.LOCAL_VERIFIED);
        }
        return _appendLeg(leg);
    }

    function appendRemoteLeg(ValueLegInput calldata leg, bytes32 messageId)
        external
        onlyRole(REMOTE_LEG_WRITER)
        returns (bytes32 legId)
    {
        if (messageId == bytes32(0)) revert ZeroMessageId();
        if (messageUsed[messageId]) revert DuplicateMessageId(messageId);
        if (leg.proofKind != ProofKind.AUTHENTICATED_ADAPTER && leg.proofKind != ProofKind.LIGHT_CLIENT_VERIFIED) {
            revert UnsupportedProofKind(leg.proofKind);
        }
        messageUsed[messageId] = true;
        return _appendLeg(leg);
    }

    function advanceStatus(bytes32 operationId, OperationStatus nextStatus) external onlyRole(STATUS_WRITER) {
        _requireOperation(operationId);
        if (
            nextStatus == OperationStatus.RECONCILED || nextStatus == OperationStatus.REFUNDED
                || nextStatus == OperationStatus.NONE
        ) revert InvalidOperationTransition(operationId, operations[operationId].status, nextStatus);
        _advance(operationId, nextStatus);
    }

    function reconcile(bytes32 operationId, DeltaReconciliation calldata delta)
        external
        onlyRole(SOURCE_FINALIZATION_WRITER)
    {
        _requireOperation(operationId);
        if (_isTerminal(operations[operationId].status)) {
            revert TerminalOperation(operationId, operations[operationId].status);
        }
        if (operations[operationId].status != OperationStatus.SOURCE_FINALIZED) {
            revert InvalidOperationTransition(operationId, operations[operationId].status, OperationStatus.RECONCILED);
        }
        OperationTerms storage t = termsByOperation[operationId];
        if (delta.recoveryAddress != t.recoveryAddress) {
            revert RecoveryAddressMismatch(t.recoveryAddress, delta.recoveryAddress);
        }
        if (delta.sourceAsset != t.sourceAsset) revert AssetMismatch(t.sourceAsset, delta.sourceAsset);
        if (delta.maximumInput != t.maximumInput) {
            revert AmountMismatch("maximumInput", t.maximumInput, delta.maximumInput);
        }
        if (delta.realizedFees > t.maximumFee) revert AmountMismatch("maximumFee", t.maximumFee, delta.realizedFees);
        ValueLeg storage escrow = _checkLeg(
            operationId, SOURCE_ESCROWED, t.sourceChainId, t.sourceAsset, t.maximumInput, t.payer, t.sourceRouter
        );
        escrow;
        ValueLeg storage delivered = _checkLegAtLeast(
            operationId,
            DESTINATION_DELIVERED,
            t.destinationChainId,
            t.destinationAsset,
            t.destinationAmount,
            t.destinationVault,
            t.recipient
        );
        uint256 excess = delivered.amount - t.destinationAmount;
        if (delta.expectedDestinationAmount != t.destinationAmount) {
            revert AmountMismatch("expectedDestinationAmount", t.destinationAmount, delta.expectedDestinationAmount);
        }
        if (delta.actualDestinationDelivered != delivered.amount) {
            revert AmountMismatch("actualDestinationDelivered", delivered.amount, delta.actualDestinationDelivered);
        }
        if (delta.excessDestinationDelivered != excess) {
            revert AmountMismatch("excessDestinationDelivered", excess, delta.excessDestinationDelivered);
        }
        if (delta.destinationExcessPolicy != RECIPIENT_RETAINS) revert InvalidLeg("destinationExcessPolicy");
        _checkLeg(
            operationId,
            PROVIDER_SETTLED,
            t.sourceChainId,
            t.sourceAsset,
            delta.realizedPrincipal,
            t.sourceRouter,
            address(0)
        );
        _checkLeg(
            operationId, FEE_REALIZED, t.sourceChainId, t.sourceAsset, delta.realizedFees, t.sourceRouter, address(0)
        );
        _checkLeg(
            operationId,
            DELTA_RETURNED,
            t.sourceChainId,
            t.sourceAsset,
            delta.residualReturned,
            t.sourceRouter,
            t.recoveryAddress
        );
        ValueLeg storage finalized =
            _checkLeg(operationId, SOURCE_FINALIZED, t.sourceChainId, t.sourceAsset, 0, t.sourceRouter, address(0));
        if (delta.sourceFinalizeTx == bytes32(0) || delta.sourceFinalizeTx != finalized.transactionHash) {
            revert InvalidLeg("sourceFinalizeTx");
        }
        _checkConservation(delta.maximumInput, delta.realizedPrincipal, delta.realizedFees, delta.residualReturned);
        reconciliations[operationId] = delta;
        operations[operationId].status = OperationStatus.RECONCILED;
        _emitReconciled(operationId, delta);
    }

    function _emitReconciled(bytes32 operationId, DeltaReconciliation calldata delta) internal {
        emit OperationReconciled(
            operationId,
            delta.sourceAsset,
            delta.maximumInput,
            delta.realizedPrincipal,
            delta.realizedFees,
            delta.residualReturned,
            delta.recoveryAddress,
            delta.sourceFinalizeTx,
            delta.expectedDestinationAmount,
            delta.actualDestinationDelivered,
            delta.excessDestinationDelivered,
            delta.destinationExcessPolicy
        );
    }

    function recordRefund(bytes32 operationId, RefundReceipt calldata refund)
        external
        onlyRole(SOURCE_FINALIZATION_WRITER)
    {
        _requireOperation(operationId);
        if (_isTerminal(operations[operationId].status)) {
            revert TerminalOperation(operationId, operations[operationId].status);
        }
        if (operations[operationId].status != OperationStatus.REFUND_PENDING) {
            revert InvalidOperationTransition(operationId, operations[operationId].status, OperationStatus.REFUNDED);
        }
        _requireRefundSafe(operationId);
        OperationTerms storage t = termsByOperation[operationId];
        if (refund.recoveryAddress != t.recoveryAddress) {
            revert RecoveryAddressMismatch(t.recoveryAddress, refund.recoveryAddress);
        }
        if (refund.sourceAsset != t.sourceAsset) revert AssetMismatch(t.sourceAsset, refund.sourceAsset);
        if (refund.amount != t.maximumInput) revert AmountMismatch("refund", t.maximumInput, refund.amount);
        _checkLeg(operationId, SOURCE_ESCROWED, t.sourceChainId, t.sourceAsset, t.maximumInput, t.payer, t.sourceRouter);
        ValueLeg storage fullRefund = _checkLeg(
            operationId, FULL_REFUND, t.sourceChainId, t.sourceAsset, t.maximumInput, t.sourceRouter, t.recoveryAddress
        );
        if (refund.refundTx == bytes32(0) || refund.refundTx != fullRefund.transactionHash) {
            revert InvalidLeg("refundTx");
        }
        if (refund.proofKind == ProofKind.NONE || refund.proofKind != fullRefund.proofKind) {
            revert UnsupportedProofKind(refund.proofKind);
        }
        operations[operationId].status = OperationStatus.REFUNDED;
        emit OperationRefunded(
            operationId, refund.sourceAsset, refund.recoveryAddress, refund.amount, refund.refundTx, refund.proofKind
        );
    }

    function _appendLeg(ValueLegInput calldata leg) internal returns (bytes32 legId) {
        _requireOperation(leg.operationId);
        if (leg.transactionHash == bytes32(0)) revert InvalidLeg("txHash");
        if (leg.proofKind == ProofKind.NONE) revert UnsupportedProofKind(leg.proofKind);
        if (!_supportedLegType(leg.legType)) revert InvalidLeg("legType");
        if (legByType[leg.operationId][leg.legType] != bytes32(0)) {
            revert DuplicateLegType(leg.operationId, leg.legType);
        }
        if (leg.proofKind == ProofKind.LOCAL_VERIFIED && leg.chainId != block.chainid) {
            revert ChainMismatch(uint64(block.chainid), leg.chainId);
        }
        if (leg.proofKind != ProofKind.LOCAL_VERIFIED && leg.chainId == block.chainid) {
            revert ChainMismatch(uint64(block.chainid), leg.chainId);
        }
        legId = keccak256(abi.encode(leg.operationId, leg.chainId, leg.transactionHash, leg.logIndex, leg.legType));
        if (legExists[legId]) revert DuplicateLegId(legId);
        legExists[legId] = true;
        legs[legId] = ValueLeg(
            legId,
            leg.operationId,
            leg.chainId,
            leg.transactionHash,
            leg.logIndex,
            leg.asset,
            leg.from,
            leg.to,
            leg.amount,
            leg.legType,
            leg.proofKind,
            leg.proofReference
        );
        legByType[leg.operationId][leg.legType] = legId;
        emit ValueLegAppended(
            legId,
            leg.operationId,
            leg.chainId,
            leg.legType,
            leg.asset,
            leg.from,
            leg.to,
            leg.amount,
            leg.proofKind,
            leg.proofReference
        );
    }

    function _computeTermsHash(OperationTerms calldata t) internal view returns (bytes32) {
        bytes32 partyHash = keccak256(
            abi.encode(t.initiator, t.payer, t.recipient, t.recoveryAddress, t.sourceRouter, t.destinationVault)
        );
        bytes32 chainHash =
            keccak256(abi.encode(t.sourceChainId, t.destinationChainId, t.sourceAsset, t.destinationAsset));
        bytes32 amountHash = keccak256(abi.encode(t.maximumInput, t.destinationAmount, t.maximumFee));
        return keccak256(
            abi.encode(
                TERMS_DOMAIN,
                block.chainid,
                address(this),
                t.operationType,
                t.proposedPurposeCode,
                partyHash,
                chainHash,
                amountHash,
                t.claimantRule,
                t.privateContextHash,
                t.expiry,
                t.nonce
            )
        );
    }

    function _computeOperationId(bytes32 termsHash) internal view returns (bytes32) {
        return keccak256(abi.encode(OPERATION_DOMAIN, block.chainid, address(this), termsHash));
    }

    function _validateTerms(OperationTerms calldata t) internal view {
        if (t.operationType == bytes32(0)) revert InvalidOperationTerms("operationType");
        if (t.proposedPurposeCode == bytes32(0)) revert InvalidOperationTerms("purpose");
        if (t.initiator == address(0)) revert InvalidOperationTerms("initiator");
        if (t.payer == address(0)) revert InvalidOperationTerms("payer");
        if (t.recipient == address(0)) revert InvalidOperationTerms("recipient");
        if (t.recoveryAddress == address(0)) revert InvalidOperationTerms("recovery");
        if (t.sourceRouter == address(0)) revert InvalidOperationTerms("router");
        if (t.destinationVault == address(0)) revert InvalidOperationTerms("vault");
        if (t.sourceChainId == 0) revert InvalidOperationTerms("sourceChainId");
        if (t.destinationChainId == 0 || t.destinationChainId == t.sourceChainId) {
            revert InvalidOperationTerms("destinationChainId");
        }
        if (t.maximumInput == 0) revert InvalidOperationTerms("maximumInput");
        if (t.destinationAmount == 0) revert InvalidOperationTerms("destinationAmount");
        if (t.maximumFee > t.maximumInput) revert InvalidOperationTerms("maximumFee");
        if (t.expiry < block.timestamp) revert InvalidOperationTerms("expiry");
    }

    function _requireOperation(bytes32 operationId) internal view {
        if (!operationExists[operationId]) revert OperationNotFound(operationId);
    }

    function _isTerminal(OperationStatus s) internal pure returns (bool) {
        return s == OperationStatus.RECONCILED || s == OperationStatus.REFUNDED;
    }

    function _advance(bytes32 operationId, OperationStatus nextStatus) internal {
        OperationStatus current = operations[operationId].status;
        if (_isTerminal(current)) revert TerminalOperation(operationId, current);
        bool ok =
            (current == OperationStatus.REGISTERED
                    && (nextStatus == OperationStatus.SOURCE_AUTHORIZED
                        || nextStatus == OperationStatus.EXPIRED
                        || nextStatus == OperationStatus.ROUTE_FAILED))
                || (current == OperationStatus.SOURCE_AUTHORIZED
                    && (nextStatus == OperationStatus.SOURCE_ESCROWED
                        || nextStatus == OperationStatus.EXPIRED
                        || nextStatus == OperationStatus.ROUTE_FAILED))
                || (current == OperationStatus.SOURCE_ESCROWED
                    && (nextStatus == OperationStatus.ROUTE_PENDING
                        || nextStatus == OperationStatus.DESTINATION_RESERVED
                        || nextStatus == OperationStatus.EXPIRED
                        || nextStatus == OperationStatus.ROUTE_FAILED))
                || (current == OperationStatus.ROUTE_PENDING
                    && (nextStatus == OperationStatus.DESTINATION_SETTLED
                        || nextStatus == OperationStatus.DESTINATION_RESERVED
                        || nextStatus == OperationStatus.EXPIRED
                        || nextStatus == OperationStatus.ROUTE_FAILED))
                || (current == OperationStatus.DESTINATION_RESERVED
                    && (nextStatus == OperationStatus.DESTINATION_SETTLED
                        || nextStatus == OperationStatus.EXPIRED
                        || nextStatus == OperationStatus.ROUTE_FAILED))
                || (current == OperationStatus.DESTINATION_SETTLED && nextStatus == OperationStatus.SOURCE_FINALIZED)
                || ((current == OperationStatus.EXPIRED || current == OperationStatus.ROUTE_FAILED)
                    && nextStatus == OperationStatus.REFUND_PENDING);
        if (!ok) revert InvalidOperationTransition(operationId, current, nextStatus);
        if (nextStatus == OperationStatus.EXPIRED) {
            uint64 expiry = operations[operationId].expiry;
            if (block.timestamp < expiry) revert OperationNotExpired(operationId, expiry, block.timestamp);
        }
        if (nextStatus == OperationStatus.REFUND_PENDING) _requireRefundSafe(operationId);
        _requireTransitionEvidence(operationId, nextStatus);
        operations[operationId].status = nextStatus;
        emit OperationStatusAdvanced(operationId, current, nextStatus, msg.sender);
    }

    function _supportedLegType(bytes32 t) internal pure returns (bool) {
        return t == SOURCE_AUTHORIZED || t == SOURCE_ESCROWED || t == DESTINATION_RESERVED || t == DESTINATION_DELIVERED
            || t == PROVIDER_SETTLED || t == FEE_REALIZED || t == DELTA_RETURNED || t == SOURCE_FINALIZED
            || t == FULL_REFUND;
    }

    function _requireTransitionEvidence(bytes32 op, OperationStatus nextStatus) internal view {
        bytes32 required;
        if (nextStatus == OperationStatus.SOURCE_AUTHORIZED) required = SOURCE_AUTHORIZED;
        if (nextStatus == OperationStatus.SOURCE_ESCROWED) required = SOURCE_ESCROWED;
        if (nextStatus == OperationStatus.DESTINATION_RESERVED) required = DESTINATION_RESERVED;
        if (nextStatus == OperationStatus.DESTINATION_SETTLED) required = DESTINATION_DELIVERED;
        if (nextStatus == OperationStatus.SOURCE_FINALIZED) required = SOURCE_FINALIZED;
        if (required == bytes32(0)) return;
        OperationTerms storage t = termsByOperation[op];
        if (nextStatus == OperationStatus.SOURCE_AUTHORIZED) {
            _checkLeg(op, SOURCE_AUTHORIZED, t.sourceChainId, t.sourceAsset, t.maximumInput, t.payer, t.sourceRouter);
        } else if (nextStatus == OperationStatus.SOURCE_ESCROWED) {
            _checkLeg(op, SOURCE_ESCROWED, t.sourceChainId, t.sourceAsset, t.maximumInput, t.payer, t.sourceRouter);
        } else if (nextStatus == OperationStatus.DESTINATION_RESERVED) {
            _checkLegAtLeast(
                op,
                DESTINATION_RESERVED,
                t.destinationChainId,
                t.destinationAsset,
                t.destinationAmount,
                t.destinationVault,
                t.recipient
            );
        } else if (nextStatus == OperationStatus.DESTINATION_SETTLED) {
            _checkLegAtLeast(
                op,
                DESTINATION_DELIVERED,
                t.destinationChainId,
                t.destinationAsset,
                t.destinationAmount,
                t.destinationVault,
                t.recipient
            );
        } else if (nextStatus == OperationStatus.SOURCE_FINALIZED) {
            _checkLeg(op, SOURCE_FINALIZED, t.sourceChainId, t.sourceAsset, 0, t.sourceRouter, address(0));
            _checkLegAtLeast(
                op,
                DESTINATION_DELIVERED,
                t.destinationChainId,
                t.destinationAsset,
                t.destinationAmount,
                t.destinationVault,
                t.recipient
            );
        }
    }

    function _checkLeg(
        bytes32 op,
        bytes32 legType,
        uint64 chainId,
        address asset,
        uint256 amount,
        address requiredFrom,
        address requiredTo
    ) internal view returns (ValueLeg storage l) {
        bytes32 legId = legByType[op][legType];
        if (legId == bytes32(0)) revert MissingRequiredReceipt(op, legType);
        l = legs[legId];
        if (l.chainId != chainId) revert ChainMismatch(chainId, l.chainId);
        if (l.asset != asset) revert AssetMismatch(asset, l.asset);
        if (l.amount != amount) revert AmountMismatch(legType, amount, l.amount);
        if (requiredFrom != address(0) && l.from != requiredFrom) {
            revert EndpointMismatch("from", requiredFrom, l.from);
        }
        if (requiredTo != address(0) && l.to != requiredTo) revert RecipientMismatch(requiredTo, l.to);
    }

    function _checkLegAtLeast(
        bytes32 op,
        bytes32 legType,
        uint64 chainId,
        address asset,
        uint256 minimumAmount,
        address requiredFrom,
        address requiredTo
    ) internal view returns (ValueLeg storage l) {
        bytes32 legId = legByType[op][legType];
        if (legId == bytes32(0)) revert MissingRequiredReceipt(op, legType);
        l = legs[legId];
        if (l.chainId != chainId) revert ChainMismatch(chainId, l.chainId);
        if (l.asset != asset) revert AssetMismatch(asset, l.asset);
        if (l.amount < minimumAmount) revert AmountMismatch(legType, minimumAmount, l.amount);
        if (requiredFrom != address(0) && l.from != requiredFrom) {
            revert EndpointMismatch("from", requiredFrom, l.from);
        }
        if (requiredTo != address(0) && l.to != requiredTo) revert RecipientMismatch(requiredTo, l.to);
    }

    function _requireRefundSafe(bytes32 operationId) internal view {
        OperationStatus s = operations[operationId].status;
        if (s == OperationStatus.DESTINATION_RESERVED) revert UnsafeRefundEvidence(operationId, DESTINATION_RESERVED);
        if (s == OperationStatus.DESTINATION_SETTLED) revert UnsafeRefundEvidence(operationId, DESTINATION_DELIVERED);
        if (s == OperationStatus.SOURCE_FINALIZED) revert UnsafeRefundEvidence(operationId, SOURCE_FINALIZED);
        bytes32[6] memory unsafeLegs = [
            DESTINATION_RESERVED,
            DESTINATION_DELIVERED,
            PROVIDER_SETTLED,
            FEE_REALIZED,
            DELTA_RETURNED,
            SOURCE_FINALIZED
        ];
        for (uint256 i; i < unsafeLegs.length; i++) {
            if (legByType[operationId][unsafeLegs[i]] != bytes32(0)) {
                revert UnsafeRefundEvidence(operationId, unsafeLegs[i]);
            }
        }
    }

    function _checkConservation(uint256 maximumInput, uint256 principal, uint256 fees, uint256 residual) internal pure {
        if (principal > maximumInput) revert InvalidConservationEquation(maximumInput, principal, fees, residual);
        uint256 remaining = maximumInput - principal;
        if (fees > remaining) revert InvalidConservationEquation(maximumInput, principal, fees, residual);
        remaining -= fees;
        if (residual != remaining) revert InvalidConservationEquation(maximumInput, principal, fees, residual);
    }
}
