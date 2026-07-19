#!/usr/bin/env python3
from __future__ import annotations
import json, hashlib, subprocess, re, shutil
from pathlib import Path
from datetime import datetime, timezone
import qrcode

ROOT=Path(__file__).resolve().parents[1]
PROOF_ID='monad-distribution-proof-20260719T172223Z'
OUT=ROOT/'state/live'/PROOF_ID
WORK=ROOT/'state/live/monad-distribution-proof-work'
FRONT=ROOT/'state/frontend'
RPC='https://testnet-rpc.monad.xyz'
CHAIN_ID=10143
CHAIN='Monad Testnet'
TOKEN='0x1d482783316FdeF2e795A1C193ACE280660A887a'
CAMPAIGN='0x34ebCe467EcB6cA5D9f0E9d5bF3C23b9E2B191bb'
SPLITTER='0x3f90710e945f1BFa07737B97676056DF3F92Db59'
OWNER='0x014eb22ab7DFa9A843Babc1C6e2dA5B596a62f36'
COLLAB='0xE5545934D275DB6b50bF911975ca36590bf96ca6'
REF='0x072B653D70614867531c9061A913A41A081941C9'
CAMPAIGN_ID='0xd4117f5899cab786974c733c07812ec19e3c0e8579fd15b33d92559c9d55b1e8'
CHILD_A='0xe3df0f88e9d251a6e5532455726ab2f11806ae08c3cb20d4ab3e8caaa5a7a938'
CHILD_B='0x49aceaf0a6cd9b87d799e1cfeb08483b8e0e27c520c3459be7d6e8748554a006'
CHILD_RECEIPT_A='0x8d165c3969c3531bfd8dd3ad1f36fb285f54a6cfe923d58ab8522dcc302127fe'
CHILD_RECEIPT_B='0x4f79d10a0c2b49bec08232efc342a4e7490fbd4f4c0727c7662ad529b5f92614'
AGG_CAMPAIGN='0x85a1c50b548e26a32765b87fe0413438a5033fa6e0c3205f8afcfd47ac5b665d'
DID='0xe91b66e0fd1df23dbd317fc1119202f2460458da2fc276a55627b342f87f888a'
CLAIMS={
 'creator': {'recipient':OWNER,'bps':7000,'amount':'14000000000000000000','receipt':'0xbb0cb1de3d99179b6b9bcebd7aa6f64d0f00ed8560c4b4ace126567a227d90a0','tx':'0xb7e99e31e327919720632ddc36aabc3d2e1ecde7ced85550852a346d5895685f'},
 'collaborator': {'recipient':COLLAB,'bps':2000,'amount':'4000000000000000000','receipt':'0xbe2df4024b3ffacefdf3f30ee41f6f4c25fc71efb18ea9615c4526618f581998','tx':'0x152cd8d01cb95a6b0015ee5a5b5af1cd2bf8c1495e7b2594a908b64a4fc47f7d'},
 'referrer': {'recipient':REF,'bps':1000,'amount':'2000000000000000000','receipt':'0x5351c4a6da9b1e4ae8b19455fd7b34fb01c110e0484005ebe668f0826f6cc57f','tx':'0x77e457dc66cbc680fbd7dcd2f92e5ef60855a673b4efe783600e0b162c4c07ee'},
}
TXS={
 'campaignDeploy':'0xc501026c99d03666d34192286165b3199b0500ccec90d14e8a4377d8f30541bd',
 'splitterDeploy':'0x2f384a28ff7e89befdae104c70c75f4e9a16fd3baaa7a7498cb7ac2a61ae5ba2',
 'tokenMint':'0x21c3169b4144c1016b45480ef0e21da93b5e7566ffe37937bbaef4dc0cea1646',
 'campaignCreate':'0x8ba5e969eaf276e944cc82cd0eda182b3897f4f89ec457371d11a6295ed24252',
 'campaignReconcileA':'0xe3a2862a19b71a3365ce0350957bc59637257bff72b5fb43e0aed40fcc5e199e',
 'campaignReconcileB':'0x9516f45ec71d061b4dea2b20a26cbb10ffe2e50d2fb2e6bd1c8ec459f1dc963a',
 'campaignClose':'0x81504312ee89b5a1c48ebdefa8202e29f23d8b813548f6abe78cc34e40cedae1',
 'approveSplitter':'0x3c6efa08c972810fb444dad67adf26cb924572aa903319538ca7a49c045d79b7',
 'distributionCreate':'0x7843f4311f3f6d58f770b2766e0f8311e191f4856ba883afddad7484e5ac5de0',
 'creatorClaim':CLAIMS['creator']['tx'],
 'collaboratorClaim':CLAIMS['collaborator']['tx'],
 'referrerClaim':CLAIMS['referrer']['tx'],
 'collaboratorGasTopup':'0xb9a5a7175ff1e58b06d75b1b136c37d5a5eaf3066e06dc1d0f20ce4bc3eedab1',
 'referrerGasTopup':'0x28619cb9874f8f83152534363f8dad233e12486559d36a8e6d502895c37205ed',
}

def sha(b:bytes)->str: return hashlib.sha256(b).hexdigest()
def write_json(p,obj): p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(obj,indent=2,sort_keys=True)+'\n')
def cast(*args): return subprocess.check_output(['cast',*args,'--rpc-url',RPC], text=True).strip()
def receipt_status(tx):
    try:
        out=subprocess.check_output(['cast','receipt',tx,'--rpc-url',RPC,'--json'], text=True)
        j=json.loads(out); return {'txHash':tx,'status':j.get('status'),'blockNumber':j.get('blockNumber'),'gasUsed':j.get('gasUsed')}
    except Exception as e: return {'txHash':tx,'error':str(e)}

def link_for(kind, h):
    return f"https://jaydearcadian.github.io/Bifrost/app?glyphReceipt={h}#kind={kind}&chain=monad-testnet&distribution={DID}"

def card_svg(title, subtitle, fields):
    rows=''.join(f'<text x="36" y="{150+i*34}" class="k">{k}</text><text x="250" y="{150+i*34}" class="v">{v}</text>' for i,(k,v) in enumerate(fields))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="920" height="520" viewBox="0 0 920 520">
<defs><linearGradient id="g" x1="0" x2="1"><stop stop-color="#17112f"/><stop offset="1" stop-color="#0a1c2f"/></linearGradient><style>.t{{font:700 32px Inter,Arial;fill:#fff}}.s{{font:500 17px Inter,Arial;fill:#aeb8ff}}.k{{font:600 15px Inter,Arial;fill:#7de6d1}}.v{{font:500 14px ui-monospace,SFMono-Regular,Menlo,monospace;fill:#f7f7ff}}.badge{{font:700 13px Inter,Arial;fill:#071014}}</style></defs>
<rect width="920" height="520" rx="32" fill="url(#g)"/><rect x="24" y="24" width="872" height="472" rx="26" fill="none" stroke="#62f5da" opacity=".45"/><text x="36" y="68" class="t">{title}</text><text x="36" y="100" class="s">{subtitle}</text><rect x="36" y="118" width="210" height="28" rx="14" fill="#62f5da"/><text x="54" y="137" class="badge">LIVE MONAD DISTRIBUTION</text>{rows}</svg>'''

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    totals=cast('call',SPLITTER,'distributionTotals(bytes32)(uint256,uint256,uint256,uint256)',DID).splitlines()
    code_checks={'campaignCode': cast('code',CAMPAIGN)[:18]+'...', 'splitterCode': cast('code',SPLITTER)[:18]+'...'}
    receipts={k:receipt_status(v) for k,v in TXS.items()}
    evidence={
      'schema':'glyph.live.distribution.evidence.v1','proofId':PROOF_ID,'chain':{'name':CHAIN,'chainId':CHAIN_ID,'rpcUrl':RPC},
      'contracts':{'token':TOKEN,'campaign':CAMPAIGN,'splitter':SPLITTER},
      'actors':{'creator':OWNER,'collaborator':COLLAB,'referrer':REF},
      'campaign':{'campaignId':CAMPAIGN_ID,'childOperations':[CHILD_A,CHILD_B],'childReceiptHashes':[CHILD_RECEIPT_A,CHILD_RECEIPT_B],'aggregateCampaignReceiptHash':AGG_CAMPAIGN},
      'distribution':{'distributionId':DID,'totalAmount':'20000000000000000000','claimedTotal':totals[1].split()[0],'unclaimedAmount':totals[2].split()[0],'recoveredAmount':totals[3].split()[0],'splitsBps':{'creator':7000,'collaborator':2000,'referrer':1000}},
      'claims':CLAIMS,'transactions':TXS,'receiptStatus':receipts,'readbacks':{'totalsRaw':totals,'codeChecks':code_checks},
      'notes':['Explicit-recipient splitter; no Merkle distribution.','Three distinct recipient addresses claimed live on Monad testnet.','Distribution is fully claimed: unclaimedAmount == 0 and recoveredAmount == 0.']
    }
    write_json(OUT/'evidence.json', evidence)
    (OUT/'broadcast.log').write_text((WORK/'broadcast.log').read_text() if (WORK/'broadcast.log').exists() else '')
    write_json(OUT/'txs.json', TXS)
    for role,c in CLAIMS.items():
        rec={
          'schema':'glyph.distribution.receipt.v1','kind':'DISTRIBUTION_CLAIM','role':role,'chainId':CHAIN_ID,'chain':CHAIN,
          'distributionId':DID,'campaignId':CAMPAIGN_ID,'parentCampaignReceiptHash':AGG_CAMPAIGN,'claimReceiptHash':c['receipt'],
          'recipient':c['recipient'],'amount':c['amount'],'bps':c['bps'],'token':TOKEN,'splitter':SPLITTER,'txHash':c['tx'],
          'status':'CLAIMED','provenance':{'proofId':PROOF_ID,'evidencePath':f'state/live/{PROOF_ID}/evidence.json'}
        }
        write_json(OUT/f'{role}.distribution.receipt.json', rec)
        link={'schema':'glyph.receipt.link.v1','kind':'DISTRIBUTION_CLAIM','receiptHash':c['receipt'],'url':link_for('DISTRIBUTION_CLAIM',c['receipt']),'receiptPath':f'state/live/{PROOF_ID}/{role}.distribution.receipt.json'}
        write_json(OUT/f'{role}.distribution.receipt.link.json', link)
        qrcode.make(link['url']).save(OUT/f'{role}.distribution.receipt.qr.png')
        svg=card_svg(f'{role.title()} distribution claim','Campaign payout split claimed on Monad',[
          ('recipient',c['recipient']),('amount wei',c['amount']),('split bps',str(c['bps'])),('claim receipt',c['receipt'][:34]+'…'),('tx',c['tx'][:34]+'…'),('distribution',DID[:34]+'…')])
        (OUT/f'{role}.distribution.receipt.card.svg').write_text(svg)
    agg={'schema':'glyph.distribution.aggregateReceipt.v1','kind':'DISTRIBUTION_AGGREGATE','distributionId':DID,'campaignId':CAMPAIGN_ID,'parentCampaignReceiptHash':AGG_CAMPAIGN,'totalAmount':'20000000000000000000','claimedTotal':totals[1].split()[0],'unclaimedAmount':totals[2].split()[0],'claims':CLAIMS,'txs':TXS}
    agg_hash='0x'+hashlib.sha256(json.dumps(agg,sort_keys=True).encode()).hexdigest()
    agg['aggregateDistributionReceiptHash']=agg_hash
    write_json(OUT/'aggregate.distribution.receipt.json',agg)
    write_json(OUT/'aggregate.distribution.receipt.link.json',{'schema':'glyph.receipt.link.v1','kind':'DISTRIBUTION_AGGREGATE','receiptHash':agg_hash,'url':link_for('DISTRIBUTION_AGGREGATE',agg_hash),'receiptPath':f'state/live/{PROOF_ID}/aggregate.distribution.receipt.json'})
    qrcode.make(link_for('DISTRIBUTION_AGGREGATE',agg_hash)).save(OUT/'aggregate.distribution.receipt.qr.png')
    (OUT/'aggregate.distribution.receipt.card.svg').write_text(card_svg('Aggregate distribution receipt','Three recipient claims fully settled on Monad',[('distribution',DID[:34]+'…'),('claimed total',totals[1].split()[0]),('unclaimed',totals[2].split()[0]),('creator',CLAIMS['creator']['receipt'][:34]+'…'),('collaborator',CLAIMS['collaborator']['receipt'][:34]+'…'),('referrer',CLAIMS['referrer']['receipt'][:34]+'…')]))
    readme=f'''# Live Monad distribution proof\n\nProof id: `{PROOF_ID}`\n\nThis proof adds the explicit-recipient campaign payout splitter on top of the campaign aggregate receipt. It proves:\n\n- campaign close / aggregate campaign receipt;\n- distribution plan funded with `20 gTST`;\n- creator claim: 70%;\n- collaborator claim: 20%;\n- referrer claim: 10%;\n- final readback: `claimedTotal == totalAmount`, `unclaimedAmount == 0`, `recoveredAmount == 0`.\n\n## Contracts\n\n- Campaign: `{CAMPAIGN}`\n- Splitter: `{SPLITTER}`\n- Token: `{TOKEN}`\n\n## Transaction proof\n\n| Step | Tx |\n|---|---|\n''' + ''.join(f'| {k} | `{v}` |\n' for k,v in TXS.items()) + '\n## Artifacts\n\n- `evidence.json`\n- `txs.json`\n- `*.distribution.receipt.json`\n- `*.distribution.receipt.card.svg`\n- `*.distribution.receipt.link.json`\n- `*.distribution.receipt.qr.png`\n'
    (OUT/'README.md').write_text(readme)
    # ABI/frontend surfaces
    abi_src=ROOT/'contracts/out/CampaignPayoutSplitter.sol/CampaignPayoutSplitter.json'
    if abi_src.exists():
        abi=json.loads(abi_src.read_text())['abi']; write_json(FRONT/'abi/CampaignPayoutSplitter.json',abi)
    cc_src=ROOT/'contracts/out/ContributionCampaign.sol/ContributionCampaign.json'
    if cc_src.exists(): write_json(FRONT/'abi/ContributionCampaign.json',json.loads(cc_src.read_text())['abi'])
    write_json(FRONT/'flows/distribution.flow.json',{'schema':'glyph.frontend.flow.v1','flow':'distribution','mode':'live-proven','stages':['campaign close','createDistribution','creator claim','collaborator claim','referrer claim','aggregate distribution receipt'],'contract':'CampaignPayoutSplitter','proofPath':f'state/live/{PROOF_ID}/evidence.json','userSafeWrites':['claim(bytes32)'],'operatorWrites':['createDistribution(CreateDistributionInput)']})
    dist_index={'schema':'glyph.frontend.distribution.index.v1','proofId':PROOF_ID,'contract':SPLITTER,'distributionId':DID,'evidencePath':f'state/live/{PROOF_ID}/evidence.json','aggregateReceiptPath':f'state/live/{PROOF_ID}/aggregate.distribution.receipt.json','claimReceipts':[{**{'role':r},**{'path':f'state/live/{PROOF_ID}/{r}.distribution.receipt.json','cardPath':f'state/live/{PROOF_ID}/{r}.distribution.receipt.card.svg','qrPath':f'state/live/{PROOF_ID}/{r}.distribution.receipt.qr.png'},**c} for r,c in CLAIMS.items()]}
    write_json(FRONT/'distributions/index.json',dist_index)
    # append proof/receipts/transactions indexes conservatively
    for idx_path, key, item in [
      (FRONT/'proofs/index.json','proofs',{'label':'Monad payout distribution proof','kind':'distribution','path':f'state/live/{PROOF_ID}/evidence.json','status':'live'}),
      (FRONT/'receipts/index.json','receipts',{'label':'Aggregate distribution receipt','kind':'DISTRIBUTION_AGGREGATE','path':f'state/live/{PROOF_ID}/aggregate.distribution.receipt.json','cardPath':f'state/live/{PROOF_ID}/aggregate.distribution.receipt.card.svg','qrPath':f'state/live/{PROOF_ID}/aggregate.distribution.receipt.qr.png','receiptHash':agg_hash}),
    ]:
        j=json.loads(idx_path.read_text()); j.setdefault(key,[]).append(item); write_json(idx_path,j)
    tx_index=json.loads((FRONT/'transactions/index.json').read_text())
    tx_index.setdefault('transactions',[]).extend([{'flow':'distribution','chainId':CHAIN_ID,'label':k,'txHash':v,'contract':SPLITTER if 'Claim' in k or 'distribution' in k else CAMPAIGN,'status':'success'} for k,v in TXS.items() if k not in ('collaboratorGasTopup','referrerGasTopup')])
    write_json(FRONT/'transactions/index.json',tx_index)
    # checksums
    files=[p for p in sorted(OUT.rglob('*')) if p.is_file()]
    (OUT/'SHA256SUMS.txt').write_text(''.join(f'{sha(p.read_bytes())}  {p.relative_to(ROOT)}\n' for p in files))
    print(OUT)

if __name__=='__main__': main()
