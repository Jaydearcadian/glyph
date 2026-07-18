// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Minimal, SafeToken} from "./libraries/SafeToken.sol";

contract SourceDeltaRouter {
    using SafeToken for IERC20Minimal;

    bytes32 public constant PUSH = keccak256("PUSH");
    bytes32 public constant PULL = keccak256("PULL");
    bytes32 public constant SESSION = keccak256("SESSION");
    bytes32 public constant PROGRAM_NONE = bytes32(0);

    enum Status {
        NONE,
        ESCROWED,
        RESERVED,
        ACK_DELIVERED,
        RECONCILED,
        REFUND_PENDING,
        REFUNDED
    }

    enum FailureCode {
        NONE,
        LIQUIDITY_UNAVAILABLE,
        TERMS_EXPIRED,
        INVALID_DESTINATION_TERMS,
        UNSUPPORTED_ASSET,
        CLAIM_NOT_COMPLETED,
        ADAPTER_FAILURE
    }

    struct Terms {
        bytes32 mode;
        bytes32 programId;
        address payer;
        address recipient;
        address recovery;
        IERC20Minimal sourceAsset;
        uint64 sourceChainId;
        address destinationVault;
        address destinationAsset;
        uint64 destinationChainId;
        uint256 maximumInput;
        uint256 destinationAmount;
        uint256 protocolFee;
        uint256 providerFee;
        uint256 referrerFee;
        uint256 gasSponsorFee;
        address provider;
        address protocol;
        address referrer;
        address gasSponsor;
        address claimGatekeeper;
        uint64 expiry;
        uint256 nonce;
    }

    struct Operation {
        bytes32 termsHash;
        Terms terms;
        Status status;
        uint256 realizedPrincipal;
        uint256 realizedFees;
        uint256 residualReturned;
        bytes32 routeMessageId;
        uint256 routeNonce;
        bytes32 destinationMessageId;
        address claimantOrRecipient;
        FailureCode failureCode;
    }

    error InvalidTerms();
    error SessionDisabled();
    error DuplicateOperation(bytes32 op);
    error UnauthorizedActor();
    error InvalidSignature();
    error NotEscrowed();
    error AlreadyTerminal();
    error Conservation();
    error RefundUnsafe();
    error UnknownOperation(bytes32 op);
    error InvalidLifecycle();
    error InvalidAck();

    mapping(bytes32 => Operation) public operations;
    mapping(address => uint256) public actorNonce;
    mapping(bytes32 => bool) public ackDelivered;
    mapping(bytes32 => bool) public reservationAcked;
    mapping(address => bool) public authorizedMessengerAdapter;
    mapping(address => bool) public authorizedMessengerProcessor;
    mapping(address => address) public messengerProcessorAdapter;
    address public owner;
    bool internal locked;

    event OperationEscrowed(
        bytes32 indexed operationId, bytes32 indexed mode, address indexed payer, uint256 maximumInput
    );
    event RouteRecorded(bytes32 indexed operationId, bytes32 indexed messageId, uint256 routeNonce);
    event DestinationReserved(bytes32 indexed operationId, bytes32 messageId);
    event DestinationAcknowledged(bytes32 indexed operationId, bytes32 messageId);
    event DestinationFailed(bytes32 indexed operationId, FailureCode code);
    event SourceFinalized(bytes32 indexed operationId, uint256 principal, uint256 fees, uint256 residual);
    event Refunded(bytes32 indexed operationId, uint256 amount);
    event MessengerAdapterSet(address indexed adapter, bool authorized);
    event MessengerProcessorSet(address indexed processor, address indexed adapter, bool authorized);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedActor();
        _;
    }

    modifier nonReentrant() {
        require(!locked, "reentrant");
        locked = true;
        _;
        locked = false;
    }

    function hashTerms(Terms memory t) public view returns (bytes32) {
        return keccak256(abi.encode("GLYPH_TERMS_V3", block.chainid, address(this), t));
    }

    function operationId(Terms memory t) public view returns (bytes32) {
        return keccak256(abi.encode("GLYPH_OPERATION_V3", block.chainid, address(this), hashTerms(t)));
    }

    function feeTotal(Terms memory t) public pure returns (uint256) {
        return t.protocolFee + t.providerFee + t.referrerFee + t.gasSponsorFee;
    }

    function escrow(Terms calldata t) external nonReentrant returns (bytes32 op) {
        if (msg.sender != t.payer) revert UnauthorizedActor();
        op = _escrow(t);
    }

    function escrowWithSignature(Terms calldata t, uint64 deadline, bytes calldata sig)
        external
        nonReentrant
        returns (bytes32 op)
    {
        if (deadline < block.timestamp) revert InvalidSignature();
        bytes32 digest = keccak256(abi.encode("GLYPH_ESCROW", block.chainid, address(this), hashTerms(t), deadline));
        (bytes32 r, bytes32 s, uint8 v) = _split(sig);
        if (ecrecover(digest, v, r, s) != t.payer) revert InvalidSignature();
        op = _escrow(t);
    }

    function _escrow(Terms calldata t) internal returns (bytes32 op) {
        _validate(t);
        op = operationId(t);
        if (operations[op].status != Status.NONE) revert DuplicateOperation(op);
        operations[op].termsHash = hashTerms(t);
        operations[op].terms = t;
        operations[op].status = Status.ESCROWED;
        t.sourceAsset.safeTransferFrom(t.payer, address(this), t.maximumInput);
        emit OperationEscrowed(op, t.mode, t.payer, t.maximumInput);
    }

    function setMessengerAdapter(address adapter, bool authorized) external onlyOwner {
        if (adapter == address(0)) revert InvalidTerms();
        authorizedMessengerAdapter[adapter] = authorized;
        emit MessengerAdapterSet(adapter, authorized);
    }

    function setMessengerProcessor(address processor, bool authorized) external onlyOwner {
        if (processor == address(0)) revert InvalidTerms();
        authorizedMessengerProcessor[processor] = authorized;
        if (!authorized) messengerProcessorAdapter[processor] = address(0);
        emit MessengerProcessorSet(processor, messengerProcessorAdapter[processor], authorized);
    }

    function setMessengerProcessorForAdapter(address processor, address adapter, bool authorized) external onlyOwner {
        if (processor == address(0) || adapter == address(0) || !authorizedMessengerAdapter[adapter]) {
            revert InvalidTerms();
        }
        authorizedMessengerProcessor[processor] = authorized;
        messengerProcessorAdapter[processor] = authorized ? adapter : address(0);
        emit MessengerProcessorSet(processor, adapter, authorized);
    }

    function _authorized(address adapter) internal view returns (bool) {
        return authorizedMessengerAdapter[adapter]
            && (msg.sender == adapter
                || (authorizedMessengerProcessor[msg.sender] && messengerProcessorAdapter[msg.sender] == adapter));
    }

    function acknowledgeDelivery(bytes32, bytes32) external pure {
        revert UnauthorizedActor();
    }

    function markRefundPending(bytes32) external pure {
        revert UnauthorizedActor();
    }

    function recordRouteFromAdapter(
        bytes32 op,
        bytes32 messageId,
        uint256 routeNonce,
        bytes32 termsHash,
        address adapter
    ) external {
        if (!_authorized(adapter)) revert UnauthorizedActor();
        Operation storage o = operations[op];
        if (o.status != Status.ESCROWED) revert NotEscrowed();
        if (o.termsHash != termsHash || messageId == bytes32(0) || routeNonce == 0) revert InvalidAck();
        if (o.routeMessageId != bytes32(0)) revert InvalidLifecycle();
        o.routeMessageId = messageId;
        o.routeNonce = routeNonce;
        emit RouteRecorded(op, messageId, routeNonce);
    }

    function recordDestinationReservedFromAdapter(
        bytes32 op,
        bytes32 ackMessageId,
        bytes32 routeMessageId,
        uint256 routeNonce,
        bytes32 termsHash,
        address provider,
        address adapter
    ) external {
        if (!_authorized(adapter)) revert UnauthorizedActor();
        Operation storage o = _known(op);
        if (o.status != Status.ESCROWED || o.terms.mode != PUSH) revert InvalidLifecycle();
        _checkRoute(o, routeMessageId, routeNonce, termsHash);
        if (provider != o.terms.provider || ackMessageId == bytes32(0)) revert InvalidAck();
        o.status = Status.RESERVED;
        reservationAcked[op] = true;
        emit DestinationReserved(op, ackMessageId);
    }

    function acknowledgeDeliveryFromAdapter(bytes32 op, bytes32 messageId, address adapter) external {
        if (!_authorized(adapter)) revert UnauthorizedActor();
        Operation storage o = _known(op);
        if (o.status != Status.ESCROWED && o.status != Status.RESERVED && o.status != Status.ACK_DELIVERED) {
            revert NotEscrowed();
        }
        if (messageId == bytes32(0)) revert InvalidAck();
        o.status = Status.ACK_DELIVERED;
        ackDelivered[op] = true;
        o.destinationMessageId = messageId;
        emit DestinationAcknowledged(op, messageId);
    }

    function recordDestinationDeliveryFromAdapter(
        bytes32 op,
        bytes32 ackMessageId,
        bytes32 routeMessageId,
        uint256 routeNonce,
        bytes32 termsHash,
        address claimantOrRecipient,
        address provider,
        address asset,
        uint256 amount,
        address adapter
    ) external {
        if (!_authorized(adapter)) revert UnauthorizedActor();
        Operation storage o = _known(op);
        if (o.status != Status.ESCROWED && o.status != Status.RESERVED) revert InvalidLifecycle();
        _checkRoute(o, routeMessageId, routeNonce, termsHash);
        if (provider != o.terms.provider || asset != o.terms.destinationAsset || amount != o.terms.destinationAmount) {
            revert InvalidAck();
        }
        if (claimantOrRecipient == address(0)) revert InvalidAck();
        if (o.terms.mode == PULL && claimantOrRecipient != o.terms.recipient) revert InvalidAck();
        o.status = Status.ACK_DELIVERED;
        ackDelivered[op] = true;
        o.destinationMessageId = ackMessageId;
        o.claimantOrRecipient = claimantOrRecipient;
        emit DestinationAcknowledged(op, ackMessageId);
    }

    function recordFailureFromAdapter(
        bytes32 op,
        bytes32 routeMessageId,
        uint256 routeNonce,
        bytes32 termsHash,
        FailureCode code,
        address adapter
    ) external {
        if (!_authorized(adapter)) revert UnauthorizedActor();
        Operation storage o = _known(op);
        if (ackDelivered[op]) revert RefundUnsafe();
        if (code == FailureCode.NONE) revert InvalidAck();
        _checkRoute(o, routeMessageId, routeNonce, termsHash);
        o.status = Status.REFUND_PENDING;
        o.failureCode = code;
        emit DestinationFailed(op, code);
    }

    function markRefundPendingFromAdapter(bytes32 op, address adapter) external {
        if (!_authorized(adapter)) revert UnauthorizedActor();
        Operation storage o = _known(op);
        if (ackDelivered[op]) revert RefundUnsafe();
        o.status = Status.REFUND_PENDING;
    }

    function finalize(bytes32 op) external nonReentrant {
        Operation storage o = _known(op);
        if (o.status == Status.RECONCILED || o.status == Status.REFUNDED) revert AlreadyTerminal();
        if (!ackDelivered[op] || o.status != Status.ACK_DELIVERED) revert RefundUnsafe();
        Terms memory t = o.terms;
        uint256 fees = feeTotal(t);
        uint256 principal = t.destinationAmount;
        if (fees + principal > t.maximumInput) revert Conservation();
        _validateFeeRecipients(t);
        uint256 residual = t.maximumInput - principal - fees;
        o.realizedPrincipal = principal;
        o.realizedFees = fees;
        o.residualReturned = residual;
        o.status = Status.RECONCILED;
        t.sourceAsset.safeTransfer(t.provider, principal + t.providerFee);
        if (t.protocolFee != 0) t.sourceAsset.safeTransfer(t.protocol, t.protocolFee);
        if (t.referrerFee != 0) t.sourceAsset.safeTransfer(t.referrer, t.referrerFee);
        if (t.gasSponsorFee != 0) t.sourceAsset.safeTransfer(t.gasSponsor, t.gasSponsorFee);
        if (residual != 0) t.sourceAsset.safeTransfer(t.recovery, residual);
        emit SourceFinalized(op, principal, fees, residual);
    }

    function refund(bytes32 op) external nonReentrant {
        Operation storage o = _known(op);
        if (o.status == Status.RECONCILED || o.status == Status.REFUNDED) revert AlreadyTerminal();
        if (ackDelivered[op]) revert RefundUnsafe();
        if (block.timestamp <= o.terms.expiry && o.status != Status.REFUND_PENDING) revert RefundUnsafe();
        o.status = Status.REFUNDED;
        o.terms.sourceAsset.safeTransfer(o.terms.recovery, o.terms.maximumInput);
        emit Refunded(op, o.terms.maximumInput);
    }

    function routeFacts(bytes32 op)
        external
        view
        returns (bytes32 termsHash, bytes32 mode, bytes32 routeMessageId, uint256 routeNonce, Status status)
    {
        Operation storage o = _known(op);
        return (o.termsHash, o.terms.mode, o.routeMessageId, o.routeNonce, o.status);
    }

    function payoutFacts(bytes32 op)
        external
        view
        returns (address provider, address protocol, address referrer, address gasSponsor, address recovery)
    {
        Terms storage t = _known(op).terms;
        return (t.provider, t.protocol, t.referrer, t.gasSponsor, t.recovery);
    }

    function termSnapshot(bytes32 op)
        external
        view
        returns (
            bytes32 mode,
            address payer,
            address recipient,
            address recovery,
            address sourceAsset,
            address destinationAsset,
            address provider,
            address gatekeeper,
            uint256 maximumInput,
            uint256 destinationAmount,
            uint256 feeTotal_,
            uint64 expiry
        )
    {
        Terms storage t = _known(op).terms;
        return (
            t.mode,
            t.payer,
            t.recipient,
            t.recovery,
            address(t.sourceAsset),
            t.destinationAsset,
            t.provider,
            t.claimGatekeeper,
            t.maximumInput,
            t.destinationAmount,
            feeTotal(t),
            t.expiry
        );
    }

    function routeInstructionFacts(bytes32 op)
        external
        view
        returns (
            bytes32 termsHash,
            bytes32 mode,
            address recipient,
            address destinationAsset,
            address provider,
            address gatekeeper,
            uint256 amount,
            uint64 expiry,
            Status status
        )
    {
        Operation storage o = _known(op);
        Terms storage t = o.terms;
        return (
            o.termsHash,
            t.mode,
            t.recipient,
            t.destinationAsset,
            t.provider,
            t.claimGatekeeper,
            t.destinationAmount,
            t.expiry,
            o.status
        );
    }

    function sourceReceiptFacts(bytes32 op)
        external
        view
        returns (
            bytes32 termsHash,
            address sourceAsset,
            uint256 maximumInput,
            uint256 destinationAmount,
            uint256 fees,
            address recovery,
            Status status
        )
    {
        Operation storage o = _known(op);
        Terms storage t = o.terms;
        return
            (
                o.termsHash,
                address(t.sourceAsset),
                t.maximumInput,
                t.destinationAmount,
                feeTotal(t),
                t.recovery,
                o.status
            );
    }

    function _checkRoute(Operation storage o, bytes32 routeMessageId, uint256 routeNonce, bytes32 termsHash)
        internal
        view
    {
        if (o.routeMessageId == bytes32(0) || o.routeMessageId != routeMessageId || o.routeNonce != routeNonce) revert InvalidAck();
        if (o.termsHash != termsHash) revert InvalidAck();
    }

    function _known(bytes32 op) internal view returns (Operation storage o) {
        o = operations[op];
        if (o.status == Status.NONE) revert UnknownOperation(op);
    }

    function _validate(Terms calldata t) internal {
        if (t.mode == SESSION) revert SessionDisabled();
        if (t.mode != PUSH && t.mode != PULL) revert InvalidTerms();
        if (
            t.payer == address(0) || t.recipient == address(0) || t.recovery == address(0)
                || address(t.sourceAsset) == address(0) || t.destinationVault == address(0)
                || t.destinationAsset == address(0) || t.provider == address(0)
        ) revert InvalidTerms();
        if (t.mode == PUSH && t.claimGatekeeper == address(0)) revert InvalidTerms();
        if (t.mode == PULL && t.claimGatekeeper != address(0)) revert InvalidTerms();
        if (t.sourceChainId == 0 || t.destinationChainId == 0) revert InvalidTerms();
        if (
            t.maximumInput == 0 || t.destinationAmount == 0 || feeTotal(t) > t.maximumInput
                || t.destinationAmount + feeTotal(t) > t.maximumInput
        ) revert InvalidTerms();
        _validateFeeRecipients(t);
        if (t.nonce != actorNonce[t.payer]++) revert InvalidTerms();
        if (t.expiry < block.timestamp) revert InvalidTerms();
    }

    function _validateFeeRecipients(Terms memory t) internal pure {
        if (t.provider == address(0)) revert InvalidTerms();
        if (t.protocolFee != 0 && t.protocol == address(0)) revert InvalidTerms();
        if (t.referrerFee != 0 && t.referrer == address(0)) revert InvalidTerms();
        if (t.gasSponsorFee != 0 && t.gasSponsor == address(0)) revert InvalidTerms();
        if (t.providerFee != 0 && t.provider == address(0)) revert InvalidTerms();
    }

    function _split(bytes calldata sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        if (sig.length != 65) revert InvalidSignature();
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v != 27 && v != 28) revert InvalidSignature();
    }
}
