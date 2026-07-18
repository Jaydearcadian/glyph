// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGlyphMessengerAdapter} from "./interfaces/IGlyphMessengerAdapter.sol";

contract MockGlyphMessengerAdapter is IGlyphMessengerAdapter {
    error DuplicateMessage(bytes32 messageId);
    error UnknownMessage(bytes32 messageId);
    error MutatedEnvelope();

    mapping(bytes32 => Envelope) public queued;
    mapping(bytes32 => bool) public exists;
    mapping(bytes32 => bool) public consumed;
    bool public mutateNext;

    function setMutateNext(bool value) external {
        mutateNext = value;
    }

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

    function send(Envelope calldata e) external returns (bytes32 messageId) {
        return _send(e);
    }

    function _send(Envelope calldata e) internal returns (bytes32 messageId) {
        if (e.messageVersion != 1 || e.messageType == MessageType.NONE) revert MutatedEnvelope();
        messageId = e.messageId == bytes32(0) ? keccak256(abi.encode(e)) : e.messageId;
        if (exists[messageId]) revert DuplicateMessage(messageId);
        queued[messageId] = e;
        queued[messageId].messageId = messageId;
        exists[messageId] = true;
        emit MessageQueued(messageId, e.operationId, e.messageType);
    }

    function consume(bytes32 messageId) external returns (Envelope memory e) {
        if (!exists[messageId]) revert UnknownMessage(messageId);
        if (consumed[messageId]) revert DuplicateMessage(messageId);
        consumed[messageId] = true;
        e = queued[messageId];
        if (mutateNext) {
            mutateNext = false;
            e.payloadHash = keccak256("mutated");
        }
        emit MessageDelivered(messageId, e.operationId, e.messageType);
    }
}
