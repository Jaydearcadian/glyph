// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {LayerZeroV2GlyphMessengerAdapter} from "../src/LayerZeroV2GlyphMessengerAdapter.sol";
import {GlyphLayerZeroApplication} from "../src/GlyphLayerZeroApplication.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {TestToken} from "../src/TestToken.sol";
import {IGlyphMessengerAdapter} from "../src/interfaces/IGlyphMessengerAdapter.sol";
import {IERC20Minimal} from "../src/libraries/SafeToken.sol";

/// @notice Per-chain deployment parameters.
/// Fill these from `script/glyph.deploy.config.json` (or env) before broadcasting.
/// No private keys live here — forge reads the key from `--account` / `ETH_KEYSTORE`.
struct ChainConfig {
    uint64 chainId;
    uint32 eid;
    address lzEndpoint;
    // SAME-CHAIN contracts. If left as 0x0 the script deploys fresh router+vault+token.
    address router;
    address vault;
    address token; // ERC-20 moved by this chain's side of the operation
    // Set after the REMOTE chain's adapter is deployed (cross-fills post-broadcast).
    address remoteAdapter;
    address remoteApp;
    address remoteToken;
    bytes32 messengerPolicyHash; // external security config commitment (e.g. oracle/ULN hash)
    address owner; // deployer/operator; becomes contract owner
    uint256 enforcedGasLimit;
    uint256 ackGasLimit;
    bool orderedExecution;
    // E2E seeding amounts (raw token units, 18 decimals assumed)
    uint256 seedPayerAmount; // minted to owner (acts as payer + provider)
    uint256 seedVaultLiquidity; // provided into DestinationGlyphVault for deliveries
}

contract GlyphDeploy is Script {
    // ------------------------------------------------------------------
    // Base Sepolia  (chainId 84532, eid 40245)  — SOURCE side
    // Monad Testnet (chainId 10143, eid 40204)  — DESTINATION side
    // ------------------------------------------------------------------
    // Defaults are placeholders. Override via JSON config or env (GLYPH_BASE_*/GLYPH_MONAD_*).

    ChainConfig internal base;
    ChainConfig internal monad;

    // addresses stashed during the run so cross-wiring can read them
    mapping(uint64 => address) internal appAddr;
    mapping(uint64 => address) internal adapterAddr;
    mapping(uint64 => address) internal routerAddr;
    mapping(uint64 => address) internal vaultAddr;
    mapping(uint64 => address) internal tokenAddr;

    function run(string calldata configPath) external {
        _loadConfig(configPath);
        _deployChain(base, true);
        _deployChain(monad, false);
        _crossWire(base, monad);
        _crossWire(monad, base);
        _seedLiquidity(base);
        _seedLiquidity(monad);
        _freeze(base);
        _freeze(monad);
        _report();
    }

    // Convenience entrypoint: both chains from in-script defaults (no config file).
    function run() external {
        _defaults();
        _applyEnv(base, "GLYPH_BASE_");
        _applyEnv(monad, "GLYPH_MONAD_");
        _deployChain(base, true);
        _deployChain(monad, false);
        _crossWire(base, monad);
        _crossWire(monad, base);
        _seedLiquidity(base);
        _seedLiquidity(monad);
        _freeze(base);
        _freeze(monad);
        _report();
    }

    function _defaults() internal {
        // PLACEHOLDER values — DO NOT broadcast with these.
        base = ChainConfig({
            chainId: 84532,
            eid: 40245,
            lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
            router: address(0),
            vault: address(0),
            token: address(0),
            remoteAdapter: address(0),
            remoteApp: address(0),
            remoteToken: address(0),
            messengerPolicyHash: bytes32(0),
            owner: address(0),
            enforcedGasLimit: 200_000,
            ackGasLimit: 200_000,
            orderedExecution: true,
            seedPayerAmount: 1_000_000 ether,
            seedVaultLiquidity: 1_000_000 ether
        });
        monad = ChainConfig({
            chainId: 10143,
            eid: 40204,
            lzEndpoint: 0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff,
            router: address(0),
            vault: address(0),
            token: address(0),
            remoteAdapter: address(0),
            remoteApp: address(0),
            remoteToken: address(0),
            messengerPolicyHash: bytes32(0),
            owner: address(0),
            enforcedGasLimit: 200_000,
            ackGasLimit: 200_000,
            orderedExecution: true,
            seedPayerAmount: 1_000_000 ether,
            seedVaultLiquidity: 1_000_000 ether
        });
    }

    function _loadConfig(string calldata /*path*/) internal {
        _defaults();
        // Config resolution is done via env overrides (see _applyEnv). The JSON file is human reference.
        _applyEnv(base, "GLYPH_BASE_");
        _applyEnv(monad, "GLYPH_MONAD_");
    }

    function _applyEnv(ChainConfig storage c, string memory prefix) internal {
        address v;
        v = _envAddr(string(abi.encodePacked(prefix, "OWNER")));
        if (v != address(0)) c.owner = v;
        v = _envAddr(string(abi.encodePacked(prefix, "ROUTER")));
        if (v != address(0)) c.router = v;
        v = _envAddr(string(abi.encodePacked(prefix, "VAULT")));
        if (v != address(0)) c.vault = v;
        v = _envAddr(string(abi.encodePacked(prefix, "TOKEN")));
        if (v != address(0)) c.token = v;
        v = _envAddr(string(abi.encodePacked(prefix, "REMOTE_ADAPTER")));
        if (v != address(0)) c.remoteAdapter = v;
        v = _envAddr(string(abi.encodePacked(prefix, "REMOTE_APP")));
        if (v != address(0)) c.remoteApp = v;
        v = _envAddr(string(abi.encodePacked(prefix, "REMOTE_TOKEN")));
        if (v != address(0)) c.remoteToken = v;
        bytes32 ph = _envBytes32(string(abi.encodePacked(prefix, "POLICY_HASH")));
        if (ph != bytes32(0)) c.messengerPolicyHash = ph;
    }

    function _envAddr(string memory key) internal view returns (address) {
        try vm.envAddress(key) returns (address v) {
            return v;
        } catch {
            return address(0);
        }
    }

    function _envBytes32(string memory key) internal view returns (bytes32) {
        try vm.envBytes32(key) returns (bytes32 v) {
            return v;
        } catch {
            return bytes32(0);
        }
    }

    function _deployChain(ChainConfig memory c, bool isSource) internal {
        require(c.owner != address(0), "owner not set");
        require(c.messengerPolicyHash != bytes32(0), "policy hash not set");

        vm.startBroadcast();
        // Deploy or reuse same-chain core contracts.
        SourceDeltaRouter router =
            c.router == address(0) ? new SourceDeltaRouter() : SourceDeltaRouter(c.router);
        DestinationGlyphVault vault =
            c.vault == address(0) ? new DestinationGlyphVault() : DestinationGlyphVault(c.vault);
        TestToken token = c.token == address(0) ? new TestToken() : TestToken(c.token);

        // App is SOURCE-side or DESTINATION-side depending on isSource.
        GlyphLayerZeroApplication.Side side =
            isSource ? GlyphLayerZeroApplication.Side.SOURCE : GlyphLayerZeroApplication.Side.DESTINATION;
        GlyphLayerZeroApplication app = new GlyphLayerZeroApplication(
            side, c.chainId, _remoteChainId(c), router, vault, c.owner
        );
        LayerZeroV2GlyphMessengerAdapter adapter = new LayerZeroV2GlyphMessengerAdapter(
            c.lzEndpoint, c.chainId, c.eid, _remoteChainId(c), _remoteEid(c), c.owner, c.messengerPolicyHash
        );
        vm.stopBroadcast();

        _record(c.chainId, address(app), address(adapter), address(router), address(vault), address(token));
        console2.log("DEPLOYED chain", uint256(c.chainId));
        console2.log("  router", address(router));
        console2.log("  vault", address(vault));
        console2.log("  token", address(token));
        console2.log("  app", address(app));
        console2.log("  adapter", address(adapter));
    }

    function _record(uint64 chainId, address app, address adapter, address router, address vault, address token)
        internal
    {
        appAddr[chainId] = app;
        adapterAddr[chainId] = adapter;
        routerAddr[chainId] = router;
        vaultAddr[chainId] = vault;
        tokenAddr[chainId] = token;
    }

    function _crossWire(ChainConfig memory local, ChainConfig memory remote) internal {
        address localApp = appAddr[local.chainId];
        address localAdapter = adapterAddr[local.chainId];
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
        SourceDeltaRouter(routerAddr[local.chainId]).setMessengerAdapter(localAdapter, true);
        SourceDeltaRouter(routerAddr[local.chainId]).setMessengerProcessorForAdapter(localApp, localAdapter, true);
        DestinationGlyphVault(vaultAddr[local.chainId]).setAuthorizedApplication(localApp, true);
        vm.stopBroadcast();

        console2.log("CROSSWIRED", uint256(local.chainId), "->", uint256(remote.chainId));
    }

    // Seed E2E liquidity: owner acts as both payer and provider.
    // SOURCE chain: mint source token to owner (payer will approve router in the E2E script).
    // DESTINATION chain: mint destination token to owner, then provide liquidity into the vault.
    function _seedLiquidity(ChainConfig memory c) internal {
        address token = tokenAddr[c.chainId];
        require(token != address(0), "token not deployed");
        vm.startBroadcast();
        TestToken(token).mint(c.owner, c.seedPayerAmount);
        if (c.chainId != base.chainId) {
            // destination side: provider pre-funds the vault
            TestToken(token).approve(vaultAddr[c.chainId], c.seedVaultLiquidity);
            DestinationGlyphVault(vaultAddr[c.chainId]).provideLiquidity(IERC20Minimal(token), c.seedVaultLiquidity);
        }
        vm.stopBroadcast();
        console2.log("SEEDED liquidity chain", uint256(c.chainId), "token", token);
    }

    function _freeze(ChainConfig memory c) internal {
        address localApp = appAddr[c.chainId];
        address localAdapter = adapterAddr[c.chainId];
        vm.startBroadcast();
        GlyphLayerZeroApplication(payable(localApp)).freezeConfig(c.messengerPolicyHash);
        LayerZeroV2GlyphMessengerAdapter(payable(localAdapter)).freezeConfig(c.messengerPolicyHash);
        vm.stopBroadcast();
        console2.log("FROZEN", uint256(c.chainId));
    }

    function _remoteChainId(ChainConfig memory c) internal view returns (uint64) {
        return c.chainId == base.chainId ? monad.chainId : base.chainId;
    }

    function _remoteEid(ChainConfig memory c) internal view returns (uint32) {
        return c.chainId == base.chainId ? monad.eid : base.eid;
    }

    function _report() internal view {
        console2.log("=== Glyph cross-chain adapter stack ===");
        console2.log("Base Sepolia   app", appAddr[base.chainId], "adapter", adapterAddr[base.chainId]);
        console2.log("Monad Testnet  app", appAddr[monad.chainId], "adapter", adapterAddr[monad.chainId]);
        console2.log("Tokens: Base", tokenAddr[base.chainId], "Monad", tokenAddr[monad.chainId]);
        console2.log("Next: broadcast per chain, then run E2E lifecycle + read back receipts.");
    }
}
