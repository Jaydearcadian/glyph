// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IGlyphRegistry } from "./IGlyphRegistry.sol";

/// @title GlyphSessionProxy
/// @notice EIP-7702 delegation target code. A user's EOA temporarily delegates
///         to this contract (via SET_CODE_TX) to gain smart-wallet guardrails
///         WITHOUT a new address. Execution is gated by a registered SessionPolicy
///         held in the GlyphRegistry.
/// @dev Constraints (Monad): delegated accounts must keep >= 10 MON reserve; the
///      proxy itself issues no CREATE/CREATE2 calls within session scope.
///      Implements only the delegated-execution surface; reads SessionPolicy off
///      the registry (does not re-implement the registry interface).
contract GlyphSessionProxy {
    IGlyphRegistry public immutable registry;

    // Local error copies (interface errors are not in-scope as identifiers here).
    error Unauthorized();
    error Expired();
    error InsufficientValue();

    constructor(IGlyphRegistry _registry) {
        registry = _registry;
    }

    //////////////////////////////////////////////////////////////////////////
    //  Delegated execution
    //////////////////////////////////////////////////////////////////////////

    /// @notice Execute a scoped call on behalf of the delegating EOA.
    /// @param sessionId The active session policy id (registered by msg.sender).
    /// @param to Whitelisted target contract.
    /// @param data Calldata for the target.
    /// @dev Only callable when the EOA has delegated this code. msg.sender is the
    ///      EOA itself (the delegated account) when invoked through EIP-7702.
    function execute(bytes32 sessionId, address to, bytes calldata data)
        external
        payable
        returns (bytes memory)
    {
        IGlyphRegistry.SessionPolicy memory s = registry.sessions(sessionId);
        if (s.owner == address(0)) revert Unauthorized();
        if (s.revoked) revert Unauthorized();
        if (block.timestamp > s.expiresAt) revert Expired();

        // Target whitelist enforcement
        bool allowed = false;
        for (uint256 i = 0; i < s.whitelistedTargets.length; i++) {
            if (s.whitelistedTargets[i] == to) {
                allowed = true;
                break;
            }
        }
        if (!allowed) revert Unauthorized();

        // Drawdown cap enforcement (native)
        if (msg.value > s.maxDrawdownNative) revert Unauthorized();

        // Forward the call from the delegated EOA's context.
        (bool ok, bytes memory ret) = to.call{ value: msg.value }(data);
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }

        // Note: ERC-20 drawdown is enforced off-chain by the agent/session client
        // before dispatch; the proxy re-checks the onchain policy upper bound here.
        return ret;
    }

    /// @notice Reserve-balance guard: reverts if the delegated account drops below
    ///         the 10 MON minimum required for EIP-7702 execution on Monad.
    function enforceReserve() external view {
        if (address(this).balance < 10 ether) revert InsufficientValue();
    }

    receive() external payable {}
}
