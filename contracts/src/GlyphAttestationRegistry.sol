// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGlyphReceiptLedger} from "./interfaces/IGlyphReceiptLedger.sol";
import {GlyphSignatureChecker} from "./libraries/GlyphSignatureChecker.sol";

contract GlyphAttestationRegistry {
    using GlyphSignatureChecker for address;

    enum VerificationLevel {
        SELF_ASSERTED,
        ISSUER_VERIFIED
    }
    enum ClaimStatus {
        ACTIVE,
        SUPERSEDED,
        REVOKED
    }

    struct IdentityClaimInput {
        address subject;
        bytes32 namespace;
        bytes32 identifierCommitment;
        bytes32 attestationReference;
        uint64 expiresAt;
        uint256 nonce;
        uint64 deadline;
    }

    struct IdentityClaim {
        bytes32 claimId;
        address subject;
        bytes32 namespace;
        bytes32 identifierCommitment;
        address issuer;
        bytes32 attestationReference;
        uint64 registeredAt;
        uint64 expiresAt;
        VerificationLevel level;
        ClaimStatus status;
    }

    struct IdentityBindingInput {
        bytes32 operationId;
        bytes32 claimId;
        address subject;
        bytes32 role;
        uint256 nonce;
        uint64 deadline;
    }

    struct OperationIdentityBinding {
        bytes32 operationId;
        bytes32 claimId;
        address subject;
        bytes32 role;
        uint64 boundAt;
    }

    struct IdentityAcknowledgementInput {
        bytes32 operationId;
        bytes32 claimId;
        address subject;
        bytes32 role;
        uint256 nonce;
        uint64 deadline;
    }

    struct IdentityAcknowledgement {
        bytes32 acknowledgementId;
        bytes32 operationId;
        bytes32 claimId;
        address acknowledger;
        address subject;
        bytes32 role;
        uint64 acknowledgedAt;
    }

    struct PurposeAttestationInput {
        bytes32 operationId;
        address attestor;
        bytes32 role;
        bytes32 purposeCode;
        bytes32 contextHash;
        bytes32 supersedesAttestationId;
        uint256 nonce;
        uint64 deadline;
    }

    struct PurposeAttestation {
        bytes32 attestationId;
        bytes32 operationId;
        address attestor;
        bytes32 role;
        bytes32 purposeCode;
        bytes32 contextHash;
        bytes32 supersedesAttestationId;
        uint64 attestedAt;
        bool superseded;
    }

    error UnauthorizedAdmin(address caller);
    error UnauthorizedSubject(address caller, address subject);
    error UnauthorizedIssuer(address issuer);
    error UnauthorizedAttestor(address attestor);
    error InvalidSignature();
    error DeadlineExpired(uint64 deadline);
    error InvalidNonce(address subject, uint256 expected, uint256 actual);
    error ClaimNotFound(bytes32 claimId);
    error ClaimExpired(bytes32 claimId);
    error ClaimRevoked(bytes32 claimId);
    error ClaimSuperseded(bytes32 claimId);
    error RoleSubjectMismatch(bytes32 role, address expected, address actual);
    error DuplicateBinding(bytes32 operationId, bytes32 role);
    error BindingNotFound(bytes32 operationId, bytes32 role);
    error UnauthorizedAcknowledgement(address caller);
    error DuplicateAcknowledgement(bytes32 acknowledgementId);
    error InvalidSupersession(bytes32 oldId);
    error DuplicateClaim(bytes32 claimId);
    error InvalidClaimInput(bytes32 field);

    bytes32 public constant ROLE_PAYER = keccak256("glyph.identity.role.payer.v1");
    bytes32 public constant ROLE_RECIPIENT = keccak256("glyph.identity.role.recipient.v1");
    bytes32 public constant ROLE_INITIATOR = keccak256("glyph.identity.role.initiator.v1");
    bytes32 public constant CLAIM_DOMAIN = keccak256("glyph.identity.claim.v1");
    bytes32 public constant BINDING_DOMAIN = keccak256("glyph.identity.binding.v1");
    bytes32 public constant ACK_DOMAIN = keccak256("glyph.identity.acknowledgement.v1");
    bytes32 public constant PURPOSE_DOMAIN = keccak256("glyph.purpose.attestation.v1");
    bytes32 public constant REVOCATION_DOMAIN = keccak256("glyph.identity.revocation.v1");
    bytes32 public constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant CLAIM_TYPEHASH = keccak256(
        "IdentityClaimAuthorization(address subject,bytes32 namespace,bytes32 identifierCommitment,bytes32 attestationReference,uint64 expiresAt,uint256 nonce,uint64 deadline)"
    );
    bytes32 public constant BINDING_TYPEHASH = keccak256(
        "IdentityBindingAuthorization(bytes32 operationId,bytes32 claimId,address subject,bytes32 role,uint256 nonce,uint64 deadline)"
    );
    bytes32 public constant ACK_TYPEHASH = keccak256(
        "IdentityAcknowledgementAuthorization(bytes32 operationId,bytes32 claimId,address subject,bytes32 role,uint256 nonce,uint64 deadline)"
    );
    bytes32 public constant PURPOSE_TYPEHASH = keccak256(
        "PurposeAttestationAuthorization(bytes32 operationId,address attestor,bytes32 role,bytes32 purposeCode,bytes32 contextHash,bytes32 supersedesAttestationId,uint256 nonce,uint64 deadline)"
    );
    bytes32 public constant REVOCATION_TYPEHASH =
        keccak256("IdentityRevocationAuthorization(bytes32 claimId,uint256 nonce,uint64 deadline)");
    bytes32 public constant SUPERSESSION_TYPEHASH = keccak256(
        "IdentitySupersessionAuthorization(bytes32 oldClaimId,address subject,bytes32 namespace,bytes32 identifierCommitment,bytes32 attestationReference,uint64 expiresAt,uint256 claimNonce,uint256 nonce,uint64 deadline)"
    );

    IGlyphReceiptLedger public immutable ledger;
    address public immutable admin;
    bytes32 public immutable DOMAIN_SEPARATOR;

    mapping(address => bool) public issuerAllowed;
    mapping(address => uint256) public identityClaimNonce;
    mapping(address => uint256) public identityBindingNonce;
    mapping(address => uint256) public identityAcknowledgementNonce;
    mapping(address => uint256) public revocationNonce;
    mapping(address => uint256) public supersessionNonce;
    mapping(address => uint256) public purposeAttestationNonce;
    mapping(bytes32 => IdentityClaim) internal claims;
    mapping(bytes32 => bool) internal claimExists;
    mapping(bytes32 => mapping(bytes32 => OperationIdentityBinding)) internal bindings;
    mapping(bytes32 => bool) internal bindingExists;
    mapping(bytes32 => bool) internal acknowledgementExists;
    mapping(bytes32 => PurposeAttestation) internal purposeAttestations;
    mapping(bytes32 => bool) internal purposeExists;
    mapping(bytes32 => bytes32) public latestPayerPurpose;
    mapping(bytes32 => bytes32) public latestRecipientPurpose;
    mapping(bytes32 => mapping(address => bytes32)) public latestPurposeByAttestor;
    mapping(bytes32 => mapping(bytes32 => bytes32)) public latestPurposeByRole;

    event IdentityClaimRegistered(
        bytes32 indexed claimId,
        address indexed subject,
        bytes32 indexed namespace,
        bytes32 identifierCommitment,
        address issuer,
        bytes32 attestationReference,
        uint64 registeredAt,
        uint64 expiresAt,
        VerificationLevel level,
        ClaimStatus status
    );
    event IdentityBoundToOperation(
        bytes32 indexed operationId, bytes32 indexed claimId, address indexed subject, bytes32 role, uint64 boundAt
    );
    event IdentityAcknowledged(
        bytes32 indexed acknowledgementId,
        bytes32 indexed operationId,
        bytes32 indexed claimId,
        address acknowledger,
        bytes32 role,
        uint64 acknowledgedAt
    );
    event IdentityClaimSuperseded(bytes32 indexed oldClaimId, bytes32 indexed newClaimId, address indexed subject);
    event IdentityClaimRevoked(bytes32 indexed claimId, address indexed subject, uint64 revokedAt);
    event PurposeAttested(
        bytes32 indexed attestationId,
        bytes32 indexed operationId,
        address indexed attestor,
        bytes32 role,
        bytes32 purposeCode,
        bytes32 contextHash,
        bytes32 supersedesAttestationId,
        uint64 attestedAt
    );
    event PurposeSuperseded(
        bytes32 indexed oldAttestationId,
        bytes32 indexed newAttestationId,
        bytes32 indexed operationId,
        address attestor
    );

    constructor(IGlyphReceiptLedger ledger_, address admin_) {
        if (address(ledger_) == address(0)) revert UnauthorizedAdmin(address(0));
        if (admin_ == address(0)) revert UnauthorizedAdmin(address(0));
        ledger = ledger_;
        admin = admin_;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("GlyphAttestationRegistry"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert UnauthorizedAdmin(msg.sender);
        _;
    }

    function configureIssuer(address issuer, bool allowed) external onlyAdmin {
        issuerAllowed[issuer] = allowed;
    }

    function getIdentityClaim(bytes32 claimId) external view returns (IdentityClaim memory) {
        if (!claimExists[claimId]) revert ClaimNotFound(claimId);
        return claims[claimId];
    }

    function getOperationIdentityBinding(bytes32 operationId, bytes32 role)
        external
        view
        returns (OperationIdentityBinding memory)
    {
        if (!bindingExists[_bindingKey(operationId, role)]) revert BindingNotFound(operationId, role);
        return bindings[operationId][role];
    }

    function getPurposeAttestation(bytes32 attestationId) external view returns (PurposeAttestation memory) {
        if (!purposeExists[attestationId]) revert InvalidSupersession(attestationId);
        return purposeAttestations[attestationId];
    }

    function isClaimExpired(bytes32 claimId) public view returns (bool) {
        return claims[claimId].expiresAt != 0 && claims[claimId].expiresAt <= block.timestamp;
    }

    function hashIdentityClaimAuthorization(IdentityClaimInput calldata input) external view returns (bytes32) {
        return _hashClaim(input);
    }

    function hashIdentityBindingAuthorization(IdentityBindingInput calldata input) external view returns (bytes32) {
        return _hashBinding(input);
    }

    function hashIdentityAcknowledgementAuthorization(IdentityAcknowledgementInput calldata input)
        external
        view
        returns (bytes32)
    {
        return _hashAck(input);
    }

    function hashPurposeAttestationAuthorization(PurposeAttestationInput calldata input)
        external
        view
        returns (bytes32)
    {
        return _hashPurpose(input);
    }

    function hashIdentitySupersessionAuthorization(
        bytes32 oldClaimId,
        IdentityClaimInput calldata replacement,
        uint256 nonce,
        uint64 deadline
    ) external view returns (bytes32) {
        return _hashSupersession(oldClaimId, replacement, nonce, deadline);
    }

    function registerSelfIdentity(IdentityClaimInput calldata input) external returns (bytes32 claimId) {
        if (msg.sender != input.subject) revert UnauthorizedSubject(msg.sender, input.subject);
        _consume(identityClaimNonce, input.subject, input.nonce);
        claimId = _registerClaim(input, address(0), VerificationLevel.SELF_ASSERTED);
    }

    function registerSelfIdentityWithSignature(IdentityClaimInput calldata input, bytes calldata signature)
        external
        returns (bytes32 claimId)
    {
        _checkDeadline(input.deadline);
        input.subject.requireValidSignature(_hashClaim(input), signature);
        _consume(identityClaimNonce, input.subject, input.nonce);
        claimId = _registerClaim(input, address(0), VerificationLevel.SELF_ASSERTED);
    }

    function registerIssuerIdentity(IdentityClaimInput calldata input) external returns (bytes32 claimId) {
        if (!issuerAllowed[msg.sender]) revert UnauthorizedIssuer(msg.sender);
        _consume(identityClaimNonce, msg.sender, input.nonce);
        claimId = _registerClaim(input, msg.sender, VerificationLevel.ISSUER_VERIFIED);
    }

    function bindIdentity(IdentityBindingInput calldata input, bytes calldata signature) external {
        address actor = input.subject;
        _checkDeadline(input.deadline);
        _authorize(actor, _hashBinding(input), signature);
        _consume(identityBindingNonce, actor, input.nonce);
        _bind(input);
    }

    function acknowledgeIdentity(IdentityAcknowledgementInput calldata input, bytes calldata signature)
        external
        returns (bytes32 acknowledgementId)
    {
        address acknowledger = _expectedAcknowledger(input.operationId, input.role);
        _checkDeadline(input.deadline);
        _authorize(acknowledger, _hashAck(input), signature);
        _consume(identityAcknowledgementNonce, acknowledger, input.nonce);
        OperationIdentityBinding storage b = bindings[input.operationId][input.role];
        if (
            !bindingExists[_bindingKey(input.operationId, input.role)] || b.claimId != input.claimId
                || b.subject != input.subject
        ) revert BindingNotFound(input.operationId, input.role);
        acknowledgementId = keccak256(
            abi.encode(
                ACK_DOMAIN,
                block.chainid,
                address(this),
                input.operationId,
                input.claimId,
                acknowledger,
                input.subject,
                input.role
            )
        );
        if (acknowledgementExists[acknowledgementId]) revert DuplicateAcknowledgement(acknowledgementId);
        acknowledgementExists[acknowledgementId] = true;
        emit IdentityAcknowledged(
            acknowledgementId, input.operationId, input.claimId, acknowledger, input.role, uint64(block.timestamp)
        );
    }

    function revokeIdentity(bytes32 claimId, uint256 nonce, uint64 deadline, bytes calldata signature) external {
        IdentityClaim storage c = claims[claimId];
        if (!claimExists[claimId]) revert ClaimNotFound(claimId);
        address actor = c.issuer == address(0) ? c.subject : c.issuer;
        _authorizeRevocation(actor, claimId, nonce, deadline, signature);
        if (c.status != ClaimStatus.ACTIVE) revert InvalidSupersession(claimId);
        c.status = ClaimStatus.REVOKED;
        emit IdentityClaimRevoked(claimId, c.subject, uint64(block.timestamp));
    }

    function supersedeIdentity(
        bytes32 oldClaimId,
        IdentityClaimInput calldata replacement,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external returns (bytes32 newClaimId) {
        IdentityClaim storage oldClaim = claims[oldClaimId];
        if (!claimExists[oldClaimId]) revert ClaimNotFound(oldClaimId);
        address actor = oldClaim.issuer == address(0) ? oldClaim.subject : oldClaim.issuer;
        _authorizeSupersession(actor, oldClaimId, replacement, nonce, deadline, signature);
        if (oldClaim.status != ClaimStatus.ACTIVE) revert InvalidSupersession(oldClaimId);
        if (replacement.subject != oldClaim.subject) revert UnauthorizedSubject(replacement.subject, oldClaim.subject);
        oldClaim.status = ClaimStatus.SUPERSEDED;
        _consume(identityClaimNonce, actor, replacement.nonce);
        newClaimId = _registerClaim(replacement, oldClaim.issuer, oldClaim.level);
        emit IdentityClaimSuperseded(oldClaimId, newClaimId, oldClaim.subject);
    }

    function attestPurpose(PurposeAttestationInput calldata input, bytes calldata signature)
        external
        returns (bytes32 attestationId)
    {
        _checkDeadline(input.deadline);
        _authorize(input.attestor, _hashPurpose(input), signature);
        _consume(purposeAttestationNonce, input.attestor, input.nonce);
        _requireOperationParty(input.operationId, input.attestor, input.role);
        bytes32 latest = latestPurposeByRole[input.operationId][input.role];
        if (latest != input.supersedesAttestationId) revert InvalidSupersession(input.supersedesAttestationId);
        if (input.supersedesAttestationId != bytes32(0)) {
            PurposeAttestation storage oldA = purposeAttestations[input.supersedesAttestationId];
            if (
                !purposeExists[input.supersedesAttestationId] || oldA.superseded || oldA.attestor != input.attestor
                    || oldA.operationId != input.operationId || oldA.role != input.role
            ) revert InvalidSupersession(input.supersedesAttestationId);
            oldA.superseded = true;
        }
        attestationId = keccak256(
            abi.encode(
                PURPOSE_DOMAIN,
                block.chainid,
                address(this),
                input.operationId,
                input.attestor,
                input.role,
                input.purposeCode,
                input.contextHash,
                input.supersedesAttestationId,
                input.nonce
            )
        );
        if (purposeExists[attestationId]) revert InvalidSupersession(attestationId);
        purposeExists[attestationId] = true;
        purposeAttestations[attestationId] = PurposeAttestation(
            attestationId,
            input.operationId,
            input.attestor,
            input.role,
            input.purposeCode,
            input.contextHash,
            input.supersedesAttestationId,
            uint64(block.timestamp),
            false
        );
        latestPurposeByAttestor[input.operationId][input.attestor] = attestationId;
        latestPurposeByRole[input.operationId][input.role] = attestationId;
        if (input.role == ROLE_PAYER) latestPayerPurpose[input.operationId] = attestationId;
        if (input.role == ROLE_RECIPIENT) latestRecipientPurpose[input.operationId] = attestationId;
        if (input.supersedesAttestationId != bytes32(0)) {
            emit PurposeSuperseded(input.supersedesAttestationId, attestationId, input.operationId, input.attestor);
        }
        emit PurposeAttested(
            attestationId,
            input.operationId,
            input.attestor,
            input.role,
            input.purposeCode,
            input.contextHash,
            input.supersedesAttestationId,
            uint64(block.timestamp)
        );
    }

    function purposeConsensus(bytes32 operationId)
        external
        view
        returns (bool agreed, bytes32 purposeCode, bytes32 contextHash)
    {
        bytes32 pId = latestPayerPurpose[operationId];
        bytes32 rId = latestRecipientPurpose[operationId];
        if (pId == bytes32(0) || rId == bytes32(0) || pId == rId) return (false, bytes32(0), bytes32(0));
        PurposeAttestation storage p = purposeAttestations[pId];
        PurposeAttestation storage r = purposeAttestations[rId];
        agreed = p.purposeCode == r.purposeCode && p.contextHash == r.contextHash;
        if (agreed) return (true, p.purposeCode, p.contextHash);
        return (false, bytes32(0), bytes32(0));
    }

    function _registerClaim(IdentityClaimInput calldata input, address issuer, VerificationLevel level)
        internal
        returns (bytes32 claimId)
    {
        claimId = keccak256(
            abi.encode(
                CLAIM_DOMAIN,
                block.chainid,
                address(this),
                input.subject,
                input.namespace,
                input.identifierCommitment,
                issuer,
                input.attestationReference,
                input.expiresAt,
                input.nonce
            )
        );
        _validateClaimInput(input);
        if (claimExists[claimId]) revert DuplicateClaim(claimId);
        claims[claimId] = IdentityClaim(
            claimId,
            input.subject,
            input.namespace,
            input.identifierCommitment,
            issuer,
            input.attestationReference,
            uint64(block.timestamp),
            input.expiresAt,
            level,
            ClaimStatus.ACTIVE
        );
        claimExists[claimId] = true;
        emit IdentityClaimRegistered(
            claimId,
            input.subject,
            input.namespace,
            input.identifierCommitment,
            issuer,
            input.attestationReference,
            uint64(block.timestamp),
            input.expiresAt,
            level,
            ClaimStatus.ACTIVE
        );
    }

    function _bind(IdentityBindingInput calldata input) internal {
        if (!ledger.hasOperation(input.operationId)) revert BindingNotFound(input.operationId, input.role);
        IdentityClaim storage c = claims[input.claimId];
        if (!claimExists[input.claimId]) revert ClaimNotFound(input.claimId);
        if (c.status == ClaimStatus.REVOKED) revert ClaimRevoked(input.claimId);
        if (c.status == ClaimStatus.SUPERSEDED) revert ClaimSuperseded(input.claimId);
        if (isClaimExpired(input.claimId)) revert ClaimExpired(input.claimId);
        if (c.subject != input.subject) revert UnauthorizedSubject(input.subject, c.subject);
        IGlyphReceiptLedger.OperationParties memory p = ledger.operationParties(input.operationId);
        address expected = input.role == ROLE_PAYER
            ? p.payer
            : input.role == ROLE_RECIPIENT ? p.recipient : input.role == ROLE_INITIATOR ? p.initiator : address(0);
        if (expected == address(0) || expected != input.subject) {
            revert RoleSubjectMismatch(input.role, expected, input.subject);
        }
        bytes32 key = _bindingKey(input.operationId, input.role);
        if (bindingExists[key]) revert DuplicateBinding(input.operationId, input.role);
        bindingExists[key] = true;
        bindings[input.operationId][input.role] = OperationIdentityBinding(
            input.operationId, input.claimId, input.subject, input.role, uint64(block.timestamp)
        );
        emit IdentityBoundToOperation(
            input.operationId, input.claimId, input.subject, input.role, uint64(block.timestamp)
        );
    }

    function _expectedAcknowledger(bytes32 operationId, bytes32 role) internal view returns (address) {
        IGlyphReceiptLedger.OperationParties memory p = ledger.operationParties(operationId);
        if (role == ROLE_RECIPIENT) return p.payer;
        if (role == ROLE_PAYER) return p.recipient;
        revert UnauthorizedAcknowledgement(msg.sender);
    }

    function _requireOperationParty(bytes32 operationId, address attestor, bytes32 role) internal view {
        IGlyphReceiptLedger.OperationParties memory p = ledger.operationParties(operationId);
        address expected = role == ROLE_PAYER
            ? p.payer
            : role == ROLE_RECIPIENT ? p.recipient : role == ROLE_INITIATOR ? p.initiator : address(0);
        if (expected == address(0) || attestor != expected) {
            revert UnauthorizedAttestor(attestor);
        }
    }

    function _authorize(address actor, bytes32 digest, bytes calldata signature) internal view {
        if (msg.sender == actor && signature.length == 0) return;
        actor.requireValidSignature(digest, signature);
    }

    function _authorizeRevocation(
        address actor,
        bytes32 claimId,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) internal {
        _checkDeadline(deadline);
        _consume(revocationNonce, actor, nonce);
        if (msg.sender == actor && signature.length == 0) return;
        actor.requireValidSignature(_hashRevocation(claimId, nonce, deadline), signature);
    }

    function _authorizeSupersession(
        address actor,
        bytes32 oldClaimId,
        IdentityClaimInput calldata replacement,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) internal {
        _checkDeadline(deadline);
        _consume(supersessionNonce, actor, nonce);
        if (msg.sender == actor && signature.length == 0) return;
        actor.requireValidSignature(_hashSupersession(oldClaimId, replacement, nonce, deadline), signature);
    }

    function _validateClaimInput(IdentityClaimInput calldata input) internal view {
        if (input.subject == address(0)) revert InvalidClaimInput("subject");
        if (input.namespace == bytes32(0)) revert InvalidClaimInput("namespace");
        if (input.identifierCommitment == bytes32(0)) revert InvalidClaimInput("identifierCommitment");
        if (input.expiresAt != 0 && input.expiresAt <= block.timestamp) revert DeadlineExpired(input.expiresAt);
    }

    function _consume(mapping(address => uint256) storage nonces, address subject, uint256 nonce) internal {
        uint256 expected = nonces[subject];
        if (nonce != expected) revert InvalidNonce(subject, expected, nonce);
        nonces[subject] = expected + 1;
    }

    function _checkDeadline(uint64 deadline) internal view {
        if (deadline < block.timestamp) revert DeadlineExpired(deadline);
    }

    function _bindingKey(bytes32 operationId, bytes32 role) internal view returns (bytes32) {
        return keccak256(abi.encode(BINDING_DOMAIN, block.chainid, address(this), operationId, role));
    }

    function _toTyped(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(bytes.concat(hex"1901", DOMAIN_SEPARATOR, structHash));
    }

    function _hashClaim(IdentityClaimInput calldata i) internal view returns (bytes32) {
        return _toTyped(
            keccak256(
                abi.encode(
                    CLAIM_TYPEHASH,
                    i.subject,
                    i.namespace,
                    i.identifierCommitment,
                    i.attestationReference,
                    i.expiresAt,
                    i.nonce,
                    i.deadline
                )
            )
        );
    }

    function _hashBinding(IdentityBindingInput calldata i) internal view returns (bytes32) {
        return _toTyped(
            keccak256(abi.encode(BINDING_TYPEHASH, i.operationId, i.claimId, i.subject, i.role, i.nonce, i.deadline))
        );
    }

    function _hashAck(IdentityAcknowledgementInput calldata i) internal view returns (bytes32) {
        return
            _toTyped(
                keccak256(abi.encode(ACK_TYPEHASH, i.operationId, i.claimId, i.subject, i.role, i.nonce, i.deadline))
            );
    }

    function _hashPurpose(PurposeAttestationInput calldata i) internal view returns (bytes32) {
        return _toTyped(
            keccak256(
                abi.encode(
                    PURPOSE_TYPEHASH,
                    i.operationId,
                    i.attestor,
                    i.role,
                    i.purposeCode,
                    i.contextHash,
                    i.supersedesAttestationId,
                    i.nonce,
                    i.deadline
                )
            )
        );
    }

    function _hashRevocation(bytes32 claimId, uint256 nonce, uint64 deadline) internal view returns (bytes32) {
        return _toTyped(keccak256(abi.encode(REVOCATION_TYPEHASH, claimId, nonce, deadline)));
    }

    function _hashSupersession(bytes32 oldClaimId, IdentityClaimInput calldata i, uint256 nonce, uint64 deadline)
        internal
        view
        returns (bytes32)
    {
        return _toTyped(
            keccak256(
                abi.encode(
                    SUPERSESSION_TYPEHASH,
                    oldClaimId,
                    i.subject,
                    i.namespace,
                    i.identifierCommitment,
                    i.attestationReference,
                    i.expiresAt,
                    i.nonce,
                    nonce,
                    deadline
                )
            )
        );
    }
}
