// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console2} from "forge-std/Script.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {TestToken} from "../src/TestToken.sol";

contract MonadRead is Script {
    function run() external view {
        SourceDeltaRouter router = SourceDeltaRouter(0xC71C119B91Fa1F1861626843Fa653F41cEF9101A);
        TestToken token = TestToken(0x1d482783316FdeF2e795A1C193ACE280660A887a);
        address owner = 0x014eb22ab7DFa9A843Babc1C6e2dA5B596a62f36;
        console2.log("actorNonce(owner):", router.actorNonce(owner), "(1 = escrow recorded on-chain)");
        console2.log("owner gTST:", token.balanceOf(owner) / 1e18, "(890 = 110 escrowed live)");
        console2.log("router gTST:", token.balanceOf(address(router)) / 1e18, "(should include 110 escrowed)");
    }
}
