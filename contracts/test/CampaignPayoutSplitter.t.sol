// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CampaignPayoutSplitter} from "../src/CampaignPayoutSplitter.sol";
import {ContributionCampaign} from "../src/ContributionCampaign.sol";
import {TestToken} from "../src/TestToken.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";

contract CampaignPayoutSplitterTest is Test {
    TestToken token;
    ContributionCampaign campaign;
    CampaignPayoutSplitter splitter;

    address funder = address(0xA11CE);
    address recovery = address(0xB0B);
    address creator = address(0xC0FFEE);
    address collaborator = address(0xCAFE);
    address referrer = address(0xFEE);
    address outsider = address(0xBAD);

    bytes32 programId = keccak256("glyph.campaign.splitter.test");
    bytes32 childA = keccak256("child-a");
    bytes32 childB = keccak256("child-b");
    bytes32 receiptA = keccak256("receipt-a");
    bytes32 receiptB = keccak256("receipt-b");
    bytes32 aggregateReceipt;
    uint256 total = 20 ether;

    function setUp() public {
        token = new TestToken();
        campaign = new ContributionCampaign();
        splitter = new CampaignPayoutSplitter();
        token.mint(funder, 100 ether);
        ContributionCampaign.Campaign memory c = ContributionCampaign.Campaign({
            recipient: funder,
            settlementAsset: address(token),
            targetAmount: total,
            minContribution: 10 ether,
            maxContribution: 10 ether,
            maxTotal: total,
            deadline: uint64(block.timestamp + 1 days),
            mode: ContributionCampaign.PayoutMode.THRESHOLD_ESCROW,
            reconciledTotal: 0,
            closed: false
        });
        campaign.create(programId, c);
        campaign.reconcileChild(programId, childA, 10 ether, receiptA);
        campaign.reconcileChild(programId, childB, 10 ether, receiptB);
        aggregateReceipt = campaign.close(programId);
    }

    function test_createAndClaimThreeRecipientDistributionConservesValue() public {
        bytes32 distributionId = _createDefaultDistribution(total, _bps(7000, 2000, 1000));

        CampaignPayoutSplitter.RecipientShare memory s0 = splitter.recipientShareAt(distributionId, 0);
        CampaignPayoutSplitter.RecipientShare memory s1 = splitter.recipientShareAt(distributionId, 1);
        CampaignPayoutSplitter.RecipientShare memory s2 = splitter.recipientShareAt(distributionId, 2);
        assertEq(s0.recipient, creator);
        assertEq(s0.amount, 14 ether);
        assertEq(s1.amount, 4 ether);
        assertEq(s2.amount, 2 ether);

        vm.prank(creator);
        bytes32 r0 = splitter.claim(distributionId);
        vm.prank(collaborator);
        bytes32 r1 = splitter.claim(distributionId);
        vm.prank(referrer);
        bytes32 r2 = splitter.claim(distributionId);

        assertEq(token.balanceOf(creator), 14 ether);
        assertEq(token.balanceOf(collaborator), 4 ether);
        assertEq(token.balanceOf(referrer), 2 ether);
        assertTrue(r0 != bytes32(0) && r1 != bytes32(0) && r2 != bytes32(0));
        assertEq(r0, splitter.claimReceiptHash(distributionId, creator));
        assertEq(r1, splitter.claimReceiptHash(distributionId, collaborator));
        assertEq(r2, splitter.claimReceiptHash(distributionId, referrer));
        (uint256 totalAmount, uint256 claimedTotal, uint256 unclaimed, uint256 recovered) =
            splitter.distributionTotals(distributionId);
        assertEq(totalAmount, total);
        assertEq(claimedTotal, total);
        assertEq(unclaimed, 0);
        assertEq(recovered, 0);
    }

    function test_lastRecipientAbsorbsRoundingDust() public {
        bytes32 tinyProgram = keccak256("tiny");
        ContributionCampaign.Campaign memory c = ContributionCampaign.Campaign({
            recipient: funder,
            settlementAsset: address(token),
            targetAmount: 101,
            minContribution: 101,
            maxContribution: 101,
            maxTotal: 101,
            deadline: uint64(block.timestamp + 1 days),
            mode: ContributionCampaign.PayoutMode.THRESHOLD_ESCROW,
            reconciledTotal: 0,
            closed: false
        });
        campaign.create(tinyProgram, c);
        campaign.reconcileChild(tinyProgram, keccak256("tiny-child"), 101, keccak256("tiny-receipt"));
        bytes32 tinyAgg = campaign.close(tinyProgram);
        address[] memory recipients = _recipients();
        uint16[] memory bps = _bps(3333, 3333, 3334);
        token.mint(funder, 101);
        vm.startPrank(funder);
        token.approve(address(splitter), 101);
        bytes32 distributionId = splitter.createDistribution(
            CampaignPayoutSplitter.CreateDistributionInput({
                campaignId: tinyProgram,
                campaignContract: address(campaign),
                token: IERC20Minimal(address(token)),
                totalAmount: 101,
                recipients: recipients,
                bps: bps,
                parentCampaignReceiptHash: tinyAgg,
                deadline: uint64(block.timestamp + 1 days),
                recovery: recovery
            })
        );
        vm.stopPrank();
        assertEq(splitter.recipientShareAt(distributionId, 0).amount, 33);
        assertEq(splitter.recipientShareAt(distributionId, 1).amount, 33);
        assertEq(splitter.recipientShareAt(distributionId, 2).amount, 35);
    }

    function test_rejectsInvalidBpsDuplicateZeroAndBeforeCampaignClose() public {
        vm.startPrank(funder);
        token.approve(address(splitter), total);
        vm.expectRevert(CampaignPayoutSplitter.InvalidDistribution.selector);
        splitter.createDistribution(
            CampaignPayoutSplitter.CreateDistributionInput({
                campaignId: programId,
                campaignContract: address(campaign),
                token: IERC20Minimal(address(token)),
                totalAmount: total,
                recipients: _recipients(),
                bps: _bps(7000, 2000, 999),
                parentCampaignReceiptHash: aggregateReceipt,
                deadline: uint64(block.timestamp + 1 days),
                recovery: recovery
            })
        );
        vm.stopPrank();

        address[] memory recipients = _recipients();
        recipients[1] = recipients[0];
        vm.startPrank(funder);
        token.approve(address(splitter), total);
        vm.expectRevert(abi.encodeWithSelector(CampaignPayoutSplitter.DuplicateRecipient.selector, creator));
        splitter.createDistribution(
            CampaignPayoutSplitter.CreateDistributionInput({
                campaignId: programId,
                campaignContract: address(campaign),
                token: IERC20Minimal(address(token)),
                totalAmount: total,
                recipients: recipients,
                bps: _bps(7000, 2000, 1000),
                parentCampaignReceiptHash: aggregateReceipt,
                deadline: uint64(block.timestamp + 1 days),
                recovery: recovery
            })
        );
        vm.stopPrank();

        recipients = _recipients();
        recipients[2] = address(0);
        vm.startPrank(funder);
        token.approve(address(splitter), total);
        vm.expectRevert(CampaignPayoutSplitter.InvalidRecipient.selector);
        splitter.createDistribution(
            CampaignPayoutSplitter.CreateDistributionInput({
                campaignId: programId,
                campaignContract: address(campaign),
                token: IERC20Minimal(address(token)),
                totalAmount: total,
                recipients: recipients,
                bps: _bps(7000, 2000, 1000),
                parentCampaignReceiptHash: aggregateReceipt,
                deadline: uint64(block.timestamp + 1 days),
                recovery: recovery
            })
        );
        vm.stopPrank();

        bytes32 openProgram = keccak256("open");
        ContributionCampaign.Campaign memory c = ContributionCampaign.Campaign({
            recipient: funder,
            settlementAsset: address(token),
            targetAmount: total,
            minContribution: 10 ether,
            maxContribution: 10 ether,
            maxTotal: total,
            deadline: uint64(block.timestamp + 1 days),
            mode: ContributionCampaign.PayoutMode.THRESHOLD_ESCROW,
            reconciledTotal: 0,
            closed: false
        });
        campaign.create(openProgram, c);
        vm.startPrank(funder);
        token.approve(address(splitter), total);
        vm.expectRevert(CampaignPayoutSplitter.InvalidDistribution.selector);
        splitter.createDistribution(
            CampaignPayoutSplitter.CreateDistributionInput({
                campaignId: openProgram,
                campaignContract: address(campaign),
                token: IERC20Minimal(address(token)),
                totalAmount: total,
                recipients: _recipients(),
                bps: _bps(7000, 2000, 1000),
                parentCampaignReceiptHash: aggregateReceipt,
                deadline: uint64(block.timestamp + 1 days),
                recovery: recovery
            })
        );
        vm.stopPrank();
    }

    function test_claimAccessDoubleClaimExpiryAndRecovery() public {
        bytes32 distributionId = _createDefaultDistribution(total, _bps(7000, 2000, 1000));
        vm.prank(outsider);
        vm.expectRevert(CampaignPayoutSplitter.NotRecipient.selector);
        splitter.claim(distributionId);

        vm.prank(creator);
        splitter.claim(distributionId);
        vm.prank(creator);
        vm.expectRevert(CampaignPayoutSplitter.AlreadyClaimed.selector);
        splitter.claim(distributionId);

        vm.warp(block.timestamp + 2 days);
        vm.prank(collaborator);
        vm.expectRevert(CampaignPayoutSplitter.Expired.selector);
        splitter.claim(distributionId);

        splitter.recoverExpired(distributionId);
        assertEq(token.balanceOf(recovery), 6 ether);
        (uint256 totalAmount, uint256 claimedTotal, uint256 unclaimed, uint256 recovered) =
            splitter.distributionTotals(distributionId);
        assertEq(totalAmount, total);
        assertEq(claimedTotal, 14 ether);
        assertEq(unclaimed, 0);
        assertEq(recovered, 6 ether);

        vm.expectRevert(CampaignPayoutSplitter.AlreadyRecovered.selector);
        splitter.recoverExpired(distributionId);
        vm.prank(collaborator);
        vm.expectRevert(CampaignPayoutSplitter.AlreadyRecovered.selector);
        splitter.claim(distributionId);
    }

    function test_recoverBeforeExpiryReverts() public {
        bytes32 distributionId = _createDefaultDistribution(total, _bps(7000, 2000, 1000));
        vm.expectRevert(CampaignPayoutSplitter.NotExpired.selector);
        splitter.recoverExpired(distributionId);
    }

    function _createDefaultDistribution(uint256 amount, uint16[] memory bps) internal returns (bytes32) {
        return _createDistribution(_recipients(), bps, amount, aggregateReceipt, programId);
    }

    function _createDistribution(
        address[] memory recipients,
        uint16[] memory bps,
        uint256 amount,
        bytes32 parentReceipt,
        bytes32 campaignId
    ) internal returns (bytes32) {
        vm.startPrank(funder);
        token.approve(address(splitter), amount);
        bytes32 distributionId = splitter.createDistribution(
            CampaignPayoutSplitter.CreateDistributionInput({
                campaignId: campaignId,
                campaignContract: address(campaign),
                token: IERC20Minimal(address(token)),
                totalAmount: amount,
                recipients: recipients,
                bps: bps,
                parentCampaignReceiptHash: parentReceipt,
                deadline: uint64(block.timestamp + 1 days),
                recovery: recovery
            })
        );
        vm.stopPrank();
        return distributionId;
    }

    function _recipients() internal view returns (address[] memory recipients) {
        recipients = new address[](3);
        recipients[0] = creator;
        recipients[1] = collaborator;
        recipients[2] = referrer;
    }

    function _bps(uint16 a, uint16 b, uint16 c) internal pure returns (uint16[] memory bps) {
        bps = new uint16[](3);
        bps[0] = a;
        bps[1] = b;
        bps[2] = c;
    }
}
