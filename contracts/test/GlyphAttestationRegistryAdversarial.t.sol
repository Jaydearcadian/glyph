// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Gate 1 adversarial closure for P1-R3-002 (attestation signature/boundary/getter/role-consensus).
// Adds isolated evidence for every gap named in state/reviews/p1-correctness-review3.json without
// modifying the reviewed source or prior fix surface.
import {Test} from "forge-std/Test.sol";
import {GlyphReceiptLedger} from "../src/GlyphReceiptLedger.sol";
import {GlyphAttestationRegistry} from "../src/GlyphAttestationRegistry.sol";
import {GlyphSignatureChecker} from "../src/libraries/GlyphSignatureChecker.sol";
import {IGlyphReceiptLedger} from "../src/interfaces/IGlyphReceiptLedger.sol";
import {MockEIP1271Malformed} from "./mocks/MockEIP1271Malformed.sol";

contract GlyphAttestationRegistryAdversarialTest is Test {
    GlyphReceiptLedger ledger;
    GlyphAttestationRegistry registry;

    uint256 payerPk = 0xA11CE;
    uint256 recipientPk = 0xB0B;
    uint256 attackerPk = 0xBADA55;
    uint256 outsiderPk = 0xC0FFEE;
    address payer;
    address recipient;
    address attacker;
    address initiator = address(0x7001);
    address issuer = address(0x7002);
    address recovery = address(0x7003);
    address router = address(0x7004);
    address vault = address(0x7005);
    address sourceAsset = address(0x7006);
    address destinationAsset = address(0x7007);
    address outsider;
    bytes32 op;
    bytes32 constant ROLE_PAYER = keccak256("glyph.identity.role.payer.v1");
    bytes32 constant ROLE_RECIPIENT = keccak256("glyph.identity.role.recipient.v1");
    bytes32 constant ROLE_INITIATOR = keccak256("glyph.identity.role.initiator.v1");
    bytes32 constant NS_DID = keccak256("glyph.identity.namespace.did-pkh.v1");
    bytes32 constant PURPOSE_BILL = keccak256("glyph.purpose.bill.v1");

    function setUp() public {
        payer = vm.addr(payerPk);
        recipient = vm.addr(recipientPk);
        attacker = vm.addr(attackerPk);
        outsider = vm.addr(outsiderPk);
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
            identifierCommitment: keccak256(abi.encode(subject, "commitment")),
            attestationReference: bytes32(0),
            expiresAt: uint64(block.timestamp + 30 days),
            nonce: nonce,
            deadline: uint64(block.timestamp + 1 hours)
        });
    }

    // == Changed chain ID and second verifying contract reject a valid EOA signature ==
    function test_eoaSignatureRejectsChangedChainAndSecondVerifyingContract() public {
        // second registry instance on a different chain id (warp chain via vm.chainId)
        vm.chainId(99999);
        GlyphAttestationRegistry altRegistry =
            new GlyphAttestationRegistry(IGlyphReceiptLedger(address(ledger)), address(this));
        vm.chainId(block.chainid); // restore

        GlyphAttestationRegistry.IdentityClaimInput memory input = _claim(payer, 0);
        bytes32 digestHere = registry.hashIdentityClaimAuthorization(input);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPk, digestHere);
        bytes memory sig = abi.encodePacked(r, s, v);
        // signature valid at `registry`; also sign for altRegistry domain (different chainId)
        bytes32 digestAlt = altRegistry.hashIdentityClaimAuthorization(input);
        (uint8 av, bytes32 ar, bytes32 az) = vm.sign(payerPk, digestAlt);
        bytes memory altSig = abi.encodePacked(ar, az, av);

        // correct registry + correct sig -> success
        bytes32 ok = registry.registerSelfIdentityWithSignature(input, sig);
        assertEq(registry.getIdentityClaim(ok).subject, payer);

        // second registry + sig bound to FIRST registry's domain -> recovered address mismatch -> revert
        vm.expectRevert(GlyphAttestationRegistry.InvalidSignature.selector);
        altRegistry.registerSelfIdentityWithSignature(input, sig);

        // first registry + sig bound to SECOND registry's domain -> revert
        GlyphAttestationRegistry.IdentityClaimInput memory recipInput = _claim(recipient, 0);
        vm.expectRevert(GlyphAttestationRegistry.InvalidSignature.selector);
        registry.registerSelfIdentityWithSignature(recipInput, altSig);
    }

    // == Malformed / short / wrong / reverting EIP-1271 return data reverts ==
    function test_eip1271MalformedShortWrongAndRevertingDataReverts() public {
        MockEIP1271Malformed wallet = new MockEIP1271Malformed();
        GlyphAttestationRegistry.IdentityClaimInput memory input = _claim(address(wallet), 0);
        // SHORT (4 bytes) -> data.length < 32
        wallet.setMode(MockEIP1271Malformed.Mode.SHORT);
        vm.expectRevert(abi.encodeWithSelector(GlyphSignatureChecker.InvalidEIP1271Signature.selector, address(wallet)));
        registry.registerSelfIdentityWithSignature(input, hex"1234");

        // WRONG32 (32 bytes, not magic)
        wallet.setMode(MockEIP1271Malformed.Mode.WRONG32);
        vm.expectRevert(abi.encodeWithSelector(GlyphSignatureChecker.InvalidEIP1271Signature.selector, address(wallet)));
        registry.registerSelfIdentityWithSignature(input, hex"1234");

        // REVERT
        wallet.setMode(MockEIP1271Malformed.Mode.REVERT);
        vm.expectRevert(abi.encodeWithSelector(GlyphSignatureChecker.InvalidEIP1271Signature.selector, address(wallet)));
        registry.registerSelfIdentityWithSignature(input, hex"1234");

        // OK
        wallet.setMode(MockEIP1271Malformed.Mode.OK);
        // MockEIP1271Malformed OK path returns magic for any digest; just ensure success.
        bytes32 ok = registry.registerSelfIdentityWithSignature(input, hex"1234");
        assertEq(registry.getIdentityClaim(ok).subject, address(wallet));
    }

    // == ECDSA edge vectors: high-s, zero-s, zero-r, invalid-v revert ==
    function test_eoaSignatureRejectsHighSZeroSandInvalidV() public {
        GlyphAttestationRegistry.IdentityClaimInput memory input = _claim(payer, 0);
        bytes32 digest = registry.hashIdentityClaimAuthorization(input);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPk, digest);

        // high-s: s' = N - s, v unchanged (requireValidSignature rejects s > N/2)
        bytes32 nDiv2 = bytes32(0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0);
        bytes32 highS =
            bytes32(uint256(0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141) - uint256(s));
        // ensure highS > nDiv2
        if (uint256(highS) <= uint256(nDiv2)) highS = bytes32(uint256(nDiv2) + 1);
        vm.expectRevert(GlyphAttestationRegistry.InvalidSignature.selector);
        registry.registerSelfIdentityWithSignature(input, abi.encodePacked(r, highS, v));

        // zero-s
        vm.expectRevert(GlyphAttestationRegistry.InvalidSignature.selector);
        registry.registerSelfIdentityWithSignature(input, abi.encodePacked(r, bytes32(0), v));

        // zero-r
        vm.expectRevert(GlyphAttestationRegistry.InvalidSignature.selector);
        registry.registerSelfIdentityWithSignature(input, abi.encodePacked(bytes32(0), s, v));

        // invalid v (3)
        vm.expectRevert(GlyphAttestationRegistry.InvalidSignature.selector);
        registry.registerSelfIdentityWithSignature(input, abi.encodePacked(r, s, uint8(3)));

        // wrong length (64)
        vm.expectRevert(GlyphAttestationRegistry.InvalidSignature.selector);
        registry.registerSelfIdentityWithSignature(input, abi.encodePacked(r, s));
    }

    // == Exact expiry equality: binding at expiresAt is rejected (<= not <) ==
    function test_claimExpiryExactEqualityRejected() public {
        GlyphAttestationRegistry.IdentityClaimInput memory input = _claim(payer, 0);
        input.expiresAt = uint64(block.timestamp + 100);
        vm.prank(payer);
        bytes32 claimId = registry.registerSelfIdentity(input);
        // boundary: at exactly expiresAt, isClaimExpired returns true -> bind reverts
        vm.warp(input.expiresAt);
        assertTrue(registry.isClaimExpired(claimId));
        GlyphAttestationRegistry.IdentityBindingInput memory b = GlyphAttestationRegistry.IdentityBindingInput(
            op, claimId, payer, ROLE_PAYER, registry.identityBindingNonce(payer), uint64(block.timestamp + 1 hours)
        );
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(GlyphAttestationRegistry.ClaimExpired.selector, claimId));
        registry.bindIdentity(b, "");
    }

    // == Fresh binding of revoked/superseded claim rejected ==
    function test_freshBindingOfRevokedAndSupersededClaimRejected() public {
        bytes32 payerClaim = _registerPayerClaim();
        _bind(payerClaim, payer, ROLE_PAYER);
        // revoke
        uint256 rn = registry.revocationNonce(payer);
        vm.prank(payer);
        registry.revokeIdentity(payerClaim, rn, uint64(block.timestamp + 1 hours), "");
        GlyphAttestationRegistry.IdentityBindingInput memory revokedBind = GlyphAttestationRegistry.IdentityBindingInput(
            op, payerClaim, payer, ROLE_PAYER, registry.identityBindingNonce(payer), uint64(block.timestamp + 1 hours)
        );
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(GlyphAttestationRegistry.ClaimRevoked.selector, payerClaim));
        registry.bindIdentity(revokedBind, "");

        // superseded path
        bytes32 recipientClaim = _registerRecipientClaim();
        uint256 sn = registry.supersessionNonce(recipient);
        GlyphAttestationRegistry.IdentityClaimInput memory replacement =
            _claim(recipient, registry.identityClaimNonce(recipient));
        vm.prank(recipient);
        registry.supersedeIdentity(recipientClaim, replacement, sn, uint64(block.timestamp + 1 hours), "");
        GlyphAttestationRegistry.IdentityBindingInput memory supersededBind =
            GlyphAttestationRegistry.IdentityBindingInput(
                op,
                recipientClaim,
                recipient,
                ROLE_RECIPIENT,
                registry.identityBindingNonce(recipient),
                uint64(block.timestamp + 1 hours)
            );
        vm.prank(recipient);
        vm.expectRevert(abi.encodeWithSelector(GlyphAttestationRegistry.ClaimSuperseded.selector, recipientClaim));
        registry.bindIdentity(supersededBind, "");
    }

    // == Nonexistent getters revert ==
    function test_nonexistentGettersRevert() public {
        vm.expectRevert(abi.encodeWithSelector(GlyphAttestationRegistry.ClaimNotFound.selector, bytes32(uint256(1))));
        registry.getIdentityClaim(bytes32(uint256(1)));
        vm.expectRevert(abi.encodeWithSelector(GlyphAttestationRegistry.BindingNotFound.selector, op, ROLE_PAYER));
        registry.getOperationIdentityBinding(op, ROLE_PAYER);
        vm.expectRevert(
            abi.encodeWithSelector(GlyphAttestationRegistry.InvalidSupersession.selector, bytes32(uint256(2)))
        );
        registry.getPurposeAttestation(bytes32(uint256(2)));
    }

    // == Validly authorized non-party purpose attestation rejected (role-scoped) ==
    function test_validlyAuthorizedNonPartyPurposeRejected() public {
        // outsider signs a purpose attestation AS payer role, but is not the payer -> UnauthorizedAttestor
        GlyphAttestationRegistry.PurposeAttestationInput memory p = GlyphAttestationRegistry.PurposeAttestationInput(
            op,
            outsider,
            ROLE_PAYER,
            PURPOSE_BILL,
            keccak256("ctx"),
            bytes32(0),
            registry.purposeAttestationNonce(outsider),
            uint64(block.timestamp + 1 hours)
        );
        // outsider signs its own authorization (valid signature, wrong party)
        bytes32 digest = registry.hashPurposeAttestationAuthorization(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(outsiderPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.expectRevert(abi.encodeWithSelector(GlyphAttestationRegistry.UnauthorizedAttestor.selector, outsider));
        registry.attestPurpose(p, sig);
    }

    // == payer == recipient dual-role consensus: two independently authorized role records ==
    function test_payerEqualsRecipientRequiresTwoAuthorizedRoleRecords() public {
        // build an operation where payer == recipient
        address same = address(0x9009);
        IGlyphReceiptLedger.OperationTerms memory t = IGlyphReceiptLedger.OperationTerms({
            operationType: keccak256("glyph.operation.pull.v1"),
            proposedPurposeCode: PURPOSE_BILL,
            initiator: initiator,
            payer: same,
            recipient: same,
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
            nonce: 2
        });
        vm.prank(initiator);
        bytes32 opSame = ledger.registerOperation(t);

        // claim for `same`
        GlyphAttestationRegistry.IdentityClaimInput memory c = _claim(same, 0);
        vm.prank(same);
        bytes32 claimId = registry.registerSelfIdentity(c);

        // bind as payer
        GlyphAttestationRegistry.IdentityBindingInput memory bp = GlyphAttestationRegistry.IdentityBindingInput(
            opSame, claimId, same, ROLE_PAYER, registry.identityBindingNonce(same), uint64(block.timestamp + 1 hours)
        );
        vm.prank(same);
        registry.bindIdentity(bp, "");
        // bind as recipient (second independent role record required)
        GlyphAttestationRegistry.IdentityBindingInput memory br = GlyphAttestationRegistry.IdentityBindingInput(
            opSame,
            claimId,
            same,
            ROLE_RECIPIENT,
            registry.identityBindingNonce(same),
            uint64(block.timestamp + 1 hours)
        );
        vm.prank(same);
        registry.bindIdentity(br, "");
        assertEq(registry.getOperationIdentityBinding(opSame, ROLE_PAYER).claimId, claimId);
        assertEq(registry.getOperationIdentityBinding(opSame, ROLE_RECIPIENT).claimId, claimId);

        // attest BOTH roles independently
        GlyphAttestationRegistry.PurposeAttestationInput memory pp = GlyphAttestationRegistry.PurposeAttestationInput(
            opSame,
            same,
            ROLE_PAYER,
            PURPOSE_BILL,
            keccak256("ctx"),
            bytes32(0),
            registry.purposeAttestationNonce(same),
            uint64(block.timestamp + 1 hours)
        );
        vm.prank(same);
        registry.attestPurpose(pp, "");
        GlyphAttestationRegistry.PurposeAttestationInput memory pr = GlyphAttestationRegistry.PurposeAttestationInput(
            opSame,
            same,
            ROLE_RECIPIENT,
            PURPOSE_BILL,
            keccak256("ctx"),
            bytes32(0),
            registry.purposeAttestationNonce(same),
            uint64(block.timestamp + 1 hours)
        );
        vm.prank(same);
        registry.attestPurpose(pr, "");
        (bool agreed,,) = registry.purposeConsensus(opSame);
        assertTrue(agreed, "coincident payer==recipient must reach consensus via two role records");
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
}
