// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract ContributionCampaign {
    enum PayoutMode {
        IMMEDIATE,
        THRESHOLD_ESCROW
    }

    struct Campaign {
        address recipient;
        address settlementAsset;
        uint256 targetAmount;
        uint256 minContribution;
        uint256 maxContribution;
        uint256 maxTotal;
        uint64 deadline;
        PayoutMode mode;
        uint256 reconciledTotal;
        bool closed;
    }
    mapping(bytes32 => Campaign) public campaigns;
    mapping(bytes32 => mapping(bytes32 => uint256)) public childAmount;
    mapping(bytes32 => bytes32[]) public childReceipts;
    error InvalidCampaign();
    error DuplicateCampaign();
    error InvalidContribution();
    error Closed();
    event CampaignCreated(bytes32 indexed programId, PayoutMode mode, uint256 targetAmount);
    event ChildReconciled(bytes32 indexed programId, bytes32 indexed childOperationId, uint256 amount);
    event CampaignClosed(bytes32 indexed programId, uint256 total, bytes32 aggregateReceiptHash);

    function create(bytes32 programId, Campaign calldata c) external {
        if (
            programId == bytes32(0) || campaigns[programId].recipient != address(0) || c.recipient == address(0)
                || c.targetAmount == 0 || c.maxTotal < c.targetAmount || c.minContribution == 0
                || c.maxContribution < c.minContribution
        ) revert InvalidCampaign();
        campaigns[programId] = c;
        emit CampaignCreated(programId, c.mode, c.targetAmount);
    }

    function reconcileChild(
        bytes32 programId,
        bytes32 childOperationId,
        uint256 normalizedAmount,
        bytes32 childReceiptHash
    ) external {
        Campaign storage c = campaigns[programId];
        if (c.closed) revert Closed();
        if (block.timestamp > c.deadline) revert Closed();
        if (
            childOperationId == bytes32(0) || childReceiptHash == bytes32(0) || normalizedAmount < c.minContribution
                || normalizedAmount > c.maxContribution || c.reconciledTotal + normalizedAmount > c.maxTotal
                || childAmount[programId][childOperationId] != 0
        ) revert InvalidContribution();
        childAmount[programId][childOperationId] = normalizedAmount;
        c.reconciledTotal += normalizedAmount;
        childReceipts[programId].push(childReceiptHash);
        emit ChildReconciled(programId, childOperationId, normalizedAmount);
    }

    function close(bytes32 programId) external returns (bytes32 aggregateReceiptHash) {
        Campaign storage c = campaigns[programId];
        if (c.closed) revert Closed();
        if (
            c.mode == PayoutMode.THRESHOLD_ESCROW && c.reconciledTotal < c.targetAmount && block.timestamp <= c.deadline
        ) revert InvalidContribution();
        c.closed = true;
        aggregateReceiptHash =
            keccak256(abi.encode("GLYPH_CAMPAIGN_RECEIPT", programId, c.reconciledTotal, childReceipts[programId]));
        emit CampaignClosed(programId, c.reconciledTotal, aggregateReceiptHash);
    }
}
