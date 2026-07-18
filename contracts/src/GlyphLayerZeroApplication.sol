// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DestinationGlyphVault} from "./DestinationGlyphVault.sol";
import {SourceDeltaRouter} from "./SourceDeltaRouter.sol";
import {IGlyphMessengerAdapter} from "./interfaces/IGlyphMessengerAdapter.sol";
import {IERC20Minimal} from "./libraries/SafeToken.sol";

contract GlyphLayerZeroApplication {
    enum Side {
        SOURCE,
        DESTINATION
    }

    struct RoutePayload {
        address asset;
        address recipient;
        uint256 amount;
        uint64 expiry;
        bytes32 claimantRule;
    }

    error Unauthorized();
    error InvalidConfig();
    error UnsupportedMessage();
    error InvalidPayload();
    error AckSendFailed();

    uint16 public constant MESSAGE_VERSION = 1;

    Side public immutable side;
    uint64 public immutable localChainId;
    uint64 public immutable remoteChainId;
    SourceDeltaRouter public immutable router;
    DestinationGlyphVault public immutable vault;
    IGlyphMessengerAdapter public adapter;
    address public owner;
    address public remoteApplication;
    uint256 public nextRouteNonce = 1;
    uint256 public ackGasLimit = 200_000;

    event AdapterSet(address indexed adapter);
    event RemoteApplicationSet(address indexed remoteApplication);
    event RouteSent(
        bytes32 indexed messageId, bytes32 indexed operationId, IGlyphMessengerAdapter.MessageType messageType
    );
    event AckSent(
        bytes32 indexed messageId, bytes32 indexed operationId, IGlyphMessengerAdapter.MessageType messageType
    );
    event InboundHandled(bytes32 indexed operationId, IGlyphMessengerAdapter.MessageType messageType);
    event InboundFailed(bytes32 indexed operationId, bytes reason);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyAdapter() {
        if (msg.sender != address(adapter)) revert Unauthorized();
        _;
    }

    constructor(
        Side side_,
        uint64 localChainId_,
        uint64 remoteChainId_,
        SourceDeltaRouter router_,
        DestinationGlyphVault vault_,
        address owner_
    ) {
        if (localChainId_ == 0 || remoteChainId_ == 0 || owner_ == address(0)) {
            revert InvalidConfig();
        }
        side = side_;
        localChainId = localChainId_;
        remoteChainId = remoteChainId_;
        router = router_;
        vault = vault_;
        owner = owner_;
    }

    receive() external payable {}

    function transferOwnership(address nextOwner) external onlyOwner {
        if (nextOwner == address(0)) revert InvalidConfig();
        owner = nextOwner;
    }

    function setAdapter(IGlyphMessengerAdapter adapter_) external onlyOwner {
        if (address(adapter_) == address(0)) revert InvalidConfig();
        adapter = adapter_;
        emit AdapterSet(address(adapter_));
    }

    function setRemoteApplication(address remoteApplication_) external onlyOwner {
        if (remoteApplication_ == address(0)) revert InvalidConfig();
        remoteApplication = remoteApplication_;
        emit RemoteApplicationSet(remoteApplication_);
    }

    function setAckGasLimit(uint256 gasLimit) external onlyOwner {
        if (gasLimit < 50_000 || gasLimit > 5_000_000) revert InvalidConfig();
        ackGasLimit = gasLimit;
    }

    function quoteRoute(
        IGlyphMessengerAdapter.MessageType messageType,
        bytes32 operationId,
        bytes32 termsHash,
        RoutePayload calldata route,
        uint256 gasLimit
    ) external view returns (uint256) {
        bytes memory payload = abi.encode(route.asset, route.recipient, route.amount, route.expiry, route.claimantRule);
        IGlyphMessengerAdapter.Envelope memory envelope =
            _envelope(messageType, operationId, termsHash, nextRouteNonce, payload);
        return adapter.quote(remoteChainId, remoteApplication, envelope, payload, gasLimit);
    }

    function sendRoute(
        IGlyphMessengerAdapter.MessageType messageType,
        bytes32 operationId,
        bytes32 termsHash,
        RoutePayload calldata route,
        address payable refundAddress,
        uint256 gasLimit
    ) external payable onlyOwner returns (bytes32 messageId) {
        if (
            messageType != IGlyphMessengerAdapter.MessageType.ROUTE_PULL
                && messageType != IGlyphMessengerAdapter.MessageType.RESERVE_PUSH
        ) {
            revert UnsupportedMessage();
        }
        bytes memory payload = abi.encode(route.asset, route.recipient, route.amount, route.expiry, route.claimantRule);
        IGlyphMessengerAdapter.Envelope memory envelope =
            _envelope(messageType, operationId, termsHash, nextRouteNonce++, payload);
        messageId = adapter.sendMessage{value: msg.value}(
            remoteChainId, remoteApplication, envelope, payload, refundAddress, gasLimit
        );
        emit RouteSent(messageId, operationId, messageType);
    }

    function handleGlyphMessage(IGlyphMessengerAdapter.Envelope calldata envelope, bytes calldata payload)
        external
        onlyAdapter
    {
        if (keccak256(payload) != envelope.payloadHash) revert InvalidPayload();
        if (side == Side.DESTINATION) {
            _handleDestination(envelope, payload);
        } else {
            _handleSource(envelope, payload);
        }
        emit InboundHandled(envelope.operationId, envelope.messageType);
    }

    function claimPushAndAck(
        bytes32 operationId,
        address claimant,
        bytes32 nullifier,
        uint64 deadline,
        bytes calldata signature
    ) external payable returns (bytes32 ackId) {
        if (side != Side.DESTINATION) revert UnsupportedMessage();
        vault.claimPush(operationId, claimant, nullifier, deadline, signature);
        ackId = _sendAck(
            operationId,
            bytes32(0),
            IGlyphMessengerAdapter.MessageType.DESTINATION_DELIVERED_ACK,
            abi.encode(operationId, nullifier)
        );
    }

    function releaseAndAck(bytes32 operationId) external payable returns (bytes32 ackId) {
        if (side != Side.DESTINATION) revert UnsupportedMessage();
        vault.release(operationId);
        ackId = _sendAck(
            operationId,
            bytes32(0),
            IGlyphMessengerAdapter.MessageType.RESERVATION_RELEASED_ACK,
            abi.encode(operationId)
        );
    }

    function _handleDestination(IGlyphMessengerAdapter.Envelope calldata envelope, bytes calldata payload) internal {
        if (
            envelope.messageType != IGlyphMessengerAdapter.MessageType.ROUTE_PULL
                && envelope.messageType != IGlyphMessengerAdapter.MessageType.RESERVE_PUSH
        ) {
            revert UnsupportedMessage();
        }
        (address asset, address recipient, uint256 amount, uint64 expiry, bytes32 claimantRule) =
            abi.decode(payload, (address, address, uint256, uint64, bytes32));
        try this.executeDestination(
            envelope.messageType,
            envelope.operationId,
            asset,
            recipient,
            amount,
            envelope.sourceChainId,
            envelope.sourceApplication,
            expiry,
            claimantRule
        ) {
            IGlyphMessengerAdapter.MessageType ackType = envelope.messageType
                == IGlyphMessengerAdapter.MessageType.ROUTE_PULL
                ? IGlyphMessengerAdapter.MessageType.DESTINATION_DELIVERED_ACK
                : IGlyphMessengerAdapter.MessageType.DESTINATION_RESERVED_ACK;
            _sendAck(
                envelope.operationId,
                envelope.termsHash,
                ackType,
                abi.encode(envelope.operationId, envelope.messageId, ackType)
            );
        } catch (bytes memory reason) {
            emit InboundFailed(envelope.operationId, reason);
            _sendAck(
                envelope.operationId,
                envelope.termsHash,
                IGlyphMessengerAdapter.MessageType.DESTINATION_FAILED_ACK,
                abi.encode(envelope.operationId, envelope.messageId, keccak256(reason))
            );
        }
    }

    function executeDestination(
        IGlyphMessengerAdapter.MessageType messageType,
        bytes32 operationId,
        address asset,
        address recipient,
        uint256 amount,
        uint64 sourceChainId,
        address sourceApplication,
        uint64 expiry,
        bytes32 claimantRule
    ) external {
        if (msg.sender != address(this)) revert Unauthorized();
        if (asset == address(0) || recipient == address(0) || amount == 0 || sourceApplication != remoteApplication) {
            revert InvalidPayload();
        }
        if (messageType == IGlyphMessengerAdapter.MessageType.ROUTE_PULL) {
            vault.reservePull(operationId, asset, recipient, amount, sourceChainId, sourceApplication, expiry);
            vault.deliverPull(operationId, sourceChainId, sourceApplication);
        } else if (messageType == IGlyphMessengerAdapter.MessageType.RESERVE_PUSH) {
            vault.reservePush(
                operationId, asset, recipient, amount, sourceChainId, sourceApplication, expiry, claimantRule
            );
        } else {
            revert UnsupportedMessage();
        }
    }

    function _handleSource(IGlyphMessengerAdapter.Envelope calldata envelope, bytes calldata) internal {
        if (
            envelope.messageType == IGlyphMessengerAdapter.MessageType.DESTINATION_DELIVERED_ACK
                || envelope.messageType == IGlyphMessengerAdapter.MessageType.DESTINATION_RESERVED_ACK
        ) {
            router.acknowledgeDeliveryFromAdapter(envelope.operationId, envelope.messageId, address(adapter));
        } else if (
            envelope.messageType == IGlyphMessengerAdapter.MessageType.DESTINATION_FAILED_ACK
                || envelope.messageType == IGlyphMessengerAdapter.MessageType.RESERVATION_RELEASED_ACK
        ) {
            router.markRefundPendingFromAdapter(envelope.operationId, address(adapter));
        } else if (
            envelope.messageType == IGlyphMessengerAdapter.MessageType.SOURCE_FINALIZED_RECEIPT
                || envelope.messageType == IGlyphMessengerAdapter.MessageType.SOURCE_REFUNDED_RECEIPT
        ) {
            return;
        } else {
            revert UnsupportedMessage();
        }
    }

    function _sendAck(
        bytes32 operationId,
        bytes32 termsHash,
        IGlyphMessengerAdapter.MessageType messageType,
        bytes memory payload
    ) internal returns (bytes32 messageId) {
        IGlyphMessengerAdapter.Envelope memory ack = _envelope(
            messageType,
            operationId,
            termsHash == bytes32(0) ? bytes32(uint256(1)) : termsHash,
            nextRouteNonce++,
            payload
        );
        uint256 fee = adapter.quote(remoteChainId, remoteApplication, ack, payload, ackGasLimit);
        if (address(this).balance < fee) revert AckSendFailed();
        messageId = adapter.sendMessage{value: fee}(
            remoteChainId, remoteApplication, ack, payload, payable(owner), ackGasLimit
        );
        emit AckSent(messageId, operationId, messageType);
    }

    function _envelope(
        IGlyphMessengerAdapter.MessageType messageType,
        bytes32 operationId,
        bytes32 termsHash,
        uint256 routeNonce,
        bytes memory payload
    ) internal view returns (IGlyphMessengerAdapter.Envelope memory) {
        if (remoteApplication == address(0) || address(adapter) == address(0)) {
            revert InvalidConfig();
        }
        return IGlyphMessengerAdapter.Envelope({
            messageVersion: MESSAGE_VERSION,
            messageType: messageType,
            messageId: bytes32(0),
            operationId: operationId,
            termsHash: termsHash,
            sourceChainId: localChainId,
            sourceApplication: address(this),
            destinationChainId: remoteChainId,
            destinationApplication: remoteApplication,
            routeNonce: routeNonce,
            payloadHash: keccak256(payload)
        });
    }
}
