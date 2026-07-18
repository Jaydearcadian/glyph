# Receipt and Identity Privacy

Status: P0 policy.

## Public-by-Default Reality

Monad contract storage, events, calldata, transaction traces, and deployment configuration are public and effectively permanent. Hashes may still be identifying if the input space is small or the preimage is later disclosed.

## Prohibited On-Chain Data

Do not publish:

- legal/personal names unless deliberately public and separately justified;
- email, phone, postal address;
- tax/government identifiers;
- bank/account numbers;
- private customer or invoice IDs;
- complete invoice/bill text;
- health, employment, or sensitive service details;
- unencrypted private document URLs;
- link-fragment claim secrets;
- credentials or private keys.

## Allowed Anchors

- wallet addresses and chain IDs;
- typed identity namespace;
- claim/attestation IDs;
- salted commitments with adequate entropy;
- issuer address and proof reference;
- deliberately public identity references;
- encrypted/content commitments where access is controlled off-chain;
- generic purpose codes selected with informed consent.

## Identity Consent

Identity is not automatically attached to every receipt. Payer and recipient independently select which claim, if any, to bind. Relayers submit only signed content.

## Minimization

Store the minimum needed to prove:

- which claim version was selected;
- who asserted/issued it;
- its verification level/status at binding;
- the commitment/reference needed for verification.

Do not mirror full identity documents.

## Context Documents

If bills/invoices are supported, the receipt stores a canonical hash. The document should be encrypted or held by the parties/provider under an access policy. A public IPFS CID is public, not private.

## Revocation and Erasure

On-chain data cannot be erased. Revocation is append-only. UI must show revoked/superseded status without hiding historical existence. Product copy must not promise deletion of on-chain claims.

## Analytics and Link Handling

Fragment material is stripped before analytics initialize. Logs use operation IDs and public state only. Crash reports, support screenshots, link previews, and referrer headers must not contain claim secrets or private context.

## Threat Tests

P1/P6 tests must cover unauthorized identity binding, signature replay, low-entropy context commitment warnings/SDK behavior, fragment removal before network activity, and no sensitive values in events/manifests.
