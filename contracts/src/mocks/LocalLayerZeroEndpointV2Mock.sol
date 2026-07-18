// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILayerZeroV2Receiver} from "../interfaces/ILayerZeroV2Endpoint.sol";

contract LocalLayerZeroEndpointV2Mock {
    error InsufficientNativeFee(uint256 required, uint256 supplied);
    error UnknownPacket(bytes32 guid);
    error WrongEndpointAddress(address expected);
    error DuplicateDelivery(bytes32 guid);

    struct Packet {
        uint32 srcEid;
        uint32 dstEid;
        address sender;
        address receiver;
        uint64 nonce;
        uint256 nativeFee;
        bytes message;
        bool exists;
        bool delivered;
    }

    uint32 public immutable eid;
    address public immutable canonicalEndpoint;
    uint64 public nextNonce = 1;
    uint256 public baseFee = 0.01 ether;
    uint256 public gasPriceWei = 1 gwei;
    address public remoteEndpoint;
    mapping(bytes32 => Packet) public packets;

    event PacketSent(bytes32 indexed guid, uint32 indexed dstEid, address indexed receiver, uint256 nativeFee);
    event PacketDelivered(bytes32 indexed guid, address indexed receiver);

    constructor(uint32 localEid, address expectedEndpointAddress) {
        eid = localEid;
        canonicalEndpoint = expectedEndpointAddress;
    }

    function setRemoteEndpoint(address remoteEndpoint_) external {
        remoteEndpoint = remoteEndpoint_;
    }

    function quote(uint32, address, bytes calldata message, uint256 gasLimit) external view returns (uint256) {
        return baseFee + gasLimit * gasPriceWei + message.length * 1e12;
    }

    function send(
        uint32 dstEid,
        address receiver,
        bytes calldata message,
        address payable refundAddress,
        uint256 gasLimit
    ) external payable returns (bytes32 guid, uint64 nonce, uint256 nativeFee) {
        nonce = nextNonce++;
        nativeFee = baseFee + gasLimit * gasPriceWei + message.length * 1e12;
        if (msg.value < nativeFee) revert InsufficientNativeFee(nativeFee, msg.value);
        guid = keccak256(abi.encode("LOCAL_LZ_V2_GUID", eid, dstEid, nonce, msg.sender, receiver, keccak256(message)));
        packets[guid] = Packet(eid, dstEid, msg.sender, receiver, nonce, nativeFee, message, true, false);
        if (remoteEndpoint != address(0)) {
            LocalLayerZeroEndpointV2Mock(remoteEndpoint)
                .mirrorPacket(guid, eid, dstEid, msg.sender, receiver, nonce, nativeFee, message);
        }
        if (msg.value > nativeFee) refundAddress.transfer(msg.value - nativeFee);
        emit PacketSent(guid, dstEid, receiver, nativeFee);
    }

    function mirrorPacket(
        bytes32 guid,
        uint32 srcEid,
        uint32 dstEid,
        address sender,
        address receiver,
        uint64 nonce,
        uint256 nativeFee,
        bytes calldata message
    ) external {
        packets[guid] = Packet(srcEid, dstEid, sender, receiver, nonce, nativeFee, message, true, false);
    }

    function deliver(address expectedSender, address receiver, bytes32 guid, bytes calldata) external {
        Packet storage p = packets[guid];
        if (!p.exists) revert UnknownPacket(guid);
        _deliver(p.srcEid, bytes32(uint256(uint160(expectedSender))), receiver, guid, p.message, p.nonce);
    }

    function deliverWith(address, address receiver, bytes32 guid, bytes calldata, uint32 srcEid, bytes32 sender)
        external
    {
        Packet storage p = packets[guid];
        if (!p.exists) revert UnknownPacket(guid);
        _deliver(srcEid, sender, receiver, guid, p.message, p.nonce);
    }

    function deliverCorrupt(
        address receiver,
        bytes32 guid,
        bytes calldata corruptMessage,
        uint32 srcEid,
        bytes32 sender
    ) external {
        Packet storage p = packets[guid];
        if (!p.exists) revert UnknownPacket(guid);
        _deliver(srcEid, sender, receiver, guid, corruptMessage, p.nonce);
    }

    function _deliver(uint32 srcEid, bytes32 sender, address receiver, bytes32 guid, bytes memory message, uint64 nonce)
        internal
    {
        Packet storage p = packets[guid];
        if (p.delivered) revert DuplicateDelivery(guid);
        p.delivered = true;
        ILayerZeroV2Receiver(receiver)
            .lzReceive(ILayerZeroV2Receiver.Origin(srcEid, sender, nonce), guid, message, address(this), bytes(""));
        emit PacketDelivered(guid, receiver);
    }
}
