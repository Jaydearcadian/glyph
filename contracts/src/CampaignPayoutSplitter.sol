// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Minimal, SafeToken} from "./libraries/SafeToken.sol";
import {ContributionCampaign} from "./ContributionCampaign.sol";

/// @notice Explicit-recipient campaign payout splitter for Glyph campaign receipts.
/// @dev Bounded/simple by design for hackathon product use: no Merkle tree, no hidden recipients.
contract CampaignPayoutSplitter {
    using SafeToken for IERC20Minimal;

    uint16 public constant BPS_DENOMINATOR = 10_000;

    struct CreateDistributionInput {
        bytes32 campaignId;
        address campaignContract;
        IERC20Minimal token;
        uint256 totalAmount;
        address[] recipients;
        uint16[] bps;
        bytes32 parentCampaignReceiptHash;
        uint64 deadline;
        address recovery;
    }

    struct Distribution {
        bytes32 campaignId;
        address campaignContract;
        IERC20Minimal token;
        address funder;
        address recovery;
        uint256 totalAmount;
        uint256 claimedTotal;
        uint256 recoveredAmount;
        bytes32 parentCampaignReceiptHash;
        bytes32 recipientsHash;
        uint64 deadline;
        bool recovered;
        uint32 recipientCount;
        uint32 claimedCount;
    }

    struct RecipientShare {
        address recipient;
        uint16 bps;
        uint256 amount;
        bool claimed;
        bytes32 claimReceiptHash;
    }

    mapping(bytes32 => Distribution) public distributions;
    mapping(bytes32 => RecipientShare[]) internal shares;
    mapping(bytes32 => mapping(address => uint256)) internal shareIndexPlusOne;

    bool internal locked;

    error InvalidDistribution();
    error DuplicateDistribution(bytes32 distributionId);
    error InvalidRecipient();
    error DuplicateRecipient(address recipient);
    error NotRecipient();
    error AlreadyClaimed();
    error AlreadyRecovered();
    error NotExpired();
    error Expired();
    error TransferFailed();

    event DistributionCreated(
        bytes32 indexed distributionId,
        bytes32 indexed campaignId,
        address indexed token,
        uint256 totalAmount,
        bytes32 parentCampaignReceiptHash,
        bytes32 recipientsHash,
        uint32 recipientCount
    );
    event DistributionClaimed(
        bytes32 indexed distributionId, address indexed recipient, uint256 amount, uint16 bps, bytes32 claimReceiptHash
    );
    event DistributionRecovered(bytes32 indexed distributionId, address indexed recovery, uint256 amount);

    modifier nonReentrant() {
        require(!locked, "reentrant");
        locked = true;
        _;
        locked = false;
    }

    function createDistribution(CreateDistributionInput calldata input)
        external
        nonReentrant
        returns (bytes32 distributionId)
    {
        uint256 n = input.recipients.length;
        if (
            input.campaignId == bytes32(0) || input.campaignContract == address(0) || address(input.token) == address(0)
                || input.totalAmount == 0 || input.parentCampaignReceiptHash == bytes32(0)
                || input.deadline <= block.timestamp || input.recovery == address(0) || n == 0 || n != input.bps.length
                || n > type(uint32).max
        ) revert InvalidDistribution();

        _requireParentCampaignClosed(input.campaignContract, input.campaignId, address(input.token), input.totalAmount);

        bytes32 recipientsHash = _recipientsHash(input.recipients, input.bps, input.totalAmount);
        distributionId = _distributionId(input, recipientsHash);
        if (distributions[distributionId].campaignId != bytes32(0)) revert DuplicateDistribution(distributionId);

        _storeShares(distributionId, input.recipients, input.bps, input.totalAmount);

        distributions[distributionId] = Distribution({
            campaignId: input.campaignId,
            campaignContract: input.campaignContract,
            token: input.token,
            funder: msg.sender,
            recovery: input.recovery,
            totalAmount: input.totalAmount,
            claimedTotal: 0,
            recoveredAmount: 0,
            parentCampaignReceiptHash: input.parentCampaignReceiptHash,
            recipientsHash: recipientsHash,
            deadline: input.deadline,
            recovered: false,
            recipientCount: uint32(n),
            claimedCount: 0
        });

        input.token.safeTransferFrom(msg.sender, address(this), input.totalAmount);
        emit DistributionCreated(
            distributionId,
            input.campaignId,
            address(input.token),
            input.totalAmount,
            input.parentCampaignReceiptHash,
            recipientsHash,
            uint32(n)
        );
    }

    function claim(bytes32 distributionId) external nonReentrant returns (bytes32 receiptHash) {
        Distribution storage d = _known(distributionId);
        if (d.recovered) revert AlreadyRecovered();
        if (block.timestamp > d.deadline) revert Expired();
        uint256 indexPlusOne = shareIndexPlusOne[distributionId][msg.sender];
        if (indexPlusOne == 0) revert NotRecipient();
        RecipientShare storage s = shares[distributionId][indexPlusOne - 1];
        if (s.claimed) revert AlreadyClaimed();

        s.claimed = true;
        d.claimedTotal += s.amount;
        d.claimedCount += 1;
        receiptHash = _claimReceiptHash(distributionId, msg.sender, s.amount, s.bps, d.parentCampaignReceiptHash);
        s.claimReceiptHash = receiptHash;
        d.token.safeTransfer(msg.sender, s.amount);
        emit DistributionClaimed(distributionId, msg.sender, s.amount, s.bps, receiptHash);
    }

    function recoverExpired(bytes32 distributionId) external nonReentrant returns (uint256 amount) {
        Distribution storage d = _known(distributionId);
        if (d.recovered) revert AlreadyRecovered();
        if (block.timestamp <= d.deadline) revert NotExpired();
        amount = d.totalAmount - d.claimedTotal;
        d.recovered = true;
        d.recoveredAmount = amount;
        if (amount != 0) d.token.safeTransfer(d.recovery, amount);
        emit DistributionRecovered(distributionId, d.recovery, amount);
    }

    function recipientShare(bytes32 distributionId, address recipient) external view returns (RecipientShare memory) {
        uint256 indexPlusOne = shareIndexPlusOne[distributionId][recipient];
        if (indexPlusOne == 0) revert NotRecipient();
        return shares[distributionId][indexPlusOne - 1];
    }

    function recipientShareAt(bytes32 distributionId, uint256 index) external view returns (RecipientShare memory) {
        return shares[distributionId][index];
    }

    function distributionTotals(bytes32 distributionId)
        external
        view
        returns (uint256 totalAmount, uint256 claimedTotal, uint256 unclaimedAmount, uint256 recoveredAmount)
    {
        Distribution storage d = _known(distributionId);
        return (d.totalAmount, d.claimedTotal, d.totalAmount - d.claimedTotal - d.recoveredAmount, d.recoveredAmount);
    }

    function claimReceiptHash(bytes32 distributionId, address recipient) external view returns (bytes32) {
        Distribution storage d = _known(distributionId);
        uint256 indexPlusOne = shareIndexPlusOne[distributionId][recipient];
        if (indexPlusOne == 0) revert NotRecipient();
        RecipientShare storage s = shares[distributionId][indexPlusOne - 1];
        return _claimReceiptHash(distributionId, recipient, s.amount, s.bps, d.parentCampaignReceiptHash);
    }

    function _known(bytes32 distributionId) internal view returns (Distribution storage d) {
        d = distributions[distributionId];
        if (d.campaignId == bytes32(0)) revert InvalidDistribution();
    }

    function _distributionId(CreateDistributionInput calldata input, bytes32 recipientsHash)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "GLYPH_DISTRIBUTION_V1",
                block.chainid,
                address(this),
                input.campaignContract,
                input.campaignId,
                address(input.token),
                input.totalAmount,
                input.parentCampaignReceiptHash,
                recipientsHash,
                input.deadline,
                input.recovery
            )
        );
    }

    function _storeShares(
        bytes32 distributionId,
        address[] calldata recipients,
        uint16[] calldata bps,
        uint256 totalAmount
    ) internal {
        uint256 totalBps;
        uint256 allocated;
        uint256 n = recipients.length;
        for (uint256 i = 0; i < n; i++) {
            address recipient = recipients[i];
            uint16 shareBps = bps[i];
            if (recipient == address(0) || shareBps == 0) revert InvalidRecipient();
            if (shareIndexPlusOne[distributionId][recipient] != 0) revert DuplicateRecipient(recipient);
            totalBps += shareBps;
            uint256 amount = i == n - 1 ? totalAmount - allocated : (totalAmount * shareBps) / BPS_DENOMINATOR;
            allocated += amount;
            shares[distributionId].push(RecipientShare(recipient, shareBps, amount, false, bytes32(0)));
            shareIndexPlusOne[distributionId][recipient] = i + 1;
        }
        if (totalBps != BPS_DENOMINATOR || allocated != totalAmount) revert InvalidDistribution();
    }

    function _requireParentCampaignClosed(
        address campaignContract,
        bytes32 campaignId,
        address token,
        uint256 totalAmount
    ) internal view {
        (address settlementAsset, uint256 reconciledTotal, bool closed) =
            _campaignDistributionFacts(campaignContract, campaignId);
        if (!closed || settlementAsset != token || reconciledTotal != totalAmount) revert InvalidDistribution();
    }

    function _campaignDistributionFacts(address campaignContract, bytes32 campaignId)
        internal
        view
        returns (address settlementAsset, uint256 reconciledTotal, bool closed)
    {
        return ContributionCampaign(campaignContract).campaignDistributionFacts(campaignId);
    }

    function _recipientsHash(address[] calldata recipients, uint16[] calldata bps, uint256 totalAmount)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode("GLYPH_DISTRIBUTION_RECIPIENTS_V1", recipients, bps, totalAmount));
    }

    function _claimReceiptHash(
        bytes32 distributionId,
        address recipient,
        uint256 amount,
        uint16 bps,
        bytes32 parentCampaignReceiptHash
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                "GLYPH_DISTRIBUTION_CLAIM_RECEIPT_V1",
                block.chainid,
                address(this),
                distributionId,
                recipient,
                amount,
                bps,
                parentCampaignReceiptHash
            )
        );
    }
}
