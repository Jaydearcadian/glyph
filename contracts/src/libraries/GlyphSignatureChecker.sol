// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library GlyphSignatureChecker {
    bytes4 internal constant ERC1271_MAGICVALUE = 0x1626ba7e;
    uint256 internal constant SECP256K1N_DIV_2 = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    error InvalidSignature();
    error InvalidEIP1271Signature(address subject);

    function isContract(address account) internal view returns (bool) {
        return account.code.length != 0;
    }

    function requireValidSignature(address signer, bytes32 digest, bytes memory signature) internal view {
        if (isContract(signer)) {
            (bool ok, bytes memory data) =
                signer.staticcall(abi.encodeWithSelector(ERC1271_MAGICVALUE, digest, signature));
            if (!ok || data.length < 32 || bytes4(data) != ERC1271_MAGICVALUE) revert InvalidEIP1271Signature(signer);
            return;
        }
        if (signature.length != 65) revert InvalidSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        if (v != 27 && v != 28) revert InvalidSignature();
        if (uint256(s) == 0 || uint256(s) > SECP256K1N_DIV_2) revert InvalidSignature();
        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0) || recovered != signer) revert InvalidSignature();
    }
}
