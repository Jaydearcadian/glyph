// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {LayerZeroV2GlyphMessengerAdapter} from "../src/LayerZeroV2GlyphMessengerAdapter.sol";
import {LocalLayerZeroEndpointV2Mock} from "../src/mocks/LocalLayerZeroEndpointV2Mock.sol";
import {IGlyphMessengerAdapter} from "../src/interfaces/IGlyphMessengerAdapter.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";
import {TestToken} from "./mocks/TestToken.sol";

contract GlyphLzAppHarness {
    DestinationGlyphVault public vault;
    SourceDeltaRouter public router;
    address public adapter;
    bool public failNext;

    constructor(DestinationGlyphVault v, SourceDeltaRouter r, address a) {
        vault = v;
        router = r;
        adapter = a;
    }

    function setAdapter(address a) external {
        adapter = a;
    }

    function setFailNext(bool value) external {
        failNext = value;
    }

    function handleGlyphMessage(IGlyphMessengerAdapter.Envelope calldata e, bytes calldata payload) external {
        require(msg.sender == adapter, "only adapter");
        require(keccak256(payload) == e.payloadHash, "payload hash");
        if (failNext) {
            failNext = false;
            revert("handler failure");
        }
        if (e.messageType == IGlyphMessengerAdapter.MessageType.ROUTE_PULL) {
            (address asset, address recipient, uint256 amount, uint64 expiry) =
                abi.decode(payload, (address, address, uint256, uint64));
            vault.reservePull(e.operationId, asset, recipient, amount, e.sourceChainId, e.sourceApplication, expiry);
            vault.deliverPull(e.operationId, e.sourceChainId, e.sourceApplication);
        } else if (e.messageType == IGlyphMessengerAdapter.MessageType.DESTINATION_DELIVERED_ACK) {
            router.acknowledgeDeliveryFromAdapter(e.operationId, e.messageId, adapter);
        } else if (e.messageType == IGlyphMessengerAdapter.MessageType.DESTINATION_FAILED_ACK) {
            router.markRefundPendingFromAdapter(e.operationId, adapter);
        } else {
            revert("unknown operation");
        }
    }
}

contract LayerZeroV2GlyphMessengerAdapterTest is Test {
    uint64 constant BASE_CHAIN = 84532;
    uint64 constant MONAD_CHAIN = 10143;
    uint32 constant BASE_EID = 40245;
    uint32 constant MONAD_EID = 40204;
    address constant BASE_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address constant MONAD_ENDPOINT = 0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff;

    SourceDeltaRouter router;
    DestinationGlyphVault vault;
    TestToken token;
    LocalLayerZeroEndpointV2Mock baseEndpoint;
    LocalLayerZeroEndpointV2Mock monadEndpoint;
    LayerZeroV2GlyphMessengerAdapter baseAdapter;
    LayerZeroV2GlyphMessengerAdapter monadAdapter;
    GlyphLzAppHarness baseApp;
    GlyphLzAppHarness monadApp;

    uint256 payerPk = 0xA11CE;
    address payer;
    address recipient = address(0xB0B);
    address recovery = address(0xCAFE);
    address provider = address(0xF00D);
    address protocol = address(0x1000);
    address referrer = address(0x2000);
    address sponsor = address(0x3000);
    bytes32 policy = keccak256("glyph-lz-v2-policy:base-sepolia-monad-testnet:test-dvn-executor-options:v1");

    function setUp() public {
        payer = vm.addr(payerPk);
        router = new SourceDeltaRouter();
        vault = new DestinationGlyphVault();
        token = new TestToken();
        baseEndpoint = new LocalLayerZeroEndpointV2Mock(BASE_EID, BASE_ENDPOINT);
        monadEndpoint = new LocalLayerZeroEndpointV2Mock(MONAD_EID, MONAD_ENDPOINT);
        baseEndpoint.setRemoteEndpoint(address(monadEndpoint));
        monadEndpoint.setRemoteEndpoint(address(baseEndpoint));
        baseAdapter = new LayerZeroV2GlyphMessengerAdapter(
            address(baseEndpoint), BASE_CHAIN, BASE_EID, MONAD_CHAIN, MONAD_EID, address(this), policy
        );
        monadAdapter = new LayerZeroV2GlyphMessengerAdapter(
            address(monadEndpoint), MONAD_CHAIN, MONAD_EID, BASE_CHAIN, BASE_EID, address(this), policy
        );
        baseApp = new GlyphLzAppHarness(vault, router, address(baseAdapter));
        monadApp = new GlyphLzAppHarness(vault, router, address(monadAdapter));
        baseApp.setAdapter(address(baseAdapter));
        monadApp.setAdapter(address(monadAdapter));
        baseAdapter.setTrustedPeer(address(monadAdapter));
        monadAdapter.setTrustedPeer(address(baseAdapter));
        baseAdapter.setLocalApplication(address(baseApp));
        baseAdapter.setRemoteApplication(address(monadApp));
        monadAdapter.setLocalApplication(address(monadApp));
        monadAdapter.setRemoteApplication(address(baseApp));
        router.setMessengerAdapter(address(baseAdapter), true);
        router.setMessengerAdapter(address(monadAdapter), true);
        router.setMessengerProcessor(address(baseApp), true);
        router.setMessengerProcessor(address(monadApp), true);
        token.mint(payer, 50_000 ether);
        token.mint(provider, 50_000 ether);
        vm.prank(payer);
        token.approve(address(router), type(uint256).max);
        vm.prank(provider);
        token.approve(address(vault), type(uint256).max);
        vm.prank(provider);
        vault.provideLiquidity(IERC20Minimal(address(token)), 3_000 ether);
    }

    function _terms(uint256 nonce) internal view returns (SourceDeltaRouter.Terms memory t) {
        t = SourceDeltaRouter.Terms({
            mode: router.PULL(),
            programId: bytes32(0),
            payer: payer,
            recipient: recipient,
            recovery: recovery,
            sourceAsset: IERC20Minimal(address(token)),
            sourceChainId: BASE_CHAIN,
            destinationVault: address(vault),
            destinationAsset: address(token),
            destinationChainId: MONAD_CHAIN,
            maximumInput: 110 ether,
            destinationAmount: 100 ether,
            protocolFee: 1 ether,
            providerFee: 2 ether,
            referrerFee: 3 ether,
            gasSponsorFee: 4 ether,
            expiry: uint64(block.timestamp + 1 days),
            nonce: nonce
        });
    }

    function _routeEnvelope(bytes32 op, SourceDeltaRouter.Terms memory t, bytes memory payload, uint256 routeNonce)
        internal
        view
        returns (IGlyphMessengerAdapter.Envelope memory e)
    {
        e = IGlyphMessengerAdapter.Envelope(
            1,
            IGlyphMessengerAdapter.MessageType.ROUTE_PULL,
            bytes32(0),
            op,
            router.hashTerms(t),
            BASE_CHAIN,
            address(baseApp),
            MONAD_CHAIN,
            address(monadApp),
            routeNonce,
            keccak256(payload)
        );
    }

    function _ackEnvelope(bytes32 op, bytes32 termsHash, bytes memory payload, uint256 routeNonce)
        internal
        view
        returns (IGlyphMessengerAdapter.Envelope memory e)
    {
        e = IGlyphMessengerAdapter.Envelope(
            1,
            IGlyphMessengerAdapter.MessageType.DESTINATION_DELIVERED_ACK,
            bytes32(0),
            op,
            termsHash,
            MONAD_CHAIN,
            address(monadApp),
            BASE_CHAIN,
            address(baseApp),
            routeNonce,
            keccak256(payload)
        );
    }

    function test_redBidirectionalRequestAckQuoteRefundAndFinalizeRetry() public {
        SourceDeltaRouter.Terms memory t = _terms(0);
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        bytes memory payload = abi.encode(address(token), recipient, 100 ether, uint64(block.timestamp + 1 days));
        IGlyphMessengerAdapter.Envelope memory route = _routeEnvelope(op, t, payload, 7);
        uint256 quote = baseAdapter.quote(MONAD_CHAIN, address(monadApp), route, payload, 200_000);
        vm.expectRevert();
        baseAdapter.send{value: quote - 1}(MONAD_CHAIN, address(monadApp), route, payload, payable(payer), 200_000);
        uint256 beforeRefund = payer.balance;
        bytes32 outbound = baseAdapter.send{value: quote + 1 ether}(
            MONAD_CHAIN, address(monadApp), route, payload, payable(payer), 200_000
        );
        assertGt(payer.balance, beforeRefund);
        monadEndpoint.deliver(address(baseAdapter), address(monadAdapter), outbound, payload);
        assertEq(token.balanceOf(recipient), 100 ether);
        bytes memory ackPayload = abi.encode(op, bytes32("destTx"), uint32(1));
        IGlyphMessengerAdapter.Envelope memory ack = _ackEnvelope(op, router.hashTerms(t), ackPayload, 7);
        uint256 ackQuote = monadAdapter.quote(BASE_CHAIN, address(baseApp), ack, ackPayload, 200_000);
        bytes32 ackId = monadAdapter.send{value: ackQuote}(
            BASE_CHAIN, address(baseApp), ack, ackPayload, payable(provider), 200_000
        );
        baseApp.setFailNext(true);
        baseEndpoint.deliver(address(monadAdapter), address(baseAdapter), ackId, ackPayload);
        assertFalse(router.ackDelivered(op));
        baseApp.setFailNext(false);
        baseAdapter.retry(ackId);
        assertTrue(router.ackDelivered(op));
        router.finalize(op, provider, protocol, referrer, sponsor);
        assertEq(token.balanceOf(protocol), 1 ether);
    }

    function test_redFailClosedAuthenticationReplayMalformedAndOrdering() public {
        SourceDeltaRouter.Terms memory t = _terms(0);
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        bytes memory payload = abi.encode(address(token), recipient, 100 ether, uint64(block.timestamp + 1 days));
        IGlyphMessengerAdapter.Envelope memory e = _routeEnvelope(op, t, payload, 1);
        uint256 q = baseAdapter.quote(MONAD_CHAIN, address(monadApp), e, payload, 200_000);
        bytes32 id = baseAdapter.send{value: q}(MONAD_CHAIN, address(monadApp), e, payload, payable(payer), 200_000);
        vm.expectRevert();
        baseEndpoint.deliver(address(0xBAD), address(monadAdapter), id, payload);
        vm.expectRevert();
        monadEndpoint.deliverWith(
            address(baseAdapter),
            address(monadAdapter),
            id,
            payload,
            BASE_EID + 1,
            bytes32(uint256(uint160(address(baseAdapter))))
        );
        vm.expectRevert();
        monadEndpoint.deliverWith(
            address(baseAdapter),
            address(monadAdapter),
            id,
            payload,
            BASE_EID,
            bytes32(uint256(uint160(address(0xBEEF))))
        );
        IGlyphMessengerAdapter.Envelope memory wrong = e;
        wrong.destinationApplication = address(0xBEEF);
        vm.expectRevert();
        baseAdapter.send{value: q}(MONAD_CHAIN, address(monadApp), wrong, payload, payable(payer), 200_000);
        IGlyphMessengerAdapter.Envelope memory badVersion = e;
        badVersion.messageVersion = 2;
        vm.expectRevert();
        baseAdapter.send{value: q}(MONAD_CHAIN, address(monadApp), badVersion, payload, payable(payer), 200_000);
        IGlyphMessengerAdapter.Envelope memory badType = e;
        badType.messageType = IGlyphMessengerAdapter.MessageType.NONE;
        vm.expectRevert();
        baseAdapter.send{value: q}(MONAD_CHAIN, address(monadApp), badType, payload, payable(payer), 200_000);
        vm.expectRevert();
        monadEndpoint.deliverCorrupt(
            address(monadAdapter), id, bytes("malformed"), BASE_EID, bytes32(uint256(uint160(address(baseAdapter))))
        );
        monadEndpoint.deliver(address(baseAdapter), address(monadAdapter), id, payload);
        vm.expectRevert();
        monadEndpoint.deliver(address(baseAdapter), address(monadAdapter), id, payload);
    }

    function test_redDuplicateSemanticTupleRejected() public {
        SourceDeltaRouter.Terms memory t = _terms(0);
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        bytes memory payload = abi.encode(address(token), recipient, 100 ether, uint64(block.timestamp + 1 days));
        IGlyphMessengerAdapter.Envelope memory e = _routeEnvelope(op, t, payload, 1);
        uint256 q = baseAdapter.quote(MONAD_CHAIN, address(monadApp), e, payload, 200_000);
        baseAdapter.send{value: q}(MONAD_CHAIN, address(monadApp), e, payload, payable(payer), 200_000);
        SourceDeltaRouter.Terms memory t2 = _terms(1);
        vm.prank(payer);
        router.escrow(t2);
        IGlyphMessengerAdapter.Envelope memory semanticDup = _routeEnvelope(op, t2, payload, 1);
        semanticDup.messageId = keccak256("different-guid");
        vm.expectRevert();
        baseAdapter.send{value: q}(MONAD_CHAIN, address(monadApp), semanticDup, payload, payable(payer), 200_000);
    }

    function test_redFailureAckRefundRaceInsufficientLiquidityAndAccessControl() public {
        SourceDeltaRouter.Terms memory t = _terms(0);
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        vm.expectRevert();
        router.acknowledgeDeliveryFromAdapter(op, bytes32("x"), address(this));
        vm.expectRevert();
        baseAdapter.setTrustedPeer(address(0));
        vm.prank(address(0xBAD));
        vm.expectRevert();
        baseAdapter.setTrustedPeer(address(monadAdapter));
        vm.expectRevert();
        new LayerZeroV2GlyphMessengerAdapter(
            address(0), BASE_CHAIN, BASE_EID, MONAD_CHAIN, MONAD_EID, address(this), policy
        );
        vm.prank(address(baseAdapter));
        router.markRefundPendingFromAdapter(op, address(baseAdapter));
        router.refund(op);
        assertEq(token.balanceOf(recovery), 110 ether);
        SourceDeltaRouter.Terms memory t2 = _terms(1);
        t2.destinationAmount = 9_999 ether;
        t2.maximumInput = 10_010 ether;
        vm.prank(payer);
        bytes32 op2 = router.escrow(t2);
        bytes memory payload = abi.encode(address(token), recipient, 9_999 ether, uint64(block.timestamp + 1 days));
        bytes32 id = baseAdapter.send{
            value: baseAdapter.quote(
                MONAD_CHAIN, address(monadApp), _routeEnvelope(op2, t2, payload, 2), payload, 200_000
            )
        }(
            MONAD_CHAIN, address(monadApp), _routeEnvelope(op2, t2, payload, 2), payload, payable(payer), 200_000
        );
        monadEndpoint.deliver(address(baseAdapter), address(monadAdapter), id, payload);
        assertEq(uint8(monadAdapter.messageStatus(id)), uint8(LayerZeroV2GlyphMessengerAdapter.MessageStatus.FAILED));
        vm.expectRevert();
        router.refund(op2);
    }
}
