// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGlyphMessengerAdapter} from "./interfaces/IGlyphMessengerAdapter.sol";
import {ILayerZeroEndpointV2Like, ILayerZeroV2Receiver} from "./interfaces/ILayerZeroV2Endpoint.sol";

interface IGlyphMessageHandler {
    function handleGlyphMessage(IGlyphMessengerAdapter.Envelope calldata envelope, bytes calldata payload) external;
}

contract LayerZeroV2GlyphMessengerAdapter is IGlyphMessengerAdapter, ILayerZeroV2Receiver {
    enum MessageStatus {
        NONE,
        SENT,
        STAGED,
        PROCESSED,
        FAILED
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

    uint16 public constant MESSAGE_VERSION = 1;
    bytes32 public constant PROOF_KIND = keccak256("AUTHENTICATED_ADAPTER");
    address public immutable endpoint;
    uint64 public immutable localChainId;
    uint64 public immutable remoteChainId;
    uint32 public immutable localEid;
    uint32 public immutable remoteEid;
    bytes32 public immutable messengerPolicyHash;
    address public owner;
    address public trustedPeer;
    address public localApplication;
    address public remoteApplication;
    uint256 public enforcedGasLimit = 200_000;

    mapping(bytes32 => Envelope) public envelopes;
    mapping(bytes32 => bytes) public payloads;
    mapping(bytes32 => MessageStatus) public messageStatus;
    mapping(bytes32 => bool) public consumedSemantic;

    event TrustedPeerSet(address indexed peer);
    event ApplicationsSet(address indexed localApplication, address indexed remoteApplication);
    event EnforcedGasLimitSet(uint256 gasLimit);
    event MessageStaged(bytes32 indexed messageId, bytes32 indexed operationId);
    event MessageProcessingFailed(bytes32 indexed messageId, bytes reason);
    event MessageProcessed(bytes32 indexed messageId, bytes32 indexed operationId);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
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
        messengerPolicyHash = messengerPolicyHash_;
    }

    receive() external payable {}

    function transferOwnership(address nextOwner) external onlyOwner {
        if (nextOwner == address(0)) revert InvalidConfig();
        owner = nextOwner;
    }

    function setTrustedPeer(address peer) external onlyOwner {
        if (peer == address(0)) revert InvalidConfig();
        trustedPeer = peer;
        emit TrustedPeerSet(peer);
    }

    function setLocalApplication(address app) external onlyOwner {
        if (app == address(0)) revert InvalidConfig();
        localApplication = app;
        emit ApplicationsSet(localApplication, remoteApplication);
    }

    function setRemoteApplication(address app) external onlyOwner {
        if (app == address(0)) revert InvalidConfig();
        remoteApplication = app;
        emit ApplicationsSet(localApplication, remoteApplication);
    }

    function setEnforcedGasLimit(uint256 gasLimit) external onlyOwner {
        if (gasLimit < 50_000 || gasLimit > 5_000_000) revert InvalidConfig();
        enforcedGasLimit = gasLimit;
        emit EnforcedGasLimitSet(gasLimit);
    }

    function quote(
        uint64 destinationChainId,
        address destinationApplication,
        Envelope memory envelope,
        bytes memory payload,
        uint256 gasLimit
    ) public view returns (uint256 nativeFee) {
        _validateOutbound(destinationChainId, destinationApplication, envelope, payload);
        if (gasLimit < enforcedGasLimit) revert InvalidConfig();
        nativeFee =
            ILayerZeroEndpointV2Like(endpoint).quote(remoteEid, trustedPeer, abi.encode(envelope, payload), gasLimit);
    }

    function send(
        uint64 destinationChainId,
        address destinationApplication,
        Envelope memory envelope,
        bytes memory payload,
        address payable refundAddress,
        uint256 gasLimit
    ) public payable returns (bytes32 messageId) {
        _validateOutbound(destinationChainId, destinationApplication, envelope, payload);
        if (gasLimit < enforcedGasLimit || refundAddress == address(0)) revert InvalidConfig();
        bytes32 semanticId = _semanticId(envelope);
        if (consumedSemantic[semanticId]) revert DuplicateSemantic(semanticId);
        uint256 nativeFee = quote(destinationChainId, destinationApplication, envelope, payload, gasLimit);
        if (msg.value < nativeFee) revert InsufficientNativeFee(nativeFee, msg.value);
        (messageId,,) = ILayerZeroEndpointV2Like(endpoint).send{value: nativeFee}(
            remoteEid, trustedPeer, abi.encode(envelope, payload), refundAddress, gasLimit
        );
        if (messageStatus[messageId] != MessageStatus.NONE) revert DuplicateMessage(messageId);
        envelope.messageId = messageId;
        envelopes[messageId] = envelope;
        payloads[messageId] = payload;
        messageStatus[messageId] = MessageStatus.SENT;
        consumedSemantic[semanticId] = true;
        if (msg.value > nativeFee) refundAddress.transfer(msg.value - nativeFee);
        emit MessageQueued(messageId, envelope.operationId, envelope.messageType);
    }

    function send(Envelope calldata envelope) external returns (bytes32 messageId) {
        bytes memory payload = payloads[envelope.messageId];
        return send(
            envelope.destinationChainId,
            envelope.destinationApplication,
            envelope,
            payload,
            payable(msg.sender),
            enforcedGasLimit
        );
    }

    function lzReceive(Origin calldata origin, bytes32 guid, bytes calldata message, address, bytes calldata)
        external
        override
    {
        if (msg.sender != endpoint) revert WrongEndpoint(msg.sender);
        if (origin.srcEid != remoteEid) revert WrongEid(origin.srcEid);
        if (origin.sender != bytes32(uint256(uint160(trustedPeer)))) revert WrongPeer(origin.sender);
        if (messageStatus[guid] != MessageStatus.NONE) revert DuplicateMessage(guid);
        (Envelope memory envelope, bytes memory payload) = abi.decode(message, (Envelope, bytes));
        envelope.messageId = guid;
        _validateInbound(envelope, payload);
        bytes32 semanticId = _semanticId(envelope);
        if (consumedSemantic[semanticId]) revert DuplicateSemantic(semanticId);
        consumedSemantic[semanticId] = true;
        envelopes[guid] = envelope;
        payloads[guid] = payload;
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

    function consume(bytes32 messageId) external returns (Envelope memory envelope) {
        if (messageStatus[messageId] == MessageStatus.NONE) revert UnknownMessage(messageId);
        if (messageStatus[messageId] == MessageStatus.PROCESSED) revert DuplicateMessage(messageId);
        envelope = envelopes[messageId];
        messageStatus[messageId] = MessageStatus.PROCESSED;
        emit MessageDelivered(messageId, envelope.operationId, envelope.messageType);
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
        Envelope memory e,
        bytes memory payload
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
}
