# Base Sepolia → Monad Testnet cross-chain blocker evidence

## Summary

Fresh current-source LayerZero V2 lane was deployed, wired, frozen, and read back successfully. A live Base escrow and LayerZero route were sent. The packet did not reach Monad `lzReceive`; LayerZero Scan stayed at `VALIDATING_TX` / DVN `WAITING`.

## Fresh lane

- Base router: `0x6eaD1370111e2E747027C728bDb1AD5C39C33294`
- Base app: `0xC6C320fB20fF4A5d8E6f5A2FCa5F430A8e43a7AF`
- Base adapter: `0xC8Cb1aB6aA5830cF5B928e6152015f3d4C3Ebc43`
- Monad vault: `0x757e30bb637860E2D89F9a85D5A5A5e49313153A`
- Monad app: `0x740d7406889CC1B447422f28468E7e5A100EE6c1`
- Monad adapter: `0x8a5AfbBBcA3F3Fae0014f58eF25E436DD14d5EEC`
- Ordered execution: `false`

## Fresh attempt

- Operation: `0x7d7091b7ec84fd9df9c10ce73d36db65104093be0f11cb64a51ed72605d2580c`
- LZ GUID: `0xfbdabd378ac63c6426fe79e5ff55b005c99c07bddaa27bf0a13e63090f478789`
- LayerZero status: `{'name': 'INFLIGHT', 'message': 'Source transaction sent'}`
- Verification: `{'dvn': {'dvns': {}, 'status': 'WAITING'}, 'sealer': {'status': 'WAITING'}}`

## Old attempt checked too

- Operation: `0xae357910459e14ee2c59209d1203d0738fb0e95e40526bea6d2527d602abb1d5`
- LZ GUID: `0xca97b7e1104f8a8399fa8e74f763b595dedf93011689cf35037f662b3ef4dc95`
- LayerZero status: `{'name': 'INFLIGHT', 'message': 'Source transaction sent'}`
- Verification: `{'dvn': {'dvns': {}, 'status': 'WAITING'}, 'sealer': {'status': 'WAITING'}}`

## Conclusion

The app/adapter route is live through Base send, but E2E delivery is blocked before destination execution by LayerZero DVN validation on the Base Sepolia → Monad Testnet pathway.
