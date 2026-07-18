// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IGlyphRegistry} from "../src/IGlyphRegistry.sol";
import {GlyphRegistry} from "../src/GlyphRegistry.sol";
import {GlyphSessionProxy} from "../src/GlyphSessionProxy.sol";

contract GlyphRegistryTest is Test {
    GlyphRegistry registry;
    bytes32 vesselId;

    uint256 constant PASSCODE_PK = 0x1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd;
    address creator = address(0xBEEF);
    address claimant = address(0xFACE);
    address attacker = address(0xA77AC4);
    bytes32 salt = keccak256("glyph-nonce-1");

    function setUp() public {
        registry = new GlyphRegistry();
        vesselId = keccak256(abi.encodePacked(creator, salt)); // off-chain deterministic ID
    }

    /// @dev Replicates in-browser claim signature: ephemeral key signs (msg.sender, vesselId)
    ///      under the Ethereum signed-message envelope (front-run-proof: binds to claimant).
    function _signClaim(uint256 pk, address who, bytes32 id) internal view returns (bytes memory) {
        bytes32 msgHash = keccak256(abi.encodePacked(who, id));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function test_ValueVesselCreateAndClaim() public {
        address gatekeeper = vm.addr(PASSCODE_PK);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        registry.forgeVessel{value: 0.5 ether}(address(0), 0.5 ether, gatekeeper, salt);

        bytes memory sig = _signClaim(PASSCODE_PK, claimant, vesselId);
        uint256 before = claimant.balance;
        vm.prank(claimant);
        registry.claimVessel(vesselId, sig);
        assertEq(claimant.balance - before, 0.5 ether);
    }

    function test_RevertWhenFrontRunnerReplaysSignature() public {
        address gatekeeper = vm.addr(PASSCODE_PK);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        registry.forgeVessel{value: 0.5 ether}(address(0), 0.5 ether, gatekeeper, salt);

        bytes memory sig = _signClaim(PASSCODE_PK, claimant, vesselId);
        // Attacker submits the copied signature from their OWN address -> sig binds to claimant, fails.
        vm.prank(attacker);
        vm.expectRevert("GLYPH: BAD_SIG");
        registry.claimVessel(vesselId, sig);
    }

    function test_RevertWhenWrongPasscode() public {
        uint256 wrongPk = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;
        address gatekeeper = vm.addr(PASSCODE_PK);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        registry.forgeVessel{value: 0.5 ether}(address(0), 0.5 ether, gatekeeper, salt);

        bytes memory sig = _signClaim(wrongPk, claimant, vesselId);
        vm.prank(claimant);
        vm.expectRevert("GLYPH: BAD_SIG");
        registry.claimVessel(vesselId, sig);
    }

    function test_ExpireRecoversToCreator() public {
        address gatekeeper = vm.addr(PASSCODE_PK);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        registry.forgeVessel{value: 0.5 ether}(address(0), 0.5 ether, gatekeeper, salt);

        vm.warp(block.timestamp + 3601); // past 1h expiry set in forgeVessel
        uint256 before = creator.balance;
        vm.prank(creator);
        registry.expireVessel(vesselId);
        assertEq(creator.balance - before, 0.5 ether);
    }
}

/// @notice Exercises the EIP-7702 session proxy execution policy end-to-end (ERC-7201 store).
contract GlyphSessionProxyTest is Test {
    GlyphSessionProxy proxy;

    address owner = address(0xBEEF);
    address target = address(0x9999);
    bytes32 sessionId = keccak256("sess-x");

    function setUp() public {
        proxy = new GlyphSessionProxy();
    }

    function _register() internal {
        address[] memory targets = new address[](1);
        targets[0] = target;
        vm.prank(owner);
        proxy.registerSession(sessionId, owner, 1 ether, block.timestamp + 3600, targets);
    }

    function test_ExecuteWhitelistedTarget() public {
        _register();
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", owner, 1);
        vm.prank(owner);
        proxy.execute(sessionId, target, 0, data); // passes guardrails
        assertTrue(true);
    }

    function test_RevertExecuteNonWhitelistedTarget() public {
        _register();
        address rogue = address(0xDEAD);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", owner, 1);
        vm.prank(owner);
        vm.expectRevert("GLYPH: UNAUTHORIZED_TARGET_CONTRACT");
        proxy.execute(sessionId, rogue, 0, data);
    }

    function test_RevertExecuteAfterRevoke() public {
        _register();
        vm.prank(owner);
        proxy.revokeSession(sessionId);

        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", owner, 1);
        vm.prank(owner);
        vm.expectRevert("GLYPH: SESSION_UNKNOWN");
        proxy.execute(sessionId, target, 0, data);
    }

    function test_RevertExecuteExpired() public {
        _register();
        vm.warp(block.timestamp + 3601); // past expiry
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", owner, 1);
        vm.prank(owner);
        vm.expectRevert("GLYPH: SESSION_EXPIRED");
        proxy.execute(sessionId, target, 0, data);
    }
}
