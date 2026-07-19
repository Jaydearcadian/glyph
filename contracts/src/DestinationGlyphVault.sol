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
        address gatekeeper;
        ReservationStatus status;
        address claimant;
        bytes32 nullifier;
    }

    error InvalidReservation();
    error InsufficientLiquidity();
    error DuplicateReservation(bytes32 operationId);
    error AlreadyTerminal(bytes32 operationId);
    error UnauthorizedDomain();
    error UnauthorizedActor();
    error Expired();
    error ClaimFailed();

    mapping(address => uint256) public providedLiquidity;
    mapping(address => uint256) public reservedLiquidity;
    mapping(address => mapping(address => uint256)) public providerAvailableLiquidity;
    mapping(address => mapping(address => uint256)) public providerReservedLiquidity;
    mapping(bytes32 => Reservation) public reservations;
    mapping(bytes32 => bool) public nullifierUsed;
    mapping(address => bool) public authorizedApplication;
    address public owner;

    event LiquidityProvided(address indexed provider, address indexed asset, uint256 amount);
    event ApplicationAuthorized(address indexed app, bool authorized);
    event Reserved(bytes32 indexed operationId, Mode mode, address indexed provider, address asset, uint256 amount);
    event Delivered(bytes32 indexed operationId, address indexed recipient, uint256 amount, bytes32 nullifier);
    event Released(bytes32 indexed operationId, address indexed provider);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedActor();
        _;
    }
    modifier onlyAuthorizedApplication() {
        if (!authorizedApplication[msg.sender]) revert UnauthorizedActor();
        _;
    }

    function setAuthorizedApplication(address app, bool authorized) external onlyOwner {
        if (app == address(0)) revert InvalidReservation();
        authorizedApplication[app] = authorized;
        emit ApplicationAuthorized(app, authorized);
    }

    function provideLiquidity(IERC20Minimal asset, uint256 amount) external {
        if (address(asset) == address(0) || amount == 0) revert InvalidReservation();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        providedLiquidity[address(asset)] += amount;
        providerAvailableLiquidity[msg.sender][address(asset)] += amount;
        emit LiquidityProvided(msg.sender, address(asset), amount);
    }

    function availableLiquidity(address asset) public view returns (uint256) {
        return providedLiquidity[asset] - reservedLiquidity[asset];
    }

    function providerAvailable(address provider, address asset) public view returns (uint256) {
        return providerAvailableLiquidity[provider][asset] - providerReservedLiquidity[provider][asset];
    }

    function reservePull(
        bytes32 op,
        address provider,
        address asset,
        address recipient,
        uint256 amount,
        uint64 sourceChainId,
        address sourceApp,
        uint64 expiry
    ) external onlyAuthorizedApplication {
        _reserve(op, Mode.PULL, provider, asset, recipient, amount, sourceChainId, sourceApp, expiry, address(0));
    }

    function reservePush(
        bytes32 op,
        address provider,
        address asset,
        address defaultRecipient,
        uint256 amount,
        uint64 sourceChainId,
        address sourceApp,
        uint64 expiry,
        address gatekeeper
    ) external onlyAuthorizedApplication {
        if (gatekeeper == address(0)) revert InvalidReservation();
        _reserve(op, Mode.PUSH, provider, asset, defaultRecipient, amount, sourceChainId, sourceApp, expiry, gatekeeper);
    }

    function _reserve(
        bytes32 op,
        Mode mode,
        address provider,
        address asset,
        address recipient,
        uint256 amount,
        uint64 sourceChainId,
        address sourceApp,
        uint64 expiry,
        address gatekeeper
    ) internal {
        if (
            op == bytes32(0) || provider == address(0) || asset == address(0) || recipient == address(0) || amount == 0
                || sourceChainId == 0 || sourceApp == address(0)
        ) revert InvalidReservation();
        if (reservations[op].status != ReservationStatus.NONE) revert DuplicateReservation(op);
        if (providerAvailable(provider, asset) < amount) revert InsufficientLiquidity();
        reservedLiquidity[asset] += amount;
        providerReservedLiquidity[provider][asset] += amount;
        reservations[op] = Reservation(
            mode,
            asset,
            provider,
            recipient,
            amount,
            sourceChainId,
            sourceApp,
            expiry,
            gatekeeper,
            ReservationStatus.RESERVED,
            address(0),
            bytes32(0)
        );
        emit Reserved(op, mode, provider, asset, amount);
    }

    function deliverPull(bytes32 op, uint64 sourceChainId, address sourceApp) external onlyAuthorizedApplication {
        Reservation storage r = reservations[op];
        if (r.status != ReservationStatus.RESERVED || r.mode != Mode.PULL) revert InvalidReservation();
        if (r.sourceChainId != sourceChainId || r.sourceApplication != sourceApp) revert UnauthorizedDomain();
        _deliver(op, r.recipient, bytes32(0));
    }

    function claimPush(
        bytes32 op,
        address claimant,
        bytes32 nullifier,
        uint64 deadline,
        bytes calldata claimantSignature,
        bytes calldata gatekeeperSignature
    ) external {
        Reservation storage r = reservations[op];
        if (r.status != ReservationStatus.RESERVED || r.mode != Mode.PUSH) revert InvalidReservation();
        if (deadline < block.timestamp || r.expiry < block.timestamp) revert Expired();
        if (claimant == address(0) || nullifier == bytes32(0) || nullifierUsed[nullifier]) revert ClaimFailed();
        bytes32 intentDigest = keccak256(
            abi.encode(
                "GLYPH_CLAIM_INTENT_V1", block.chainid, address(this), op, claimant, r.amount, nullifier, deadline
            )
        );
        if (_recover(intentDigest, claimantSignature) != claimant) revert ClaimFailed();
        bytes32 authDigest = keccak256(
            abi.encode(
                "GLYPH_CLAIM_AUTH_V1",
                block.chainid,
                address(this),
                op,
                claimant,
                r.asset,
                r.amount,
                nullifier,
                deadline
            )
        );
        if (_recover(authDigest, gatekeeperSignature) != r.gatekeeper) revert ClaimFailed();
        nullifierUsed[nullifier] = true;
        r.claimant = claimant;
        r.nullifier = nullifier;
        _deliver(op, claimant, nullifier);
    }

    function release(bytes32 op) external {
        Reservation storage r = reservations[op];
        if (r.status != ReservationStatus.RESERVED) revert AlreadyTerminal(op);
        if (r.expiry >= block.timestamp) revert Expired();
        r.status = ReservationStatus.RELEASED;
        reservedLiquidity[r.asset] -= r.amount;
        providerReservedLiquidity[r.provider][r.asset] -= r.amount;
        emit Released(op, r.provider);
    }

    function reservationEvidence(bytes32 op)
        external
        view
        returns (
            Mode mode,
            ReservationStatus status,
            address provider,
            address asset,
            address recipient,
            uint256 amount,
            address claimant,
            bytes32 nullifier,
            address gatekeeper
        )
    {
        Reservation storage r = reservations[op];
        return (r.mode, r.status, r.provider, r.asset, r.recipient, r.amount, r.claimant, r.nullifier, r.gatekeeper);
    }

    function reservationCore(bytes32 op) external view returns (address provider, address asset, uint256 amount) {
        Reservation storage r = reservations[op];
        return (r.provider, r.asset, r.amount);
    }

    function _deliver(bytes32 op, address to, bytes32 nullifier) internal {
        Reservation storage r = reservations[op];
        r.status = ReservationStatus.DELIVERED;
        reservedLiquidity[r.asset] -= r.amount;
        providerReservedLiquidity[r.provider][r.asset] -= r.amount;
        providerAvailableLiquidity[r.provider][r.asset] -= r.amount;
        providedLiquidity[r.asset] -= r.amount;
        IERC20Minimal(r.asset).safeTransfer(to, r.amount);
        emit Delivered(op, to, r.amount, nullifier);
    }

    function _recover(bytes32 digest, bytes calldata sig) internal pure returns (address signer) {
        (bytes32 r, bytes32 s, uint8 v) = _split(sig);
        signer = ecrecover(digest, v, r, s);
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
