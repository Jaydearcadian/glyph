// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {GlyphLayerZeroApplication} from "../src/GlyphLayerZeroApplication.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {TestToken} from "../src/TestToken.sol";
import {LocalLoopbackGlyphAdapter} from "../src/LocalLoopbackGlyphAdapter.sol";
import {ContributionCampaign} from "../src/ContributionCampaign.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";

/// @notice One-shot Monad testnet campaign proof:
/// deploy fresh current-source loopback stack + ContributionCampaign,
/// execute two child Pull operations from distinct contributors, reconcile both
/// child terminal receipts, then close the campaign into an aggregate receipt.
/// Requires env MONAD_PK and CONTRIBUTOR_B_PK. Testnet only.
contract MonadCampaignProof is Script {
    SourceDeltaRouter router = SourceDeltaRouter(0xC71C119B91Fa1F1861626843Fa653F41cEF9101A);
    TestToken token = TestToken(0x1d482783316FdeF2e795A1C193ACE280660A887a);
    bytes32 policyHash = 0x9f2b1c4e7a3d5f6082b4c9e1d7a0f3b6c5e8d2a4b7c9e1f3a5b7c9d1e3f5a7b9;

    uint256 constant VAULT_SEED = 100 ether;
    uint256 constant CONTRIBUTOR_TOP_UP = 25 ether;
    uint256 constant MAXIMUM_INPUT = 11 ether;
    uint256 constant DESTINATION_AMOUNT = 10 ether;
    uint256 constant PROVIDER_FEE = 1 ether;
    uint256 constant GAS_LIMIT = 300_000;

    struct Stack {
        DestinationGlyphVault vault;
        LocalLoopbackGlyphAdapter adapter;
        GlyphLayerZeroApplication srcApp;
        GlyphLayerZeroApplication dstApp;
        ContributionCampaign campaign;
    }

    function run() external {
        uint256 ownerPk = vm.envUint("MONAD_PK");
        uint256 contributorBPk = vm.envUint("CONTRIBUTOR_B_PK");
        address owner = vm.addr(ownerPk);
        address contributorA = owner;
        address contributorB = vm.addr(contributorBPk);
        address recipient = owner;

        vm.startBroadcast(ownerPk);
        Stack memory stack = _deployStack(owner);
        token.mint(contributorA, CONTRIBUTOR_TOP_UP);
        token.mint(contributorB, CONTRIBUTOR_TOP_UP);
        bytes32 programId = keccak256(
            abi.encode(
                "glyph.live.monad.campaign.v1",
                address(stack.campaign),
                block.chainid,
                router.actorNonce(contributorA),
                router.actorNonce(contributorB)
            )
        );
        _createCampaign(stack.campaign, programId, recipient);
        vm.stopBroadcast();

        bytes32 childA = _executePullAs(ownerPk, stack, contributorA, recipient, owner, programId, 0);
        bytes32 receiptA = stack.dstApp.sourceTerminalReceipt(childA);
        require(receiptA != bytes32(0), "receipt A missing");

        bytes32 childB = _executePullAs(contributorBPk, stack, contributorB, recipient, owner, programId, 1);
        bytes32 receiptB = stack.dstApp.sourceTerminalReceipt(childB);
        require(receiptB != bytes32(0), "receipt B missing");

        vm.startBroadcast(ownerPk);
        stack.campaign.reconcileChild(programId, childA, DESTINATION_AMOUNT, receiptA);
        stack.campaign.reconcileChild(programId, childB, DESTINATION_AMOUNT, receiptB);
        bytes32 aggregate = stack.campaign.close(programId);
        vm.stopBroadcast();

        console2.log("CAMPAIGN-PROOF COMPLETE", true);
        console2.log("owner/recipient", owner);
        console2.log("contributor A", contributorA);
        console2.log("contributor B", contributorB);
        console2.log("router", address(router));
        console2.log("token", address(token));
        console2.log("vault", address(stack.vault));
        console2.log("adapter", address(stack.adapter));
        console2.log("source app", address(stack.srcApp));
        console2.log("dest app", address(stack.dstApp));
        console2.log("campaign", address(stack.campaign));
        console2.log("program", vm.toString(programId));
        console2.log("child A", vm.toString(childA));
        console2.log("receipt A", vm.toString(receiptA));
        console2.log("child B", vm.toString(childB));
        console2.log("receipt B", vm.toString(receiptB));
        console2.log("aggregate receipt", vm.toString(aggregate));
        console2.log("recipient gTST", token.balanceOf(recipient) / 1e18);
        console2.log("contributor B gTST", token.balanceOf(contributorB) / 1e18);
    }

    function _deployStack(address owner) internal returns (Stack memory stack) {
        stack.vault = new DestinationGlyphVault();
        token.mint(owner, VAULT_SEED);
        token.approve(address(stack.vault), VAULT_SEED);
        stack.vault.provideLiquidity(IERC20Minimal(address(token)), VAULT_SEED);

        stack.adapter = new LocalLoopbackGlyphAdapter();
        stack.srcApp = new GlyphLayerZeroApplication(
            GlyphLayerZeroApplication.Side.SOURCE, 10143, 10143, router, stack.vault, owner
        );
        stack.dstApp = new GlyphLayerZeroApplication(
            GlyphLayerZeroApplication.Side.DESTINATION, 10143, 10143, router, stack.vault, owner
        );
        stack.campaign = new ContributionCampaign();

        router.setMessengerAdapter(address(stack.adapter), true);
        router.setMessengerProcessorForAdapter(address(stack.srcApp), address(stack.adapter), true);
        router.setMessengerProcessorForAdapter(address(stack.dstApp), address(stack.adapter), true);

        stack.srcApp.setAdapter(stack.adapter);
        stack.srcApp.setRemoteApplication(address(stack.dstApp));
        stack.srcApp.freezeConfig(policyHash);

        stack.dstApp.setAdapter(stack.adapter);
        stack.dstApp.setRemoteApplication(address(stack.srcApp));
        stack.dstApp.freezeConfig(policyHash);

        stack.vault.setAuthorizedApplication(address(stack.dstApp), true);
    }

    function _createCampaign(ContributionCampaign campaign, bytes32 programId, address recipient) internal {
        ContributionCampaign.Campaign memory c = ContributionCampaign.Campaign({
            recipient: recipient,
            settlementAsset: address(token),
            targetAmount: 20 ether,
            minContribution: 10 ether,
            maxContribution: 10 ether,
            maxTotal: 20 ether,
            deadline: uint64(block.timestamp + 1 days),
            mode: ContributionCampaign.PayoutMode.THRESHOLD_ESCROW,
            reconciledTotal: 0,
            closed: false
        });
        campaign.create(programId, c);
    }

    function _executePullAs(
        uint256 contributorPk,
        Stack memory stack,
        address contributor,
        address recipient,
        address provider,
        bytes32 programId,
        uint256 salt
    ) internal returns (bytes32 op) {
        vm.startBroadcast(contributorPk);
        SourceDeltaRouter.Terms memory t =
            _terms(router.PULL(), contributor, recipient, address(0), provider, programId, stack, salt);
        token.approve(address(router), MAXIMUM_INPUT);
        op = router.escrow(t);
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("MONAD_PK"));
        bytes32 routeId = stack.srcApp.sendRouteFromEscrow(op, payable(provider), GAS_LIMIT);
        stack.adapter.deliver(routeId);
        bytes32 deliveredAckId = stack.adapter.lastMessageId();
        stack.adapter.deliver(deliveredAckId);
        bytes32 receiptId = stack.srcApp.finalizeAndSendReceipt(op, payable(provider), GAS_LIMIT);
        stack.adapter.deliver(receiptId);
        vm.stopBroadcast();
    }

    function _terms(
        bytes32 mode,
        address payer,
        address recipient,
        address gatekeeper,
        address provider,
        bytes32 programId,
        Stack memory stack,
        uint256 salt
    ) internal view returns (SourceDeltaRouter.Terms memory) {
        salt; // programId + actor nonce already separate the child operations; keep arg for console trace stability.
        return SourceDeltaRouter.Terms({
            mode: mode,
            programId: programId,
            payer: payer,
            recipient: recipient,
            recovery: payer,
            sourceAsset: IERC20Minimal(address(token)),
            sourceChainId: 10143,
            destinationVault: address(stack.vault),
            destinationAsset: address(token),
            destinationChainId: 10143,
            maximumInput: MAXIMUM_INPUT,
            destinationAmount: DESTINATION_AMOUNT,
            protocolFee: 0,
            providerFee: PROVIDER_FEE,
            referrerFee: 0,
            gasSponsorFee: 0,
            provider: provider,
            protocol: provider,
            referrer: provider,
            gasSponsor: provider,
            claimGatekeeper: gatekeeper,
            expiry: uint64(block.timestamp + 1 days),
            nonce: router.actorNonce(payer)
        });
    }
}
