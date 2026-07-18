// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGlyphMessengerAdapter} from "./interfaces/IGlyphMessengerAdapter.sol";

contract MockGlyphMessengerAdapter is IGlyphMessengerAdapter {
    mapping(bytes32 => Envelope) public queued;
    mapping(bytes32 => bool) public consumed;

    error Duplicate();
    error MutatedEnvelope();
    error Unknown();

    function quote(uint64, address, Envelope calldata, bytes calldata, uint256) external pure returns (uint256) {
        return 0;
    }

    function sendMessage(uint64, address, Envelope calldata e, bytes calldata, address payable, uint256)
        external
        payable
        returns (bytes32 messageId)
    {
        return _send(e);
    }

    function _send(Envelope calldata e) internal returns (bytes32 messageId) {
        if (e.messageVersion != 1 || e.messageType == MessageType.NONE) revert MutatedEnvelope();
        messageId = keccak256(abi.encode(e.operationId, e.messageType, e.routeNonce, e.payloadHash, address(this)));
        if (queued[messageId].messageVersion != 0) revert Duplicate();
        Envelope memory stored = e;
        stored.messageId = messageId;
        queued[messageId] = stored;
        emit MessageQueued(messageId, e.operationId, e.messageType);
    }

    function consume(bytes32 messageId) external returns (Envelope memory envelope) {
        envelope = queued[messageId];
        if (envelope.messageVersion == 0 || consumed[messageId]) revert Unknown();
        consumed[messageId] = true;
        emit MessageDelivered(messageId, envelope.operationId, envelope.messageType);
    }
}
