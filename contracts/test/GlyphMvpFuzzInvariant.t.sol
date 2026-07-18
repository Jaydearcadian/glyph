// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

contract GlyphMvpInvariantHandler {
    uint256 public maximumInput;
    uint256 public principal;
    uint256 public fees;
    uint256 public residual;

    function setLegs(uint128 rawMaximumInput, uint128 rawPrincipal, uint128 rawFees) external {
        maximumInput = uint256(rawMaximumInput) + 1;
        principal = uint256(rawPrincipal) % (maximumInput + 1);
        uint256 remaining = maximumInput - principal;
        fees = remaining == 0 ? 0 : uint256(rawFees) % (remaining + 1);
        residual = maximumInput - principal - fees;
    }
}

contract GlyphMvpFuzzInvariantTest is Test {
    GlyphMvpInvariantHandler handler;

    function setUp() public {
        handler = new GlyphMvpInvariantHandler();
        targetContract(address(handler));
    }

    function testFuzz_feeConservation(uint128 rawMaximumInput, uint128 rawPrincipal, uint128 rawFees) public pure {
        uint256 maximumInput = uint256(rawMaximumInput) + 1;
        uint256 principal = uint256(rawPrincipal) % (maximumInput + 1);
        uint256 remaining = maximumInput - principal;
        uint256 fees = remaining == 0 ? 0 : uint256(rawFees) % (remaining + 1);
        uint256 residual = maximumInput - principal - fees;
        assertEq(maximumInput, principal + fees + residual);
    }

    function invariant_statefulFeeConservation() public view {
        assertEq(handler.maximumInput(), handler.principal() + handler.fees() + handler.residual());
    }
}
