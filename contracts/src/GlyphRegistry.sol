// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IGlyphRegistry } from "./IGlyphRegistry.sol";

/// @title GlyphRegistry
/// @notice The Glyph Vessel registry: a unified cryptographic envelope for
///         Value (escrowed tokens, front-run-proof) and Authority (EIP-7702
///         scoped session policy) payloads.
/// @dev Vessels are stored in an isolated mapping(bytes32 => Vessel) keyed by an
///      off-chain-derived vesselId, so concurrent deployments on Monad's parallel
///      OCC engine never touch the same storage slot.
contract GlyphRegistry is IGlyphRegistry {
    //////////////////////////////////////////////////////////////////////////
    //  Storage  (isolated mappings — no shared iterators => parallel-friendly)
    //////////////////////////////////////////////////////////////////////////

    mapping(bytes32 => Vessel) private _vessels;
    mapping(bytes32 => SessionPolicy) private _sessions;

    //////////////////////////////////////////////////////////////////////////
    //  Value API
    //////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IGlyphRegistry
    function createValueVessel(
        bytes32 vesselId,
        address token,
        uint256 amount,
        address gatekeeper,
        uint256 expiresAt
    ) external payable returns (bytes32) {
        if (_vessels[vesselId].vesselId != bytes32(0)) revert VesselExists();
        if (amount == 0) revert InsufficientValue();
        if (gatekeeper == address(0)) revert Unauthorized();

        if (token == address(0)) {
            if (msg.value != amount) revert InsufficientValue();
        } else {
            _pullERC20(token, msg.sender, amount);
        }

        _vessels[vesselId] = Vessel({
            vesselId: vesselId,
            vType: VesselType.ValueOnly,
            creator: msg.sender,
            token: token,
            amount: amount,
            gatekeeper: gatekeeper,
            claimed: false,
            createdAt: block.timestamp,
            expiresAt: expiresAt
        });

        emit VesselCreated(vesselId, VesselType.ValueOnly, msg.sender, token, amount);
        return vesselId;
    }

    /// @inheritdoc IGlyphRegistry
    function claimVessel(bytes32 vesselId, bytes calldata signature) external {
        Vessel storage v = _vessels[vesselId];
        if (v.vesselId == bytes32(0)) revert VesselNotFound();
        if (v.claimed) revert AlreadyClaimed();
        if (v.expiresAt != 0 && block.timestamp > v.expiresAt) revert Expired();

        // Front-run defense: the passcode's ephemeral key signs (msg.sender, vesselId).
        // A copied mempool tx from a different msg.sender fails ecrecover.
        bytes32 msgHash = _claimMessageHash(msg.sender, vesselId);
        address recovered = _recover(msgHash, signature);
        if (recovered != v.gatekeeper) revert InvalidSignature();

        v.claimed = true;
        _disburse(v.token, msg.sender, v.amount);

        emit VesselClaimed(vesselId, msg.sender, v.amount);
    }

    /// @inheritdoc IGlyphRegistry
    function expireValueVessel(bytes32 vesselId) external {
        Vessel storage v = _vessels[vesselId];
        if (v.vesselId == bytes32(0)) revert VesselNotFound();
        if (v.claimed) revert AlreadyClaimed();
        if (v.expiresAt == 0 || block.timestamp <= v.expiresAt) revert NotExpired();

        v.claimed = true; // lock to prevent double-spend
        _disburse(v.token, v.creator, v.amount);

        emit VesselExpired(vesselId, v.creator);
    }

    //////////////////////////////////////////////////////////////////////////
    //  Authority API  (EIP-7702 session policy vault)
    //////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IGlyphRegistry
    function registerSession(
        bytes32 sessionId,
        address[] calldata whitelistedTargets,
        uint256 maxDrawdownNative,
        uint256 maxDrawdownToken,
        address drawdownToken,
        uint256 expiresAt
    ) external returns (bytes32) {
        if (_sessions[sessionId].owner != address(0)) revert SessionExists();
        if (expiresAt <= block.timestamp) revert Expired();

        _sessions[sessionId] = SessionPolicy({
            owner: msg.sender,
            whitelistedTargets: whitelistedTargets,
            maxDrawdownNative: maxDrawdownNative,
            maxDrawdownToken: maxDrawdownToken,
            drawdownToken: drawdownToken,
            expiresAt: expiresAt,
            revoked: false
        });

        emit SessionRegistered(sessionId, msg.sender, expiresAt);
        return sessionId;
    }

    /// @inheritdoc IGlyphRegistry
    function revokeSession(bytes32 sessionId) external {
        SessionPolicy storage s = _sessions[sessionId];
        if (s.owner == address(0)) revert Unauthorized();
        if (msg.sender != s.owner) revert Unauthorized();
        s.revoked = true;
        emit SessionRevoked(sessionId, s.owner);
    }

    //////////////////////////////////////////////////////////////////////////
    //  Views
    //////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IGlyphRegistry
    function vessels(bytes32 vesselId) external view returns (Vessel memory) {
        return _vessels[vesselId];
    }

    /// @inheritdoc IGlyphRegistry
    function sessions(bytes32 sessionId) external view returns (SessionPolicy memory) {
        return _sessions[sessionId];
    }

    //////////////////////////////////////////////////////////////////////////
    //  Internal helpers
    //////////////////////////////////////////////////////////////////////////

    /// @notice Claim message hash. Binds the signature to the claimant and vessel.
    function _claimMessageHash(address claimant, bytes32 vesselId) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(claimant, vesselId));
    }

    function _recover(bytes32 msgHash, bytes calldata sig) private pure returns (address) {
        if (sig.length != 65) revert InvalidSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 0x20))
            v := byte(0, calldataload(add(sig.offset, 0x40)))
        }
        if (v < 27) v += 27;
        address recovered = ecrecover(_toEthSignedMessageHash(msgHash), v, r, s);
        if (recovered == address(0)) revert InvalidSignature();
        return recovered;
    }

    function _toEthSignedMessageHash(bytes32 hash) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function _pullERC20(address token, address from, uint256 amount) private {
        // Minimal ERC-20 pull (no return-value checks for gas savings; standard tokens return bool).
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, address(this), amount)
        );
        if (!ok) revert TransferFailed();
        if (ret.length > 0 && abi.decode(ret, (uint256)) == 0 && _isStrictToken(token)) {
            revert TransferFailed();
        }
    }

    function _disburse(address token, address to, uint256 amount) private {
        if (token == address(0)) {
            (bool ok, ) = payable(to).call{ value: amount }("");
            if (!ok) revert TransferFailed();
        } else {
            (bool ok, ) = token.call(
                abi.encodeWithSignature("transfer(address,uint256)", to, amount)
            );
            if (!ok) revert TransferFailed();
        }
    }

    function _isStrictToken(address) private pure returns (bool) {
        return true; // conservative: enforce non-zero return on ERC-20 paths
    }

    receive() external payable {}
}
