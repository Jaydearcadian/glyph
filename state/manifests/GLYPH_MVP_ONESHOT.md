# Glyph MVP `hy3:free` One-Shot Invocation Manifest

Status: **FROZEN FOR REVIEW — NOT EXECUTED**

## Authoritative Contract

```text
path:   docs/architecture/GLYPH_MVP_EXECUTION_CONTRACT.md
sha256: 74a88f873bc10451629aef536d5c757604607345d7418264faee119357fbe3a1
```

The executor must recompute and match this SHA-256 before reading implementation inputs or writing files. Any mismatch returns `BLOCKED_EXECUTION_CONTRACT_HASH` without modifying source.

## Intended Runtime

```text
executor count:       one
execution style:      direct sequential Hermes CLI process
model:                hy3:free
source tag:           glyph-mvp-hy3-oneshot
global config change: prohibited
delegation:           prohibited
filesystem checkpoint: required
working directory:    /root/monadglyph-hy3-oneshot
public side effects:  prohibited
```

The exact provider route for `hy3:free` must be read from live per-invocation model resolution before launch. Do not change the gateway/default model or global provider configuration. If `hy3:free` cannot be resolved exactly, stop before implementation.

## Input Snapshot

The isolated candidate must be prepared before invocation from:

```text
canonical specifications: /root/monadglyph
reviewed P1 candidate:    /root/monadglyph-p1-engineer
latest review evidence:   /root/monadglyph/state/reviews/p1-correctness-review3.json
latest review handoff:    /root/monadglyph/state/handoffs/p1-correctness-review3.json
```

Preparation rules:

- do not let the executor write canonical `/root/monadglyph`;
- do not copy `.env`, private keys, credentials, secrets, live deployment authority, build caches, or unrelated worktrees;
- record path-and-content SHA-256 for every imported P1 production/test file;
- preserve canonical governance/specification files read-only to the executor by instruction and hash verification;
- record canonical Git HEAD and dirty state;
- do not promote, commit, push, deploy, or broadcast during preparation.

## Allowed Toolsets

Intended minimal toolset:

```text
terminal,file,web,code_execution,todo,skills
```

No delegation, MoA, messaging, cron, MCP mutation, gateway control, memory mutation, or computer-use toolset is required.

Web access is for read-only verification of current official chain/messenger support and dependency documentation. Web evidence does not authorize deployment.

## Invocation Prompt

Pass the following self-contained instruction to the single `hy3:free` process:

```text
You are the sole sequential Glyph MVP implementation executor.

Work only in /root/monadglyph-hy3-oneshot.

Your immutable authority is:
- docs/architecture/GLYPH_MVP_EXECUTION_CONTRACT.md
- expected SHA-256 74a88f873bc10451629aef536d5c757604607345d7418264faee119357fbe3a1

First recompute that SHA-256. If it differs, stop with BLOCKED_EXECUTION_CONTRACT_HASH before writing source.

Read and obey the execution contract in full. It governs scope, architecture, security, TDD, phases, receipts, completion status, and prohibited actions. Do not edit the contract, this invocation manifest, or their checksum file.

You are one direct sequential executor. Do not invoke delegate_task, another model, another Hermes process, MoA, or subagents. Do not use gpt-5.6-sol. Do not change Hermes/global/project infrastructure configuration.

Use strict RED → GREEN → REFACTOR. Complete gates in the exact order defined by the execution contract. A failed prior gate blocks later gates. Repair within this one session until GREEN or return a truthful BLOCKED/FAILED handoff.

Do not deploy, sign, broadcast, fund, move assets, access private keys, commit, push, expose a service, or write outside the isolated workspace. Do not use --yolo. Do not claim Deployed or Live.

The canonical receipt JSON and deterministic human-readable SVG receipt card are mandatory. The application UI is excluded.

A real Base Sepolia → Monad Testnet adapter candidate may be called DEPLOY_READY only if current official lane support and configuration are verified from authoritative sources. Otherwise fully implement/test the messenger-neutral interface and adversarial mock and return BLOCKED_LANE_SUPPORT; do not invent support.

Required final artifact:
state/handoffs/glyph-mvp-hy3-oneshot.json

It must contain the contract hash, runtime model/source evidence, imported source fingerprints, exact commands and exit codes, RED/GREEN evidence, tests by suite, fuzz/invariant settings, receipt/card fixture hashes, final tree fingerprint, lane evidence or blocker, risks, and false/empty deployment/signing/funding/external-write fields. Validate it against the locked handoff schema or a compatible in-workspace extension.

Stop only at DEPLOY_READY, BLOCKED, or FAILED as defined by the execution contract.
```

## Intended CLI Shape

This is a reviewable shape, not authorization to execute:

```bash
cd /root/monadglyph-hy3-oneshot
hermes chat \
  --model 'hy3:free' \
  --toolsets 'terminal,file,web,code_execution,todo,skills' \
  --checkpoints \
  --source 'glyph-mvp-hy3-oneshot' \
  --query '<the exact invocation prompt above>'
```

Before launch, verify from actual CLI output that the process resolved exactly to `hy3:free`. If the CLI requires an explicit provider, add it per invocation only after discovery; do not edit global configuration.

## Parent Verification After Exit

No executor summary is accepted without direct verification of the returned candidate:

```text
execution-contract hash
input/import fingerprints
Git/workspace diff
Foundry effective config
format/build/full test results
focused/fuzz/invariant results
receipt schema and fixture verification
receipt card sourceReceiptHash verification
dangerous-pattern inspection
lane citations/configuration evidence
final tree fingerprint
handoff JSON-schema validation
no external side effects
```

Only after a GREEN frozen tree may one quota-limited `gpt-5.6-sol` strengthening review begin.

## Approval Boundaries

This manifest does not authorize:

- creation of the isolated workspace;
- starting the `hy3:free` process;
- installing dependencies;
- deployment or chain interaction;
- funding/signing/broadcast;
- committing/pushing;
- global Hermes/provider/tool/MCP/gateway changes.

Those actions retain their existing approval boundaries. The current approval covers writing and hashing this execution contract and invocation manifest for review only.
