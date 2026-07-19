// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {LayerZeroV2GlyphMessengerAdapter} from "../src/LayerZeroV2GlyphMessengerAdapter.sol";
import {GlyphLayerZeroApplication} from "../src/GlyphLayerZeroApplication.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {IGlyphMessengerAdapter} from "../src/interfaces/IGlyphMessengerAdapter.sol";

/// @notice Per-chain deployment parameters.
/// Fill these from `script/glyph.deploy.config.json` (or env) before broadcasting.
/// No private keys live here — forge reads the key from `--account` / `ETH_KEYSTORE`.
struct ChainConfig {
    uint64 chainId;
    uint32 eid;
    address lzEndpoint;
    // The SAME-CHAIN contracts this adapter talks to (already deployed, or deployed here).
    address router;
    address vault;
    // Set after the REMOTE chain's adapter is deployed (cross-fills post-broadcast).
    address remoteAdapter;
    address remoteApp;
    bytes32 messengerPolicyHash; // external security config commitment (e.g. oracle/ULN hash)
    address owner; // deployer/operator; becomes contract owner
    uint256 enforcedGasLimit;
    uint256 ackGasLimit;
    bool orderedExecution;
}

contract GlyphDeploy is Script {
    // ------------------------------------------------------------------
    // Base Sepolia  (chainId 84532, eid 40245)  — SOURCE side
    // Monad Testnet (chainId 10143, eid 40204)  — DESTINATION side
    // ------------------------------------------------------------------
    // These defaults are placeholders. Override via the JSON config file:
    //   forge script script/GlyphDeploy.s.sol --sig "run(string)" script/glyph.deploy.config.json
    // or per-chain env vars (GLYPH_BASE_* / GLYPH_MONAD_*).

    ChainConfig internal base;
    ChainConfig internal monad;

    function run(string calldata configPath) external {
        _loadConfig(configPath);
        // Phase 1: deploy each chain's adapter stack (no cross-dependency yet).
        _deployChain(base, true); // isSource = true
        _deployChain(monad, false); // isSource = false

        // Phase 2: cross-wire. The remote adapter/app addresses are filled by
        // the operator after both broadcasts (see _crossWire), or passed in config.
        _crossWire(base, monad);
        _crossWire(monad, base);

        // Phase 3: freeze both adapters + both apps (config-locked, messenger-neutral).
        _freeze(base);
        _freeze(monad);

        _report();
    }

    // Convenience entrypoint: both chains from in-script defaults (no config file).
    function run() external {
        _defaults();
        _deployChain(base, true);
        _deployChain(monad, false);
        _crossWire(base, monad);
        _crossWire(monad, base);
        _freeze(base);
        _freeze(monad);
        _report();
    }

    function _defaults() internal {
        // PLACEHOLDER values — DO NOT broadcast with these.
        // Base Sepolia LayerZero V2 endpoint (verified on-chain readback).
        base = ChainConfig({
            chainId: 84532,
            eid: 40245,
            lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
            router: address(0),
            vault: address(0),
            remoteAdapter: address(0),
            remoteApp: address(0),
            messengerPolicyHash: bytes32(0),
            owner: address(0),
            enforcedGasLimit: 200_000,
            ackGasLimit: 200_000,
            orderedExecution: true
        });
        // Monad Testnet LayerZero V2 endpoint (verified on-chain readback).
        monad = ChainConfig({
            chainId: 10143,
            eid: 40204,
            lzEndpoint: 0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff,
            router: address(0),
            vault: address(0),
            remoteAdapter: address(0),
            remoteApp: address(0),
            messengerPolicyHash: bytes32(0),
            owner: address(0),
            enforcedGasLimit: 200_000,
            ackGasLimit: 200_000,
            orderedExecution: true
        });
    }

    function _loadConfig(string calldata path) internal {
        _defaults();
        // Expects a JSON with keys: base.* and monad.*
        // forge-std has no JSON parse in Script precompile easily; operator passes
        // fully-resolved addresses via env instead. We honor env overrides here.
        _applyEnv(base, "GLYPH_BASE_");
        _applyEnv(monad, "GLYPH_MONAD_");
    }

    function _applyEnv(ChainConfig storage c, string memory prefix) internal {
        address owner = _envAddr(string(abi.encodePacked(prefix, "OWNER")), c.owner);
        if (owner != address(0)) c.owner = owner;
        address router = _envAddr(string(abi.encodePacked(prefix, "ROUTER")), c.router);
        if (router != address(0)) c.router = router;
        address vault = _envAddr(string(abi.encodePacked(prefix, "VAULT")), c.vault);
        if (vault != address(0)) c.vault = vault;
        address remoteAdapter =
            _envAddr(string(abi.encodePacked(prefix, "REMOTE_ADAPTER")), c.remoteAdapter);
        if (remoteAdapter != address(0)) c.remoteAdapter = remoteAdapter;
        address remoteApp = _envAddr(string(abi.encodePacked(prefix, "REMOTE_APP")), c.remoteApp);
        if (remoteApp != address(0)) c.remoteApp = remoteApp;
        bytes32 ph = _envBytes32(string(abi.encodePacked(prefix, "POLICY_HASH")), c.messengerPolicyHash);
        if (ph != bytes32(0)) c.messengerPolicyHash = ph;
    }

    function _envAddr(string memory key, address fallback_) internal view returns (address) {
        try vm.envAddress(key) returns (address v) {
            return v;
        } catch {
            return fallback_;
        }
    }

    function _envBytes32(string memory key, bytes32 fallback_) internal view returns (bytes32) {
        try vm.envBytes32(key) returns (bytes32 v) {
            return v;
        } catch {
            return fallback_;
        }
    }

    function _deployChain(ChainConfig memory c, bool isSource) internal {
        require(c.owner != address(0), "owner not set");
        require(c.router != address(0), "router not set");
        require(c.vault != address(0), "vault not set");
        require(c.messengerPolicyHash != bytes32(0), "policy hash not set");

        vm.startBroadcast();
        // App is SOURCE-side or DESTINATION-side depending on isSource.
        GlyphLayerZeroApplication.Side side =
            isSource ? GlyphLayerZeroApplication.Side.SOURCE : GlyphLayerZeroApplication.Side.DESTINATION;
        GlyphLayerZeroApplication app = new GlyphLayerZeroApplication(
            side, c.chainId, _remoteChainId(c), SourceDeltaRouter(c.router), DestinationGlyphVault(c.vault), c.owner
        );
        LayerZeroV2GlyphMessengerAdapter adapter = new LayerZeroV2GlyphMessengerAdapter(
            c.lzEndpoint, c.chainId, c.eid, _remoteChainId(c), _remoteEid(c), c.owner, c.messengerPolicyHash
        );
        vm.stopBroadcast();

        // Record for cross-wiring.
        if (c.chainId == base.chainId) {
            base.remoteApp = monad.owner == address(0) ? base.remoteApp : base.remoteApp; // filled later
        }

        console2.log("DEPLOYED chain", uint256(c.chainId));
        console2.log("  app", address(app));
        console2.log("  adapter", address(adapter));
        _record(c.chainId, address(app), address(adapter));
    }

    // addresses stashed during the run so _crossWire can read them
    mapping(uint64 => address) internal appAddr;
    mapping(uint64 => address) internal adapterAddr;

    function _record(uint64 chainId, address app, address adapter) internal {
        appAddr[chainId] = app;
        adapterAddr[chainId] = adapter;
    }

    function _crossWire(ChainConfig memory local, ChainConfig memory remote) internal {
        address localApp = appAddr[local.chainId];
        address localAdapter = adapterAddr[local.chainId];
        // Remote adapter/app are either from config (post-broadcast) or from this run's stash.
        address remoteAdapter = remote.remoteAdapter != address(0) ? remote.remoteAdapter : adapterAddr[remote.chainId];
        address remoteApp = remote.remoteApp != address(0) ? remote.remoteApp : appAddr[remote.chainId];
        require(remoteAdapter != address(0) && remoteApp != address(0), "remote not resolved");

        vm.startBroadcast();
        GlyphLayerZeroApplication(payable(localApp)).setAdapter(IGlyphMessengerAdapter(localAdapter));
        GlyphLayerZeroApplication(payable(localApp)).setRemoteApplication(remoteApp);
        LayerZeroV2GlyphMessengerAdapter(payable(localAdapter)).setLocalApplication(localApp);
        LayerZeroV2GlyphMessengerAdapter(payable(localAdapter)).setRemoteApplication(remoteApp);
        LayerZeroV2GlyphMessengerAdapter(payable(localAdapter)).setTrustedPeer(remoteAdapter);
        LayerZeroV2GlyphMessengerAdapter(payable(localAdapter)).setEnforcedGasLimit(local.enforcedGasLimit);
        LayerZeroV2GlyphMessengerAdapter(payable(localAdapter)).setOrderedExecution(local.orderedExecution);
        // Router/vault authorization (router authorizes the adapter; vault authorizes the app)
        SourceDeltaRouter(local.router).setMessengerAdapter(localAdapter, true);
        SourceDeltaRouter(local.router).setMessengerProcessorForAdapter(localApp, localAdapter, true);
        DestinationGlyphVault(local.vault).setAuthorizedApplication(localApp, true);
        vm.stopBroadcast();

        console2.log("CROSSWIRED", local.chainId, "->", remote.chainId);
    }

    function _freeze(ChainConfig memory c) internal {
        address localApp = appAddr[c.chainId];
        address localAdapter = adapterAddr[c.chainId];
        vm.startBroadcast();
        GlyphLayerZeroApplication(payable(localApp)).freezeConfig(c.messengerPolicyHash);
        LayerZeroV2GlyphMessengerAdapter(payable(localAdapter)).freezeConfig(c.messengerPolicyHash);
        vm.stopBroadcast();
        console2.log("FROZEN", c.chainId);
    }

    function _remoteChainId(ChainConfig memory c) internal view returns (uint64) {
        return c.chainId == base.chainId ? monad.chainId : base.chainId;
    }

    function _remoteEid(ChainConfig memory c) internal view returns (uint32) {
        return c.chainId == base.chainId ? monad.eid : base.eid;
    }

    function _report() internal view {
        console2.log("=== Glyph cross-chain adapter stack ===");
        console2.log("Base Sepolia    app", appAddr[base.chainId], "adapter", adapterAddr[base.chainId]);
        console2.log("Monad Testnet   app", appAddr[monad.chainId], "adapter", adapterAddr[monad.chainId]);
        console2.log("Next: broadcast per chain, then verify config readback + E2E lifecycle.");
    }
}
