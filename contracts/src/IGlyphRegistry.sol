// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IGlyphRegistry — Glyph Value Vessel interface (corrected, matches implementation)
interface IGlyphRegistry {
    /// @notice A Glyph Vessel: a single signed entry point carrying a value payload.
    struct Vessel {
        address creator;
        address token; // address(0) = native MON
        uint256 amount; // escrowed value
        address gatekeeper; // P_ephemeral derived from passcode
        bool claimed;
        uint64 expiry;
    }

    event VesselForged(bytes32 indexed vesselId, address indexed creator, address token, uint256 amount);
    event VesselClaimed(bytes32 indexed vesselId, address indexed claimant, uint256 amount);
    event VesselExpired(bytes32 indexed vesselId, address indexed creator);

    error InvalidSignature();
    error VesselExists();
    error VesselNotFound();

    /// @notice Forge a value Vessel. Off-chain deterministic ID = keccak256(msg.sender, salt).
    /// @param token address(0) for native MON, else ERC-20.
    /// @param amount value to escrow (in wei).
    /// @param gatekeeper P_ephemeral address derived client-side from the passcode.
    /// @param salt 32-byte entropy for off-chain OCC isolation.
    function forgeVessel(address token, uint256 amount, address gatekeeper, bytes32 salt)
        external
        payable
        returns (bytes32 vesselId);

    /// @notice Claim a Vessel. Signature must be (msg.sender, vesselId) under EIP-191,
    ///         signed by the passcode-derived ephemeral key. Binds to msg.sender (front-run-proof).
    function claimVessel(bytes32 vesselId, bytes calldata signature) external;

    /// @notice Recover an unclaimed, expired Vessel to its creator.
    function expireVessel(bytes32 vesselId) external;
}
