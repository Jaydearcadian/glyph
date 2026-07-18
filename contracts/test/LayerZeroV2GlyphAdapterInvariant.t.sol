// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LayerZeroV2GlyphMessengerAdapter} from "../src/LayerZeroV2GlyphMessengerAdapter.sol";
import {LocalLayerZeroEndpointV2Mock} from "../src/mocks/LocalLayerZeroEndpointV2Mock.sol";
import {IGlyphMessengerAdapter} from "../src/interfaces/IGlyphMessengerAdapter.sol";

contract AdapterInvariantHandler {
    LayerZeroV2GlyphMessengerAdapter public adapter;
    uint256 public outsiderAttempts;

    constructor(LayerZeroV2GlyphMessengerAdapter adapter_) {
        adapter = adapter_;
    }

    function outsiderConsume(bytes32 messageId) external {
        outsiderAttempts++;
        try adapter.consume(messageId) returns (IGlyphMessengerAdapter.Envelope memory) {
            revert("consume bypass");
        } catch {}
    }

    function outsiderSend(bytes32 op, bytes32 termsHash, bytes32 payloadHash, uint256 routeNonce) external payable {
        outsiderAttempts++;
        IGlyphMessengerAdapter.Envelope memory e = IGlyphMessengerAdapter.Envelope({
            messageVersion: 1,
            messageType: IGlyphMessengerAdapter.MessageType.ROUTE_PULL,
            messageId: bytes32(0),
            operationId: op == bytes32(0) ? bytes32(uint256(1)) : op,
            termsHash: termsHash == bytes32(0) ? bytes32(uint256(1)) : termsHash,
            sourceChainId: 84532,
            sourceApplication: address(0x1111),
            destinationChainId: 10143,
            destinationApplication: address(0x2222),
            routeNonce: routeNonce == 0 ? 1 : routeNonce,
            payloadHash: payloadHash
        });
        try adapter.sendMessage{value: msg.value}(
            10143, address(0x2222), e, bytes("payload"), payable(msg.sender), 200_000
        ) returns (
            bytes32
        ) {
            revert("send bypass");
        } catch {}
    }
}

contract LayerZeroV2GlyphAdapterInvariantTest is Test {
    LocalLayerZeroEndpointV2Mock endpoint;
    LayerZeroV2GlyphMessengerAdapter adapter;
    AdapterInvariantHandler handler;
    bytes32 policy = keccak256("glyph-lz-v2-policy:invariant");

    function setUp() public {
        endpoint = new LocalLayerZeroEndpointV2Mock(40245, address(0x1234));
        adapter =
            new LayerZeroV2GlyphMessengerAdapter(address(endpoint), 84532, 40245, 10143, 40204, address(this), policy);
        adapter.setTrustedPeer(address(0x3333));
        adapter.setLocalApplication(address(0x1111));
        adapter.setRemoteApplication(address(0x2222));
        handler = new AdapterInvariantHandler(adapter);
        vm.deal(address(handler), 100 ether);
        targetContract(address(handler));
    }

    function testFuzz_buildOptionsRejectsBelowPolicyAndEncodesOrdered(uint256 gasLimit) public {
        gasLimit = bound(gasLimit, 200_000, 5_000_000);
        bytes memory options = adapter.buildOptions(gasLimit);
        assertEq(uint8(options[2]), uint8(1));
        assertEq(uint8(options[5]), uint8(1));
        assertEq(uint8(options[38]), uint8(1));
        assertEq(uint8(options[41]), uint8(4));
    }

    function testFuzz_outsiderCannotConsumeOrSend(bytes32 messageId) public {
        vm.expectRevert(LayerZeroV2GlyphMessengerAdapter.Unauthorized.selector);
        adapter.consume(messageId);
    }

    function invariant_adapterOutsidersCannotStageMessagesOrTrapNative() public view {
        assertEq(
            uint8(adapter.messageStatus(bytes32(uint256(1)))),
            uint8(LayerZeroV2GlyphMessengerAdapter.MessageStatus.NONE)
        );
        assertEq(address(adapter).balance, 0);
        assertEq(endpoint.nextOutboundNonce(), 1);
    }
}
