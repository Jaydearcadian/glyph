// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console2} from "forge-std/Script.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {GlyphLayerZeroApplication} from "../src/GlyphLayerZeroApplication.sol";
import {TestToken} from "../src/TestToken.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";

contract MonadLoopbackPull is Script {
    SourceDeltaRouter router = SourceDeltaRouter(0xC71C119B91Fa1F1861626843Fa653F41cEF9101A);
    GlyphLayerZeroApplication app;
    TestToken token = TestToken(0x1d482783316FdeF2e795A1C193ACE280660A887a);

    function run() external {
        uint256 pk = vm.envUint("MONAD_PK");
        address owner = vm.addr(pk);
        app = GlyphLayerZeroApplication(payable(vm.envAddress("LOOP_APP")));
        DestinationGlyphVault vault = app.vault();
        vm.startBroadcast(pk);

        bytes32 MODE_PULL = router.PULL();
        uint64 expiry = uint64(block.timestamp + 86400);
        uint256 maximumInput = 110 ether;
        uint256 destinationAmount = 100 ether;
        uint256 providerFee = 10 ether;

        SourceDeltaRouter.Terms memory t = SourceDeltaRouter.Terms({
            mode: MODE_PULL,
            programId: bytes32(0),
            payer: owner,
            recipient: owner,
            recovery: owner,
            sourceAsset: IERC20Minimal(address(token)),
            sourceChainId: 10143,
            destinationVault: address(vault),
            destinationAsset: address(token),
            destinationChainId: 10143, // same-chain Monad loopback
            maximumInput: maximumInput,
            destinationAmount: destinationAmount,
            protocolFee: 0,
            providerFee: providerFee,
            referrerFee: 0,
            gasSponsorFee: 0,
            provider: owner,
            protocol: owner,
            referrer: owner,
            gasSponsor: owner,
            claimGatekeeper: address(0),
            expiry: expiry,
            nonce: router.actorNonce(owner)
        });

        uint256 balBefore = token.balanceOf(owner);
        console2.log("actorNonce:", t.nonce);
        console2.log("balBefore (gTST):", balBefore / 1e18);
        token.approve(address(router), maximumInput);
        bytes32 op = router.escrow(t);
        console2.log("escrowed op:", vm.toString(op));

        // Route via loopback app: synchronous delivery to Monad vault + ACK back to self.
        uint256 gasLimit = 300_000;
        uint256 fee = app.quoteRouteFromEscrow(op, gasLimit); // loopback quote = 0
        console2.log("loopback fee:", fee);
        app.sendRouteFromEscrow(op, payable(owner), gasLimit);
        console2.log("routed (synchronous loopback delivery done)");

        // Finalize on source (Monad) — reads the looped-back DELIVERED_ACK terminal receipt.
        app.finalizeAndSendReceipt(op, payable(owner), gasLimit);
        bytes32 receipt = app.sourceTerminalReceipt(op);
        console2.log("finalized. sourceTerminalReceipt:", vm.toString(receipt));

        uint256 balAfter = token.balanceOf(owner);
        console2.log("balAfter (gTST):", balAfter / 1e18);
        console2.log("delivered delta (gTST):", (balAfter - balBefore) / 1e18);
        console2.log("MONAD-ONLY PULL COMPLETE:", receipt != bytes32(0));
        vm.stopBroadcast();
    }
}
