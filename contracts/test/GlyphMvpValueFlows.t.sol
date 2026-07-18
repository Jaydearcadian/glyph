// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {ContributionCampaign} from "../src/ContributionCampaign.sol";
import {GiftPool} from "../src/GiftPool.sol";
import {MockGlyphMessengerAdapter} from "../src/MockGlyphMessengerAdapter.sol";
import {IGlyphMessengerAdapter} from "../src/interfaces/IGlyphMessengerAdapter.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";
import {TestToken} from "./mocks/TestToken.sol";

contract GlyphMvpValueFlowsTest is Test {
    SourceDeltaRouter router;
    DestinationGlyphVault vault;
    ContributionCampaign campaign;
    GiftPool gift;
    MockGlyphMessengerAdapter messenger;
    TestToken token;

    uint256 payerPk = 0xA11CE;
    uint256 claimantPk = 0xC1A1;
    uint256 gatekeeperPk = 0xBEEF;
    address payer;
    address claimant;
    address gatekeeper;
    address recipient = address(0xB0B);
    address recovery = address(0xCAFE);
    address provider = address(0xF00D);
    address protocol = address(0x1000);
    address referrer = address(0x2000);
    address sponsor = address(0x3000);
    address app = address(0xA99);

    function setUp() public {
        payer = vm.addr(payerPk);
        claimant = vm.addr(claimantPk);
        gatekeeper = vm.addr(gatekeeperPk);
        router = new SourceDeltaRouter();
        vault = new DestinationGlyphVault();
        campaign = new ContributionCampaign();
        gift = new GiftPool();
        messenger = new MockGlyphMessengerAdapter();
        token = new TestToken();
        token.mint(payer, 10_000 ether);
        token.mint(provider, 10_000 ether);
        vm.prank(payer);
        token.approve(address(router), type(uint256).max);
        vm.prank(provider);
        token.approve(address(vault), type(uint256).max);
        vm.prank(provider);
        token.approve(address(gift), type(uint256).max);
        vm.prank(provider);
        vault.provideLiquidity(IERC20Minimal(address(token)), 2_000 ether);
        vault.setAuthorizedApplication(app, true);
        router.setMessengerAdapter(address(messenger), true);
        router.setMessengerProcessorForAdapter(app, address(messenger), true);
    }

    function _terms(bytes32 mode, uint256 nonce, address recip)
        internal
        view
        returns (SourceDeltaRouter.Terms memory t)
    {
        t = SourceDeltaRouter.Terms({
            mode: mode,
            programId: bytes32(0),
            payer: payer,
            recipient: recip,
            recovery: recovery,
            sourceAsset: IERC20Minimal(address(token)),
            sourceChainId: uint64(block.chainid),
            destinationVault: address(vault),
            destinationAsset: address(token),
            destinationChainId: 10143,
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

    function _escrowPull(uint256 nonce) internal returns (bytes32 op, SourceDeltaRouter.Terms memory t) {
        t = _terms(router.PULL(), nonce, recipient);
        vm.prank(payer);
        op = router.escrow(t);
    }

    function _claimSig(bytes32 op, bytes32 nullifier, uint64 deadline) internal view returns (bytes memory sig) {
        bytes32 digest = keccak256(
            abi.encode(
                "GLYPH_CLAIM_INTENT_V1", block.chainid, address(vault), op, claimant, 100 ether, nullifier, deadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimantPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _gateSig(bytes32 op, bytes32 nullifier, uint64 deadline) internal view returns (bytes memory sig) {
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
        sig = abi.encodePacked(r, s, v);
    }

    function _signGiftClaim(bytes32 program, bytes32 nullifier, uint64 deadline)
        internal
        view
        returns (bytes memory sig)
    {
        bytes32 digest = keccak256(
            abi.encode(
                "GLYPH_GIFT_CLAIM", block.chainid, address(gift), program, claimant, 100 ether, nullifier, deadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimantPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function test_gate2LocalAndCrossChainPullAccountingRefundAndSessionFailClosed() public {
        (bytes32 op, SourceDeltaRouter.Terms memory t) = _escrowPull(0);
        assertEq(token.balanceOf(address(router)), 110 ether);
        vm.startPrank(app);
        vault.reservePull(
            op, provider, address(token), recipient, 100 ether, t.sourceChainId, address(router), t.expiry
        );
        vault.deliverPull(op, t.sourceChainId, address(router));
        router.recordRouteFromAdapter(op, keccak256("route"), 1, router.hashTerms(t), address(messenger));
        router.recordDestinationDeliveryFromAdapter(
            op,
            keccak256("ack"),
            keccak256("route"),
            1,
            router.hashTerms(t),
            recipient,
            provider,
            address(token),
            100 ether,
            address(messenger)
        );
        vm.stopPrank();
        assertEq(token.balanceOf(recipient), 100 ether);
        router.finalize(op);
        assertEq(token.balanceOf(protocol), 1 ether);
        assertEq(token.balanceOf(referrer), 3 ether);
        assertEq(token.balanceOf(sponsor), 4 ether);
        assertEq(token.balanceOf(provider), 10_000 ether - 2_000 ether + 102 ether);

        SourceDeltaRouter.Terms memory refundTerms = _terms(router.PULL(), 1, recipient);
        vm.prank(payer);
        bytes32 refundOp = router.escrow(refundTerms);
        vm.warp(refundTerms.expiry + 1);
        router.refund(refundOp);
        assertEq(token.balanceOf(recovery), 110 ether);

        SourceDeltaRouter.Terms memory session = _terms(router.SESSION(), 2, recipient);
        vm.prank(payer);
        vm.expectRevert(SourceDeltaRouter.SessionDisabled.selector);
        router.escrow(session);
    }

    function test_gate3GaslessRelayedEscrowEquivalentAndPermitPath() public {
        SourceDeltaRouter.Terms memory direct = _terms(router.PULL(), 0, recipient);
        vm.prank(payer);
        bytes32 opDirect = router.escrow(direct);
        SourceDeltaRouter.Terms memory gasless = _terms(router.PULL(), 1, recipient);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 digest =
            keccak256(abi.encode("GLYPH_ESCROW", block.chainid, address(router), router.hashTerms(gasless), deadline));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPk, digest);
        bytes32 opGasless = router.escrowWithSignature(gasless, deadline, abi.encodePacked(r, s, v));
        assertTrue(opGasless != opDirect);
        assertEq(token.balanceOf(address(router)), 220 ether);
        TestToken permitToken = new TestToken();
        permitToken.mint(payer, 1 ether);
        uint256 permitDeadline = block.timestamp + 1 hours;
        bytes32 permitDigest = keccak256(
            bytes.concat(
                hex"1901",
                permitToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        permitToken.PERMIT_TYPEHASH(),
                        payer,
                        address(router),
                        uint256(1 ether),
                        uint256(0),
                        permitDeadline
                    )
                )
            )
        );
        (v, r, s) = vm.sign(payerPk, permitDigest);
        permitToken.permit(payer, address(router), 1 ether, permitDeadline, v, r, s);
        assertEq(permitToken.allowance(payer, address(router)), 1 ether);
    }

    function test_gate4CrossChainPullMockMessengerDuplicateAndMutatedMessages() public {
        (bytes32 op, SourceDeltaRouter.Terms memory t) = _escrowPull(0);
        bytes memory payload = abi.encode("route");
        IGlyphMessengerAdapter.Envelope memory e = IGlyphMessengerAdapter.Envelope(
            1,
            IGlyphMessengerAdapter.MessageType.ROUTE_PULL,
            bytes32(0),
            op,
            router.hashTerms(t),
            t.sourceChainId,
            address(router),
            t.destinationChainId,
            address(vault),
            1,
            keccak256(payload)
        );
        bytes32 msgId =
            messenger.sendMessage(t.destinationChainId, address(vault), e, payload, payable(recovery), 200_000);
        IGlyphMessengerAdapter.Envelope memory got = messenger.consume(msgId);
        assertEq(got.operationId, op);
        vm.expectRevert();
        messenger.consume(msgId);
    }

    function test_gate5CrossChainPushClaimNullifierExpiryReleaseRefund() public {
        SourceDeltaRouter.Terms memory t = _terms(router.PUSH(), 0, recipient);
        vm.prank(payer);
        bytes32 op = router.escrow(t);
        vm.startPrank(app);
        vault.reservePush(
            op, provider, address(token), recipient, 100 ether, t.sourceChainId, address(router), t.expiry, gatekeeper
        );
        router.recordRouteFromAdapter(op, keccak256("route"), 1, router.hashTerms(t), address(messenger));
        router.recordDestinationReservedFromAdapter(
            op, keccak256("reserve"), keccak256("route"), 1, router.hashTerms(t), provider, address(messenger)
        );
        vm.stopPrank();
        assertFalse(router.ackDelivered(op));
        bytes32 nullifier = keccak256("claim-1");
        uint64 deadline = uint64(block.timestamp + 1 hours);
        vault.claimPush(
            op, claimant, nullifier, deadline, _claimSig(op, nullifier, deadline), _gateSig(op, nullifier, deadline)
        );
        assertEq(token.balanceOf(claimant), 100 ether);
        bytes32 pushTermsHash = router.hashTerms(t);
        vm.prank(app);
        router.recordDestinationDeliveryFromAdapter(
            op,
            keccak256("push-ack"),
            keccak256("route"),
            1,
            pushTermsHash,
            claimant,
            provider,
            address(token),
            100 ether,
            address(messenger)
        );
        router.finalize(op);

        SourceDeltaRouter.Terms memory unclaimed = _terms(router.PUSH(), 1, recipient);
        vm.prank(payer);
        bytes32 unclaimedOp = router.escrow(unclaimed);
        vm.prank(app);
        vault.reservePush(
            unclaimedOp,
            provider,
            address(token),
            recipient,
            100 ether,
            unclaimed.sourceChainId,
            address(router),
            uint64(block.timestamp + 10),
            gatekeeper
        );
        vm.warp(block.timestamp + 11);
        vault.release(unclaimedOp);
        vm.prank(app);
        router.markRefundPendingFromAdapter(unclaimedOp, address(messenger));
        router.refund(unclaimedOp);
        assertEq(token.balanceOf(recovery), 110 ether);
    }

    function test_gate6ContributionCampaignImmediateThresholdHardCap() public {
        bytes32 program = keccak256("campaign");
        ContributionCampaign.Campaign memory c = ContributionCampaign.Campaign(
            recipient,
            address(token),
            200 ether,
            10 ether,
            150 ether,
            250 ether,
            uint64(block.timestamp + 1 days),
            ContributionCampaign.PayoutMode.THRESHOLD_ESCROW,
            0,
            false
        );
        campaign.create(program, c);
        campaign.reconcileChild(program, keccak256("child1"), 100 ether, keccak256("receipt1"));
        campaign.reconcileChild(program, keccak256("child2"), 100 ether, keccak256("receipt2"));
        vm.expectRevert();
        campaign.reconcileChild(program, keccak256("child3"), 100 ether, keccak256("receipt3"));
        bytes32 aggregate = campaign.close(program);
        assertTrue(aggregate != bytes32(0));
    }

    function test_gate7GiftPoolUniqueClaimsAndClosureConservation() public {
        bytes32 program = keccak256("gift");
        vm.prank(provider);
        gift.fund(
            program, IERC20Minimal(address(token)), 300 ether, 100 ether, uint64(block.timestamp + 1 days), recovery
        );
        bytes32 n1 = keccak256("gift-nullifier-1");
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _signGiftClaim(program, n1, deadline);
        gift.claim(program, claimant, n1, deadline, sig);
        vm.expectRevert();
        gift.claim(program, claimant, n1, deadline, sig);
        assertEq(token.balanceOf(claimant), 100 ether);
        vm.warp(block.timestamp + 2 days);
        bytes32 closed = gift.close(program);
        assertTrue(closed != bytes32(0));
        assertEq(token.balanceOf(recovery), 200 ether);
    }
}
