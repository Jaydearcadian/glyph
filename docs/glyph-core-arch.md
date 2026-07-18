# Glyph Core Architecture — Legacy EIP-7702 Prototype

> **SUPERSEDED / DEPRECATED:** This document describes the retired Vessel/Session prototype, not the active Push/Pull, STN-Delta, receipt-ledger architecture. Its ERC-7201 slot `0x07d2...3700` was derived with NIST SHA3 and is incorrect for Ethereum Keccak. The verified slot from `cast index-erc7201 glyph.storage.session.v1` is `0xe41f22272467a59d9f0c5cddde07c168cf1192ad3a1536e2283f6fbda6e9a300`. Do not use the deployed proxy or this document as an implementation foundation. Read `../AGENTS.md`, `PRODUCT_DOCTRINE.md`, and `architecture/INVARIANTS.md`.

Status: **HISTORICAL ARTIFACT — NOT ACTIVE ARCHITECTURE**.

## 1. Monad Parallel Execution (OCC) Strategy
Monad runs Optimistic Concurrency Control: parallel lanes, rolled back on storage-slot
conflict. To maximize throughput, Glyph avoids anything that serializes:

| Vector | Anti-pattern (sequential) | Glyph pattern (parallel) |
|---|---|---|
| Vessel registry | `Vessel[] public allVessels` | `mapping(bytes32 => Vessel) vessels` |
| Metrics | `uint256 totalVolumeEscrowed` | event logs + off-chain indexer |
| IDs | `uint256 nextVesselId++` | `keccak256(abi.encodePacked(msg.sender, salt))` (off-chain) |

## 2. Deterministic ID Generation
V_id = keccak256( abi.encodePacked( A_creator, N_entropy ) )
- A_creator = deployer address
- N_entropy = 32-byte client-side salt
=> concurrent forges never collide in parallel state lanes.

## 3. EIP-7702 Authority Engine — Historical Slot Error
EOA delegation executes in the EOA's storage context, so namespaced storage is required.
This prototype attempted ERC-7201 but calculated the namespace with NIST SHA3 rather
than Ethereum Keccak. Its deployed/source slot is therefore incorrect:

```text
legacy incorrect: 0x07d2f48c801d2b2cb4b6045c6ab259930c8bedfd901510428297972876083700
verified correct:  0xe41f22272467a59d9f0c5cddde07c168cf1192ad3a1536e2283f6fbda6e9a300
```

The older manifest slot `0xac6b9d62...f6700` was also incorrect. Neither legacy
slot may be used by future Session work.

## 4. Corrections vs. Raw Manifest
| Item | Manifest | Adopted |
|---|---|---|
| Solidity | ^0.8.29 (nonexistent) | ^0.8.24 |
| 7201 slot | 0xac6b9d62… (wrong) | 0x07d2f48c… (also wrong; deprecated) |
| Session store | single SessionData | mapping(sessionId => SessionData) for multi-session safety |
| Execution | execute(target,data) | execute(sessionId,target,value,data) with drawdown accounting |

## 5. Files
- contracts/src/GlyphSessionProxy.sol — deprecated proxy with incorrect namespace slot
- contracts/skills.json — machine-readable capability schema
- contracts/vessel_sync.json — inter-agent state bus (frozen, master-owned)
- (pending) GlyphRegistry.sol — to be rebuilt with KV mapping + off-chain IDs
