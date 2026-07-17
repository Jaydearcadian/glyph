// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IGlyphRegistry
/// @notice Interface for the Glyph Vessel registry: value escrow + session policy vault.
interface IGlyphRegistry {
    //////////////////////////////////////////////////////////////////////////
    //  Types
    //////////////////////////////////////////////////////////////////////////

    /// @notice Vessel configuration.
    enum VesselType {
        ValueOnly, // shareable, front-run-proof social payment
        AuthorityOnly, // ephemeral EIP-7702 session key
        Hybrid // funds + authority, atomic, single tx
    }

    /// @notice A Glyph Vessel: a single signed entry point carrying a payload.
    struct Vessel {
        bytes32 vesselId; // globally unique, off-chain derived
        VesselType vType;
        address creator;
        address token; // address(0) = native MON
        uint256 amount; // escrowed value
        address gatekeeper; // P_ephemeral derived from passcode
        bool claimed;
        uint256 createdAt;
        uint256 expiresAt; // 0 = never
    }

    /// @notice EIP-7702 session execution policy.
    struct SessionPolicy {
        address owner; // primary wallet that delegated
        address[] whitelistedTargets; // allowed call targets
        uint256 maxDrawdownNative; // hard cap on native MON spend
        uint256 maxDrawdownToken; // hard cap on ERC-20 spend
        address drawdownToken; // token the token cap applies to
        uint256 expiresAt; // block.timestamp limit
        bool revoked;
    }

    //////////////////////////////////////////////////////////////////////////
    //  Events
    //////////////////////////////////////////////////////////////////////////

    event VesselCreated(
        bytes32 indexed vesselId,
        VesselType vType,
        address indexed creator,
        address token,
        uint256 amount
    );
    event VesselClaimed(bytes32 indexed vesselId, address indexed claimant, uint256 amount);
    event VesselExpired(bytes32 indexed vesselId, address indexed creator);
    event SessionRegistered(bytes32 indexed sessionId, address indexed owner, uint256 expiresAt);
    event SessionRevoked(bytes32 indexed sessionId, address indexed owner);

    //////////////////////////////////////////////////////////////////////////
    //  Errors
    //////////////////////////////////////////////////////////////////////////

    error VesselExists();
    error VesselNotFound();
    error AlreadyClaimed();
    error NotExpired();
    error InvalidSignature();
    error Expired();
    error Unauthorized();
    error SessionExists();
    error InsufficientValue();
    error TransferFailed();

    //////////////////////////////////////////////////////////////////////////
    //  Value API
    //////////////////////////////////////////////////////////////////////////

    /// @notice Create a value-bearing Vessel (escrowed tokens behind a passcode gate).
    /// @param vesselId Off-chain derived unique id (keccak of nonce) to avoid storage OCC conflicts.
    /// @param token address(0) for native MON, else ERC-20.
    /// @param amount value to escrow.
    /// @param gatekeeper P_ephemeral address derived from the share passcode.
    /// @param expiresAt 0 = no expiry; else unix-seconds deadline.
    function createValueVessel(
        bytes32 vesselId,
        address token,
        uint256 amount,
        address gatekeeper,
        uint256 expiresAt
    ) external payable returns (bytes32);

    /// @notice Claim a value Vessel. Signature must be produced by the passcode's
    ///         ephemeral key over (msg.sender, vesselId) — binds to claimant, MEV-proof.
    function claimVessel(bytes32 vesselId, bytes calldata signature) external;

    /// @notice Recover an unclaimed, expired value Vessel back to the creator.
    function expireValueVessel(bytes32 vesselId) external;

    //////////////////////////////////////////////////////////////////////////
    //  Authority API
    //////////////////////////////////////////////////////////////////////////

    function registerSession(
        bytes32 sessionId,
        address[] calldata whitelistedTargets,
        uint256 maxDrawdownNative,
        uint256 maxDrawdownToken,
        address drawdownToken,
        uint256 expiresAt
    ) external returns (bytes32);

    function revokeSession(bytes32 sessionId) external;

    //////////////////////////////////////////////////////////////////////////
    //  Views
    //////////////////////////////////////////////////////////////////////////

    function vessels(bytes32 vesselId) external view returns (Vessel memory);
    function sessions(bytes32 sessionId) external view returns (SessionPolicy memory);
}
