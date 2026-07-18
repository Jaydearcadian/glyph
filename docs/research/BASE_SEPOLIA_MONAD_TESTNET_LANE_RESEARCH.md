# Base Sepolia -> Monad Testnet authenticated messaging lane research

Retrieval time (UTC): 2026-07-18T10:43:37Z

Scope: research only. No adapter implementation, deployment, signing, broadcast, funding, private-key access, service exposure, Hermes configuration change, manifest/checksum-lock change, or infrastructure change was performed.

Locked lane under review:

```text
source:      Base Sepolia, chainId 84532
destination: Monad Testnet, chainId 10143
semantics:  authenticated arbitrary/application messaging usable behind IGlyphMessengerAdapter; source-finalization requires authenticated destination-delivery acknowledgement and replay-safe message identity.
```

Baseline files read before research:

- `AGENTS.md`
- `docs/architecture/GLYPH_MVP_EXECUTION_CONTRACT.md`
- `docs/architecture/CROSSCHAIN_DELTA.md`
- `docs/architecture/MESSAGE_SCHEMA.md`
- `contracts/src/interfaces/IGlyphMessengerAdapter.sol`
- `state/handoffs/glyph-mvp-hy3-oneshot.json`
- `state/adapter/base-sepolia-monad-testnet.adapter.template.json`

Frozen baseline hashes recomputed before work:

```text
74a88f873bc10451629aef536d5c757604607345d7418264faee119357fbe3a1  docs/architecture/GLYPH_MVP_EXECUTION_CONTRACT.md
07e33cc7ba3055d4c68e6017587539a9e4b9b527831e865769cbebdfb0b3e286  docs/architecture/CROSSCHAIN_DELTA.md
f543bb9c21f4b2d000ae9034c0da68a4881433204540bbd26575ca1cd7b85e08  docs/architecture/MESSAGE_SCHEMA.md
05061ad1f1aad001a7073cd60ffd540c459bb1b33a678ab457792314c3ca080f  contracts/src/interfaces/IGlyphMessengerAdapter.sol
```

## Executive verdict

Exact-lane verdict: VERIFIED_SUPPORTED, with LayerZero V2 as the recommended adapter candidate.

Why: LayerZero's official metadata API currently publishes active V2 deployments for both exact endpoints:

- Base Sepolia: native chain ID 84532, V2 EID 40245, EndpointV2 `0x6EDCE65403992e310A62460808c4b910D972f10f`.
- Monad Testnet: native chain ID 10143, V2 EID 40204, EndpointV2 `0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff`.

LayerZero's official architecture documentation describes arbitrary cross-chain OApp messaging, Endpoint send/receive, GUIDs, nonces, configurable verification, and executor delivery. This matches the adapter isolation model: the Glyph adapter can authenticate inbound messages from trusted endpoint/origin/peer context, map LayerZero GUIDs/nonces to `messageId`, and classify proof as `AUTHENTICATED_ADAPTER` (not light-client verification).

Chainlink CCIP also has official current evidence of the exact Base Sepolia -> Monad Testnet testnet lane, including routers, chain selectors, and lane onRamp/offRamp addresses. However, Chainlink's currently visible testnet directory evidence did not show the reverse Monad Testnet -> Base Sepolia lane needed for a pure CCIP round-trip acknowledgement path. Therefore CCIP is a strong secondary/outbound candidate but not the recommended first Glyph source-finalization adapter unless the reverse acknowledgement lane or another accepted acknowledgement design is verified.

Hyperlane publishes both chains in its official registry, but Monad Testnet is explicitly disabled/deprecated there, so it is not a fail-closed production-lane candidate.

Wormhole, Axelar, deBridge, LI.FI, and Relay did not provide authoritative exact-lane support for authenticated arbitrary messaging on Base Sepolia -> Monad Testnet. LI.FI and Relay are primarily liquidity/solver/token-routing APIs rather than authenticated arbitrary-message protocols for this adapter requirement.

Recommended next gate: implement a LayerZero V2 adapter candidate behind `IGlyphMessengerAdapter` in a future code phase, with local tests first and public testnet proof only after explicit deployment/signing approval. Keep `BLOCKED_LANE_SUPPORT` cleared only for LayerZero V2 adapter-gate planning; do not mark deployed/live.

## Adapter authentication requirements from locked Glyph specs

The adapter must satisfy these requirements from the read architecture files:

- `IGlyphMessengerAdapter.Envelope` binds `messageVersion`, `messageType`, `messageId`, `operationId`, `termsHash`, source/destination chain IDs, source/destination applications, `routeNonce`, and `payloadHash`.
- Receivers must validate source domain/application from trusted adapter context, not from payload claims alone.
- Duplicate/replayed message IDs and duplicate `(operationId, messageType, routeNonce)` effects must fail closed.
- Unknown versions/types fail closed.
- Source finalization may settle only after authenticated destination-delivery evidence; refund must be forbidden once authenticated delivery evidence exists.
- Adapter attestations must be labeled `AUTHENTICATED_ADAPTER`, not `LIGHT_CLIENT_VERIFIED`.

## Evidence matrix

| Provider | Exact endpoint status | Exact lane status | Official identifiers / addresses | Verdict | Adapter suitability |
|---|---|---|---|---|---|
| LayerZero V2 | Base Sepolia and Monad Testnet both officially active in metadata | Supported by V2 endpoint/OApp model; direction-neutral configuration required | Base Sepolia chainId 84532, EID 40245, EndpointV2 `0x6EDCE65403992e310A62460808c4b910D972f10f`; Monad Testnet chainId 10143, EID 40204, EndpointV2 `0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff` | VERIFIED_SUPPORTED | Best candidate. Requires OApp peer/config setup and tests for GUID/nonce/replay/domain validation. |
| Hyperlane | Both endpoints listed, but Monad Testnet disabled/deprecated | Fail-closed unsupported because destination chain registry says disabled | Base Sepolia domainId 84532 mailbox `0x6966b0E55883d49BFB24539356a2f8A673E02039`; Monad Testnet domainId 10143 mailbox `0x589C201a07c26b4725A4A829d772f24423da480B`, `availability.status: disabled`, `reasons: [deprecated]` | VERIFIED_UNSUPPORTED | Not acceptable until official registry re-enables Monad Testnet and relayer/ISM path is verified. |
| Wormhole | Base Sepolia present in official SDK constants; Monad Testnet not present in checked official constants | No exact endpoint pair | Wormhole chain IDs include `base_sepolia: 10004`; no Monad/10143 entry found in checked constants | VERIFIED_UNSUPPORTED | No exact lane. |
| Axelar | Official contract-address pages checked; neither Base Sepolia nor Monad Testnet present | No exact endpoint pair | No gateway/gas-service entries for Base Sepolia or Monad Testnet in checked pages | VERIFIED_UNSUPPORTED | No exact lane. |
| Chainlink CCIP | Both exact chains present in official testnet directory | Base Sepolia -> Monad Testnet lane officially listed; reverse Monad -> Base not found in visible directory | Base Sepolia router `0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93`, selector `10344971235874465080`; Monad Testnet router `0x5aD0A67f4Da0E8665a3fbf15E4215A780407Cf33`, selector `2183018362218727504`; exact lane onRamp `0x28A025d34c830BF212f5D2357C8DcAB32dD92A20`, offRamp `0xF4EbCC2c077d3939434C7Ab0572660c5A45e4df5`, version 1.6.0 | INCONCLUSIVE for full Glyph source-finalization semantics; VERIFIED_SUPPORTED for one-way outbound lane only | Authenticated arbitrary message candidate, but do not select until reverse acknowledgement or accepted alternate source-finalization evidence is verified. |
| deBridge / DLN | Official API does not list Base Sepolia or Monad Testnet | No exact endpoint pair | `supported-chains-info` lists mainnets such as Ethereum, Optimism, BSC, Polygon, Base mainnet, etc.; no 84532 or 10143 | VERIFIED_UNSUPPORTED | DLN is solver/liquidity order infrastructure, not a verified arbitrary-message adapter lane here. |
| LI.FI | Official API lists Base Sepolia testnet and Monad mainnet, not Monad Testnet | No exact endpoint pair | Base Sepolia id 84532 listed; Monad id 143 listed; no Monad Testnet id 10143 | VERIFIED_UNSUPPORTED | Token/liquidity aggregation, not authenticated arbitrary messaging for Glyph. |
| Relay | Official API lists Monad mainnet, not Base Sepolia or Monad Testnet | No exact endpoint pair | Monad id 143 listed; no 84532 or 10143 | VERIFIED_UNSUPPORTED | Solver/liquidity routing, not arbitrary message authentication. |

## Provider notes and quoted official evidence

### LayerZero V2 — VERIFIED_SUPPORTED

Official sources checked:

- `https://docs.layerzero.network/v2/deployments/chains/base-sepolia.md`
- `https://docs.layerzero.network/v2/deployments/chains/monad-testnet.md`
- `https://docs.layerzero.network/v2/deployments/deployed-contracts.md`
- `https://metadata.layerzero-api.com/v1/metadata/deployments`
- `https://docs.layerzero.network/v2/concepts/layerzero-protocol-architecture.md`

Quoted evidence:

- Base Sepolia docs title/description: `# Base Sepolia Testnet` and `LayerZero V2 deployment addresses and configuration for Base Sepolia. Find Endpoint, DVN, and Executor contract addresses for integration.`
- Monad Testnet docs title/description: `# Monad Testnet` and `LayerZero V2 deployment addresses and configuration for Monad. Find Endpoint, DVN, and Executor contract addresses for integration.`
- LayerZero architecture: `LayerZero is an omnichain interoperability protocol that provides a stable, immutable interface for crosschain messaging.`
- LayerZero OApp architecture: applications can `define any custom data as bytes and send them as crosschain messages`.
- LayerZero Endpoint architecture: `The LayerZero Endpoint serves as the single entrypoint and exitpoint for all crosschain messaging on a blockchain.`
- LayerZero receipt fields: `MessagingReceipt { bytes32 guid; uint64 nonce; MessagingFee fee; }`.

Official metadata readback:

```json
Base Sepolia V2:
{
  "chainKey": "base-sepolia",
  "nativeChainId": 84532,
  "chainStatus": "ACTIVE",
  "version": 2,
  "eid": "40245",
  "stage": "testnet",
  "endpointV2": "0x6EDCE65403992e310A62460808c4b910D972f10f",
  "endpointV2View": "0xf49d162484290EaEaD7BbC2c7E3a6F8f52E32d6",
  "sendUln302": "0xC1868e054425D378095A003EcbA3823a5D0135C9",
  "receiveUln302": "0x12523DE19Dc41c91f7D2093E0CFbB76b17012C8d",
  "executor": "0x8A3D588d9F6AC041476b094F97fF94ec30169d3D"
}
```

```json
Monad Testnet V2:
{
  "chainKey": "monad-testnet",
  "nativeChainId": 10143,
  "chainStatus": "ACTIVE",
  "version": 2,
  "eid": "40204",
  "stage": "testnet",
  "endpointV2": "0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff",
  "endpointV2View": "0x145c041566b21bEC558b2a37f1A5fF261Ab55998",
  "sendUln302": "0xD682ECF100f6F4284138AA925348633B0611Ae21",
  "receiveUln302": "0xcf1B0F4106B0324f96fEFCc31bA9498caa80701C",
  "executor": "0x9dB9Ca3305B48F196D18082e91cB64663b13d014"
}
```

Authentication model:

LayerZero authenticates OApp messages through configured send/receive libraries and DVNs, then executes delivery through the Endpoint/executor path. For Glyph, the adapter must still enforce the application-level trust boundary: expected LayerZero endpoint, expected `Origin.srcEid`, expected peer/source application, expected destination application, expected message schema version/type, and consumed GUID/message ID.

Finality assumptions:

LayerZero finality is adapter-configuration dependent: DVN confirmations/finality and executor options must be explicitly configured and recorded in the adapter policy. The Glyph receipt must label this as `AUTHENTICATED_ADAPTER`; it is not a light-client proof.

Replay/message-ID guarantees:

LayerZero V2 exposes a globally unique `guid` and a `nonce` in the messaging receipt. The Glyph adapter should map `guid` or a domain-separated hash of `(srcEid, dstEid, nonce, sender, receiver, payloadHash)` to `IGlyphMessengerAdapter.Envelope.messageId` and also enforce `(operationId, messageType, routeNonce)` one-time consumption.

Liquidity/provider dependencies:

LayerZero transports messages only; it does not provide destination liquidity. Glyph still requires its own provider-prefunded destination liquidity and STN-Delta accounting.

Implementation/test requirements before any public deployment:

1. Add a LayerZero V2 adapter contract only after opening a separate implementation phase.
2. Constructor/config must bind endpoint, local chainId/EID, remote chainId/EID, remote peer app, proof kind `AUTHENTICATED_ADAPTER`, and message version.
3. Inbound `_lzReceive` must fail closed unless endpoint/origin/source peer/destination app/schema all match.
4. Map LayerZero `guid` to Glyph `messageId` and store consumed message IDs.
5. Add adversarial tests for wrong endpoint, wrong `srcEid`, wrong peer, wrong destination app, duplicate GUID, duplicate `(operationId,type,routeNonce)`, wrong version/type, mutated payload hash, unordered acknowledgement, and delayed destination-delivery ack.
6. Add a no-secrets config template with Base Sepolia EID 40245 and Monad Testnet EID 40204.
7. Do not deploy/sign/broadcast until explicit user approval.

### Hyperlane — VERIFIED_UNSUPPORTED

Official sources checked:

- `https://docs.hyperlane.xyz/docs/protocol/protocol-overview.md`
- `https://raw.githubusercontent.com/hyperlane-xyz/hyperlane-registry/main/chains/basesepolia/metadata.yaml`
- `https://raw.githubusercontent.com/hyperlane-xyz/hyperlane-registry/main/chains/basesepolia/addresses.yaml`
- `https://raw.githubusercontent.com/hyperlane-xyz/hyperlane-registry/main/chains/monadtestnet/metadata.yaml`
- `https://raw.githubusercontent.com/hyperlane-xyz/hyperlane-registry/main/chains/monadtestnet/addresses.yaml`

Quoted evidence:

- Protocol capability: `Hyperlane is the first permissionless interoperability layer that allows smart contract developers to send arbitrary data between blockchains.`
- Mailbox model: users interface with `Mailbox smart contracts`, and destination processing calls `verify(metadata, message)` on an `InterchainSecurityModule` before `handle(origin, sender, body)`.
- Base Sepolia registry: `chainId: 84532`, `domainId: 84532`, `displayName: Base Sepolia`, `mailbox: "0x6966b0E55883d49BFB24539356a2f8A673E02039"`.
- Monad Testnet registry: `availability: reasons: [deprecated] status: disabled`, `chainId: 10143`, `domainId: 10143`, `displayName: Monad Testnet`, `mailbox: "0x589C201a07c26b4725A4A829d772f24423da480B"`.

Authentication model:

Hyperlane uses Mailbox dispatch/process and application-selected ISMs. It could satisfy Glyph in principle if both chains were available and if an ISM/relayer path were configured, but official registry disabled status for Monad Testnet is fail-closed.

Verdict reason:

Even though both metadata/addresses files exist, the destination endpoint is explicitly disabled/deprecated. A locked production-lane adapter must not infer usability from stale addresses.

### Wormhole — VERIFIED_UNSUPPORTED

Official source checked:

- `https://raw.githubusercontent.com/wormhole-foundation/wormhole/main/sdk/js/src/utils/consts.ts`

Quoted evidence:

- Wormhole constants include `base_sepolia: 10004` in testnet chain IDs.
- The checked official constants list EVM chain names including `base_sepolia`, `arbitrum_sepolia`, `optimism_sepolia`, `holesky`, and `polygon_sepolia`, but no `monad` or `monad_testnet` entry.

Authentication model:

Wormhole arbitrary messaging is VAA/guardian-attested. It may be adapter-suitable where both endpoints exist, but the exact Monad Testnet endpoint was not present in the checked official constants.

Verdict reason:

No official exact Monad Testnet support evidence was obtained. Do not infer support from any mainnet or third-party list.

### Axelar — VERIFIED_UNSUPPORTED

Official sources checked:

- `https://docs.axelar.dev/dev/reference/testnet-contract-addresses/`
- `https://docs.axelar.dev/dev/reference/mainnet-contract-addresses/`

Quoted evidence:

- The official testnet and mainnet contract-address pages were fetched successfully and contain Axelar gateway/gas-service contract data, but searches for `Monad`, `Base Sepolia`, `10143`, and `84532` returned no matches in the fetched pages.

Authentication model:

Axelar GMP can authenticate contract calls through the Axelar Gateway where supported. No exact endpoint pair was found.

Verdict reason:

No official exact Base Sepolia or Monad Testnet deployment evidence was obtained.

### Chainlink CCIP — INCONCLUSIVE for full Glyph source-finalization semantics; one-way exact lane verified

Official sources checked:

- `https://docs.chain.link/ccip/directory/testnet`
- `https://docs.chain.link/ccip/directory/testnet/chain/ethereum-testnet-sepolia-base-1`
- `https://docs.chain.link/ccip/directory/testnet/chain/monad-testnet`
- `https://docs.chain.link/ccip/concepts/cross-chain-message` (HTML path available through docs site navigation; `.md` extraction path returned 404)

Quoted evidence:

- Testnet directory describes `Base Sepolia CCIP Network Data` with `supported tokens and active lanes`.
- Testnet directory describes `Monad Testnet CCIP Network Data` with `supported tokens and active lanes`.
- Base Sepolia page metadata: `CCIP configuration for Base Sepolia on Testnet. View 5 supported tokens, active cross-chain lanes, fees, and technical specifications.`
- Monad Testnet page metadata: `CCIP configuration for Monad Testnet on Testnet. View 2 supported tokens, active cross-chain lanes, fees, and technical specifications.`
- Base Sepolia chain data: `router` address `0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93`, `chainSelector` `10344971235874465080`.
- Monad Testnet chain data: `router` address `0x5aD0A67f4Da0E8665a3fbf15E4215A780407Cf33`, `chainSelector` `2183018362218727504`.
- Exact lane data on Base Sepolia page: source `Base Sepolia`, destination `Monad Testnet`, `offRamp` address `0xF4EbCC2c077d3939434C7Ab0572660c5A45e4df5`, version `1.6.0`; `onRamp` address `0x28A025d34c830BF212f5D2357C8DcAB32dD92A20`, `enforceOutOfOrder: false`, version `1.6.0`.

Authentication model:

CCIP provides authenticated cross-chain message routing through Chainlink CCIP routers/onramps/offramps and a `CCIPReceiver`-style destination contract model. It supports arbitrary data messages in addition to token transfers, but lane support is directional.

Finality assumptions:

CCIP security/finality depends on Chainlink CCIP lane configuration and Risk Management Network/commit/execution flow. The adapter would classify evidence as `AUTHENTICATED_ADAPTER`, not light-client verification.

Replay/message-ID guarantees:

A CCIP adapter should map CCIP message IDs to `Envelope.messageId`, and still enforce Glyph semantic replay protections. The fetched directory evidence exposes lane/router/onRamp/offRamp addresses but not enough implementation detail to finalize exact adapter code in this research-only phase.

Verdict reason:

The one-way exact outbound lane Base Sepolia -> Monad Testnet is verified. But source finalization requires an authenticated Monad -> Base acknowledgement route, and the visible Monad Testnet lane list did not show Base Sepolia as a destination among current Monad outbound lanes. Use CCIP only if a reverse lane is later verified or the locked semantics accept a different authenticated acknowledgement path.

### deBridge / DLN — VERIFIED_UNSUPPORTED

Official source checked:

- `https://dln.debridge.finance/v1.0/supported-chains-info`

Quoted evidence:

The fetched official API returned chains including Ethereum, Optimism, BSC, Polygon, Robinhood, Base mainnet, Arbitrum, Avalanche, Linea, Solana, Story, Cronos, HyperEVM, Tron, Sei, Injective, etc., but no `84532` and no `10143`.

Authentication/liquidity distinction:

deBridge/DLN is an intent/order and liquidity network. It is not accepted as an authenticated arbitrary-message adapter for the locked Glyph semantics without exact chain support and a destination-authentication contract model.

### LI.FI — VERIFIED_UNSUPPORTED

Official source checked:

- `https://li.quest/v1/chains`

Quoted evidence:

- Base Sepolia Testnet is listed with `id: 84532`, `key: bast`, `mainnet: false`, `relayerSupported: false`.
- Monad is listed with `id: 143`, `key: mon`, `mainnet: true`.
- No Monad Testnet `id: 10143` entry was found.

Authentication/liquidity distinction:

LI.FI is a token/liquidity route aggregation API. It is not a verified authenticated arbitrary-message transport for Glyph and lacks exact Monad Testnet support in the checked official API.

### Relay — VERIFIED_UNSUPPORTED

Official source checked:

- `https://api.relay.link/chains`

Quoted evidence:

- Relay API lists Monad mainnet `id: 143`.
- The checked API returned no `id: 84532` and no `id: 10143`.

Authentication/liquidity distinction:

Relay is a solver/liquidity bridge/route API. It does not satisfy the locked `IGlyphMessengerAdapter` authenticated arbitrary-message requirement for the exact testnet lane.

## Recommendation

Implement LayerZero V2 first in a later implementation phase, not in this research commit.

Minimum next implementation gate:

1. Create `LayerZeroV2GlyphMessengerAdapter` behind the existing `IGlyphMessengerAdapter`.
2. Bind exact config:
   - Base Sepolia chainId 84532, EID 40245, EndpointV2 `0x6EDCE65403992e310A62460808c4b910D972f10f`.
   - Monad Testnet chainId 10143, EID 40204, EndpointV2 `0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff`.
3. Configure bidirectional peers for route instruction and destination acknowledgement.
4. Keep destination liquidity/provider selection in Glyph contracts; do not depend on bridge liquidity.
5. Label proof kind `AUTHENTICATED_ADAPTER`.
6. Add fail-closed tests for every adapter context and replay failure listed above.
7. Only after tests pass, ask for explicit approval before any testnet deployment/signing/broadcast.

If LayerZero public testnet send/receive cannot be executed later due endpoint, DVN, executor, fee, or peer-configuration failure, fall back to `BLOCKED_LANE_SUPPORT` with the exact runtime receipt/error, not to a mock-labeled-public proof.

## Explicit unknowns

- LayerZero V2 current endpoint support is verified from official metadata, but no live public send/receive transaction was performed in this research-only phase.
- LayerZero OApp-specific DVN confirmation counts, executor gas limits, enforced options, and peer wiring must be selected and tested during implementation.
- Chainlink CCIP exact outbound lane is verified, but reverse Monad Testnet -> Base Sepolia acknowledgement support was not found in the visible directory evidence.
- No private/provider-specific support channels were queried.
- No chain readback through RPC was used for deployment-code verification; official registries/APIs/docs were the authority for this research artifact.
