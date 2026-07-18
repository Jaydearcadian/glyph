// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GlyphReceiptLedger} from "../src/GlyphReceiptLedger.sol";
import {GlyphAttestationRegistry} from "../src/GlyphAttestationRegistry.sol";
import {IGlyphReceiptLedger} from "../src/interfaces/IGlyphReceiptLedger.sol";
import {MockERC1271Wallet} from "./mocks/MockERC1271Wallet.sol";

contract GlyphAttestationRegistryTest is Test {
    GlyphReceiptLedger ledger;
    GlyphAttestationRegistry registry;

    uint256 payerPk = 0xA11CE;
    uint256 recipientPk = 0xB0B;
    address payer;
    address recipient;
    address initiator = address(0x7001);
    address issuer = address(0x7002);
    address recovery = address(0x7003);
    address router = address(0x7004);
    address vault = address(0x7005);
    address sourceAsset = address(0x7006);
    address destinationAsset = address(0x7007);
    bytes32 op;
    bytes32 constant ROLE_PAYER = keccak256("glyph.identity.role.payer.v1");
    bytes32 constant ROLE_RECIPIENT = keccak256("glyph.identity.role.recipient.v1");
    bytes32 constant NS_DID = keccak256("glyph.identity.namespace.did-pkh.v1");
    bytes32 constant PURPOSE_BILL = keccak256("glyph.purpose.bill.v1");
    bytes32 constant PURPOSE_INVOICE = keccak256("glyph.purpose.invoice.v1");

    function setUp() public {
        payer = vm.addr(payerPk);
        recipient = vm.addr(recipientPk);
        ledger = new GlyphReceiptLedger(address(this));
        registry = new GlyphAttestationRegistry(IGlyphReceiptLedger(address(ledger)), address(this));
        registry.configureIssuer(issuer, true);
        IGlyphReceiptLedger.OperationTerms memory t = IGlyphReceiptLedger.OperationTerms({
            operationType: keccak256("glyph.operation.pull.v1"),
            proposedPurposeCode: PURPOSE_BILL,
            initiator: initiator,
            payer: payer,
            recipient: recipient,
            recoveryAddress: recovery,
            sourceRouter: router,
            destinationVault: vault,
            sourceChainId: uint64(block.chainid),
            destinationChainId: 84532,
            sourceAsset: sourceAsset,
            destinationAsset: destinationAsset,
            maximumInput: 110,
            destinationAmount: 100,
            maximumFee: 10,
            claimantRule: keccak256("claimant"),
            privateContextHash: keccak256("ctx"),
            expiry: uint64(block.timestamp + 1 days),
            nonce: 1
        });
        vm.prank(initiator);
        op = ledger.registerOperation(t);
    }

    function _claim(address subject, uint256 nonce)
        internal
        view
        returns (GlyphAttestationRegistry.IdentityClaimInput memory)
    {
        return GlyphAttestationRegistry.IdentityClaimInput({
            subject: subject,
            namespace: NS_DID,
            identifierCommitment: keccak256(abi.encode(subject, "commitment-only")),
            attestationReference: bytes32(0),
            expiresAt: uint64(block.timestamp + 30 days),
            nonce: nonce,
            deadline: uint64(block.timestamp + 1 hours)
        });
    }

    function _signClaim(GlyphAttestationRegistry.IdentityClaimInput memory input, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = registry.hashIdentityClaimAuthorization(input);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signBinding(GlyphAttestationRegistry.IdentityBindingInput memory input, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = registry.hashIdentityBindingAuthorization(input);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signAck(GlyphAttestationRegistry.IdentityAcknowledgementInput memory input, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = registry.hashIdentityAcknowledgementAuthorization(input);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signPurpose(GlyphAttestationRegistry.PurposeAttestationInput memory input, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = registry.hashPurposeAttestationAuthorization(input);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signSupersession(
        bytes32 oldClaimId,
        GlyphAttestationRegistry.IdentityClaimInput memory replacement,
        uint256 nonce,
        uint64 deadline,
        uint256 pk
    ) internal view returns (bytes memory) {
        bytes32 digest = registry.hashIdentitySupersessionAuthorization(oldClaimId, replacement, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _registerPayerClaim() internal returns (bytes32 claimId) {
        GlyphAttestationRegistry.IdentityClaimInput memory input = _claim(payer, registry.identityClaimNonce(payer));
        vm.prank(payer);
        claimId = registry.registerSelfIdentity(input);
    }

    function _registerRecipientClaim() internal returns (bytes32 claimId) {
        GlyphAttestationRegistry.IdentityClaimInput memory input =
            _claim(recipient, registry.identityClaimNonce(recipient));
        vm.prank(recipient);
        claimId = registry.registerSelfIdentity(input);
    }

    function _bind(bytes32 claimId, address subject, bytes32 role) internal {
        GlyphAttestationRegistry.IdentityBindingInput memory input = GlyphAttestationRegistry.IdentityBindingInput(
            op, claimId, subject, role, registry.identityBindingNonce(subject), uint64(block.timestamp + 1 hours)
        );
        vm.prank(subject);
        registry.bindIdentity(input, "");
    }

    function test_directSelfClaimForcesSelfAssertedAndRejectsCrossPartyForgery() public {
        GlyphAttestationRegistry.IdentityClaimInput memory input = _claim(payer, 0);
        vm.prank(recipient);
        vm.expectRevert();
        registry.registerSelfIdentity(input);
        vm.prank(payer);
        bytes32 claimId = registry.registerSelfIdentity(input);
        GlyphAttestationRegistry.IdentityClaim memory c = registry.getIdentityClaim(claimId);
        assertEq(c.subject, payer);
        assertEq(uint256(c.level), uint256(GlyphAttestationRegistry.VerificationLevel.SELF_ASSERTED));
        assertEq(c.issuer, address(0));
    }

    function test_relayedEoaClaimRejectsWrongDomainNonceDeadlineReplayAndWrongSigner() public {
        GlyphAttestationRegistry.IdentityClaimInput memory input = _claim(payer, 0);
        bytes memory sig = _signClaim(input, payerPk);
        bytes32 claimId = registry.registerSelfIdentityWithSignature(input, sig);
        assertEq(registry.getIdentityClaim(claimId).subject, payer);
        vm.expectRevert();
        registry.registerSelfIdentityWithSignature(input, sig);
        GlyphAttestationRegistry.IdentityClaimInput memory stale =
            _claim(recipient, registry.identityClaimNonce(recipient));
        stale.deadline = uint64(block.timestamp - 1);
        bytes memory staleSig = _signClaim(stale, recipientPk);
        vm.expectRevert();
        registry.registerSelfIdentityWithSignature(stale, staleSig);
        GlyphAttestationRegistry.IdentityClaimInput memory wrong =
            _claim(recipient, registry.identityClaimNonce(recipient));
        bytes memory wrongSig = _signClaim(wrong, payerPk);
        vm.expectRevert();
        registry.registerSelfIdentityWithSignature(wrong, wrongSig);
    }

    function test_eip1271SuccessWrongMagicAndRevertFailure() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet();
        GlyphAttestationRegistry.IdentityClaimInput memory input = _claim(address(wallet), 0);
        bytes32 digest = registry.hashIdentityClaimAuthorization(input);
        wallet.setValidDigest(digest, true);
        bytes32 ok = registry.registerSelfIdentityWithSignature(input, hex"1234");
        assertEq(registry.getIdentityClaim(ok).subject, address(wallet));
        MockERC1271Wallet bad = new MockERC1271Wallet();
        GlyphAttestationRegistry.IdentityClaimInput memory badInput = _claim(address(bad), 0);
        bad.setWrongMagic(true);
        vm.expectRevert();
        registry.registerSelfIdentityWithSignature(badInput, hex"1234");
        bad.setWrongMagic(false);
        bad.setShouldRevert(true);
        vm.expectRevert();
        registry.registerSelfIdentityWithSignature(badInput, hex"1234");
    }

    function test_issuerClaimForcesIssuerLevelAndUnauthorizedIssuerRejected() public {
        GlyphAttestationRegistry.IdentityClaimInput memory input = _claim(recipient, 0);
        input.attestationReference = keccak256("issuer-ref");
        vm.prank(payer);
        vm.expectRevert();
        registry.registerIssuerIdentity(input);
        vm.prank(issuer);
        bytes32 claimId = registry.registerIssuerIdentity(input);
        GlyphAttestationRegistry.IdentityClaim memory c = registry.getIdentityClaim(claimId);
        assertEq(uint256(c.level), uint256(GlyphAttestationRegistry.VerificationLevel.ISSUER_VERIFIED));
        assertEq(c.issuer, issuer);
    }

    function test_bindingChecksImmutableOperationPartyRoleOnceAndClaimActive() public {
        bytes32 payerClaim = _registerPayerClaim();
        GlyphAttestationRegistry.IdentityBindingInput memory badBind = GlyphAttestationRegistry.IdentityBindingInput(
            op,
            payerClaim,
            payer,
            ROLE_PAYER,
            registry.identityBindingNonce(recipient),
            uint64(block.timestamp + 1 hours)
        );
        vm.prank(recipient);
        vm.expectRevert();
        registry.bindIdentity(badBind, "");
        _bind(payerClaim, payer, ROLE_PAYER);
        assertEq(registry.getOperationIdentityBinding(op, ROLE_PAYER).claimId, payerClaim);
        GlyphAttestationRegistry.IdentityBindingInput memory duplicate = GlyphAttestationRegistry.IdentityBindingInput(
            op, payerClaim, payer, ROLE_PAYER, registry.identityBindingNonce(payer), uint64(block.timestamp + 1 hours)
        );
        vm.prank(payer);
        vm.expectRevert();
        registry.bindIdentity(duplicate, "");
        bytes32 recipientClaim = _registerRecipientClaim();
        GlyphAttestationRegistry.IdentityBindingInput memory wrongRole = GlyphAttestationRegistry.IdentityBindingInput(
            op,
            recipientClaim,
            recipient,
            ROLE_PAYER,
            registry.identityBindingNonce(recipient),
            uint64(block.timestamp + 1 hours)
        );
        vm.prank(recipient);
        vm.expectRevert();
        registry.bindIdentity(wrongRole, "");
    }

    function test_expiredRevokedSupersededCannotNewlyBindButHistoricalBindingPersists() public {
        bytes32 payerClaim = _registerPayerClaim();
        _bind(payerClaim, payer, ROLE_PAYER);
        uint256 payerRevocationNonce = registry.revocationNonce(payer);
        vm.prank(payer);
        registry.revokeIdentity(payerClaim, payerRevocationNonce, uint64(block.timestamp + 1 hours), "");
        assertEq(registry.getOperationIdentityBinding(op, ROLE_PAYER).claimId, payerClaim);
        bytes32 recipientClaim = _registerRecipientClaim();
        GlyphAttestationRegistry.IdentityClaimInput memory replacementInput =
            _claim(recipient, registry.identityClaimNonce(recipient));
        uint256 recipientRevocationNonce = registry.revocationNonce(recipient);
        vm.prank(recipient);
        bytes32 replacement = registry.supersedeIdentity(
            recipientClaim, replacementInput, recipientRevocationNonce, uint64(block.timestamp + 1 hours), ""
        );
        assertTrue(replacement != bytes32(0));
        GlyphAttestationRegistry.IdentityBindingInput memory oldBind = GlyphAttestationRegistry.IdentityBindingInput(
            op,
            recipientClaim,
            recipient,
            ROLE_RECIPIENT,
            registry.identityBindingNonce(recipient),
            uint64(block.timestamp + 1 hours)
        );
        vm.prank(recipient);
        vm.expectRevert();
        registry.bindIdentity(oldBind, "");
        GlyphAttestationRegistry.IdentityClaimInput memory exp =
            _claim(initiator, registry.identityClaimNonce(initiator));
        exp.expiresAt = uint64(block.timestamp + 1);
        vm.prank(initiator);
        bytes32 expired = registry.registerSelfIdentity(exp);
        vm.warp(block.timestamp + 2);
        GlyphAttestationRegistry.IdentityBindingInput memory expiredBind = GlyphAttestationRegistry.IdentityBindingInput(
            op,
            expired,
            initiator,
            registry.ROLE_INITIATOR(),
            registry.identityBindingNonce(initiator),
            uint64(block.timestamp + 1 hours)
        );
        vm.prank(initiator);
        vm.expectRevert();
        registry.bindIdentity(expiredBind, "");
    }

    function test_acknowledgementRestrictedToCounterpartyAndDoesNotUpgradeVerification() public {
        bytes32 payerClaim = _registerPayerClaim();
        bytes32 recipientClaim = _registerRecipientClaim();
        _bind(payerClaim, payer, ROLE_PAYER);
        _bind(recipientClaim, recipient, ROLE_RECIPIENT);
        GlyphAttestationRegistry.IdentityAcknowledgementInput memory ack =
            GlyphAttestationRegistry.IdentityAcknowledgementInput(
                op,
                recipientClaim,
                recipient,
                ROLE_RECIPIENT,
                registry.identityAcknowledgementNonce(payer),
                uint64(block.timestamp + 1 hours)
            );
        vm.prank(payer);
        registry.acknowledgeIdentity(ack, "");
        assertEq(
            uint256(registry.getIdentityClaim(recipientClaim).level),
            uint256(GlyphAttestationRegistry.VerificationLevel.SELF_ASSERTED)
        );
        GlyphAttestationRegistry.IdentityAcknowledgementInput memory badAck =
            GlyphAttestationRegistry.IdentityAcknowledgementInput(
                op,
                payerClaim,
                payer,
                ROLE_PAYER,
                registry.identityAcknowledgementNonce(payer),
                uint64(block.timestamp + 1 hours)
            );
        vm.prank(payer);
        vm.expectRevert();
        registry.acknowledgeIdentity(badAck, "");
    }

    function test_purposeIndependentConsensusDisagreementSupersessionAndSignatureReplay() public {
        GlyphAttestationRegistry.PurposeAttestationInput memory p1 = GlyphAttestationRegistry.PurposeAttestationInput(
            op,
            payer,
            ROLE_PAYER,
            PURPOSE_BILL,
            keccak256("ctx1"),
            bytes32(0),
            registry.purposeAttestationNonce(payer),
            uint64(block.timestamp + 1 hours)
        );
        bytes memory sig = _signPurpose(p1, payerPk);
        bytes32 payerAtt = registry.attestPurpose(p1, sig);
        vm.expectRevert();
        registry.attestPurpose(p1, sig);
        GlyphAttestationRegistry.PurposeAttestationInput memory p2 = GlyphAttestationRegistry.PurposeAttestationInput(
            op,
            recipient,
            ROLE_RECIPIENT,
            PURPOSE_INVOICE,
            keccak256("ctx2"),
            bytes32(0),
            registry.purposeAttestationNonce(recipient),
            uint64(block.timestamp + 1 hours)
        );
        vm.prank(recipient);
        bytes32 recipientAtt = registry.attestPurpose(p2, "");
        (bool ok,,) = registry.purposeConsensus(op);
        assertFalse(ok);
        GlyphAttestationRegistry.PurposeAttestationInput memory p3 = GlyphAttestationRegistry.PurposeAttestationInput(
            op,
            recipient,
            ROLE_RECIPIENT,
            PURPOSE_BILL,
            keccak256("ctx1"),
            recipientAtt,
            registry.purposeAttestationNonce(recipient),
            uint64(block.timestamp + 1 hours)
        );
        vm.prank(recipient);
        bytes32 superseding = registry.attestPurpose(p3, "");
        (ok,,) = registry.purposeConsensus(op);
        assertTrue(ok);
        assertEq(registry.getPurposeAttestation(payerAtt).attestor, payer);
        assertEq(registry.getPurposeAttestation(superseding).supersedesAttestationId, recipientAtt);
        GlyphAttestationRegistry.PurposeAttestationInput memory badPurpose =
            GlyphAttestationRegistry.PurposeAttestationInput(
                op,
                address(0xDEAD),
                ROLE_PAYER,
                PURPOSE_BILL,
                bytes32(0),
                bytes32(0),
                0,
                uint64(block.timestamp + 1 hours)
            );
        vm.expectRevert();
        registry.attestPurpose(badPurpose, "");
    }

    function test_bindingAndAcknowledgementSignaturePathsRejectReplayAndWrongSigner() public {
        bytes32 payerClaim = _registerPayerClaim();
        GlyphAttestationRegistry.IdentityBindingInput memory b = GlyphAttestationRegistry.IdentityBindingInput(
            op, payerClaim, payer, ROLE_PAYER, registry.identityBindingNonce(payer), uint64(block.timestamp + 1 hours)
        );
        bytes memory sig = _signBinding(b, payerPk);
        registry.bindIdentity(b, sig);
        vm.expectRevert();
        registry.bindIdentity(b, sig);
        bytes32 recipientClaim = _registerRecipientClaim();
        _bind(recipientClaim, recipient, ROLE_RECIPIENT);
        GlyphAttestationRegistry.IdentityAcknowledgementInput memory a =
            GlyphAttestationRegistry.IdentityAcknowledgementInput(
                op,
                recipientClaim,
                recipient,
                ROLE_RECIPIENT,
                registry.identityAcknowledgementNonce(payer),
                uint64(block.timestamp + 1 hours)
            );
        bytes memory badSig = _signAck(a, recipientPk);
        vm.expectRevert();
        registry.acknowledgeIdentity(a, badSig);
        registry.acknowledgeIdentity(a, _signAck(a, payerPk));
    }

    function test_expiredSignedBindingAcknowledgementAndPurposeAuthorizationsRevert() public {
        vm.warp(100);
        bytes32 payerClaim = _registerPayerClaim();
        GlyphAttestationRegistry.IdentityBindingInput memory b = GlyphAttestationRegistry.IdentityBindingInput(
            op, payerClaim, payer, ROLE_PAYER, registry.identityBindingNonce(payer), uint64(block.timestamp - 1)
        );
        bytes memory expiredBindingSig = _signBinding(b, payerPk);
        vm.expectRevert(abi.encodeWithSelector(GlyphAttestationRegistry.DeadlineExpired.selector, b.deadline));
        registry.bindIdentity(b, expiredBindingSig);

        b.deadline = uint64(block.timestamp + 1 hours);
        registry.bindIdentity(b, _signBinding(b, payerPk));
        bytes32 recipientClaim = _registerRecipientClaim();
        _bind(recipientClaim, recipient, ROLE_RECIPIENT);

        GlyphAttestationRegistry.IdentityAcknowledgementInput memory a =
            GlyphAttestationRegistry.IdentityAcknowledgementInput(
                op,
                recipientClaim,
                recipient,
                ROLE_RECIPIENT,
                registry.identityAcknowledgementNonce(payer),
                uint64(block.timestamp - 1)
            );
        bytes memory expiredAckSig = _signAck(a, payerPk);
        vm.expectRevert(abi.encodeWithSelector(GlyphAttestationRegistry.DeadlineExpired.selector, a.deadline));
        registry.acknowledgeIdentity(a, expiredAckSig);

        GlyphAttestationRegistry.PurposeAttestationInput memory p = GlyphAttestationRegistry.PurposeAttestationInput(
            op,
            payer,
            ROLE_PAYER,
            PURPOSE_BILL,
            keccak256("ctx-expired"),
            bytes32(0),
            registry.purposeAttestationNonce(payer),
            uint64(block.timestamp - 1)
        );
        bytes memory expiredPurposeSig = _signPurpose(p, payerPk);
        vm.expectRevert(abi.encodeWithSelector(GlyphAttestationRegistry.DeadlineExpired.selector, p.deadline));
        registry.attestPurpose(p, expiredPurposeSig);
    }

    function test_issuerReplayAfterRevokeAndAfterSupersessionCannotResurrectClaim() public {
        GlyphAttestationRegistry.IdentityClaimInput memory input =
            _claim(recipient, registry.identityClaimNonce(issuer));
        input.attestationReference = keccak256("issuer-ref");
        vm.prank(issuer);
        bytes32 claimId = registry.registerIssuerIdentity(input);
        uint256 issuerRevocationNonce = registry.revocationNonce(issuer);
        vm.prank(issuer);
        registry.revokeIdentity(claimId, issuerRevocationNonce, uint64(block.timestamp + 1 hours), "");
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(GlyphAttestationRegistry.InvalidNonce.selector, issuer, 1, 0));
        registry.registerIssuerIdentity(input);

        GlyphAttestationRegistry.IdentityClaimInput memory second =
            _claim(recipient, registry.identityClaimNonce(issuer));
        second.attestationReference = keccak256("issuer-ref-2");
        vm.prank(issuer);
        bytes32 secondId = registry.registerIssuerIdentity(second);
        GlyphAttestationRegistry.IdentityClaimInput memory replacement =
            _claim(recipient, registry.identityClaimNonce(issuer));
        replacement.attestationReference = keccak256("issuer-ref-3");
        uint256 issuerSupersessionNonce = registry.supersessionNonce(issuer);
        vm.prank(issuer);
        registry.supersedeIdentity(
            secondId, replacement, issuerSupersessionNonce, uint64(block.timestamp + 1 hours), ""
        );
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(GlyphAttestationRegistry.InvalidNonce.selector, issuer, 3, 1));
        registry.registerIssuerIdentity(second);
        assertEq(
            uint256(registry.getIdentityClaim(secondId).status),
            uint256(GlyphAttestationRegistry.ClaimStatus.SUPERSEDED)
        );
    }

    function test_supersessionSignatureBindsReplacementFieldsAndCannotBeUsedForRevocation() public {
        bytes32 payerClaim = _registerPayerClaim();
        GlyphAttestationRegistry.IdentityClaimInput memory replacement =
            _claim(payer, registry.identityClaimNonce(payer));
        replacement.identifierCommitment = keccak256("replacement-a");
        uint256 nonce = registry.supersessionNonce(payer);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _signSupersession(payerClaim, replacement, nonce, deadline, payerPk);

        vm.expectRevert();
        registry.revokeIdentity(payerClaim, nonce, deadline, sig);

        GlyphAttestationRegistry.IdentityClaimInput memory mutated = _claim(payer, replacement.nonce);
        mutated.identifierCommitment = keccak256("replacement-b");
        vm.expectRevert();
        registry.supersedeIdentity(payerClaim, mutated, nonce, deadline, sig);

        uint256 currentSupersessionNonce = registry.supersessionNonce(payer);
        registry.supersedeIdentity(payerClaim, replacement, currentSupersessionNonce, deadline, sig);
    }
}
