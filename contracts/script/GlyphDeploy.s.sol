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

/// @notice Per-chain deployment. Run TWICE (once per RPC), then finalize TWICE.
/// Chain is selected by `block.chainid` so a single script safely targets the RPC it runs on.
/// Run:
///   1) runDeploy()   on Base RPC  -> deploys Base stack (prints addresses)
///   2) runDeploy()   on Monad RPC -> deploys Monad stack (prints addresses)
///   3) runFinalize() on Base RPC  with GLYPH_REMOTE_APP/GLYPH_REMOTE_ADAPTER = Monad's app+adapter
///   4) runFinalize() on Monad RPC with GLYPH_REMOTE_APP/GLYPH_REMOTE_ADAPTER = Base's app+adapter
/// No private keys here — forge signs via --private-key / --account.

contract GlyphDeploy is Script {
    address internal OWNER;
    bytes32 internal POLICY;
    uint256 internal SEED = 1_000_000 ether;

    function _init() internal {
        require(block.chainid == 84532 || block.chainid == 10143, "unsupported chain");
        try vm.envAddress("GLYPH_OWNER") returns (address o) {
            OWNER = o;
        } catch {
            revert("GLYPH_OWNER env not set");
        }
        try vm.envBytes32("GLYPH_POLICY_HASH") returns (bytes32 p) {
            POLICY = p;
        } catch {
            revert("GLYPH_POLICY_HASH env not set");
        }
        require(OWNER != address(0) && POLICY != bytes32(0), "owner/policy unset");
    }

    function _isSource() internal view returns (bool) {
        return block.chainid == 84532; // Base Sepolia = SOURCE
    }

    function _remoteChainId() internal view returns (uint64) {
        return _isSource() ? 10143 : 84532;
    }

    function _remoteEid() internal view returns (uint32) {
        return _isSource() ? 40204 : 40245;
    }

    function _localEid() internal view returns (uint32) {
        return _isSource() ? 40245 : 40204;
    }

    function _lzEndpoint() internal view returns (address) {
        return _isSource() ? address(0x6EDCE65403992e310A62460808c4b910D972f10f)
            : address(0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff);
    }

    function _envAddr(string memory key) internal view returns (address) {
        try vm.envAddress(key) returns (address v) {
            return v;
        } catch {
            return address(0);
        }
    }

    // ---- Phase 1: deploy this chain's stack (no freeze) ----
    function runDeploy() external {
        _init();
        vm.startBroadcast();
        SourceDeltaRouter router = new SourceDeltaRouter();
        DestinationGlyphVault vault = new DestinationGlyphVault();
        TestToken token = new TestToken();
        GlyphLayerZeroApplication.Side side =
            _isSource() ? GlyphLayerZeroApplication.Side.SOURCE : GlyphLayerZeroApplication.Side.DESTINATION;
        GlyphLayerZeroApplication app = new GlyphLayerZeroApplication(
            side, uint64(block.chainid), _remoteChainId(), router, vault, OWNER
        );
        LayerZeroV2GlyphMessengerAdapter adapter = new LayerZeroV2GlyphMessengerAdapter(
            _lzEndpoint(), uint64(block.chainid), _localEid(), _remoteChainId(), _remoteEid(), OWNER, POLICY
        );
        vm.stopBroadcast();

        console2.log("DEPLOYED chain", uint256(block.chainid));
        console2.log("  router", address(router));
        console2.log("  vault", address(vault));
        console2.log("  token", address(token));
        console2.log("  app", address(app));
        console2.log("  adapter", address(adapter));
        console2.log("COPY THESE for the OTHER chain's GLYPH_REMOTE_APP / GLYPH_REMOTE_ADAPTER");
    }

    // ---- Phase 2: cross-wire + seed + freeze ----
    function runFinalize() external {
        _init();
        address rApp = _envAddr("GLYPH_REMOTE_APP");
        address rAdapter = _envAddr("GLYPH_REMOTE_ADAPTER");
        require(rAdapter != address(0) && rApp != address(0), "remote not set (GLYPH_REMOTE_APP/ADAPTER)");

        // Re-derive local addresses by redeploying? No — read from printed output is manual.
        // Instead, this script expects the local addresses via env too:
        address app = _envAddr("GLYPH_LOCAL_APP");
        address adapter = _envAddr("GLYPH_LOCAL_ADAPTER");
        address router = _envAddr("GLYPH_LOCAL_ROUTER");
        address vault = _envAddr("GLYPH_LOCAL_VAULT");
        address token = _envAddr("GLYPH_LOCAL_TOKEN");
        require(app != address(0) && adapter != address(0) && router != address(0) && vault != address(0)
            && token != address(0), "local addrs not set");

        vm.startBroadcast();
        GlyphLayerZeroApplication(payable(app)).setAdapter(IGlyphMessengerAdapter(adapter));
        GlyphLayerZeroApplication(payable(app)).setRemoteApplication(rApp);
        LayerZeroV2GlyphMessengerAdapter(payable(adapter)).setLocalApplication(app);
        LayerZeroV2GlyphMessengerAdapter(payable(adapter)).setRemoteApplication(rApp);
        LayerZeroV2GlyphMessengerAdapter(payable(adapter)).setTrustedPeer(rAdapter);
        LayerZeroV2GlyphMessengerAdapter(payable(adapter)).setEnforcedGasLimit(200_000);
        LayerZeroV2GlyphMessengerAdapter(payable(adapter)).setOrderedExecution(true);
        SourceDeltaRouter(router).setMessengerAdapter(adapter, true);
        SourceDeltaRouter(router).setMessengerProcessorForAdapter(app, adapter, true);
        DestinationGlyphVault(vault).setAuthorizedApplication(app, true);
        TestToken(token).mint(OWNER, SEED);
        if (!_isSource()) {
            TestToken(token).approve(vault, SEED);
            DestinationGlyphVault(vault).provideLiquidity(IERC20Minimal(token), SEED);
        }
        GlyphLayerZeroApplication(payable(app)).freezeConfig(POLICY);
        LayerZeroV2GlyphMessengerAdapter(payable(adapter)).freezeConfig(POLICY);
        vm.stopBroadcast();

        console2.log("FINALIZED chain", uint256(block.chainid), "remote", uint256(_remoteChainId()));
    }
}
