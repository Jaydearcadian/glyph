// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Minimal, SafeToken} from "./libraries/SafeToken.sol";

contract DestinationGlyphVault {
    using SafeToken for IERC20Minimal;

    enum Mode {
        NONE,
        PULL,
        PUSH
    }
    enum ReservationStatus {
        NONE,
        RESERVED,
        DELIVERED,
        RELEASED
    }

    struct Reservation {
        Mode mode;
        address asset;
        address provider;
        address recipient;
        uint256 amount;
        uint64 sourceChainId;
        address sourceApplication;
        uint64 expiry;
        bytes32 claimantRule;
        ReservationStatus status;
    }

    error InvalidReservation();
    error InsufficientLiquidity();
    error DuplicateReservation(bytes32 operationId);
    error AlreadyTerminal(bytes32 operationId);
    error UnauthorizedDomain();
    error Expired();
    error ClaimFailed();

    mapping(address => uint256) public providedLiquidity;
    mapping(address => uint256) public reservedLiquidity;
    mapping(bytes32 => Reservation) public reservations;
    mapping(bytes32 => bool) public nullifierUsed;

    event LiquidityProvided(address indexed provider, address indexed asset, uint256 amount);
    event Reserved(bytes32 indexed operationId, Mode mode, address asset, uint256 amount);
    event Delivered(bytes32 indexed operationId, address indexed recipient, uint256 amount, bytes32 nullifier);
    event Released(bytes32 indexed operationId);

    function provideLiquidity(IERC20Minimal asset, uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        providedLiquidity[address(asset)] += amount;
        emit LiquidityProvided(msg.sender, address(asset), amount);
    }

    function availableLiquidity(address asset) public view returns (uint256) {
        return providedLiquidity[asset] - reservedLiquidity[asset];
    }

    function reservePull(
        bytes32 op,
        address asset,
        address recipient,
        uint256 amount,
        uint64 sourceChainId,
        address sourceApp,
        uint64 expiry
    ) external {
        _reserve(op, Mode.PULL, asset, recipient, amount, sourceChainId, sourceApp, expiry, bytes32(0));
    }

    function reservePush(
        bytes32 op,
        address asset,
        address defaultRecipient,
        uint256 amount,
        uint64 sourceChainId,
        address sourceApp,
        uint64 expiry,
        bytes32 claimantRule
    ) external {
        if (claimantRule == bytes32(0)) revert InvalidReservation();
        _reserve(op, Mode.PUSH, asset, defaultRecipient, amount, sourceChainId, sourceApp, expiry, claimantRule);
    }

    function _reserve(
        bytes32 op,
        Mode mode,
        address asset,
        address recipient,
        uint256 amount,
        uint64 sourceChainId,
        address sourceApp,
        uint64 expiry,
        bytes32 rule
    ) internal {
        if (
            op == bytes32(0) || asset == address(0) || recipient == address(0) || amount == 0 || sourceChainId == 0
                || sourceApp == address(0)
        ) revert InvalidReservation();
        if (reservations[op].status != ReservationStatus.NONE) revert DuplicateReservation(op);
        if (availableLiquidity(asset) < amount) revert InsufficientLiquidity();
        reservedLiquidity[asset] += amount;
        reservations[op] = Reservation(
            mode,
            asset,
            msg.sender,
            recipient,
            amount,
            sourceChainId,
            sourceApp,
            expiry,
            rule,
            ReservationStatus.RESERVED
        );
        emit Reserved(op, mode, asset, amount);
    }

    function deliverPull(bytes32 op, uint64 sourceChainId, address sourceApp) external {
        Reservation storage r = reservations[op];
        if (r.status != ReservationStatus.RESERVED || r.mode != Mode.PULL) revert InvalidReservation();
        if (r.sourceChainId != sourceChainId || r.sourceApplication != sourceApp) revert UnauthorizedDomain();
        _deliver(op, r.recipient, bytes32(0));
    }

    function claimPush(bytes32 op, address claimant, bytes32 nullifier, uint64 deadline, bytes calldata signature)
        external
    {
        Reservation storage r = reservations[op];
        if (r.status != ReservationStatus.RESERVED || r.mode != Mode.PUSH) revert InvalidReservation();
        if (deadline < block.timestamp || r.expiry < block.timestamp) revert Expired();
        if (nullifier == bytes32(0) || nullifierUsed[nullifier]) revert ClaimFailed();
        bytes32 digest = keccak256(
            abi.encode("GLYPH_CLAIM", block.chainid, address(this), op, claimant, r.amount, nullifier, deadline)
        );
        (bytes32 rs, bytes32 ss, uint8 v) = _split(signature);
        address recovered = ecrecover(digest, v, rs, ss);
        if (recovered != claimant) revert ClaimFailed();
        nullifierUsed[nullifier] = true;
        _deliver(op, claimant, nullifier);
    }

    function release(bytes32 op) external {
        Reservation storage r = reservations[op];
        if (r.status != ReservationStatus.RESERVED) revert AlreadyTerminal(op);
        if (block.timestamp <= r.expiry) revert Expired();
        r.status = ReservationStatus.RELEASED;
        reservedLiquidity[r.asset] -= r.amount;
        emit Released(op);
    }

    function _deliver(bytes32 op, address to, bytes32 nullifier) internal {
        Reservation storage r = reservations[op];
        r.status = ReservationStatus.DELIVERED;
        reservedLiquidity[r.asset] -= r.amount;
        IERC20Minimal(r.asset).safeTransfer(to, r.amount);
        emit Delivered(op, to, r.amount, nullifier);
    }

    function _split(bytes calldata sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        if (sig.length != 65) revert ClaimFailed();
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v != 27 && v != 28) revert ClaimFailed();
    }
}
