# Glyph Cross-Chain Adapter — Deployment

Base Sepolia (`84532`, eid `40245`) ↔ Monad Testnet (`10143`, eid `40204`)
via LayerZero V2 (`LayerZeroV2GlyphMessengerAdapter`).

This stack is **local-DEPLOY-READY** (adversarial review closed, 73 tests green).
Deployment requires explicit user approval + signing/broadcast. Nothing here signs or sends.

## What gets deployed per chain
- `GlyphLayerZeroApplication` (SOURCE side on Base, DESTINATION side on Monad)
- `LayerZeroV2GlyphMessengerAdapter` (bound to the chain's verified LZ V2 endpoint)

It assumes the same-chain `SourceDeltaRouter` + `DestinationGlyphVault` are already
deployed (or you deploy them separately and put their addresses in the config).

## Wiring (mirrors the test harness exactly)
1. `app.setAdapter(adapter)`
2. `app.setRemoteApplication(remoteApp)`
3. `adapter.setLocalApplication(app)`
4. `adapter.setRemoteApplication(remoteApp)`
5. `adapter.setTrustedPeer(remoteAdapter)`
6. `adapter.setEnforcedGasLimit` / `setOrderedExecution`
7. `router.setMessengerAdapter(adapter, true)`
8. `router.setMessengerProcessorForAdapter(app, adapter, true)`
9. `vault.setAuthorizedApplication(app, true)`
10. `app.freezeConfig(policy)` + `adapter.freezeConfig(policy)` → config locked

## Config (no secrets)
Edit `glyph.deploy.config.json`: fill `router`, `vault`, `owner`, and the
`messengerPolicyHash` (external security commitment, e.g. the ULN/oracle config hash).
Leave placeholder zeros until you have real addresses.

## Dry run (compile + simulate, NO broadcast)
```bash
cd contracts
forge script script/GlyphDeploy.s.sol --tc GlyphDeploy --sig "run()" -vv
```

## Broadcast (requires approval + funded key)
```bash
# Base Sepolia
forge script script/GlyphDeploy.s.sol --tc GlyphDeploy --sig "run()" \
  --rpc-url $BASE_SEPOLIA_RPC --account <your-account> --broadcast --verify

# Monad Testnet (after Base, so remote addresses resolve)
forge script script/GlyphDeploy.s.sol --tc GlyphDeploy --sig "run()" \
  --rpc-url $MONAD_TESTNET_RPC --account <your-account> --broadcast --verify
```

## Post-deploy verification (readback, no value movement)
- `cast call <adapter> computedPolicyHash(bytes32) <externalCommitment>`
- `cast call <adapter> configFrozen()  -> true`
- `cast call <app> configFrozen()      -> true`
- Run one Pull lifecycle end-to-end and read back the source terminal receipt.

## Status
- Local gate: PASS (73 tests, invariants 256×128k calls, 0 reverts).
- Public/live: NOT until on-chain E2E receipts are read back on both chains.
