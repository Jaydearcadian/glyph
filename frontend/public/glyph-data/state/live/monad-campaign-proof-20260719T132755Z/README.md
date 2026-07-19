# Monad campaign contribution proof

Live Monad testnet proof executed via `contracts/script/MonadCampaignProof.s.sol`.

- Chain: Monad testnet `10143`
- Owner/recipient/contributor A: `0x014eb22ab7DFa9A843Babc1C6e2dA5B596a62f36`
- Contributor B: `0x428D2131102aCd3660b0346c1DFacEDC682E5324`
- Campaign: `0xc1734449aeca5e45E570afd862f47Ff0eE03bEd1`
- Program ID: `0x1c02c59218771a5bd216c7ddfa81ef46e0ca88ed35b3eaa70856c9ab3446e4a9`
- Child A op: `0x6add05a903aa8f57009aea2b7b2951ae4e750b71184c5ec925236bb28ff977f8`
- Child A receipt: `0x64340d39714010e82f3efa2164b5316fae426be8ba6aded06c8f95d051c098db`
- Child B op: `0x22c539cd643f3444be362b9f736b40175d1983a458593a353b96539d697382aa`
- Child B receipt: `0x13568ae2146d48456dd086964d9625fcaf86fa409259fbb3f5608755b3d52db8`
- Aggregate campaign receipt: `0x0f65224219c9db8aba9f580012ea3bd2f3d910bd3b88be35fb9f07d1bd3795af`
- Transactions: `38` total, all status `0x1`
- Readback reconciled total: `20 gTST` and `closed=true` in `campaigns(programId)`.

This proves a campaign aggregates multiple live child Pull operation receipts into one campaign close receipt.
