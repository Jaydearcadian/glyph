// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Minimal, SafeToken} from "./libraries/SafeToken.sol";

contract GiftPool {
    using SafeToken for IERC20Minimal;

    struct Pool {
        IERC20Minimal asset;
        address creator;
        address recovery;
        uint256 fundedPool;
        uint256 denomination;
        uint64 expiry;
        uint256 totalClaimed;
        uint256 remainingPool;
        bool closed;
    }
    mapping(bytes32 => Pool) public pools;
    mapping(bytes32 => bool) public nullifierUsed;
    error InvalidPool();
    error InvalidClaim();
    error Closed();
    error Expired();
    event PoolFunded(bytes32 indexed programId, address asset, uint256 fundedPool, uint256 denomination);
    event Claimed(bytes32 indexed programId, address indexed claimant, uint256 amount, bytes32 nullifier);
    event PoolClosed(bytes32 indexed programId, uint256 returnedToRecovery, bytes32 closureReceiptHash);

    function fund(
        bytes32 programId,
        IERC20Minimal asset,
        uint256 fundedPool,
        uint256 denomination,
        uint64 expiry,
        address recovery
    ) external {
        if (
            programId == bytes32(0) || address(asset) == address(0) || fundedPool == 0 || denomination == 0
                || fundedPool < denomination || recovery == address(0) || pools[programId].creator != address(0)
        ) revert InvalidPool();
        asset.safeTransferFrom(msg.sender, address(this), fundedPool);
        pools[programId] = Pool(asset, msg.sender, recovery, fundedPool, denomination, expiry, 0, fundedPool, false);
        emit PoolFunded(programId, address(asset), fundedPool, denomination);
    }

    function claim(bytes32 programId, address claimant, bytes32 nullifier, uint64 deadline, bytes calldata signature)
        external
    {
        Pool storage p = pools[programId];
        if (p.closed) revert Closed();
        if (block.timestamp > p.expiry || block.timestamp > deadline) revert Expired();
        if (
            claimant == address(0) || nullifier == bytes32(0) || nullifierUsed[nullifier]
                || p.remainingPool < p.denomination
        ) revert InvalidClaim();
        bytes32 digest = keccak256(
            abi.encode(
                "GLYPH_GIFT_CLAIM",
                block.chainid,
                address(this),
                programId,
                claimant,
                p.denomination,
                nullifier,
                deadline
            )
        );
        (bytes32 r, bytes32 s, uint8 v) = _split(signature);
        if (ecrecover(digest, v, r, s) != claimant) revert InvalidClaim();
        nullifierUsed[nullifier] = true;
        p.totalClaimed += p.denomination;
        p.remainingPool -= p.denomination;
        p.asset.safeTransfer(claimant, p.denomination);
        emit Claimed(programId, claimant, p.denomination, nullifier);
    }

    function close(bytes32 programId) external returns (bytes32 closureReceiptHash) {
        Pool storage p = pools[programId];
        if (p.closed) revert Closed();
        if (block.timestamp <= p.expiry && p.remainingPool != 0) revert Expired();
        p.closed = true;
        uint256 returned = p.remainingPool;
        p.remainingPool = 0;
        if (returned != 0) p.asset.safeTransfer(p.recovery, returned);
        closureReceiptHash =
            keccak256(abi.encode("GLYPH_GIFT_POOL_RECEIPT", programId, p.fundedPool, p.totalClaimed, returned));
        emit PoolClosed(programId, returned, closureReceiptHash);
    }

    function _split(bytes calldata sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        if (sig.length != 65) revert InvalidClaim();
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v != 27 && v != 28) revert InvalidClaim();
    }
}
