// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IGlyphRegistry } from "../src/IGlyphRegistry.sol";
import { GlyphRegistry } from "../src/GlyphRegistry.sol";
import { GlyphSessionProxy } from "../src/GlyphSessionProxy.sol";

contract GlyphRegistryTest is Test {
    GlyphRegistry registry;
    bytes32 vesselId;

    uint256 constant PASSCODE_PK = 0x1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd;
    address creator = address(0xBEEF);
    address claimant = address(0xFACE);
    address attacker = address(0xA77AC4);

    function setUp() public {
        registry = new GlyphRegistry();
        vesselId = keccak256(abi.encodePacked("glyph-nonce-1"));
    }

    /// @dev Replicates the in-browser claim signature: ephemeral key signs
    ///      (msg.sender, vesselId) under the Ethereum signed-message envelope.
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
        registry.createValueVessel{ value: 0.5 ether }(vesselId, address(0), 0.5 ether, gatekeeper, 0);

        bytes memory sig = _signClaim(PASSCODE_PK, claimant, vesselId);
        uint256 before = claimant.balance;
        vm.prank(claimant);
        registry.claimVessel(vesselId, sig);
        assertEq(claimant.balance - before, 0.5 ether);

        assertTrue(registry.vessels(vesselId).claimed);
    }

    function test_RevertWhenFrontRunnerReplaysSignature() public {
        address gatekeeper = vm.addr(PASSCODE_PK);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        registry.createValueVessel{ value: 0.5 ether }(vesselId, address(0), 0.5 ether, gatekeeper, 0);

        bytes memory sig = _signClaim(PASSCODE_PK, claimant, vesselId);
        vm.prank(attacker);
        vm.expectRevert(IGlyphRegistry.InvalidSignature.selector);
        registry.claimVessel(vesselId, sig);
    }

    function test_RevertWhenWrongPasscode() public {
        uint256 wrongPk = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;
        address gatekeeper = vm.addr(PASSCODE_PK);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        registry.createValueVessel{ value: 0.5 ether }(vesselId, address(0), 0.5 ether, gatekeeper, 0);

        bytes memory sig = _signClaim(wrongPk, claimant, vesselId);
        vm.prank(claimant);
        vm.expectRevert(IGlyphRegistry.InvalidSignature.selector);
        registry.claimVessel(vesselId, sig);
    }

    function test_ExpireRecoversToCreator() public {
        address gatekeeper = vm.addr(PASSCODE_PK);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        registry.createValueVessel{ value: 0.5 ether }(vesselId, address(0), 0.5 ether, gatekeeper, 100);

        vm.warp(200);
        uint256 before = creator.balance;
        vm.prank(creator);
        registry.expireValueVessel(vesselId);
        assertEq(creator.balance - before, 0.5 ether);
    }

    function test_SessionRegisterAndRevoke() public {
        bytes32 sid = keccak256("session-1");
        address[] memory targets = new address[](1);
        targets[0] = address(0x9999);
        vm.prank(claimant);
        registry.registerSession(sid, targets, 1 ether, 0, address(0), block.timestamp + 3600);

        IGlyphRegistry.SessionPolicy memory s = registry.sessions(sid);
        assertEq(s.owner, claimant);
        assertFalse(s.revoked);

        vm.prank(claimant);
        registry.revokeSession(sid);
        assertTrue(registry.sessions(sid).revoked);
    }

    function test_RevertSessionDoubleRegister() public {
        bytes32 sid = keccak256("session-1");
        address[] memory targets = new address[](1);
        targets[0] = address(0x9999);
        vm.prank(claimant);
        registry.registerSession(sid, targets, 1 ether, 0, address(0), block.timestamp + 3600);

        vm.prank(claimant);
        vm.expectRevert(IGlyphRegistry.SessionExists.selector);
        registry.registerSession(sid, targets, 1 ether, 0, address(0), block.timestamp + 3600);
    }
}

/// @notice Exercises the EIP-7702 session proxy execution policy end-to-end.
contract GlyphSessionProxyTest is Test {
    GlyphRegistry registry;
    GlyphSessionProxy proxy;

    address owner = address(0xBEEF);
    address target = address(0x9999);

    function setUp() public {
        registry = new GlyphRegistry();
        proxy = new GlyphSessionProxy(registry);
    }

    function test_ExecuteWhitelistedTarget() public {
        bytes32 sid = keccak256("sess-x");
        address[] memory targets = new address[](1);
        targets[0] = target;
        vm.prank(owner);
        registry.registerSession(sid, targets, 1 ether, 0, address(0), block.timestamp + 3600);

        // A whitelisted call passes the policy gate.
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", owner, 1);
        vm.prank(owner);
        proxy.execute(sid, target, data); // should not revert
        assertTrue(true);
    }

    function test_RevertExecuteNonWhitelistedTarget() public {
        bytes32 sid = keccak256("sess-y");
        address[] memory targets = new address[](1);
        targets[0] = target;
        vm.prank(owner);
        registry.registerSession(sid, targets, 1 ether, 0, address(0), block.timestamp + 3600);

        address rogue = address(0xDEAD);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", owner, 1);
        vm.prank(owner);
        vm.expectRevert(IGlyphRegistry.Unauthorized.selector);
        proxy.execute(sid, rogue, data);
    }

    function test_RevertExecuteAfterRevoke() public {
        bytes32 sid = keccak256("sess-z");
        address[] memory targets = new address[](1);
        targets[0] = target;
        vm.prank(owner);
        registry.registerSession(sid, targets, 1 ether, 0, address(0), block.timestamp + 3600);
        vm.prank(owner);
        registry.revokeSession(sid);

        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", owner, 1);
        vm.prank(owner);
        vm.expectRevert(IGlyphRegistry.Unauthorized.selector);
        proxy.execute(sid, target, data);
    }
}
