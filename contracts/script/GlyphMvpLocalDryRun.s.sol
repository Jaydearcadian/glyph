// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {SourceDeltaRouter} from "../src/SourceDeltaRouter.sol";
import {DestinationGlyphVault} from "../src/DestinationGlyphVault.sol";
import {MockGlyphMessengerAdapter} from "../src/MockGlyphMessengerAdapter.sol";
import {ContributionCampaign} from "../src/ContributionCampaign.sol";
import {GiftPool} from "../src/GiftPool.sol";

// Local dry-run constructor script only. No broadcast, no private keys, no deployment authorization.
contract GlyphMvpLocalDryRunScript is Script {
    function run()
        external
        returns (
            SourceDeltaRouter router,
            DestinationGlyphVault vault,
            MockGlyphMessengerAdapter messenger,
            ContributionCampaign campaign,
            GiftPool gift
        )
    {
        router = new SourceDeltaRouter();
        vault = new DestinationGlyphVault();
        messenger = new MockGlyphMessengerAdapter();
        campaign = new ContributionCampaign();
        gift = new GiftPool();
    }
}
