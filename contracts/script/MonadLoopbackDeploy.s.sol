// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console2} from "forge-std/Script.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {GlyphLayerZeroApplication} from "../src/GlyphLayerZeroApplication.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {TestToken} from "../src/TestToken.sol";
import {LocalLoopbackGlyphAdapter} from "../src/LocalLoopbackGlyphAdapter.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";

/// @notice Deploys a CURRENT-source Monad loopback stack (adapter + srcApp + dstApp + fresh vault),
/// seeds the vault, and wires/authorizes everything. Fixes the stale-deployed-vault issue.
contract MonadLoopbackDeploy is Script {
    SourceDeltaRouter router = SourceDeltaRouter(0xC71C119B91Fa1F1861626843Fa653F41cEF9101A);
    TestToken token = TestToken(0x1d482783316FdeF2e795A1C193ACE280660A887a);
    bytes32 policyHash = 0x9f2b1c4e7a3d5f6082b4c9e1d7a0f3b6c5e8d2a4b7c9e1f3a5b7c9d1e3f5a7b9;
    uint256 SEED = 1_000_000 ether;

    function run() external {
        uint256 pk = vm.envUint("MONAD_PK");
        address owner = vm.addr(pk);
        vm.startBroadcast(pk);

        // 1) fresh current-source vault + seed
        DestinationGlyphVault vault = new DestinationGlyphVault();
        console2.log("loopback vault:", address(vault));
        token.mint(owner, SEED);
        token.approve(address(vault), SEED);
        vault.provideLiquidity(IERC20Minimal(address(token)), SEED);
        console2.log("vault seeded gTST:", vault.providedLiquidity(address(token)) / 1e18);

        // 2) one shared synchronous loopback adapter
        LocalLoopbackGlyphAdapter adapter = new LocalLoopbackGlyphAdapter();
        console2.log("loopback adapter:", address(adapter));

        // 3) SOURCE app (entrypoint) + DESTINATION app (delivery). They point at each other.
        GlyphLayerZeroApplication srcApp =
            new GlyphLayerZeroApplication(GlyphLayerZeroApplication.Side.SOURCE, 10143, 10143, router, vault, owner);
        GlyphLayerZeroApplication dstApp = new GlyphLayerZeroApplication(
            GlyphLayerZeroApplication.Side.DESTINATION, 10143, 10143, router, vault, owner
        );
        console2.log("source app:", address(srcApp));
        console2.log("dest   app:", address(dstApp));

        // 4) wire: router authorizes adapter + both apps as processors
        router.setMessengerAdapter(address(adapter), true);
        router.setMessengerProcessorForAdapter(address(srcApp), address(adapter), true);
        router.setMessengerProcessorForAdapter(address(dstApp), address(adapter), true);

        // 5) apps point at each other; dstApp authorized on the fresh vault
        srcApp.setAdapter(adapter);
        srcApp.setRemoteApplication(address(dstApp));
        srcApp.freezeConfig(policyHash);

        dstApp.setAdapter(adapter);
        dstApp.setRemoteApplication(address(srcApp));
        dstApp.freezeConfig(policyHash);

        vault.setAuthorizedApplication(address(dstApp), true);
        console2.log("vault authorized dest app:", vault.authorizedApplication(address(dstApp)));

        console2.log("wired + frozen.");
        console2.log("NEXT: run MonadLoopbackPull with LOOP_APP=", vm.toString(address(srcApp)));
        console2.log("fresh vault=", vm.toString(address(vault)), " destApp=", vm.toString(address(dstApp)));
        vm.stopBroadcast();
    }
}
