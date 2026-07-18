// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Minimal, SafeToken} from "./libraries/SafeToken.sol";
import {IGlyphMessengerAdapter} from "./interfaces/IGlyphMessengerAdapter.sol";

contract SourceDeltaRouter {
    using SafeToken for IERC20Minimal;

    bytes32 public constant PUSH = keccak256("PUSH");
    bytes32 public constant PULL = keccak256("PULL");
    bytes32 public constant SESSION = keccak256("SESSION");
    bytes32 public constant PROGRAM_NONE = bytes32(0);

    enum Status {
        NONE,
        ESCROWED,
        ACK_DELIVERED,
        RECONCILED,
        REFUND_PENDING,
        REFUNDED
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

    mapping(bytes32 => Operation) public operations;
    mapping(address => uint256) public actorNonce;
    mapping(bytes32 => bool) public ackDelivered;
    mapping(address => bool) public authorizedMessengerAdapter;
    mapping(address => bool) public authorizedMessengerProcessor;
    mapping(address => address) public messengerProcessorAdapter;
    address public owner;
    bool internal locked;

    event OperationEscrowed(
        bytes32 indexed operationId, bytes32 indexed mode, address indexed payer, uint256 maximumInput
    );
    event DestinationAcknowledged(bytes32 indexed operationId, bytes32 messageId);
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
        return keccak256(abi.encode("GLYPH_TERMS_V2", block.chainid, address(this), t));
    }

    function operationId(Terms memory t) public view returns (bytes32) {
        return keccak256(abi.encode("GLYPH_OPERATION_V2", block.chainid, address(this), hashTerms(t)));
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

    function acknowledgeDelivery(bytes32, bytes32) external pure {
        revert UnauthorizedActor();
    }

    function acknowledgeDeliveryFromAdapter(bytes32 op, bytes32 messageId, address adapter) external {
        if (
            !authorizedMessengerAdapter[adapter]
                || (msg.sender != adapter
                    && (!authorizedMessengerProcessor[msg.sender] || messengerProcessorAdapter[msg.sender] != adapter))
        ) {
            revert UnauthorizedActor();
        }
        _acknowledgeDelivery(op, messageId);
    }

    function _acknowledgeDelivery(bytes32 op, bytes32 messageId) internal {
        Operation storage o = operations[op];
        if (o.status != Status.ESCROWED && o.status != Status.ACK_DELIVERED) revert NotEscrowed();
        o.status = Status.ACK_DELIVERED;
        ackDelivered[op] = true;
        emit DestinationAcknowledged(op, messageId);
    }

    function finalize(bytes32 op, address provider, address protocol, address referrer, address gasSponsor)
        external
        nonReentrant
    {
        Operation storage o = operations[op];
        if (o.status == Status.RECONCILED || o.status == Status.REFUNDED) revert AlreadyTerminal();
        if (!ackDelivered[op]) revert RefundUnsafe();
        Terms memory t = o.terms;
        uint256 fees = feeTotal(t);
        uint256 principal = t.destinationAmount;
        if (fees + principal > t.maximumInput) revert Conservation();
        uint256 residual = t.maximumInput - principal - fees;
        o.realizedPrincipal = principal;
        o.realizedFees = fees;
        o.residualReturned = residual;
        o.status = Status.RECONCILED;
        t.sourceAsset.safeTransfer(provider, principal + t.providerFee);
        if (t.protocolFee != 0) t.sourceAsset.safeTransfer(protocol, t.protocolFee);
        if (t.referrerFee != 0) t.sourceAsset.safeTransfer(referrer, t.referrerFee);
        if (t.gasSponsorFee != 0) t.sourceAsset.safeTransfer(gasSponsor, t.gasSponsorFee);
        if (residual != 0) t.sourceAsset.safeTransfer(t.recovery, residual);
        emit SourceFinalized(op, principal, fees, residual);
    }

    function refund(bytes32 op) external nonReentrant {
        Operation storage o = operations[op];
        if (o.status == Status.RECONCILED || o.status == Status.REFUNDED) revert AlreadyTerminal();
        if (ackDelivered[op]) revert RefundUnsafe();
        if (block.timestamp <= o.terms.expiry && o.status != Status.REFUND_PENDING) revert RefundUnsafe();
        o.status = Status.REFUNDED;
        o.terms.sourceAsset.safeTransfer(o.terms.recovery, o.terms.maximumInput);
        emit Refunded(op, o.terms.maximumInput);
    }

    function markRefundPending(bytes32) external pure {
        revert UnauthorizedActor();
    }

    function markRefundPendingFromAdapter(bytes32 op, address adapter) external {
        if (
            !authorizedMessengerAdapter[adapter]
                || (msg.sender != adapter
                    && (!authorizedMessengerProcessor[msg.sender] || messengerProcessorAdapter[msg.sender] != adapter))
        ) {
            revert UnauthorizedActor();
        }
        _markRefundPending(op);
    }

    function _markRefundPending(bytes32 op) internal {
        Operation storage o = operations[op];
        if (ackDelivered[op]) revert RefundUnsafe();
        o.status = Status.REFUND_PENDING;
    }

    function _validate(Terms calldata t) internal {
        if (t.mode == SESSION) revert SessionDisabled();
        if (t.mode != PUSH && t.mode != PULL) revert InvalidTerms();
        if (
            t.payer == address(0) || t.recipient == address(0) || t.recovery == address(0)
                || address(t.sourceAsset) == address(0) || t.destinationVault == address(0)
        ) revert InvalidTerms();
        if (t.sourceChainId == 0 || t.destinationChainId == 0) revert InvalidTerms();
        if (
            t.maximumInput == 0 || t.destinationAmount == 0 || feeTotal(t) > t.maximumInput
                || t.destinationAmount + feeTotal(t) > t.maximumInput
        ) revert InvalidTerms();
        if (t.nonce != actorNonce[t.payer]++) revert InvalidTerms();
        if (t.expiry < block.timestamp) revert InvalidTerms();
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
