# Monad address-pair proof

Live Monad testnet proof executed via `contracts/script/MonadAddressPairProof.s.sol`.

- Chain: Monad testnet `10143`
- Payer: `0x014eb22ab7DFa9A843Babc1C6e2dA5B596a62f36`
- Claimant/recipient: `0xd9fE7c8EE7B5E11f8a4e13811E7CFf01E8c82BbD`
- Pull op: `0x8b83664ad0edf186eb6b2b056af9e8778194ad6447813c5a46b60c70b02c6dbc`
- Push op: `0x2ce136c0bd76ab6c8bce42c3bcbbc284296a0f7cddebc763e645d5d536a48105`
- Pull destination receipt: `0x0fe31e1796c4efac6027c9ac8298fbe55a0b3354014805a0500e4b014e689ded`
- Push destination receipt: `0x1f96812d34c4f78737a4f6dd20acf92747076f1e5b140276bbafea45c93ada2c`
- Transactions: `34` total, all status `0x1`
- Final actorNonce: `3`
- Final payer gTST: `940000000000000000000 [9.4e20]`
- Final claimant gTST: `20000000000000000000 [2e19]`

The proof deployed a fresh current-source local loopback stack, executed Pull from payer to claimant/recipient, executed Push claim by the same separate claimant address, finalized both operations, and delivered terminal receipt messages to the destination app.
