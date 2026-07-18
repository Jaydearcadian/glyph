// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Adversarial EIP-1271 mock that can return short, wrong-length, wrong-magic, or reverting
// data so the signature checker's `data.length < 32` and `bytes4(data) != MAGIC` branches are
// exercised. This is a TEST helper only and is never linked into production contracts.
contract MockEIP1271Malformed {
    bytes4 constant MAGIC = 0x1626ba7e;

    enum Mode {
        OK,
        SHORT,
        WRONG32,
        REVERT
    }

    Mode public mode;

    function setMode(Mode m) external {
        mode = m;
    }

    function isValidSignature(bytes32, bytes calldata) external view returns (bytes4) {
        if (mode == Mode.REVERT) revert("malformed-1271");
        if (mode == Mode.SHORT) {
            // Return 4 bytes only -> data.length < 32 in the staticcall reader.
            assembly {
                mstore(0x00, 0x12345678)
                return(0x00, 4)
            }
        }
        if (mode == Mode.WRONG32) {
            // 32-byte padded but not the magic value.
            return bytes4(0xdeadbeef);
        }
        return MAGIC;
    }
}
