// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IGlyphReceiptLedger {
    enum OperationStatus {
        NONE,
        REGISTERED,
        SOURCE_AUTHORIZED,
        SOURCE_ESCROWED,
        ROUTE_PENDING,
        DESTINATION_RESERVED,
        DESTINATION_SETTLED,
        SOURCE_FINALIZED,
        RECONCILED,
        REFUND_PENDING,
        REFUNDED,
        EXPIRED,
        ROUTE_FAILED
    }
    enum ProofKind {
        NONE,
        LOCAL_VERIFIED,
        AUTHENTICATED_ADAPTER,
        LIGHT_CLIENT_VERIFIED
    }

    struct OperationTerms {
        bytes32 operationType;
        bytes32 proposedPurposeCode;
        address initiator;
        address payer;
        address recipient;
        address recoveryAddress;
        address sourceRouter;
        address destinationVault;
        uint64 sourceChainId;
        uint64 destinationChainId;
        address sourceAsset;
        address destinationAsset;
        uint256 maximumInput;
        uint256 destinationAmount;
        uint256 maximumFee;
        bytes32 claimantRule;
        bytes32 privateContextHash;
        uint64 expiry;
        uint256 nonce;
    }

    struct OperationRecord {
        bytes32 operationId;
        bytes32 operationType;
        bytes32 proposedPurposeCode;
        address initiator;
        address payer;
        address recipient;
        bytes32 termsHash;
        bytes32 privateContextHash;
        uint64 createdAt;
        uint64 expiry;
        OperationStatus status;
    }

    struct OperationParties {
        address initiator;
        address payer;
        address recipient;
    }

    struct ValueLegInput {
        bytes32 operationId;
        uint64 chainId;
        bytes32 transactionHash;
        uint32 logIndex;
        address asset;
        address from;
        address to;
        uint256 amount;
        bytes32 legType;
        ProofKind proofKind;
        bytes32 proofReference;
    }

    struct ValueLeg {
        bytes32 legId;
        bytes32 operationId;
        uint64 chainId;
        bytes32 transactionHash;
        uint32 logIndex;
        address asset;
        address from;
        address to;
        uint256 amount;
        bytes32 legType;
        ProofKind proofKind;
        bytes32 proofReference;
    }

    struct DeltaReconciliation {
        address sourceAsset;
        uint256 maximumInput;
        uint256 realizedPrincipal;
        uint256 realizedFees;
        uint256 residualReturned;
        address recoveryAddress;
        bytes32 sourceFinalizeTx;
        uint256 expectedDestinationAmount;
        uint256 actualDestinationDelivered;
        uint256 excessDestinationDelivered;
        bytes32 destinationExcessPolicy;
    }

    struct RefundReceipt {
        address sourceAsset;
        address recoveryAddress;
        uint256 amount;
        bytes32 refundTx;
        ProofKind proofKind;
    }

    error UnauthorizedAdmin(address caller);
    error UnauthorizedInitiator(address caller, address initiator);
    error DuplicateOperationId(bytes32 operationId);
    error OperationNotFound(bytes32 operationId);
    error UnauthorizedFinancialWriter(address caller, bytes32 writerRole);
    error DuplicateLegId(bytes32 legId);
    error DuplicateMessageId(bytes32 messageId);
    error ZeroMessageId();
    error UnsupportedProofKind(ProofKind proofKind);
    error ProofKindMismatch(ProofKind provided, ProofKind expected);
    error InvalidLeg(bytes32 reason);
    error InvalidOperationTransition(bytes32 operationId, OperationStatus currentStatus, OperationStatus nextStatus);
    error TerminalOperation(bytes32 operationId, OperationStatus status);
    error MissingRequiredReceipt(bytes32 operationId, bytes32 requirement);
    error AssetMismatch(address expected, address actual);
    error RecipientMismatch(address expected, address actual);
    error AmountMismatch(bytes32 field, uint256 expected, uint256 actual);
    error RecoveryAddressMismatch(address expectedRecoveryAddress, address actualRecoveryAddress);
    error InvalidConservationEquation(
        uint256 maximumInput, uint256 realizedPrincipal, uint256 realizedFees, uint256 residualReturned
    );
    error DuplicateLegType(bytes32 operationId, bytes32 legType);
    error ChainMismatch(uint64 expected, uint64 actual);
    error EndpointMismatch(bytes32 field, address expected, address actual);
    error InvalidOperationTerms(bytes32 field);
    error OperationNotExpired(bytes32 operationId, uint64 expiry, uint256 nowTimestamp);
    error UnsafeRefundEvidence(bytes32 operationId, bytes32 evidence);

    function registerOperation(OperationTerms calldata terms) external returns (bytes32 operationId);
    function computeTermsHash(OperationTerms calldata terms) external view returns (bytes32);
    function computeOperationId(OperationTerms calldata terms) external view returns (bytes32);
    function getOperation(bytes32 operationId) external view returns (OperationRecord memory);
    function operationParties(bytes32 operationId) external view returns (OperationParties memory);
    function appendLocalLeg(ValueLegInput calldata leg) external returns (bytes32 legId);
    function appendRemoteLeg(ValueLegInput calldata leg, bytes32 messageId) external returns (bytes32 legId);
    function advanceStatus(bytes32 operationId, OperationStatus nextStatus) external;
    function reconcile(bytes32 operationId, DeltaReconciliation calldata delta) external;
    function recordRefund(bytes32 operationId, RefundReceipt calldata refund) external;
    function getValueLeg(bytes32 legId) external view returns (ValueLeg memory);
    function getReconciliation(bytes32 operationId) external view returns (DeltaReconciliation memory);
    function hasOperation(bytes32 operationId) external view returns (bool);
}
