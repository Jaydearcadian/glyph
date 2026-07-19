// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGlyphMessengerAdapter} from "./interfaces/IGlyphMessengerAdapter.sol";

/// @notice Synchronous local loopback messenger. Used for same-chain (Monad->Monad)
/// Pull/Push so the full value loop completes in a single transaction with no external relay.
/// Delivers the message to `destinationApplication` inline via a low-level call.
contract LocalLoopbackGlyphAdapter is IGlyphMessengerAdapter {
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
        Envelope memory delivered = e;
        delivered.messageId = messageId;
        // Synchronous delivery: invoke the destination app's handler inline with the final messageId.
        (bool ok, bytes memory ret) = destinationApplication.call(
            abi.encodeWithSelector(IGlyphMessageHandler.handleGlyphMessage.selector, delivered, payload)
        );
        if (!ok) {
            // Bubble up revert reason if present
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        emit MessageQueued(messageId, e.operationId, e.messageType);
        emit MessageDelivered(messageId, e.operationId, e.messageType);
    }

    function consume(bytes32) external pure returns (Envelope memory) {
        revert("loopback: no async consume");
    }
}

interface IGlyphMessageHandler {
    function handleGlyphMessage(IGlyphMessengerAdapter.Envelope calldata envelope, bytes calldata payload) external;
}
