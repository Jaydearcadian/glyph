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
    receive() external payable {}
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
    uint256 gatekeeperPk = 0xBEEF;
    address payer;
    address claimant;
    address gatekeeper;
    address recipient = address(0xB0B);
    address recovery = address(0xCAFE);
    address provider = address(0xF00D);
    address provider2 = address(0xF00E);
    address protocol = address(0x1000);
    address referrer = address(0x2000);
    address sponsor = address(0x3000);
    bytes32 policy = keccak256("glyph-lz-v2-policy:base-sepolia-monad-testnet:test-dvn-executor-options:v2");

    function setUp() public {
        payer = vm.addr(payerPk);
        claimant = vm.addr(claimantPk);
        gatekeeper = vm.addr(gatekeeperPk);
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
        baseAdapter.freezeConfig(policy);
        monadAdapter.freezeConfig(policy);
        baseApp.freezeConfig(policy);
        monadApp.freezeConfig(policy);
        router.setMessengerAdapter(address(baseAdapter), true);
        router.setMessengerAdapter(address(monadAdapter), true);
        router.setMessengerProcessorForAdapter(address(baseApp), address(baseAdapter), true);
        router.setMessengerProcessorForAdapter(address(monadApp), address(monadAdapter), true);
        vault.setAuthorizedApplication(address(monadApp), true);
        (bool okBase,) = payable(address(baseApp)).call{value: 10 ether}("");
        assertTrue(okBase);
        (bool okMonad,) = payable(address(monadApp)).call{value: 10 ether}("");
        assertTrue(okMonad);
        token.mint(payer, 50_000 ether);
        token.mint(provider, 50_000 ether);
        token.mint(provider2, 50_000 ether);
        vm.prank(payer);
        token.approve(address(router), type(uint256).max);
        vm.prank(provider);
        token.approve(address(vault), type(uint256).max);
        vm.prank(provider);
        vault.provideLiquidity(IERC20Minimal(address(token)), 3_000 ether);
        vm.prank(provider2);
        token.approve(address(vault), type(uint256).max);
        vm.prank(provider2);
        vault.provideLiquidity(IERC20Minimal(address(token)), 50 ether);
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
            provider: provider,
            protocol: protocol,
            referrer: referrer,
            gasSponsor: sponsor,
            claimGatekeeper: mode == router.PUSH() ? gatekeeper : address(0),
            expiry: uint64(block.timestamp + 1 days),
            nonce: nonce
        });
    }

    function _claimSig(bytes32 op, bytes32 nullifier, uint64 deadline) internal view returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encode(
                "GLYPH_CLAIM_INTENT_V1", block.chainid, address(vault), op, claimant, 100 ether, nullifier, deadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimantPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _gateSig(bytes32 op, bytes32 nullifier, uint64 deadline) internal view returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encode(
                "GLYPH_CLAIM_AUTH_V1",
                block.chainid,
                address(vault),
                op,
                claimant,
                address(token),
                100 ether,
                nullifier,
                deadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(gatekeeperPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _send(bytes32 op, uint256 gasLimit) internal returns (bytes32 outbound) {
        uint256 q = baseApp.quoteRouteFromEscrow(op, gasLimit);
        outbound = baseApp.sendRouteFromEscrow{value: q}(op, payable(payer), gasLimit);
    }

    function test_officialSelectorsConfigFreezeAndPostFreezeMutationReverts() public {
        assertEq(baseAdapter.endpointQuoteSelector(), bytes4(0xddc28c58));
        assertEq(baseAdapter.endpointSendSelector(), bytes4(0x2637a450));
        assertEq(baseAdapter.messengerPolicyHash(), policy);
        vm.expectRevert(LayerZeroV2GlyphMessengerAdapter.InvalidConfig.selector);
        baseAdapter.setTrustedPeer(address(0x1234));
        vm.expectRevert(GlyphLayerZeroApplication.InvalidConfig.selector);
        baseApp.setRemoteApplication(address(0x1234));
    }

    function test_pullDeliveryAckFinalizeAndSourceReceiptUsesBoundProviderOnly() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PULL());
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        bytes32 outbound = _send(op, 200_000);
        monadEndpoint.deliver(address(monadAdapter), outbound);
        assertEq(token.balanceOf(recipient), 100 ether);
        baseEndpoint.deliver(address(baseAdapter), monadEndpoint.lastGuid());
        assertTrue(router.ackDelivered(op));
        baseApp.finalizeAndSendReceipt{value: 1 ether}(op, payable(payer), 200_000);
        assertEq(token.balanceOf(provider), 50_000 ether - 3_000 ether + 102 ether);
        assertEq(token.balanceOf(protocol), 1 ether);
        assertEq(token.balanceOf(referrer), 3 ether);
        assertEq(token.balanceOf(sponsor), 4 ether);
        monadEndpoint.deliver(address(monadAdapter), baseEndpoint.lastGuid());
        assertTrue(monadApp.sourceTerminalReceipt(op) != bytes32(0));
    }

    function test_pushReservedAckDoesNotFinalizeUntilClaimDeliveryAckArrives() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PUSH());
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        bytes32 outbound = _send(op, 200_000);
        monadEndpoint.deliver(address(monadAdapter), outbound);
        baseEndpoint.deliver(address(baseAdapter), monadEndpoint.lastGuid());
        assertTrue(router.reservationAcked(op));
        assertFalse(router.ackDelivered(op));
        vm.expectRevert(SourceDeltaRouter.RefundUnsafe.selector);
        router.finalize(op);
        bytes32 nullifier = keccak256("claim-1");
        uint64 deadline = uint64(block.timestamp + 1 hours);
        uint256 claimFee = 1 ether;
        monadApp.claimPushAndAck{value: claimFee}(
            op, claimant, nullifier, deadline, _claimSig(op, nullifier, deadline), _gateSig(op, nullifier, deadline)
        );
        assertEq(token.balanceOf(claimant), 100 ether);
        baseEndpoint.deliver(address(baseAdapter), monadEndpoint.lastGuid());
        assertTrue(router.ackDelivered(op));
        router.finalize(op);
        vm.expectRevert(SourceDeltaRouter.AlreadyTerminal.selector);
        router.refund(op);
    }

    function test_unknownMutatedRouteAndAckFactsFailClosed() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PULL());
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        SourceDeltaRouter.Terms memory bad = t;
        bad.destinationAmount = 1 ether;
        bytes32 badTermsHash = router.hashTerms(bad);
        vm.expectRevert();
        router.recordDestinationDeliveryFromAdapter(
            op,
            keccak256("ack"),
            keccak256("route"),
            1,
            badTermsHash,
            recipient,
            provider,
            address(token),
            100 ether,
            address(baseAdapter)
        );
        bytes32 goodTermsHash = router.hashTerms(t);
        vm.expectRevert();
        vm.prank(address(baseApp));
        router.recordFailureFromAdapter(
            keccak256("future"),
            keccak256("route"),
            1,
            goodTermsHash,
            SourceDeltaRouter.FailureCode.LIQUIDITY_UNAVAILABLE,
            address(baseAdapter)
        );
    }

    function test_vaultOutsiderCannotReserveOrDeliverAndProviderIsolation() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PULL());
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        vm.expectRevert(DestinationGlyphVault.UnauthorizedActor.selector);
        vault.reservePull(op, provider, address(token), recipient, 100 ether, BASE_CHAIN, address(baseApp), t.expiry);
        bytes32 outbound = _send(op, 200_000);
        monadEndpoint.deliver(address(monadAdapter), outbound);
        assertEq(vault.providerAvailable(provider2, address(token)), 50 ether);
        assertEq(token.balanceOf(recipient), 100 ether);
    }

    function test_claimGatekeeperRejectsArbitraryClaimantWrongSignatureAndReplay() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PUSH());
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        monadEndpoint.deliver(address(monadAdapter), _send(op, 200_000));
        bytes32 nullifier = keccak256("claim-1");
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory claimantSig = _claimSig(op, nullifier, deadline);
        bytes memory badGateSig = claimantSig;
        vm.expectRevert(DestinationGlyphVault.ClaimFailed.selector);
        monadApp.claimPushAndAck{value: 1 ether}(op, claimant, nullifier, deadline, claimantSig, badGateSig);
        monadApp.claimPushAndAck{value: 1 ether}(
            op, claimant, nullifier, deadline, claimantSig, _gateSig(op, nullifier, deadline)
        );
        vm.expectRevert(DestinationGlyphVault.InvalidReservation.selector);
        monadApp.claimPushAndAck{value: 1 ether}(
            op, claimant, nullifier, deadline, claimantSig, _gateSig(op, nullifier, deadline)
        );
    }

    function test_failureAckAuthorizesRefundButNotAfterDelivery() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PULL());
        t.destinationAmount = 9_999 ether;
        t.maximumInput = 10_010 ether;
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        monadEndpoint.deliver(address(monadAdapter), _send(op, 200_000));
        baseEndpoint.deliver(address(baseAdapter), monadEndpoint.lastGuid());
        assertFalse(router.ackDelivered(op));
        router.refund(op);
        assertEq(token.balanceOf(recovery), 10_010 ether);
    }

    function test_revertingNativeRefundDoesNotTrapInAdapterOrApp() public {
        SourceDeltaRouter.Terms memory t = _terms(0, router.PULL());
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        uint256 q = baseApp.quoteRouteFromEscrow(op, 200_000);
        RevertingRefundReceiver bad = new RevertingRefundReceiver();
        vm.expectRevert(LayerZeroV2GlyphMessengerAdapter.RefundFailed.selector);
        baseApp.sendRouteFromEscrow{value: q + 1}(op, payable(address(bad)), 200_000);
        assertEq(address(baseAdapter).balance, 0);
    }
}
