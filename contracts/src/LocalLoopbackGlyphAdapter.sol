// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGlyphMessengerAdapter} from "./interfaces/IGlyphMessengerAdapter.sol";

/// @notice Local loopback messenger for same-chain proofs.
/// @dev Messages are staged by `sendMessage` and delivered by `deliver(messageId)`.
/// This preserves production ordering: the source app records route facts after
/// `sendMessage` returns, then a relayer/test script delivers the staged message.
contract LocalLoopbackGlyphAdapter is IGlyphMessengerAdapter {
    struct PendingMessage {
        address destinationApplication;
        Envelope envelope;
        bytes payload;
        bool exists;
    }

    mapping(bytes32 => PendingMessage) public pending;
    bytes32 public lastMessageId;

    function quote(uint64, address, Envelope calldata, bytes calldata, uint256) external pure returns (uint256) {
        return 0;
    }

    function sendMessage(
        uint64,
        address destinationApplication,
        Envelope calldata e,
        bytes calldata payload,
        address payable,
        uint256
    ) external payable returns (bytes32 messageId) {
        messageId = keccak256(abi.encode(e.operationId, e.messageType, e.routeNonce, e.payloadHash, address(this)));
        Envelope memory staged = e;
        staged.messageId = messageId;
        if (pending[messageId].exists) revert("loopback: duplicate message");
        pending[messageId] = PendingMessage({
            destinationApplication: destinationApplication, envelope: staged, payload: payload, exists: true
        });
        lastMessageId = messageId;
        emit MessageQueued(messageId, e.operationId, e.messageType);
    }

    function deliver(bytes32 messageId) external {
        PendingMessage memory p = pending[messageId];
        if (!p.exists) revert("loopback: missing message");
        delete pending[messageId];
        (bool ok, bytes memory ret) = p.destinationApplication
            .call(abi.encodeWithSelector(IGlyphMessageHandler.handleGlyphMessage.selector, p.envelope, p.payload));
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        emit MessageDelivered(messageId, p.envelope.operationId, p.envelope.messageType);
    }

    function consume(bytes32 messageId) external returns (Envelope memory envelope) {
        PendingMessage memory p = pending[messageId];
        if (!p.exists) revert("loopback: missing message");
        delete pending[messageId];
        return p.envelope;
    }
}

interface IGlyphMessageHandler {
    function handleGlyphMessage(IGlyphMessengerAdapter.Envelope calldata envelope, bytes calldata payload) external;
}
