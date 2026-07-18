// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal reviewed LayerZero V2-compatible surface used by the Glyph adapter.
/// This local interface intentionally contains only endpoint/OApp fields required by
/// the deploy-ready adapter gate: endpoint fee quote/send and authenticated lzReceive
/// Origin context (srcEid, sender, nonce) plus GUID.
interface ILayerZeroV2Receiver {
    struct Origin {
        uint32 srcEid;
        bytes32 sender;
        uint64 nonce;
    }

    function lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) external;
}

interface ILayerZeroEndpointV2Like {
    function quote(uint32 dstEid, address receiver, bytes calldata message, uint256 gasLimit)
        external
        view
        returns (uint256 nativeFee);

    function send(
        uint32 dstEid,
        address receiver,
        bytes calldata message,
        address payable refundAddress,
        uint256 gasLimit
    ) external payable returns (bytes32 guid, uint64 nonce, uint256 nativeFee);
}
