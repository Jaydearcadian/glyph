# LayerZero support packet — Base Sepolia → Monad Testnet

## Summary

Fresh Base Sepolia → Monad Testnet route-send proof remains externally blocked at LayerZero DVN validation.

## Fresh attempt

| Field | Value |
|---|---|
| Source chain | Base Sepolia `84532` |
| Destination chain | Monad Testnet `10143` |
| Operation ID | `0x7d7091b7ec84fd9df9c10ce73d36db65104093be0f11cb64a51ed72605d2580c` |
| LayerZero GUID | `0xfbdabd378ac63c6426fe79e5ff55b005c99c07bddaa27bf0a13e63090f478789` |
| LayerZero status | `INFLIGHT` |
| DVN status | `WAITING` |
| Destination status | `WAITING` |

## Fresh lane contracts

```json
{
  "orderedExecution": false,
  "baseRouter": "0x6eaD1370111e2E747027C728bDb1AD5C39C33294",
  "baseVault": "0xb949494E4430F666174a57d0E0dd4b98c0b7854B",
  "baseToken": "0x4cBA226A903f44E33446f55499c57147DC03EE82",
  "baseApp": "0xC6C320fB20fF4A5d8E6f5A2FCa5F430A8e43a7AF",
  "baseAdapter": "0xC8Cb1aB6aA5830cF5B928e6152015f3d4C3Ebc43",
  "monadRouter": "0x6F505b2c3d28aE37a2e3DC126440fB60e17A69cf",
  "monadVault": "0x757e30bb637860E2D89F9a85D5A5A5e49313153A",
  "monadToken": "0xed4152e5a8ea20192BA9B0B4319A2615416341B0",
  "monadApp": "0x740d7406889CC1B447422f28468E7e5A100EE6c1",
  "monadAdapter": "0x8a5AfbBBcA3F3Fae0014f58eF25E436DD14d5EEC"
}
```

## Readback highlights

```json
{
  "baseAdapterFrozen": {
    "ok": true,
    "stdout": "true",
    "stderr": ""
  },
  "baseAdapterOrdered": {
    "ok": true,
    "stdout": "false",
    "stderr": ""
  },
  "baseTrustedPeer": {
    "ok": true,
    "stdout": "0x8a5AfbBBcA3F3Fae0014f58eF25E436DD14d5EEC",
    "stderr": ""
  },
  "baseLocalApplication": {
    "ok": true,
    "stdout": "0xC6C320fB20fF4A5d8E6f5A2FCa5F430A8e43a7AF",
    "stderr": ""
  },
  "baseRemoteApplication": {
    "ok": true,
    "stdout": "0x740d7406889CC1B447422f28468E7e5A100EE6c1",
    "stderr": ""
  },
  "baseMessageStatus": {
    "ok": true,
    "stdout": "1",
    "stderr": ""
  },
  "baseAckDelivered": {
    "ok": true,
    "stdout": "false",
    "stderr": ""
  },
  "monadAdapterFrozen": {
    "ok": true,
    "stdout": "true",
    "stderr": ""
  },
  "monadAdapterOrdered": {
    "ok": true,
    "stdout": "false",
    "stderr": ""
  },
  "monadTrustedPeer": {
    "ok": true,
    "stdout": "0xC8Cb1aB6aA5830cF5B928e6152015f3d4C3Ebc43",
    "stderr": ""
  },
  "monadLocalApplication": {
    "ok": true,
    "stdout": "0x740d7406889CC1B447422f28468E7e5A100EE6c1",
    "stderr": ""
  },
  "monadRemoteApplication": {
    "ok": true,
    "stdout": "0xC6C320fB20fF4A5d8E6f5A2FCa5F430A8e43a7AF",
    "stderr": ""
  },
  "monadMessageStatus": {
    "ok": true,
    "stdout": "0",
    "stderr": ""
  },
  "monadDestinationRouteMessage": {
    "ok": true,
    "stdout": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "stderr": ""
  },
  "monadVaultTokenBalance": {
    "ok": true,
    "stdout": "1000000000000000000000000 [1e24]",
    "stderr": ""
  }
}
```

## Conclusion

Both old and fresh Base Sepolia -> Monad Testnet LayerZero V2 packets remain INFLIGHT at source VALIDATING_TX with DVN WAITING and destination WAITING. Base send txs succeeded and source adapter status is SENT; Monad lzReceive has not been called. E2E is externally blocked at LayerZero DVN validation for this pathway.

## Evidence files

```text
state/live/base-monad-crosschain-blocker-20260719T165200Z/evidence.json
state/live/base-monad-crosschain-blocker-20260719T165200Z/fresh-escrow.json
state/live/base-monad-crosschain-blocker-20260719T165200Z/fresh-route.json
state/live/base-monad-crosschain-blocker-20260719T165200Z/layerzero-fresh-guid.json
```
