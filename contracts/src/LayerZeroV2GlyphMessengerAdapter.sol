// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGlyphMessengerAdapter} from "./interfaces/IGlyphMessengerAdapter.sol";
import {
    ILayerZeroEndpointV2,
    ILayerZeroReceiver,
    MessagingFee,
    MessagingParams,
    MessagingReceipt,
    Origin
} from "./interfaces/ILayerZeroV2Endpoint.sol";

interface IGlyphMessageHandler {
    function handleGlyphMessage(IGlyphMessengerAdapter.Envelope calldata envelope, bytes calldata payload) external;
}

contract LayerZeroV2GlyphMessengerAdapter is IGlyphMessengerAdapter, ILayerZeroReceiver {
    enum MessageStatus {
        NONE,
        SENT,
        STAGED,
        PROCESSED,
        FAILED
    }

    struct WireMessage {
        uint16 wireVersion;
        bytes32 messengerPolicyHash;
        bytes32 proofKind;
        bool ordered;
        Envelope envelope;
        bytes payload;
    }

    error Unauthorized();
    error InvalidConfig();
    error WrongEndpoint(address caller);
    error WrongEid(uint32 eid);
    error WrongPeer(bytes32 peer);
    error WrongChain(uint64 chainId);
    error WrongApplication(address app);
    error UnsupportedMessage();
    error PayloadHashMismatch();
    error DuplicateMessage(bytes32 messageId);
    error DuplicateSemantic(bytes32 semanticId);
    error UnknownMessage(bytes32 messageId);
    error HandlerFailed(bytes32 messageId);
    error InsufficientNativeFee(uint256 required, uint256 supplied);
    error RefundFailed();
    error WrongPolicy(bytes32 policyHash);
    error WrongProofKind(bytes32 proofKind);
    error StaleNonce(uint64 expected, uint64 actual);
    error Reentrant();
    error NativeValueRejected();

    uint16 public constant MESSAGE_VERSION = 1;
    uint16 public constant WIRE_VERSION = 1;
    bytes32 public constant PROOF_KIND = keccak256("AUTHENTICATED_ADAPTER");
    uint16 internal constant OPTIONS_TYPE_3 = 3;
    uint8 internal constant EXECUTOR_WORKER_ID = 1;
    uint8 internal constant OPTION_TYPE_LZRECEIVE = 1;
    uint8 internal constant OPTION_TYPE_ORDERED_EXECUTION = 4;

    address public immutable endpoint;
    uint64 public immutable localChainId;
    uint64 public immutable remoteChainId;
    uint32 public immutable localEid;
    uint32 public immutable remoteEid;
    bytes32 public messengerPolicyHash;
    address public owner;
    address public trustedPeer;
    address public localApplication;
    address public remoteApplication;
    uint256 public enforcedGasLimit = 200_000;
    bool public orderedExecution = true;
    bool public configFrozen;
    bytes32 public externalSecurityConfigHash;
    bool internal locked;

    mapping(bytes32 => Envelope) public envelopes;
    mapping(bytes32 => bytes) public payloads;
    mapping(bytes32 => MessageStatus) public messageStatus;
    mapping(bytes32 => bool) public consumedSemantic;
    mapping(uint32 => mapping(bytes32 => uint64)) public lastInboundNonce;

    event TrustedPeerSet(address indexed peer);
    event ApplicationsSet(address indexed localApplication, address indexed remoteApplication);
    event EnforcedGasLimitSet(uint256 gasLimit);
    event OrderedExecutionSet(bool ordered);
    event ConfigFrozen(bytes32 indexed policyHash, bytes32 indexed externalSecurityConfigHash);
    event MessageStaged(bytes32 indexed messageId, bytes32 indexed operationId);
    event MessageProcessingFailed(bytes32 indexed messageId, bytes reason);
    event MessageProcessed(bytes32 indexed messageId, bytes32 indexed operationId);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyLocalApplication() {
        if (msg.sender != localApplication) revert Unauthorized();
        _;
    }

    modifier mutableConfig() {
        if (configFrozen) revert InvalidConfig();
        _;
    }

    modifier frozenConfig() {
        if (!configFrozen) revert InvalidConfig();
        _;
    }

    modifier nonReentrant() {
        if (locked) revert Reentrant();
        locked = true;
        _;
        locked = false;
    }

    constructor(
        address endpoint_,
        uint64 localChainId_,
        uint32 localEid_,
        uint64 remoteChainId_,
        uint32 remoteEid_,
        address owner_,
        bytes32 messengerPolicyHash_
    ) {
        if (
            endpoint_ == address(0) || owner_ == address(0) || localChainId_ == 0 || remoteChainId_ == 0
                || localEid_ == 0 || remoteEid_ == 0 || localChainId_ == remoteChainId_
                || messengerPolicyHash_ == bytes32(0)
        ) revert InvalidConfig();
        endpoint = endpoint_;
        localChainId = localChainId_;
        localEid = localEid_;
        remoteChainId = remoteChainId_;
        remoteEid = remoteEid_;
        owner = owner_;
        externalSecurityConfigHash = messengerPolicyHash_;
    }

    receive() external payable {
        revert NativeValueRejected();
    }

    function transferOwnership(address nextOwner) external onlyOwner {
        if (nextOwner == address(0)) revert InvalidConfig();
        owner = nextOwner;
    }

    function setTrustedPeer(address peer) external onlyOwner mutableConfig {
        if (peer == address(0)) revert InvalidConfig();
        trustedPeer = peer;
        emit TrustedPeerSet(peer);
    }

    function setLocalApplication(address app) external onlyOwner mutableConfig {
        if (app == address(0)) revert InvalidConfig();
        localApplication = app;
        emit ApplicationsSet(localApplication, remoteApplication);
    }

    function setRemoteApplication(address app) external onlyOwner mutableConfig {
        if (app == address(0)) revert InvalidConfig();
        remoteApplication = app;
        emit ApplicationsSet(localApplication, remoteApplication);
    }

    function setEnforcedGasLimit(uint256 gasLimit) external onlyOwner mutableConfig {
        if (gasLimit < 50_000 || gasLimit > 5_000_000) revert InvalidConfig();
        enforcedGasLimit = gasLimit;
        emit EnforcedGasLimitSet(gasLimit);
    }

    function setOrderedExecution(bool ordered) external onlyOwner mutableConfig {
        orderedExecution = ordered;
        emit OrderedExecutionSet(ordered);
    }

    function computedPolicyHash(bytes32 externalCommitment) public view returns (bytes32) {
        bytes32 lane = keccak256(abi.encode(endpoint, localChainId, localEid, remoteChainId, remoteEid));
        bytes32 apps = keccak256(abi.encode(trustedPeer, localApplication, remoteApplication));
        bytes32 options =
            keccak256(abi.encode(PROOF_KIND, WIRE_VERSION, orderedExecution, enforcedGasLimit, externalCommitment));
        return keccak256(abi.encode("GLYPH_LZ_V2_POLICY_V1", lane, apps, options));
    }

    function freezeConfig(bytes32 externalCommitment) external onlyOwner {
        if (
            configFrozen || trustedPeer == address(0) || localApplication == address(0)
                || remoteApplication == address(0)
        ) {
            revert InvalidConfig();
        }
        if (externalCommitment == bytes32(0) || externalCommitment != externalSecurityConfigHash) {
            revert WrongPolicy(externalCommitment);
        }
        messengerPolicyHash = externalCommitment;
        configFrozen = true;
        emit ConfigFrozen(messengerPolicyHash, externalCommitment);
    }

    function quote(
        uint64 destinationChainId,
        address destinationApplication,
        Envelope calldata envelope,
        bytes calldata payload,
        uint256 gasLimit
    ) external view onlyLocalApplication frozenConfig returns (uint256 nativeFee) {
        _validateOutbound(destinationChainId, destinationApplication, envelope, payload);
        MessagingFee memory fee =
            ILayerZeroEndpointV2(endpoint).quote(_params(envelope, payload, gasLimit), address(this));
        nativeFee = fee.nativeFee;
    }

    function sendMessage(
        uint64 destinationChainId,
        address destinationApplication,
        Envelope calldata envelope,
        bytes calldata payload,
        address payable refundAddress,
        uint256 gasLimit
    ) external payable onlyLocalApplication frozenConfig nonReentrant returns (bytes32 messageId) {
        _validateOutbound(destinationChainId, destinationApplication, envelope, payload);
        if (refundAddress == address(0)) revert InvalidConfig();
        bytes32 semanticId = _semanticId(envelope);
        if (consumedSemantic[semanticId]) revert DuplicateSemantic(semanticId);
        MessagingParams memory params = _params(envelope, payload, gasLimit);
        MessagingFee memory fee = ILayerZeroEndpointV2(endpoint).quote(params, address(this));
        if (msg.value < fee.nativeFee) revert InsufficientNativeFee(fee.nativeFee, msg.value);
        MessagingReceipt memory receipt =
            ILayerZeroEndpointV2(endpoint).send{value: fee.nativeFee}(params, refundAddress);
        messageId = receipt.guid;
        if (messageStatus[messageId] != MessageStatus.NONE) revert DuplicateMessage(messageId);
        Envelope memory stored = envelope;
        stored.messageId = messageId;
        envelopes[messageId] = stored;
        payloads[messageId] = payload;
        messageStatus[messageId] = MessageStatus.SENT;
        consumedSemantic[semanticId] = true;
        _safeRefund(refundAddress, msg.value - fee.nativeFee);
        emit MessageQueued(messageId, stored.operationId, stored.messageType);
    }

    function allowInitializePath(Origin calldata origin) external view returns (bool) {
        return origin.srcEid == remoteEid && origin.sender == bytes32(uint256(uint160(trustedPeer)));
    }

    function nextNonce(uint32 eid, bytes32 sender) external view returns (uint64) {
        if (!orderedExecution) return 0;
        return lastInboundNonce[eid][sender] + 1;
    }

    function lzReceive(Origin calldata origin, bytes32 guid, bytes calldata message, address, bytes calldata)
        external
        payable
        override
        frozenConfig
    {
        if (msg.sender != endpoint) revert WrongEndpoint(msg.sender);
        if (origin.srcEid != remoteEid) revert WrongEid(origin.srcEid);
        bytes32 peer = bytes32(uint256(uint160(trustedPeer)));
        if (origin.sender != peer) revert WrongPeer(origin.sender);
        if (orderedExecution) {
            uint64 expected = lastInboundNonce[origin.srcEid][origin.sender] + 1;
            if (origin.nonce != expected) revert StaleNonce(expected, origin.nonce);
            lastInboundNonce[origin.srcEid][origin.sender] = origin.nonce;
        }
        if (messageStatus[guid] != MessageStatus.NONE) revert DuplicateMessage(guid);
        WireMessage memory wire = abi.decode(message, (WireMessage));
        if (wire.wireVersion != WIRE_VERSION) revert UnsupportedMessage();
        if (wire.messengerPolicyHash != messengerPolicyHash) revert WrongPolicy(wire.messengerPolicyHash);
        if (wire.proofKind != PROOF_KIND) revert WrongProofKind(wire.proofKind);
        if (wire.ordered != orderedExecution) revert UnsupportedMessage();
        Envelope memory envelope = wire.envelope;
        envelope.messageId = guid;
        _validateInbound(envelope, wire.payload);
        bytes32 semanticId = _semanticId(envelope);
        if (consumedSemantic[semanticId]) revert DuplicateSemantic(semanticId);
        consumedSemantic[semanticId] = true;
        envelopes[guid] = envelope;
        payloads[guid] = wire.payload;
        messageStatus[guid] = MessageStatus.STAGED;
        emit MessageStaged(guid, envelope.operationId);
        _tryProcess(guid);
    }

    function retry(bytes32 messageId) external {
        MessageStatus s = messageStatus[messageId];
        if (s != MessageStatus.STAGED && s != MessageStatus.FAILED) revert UnknownMessage(messageId);
        _tryProcess(messageId);
        if (messageStatus[messageId] != MessageStatus.PROCESSED) revert HandlerFailed(messageId);
    }

    function consume(bytes32 messageId) external onlyLocalApplication returns (Envelope memory envelope) {
        if (messageStatus[messageId] != MessageStatus.PROCESSED) revert UnknownMessage(messageId);
        envelope = envelopes[messageId];
    }

    function buildOptions(uint256 gasLimit) public view returns (bytes memory) {
        if (gasLimit < enforcedGasLimit || gasLimit > type(uint128).max) revert InvalidConfig();
        bytes memory receiveOption = abi.encodePacked(uint128(gasLimit), uint128(0));
        bytes memory options = abi.encodePacked(
            OPTIONS_TYPE_3, EXECUTOR_WORKER_ID, uint16(receiveOption.length + 1), OPTION_TYPE_LZRECEIVE, receiveOption
        );
        if (orderedExecution) {
            options = abi.encodePacked(options, EXECUTOR_WORKER_ID, uint16(1), OPTION_TYPE_ORDERED_EXECUTION);
        }
        return options;
    }

    function endpointQuoteSelector() external pure returns (bytes4) {
        return ILayerZeroEndpointV2.quote.selector;
    }

    function endpointSendSelector() external pure returns (bytes4) {
        return ILayerZeroEndpointV2.send.selector;
    }

    function _params(Envelope calldata envelope, bytes calldata payload, uint256 gasLimit)
        internal
        view
        returns (MessagingParams memory)
    {
        if (gasLimit < enforcedGasLimit) revert InvalidConfig();
        WireMessage memory wire =
            WireMessage(WIRE_VERSION, messengerPolicyHash, PROOF_KIND, orderedExecution, envelope, payload);
        return MessagingParams({
            dstEid: remoteEid,
            receiver: bytes32(uint256(uint160(trustedPeer))),
            message: abi.encode(wire),
            options: buildOptions(gasLimit),
            payInLzToken: false
        });
    }

    function _tryProcess(bytes32 messageId) internal {
        Envelope memory envelope = envelopes[messageId];
        try IGlyphMessageHandler(localApplication).handleGlyphMessage(envelope, payloads[messageId]) {
            messageStatus[messageId] = MessageStatus.PROCESSED;
            emit MessageProcessed(messageId, envelope.operationId);
            emit MessageDelivered(messageId, envelope.operationId, envelope.messageType);
        } catch (bytes memory reason) {
            messageStatus[messageId] = MessageStatus.FAILED;
            emit MessageProcessingFailed(messageId, reason);
        }
    }

    function _validateOutbound(
        uint64 destinationChainId,
        address destinationApplication,
        Envelope calldata e,
        bytes calldata payload
    ) internal view {
        if (trustedPeer == address(0) || localApplication == address(0) || remoteApplication == address(0)) revert InvalidConfig();
        if (destinationChainId != remoteChainId || e.destinationChainId != remoteChainId) {
            revert WrongChain(destinationChainId);
        }
        if (e.sourceChainId != localChainId) revert WrongChain(e.sourceChainId);
        if (destinationApplication != remoteApplication || e.destinationApplication != remoteApplication) {
            revert WrongApplication(destinationApplication);
        }
        if (e.sourceApplication != localApplication) revert WrongApplication(e.sourceApplication);
        _validateCommon(e, payload);
    }

    function _validateInbound(Envelope memory e, bytes memory payload) internal view {
        if (e.sourceChainId != remoteChainId) revert WrongChain(e.sourceChainId);
        if (e.destinationChainId != localChainId) revert WrongChain(e.destinationChainId);
        if (e.sourceApplication != remoteApplication) revert WrongApplication(e.sourceApplication);
        if (e.destinationApplication != localApplication) revert WrongApplication(e.destinationApplication);
        _validateCommon(e, payload);
    }

    function _validateCommon(Envelope memory e, bytes memory payload) internal pure {
        if (e.messageVersion != MESSAGE_VERSION || e.messageType == MessageType.NONE) revert UnsupportedMessage();
        if (e.operationId == bytes32(0) || e.termsHash == bytes32(0) || e.routeNonce == 0) revert UnsupportedMessage();
        if (e.payloadHash != keccak256(payload)) revert PayloadHashMismatch();
        if (
            e.messageType != MessageType.ROUTE_PULL && e.messageType != MessageType.RESERVE_PUSH
                && e.messageType != MessageType.DESTINATION_RESERVED_ACK
                && e.messageType != MessageType.DESTINATION_DELIVERED_ACK
                && e.messageType != MessageType.RESERVATION_RELEASED_ACK
                && e.messageType != MessageType.DESTINATION_FAILED_ACK
                && e.messageType != MessageType.SOURCE_FINALIZED_RECEIPT
                && e.messageType != MessageType.SOURCE_REFUNDED_RECEIPT
        ) revert UnsupportedMessage();
    }

    function _semanticId(Envelope memory e) internal pure returns (bytes32) {
        return keccak256(abi.encode(e.operationId, e.messageType, e.routeNonce));
    }

    function _safeRefund(address payable to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert RefundFailed();
    }
}
