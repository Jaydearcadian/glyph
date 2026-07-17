# Glyph Core Architecture — Parallel EVM & EIP-7702 Synthesis

Status: **DESIGN / CORRECTED — NOT COMPILED OR DEPLOYED** (per user directive "initiate correction but don't execute").

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

## 3. EIP-7702 Authority Engine — Storage Collision Guardrails
EOA delegates to proxy code; proxy runs in the EOA's storage context. Standard slots
(Slot 0,1…) corrupt other delegations. Fix: **ERC-7201 namespaced storage**.

ERC-7201 slot = keccak256( uint256(keccak256(NS)) - 1 ) & ~uint256(0xff)
NS = "glyph.storage.session.v1"
=> **0x07d2f48c801d2b2cb4b6045c6ab259930c8bedfd901510428297972876083700**

⚠️ Manifest hard-coded 0xac6b9d62...f6700 — verified NOT the ERC-7201 slot for this NS.
   Using the correct computed slot. This is the critical correction.

## 4. Corrections vs. Raw Manifest
| Item | Manifest | Adopted |
|---|---|---|
| Solidity | ^0.8.29 (nonexistent) | ^0.8.24 |
| 7201 slot | 0xac6b9d62… (wrong) | 0x07d2f48c… (computed) |
| Session store | single SessionData | mapping(sessionId => SessionData) for multi-session safety |
| Execution | execute(target,data) | execute(sessionId,target,value,data) with drawdown accounting |

## 5. Files
- contracts/src/GlyphSessionProxy.sol — ERC-7201 corrected proxy (design)
- contracts/skills.json — machine-readable capability schema
- contracts/vessel_sync.json — inter-agent state bus (frozen, master-owned)
- (pending) GlyphRegistry.sol — to be rebuilt with KV mapping + off-chain IDs
