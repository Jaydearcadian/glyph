#!/usr/bin/env python3
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "scripts" / "glyph_link_tool.py"


def load_tool():
    spec = importlib.util.spec_from_file_location("glyph_link_tool", TOOL)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GlyphLinkToolTest(unittest.TestCase):
    def test_pull_link_roundtrip_keeps_secret_in_fragment_only(self):
        tool = load_tool()
        link = tool.create_pull_link(
            base_url="https://glyph.local/app",
            chain_id=10143,
            router="0x0000000000000000000000000000000000001005",
            vault="0x0000000000000000000000000000000000001006",
            source_asset="0x0000000000000000000000000000000000002001",
            destination_asset="0x0000000000000000000000000000000000002001",
            payer="0x0000000000000000000000000000000000001002",
            recipient="0x0000000000000000000000000000000000001003",
            recovery="0x0000000000000000000000000000000000001004",
            provider="0x0000000000000000000000000000000000009001",
            maximum_input="110000000000000000000",
            destination_amount="100000000000000000000",
            fees={"protocol":"1","provider":"2","referrer":"3","gasSponsor":"4"},
            expiry=1784543060,
            nonce=7,
            secret="pull-secret-do-not-index",
        )
        self.assertTrue(link.startswith("https://glyph.local/app#/glyph/"))
        self.assertNotIn("pull-secret-do-not-index", link.split("#", 1)[0])
        decoded = tool.decode_link(link)
        self.assertEqual(decoded["kind"], "PULL")
        self.assertEqual(decoded["topology"], "LOCAL")
        self.assertEqual(decoded["terms"]["sourceChainId"], 10143)
        self.assertEqual(decoded["terms"]["destinationChainId"], 10143)
        self.assertEqual(decoded["secrets"]["secret"], "pull-secret-do-not-index")
        self.assertEqual(decoded["operationId"], tool.operation_id(decoded["terms"]))

    def test_push_claim_link_has_nullifier_hash_not_secret_in_public_index(self):
        tool = load_tool()
        link = tool.create_push_link(
            base_url="https://glyph.local/app",
            chain_id=10143,
            router="0x0000000000000000000000000000000000001005",
            vault="0x0000000000000000000000000000000000001006",
            source_asset="0x0000000000000000000000000000000000002001",
            destination_asset="0x0000000000000000000000000000000000002001",
            payer="0x0000000000000000000000000000000000001002",
            recipient="0x0000000000000000000000000000000000001003",
            recovery="0x0000000000000000000000000000000000001004",
            provider="0x0000000000000000000000000000000000009001",
            gatekeeper="0x0000000000000000000000000000000000009002",
            maximum_input="110000000000000000000",
            destination_amount="100000000000000000000",
            fees={"protocol":"1","provider":"2","referrer":"3","gasSponsor":"4"},
            expiry=1784543060,
            nonce=8,
            claim_secret="claim-secret-do-not-index",
        )
        decoded = tool.decode_link(link)
        public_index = tool.public_index_record(decoded)
        self.assertEqual(decoded["kind"], "PUSH")
        self.assertIn("nullifierHash", decoded["claim"])
        self.assertNotIn("claim_secret", json.dumps(public_index))
        self.assertNotIn("claim-secret-do-not-index", json.dumps(public_index))
        self.assertNotIn("secrets", public_index)
        self.assertEqual(public_index["operationId"], decoded["operationId"])

    def test_crosschain_pull_roundtrip_includes_route_facts_and_public_index(self):
        tool = load_tool()
        link = tool.create_crosschain_pull_link(
            base_url="https://glyph.local/app",
            source_chain_id=84532,
            destination_chain_id=10143,
            router="0x0000000000000000000000000000000000001005",
            vault="0x0000000000000000000000000000000000001006",
            source_asset="0x0000000000000000000000000000000000002001",
            destination_asset="0x0000000000000000000000000000000000002002",
            payer="0x0000000000000000000000000000000000001002",
            recipient="0x0000000000000000000000000000000000001003",
            recovery="0x0000000000000000000000000000000000001004",
            provider="0x0000000000000000000000000000000000009001",
            maximum_input="110000000000000000000",
            destination_amount="100000000000000000000",
            fees={"protocol":"1","provider":"2","referrer":"3","gasSponsor":"4"},
            expiry=1784543060,
            nonce=17,
            route={
                "sourceApplication":"0x0000000000000000000000000000000000003001",
                "destinationApplication":"0x0000000000000000000000000000000000003002",
                "adapter":"0x0000000000000000000000000000000000004001",
                "destinationEid":40267,
                "gasLimit":300000,
                "proof":"AUTHENTICATED_ADAPTER"
            },
            secret="crosschain-pull-secret",
        )
        decoded = tool.decode_link(link)
        public_index = tool.public_index_record(decoded)
        self.assertEqual(decoded["topology"], "CROSS_CHAIN")
        self.assertEqual(decoded["terms"]["sourceChainId"], 84532)
        self.assertEqual(decoded["terms"]["destinationChainId"], 10143)
        self.assertEqual(decoded["route"]["destinationEid"], 40267)
        self.assertEqual(public_index["sourceChainId"], 84532)
        self.assertEqual(public_index["destinationChainId"], 10143)
        self.assertEqual(public_index["destinationEid"], 40267)
        self.assertNotIn("crosschain-pull-secret", json.dumps(public_index))

    def test_crosschain_push_claim_link_keeps_secret_private_and_route_public(self):
        tool = load_tool()
        link = tool.create_crosschain_push_link(
            base_url="https://glyph.local/app",
            source_chain_id=84532,
            destination_chain_id=10143,
            router="0x0000000000000000000000000000000000001005",
            vault="0x0000000000000000000000000000000000001006",
            source_asset="0x0000000000000000000000000000000000002001",
            destination_asset="0x0000000000000000000000000000000000002002",
            payer="0x0000000000000000000000000000000000001002",
            recipient="0x0000000000000000000000000000000000001003",
            recovery="0x0000000000000000000000000000000000001004",
            provider="0x0000000000000000000000000000000000009001",
            gatekeeper="0x0000000000000000000000000000000000009002",
            maximum_input="110000000000000000000",
            destination_amount="100000000000000000000",
            fees={"protocol":"1","provider":"2","referrer":"3","gasSponsor":"4"},
            expiry=1784543060,
            nonce=18,
            route={
                "sourceApplication":"0x0000000000000000000000000000000000003001",
                "destinationApplication":"0x0000000000000000000000000000000000003002",
                "adapter":"0x0000000000000000000000000000000000004001",
                "destinationEid":40267,
                "gasLimit":350000,
                "proof":"AUTHENTICATED_ADAPTER"
            },
            claim_secret="crosschain-claim-secret",
        )
        decoded = tool.decode_link(link)
        public_index = tool.public_index_record(decoded)
        self.assertEqual(decoded["kind"], "PUSH")
        self.assertEqual(decoded["topology"], "CROSS_CHAIN")
        self.assertIn("nullifierHash", decoded["claim"])
        self.assertEqual(public_index["destinationEid"], 40267)
        self.assertIn("nullifierHash", public_index)
        self.assertNotIn("crosschain-claim-secret", json.dumps(public_index))
        self.assertNotIn("secrets", public_index)

    def test_receipt_link_verifies_existing_canonical_receipt(self):
        tool = load_tool()
        for name in ["LOCAL_PULL.receipt.json", "PULL.receipt.json"]:
            receipt_path = ROOT / "state" / "receipts" / name
            link = tool.create_receipt_link("https://glyph.local/app", receipt_path)
            decoded = tool.decode_link(link)
            self.assertEqual(decoded["kind"], "RECEIPT")
            verification = tool.verify_receipt_link(decoded, ROOT)
            self.assertTrue(verification["ok"])
            self.assertEqual(verification["finalReceiptHash"], decoded["receipt"]["finalReceiptHash"])

    def test_cli_create_inspect_and_index(self):
        with tempfile.TemporaryDirectory() as td:
            out = pathlib.Path(td) / "pull.link.json"
            subprocess.run([
                sys.executable, str(TOOL), "pull", "create", "--base-url", "https://glyph.local/app",
                "--chain-id", "10143", "--router", "0x0000000000000000000000000000000000001005",
                "--vault", "0x0000000000000000000000000000000000001006",
                "--source-asset", "0x0000000000000000000000000000000000002001",
                "--destination-asset", "0x0000000000000000000000000000000000002001",
                "--payer", "0x0000000000000000000000000000000000001002",
                "--recipient", "0x0000000000000000000000000000000000001003",
                "--recovery", "0x0000000000000000000000000000000000001004",
                "--provider", "0x0000000000000000000000000000000000009001",
                "--maximum-input", "110000000000000000000", "--destination-amount", "100000000000000000000",
                "--protocol-fee", "1", "--provider-fee", "2", "--referrer-fee", "3", "--gas-sponsor-fee", "4",
                "--expiry", "1784543060", "--nonce", "9", "--secret", "cli-secret", "--out", str(out)
            ], check=True, cwd=ROOT)
            payload = json.loads(out.read_text())
            inspect = subprocess.run([sys.executable, str(TOOL), "inspect", payload["link"]], check=True, cwd=ROOT, text=True, capture_output=True)
            data = json.loads(inspect.stdout)
            self.assertEqual(data["kind"], "PULL")
            index = subprocess.run([sys.executable, str(TOOL), "index", payload["link"]], check=True, cwd=ROOT, text=True, capture_output=True)
            index_data = json.loads(index.stdout)
            self.assertNotIn("secret", json.dumps(index_data))
            self.assertEqual(index_data["operationId"], data["operationId"])


if __name__ == "__main__":
    unittest.main()
