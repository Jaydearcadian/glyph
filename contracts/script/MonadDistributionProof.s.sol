// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ContributionCampaign} from "../src/ContributionCampaign.sol";
import {CampaignPayoutSplitter} from "../src/CampaignPayoutSplitter.sol";
import {TestToken} from "../src/TestToken.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";

/// @notice Live Monad proof for explicit-recipient campaign payout distribution:
/// campaign aggregate receipt -> distribution plan -> three recipient claims -> claim receipts.
/// Requires MONAD_PK. Uses deterministic throwaway recipient keys funded by owner for gas.
contract MonadDistributionProof is Script {
    TestToken constant token = TestToken(0x1d482783316FdeF2e795A1C193ACE280660A887a);

    uint256 constant TOTAL = 20 ether;
    uint256 constant CHILD_AMOUNT = 10 ether;
    uint256 constant RECIPIENT_B_PK = uint256(keccak256("glyph.live.monad.distribution.recipient.b.v1"));
    uint256 constant RECIPIENT_C_PK = uint256(keccak256("glyph.live.monad.distribution.recipient.c.v1"));

    ContributionCampaign campaign;
    CampaignPayoutSplitter splitter;
    bytes32 campaignId;
    bytes32 childA;
    bytes32 childB;
    bytes32 childReceiptA;
    bytes32 childReceiptB;
    bytes32 aggregateCampaignReceipt;
    bytes32 distributionId;
    bytes32 creatorClaim;
    bytes32 collaboratorClaim;
    bytes32 referrerClaim;
    address owner;
    address collaborator;
    address referrer;

    function run() external {
        require(block.chainid == 10143, "Monad testnet only");
        uint256 ownerPk = vm.envUint("MONAD_PK");
        owner = vm.addr(ownerPk);
        collaborator = vm.addr(RECIPIENT_B_PK);
        referrer = vm.addr(RECIPIENT_C_PK);

        vm.startBroadcast(ownerPk);
        _deployAndCreateCampaign();
        _createDistributionAndCreatorClaim();
        vm.stopBroadcast();

        vm.startBroadcast(RECIPIENT_B_PK);
        collaboratorClaim = splitter.claim(distributionId);
        vm.stopBroadcast();

        vm.startBroadcast(RECIPIENT_C_PK);
        referrerClaim = splitter.claim(distributionId);
        vm.stopBroadcast();

        _logProof();
    }

    function _deployAndCreateCampaign() internal {
        campaign = new ContributionCampaign();
        splitter = new CampaignPayoutSplitter();
        token.mint(owner, TOTAL);
        campaignId = keccak256(
            abi.encode("glyph.live.monad.distribution.v1", block.chainid, address(campaign), address(splitter), owner)
        );
        campaign.create(campaignId, _campaignTerms());
        childA = keccak256(abi.encode("glyph.live.distribution.child.a", campaignId));
        childB = keccak256(abi.encode("glyph.live.distribution.child.b", campaignId));
        childReceiptA = keccak256(abi.encode("glyph.live.distribution.child.receipt.a", campaignId, CHILD_AMOUNT));
        childReceiptB = keccak256(abi.encode("glyph.live.distribution.child.receipt.b", campaignId, CHILD_AMOUNT));
        campaign.reconcileChild(campaignId, childA, CHILD_AMOUNT, childReceiptA);
        campaign.reconcileChild(campaignId, childB, CHILD_AMOUNT, childReceiptB);
        aggregateCampaignReceipt = campaign.close(campaignId);
    }

    function _campaignTerms() internal view returns (ContributionCampaign.Campaign memory c) {
        c = ContributionCampaign.Campaign({
            recipient: owner,
            settlementAsset: address(token),
            targetAmount: TOTAL,
            minContribution: CHILD_AMOUNT,
            maxContribution: CHILD_AMOUNT,
            maxTotal: TOTAL,
            deadline: uint64(block.timestamp + 1 days),
            mode: ContributionCampaign.PayoutMode.THRESHOLD_ESCROW,
            reconciledTotal: 0,
            closed: false
        });
    }

    function _createDistributionAndCreatorClaim() internal {
        token.approve(address(splitter), TOTAL);
        distributionId = splitter.createDistribution(
            CampaignPayoutSplitter.CreateDistributionInput({
                campaignId: campaignId,
                campaignContract: address(campaign),
                token: IERC20Minimal(address(token)),
                totalAmount: TOTAL,
                recipients: _recipients(),
                bps: _bps(),
                parentCampaignReceiptHash: aggregateCampaignReceipt,
                deadline: uint64(block.timestamp + 1 days),
                recovery: owner
            })
        );
        creatorClaim = splitter.claim(distributionId);
    }

    function _recipients() internal view returns (address[] memory recipients) {
        recipients = new address[](3);
        recipients[0] = owner;
        recipients[1] = collaborator;
        recipients[2] = referrer;
    }

    function _bps() internal pure returns (uint16[] memory bps) {
        bps = new uint16[](3);
        bps[0] = 7000;
        bps[1] = 2000;
        bps[2] = 1000;
    }

    function _logProof() internal view {
        (uint256 totalAmount, uint256 claimedTotal, uint256 unclaimedAmount, uint256 recoveredAmount) =
            splitter.distributionTotals(distributionId);
        console2.log("DISTRIBUTION-PROOF COMPLETE", true);
        console2.log("owner/creator", owner);
        console2.log("collaborator", collaborator);
        console2.log("referrer", referrer);
        console2.log("token", address(token));
        console2.log("campaign", address(campaign));
        console2.log("splitter", address(splitter));
        console2.log("campaign id", vm.toString(campaignId));
        console2.log("child A", vm.toString(childA));
        console2.log("child receipt A", vm.toString(childReceiptA));
        console2.log("child B", vm.toString(childB));
        console2.log("child receipt B", vm.toString(childReceiptB));
        console2.log("aggregate campaign receipt", vm.toString(aggregateCampaignReceipt));
        console2.log("distribution id", vm.toString(distributionId));
        console2.log("creator claim receipt", vm.toString(creatorClaim));
        console2.log("collaborator claim receipt", vm.toString(collaboratorClaim));
        console2.log("referrer claim receipt", vm.toString(referrerClaim));
        console2.log("creator amount", token.balanceOf(owner));
        console2.log("collaborator amount", token.balanceOf(collaborator));
        console2.log("referrer amount", token.balanceOf(referrer));
        console2.log("distribution total", totalAmount);
        console2.log("claimed total", claimedTotal);
        console2.log("unclaimed amount", unclaimedAmount);
        console2.log("recovered amount", recoveredAmount);
    }
}
