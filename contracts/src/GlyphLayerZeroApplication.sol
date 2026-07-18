// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DestinationGlyphVault} from "./DestinationGlyphVault.sol";
import {SourceDeltaRouter} from "./SourceDeltaRouter.sol";
import {IGlyphMessengerAdapter} from "./interfaces/IGlyphMessengerAdapter.sol";

contract GlyphLayerZeroApplication {
    enum Side {
        SOURCE,
        DESTINATION
    }
    enum PayloadKind {
        NONE,
        ROUTE_INSTRUCTION,
        DESTINATION_RESERVED_ACK,
        DESTINATION_DELIVERED_ACK,
        DESTINATION_FAILED_ACK,
        RESERVATION_RELEASED_ACK,
        SOURCE_FINALIZED_RECEIPT,
        SOURCE_REFUNDED_RECEIPT
    }

    struct RouteInstructionV1 {
        uint16 payloadVersion;
        bytes32 termsHash;
        address recipient;
        address destinationAsset;
        address provider;
        uint256 destinationAmount;
        uint64 expiry;
        address gatekeeper;
    }

    struct DestinationAckV1 {
        uint16 payloadVersion;
        PayloadKind kind;
        bytes32 operationId;
        bytes32 termsHash;
        bytes32 routeMessageId;
        uint256 routeNonce;
        address claimantOrRecipient;
        address provider;
        address destinationAsset;
        uint256 deliveredAmount;
        SourceDeltaRouter.FailureCode failureCode;
    }

    struct SourceTerminalReceiptV1 {
        uint16 payloadVersion;
        PayloadKind kind;
        bytes32 operationId;
        bytes32 termsHash;
        address sourceAsset;
        uint256 maximumInput;
        uint256 realizedPrincipal;
        uint256 realizedFees;
        uint256 residualReturned;
        address recoveryAddress;
        uint256 routeNonce;
    }

    error Unauthorized();
    error InvalidConfig();
    error UnsupportedMessage();
    error InvalidPayload();
    error AckSendFailed();
    error NativeTransferFailed();
    error AlreadyFinalized();

    uint16 public constant MESSAGE_VERSION = 1;
    uint16 public constant PAYLOAD_VERSION = 1;

    Side public immutable side;
    uint64 public immutable localChainId;
    uint64 public immutable remoteChainId;
    SourceDeltaRouter public immutable router;
    DestinationGlyphVault public immutable vault;
    IGlyphMessengerAdapter public adapter;
    address public owner;
    address public remoteApplication;
    uint256 public nextRouteNonce = 1;
    uint256 public ackGasLimit = 200_000;
    bool public configFrozen;
    mapping(bytes32 => bytes32) public destinationRouteMessage;
    mapping(bytes32 => uint256) public destinationRouteNonce;
    mapping(bytes32 => bytes32) public destinationTermsHash;
    mapping(bytes32 => bytes32) public sourceTerminalReceipt;
    mapping(address => uint256) public sponsorBalance;

    event AdapterSet(address indexed adapter);
    event RemoteApplicationSet(address indexed remoteApplication);
    event AckGasLimitSet(uint256 gasLimit);
    event ConfigFrozen(bytes32 policyHash);
    event RouteSent(
        bytes32 indexed messageId, bytes32 indexed operationId, IGlyphMessengerAdapter.MessageType messageType
    );
    event AckSent(
        bytes32 indexed messageId, bytes32 indexed operationId, IGlyphMessengerAdapter.MessageType messageType
    );
    event InboundHandled(bytes32 indexed operationId, IGlyphMessengerAdapter.MessageType messageType);
    event InboundFailed(bytes32 indexed operationId, SourceDeltaRouter.FailureCode code);
    event SponsorDeposited(address indexed sponsor, uint256 amount);
    event SponsorWithdrawn(address indexed sponsor, uint256 amount);
    event TerminalReceiptRecorded(bytes32 indexed operationId, PayloadKind kind, bytes32 receiptHash);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    modifier onlyAdapter() {
        if (msg.sender != address(adapter)) revert Unauthorized();
        _;
    }
    modifier mutableConfig() {
        if (configFrozen) revert InvalidConfig();
        _;
    }

    constructor(
        Side side_,
        uint64 localChainId_,
        uint64 remoteChainId_,
        SourceDeltaRouter router_,
        DestinationGlyphVault vault_,
        address owner_
    ) {
        if (localChainId_ == 0 || remoteChainId_ == 0 || owner_ == address(0)) {
            revert InvalidConfig();
        }
        side = side_;
        localChainId = localChainId_;
        remoteChainId = remoteChainId_;
        router = router_;
        vault = vault_;
        owner = owner_;
    }

    receive() external payable {
        depositSponsor();
    }

    function depositSponsor() public payable {
        if (msg.value == 0) revert InvalidConfig();
        sponsorBalance[msg.sender] += msg.value;
        emit SponsorDeposited(msg.sender, msg.value);
    }

    function withdrawSponsor(uint256 amount, address payable to) external {
        if (to == address(0) || sponsorBalance[msg.sender] < amount) revert InvalidConfig();
        sponsorBalance[msg.sender] -= amount;
        _safeNative(to, amount);
        emit SponsorWithdrawn(msg.sender, amount);
    }

    function transferOwnership(address nextOwner) external onlyOwner {
        if (nextOwner == address(0)) revert InvalidConfig();
        owner = nextOwner;
    }

    function setAdapter(IGlyphMessengerAdapter adapter_) external onlyOwner mutableConfig {
        if (address(adapter_) == address(0)) revert InvalidConfig();
        adapter = adapter_;
        emit AdapterSet(address(adapter_));
    }

    function setRemoteApplication(address remoteApplication_) external onlyOwner mutableConfig {
        if (remoteApplication_ == address(0)) revert InvalidConfig();
        remoteApplication = remoteApplication_;
        emit RemoteApplicationSet(remoteApplication_);
    }

    function setAckGasLimit(uint256 gasLimit) external onlyOwner mutableConfig {
        if (gasLimit < 50_000 || gasLimit > 5_000_000) revert InvalidConfig();
        ackGasLimit = gasLimit;
        emit AckGasLimitSet(gasLimit);
    }

    function freezeConfig(bytes32 expectedPolicyHash) external onlyOwner {
        if (configFrozen || address(adapter) == address(0) || remoteApplication == address(0)) revert InvalidConfig();
        if (expectedPolicyHash == bytes32(0)) revert InvalidConfig();
        configFrozen = true;
        emit ConfigFrozen(expectedPolicyHash);
    }

    function quoteRouteFromEscrow(bytes32 operationId, uint256 gasLimit) external view returns (uint256) {
        (IGlyphMessengerAdapter.MessageType mt, bytes32 termsHash, bytes memory payload) =
            _routePayloadFromEscrow(operationId);
        IGlyphMessengerAdapter.Envelope memory envelope = _envelope(mt, operationId, termsHash, nextRouteNonce, payload);
        return adapter.quote(remoteChainId, remoteApplication, envelope, payload, gasLimit);
    }

    function sendRouteFromEscrow(bytes32 operationId, address payable refundAddress, uint256 gasLimit)
        external
        payable
        onlyOwner
        returns (bytes32 messageId)
    {
        (IGlyphMessengerAdapter.MessageType mt, bytes32 termsHash, bytes memory payload) =
            _routePayloadFromEscrow(operationId);
        uint256 routeNonce = nextRouteNonce++;
        IGlyphMessengerAdapter.Envelope memory envelope = _envelope(mt, operationId, termsHash, routeNonce, payload);
        messageId = adapter.sendMessage{value: msg.value}(
            remoteChainId, remoteApplication, envelope, payload, refundAddress, gasLimit
        );
        router.recordRouteFromAdapter(operationId, messageId, routeNonce, termsHash, address(adapter));
        emit RouteSent(messageId, operationId, mt);
    }

    function handleGlyphMessage(IGlyphMessengerAdapter.Envelope calldata envelope, bytes calldata payload)
        external
        onlyAdapter
    {
        if (keccak256(payload) != envelope.payloadHash) revert InvalidPayload();
        if (side == Side.DESTINATION) _handleDestination(envelope, payload);
        else _handleSource(envelope, payload);
        emit InboundHandled(envelope.operationId, envelope.messageType);
    }

    function claimPushAndAck(
        bytes32 operationId,
        address claimant,
        bytes32 nullifier,
        uint64 deadline,
        bytes calldata claimantSignature,
        bytes calldata gatekeeperSignature
    ) external payable returns (bytes32 ackId) {
        if (side != Side.DESTINATION) revert UnsupportedMessage();
        vault.claimPush(operationId, claimant, nullifier, deadline, claimantSignature, gatekeeperSignature);
        DestinationAckV1 memory ack = _destinationAck(
            operationId, PayloadKind.DESTINATION_DELIVERED_ACK, claimant, SourceDeltaRouter.FailureCode.NONE
        );
        ackId = _sendAckExact(
            operationId,
            ack.termsHash,
            IGlyphMessengerAdapter.MessageType.DESTINATION_DELIVERED_ACK,
            abi.encode(ack),
            payable(msg.sender),
            msg.value
        );
    }

    function releaseAndAck(bytes32 operationId) external payable returns (bytes32 ackId) {
        if (side != Side.DESTINATION) revert UnsupportedMessage();
        vault.release(operationId);
        DestinationAckV1 memory ack = _destinationAck(
            operationId,
            PayloadKind.RESERVATION_RELEASED_ACK,
            address(0),
            SourceDeltaRouter.FailureCode.CLAIM_NOT_COMPLETED
        );
        ackId = _sendAckExact(
            operationId,
            ack.termsHash,
            IGlyphMessengerAdapter.MessageType.RESERVATION_RELEASED_ACK,
            abi.encode(ack),
            payable(msg.sender),
            msg.value
        );
    }

    function finalizeAndSendReceipt(bytes32 operationId, address payable refundAddress, uint256 gasLimit)
        external
        payable
        returns (bytes32 messageId)
    {
        if (side != Side.SOURCE) revert UnsupportedMessage();
        router.finalize(operationId);
        SourceTerminalReceiptV1 memory receipt = _sourceReceipt(operationId, PayloadKind.SOURCE_FINALIZED_RECEIPT);
        bytes memory payload = abi.encode(receipt);
        uint256 nonce = nextRouteNonce++;
        IGlyphMessengerAdapter.Envelope memory e = _envelope(
            IGlyphMessengerAdapter.MessageType.SOURCE_FINALIZED_RECEIPT, operationId, receipt.termsHash, nonce, payload
        );
        messageId = adapter.sendMessage{value: msg.value}(
            remoteChainId, remoteApplication, e, payload, refundAddress, gasLimit
        );
    }

    function refundAndSendReceipt(bytes32 operationId, address payable refundAddress, uint256 gasLimit)
        external
        payable
        returns (bytes32 messageId)
    {
        if (side != Side.SOURCE) revert UnsupportedMessage();
        router.refund(operationId);
        SourceTerminalReceiptV1 memory receipt = _sourceReceipt(operationId, PayloadKind.SOURCE_REFUNDED_RECEIPT);
        bytes memory payload = abi.encode(receipt);
        uint256 nonce = nextRouteNonce++;
        IGlyphMessengerAdapter.Envelope memory e = _envelope(
            IGlyphMessengerAdapter.MessageType.SOURCE_REFUNDED_RECEIPT, operationId, receipt.termsHash, nonce, payload
        );
        messageId = adapter.sendMessage{value: msg.value}(
            remoteChainId, remoteApplication, e, payload, refundAddress, gasLimit
        );
    }

    function _handleDestination(IGlyphMessengerAdapter.Envelope calldata envelope, bytes calldata payload) internal {
        if (
            envelope.messageType == IGlyphMessengerAdapter.MessageType.SOURCE_FINALIZED_RECEIPT
                || envelope.messageType == IGlyphMessengerAdapter.MessageType.SOURCE_REFUNDED_RECEIPT
        ) {
            SourceTerminalReceiptV1 memory receipt = abi.decode(payload, (SourceTerminalReceiptV1));
            if (
                receipt.payloadVersion != PAYLOAD_VERSION || receipt.operationId != envelope.operationId
                    || receipt.termsHash != envelope.termsHash
            ) revert InvalidPayload();
            if (sourceTerminalReceipt[receipt.operationId] != bytes32(0)) revert AlreadyFinalized();
            bytes32 rh = keccak256(payload);
            sourceTerminalReceipt[receipt.operationId] = rh;
            emit TerminalReceiptRecorded(receipt.operationId, receipt.kind, rh);
            return;
        }
        if (
            envelope.messageType != IGlyphMessengerAdapter.MessageType.ROUTE_PULL
                && envelope.messageType != IGlyphMessengerAdapter.MessageType.RESERVE_PUSH
        ) revert UnsupportedMessage();
        RouteInstructionV1 memory instr = abi.decode(payload, (RouteInstructionV1));
        if (
            instr.payloadVersion != PAYLOAD_VERSION || instr.termsHash != envelope.termsHash
                || instr.destinationAsset == address(0) || instr.provider == address(0)
        ) revert InvalidPayload();
        try this.executeDestination(
            envelope.messageType, envelope.operationId, instr, envelope.sourceChainId, envelope.sourceApplication
        ) {
            destinationRouteMessage[envelope.operationId] = envelope.messageId;
            destinationRouteNonce[envelope.operationId] = envelope.routeNonce;
            destinationTermsHash[envelope.operationId] = envelope.termsHash;
            IGlyphMessengerAdapter.MessageType mt = envelope.messageType
                == IGlyphMessengerAdapter.MessageType.ROUTE_PULL
                ? IGlyphMessengerAdapter.MessageType.DESTINATION_DELIVERED_ACK
                : IGlyphMessengerAdapter.MessageType.DESTINATION_RESERVED_ACK;
            PayloadKind kind = envelope.messageType == IGlyphMessengerAdapter.MessageType.ROUTE_PULL
                ? PayloadKind.DESTINATION_DELIVERED_ACK
                : PayloadKind.DESTINATION_RESERVED_ACK;
            address actor =
                envelope.messageType == IGlyphMessengerAdapter.MessageType.ROUTE_PULL ? instr.recipient : address(0);
            DestinationAckV1 memory ack = DestinationAckV1(
                PAYLOAD_VERSION,
                kind,
                envelope.operationId,
                envelope.termsHash,
                envelope.messageId,
                envelope.routeNonce,
                actor,
                instr.provider,
                instr.destinationAsset,
                instr.destinationAmount,
                SourceDeltaRouter.FailureCode.NONE
            );
            _sendAckFunded(envelope.operationId, envelope.termsHash, mt, abi.encode(ack));
        } catch {
            DestinationAckV1 memory failAck = DestinationAckV1(
                PAYLOAD_VERSION,
                PayloadKind.DESTINATION_FAILED_ACK,
                envelope.operationId,
                envelope.termsHash,
                envelope.messageId,
                envelope.routeNonce,
                address(0),
                instr.provider,
                instr.destinationAsset,
                instr.destinationAmount,
                SourceDeltaRouter.FailureCode.LIQUIDITY_UNAVAILABLE
            );
            emit InboundFailed(envelope.operationId, failAck.failureCode);
            _sendAckFunded(
                envelope.operationId,
                envelope.termsHash,
                IGlyphMessengerAdapter.MessageType.DESTINATION_FAILED_ACK,
                abi.encode(failAck)
            );
        }
    }

    function executeDestination(
        IGlyphMessengerAdapter.MessageType messageType,
        bytes32 operationId,
        RouteInstructionV1 calldata instr,
        uint64 sourceChainId,
        address sourceApplication
    ) external {
        if (msg.sender != address(this)) revert Unauthorized();
        if (sourceApplication != remoteApplication || instr.destinationAmount == 0 || instr.expiry < block.timestamp) {
            revert InvalidPayload();
        }
        if (messageType == IGlyphMessengerAdapter.MessageType.ROUTE_PULL) {
            if (instr.gatekeeper != address(0)) revert InvalidPayload();
            vault.reservePull(
                operationId,
                instr.provider,
                instr.destinationAsset,
                instr.recipient,
                instr.destinationAmount,
                sourceChainId,
                sourceApplication,
                instr.expiry
            );
            vault.deliverPull(operationId, sourceChainId, sourceApplication);
        } else if (messageType == IGlyphMessengerAdapter.MessageType.RESERVE_PUSH) {
            if (instr.gatekeeper == address(0)) revert InvalidPayload();
            vault.reservePush(
                operationId,
                instr.provider,
                instr.destinationAsset,
                instr.recipient,
                instr.destinationAmount,
                sourceChainId,
                sourceApplication,
                instr.expiry,
                instr.gatekeeper
            );
        } else {
            revert UnsupportedMessage();
        }
    }

    function _handleSource(IGlyphMessengerAdapter.Envelope calldata envelope, bytes calldata payload) internal {
        if (envelope.messageType == IGlyphMessengerAdapter.MessageType.DESTINATION_RESERVED_ACK) {
            DestinationAckV1 memory ack = abi.decode(payload, (DestinationAckV1));
            _validateAck(envelope, ack, PayloadKind.DESTINATION_RESERVED_ACK);
            router.recordDestinationReservedFromAdapter(
                ack.operationId,
                envelope.messageId,
                ack.routeMessageId,
                ack.routeNonce,
                ack.termsHash,
                ack.provider,
                address(adapter)
            );
        } else if (envelope.messageType == IGlyphMessengerAdapter.MessageType.DESTINATION_DELIVERED_ACK) {
            DestinationAckV1 memory ack = abi.decode(payload, (DestinationAckV1));
            _validateAck(envelope, ack, PayloadKind.DESTINATION_DELIVERED_ACK);
            router.recordDestinationDeliveryFromAdapter(
                ack.operationId,
                envelope.messageId,
                ack.routeMessageId,
                ack.routeNonce,
                ack.termsHash,
                ack.claimantOrRecipient,
                ack.provider,
                ack.destinationAsset,
                ack.deliveredAmount,
                address(adapter)
            );
        } else if (
            envelope.messageType == IGlyphMessengerAdapter.MessageType.DESTINATION_FAILED_ACK
                || envelope.messageType == IGlyphMessengerAdapter.MessageType.RESERVATION_RELEASED_ACK
        ) {
            DestinationAckV1 memory ack = abi.decode(payload, (DestinationAckV1));
            _validateAck(
                envelope,
                ack,
                envelope.messageType == IGlyphMessengerAdapter.MessageType.DESTINATION_FAILED_ACK
                    ? PayloadKind.DESTINATION_FAILED_ACK
                    : PayloadKind.RESERVATION_RELEASED_ACK
            );
            router.recordFailureFromAdapter(
                ack.operationId, ack.routeMessageId, ack.routeNonce, ack.termsHash, ack.failureCode, address(adapter)
            );
        } else {
            revert UnsupportedMessage();
        }
    }

    function _validateAck(
        IGlyphMessengerAdapter.Envelope calldata envelope,
        DestinationAckV1 memory ack,
        PayloadKind kind
    ) internal pure {
        if (
            ack.payloadVersion != PAYLOAD_VERSION || ack.kind != kind || ack.operationId != envelope.operationId
                || ack.termsHash != envelope.termsHash || ack.routeMessageId == bytes32(0) || ack.routeNonce == 0
        ) revert InvalidPayload();
    }

    function _destinationAck(
        bytes32 operationId,
        PayloadKind kind,
        address claimant,
        SourceDeltaRouter.FailureCode code
    ) internal view returns (DestinationAckV1 memory ack) {
        (address provider, address asset, uint256 amount) = vault.reservationCore(operationId);
        ack = DestinationAckV1(
            PAYLOAD_VERSION,
            kind,
            operationId,
            destinationTermsHash[operationId],
            destinationRouteMessage[operationId],
            destinationRouteNonce[operationId],
            claimant,
            provider,
            asset,
            amount,
            code
        );
    }

    function _sourceReceipt(bytes32 operationId, PayloadKind kind)
        internal
        view
        returns (SourceTerminalReceiptV1 memory receipt)
    {
        (
            bytes32 termsHash,
            address sourceAsset,
            uint256 maximumInput,
            uint256 amount,
            uint256 fees,
            address recovery,
            SourceDeltaRouter.Status status
        ) = router.sourceReceiptFacts(operationId);
        uint256 principal = kind == PayloadKind.SOURCE_FINALIZED_RECEIPT ? amount : 0;
        uint256 realizedFees = kind == PayloadKind.SOURCE_FINALIZED_RECEIPT ? fees : 0;
        uint256 residual =
            kind == PayloadKind.SOURCE_FINALIZED_RECEIPT ? maximumInput - principal - realizedFees : maximumInput;
        if (kind == PayloadKind.SOURCE_FINALIZED_RECEIPT && status != SourceDeltaRouter.Status.RECONCILED) {
            revert InvalidPayload();
        }
        if (kind == PayloadKind.SOURCE_REFUNDED_RECEIPT && status != SourceDeltaRouter.Status.REFUNDED) {
            revert InvalidPayload();
        }
        receipt = SourceTerminalReceiptV1(
            PAYLOAD_VERSION,
            kind,
            operationId,
            termsHash,
            sourceAsset,
            maximumInput,
            principal,
            realizedFees,
            residual,
            recovery,
            0
        );
    }

    function _routePayloadFromEscrow(bytes32 operationId)
        internal
        view
        returns (IGlyphMessengerAdapter.MessageType mt, bytes32 termsHash, bytes memory payload)
    {
        (bytes32 currentTermsHash, bytes32 mode,,,,,,, SourceDeltaRouter.Status status) =
            router.routeInstructionFacts(operationId);
        termsHash = currentTermsHash;
        if (status != SourceDeltaRouter.Status.ESCROWED) revert InvalidPayload();
        RouteInstructionV1 memory instr = _instructionFromRouter(operationId, termsHash, mode);
        mt = mode == router.PULL()
            ? IGlyphMessengerAdapter.MessageType.ROUTE_PULL
            : IGlyphMessengerAdapter.MessageType.RESERVE_PUSH;
        payload = abi.encode(instr);
    }

    function _instructionFromRouter(bytes32 operationId, bytes32 termsHash, bytes32 mode)
        internal
        view
        returns (RouteInstructionV1 memory instr)
    {
        (
            bytes32 m,,
            address recipient,
            address destAsset,
            address provider,
            address gatekeeper,
            uint256 amount,
            uint64 expiry,
        ) = router.routeInstructionFacts(operationId);
        if (m != termsHash || mode == bytes32(0)) revert InvalidPayload();
        instr =
            RouteInstructionV1(PAYLOAD_VERSION, termsHash, recipient, destAsset, provider, amount, expiry, gatekeeper);
    }

    function _sendAckFunded(
        bytes32 operationId,
        bytes32 termsHash,
        IGlyphMessengerAdapter.MessageType messageType,
        bytes memory payload
    ) internal returns (bytes32 messageId) {
        uint256 fee = adapter.quote(
            remoteChainId,
            remoteApplication,
            _envelope(messageType, operationId, termsHash, nextRouteNonce, payload),
            payload,
            ackGasLimit
        );
        if (address(this).balance < fee) revert AckSendFailed();
        sponsorBalance[owner] = sponsorBalance[owner] >= fee ? sponsorBalance[owner] - fee : 0;
        return _sendAckExact(operationId, termsHash, messageType, payload, payable(owner), fee);
    }

    function _sendAckExact(
        bytes32 operationId,
        bytes32 termsHash,
        IGlyphMessengerAdapter.MessageType messageType,
        bytes memory payload,
        address payable refundAddress,
        uint256 supplied
    ) internal returns (bytes32 messageId) {
        uint256 nonce = nextRouteNonce++;
        IGlyphMessengerAdapter.Envelope memory ack = _envelope(messageType, operationId, termsHash, nonce, payload);
        uint256 fee = adapter.quote(remoteChainId, remoteApplication, ack, payload, ackGasLimit);
        if (supplied < fee) revert AckSendFailed();
        messageId =
            adapter.sendMessage{value: fee}(remoteChainId, remoteApplication, ack, payload, refundAddress, ackGasLimit);
        _safeNative(refundAddress, supplied - fee);
        emit AckSent(messageId, operationId, messageType);
    }

    function _envelope(
        IGlyphMessengerAdapter.MessageType messageType,
        bytes32 operationId,
        bytes32 termsHash,
        uint256 routeNonce,
        bytes memory payload
    ) internal view returns (IGlyphMessengerAdapter.Envelope memory) {
        if (!configFrozen || remoteApplication == address(0) || address(adapter) == address(0)) {
            revert InvalidConfig();
        }
        return IGlyphMessengerAdapter.Envelope(
            MESSAGE_VERSION,
            messageType,
            bytes32(0),
            operationId,
            termsHash,
            localChainId,
            address(this),
            remoteChainId,
            remoteApplication,
            routeNonce,
            keccak256(payload)
        );
    }

    function _safeNative(address payable to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
    }
}
