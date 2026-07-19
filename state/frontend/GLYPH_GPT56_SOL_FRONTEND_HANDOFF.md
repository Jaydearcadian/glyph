# Glyph GPT-5.6 Sol frontend handoff

## Status

This is the exact handoff for a higher-tier frontend/design model. It is scoped to a fully interactive judge demo while preserving Glyph's proof boundaries.

## Role

Act as a senior frontend engineer, creative developer, product designer, and design systems architect.

Build a production-ready frontend for Glyph.

Glyph is a link-native settlement protocol for programmable payments. Users share simple payment, claim, campaign, payout/distribution, and receipt links while the protocol enforces exact terms, recovery, distribution, and verifiable terminal receipts onchain.

Judge-facing thesis:

> Payment links that end in proof.

Supporting product line:

> Glyph turns every payment link into a verifiable settlement record.

Product explanation:

> Glyph lets anyone create simple payment, claim, campaign, and payout links while the protocol enforces exact terms, recovery, distribution, and verifiable receipts onchain.

## Critical product decision

Cross-chain is NOT part of the interactive judge flow.

Cross-chain may appear only as previously-tested evidence/status boundary:

- source-send proven;
- destination settlement not claimed;
- no interactive cross-chain route/finalize flow;
- no fake Base→Monad completion.

## Tech stack

Use:

- Next.js
- TypeScript
- Tailwind CSS
- Framer Motion
- wagmi + viem for wallet/RPC
- Semantic HTML
- Reusable React components
- Accessible navigation and controls
- Responsive layouts
- Optimized local SVG/assets

## Existing source of truth

Use these repo artifacts. Do not invent API endpoints.

```text
FRONTEND_MANIFEST.md
state/frontend/frontend.manifest.json
state/frontend/contracts/glyphContracts.ts
state/frontend/contracts/glyphChains.ts
state/frontend/addresses/monad-testnet.json
state/frontend/abi/*.json
state/frontend/flows/*.flow.json
state/frontend/receipts/index.json
state/frontend/proofs/index.json
state/frontend/transactions/index.json
state/frontend/distributions/index.json
state/frontend/crosschain/base-monad.timeline.json
state/frontend/crosschain/CROSSCHAIN_UI_COPY.md
```

## Live test token

Use gTST for active judge tests.

```text
Name: Glyph Test Token
Symbol: gTST
Decimals: 18
Chain: Monad testnet
Token: 0x1d482783316FdeF2e795A1C193ACE280660A887a
```

The token exposes a public faucet-style method:

```solidity
mint(address to, uint256 amount)
```

Do not label live proof/demo token as USDC.

## Required routes

```text
/             Landing / overview
/links        Fully interactive Push/Pull link mode engine
/campaign     Interactive campaign creation/contribution/close where feasible + completed proof display
/distribution Interactive explicit-recipient splitter where feasible + live proof display
/receipts     Receipt gallery: JSON/card/link/QR
/proofs       Live proof dashboard; cross-chain only as tested evidence/boundary
```

## Design direction

Premium dark editorial interface.

Glyph should feel like:

```text
Stripe-grade payment UX
+ premium financial ledger
+ warm paper receipt artifacts
+ onchain proof infrastructure
+ link-native simplicity
```

Do not make it look like:

- meme coin app;
- generic DeFi dashboard;
- neon hacker terminal;
- purple-gradient crypto product;
- generic SaaS template;
- colorful chain abstraction website;
- glassmorphism-heavy landing page.

Desired feel:

> A black-card payment network for verifiable receipts.

## Palette

Use exactly:

```css
--black: #050505;
--near-black: #0A0A0B;
--charcoal: #121214;
--graphite: #1B1B1F;

--white: #FFFFFF;
--soft-white: #F5F5F0;
--receipt: #FFF7E6;

--text-primary: #F7F7F2;
--text-muted: #A1A1AA;
--text-subtle: #71717A;

--receipt-ink: #17130E;
--receipt-muted: #756A5C;

--border-gray: #2A2A2E;
--border-soft: rgba(255, 255, 255, 0.10);
--panel-soft: rgba(255, 255, 255, 0.045);

--proof-mint: #7CFFCB;
--receipt-gold: #D8B45A;
--pending-amber: #F5B94C;
--blocked-rose: #E85D75;
```

Use approximately:

- 90% black/white/receipt ivory;
- 7% gray structure;
- 3% semantic proof accents.

## Color semantics

Proof mint means:

- verified;
- live-proven;
- claimed;
- reconciled;
- checksum valid;
- receipt verified;
- settlement complete.

Receipt gold means:

- receipt seals;
- aggregate settlement receipts;
- distribution-complete state;
- receipt borders;
- proof signatures;
- final settlement marks.

Pending amber means:

- external dependency waiting;
- source-send proven but destination incomplete;
- pending proof/readback.

Blocked rose means only:

- forbidden action;
- invalid route;
- failed proof validation;
- impossible settlement state;
- explicit blocked boundary.

Do not use semantic colors as general decoration.

## Landing page first viewport

Desktop first viewport should include:

1. transparent top nav;
2. centered eyebrow;
3. large centered headline;
4. supporting copy;
5. primary CTA;
6. secondary understated action;
7. large lower-half editorial settlement illustration;
8. trust statement;
9. ecosystem logo row.

Hero copy:

```text
Eyebrow: LINK-NATIVE PAYMENT INFRASTRUCTURE
Headline: Payment links that end in proof.
Subhead: Glyph lets anyone create simple payment, claim, campaign, and payout links while the protocol enforces exact terms, recovery, distribution, and verifiable receipts onchain.
Primary CTA: Create a payment link
Secondary CTA: View verified receipts
Trust: Built for teams that need every payment to end in proof.
```

Hero illustration must show:

```text
payment link → route → settlement event → receipt artifact → verified proof seal
```

Use warm ivory receipt artifact as focal point.

## Full interactive judge test requirements

Judges must be able to actively test Glyph features on Monad testnet.

### Required active flow

```text
1. Connect wallet
2. Switch/add Monad testnet
3. Read gTST balance
4. Mint test gTST via TestToken.mint(address,uint256)
5. Approve router
6. Create Pull payment link escrow
7. Create Push claim link escrow / claim payload where supported
8. Wait for tx receipt
9. Read operation state after tx receipt
10. Show operationId, tx hash, explorer link, and readback fields
```

### Campaign active flow

Implement as much as contract/frontend prerequisites allow:

- create campaign;
- contribute/reconcile if user-safe inputs available;
- close if conditions met;
- otherwise clearly mark partial state and show completed proof bundle.

No fake aggregate settlement.

### Distribution active flow

Implement as much as contract/frontend prerequisites allow:

- read live proof distribution;
- display recipient splits and final totals;
- create distribution only if closed campaign/funded prerequisites can be satisfied from the UI;
- allow claim only if connected wallet is an eligible unclaimed recipient;
- otherwise mark proof-backed only.

No fake claims.

## Authority labels

Every action/card must label execution authority:

```text
User wallet action
Operator/proof action
Evidence-only
Blocked/pending external dependency
```

Fresh judge-created operations must not be shown as terminally settled unless the frontend actually reaches terminal state.

## Recommended component hierarchy

```text
app/layout.tsx
app/page.tsx
app/links/page.tsx
app/campaign/page.tsx
app/distribution/page.tsx
app/receipts/page.tsx
app/proofs/page.tsx

components/layout/Header.tsx
components/layout/MobileNavigation.tsx
components/layout/PageShell.tsx

components/landing/HeroSection.tsx
components/landing/LedgerBackground.tsx
components/landing/SettlementIllustration.tsx
components/landing/PaymentLinkArtifact.tsx
components/landing/ReceiptArtifact.tsx
components/landing/ProofSeal.tsx
components/landing/EcosystemLogoRow.tsx

components/wallet/WalletConnectButton.tsx
components/wallet/NetworkGate.tsx
components/wallet/FaucetCard.tsx
components/wallet/BalanceCard.tsx

components/links/LinkModeTabs.tsx
components/links/PullLinkBuilder.tsx
components/links/PushLinkBuilder.tsx
components/links/TermsPreview.tsx
components/links/OperationReadback.tsx

components/campaign/CampaignBuilder.tsx
components/campaign/CampaignProofPanel.tsx

components/distribution/DistributionProofPanel.tsx
components/distribution/RecipientSplitTable.tsx
components/distribution/DistributionClaimCard.tsx

components/receipts/ReceiptGallery.tsx
components/receipts/ReceiptCard.tsx
components/receipts/ReceiptJsonViewer.tsx

components/proofs/ProofDashboard.tsx
components/proofs/ProofTimeline.tsx
components/proofs/CrosschainEvidenceBoundary.tsx

components/status/StatusBadge.tsx
components/status/AuthorityBadge.tsx
components/status/ProofIndicator.tsx

lib/artifacts.ts
lib/contracts.ts
lib/chains.ts
lib/format.ts
lib/glyphActions.ts
lib/glyphReads.ts
```

## Required wallet/RPC action plan

Use wagmi + viem.

### Connect/switch

- configure Monad testnet chainId 10143;
- expose switch/add chain flow;
- block writes unless connected to Monad testnet.

### Faucet

Call:

```text
TestToken.mint(connectedAddress, parseUnits(amount, 18))
```

Default amount: `100 gTST`.

Wait for receipt, then read `balanceOf`.

### Approve

Call:

```text
TestToken.approve(router, amount)
```

Use router from `glyphContracts.monadCore.router` for Pull/Push demos unless a page intentionally uses campaign/distribution stack.

Wait for receipt, then read `allowance`.

### Pull escrow

Build `SourceDeltaRouter.Terms` from UI fields and safe defaults.

Call:

```text
SourceDeltaRouter.escrow(terms)
```

Before write, compute/read:

```text
actorNonce(address)
hashTerms(terms)
operationId(terms)
```

After write, wait for receipt and read:

```text
routeFacts(op)
sourceReceiptFacts(op)
```

Label fresh result: `Payment link created / escrowed`, not settled.

### Push escrow

Same as Pull but with Push mode terms. Generate local claim-link payload where supported by existing link schema. Keep fragment-only secret rule: never persist private claim secret.

Label fresh result: `Claim link funded / escrowed`, not claimed unless actual claim completes.

### Campaign

Use `ContributionCampaign` ABI. Support create/close if conditions can be met; use proof bundle for completed aggregation. Do not fake reconciliation.

### Distribution

Use `CampaignPayoutSplitter` ABI. Read:

```text
distributionTotals(distributionId)
recipientShare(distributionId, connectedAddress)
claimReceiptHash(distributionId, connectedAddress)
```

Allow:

```text
claim(distributionId)
```

only if recipientShare > 0 and unclaimed. Existing proof recipients are already claimed, so UI should likely show proof/readback unless using a fresh judge-created distribution.

## Judge-testable vs proof-backed matrix

Fully live-testable:

- connect wallet;
- switch Monad testnet;
- mint gTST;
- read balance/allowance;
- approve router;
- create Pull escrow;
- create Push escrow;
- generate link payload;
- read operation ids/facts;
- view receipts/proofs.

Partially interactive / proof-backed:

- campaign full lifecycle if user can satisfy inputs; otherwise completed proof bundle;
- distribution creation if prerequisites satisfied; otherwise completed proof bundle;
- distribution claim only when connected wallet is eligible unclaimed recipient.

Evidence-only:

- existing completed Push/Pull terminal lifecycle;
- existing campaign aggregation proof;
- existing 70/20/10 distribution proof;
- cross-chain source-send evidence/boundary.

Not allowed:

- fake settlement;
- hidden backend signer;
- indexer requirement;
- invented backend API;
- cross-chain interactive completion claim.

## Acceptance gates

Implementation must pass:

```bash
npm install
npm run lint
npm run typecheck
npm run build
```

Also run direct smoke checks:

- load `state/frontend/frontend.manifest.json`;
- load all ABIs;
- read live `name/symbol/decimals` from gTST;
- read `distributionTotals(distributionId)`;
- render all routes without JS errors;
- verify no horizontal overflow at 390, 768, 1024, 1280, 1440 widths;
- verify reduced-motion behavior;
- verify wallet writes wait for receipts before success state.

## Demo video outline after build confirmation

1. Open landing: "Payment links that end in proof."
2. Connect wallet and switch Monad testnet.
3. Mint 100 gTST.
4. Create a Pull payment link; show operationId and tx.
5. Create a Push claim link; show generated link payload and tx.
6. Open Campaign: show active path/proof bundle.
7. Open Distribution: show 20 gTST split, 14/4/2 claimed, totals readback.
8. Open Receipts: show JSON/card/link/QR.
9. Open Proofs: show live Monad proofs and cross-chain as tested evidence only.
10. Close with: "Every payment link ends in a receipt the chain can verify."
