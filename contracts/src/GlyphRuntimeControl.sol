// SPDX-License-Identifier: MIT
// Glyph Runtime Control — Fault Isolation & Panic Revocation (DESIGN, not executed)
//
// CORRECTIONS vs raw manifest (verified against live Monad testnet 2026-07-17):
//   1. "10 MON Capital Floor -> unconditional revert at CONSENSUS layer" is FALSE.
//      No such consensus rule exists on Monad testnet (dead addr & deployer both <10 MON
//      and execute fine). Kept ONLY as a client-side / policy safety guardrail, clearly
//      labeled, NOT claimed as chain enforcement.
//   2. EIP-7702 undelegation via Type-4 (0x04) tx with contractAddress = 0x00... is CORRECT.
//      Adopted as absoluteVesselRevocation().
//   3. CREATE/CREATE2 ban in delegated code: adopted as BEST-PRACTICE guard, not a hard Monad ban.
//
// These are design additions to GlyphSessionProxy; not compiled/deployed yet.

pragma solidity ^0.8.24;

// --- Runtime control hooks to be merged into GlyphSessionProxy ---

/// @notice Client-side / policy 10-MON reserve guard. NOT a chain rule.
/// @dev Monad testnet has no consensus 10-MON floor; this is a protocol safety recommendation
///      to keep delegated accounts solvent for gas + drawdown headroom.
function verifyMonadStateInvariants(address account, uint256 transactionalOutflow) internal view {
    uint256 currentBalance = account.balance;
    uint256 RESERVE = 10 ether; // policy floor, advisory only
    if (currentBalance >= RESERVE) {
        require(currentBalance - transactionalOutflow >= RESERVE,
            "GLYPH_ERR: POLICY_RESERVE_VIOLATION"); // labeled POLICY, not consensus
    } else {
        require(transactionalOutflow == 0, "GLYPH_ERR: BALANCE_DIP_FORBIDDEN_UNDER_RESERVE");
    }
}

/// @notice Emitted on sub-call failure so the batch loop can continue (TRY_CATCH_WRAPPER).
event LogVesselExecutionFailure(bytes32 indexed vesselId, bytes reason);

/// @notice Best-practice guard: delegated proxy must never deploy inline bytecode.
/// (Monad does not hard-ban CREATE/CREATE2, but a delegated EOA should avoid them.)
modifier noFactoryOpcodes() {
    // Enforced client-side + by restricting proxy to call() only (no CREATE in execute()).
    _;
}

/// @notice EIP-7702 undelegation is performed client-side (see absoluteVesselRevocation in
///         control_client.ts). On-chain, revokeSession() zeroes the namespaced session state;
///         the actual code wipe happens via the 0x04 tx with contractAddress = 0x00...
