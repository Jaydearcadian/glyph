// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {GlyphLayerZeroApplication} from "../src/GlyphLayerZeroApplication.sol";
import {LayerZeroV2GlyphMessengerAdapter} from "../src/LayerZeroV2GlyphMessengerAdapter.sol";
import {LocalLayerZeroEndpointV2Mock} from "../src/mocks/LocalLayerZeroEndpointV2Mock.sol";
import {IGlyphMessengerAdapter} from "../src/interfaces/IGlyphMessengerAdapter.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";
import {TestToken} from "./mocks/TestToken.sol";

contract RevertingRefundReceiver {
    receive() external payable {
        revert("no refund");
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
    GlyphLayerZeroApplication baseApp;
    GlyphLayerZeroApplication monadApp;

    uint256 payerPk = 0xA11CE;
    uint256 claimantPk = 0xC1A1;
    address payer;
    address claimant;
    address recipient = address(0xB0B);
    address recovery = address(0xCAFE);
    address provider = address(0xF00D);
    address protocol = address(0x1000);
    address referrer = address(0x2000);
    address sponsor = address(0x3000);
    bytes32 policy = keccak256("glyph-lz-v2-policy:base-sepolia-monad-testnet:test-dvn-executor-options:v1");

    function setUp() public {
        payer = vm.addr(payerPk);
        claimant = vm.addr(claimantPk);
        vm.deal(address(this), 100 ether);
        vm.deal(payer, 100 ether);
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
        baseApp = new GlyphLayerZeroApplication(
            GlyphLayerZeroApplication.Side.SOURCE, BASE_CHAIN, MONAD_CHAIN, router, vault, address(this)
        );
        monadApp = new GlyphLayerZeroApplication(
            GlyphLayerZeroApplication.Side.DESTINATION, MONAD_CHAIN, BASE_CHAIN, router, vault, address(this)
        );
        baseApp.setAdapter(IGlyphMessengerAdapter(address(baseAdapter)));
        monadApp.setAdapter(IGlyphMessengerAdapter(address(monadAdapter)));
        baseApp.setRemoteApplication(address(monadApp));
        monadApp.setRemoteApplication(address(baseApp));
        baseAdapter.setTrustedPeer(address(monadAdapter));
        monadAdapter.setTrustedPeer(address(baseAdapter));
        baseAdapter.setLocalApplication(address(baseApp));
        baseAdapter.setRemoteApplication(address(monadApp));
        monadAdapter.setLocalApplication(address(monadApp));
        monadAdapter.setRemoteApplication(address(baseApp));
        router.setMessengerAdapter(address(baseAdapter), true);
        router.setMessengerAdapter(address(monadAdapter), true);
        router.setMessengerProcessorForAdapter(address(baseApp), address(baseAdapter), true);
        router.setMessengerProcessorForAdapter(address(monadApp), address(monadAdapter), true);
        payable(address(baseApp)).transfer(10 ether);
        payable(address(monadApp)).transfer(10 ether);
        token.mint(payer, 50_000 ether);
        token.mint(provider, 50_000 ether);
        vm.prank(payer);
        token.approve(address(router), type(uint256).max);
        vm.prank(provider);
        token.approve(address(vault), type(uint256).max);
        vm.prank(provider);
        vault.provideLiquidity(IERC20Minimal(address(token)), 3_000 ether);
    }

    function _terms(uint256 nonce, bytes32 mode) internal view returns (SourceDeltaRouter.Terms memory t) {
        t = SourceDeltaRouter.Terms({
            mode: mode,
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

    function _route(SourceDeltaRouter.Terms memory t, bytes32 rule)
        internal
        pure
        returns (GlyphLayerZeroApplication.RoutePayload memory)
    {
        return GlyphLayerZeroApplication.RoutePayload(
            address(t.destinationAsset), t.recipient, t.destinationAmount, t.expiry, rule
        );
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

    function _signVaultClaim(bytes32 op, bytes32 nullifier, uint64 deadline) internal view returns (bytes memory sig) {
        bytes32 digest = keccak256(
            abi.encode("GLYPH_CLAIM", block.chainid, address(vault), op, claimant, 100 ether, nullifier, deadline)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimantPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function test_officialEndpointSelectorsAndOptionsAreAbiCompatible() public view {
        assertEq(baseAdapter.endpointQuoteSelector(), bytes4(0xddc28c58));
        assertEq(baseAdapter.endpointSendSelector(), bytes4(0x2637a450));
        assertTrue(baseAdapter.endpointQuoteSelector() != bytes4(0x9b4c6f3a));
        assertTrue(baseAdapter.endpointSendSelector() != bytes4(0x6006aea7));
        bytes memory options = baseAdapter.buildOptions(200_000);
        uint16 optionType;
        assembly { optionType := mload(add(options, 2)) }
        assertEq(optionType, uint16(3));
        assertEq(uint8(options[2]), uint8(1));
        assertEq(uint8(options[5]), uint8(1));
    }

    function test_pullRequestDeliveryAckAndFinalizeThroughProductionApps() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PULL());
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        GlyphLayerZeroApplication.RoutePayload memory r = _route(t, bytes32(0));
        bytes32 th = router.hashTerms(t);
        uint256 quote = baseApp.quoteRoute(IGlyphMessengerAdapter.MessageType.ROUTE_PULL, op, th, r, 200_000);
        vm.expectRevert(
            abi.encodeWithSelector(LayerZeroV2GlyphMessengerAdapter.InsufficientNativeFee.selector, quote, quote - 1)
        );
        baseApp.sendRoute{value: quote - 1}(
            IGlyphMessengerAdapter.MessageType.ROUTE_PULL, op, th, r, payable(payer), 200_000
        );
        uint256 payerBefore = payer.balance;
        bytes32 outbound = baseApp.sendRoute{value: quote + 1 ether}(
            IGlyphMessengerAdapter.MessageType.ROUTE_PULL, op, th, r, payable(payer), 200_000
        );
        assertGt(payer.balance, payerBefore);
        monadEndpoint.deliver(address(monadAdapter), outbound);
        assertEq(token.balanceOf(recipient), 100 ether);
        bytes32 ackId = monadEndpoint.lastGuid();
        baseEndpoint.deliver(address(baseAdapter), ackId);
        assertTrue(router.ackDelivered(op));
        router.finalize(op, provider, protocol, referrer, sponsor);
        assertEq(token.balanceOf(protocol), 1 ether);
    }

    function test_pushReserveClaimAckAndReleaseRefundRace() public {
        bytes32 rule = keccak256("bearer-secret-commitment");
        SourceDeltaRouter.Terms memory t = _terms(0, router.PUSH());
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        uint256 q = baseApp.quoteRoute(
            IGlyphMessengerAdapter.MessageType.RESERVE_PUSH, op, router.hashTerms(t), _route(t, rule), 200_000
        );
        bytes32 outbound = baseApp.sendRoute{value: q}(
            IGlyphMessengerAdapter.MessageType.RESERVE_PUSH,
            op,
            router.hashTerms(t),
            _route(t, rule),
            payable(payer),
            200_000
        );
        monadEndpoint.deliver(address(monadAdapter), outbound);
        baseEndpoint.deliver(address(baseAdapter), monadEndpoint.lastGuid());
        assertTrue(router.ackDelivered(op));
        bytes32 nullifier = keccak256("claim-1");
        uint64 deadline = uint64(block.timestamp + 1 hours);
        monadApp.claimPushAndAck(op, claimant, nullifier, deadline, _signVaultClaim(op, nullifier, deadline));
        assertEq(token.balanceOf(claimant), 100 ether);
        router.finalize(op, provider, protocol, referrer, sponsor);
        vm.expectRevert(SourceDeltaRouter.AlreadyTerminal.selector);
        router.refund(op);
    }

    function test_authorityConsumeAndRouterTransitionsFailClosed() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PULL());
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        bytes32 mid = keccak256("msg");
        vm.expectRevert(SourceDeltaRouter.UnauthorizedActor.selector);
        router.acknowledgeDelivery(op, mid);
        vm.expectRevert(SourceDeltaRouter.UnauthorizedActor.selector);
        router.markRefundPending(op);
        vm.expectRevert(SourceDeltaRouter.UnauthorizedActor.selector);
        router.acknowledgeDeliveryFromAdapter(op, mid, address(monadAdapter));
        vm.prank(address(baseApp));
        vm.expectRevert(SourceDeltaRouter.UnauthorizedActor.selector);
        router.acknowledgeDeliveryFromAdapter(op, mid, address(monadAdapter));
        vm.expectRevert(LayerZeroV2GlyphMessengerAdapter.Unauthorized.selector);
        baseAdapter.consume(mid);
    }

    function test_publicQuoteSendAndWrongPayloadPolicyProofEndpointPeerNonceRejected() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PULL());
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        bytes memory payload =
            abi.encode(address(token), recipient, 100 ether, uint64(block.timestamp + 1 days), bytes32(0));
        IGlyphMessengerAdapter.Envelope memory e = _routeEnvelope(op, t, payload, 1);
        vm.expectRevert(LayerZeroV2GlyphMessengerAdapter.Unauthorized.selector);
        baseAdapter.quote(MONAD_CHAIN, address(monadApp), e, payload, 200_000);
        vm.expectRevert(LayerZeroV2GlyphMessengerAdapter.Unauthorized.selector);
        baseAdapter.sendMessage{value: 1 ether}(MONAD_CHAIN, address(monadApp), e, payload, payable(payer), 200_000);

        bytes32 outbound = baseApp.sendRoute{
            value: baseApp.quoteRoute(
                IGlyphMessengerAdapter.MessageType.ROUTE_PULL, op, router.hashTerms(t), _route(t, bytes32(0)), 200_000
            )
        }(
            IGlyphMessengerAdapter.MessageType.ROUTE_PULL,
            op,
            router.hashTerms(t),
            _route(t, bytes32(0)),
            payable(payer),
            200_000
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LocalLayerZeroEndpointV2Mock.WrongReceiver.selector, address(monadAdapter), address(baseAdapter)
            )
        );
        monadEndpoint.deliver(address(baseAdapter), outbound);
        vm.expectRevert(abi.encodeWithSelector(LayerZeroV2GlyphMessengerAdapter.WrongEid.selector, BASE_EID + 1));
        monadEndpoint.deliverWithForgedOrigin(
            address(monadAdapter), outbound, BASE_EID + 1, bytes32(uint256(uint160(address(baseAdapter))))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LayerZeroV2GlyphMessengerAdapter.WrongPeer.selector, bytes32(uint256(uint160(address(0xBEEF))))
            )
        );
        monadEndpoint.deliverWithForgedOrigin(
            address(monadAdapter), outbound, BASE_EID, bytes32(uint256(uint160(address(0xBEEF))))
        );
        bytes memory wire = monadEndpoint.packetMessage(outbound);
        LayerZeroV2GlyphMessengerAdapter.WireMessage memory decoded =
            abi.decode(wire, (LayerZeroV2GlyphMessengerAdapter.WireMessage));
        bytes32 wrongPolicy = keccak256("wrong-policy");
        decoded.messengerPolicyHash = wrongPolicy;
        vm.expectRevert(abi.encodeWithSelector(LayerZeroV2GlyphMessengerAdapter.WrongPolicy.selector, wrongPolicy));
        monadEndpoint.deliverCorrupt(address(monadAdapter), outbound, abi.encode(decoded));
    }

    function test_failedDestinationSendsFailureAckAndAllowsRefundNoConsumeBypass() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PULL());
        t.destinationAmount = 9_999 ether;
        t.maximumInput = 10_010 ether;
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        GlyphLayerZeroApplication.RoutePayload memory r = _route(t, bytes32(0));
        uint256 q =
            baseApp.quoteRoute(IGlyphMessengerAdapter.MessageType.ROUTE_PULL, op, router.hashTerms(t), r, 200_000);
        bytes32 outbound = baseApp.sendRoute{value: q}(
            IGlyphMessengerAdapter.MessageType.ROUTE_PULL, op, router.hashTerms(t), r, payable(payer), 200_000
        );
        monadEndpoint.deliver(address(monadAdapter), outbound);
        assertEq(
            uint8(monadAdapter.messageStatus(outbound)), uint8(LayerZeroV2GlyphMessengerAdapter.MessageStatus.PROCESSED)
        );
        bytes32 failAck = monadEndpoint.lastGuid();
        baseEndpoint.deliver(address(baseAdapter), failAck);
        assertFalse(router.ackDelivered(op));
        vm.expectRevert(LayerZeroV2GlyphMessengerAdapter.Unauthorized.selector);
        monadAdapter.consume(outbound);
        router.refund(op);
        assertEq(token.balanceOf(recovery), 10_010 ether);
    }

    function test_revertingRefundRecipientRevertsWithoutTrappingExcess() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PULL());
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        GlyphLayerZeroApplication.RoutePayload memory r = _route(t, bytes32(0));
        bytes32 th = router.hashTerms(t);
        uint256 q = baseApp.quoteRoute(IGlyphMessengerAdapter.MessageType.ROUTE_PULL, op, th, r, 200_000);
        RevertingRefundReceiver bad = new RevertingRefundReceiver();
        vm.expectRevert(LayerZeroV2GlyphMessengerAdapter.RefundFailed.selector);
        baseApp.sendRoute{value: q + 1}(
            IGlyphMessengerAdapter.MessageType.ROUTE_PULL, op, th, r, payable(address(bad)), 200_000
        );
    }
}
