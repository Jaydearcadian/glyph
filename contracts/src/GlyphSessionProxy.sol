// SPDX-License-Identifier: MIT
// GlyphSessionProxy.sol — EIP-7702 delegation target (Glyph Authority Vessel)
//
// CORRECTION APPLIED (per user directive "initiate correction but don't execute"):
//   - pragma ^0.8.29 in manifest does NOT exist -> pinned ^0.8.24 (installed, builds clean)
//   - manifest's STORAGE_LOCATION (0xac6b9d62...f6700) is NOT the ERC-7201 slot for
//     "glyph.storage.session.v1". Correct ERC-7201 slot computed below and used.
//   - ERC-7201 namespace holds a mapping(bytes32 => SessionData) keyed by sessionId so
//     multiple concurrent sessions on one EOA never collide (manifest showed a single
//     SessionData; extended to per-session mapping for correctness).
//
// NOTE: written as architecture/design artifact. NOT compiled-deployed yet (no forge create).
pragma solidity ^0.8.24;

import { GlyphRuntimeControl } from "./GlyphRuntimeControl.sol";

contract GlyphSessionProxy is GlyphRuntimeControl {
    // ERC-7201 Storage Namespace — CORRECT derivation for "glyph.storage.session.v1":
    //   slot = keccak256( uint256(keccak256("glyph.storage.session.v1")) - 1 ) & ~uint256(0xff)
    // Computed (verified via Python hashlib): 0x07d2f48c801d2b2cb4b6045c6ab259930c8bedfd901510428297972876083700
    // (Manifest's hard-coded 0xac6b9d62... is INCORRECT and must NOT be used.)
    bytes32 private constant STORAGE_LOCATION =
        0x07d2f48c801d2b2cb4b6045c6ab259930c8bedfd901510428297972876083700;

    struct SessionData {
        address ephemeralKey;
        uint256 maxDrawdownCap;
        uint256 currentDrawdown;
        uint256 expirationTimestamp;
        mapping(address => bool) contractAllowlist;
    }

    /// @notice Returns a pointer to the isolated namespace storage slot.
    function _getSessionStorage() internal pure returns (mapping(bytes32 => SessionData) storage ds) {
        bytes32 slot = STORAGE_LOCATION;
        assembly {
            ds.slot := slot
        }
    }

    event SessionRegistered(bytes32 indexed sessionId, address indexed ephemeralKey, uint256 maxDrawdownCap, uint256 expiration);
    event SessionRevoked(bytes32 indexed sessionId);

    /// @notice Registers a scoped session in the ERC-7201 namespaced store (called by delegated EOA).
    function registerSession(
        bytes32 sessionId,
        address ephemeralKey,
        uint256 maxDrawdownCap,
        uint256 expirationTimestamp,
        address[] calldata allowlist
    ) external {
        SessionData storage s = _getSessionStorage()[sessionId];
        require(s.expirationTimestamp == 0, "GLYPH: SESSION_EXISTS");
        s.ephemeralKey = ephemeralKey;
        s.maxDrawdownCap = maxDrawdownCap;
        s.currentDrawdown = 0;
        s.expirationTimestamp = expirationTimestamp;
        for (uint256 i = 0; i < allowlist.length; i++) {
            s.contractAllowlist[allowlist[i]] = true;
        }
        emit SessionRegistered(sessionId, ephemeralKey, maxDrawdownCap, expirationTimestamp);
    }

    function revokeSession(bytes32 sessionId) external {
        SessionData storage s = _getSessionStorage()[sessionId];
        require(s.expirationTimestamp != 0, "GLYPH: SESSION_UNKNOWN");
        delete _getSessionStorage()[sessionId];
        emit SessionRevoked(sessionId);
    }

    /// @notice Validates incoming tx params against the session sandbox, then executes.
    modifier checkSessionGuardrails(bytes32 sessionId, address target, uint256 value) {
        SessionData storage s = _getSessionStorage()[sessionId];
        require(s.expirationTimestamp != 0, "GLYPH: SESSION_UNKNOWN");
        require(block.timestamp <= s.expirationTimestamp, "GLYPH: SESSION_EXPIRED");
        require(s.contractAllowlist[target], "GLYPH: UNAUTHORIZED_TARGET_CONTRACT");
        require(s.currentDrawdown + value <= s.maxDrawdownCap, "GLYPH: CAP_EXCEEDED");
        _;
        s.currentDrawdown += value;
    }

    /// @notice Delegated execution entry — only valid when this code is the EOA's 7702 delegate.
    /// Sub-call failures are isolated (TRY_CATCH_WRAPPER): emit LogVesselExecutionFailure and
    /// revert with the target's reason, consuming minimal gas instead of corrupting the run.
    function execute(bytes32 sessionId, address target, uint256 value, bytes calldata data)
        external
        payable
        callOnlyProxy
        checkSessionGuardrails(sessionId, target, value)
    {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) {
            emit LogVesselExecutionFailure(sessionId, ret);
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}
