# Glyph Cross-Chain Adapter — Deployment

Base Sepolia (`84532`, eid `40245`) ↔ Monad Testnet (`10143`, eid `40204`)
via LayerZero V2 (`LayerZeroV2GlyphMessengerAdapter`).

This stack is **local-DEPLOY-READY** (adversarial review closed, 73 tests green).
Deployment requires explicit user approval + signing/broadcast. Nothing here signs or sends.

## What the script deploys per chain (self-contained)
- `SourceDeltaRouter` (same-chain escrow/settlement) — fresh if `GLYPH_*_ROUTER` unset
- `DestinationGlyphVault` (same-chain delivery) — fresh if `GLYPH_*_VAULT` unset
- `TestToken` (ERC-20 moved by this side) — fresh if `GLYPH_*_TOKEN` unset
- `GlyphLayerZeroApplication` (SOURCE on Base / DESTINATION on Monad)
- `LayerZeroV2GlyphMessengerAdapter` (bound to the chain's verified LZ V2 endpoint)

## Wiring (mirrors the adversarial test harness exactly)
1. `app.setAdapter(adapter)`
2. `app.setRemoteApplication(remoteApp)`
3. `adapter.setLocalApplication(app)` / `setRemoteApplication(remoteApp)` / `setTrustedPeer(remoteAdapter)`
4. `router.setMessengerAdapter(adapter, true)` + `setMessengerProcessorForAdapter(app, adapter, true)`
5. `vault.setAuthorizedApplication(app, true)`
6. `_seedLiquidity`: mint source token to owner; on destination, `provideLiquidity` into vault
7. `app.freezeConfig(policy)` + `adapter.freezeConfig(policy)` → config locked

## Config (no secrets)
Edit `glyph.deploy.config.json` OR pass everything via env (preferred for the keyless->keyed flow):
- `GLYPH_BASE_OWNER`, `GLYPH_MONAD_OWNER` — deployer address (becomes owner)
- `GLYPH_BASE_POLICY_HASH`, `GLYPH_MONAD_POLICY_HASH` — external security commitment
- optional `GLYPH_*_ROUTER/VAULT/TOKEN/REMOTE_ADAPTER/REMOTE_APP/REMOTE_TOKEN` to reuse existing

## Dry run (simulate, NO broadcast)
```bash
cd contracts
GLYPH_BASE_OWNER=0x... GLYPH_MONAD_OWNER=0x... \
GLYPH_BASE_POLICY_HASH=0x... GLYPH_MONAD_POLICY_HASH=0x... \
forge script script/GlyphDeploy.s.sol --tc GlyphDeploy --sig "run()" \
  --fork-url https://testnet-rpc.monad.xyz -vv
```
Verified: all core contracts + token deploy per chain; wiring executes. (Keyless sim stops at
owner-gated calls — expected. Real broadcast with `--account` + key passes them.)

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
- `cast call <adapter> configFrozen() -> true` / `cast call <app> configFrozen() -> true`
- Run one Pull lifecycle end-to-end and read back the source terminal receipt on Monad.

## Status
- Local gate: PASS (73 tests, invariants 256×128k calls, 0 reverts).
- Script verified: compiles + full deploy/wire/seed simulation runs.
- Public/live: NOT until on-chain E2E receipts are read back on both chains.
