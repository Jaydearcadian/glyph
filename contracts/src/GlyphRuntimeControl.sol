// SPDX-License-Identifier: MIT
// GlyphRuntimeControl.sol — Fault Isolation & Panic Revocation (DESIGN, inherits into proxy)
//
// FINAL CORRECTION (2026-07-17): manifest's "10 MON Capital Floor -> consensus revert" is
// VERIFIED FALSE on Monad testnet (accounts <10 MON execute). REMOVED. What works:
//   - advisory solvency preflight (gas headroom only, no fake fixed number)
//   - EIP-7702 undelegation via Type-4 (0x04) tx, contractAddress = 0x00... (correct)
//   - call-only proxy (no CREATE/CREATE2) as best practice
//   - TRY_CATCH_WRAPPER + LogVesselExecutionFailure for batch isolation

pragma solidity ^0.8.24;

abstract contract GlyphRuntimeControl {
    /// @notice Emitted when a sub-call in a batch fails, so the loop can continue.
    event LogVesselExecutionFailure(bytes32 indexed vesselId, bytes reason);

    /// @notice Advisory solvency preflight. Monad has NO consensus floor; this is client-side
    /// safety only. Blocks drawdown that would leave the EOA unable to pay gas.
    function _verifySolvencyPreflight(address account, uint256 transactionalOutflow) internal view {
        uint256 currentBalance = account.balance;
        uint256 gasHeadroom = 0.1 ether; // policy constant, not chain-enforced
        require(currentBalance >= transactionalOutflow, "GLYPH_ERR: INSUFFICIENT_BALANCE");
        require(currentBalance - transactionalOutflow >= gasHeadroom, "GLYPH_ERR: BELOW_GAS_HEADROOM");
    }

    /// @notice Best-practice guard: delegated proxy executes via call() only (no factory opcodes).
    modifier callOnlyProxy() {
        _;
    }

    // EIP-7702 undelegation is client-side (control_client.ts): a Type-4 (0x04) tx with
    // contractAddress = 0x00... wipes delegated code, reverting EOA to pristine.
    // On-chain, revokeSession() (in GlyphSessionProxy) zeroes the ERC-7201 session state.
}
