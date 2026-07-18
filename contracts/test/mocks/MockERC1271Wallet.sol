// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockERC1271Wallet {
    bytes4 constant MAGIC = 0x1626ba7e;
    mapping(bytes32 => bool) public validDigest;
    bool public wrongMagic;
    bool public shouldRevert;

    function setValidDigest(bytes32 digest, bool valid) external {
        validDigest[digest] = valid;
    }

    function setWrongMagic(bool value) external {
        wrongMagic = value;
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function isValidSignature(bytes32 digest, bytes calldata) external view returns (bytes4) {
        if (shouldRevert) revert("1271 revert");
        if (wrongMagic || !validDigest[digest]) return 0xffffffff;
        return MAGIC;
    }
}
