// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {LayerZeroV2GlyphMessengerAdapter} from "../src/LayerZeroV2GlyphMessengerAdapter.sol";

/// @notice Dry-run only helper for reviewing constructor/config calldata.
/// Do not run with --broadcast. It reads placeholders from environment and reverts on unsafe blanks.
contract LayerZeroV2GlyphAdapterDryRunScript is Script {
    function run() external returns (LayerZeroV2GlyphMessengerAdapter adapter) {
        address endpoint = vm.envAddress("LZ_ENDPOINT_V2");
        uint64 localChainId = uint64(vm.envUint("GLYPH_LOCAL_CHAIN_ID"));
        uint32 localEid = uint32(vm.envUint("GLYPH_LOCAL_EID"));
        uint64 remoteChainId = uint64(vm.envUint("GLYPH_REMOTE_CHAIN_ID"));
        uint32 remoteEid = uint32(vm.envUint("GLYPH_REMOTE_EID"));
        address owner = vm.envAddress("GLYPH_OWNER_ADMIN");
        address localApp = vm.envAddress("GLYPH_LOCAL_APPLICATION");
        address remoteApp = vm.envAddress("GLYPH_REMOTE_APPLICATION");
        address trustedPeer = vm.envAddress("GLYPH_TRUSTED_REMOTE_ADAPTER");
        bytes32 policyHash = vm.envBytes32("GLYPH_MESSENGER_POLICY_HASH");
        uint256 enforcedGasLimit = vm.envOr("GLYPH_ENFORCED_RECEIVE_GAS", uint256(200_000));

        require(endpoint != address(0), "endpoint required");
        require(owner != address(0), "owner required");
        require(localApp != address(0), "local app required");
        require(remoteApp != address(0), "remote app required");
        require(trustedPeer != address(0), "trusted peer required");
        require(localChainId != 0 && remoteChainId != 0 && localChainId != remoteChainId, "chain ids required");
        require(localEid != 0 && remoteEid != 0 && localEid != remoteEid, "eids required");
        require(policyHash != bytes32(0), "policy hash required");
        require(enforcedGasLimit >= 50_000 && enforcedGasLimit <= 5_000_000, "gas limit bounds");

        adapter = new LayerZeroV2GlyphMessengerAdapter(
            endpoint, localChainId, localEid, remoteChainId, remoteEid, owner, policyHash
        );
        adapter.setTrustedPeer(trustedPeer);
        adapter.setLocalApplication(localApp);
        adapter.setRemoteApplication(remoteApp);
        adapter.setEnforcedGasLimit(enforcedGasLimit);
    }
}
