// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    ILayerZeroEndpointV2,
    ILayerZeroReceiver,
    MessagingFee,
    MessagingParams,
    MessagingReceipt,
    Origin
} from "../interfaces/ILayerZeroV2Endpoint.sol";

contract LocalLayerZeroEndpointV2Mock is ILayerZeroEndpointV2 {
    error InsufficientNativeFee(uint256 required, uint256 supplied);
    error UnknownPacket(bytes32 guid);
    error WrongEndpointAddress(address expected);
    error DuplicateDelivery(bytes32 guid);
    error UnauthorizedMirror(address caller);
    error WrongDestination(uint32 expected, uint32 actual);
    error WrongReceiver(address expected, address actual);
    error RefundFailed();

    struct Packet {
        uint32 srcEid;
        uint32 dstEid;
        address sender;
        address receiver;
        uint64 nonce;
        uint256 nativeFee;
        bytes message;
        bytes options;
        bool exists;
        bool delivered;
    }

    uint32 public immutable eid;
    address public immutable canonicalEndpoint;
    uint64 public nextOutboundNonce = 1;
    uint256 public baseFee = 0.01 ether;
    uint256 public gasPriceWei = 1 gwei;
    address public remoteEndpoint;
    bytes32 public lastGuid;
    mapping(bytes32 => Packet) public packets;
    mapping(address => address) public delegates;

    event PacketSent(bytes encodedPayload, bytes options, address sendLibrary);
    event PacketVerified(Origin origin, address receiver, bytes32 payloadHash);
    event PacketDelivered(Origin origin, address receiver);
    event LzReceiveAlert(
        address indexed receiver,
        address indexed executor,
        Origin origin,
        bytes32 guid,
        uint256 gas,
        uint256 value,
        bytes message,
        bytes extraData,
        bytes reason
    );
    event LzTokenSet(address token);
    event DelegateSet(address sender, address delegate);
    event LocalPacketRecorded(bytes32 indexed guid, uint32 indexed dstEid, address indexed receiver, uint256 nativeFee);

    constructor(uint32 localEid, address expectedEndpointAddress) {
        eid = localEid;
        canonicalEndpoint = expectedEndpointAddress;
    }

    function setRemoteEndpoint(address remoteEndpoint_) external {
        remoteEndpoint = remoteEndpoint_;
    }

    function quote(MessagingParams calldata params, address) external view returns (MessagingFee memory fee) {
        fee.nativeFee = baseFee + params.options.length * 1e10 + params.message.length * 1e12;
    }

    function send(MessagingParams calldata params, address refundAddress)
        external
        payable
        returns (MessagingReceipt memory receipt)
    {
        bytes memory message = params.message;
        bytes memory options = params.options;
        uint32 dstEid = params.dstEid;
        bytes32 receiverBytes = params.receiver;
        MessagingFee memory fee = this.quote(params, msg.sender);
        if (msg.value < fee.nativeFee) revert InsufficientNativeFee(fee.nativeFee, msg.value);
        address receiver = address(uint160(uint256(receiverBytes)));
        uint64 nonce = nextOutboundNonce++;
        bytes32 guid =
            keccak256(abi.encode("LOCAL_LZ_V2_GUID", eid, dstEid, nonce, msg.sender, receiver, keccak256(message)));
        packets[guid] = Packet(eid, dstEid, msg.sender, receiver, nonce, fee.nativeFee, message, options, true, false);
        lastGuid = guid;
        if (remoteEndpoint != address(0)) {
            _mirror(guid);
        }
        uint256 excess = msg.value - fee.nativeFee;
        if (excess != 0) {
            (bool ok,) = payable(refundAddress).call{value: excess}("");
            if (!ok) revert RefundFailed();
        }
        receipt = MessagingReceipt(guid, nonce, fee);
        emit LocalPacketRecorded(guid, params.dstEid, receiver, fee.nativeFee);
        emit PacketSent(abi.encode(params.dstEid, params.receiver, params.message), params.options, address(this));
    }

    function _mirror(bytes32 guid) internal {
        Packet storage p = packets[guid];
        LocalLayerZeroEndpointV2Mock(remoteEndpoint)
            .mirrorPacket(guid, p.srcEid, p.dstEid, p.sender, p.receiver, p.nonce, p.nativeFee, p.message, p.options);
    }

    function mirrorPacket(
        bytes32 guid,
        uint32 srcEid,
        uint32 dstEid,
        address sender,
        address receiver,
        uint64 nonce,
        uint256 nativeFee,
        bytes calldata message,
        bytes calldata options
    ) external {
        if (msg.sender != remoteEndpoint) revert UnauthorizedMirror(msg.sender);
        if (dstEid != eid) revert WrongDestination(eid, dstEid);
        packets[guid] = Packet(srcEid, dstEid, sender, receiver, nonce, nativeFee, message, options, true, false);
    }

    function packetMessage(bytes32 guid) external view returns (bytes memory) {
        Packet storage p = packets[guid];
        if (!p.exists) revert UnknownPacket(guid);
        return p.message;
    }

    function deliver(address receiver, bytes32 guid) external {
        Packet storage p = packets[guid];
        if (!p.exists) revert UnknownPacket(guid);
        if (p.receiver != receiver) revert WrongReceiver(p.receiver, receiver);
        _deliver(p.srcEid, bytes32(uint256(uint160(p.sender))), receiver, guid, p.message, p.nonce);
    }

    function deliverCorrupt(address receiver, bytes32 guid, bytes calldata corruptMessage) external {
        Packet storage p = packets[guid];
        if (!p.exists) revert UnknownPacket(guid);
        if (p.receiver != receiver) revert WrongReceiver(p.receiver, receiver);
        _deliver(p.srcEid, bytes32(uint256(uint160(p.sender))), receiver, guid, corruptMessage, p.nonce);
    }

    function deliverWithForgedOrigin(address receiver, bytes32 guid, uint32 srcEid, bytes32 sender) external {
        Packet storage p = packets[guid];
        if (!p.exists) revert UnknownPacket(guid);
        if (p.receiver != receiver) revert WrongReceiver(p.receiver, receiver);
        _deliver(srcEid, sender, receiver, guid, p.message, p.nonce);
    }

    function _deliver(uint32 srcEid, bytes32 sender, address receiver, bytes32 guid, bytes memory message, uint64 nonce)
        internal
    {
        Packet storage p = packets[guid];
        if (p.delivered) revert DuplicateDelivery(guid);
        p.delivered = true;
        Origin memory origin = Origin(srcEid, sender, nonce);
        ILayerZeroReceiver(receiver).lzReceive(origin, guid, message, address(this), bytes(""));
        emit PacketDelivered(origin, receiver);
    }

    function verify(Origin calldata origin, address receiver, bytes32 payloadHash) external {
        emit PacketVerified(origin, receiver, payloadHash);
    }

    function verifiable(Origin calldata, address) external pure returns (bool) {
        return true;
    }

    function initializable(Origin calldata, address) external pure returns (bool) {
        return true;
    }

    function lzReceive(
        Origin calldata origin,
        address receiver,
        bytes32 guid,
        bytes calldata message,
        bytes calldata extraData
    ) external payable {
        ILayerZeroReceiver(receiver).lzReceive{value: msg.value}(origin, guid, message, msg.sender, extraData);
    }

    function clear(address, Origin calldata, bytes32, bytes calldata) external pure {}

    function setLzToken(address token) external {
        emit LzTokenSet(token);
    }

    function lzToken() external pure returns (address) {
        return address(0);
    }

    function nativeToken() external pure returns (address) {
        return address(0);
    }

    function setDelegate(address delegate) external {
        delegates[msg.sender] = delegate;
        emit DelegateSet(msg.sender, delegate);
    }
}
