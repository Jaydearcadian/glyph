// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {GlyphLayerZeroApplication} from "../src/GlyphLayerZeroApplication.sol";
import {TestToken} from "../src/TestToken.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";

contract MonadLocalPull is Script {
    // Deployed Monad Testnet (10143) addresses
    SourceDeltaRouter router = SourceDeltaRouter(0xC71C119B91Fa1F1861626843Fa653F41cEF9101A);
    GlyphLayerZeroApplication app = GlyphLayerZeroApplication(payable(0xb30a58245300127110583925956207f859947936));
    TestToken token = TestToken(0x1d482783316FdeF2e795A1C193ACE280660A887a);
    address vault = 0x5c9B29130A91c8419CCAa33D7fEBE6dE0B26824A;

    function run() external {
        uint256 pk = vm.envUint("MONAD_PK");
        address owner = vm.addr(pk);
        vm.startBroadcast(pk);

        bytes32 MODE_PULL = router.PULL();
        uint64 expiry = uint64(block.timestamp + 86400);
        uint256 maximumInput = 110 ether;
        uint256 destinationAmount = 100 ether;
        uint256 providerFee = 10 ether;
        address zero = address(0);

        SourceDeltaRouter.Terms memory t = SourceDeltaRouter.Terms({
            mode: MODE_PULL,
            programId: bytes32(0),
            payer: owner,
            recipient: owner,
            recovery: owner,
            sourceAsset: IERC20Minimal(address(token)),
            sourceChainId: 10143,
            destinationVault: vault,
            destinationAsset: address(token),
            destinationChainId: 10143,
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
            claimGatekeeper: zero,
            expiry: expiry,
            nonce: router.actorNonce(owner)
        });

        console2.log("actorNonce:", t.nonce);
        token.approve(address(router), maximumInput);
        bytes32 op = router.escrow(t);
        console2.log("escrowed op:", vm.toString(op));

        uint256 gasLimit = 300_000;
        uint256 fee = app.quoteRouteFromEscrow(op, gasLimit);
        console2.log("LZ fee (MON):", fee);
        app.sendRouteFromEscrow{value: fee}(op, payable(owner), gasLimit);
        console2.log("routed op:", vm.toString(op));
        console2.log(
            "NEXT: poll vault reservations(op) status==2, then run MonadLocalFinalize with OP env =", vm.toString(op)
        );

        vm.stopBroadcast();
    }
}
