// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IGlyphMessengerAdapter {
    enum MessageType {
        NONE,
        ROUTE_PULL,
        RESERVE_PUSH,
        DESTINATION_RESERVED_ACK,
        DESTINATION_DELIVERED_ACK,
        RESERVATION_RELEASED_ACK,
        DESTINATION_FAILED_ACK,
        SOURCE_FINALIZED_RECEIPT,
        SOURCE_REFUNDED_RECEIPT
    }

    struct Envelope {
        uint16 messageVersion;
        MessageType messageType;
        bytes32 messageId;
        bytes32 operationId;
        bytes32 termsHash;
        uint64 sourceChainId;
        address sourceApplication;
        uint64 destinationChainId;
        address destinationApplication;
        uint256 routeNonce;
        bytes32 payloadHash;
    }

    event MessageQueued(bytes32 indexed messageId, bytes32 indexed operationId, MessageType indexed messageType);
    event MessageDelivered(bytes32 indexed messageId, bytes32 indexed operationId, MessageType indexed messageType);

    function send(Envelope calldata envelope) external returns (bytes32 messageId);
    function consume(bytes32 messageId) external returns (Envelope memory envelope);
}
