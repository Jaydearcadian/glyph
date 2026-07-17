// SPDX-License-Identifier: MIT
// GlyphRegistry.sol — Asset escrow & front-run-proof value vault (DESIGN, not deployed)
//
// CORRECTIONS (per user directive, do not execute yet):
//   - pragma ^0.8.24 (manifest's 0.8.29 unavailable)
//   - OCC-safe: mapping(bytes32 => Vessel) KV store, NO global arrays/counters
//   - Off-chain ID: keccak256(abi.encodePacked(msg.sender, salt))
//   - Front-run-proof claim: ephemeral key from passcode, sig binds to msg.sender
//   - Authority sessions stored via GlyphSessionProxy ERC-7201 namespace (see proxy)
pragma solidity ^0.8.24;

import { IGlyphRegistry } from "./IGlyphRegistry.sol";

contract GlyphRegistry is IGlyphRegistry {
    // OCC-safe: isolated KV lanes, no global counters/arrays.
    mapping(bytes32 => IGlyphRegistry.Vessel) public vessels;

    /// @notice Off-chain deterministic ID (no sequential tracker).
    function _deriveId(address creator, bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(creator, salt));
    }

    function forgeVessel(address token, uint256 amount, address gatekeeper, bytes32 salt)
        external
        payable
        returns (bytes32 vesselId)
    {
        require(token == address(0), "GLYPH: ERC20_NOT_IMPL"); // native MON only in this build
        require(msg.value == amount, "GLYPH: VALUE_MISMATCH");
        vesselId = _deriveId(msg.sender, salt);
        require(vessels[vesselId].creator == address(0), "GLYPH: VESSEL_EXISTS");
        vessels[vesselId] = IGlyphRegistry.Vessel(msg.sender, token, amount, gatekeeper, false, uint64(block.timestamp + 1 hours));
        emit VesselForged(vesselId, msg.sender, token, amount);
    }

    function claimVessel(bytes32 vesselId, bytes calldata sig) external {
        IGlyphRegistry.Vessel storage v = vessels[vesselId];
        require(v.creator != address(0), "GLYPH: NOT_FOUND");
        require(!v.claimed, "GLYPH: CLAIMED");
        // Front-run shield: ecrecover of (msg.sender, vesselId) under Ethereum Signed Message
        // must equal v.gatekeeper. Binds sig to msg.sender -> replay from other address fails.
        bytes32 digest = _toEthSignedMessageHash(keccak256(abi.encodePacked(msg.sender, vesselId)));
        require(ecrecover(digest, uint8(sig[64]), bytes32(sig[0:32]), bytes32(sig[32:64])) == v.gatekeeper, "GLYPH: BAD_SIG");
        v.claimed = true;
        (bool ok, ) = msg.sender.call{value: v.amount}("");
        require(ok, "GLYPH: TRANSFER_FAILED");
        emit VesselClaimed(vesselId, msg.sender, v.amount);
    }

    function expireVessel(bytes32 vesselId) external {
        IGlyphRegistry.Vessel storage v = vessels[vesselId];
        require(v.creator != address(0), "GLYPH: NOT_FOUND");
        require(block.timestamp > v.expiry, "GLYPH: NOT_EXPIRED");
        require(!v.claimed, "GLYPH: CLAIMED");
        address to = v.creator;
        uint256 amt = v.amount;
        delete vessels[vesselId];
        (bool ok, ) = to.call{value: amt}("");
        require(ok, "GLYPH: TRANSFER_FAILED");
        emit VesselExpired(vesselId, to);
    }

    function _toEthSignedMessageHash(bytes32 h) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }
}
