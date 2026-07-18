// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Minimal verbatim ABI subset from @layerzerolabs/lz-evm-protocol-v2@3.0.168
// contracts/interfaces/ILayerZeroEndpointV2.sol and ILayerZeroReceiver.sol.
// Source tarball: https://registry.npmjs.org/@layerzerolabs/lz-evm-protocol-v2/-/lz-evm-protocol-v2-3.0.168.tgz
// Tarball SHA-256: 4f8fcf8173a0ff841a6e9f6891662eeaea6a44b2af410298b921a43169f6485c
// License: MIT for interfaces in this file; package license LZBL-1.2.

struct MessagingParams {
    uint32 dstEid;
    bytes32 receiver;
    bytes message;
    bytes options;
    bool payInLzToken;
}

struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    MessagingFee fee;
}

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}

interface ILayerZeroEndpointV2 {
    function quote(MessagingParams calldata _params, address _sender) external view returns (MessagingFee memory);

    function send(MessagingParams calldata _params, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory);

    function verify(Origin calldata _origin, address _receiver, bytes32 _payloadHash) external;
    function verifiable(Origin calldata _origin, address _receiver) external view returns (bool);
    function initializable(Origin calldata _origin, address _receiver) external view returns (bool);

    function lzReceive(
        Origin calldata _origin,
        address _receiver,
        bytes32 _guid,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable;

    function clear(address _oapp, Origin calldata _origin, bytes32 _guid, bytes calldata _message) external;
    function setLzToken(address _lzToken) external;
    function lzToken() external view returns (address);
    function nativeToken() external view returns (address);
    function setDelegate(address _delegate) external;
}

interface ILayerZeroReceiver {
    function allowInitializePath(Origin calldata _origin) external view returns (bool);
    function nextNonce(uint32 _eid, bytes32 _sender) external view returns (uint64);

    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable;
}
