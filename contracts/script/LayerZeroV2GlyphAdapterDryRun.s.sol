// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {GlyphLayerZeroApplication} from "../src/GlyphLayerZeroApplication.sol";
import {IGlyphMessengerAdapter} from "../src/interfaces/IGlyphMessengerAdapter.sol";
import {LayerZeroV2GlyphMessengerAdapter} from "../src/LayerZeroV2GlyphMessengerAdapter.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";

/// @notice Dry-run only helper for reviewing constructor/config calldata.
/// Do not run with --broadcast. It uses placeholders/envs and performs no signing by itself.
contract LayerZeroV2GlyphAdapterDryRunScript is Script {
    struct DeployedDryRun {
        LayerZeroV2GlyphMessengerAdapter adapter;
        GlyphLayerZeroApplication app;
    }

    function run() external returns (DeployedDryRun memory out) {
        address endpoint = vm.envAddress("LZ_ENDPOINT_V2");
        uint64 localChainId = uint64(vm.envUint("GLYPH_LOCAL_CHAIN_ID"));
        uint32 localEid = uint32(vm.envUint("GLYPH_LOCAL_EID"));
        uint64 remoteChainId = uint64(vm.envUint("GLYPH_REMOTE_CHAIN_ID"));
        uint32 remoteEid = uint32(vm.envUint("GLYPH_REMOTE_EID"));
        address owner = vm.envAddress("GLYPH_OWNER_ADMIN");
        address routerAddr = vm.envAddress("GLYPH_SOURCE_ROUTER");
        address vaultAddr = vm.envAddress("GLYPH_DESTINATION_VAULT");
        address remoteApp = vm.envAddress("GLYPH_REMOTE_APPLICATION");
        address trustedPeer = vm.envAddress("GLYPH_TRUSTED_REMOTE_ADAPTER");
        bytes32 policyHash = vm.envBytes32("GLYPH_MESSENGER_POLICY_HASH");
        uint256 enforcedGasLimit = vm.envOr("GLYPH_ENFORCED_RECEIVE_GAS", uint256(200_000));
        uint256 sideRaw = vm.envOr("GLYPH_APP_SIDE_SOURCE_0_DESTINATION_1", uint256(0));

        require(endpoint != address(0), "endpoint required");
        require(owner != address(0), "owner required");
        require(routerAddr != address(0), "router required");
        require(vaultAddr != address(0), "vault required");
        require(remoteApp != address(0), "remote app required");
        require(trustedPeer != address(0), "trusted peer required");
        require(localChainId != 0 && remoteChainId != 0 && localChainId != remoteChainId, "chain ids required");
        require(localEid != 0 && remoteEid != 0 && localEid != remoteEid, "eids required");
        require(policyHash != bytes32(0), "policy hash required");
        require(enforcedGasLimit >= 50_000 && enforcedGasLimit <= 5_000_000, "gas limit bounds");
        require(sideRaw <= 1, "side bounds");

        out.adapter = new LayerZeroV2GlyphMessengerAdapter(
            endpoint, localChainId, localEid, remoteChainId, remoteEid, address(this), policyHash
        );
        out.app = new GlyphLayerZeroApplication(
            sideRaw == 0 ? GlyphLayerZeroApplication.Side.SOURCE : GlyphLayerZeroApplication.Side.DESTINATION,
            localChainId,
            remoteChainId,
            SourceDeltaRouter(routerAddr),
            DestinationGlyphVault(vaultAddr),
            address(this)
        );
        out.adapter.setTrustedPeer(trustedPeer);
        out.adapter.setLocalApplication(address(out.app));
        out.adapter.setRemoteApplication(remoteApp);
        out.adapter.setEnforcedGasLimit(enforcedGasLimit);
        out.app.setAdapter(IGlyphMessengerAdapter(address(out.adapter)));
        out.app.setRemoteApplication(remoteApp);
        out.app.transferOwnership(owner);
        out.adapter.transferOwnership(owner);
    }
}
