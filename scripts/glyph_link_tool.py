#!/usr/bin/env python3
"""Glyph link protocol helper.

Canonicalizes PULL/PUSH/RECEIPT link payloads for frontend-independent tests.
Secrets are carried only inside URL fragments and stripped from public index records.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import pathlib
import sys
from typing import Any
from urllib.parse import urlsplit, urlunsplit

LINK_SCHEMA_VERSION = "glyph.link.v1"
TERMS_DOMAIN = "GLYPH_LINK_TERMS_V1"
OPERATION_DOMAIN = "GLYPH_LINK_OPERATION_V1"
NULLIFIER_DOMAIN = "GLYPH_PUSH_CLAIM_NULLIFIER_V1"
RECEIPT_DOMAIN = "GLYPH_FINAL_RECEIPT_V1"
ROUTE_DOMAIN = "GLYPH_LINK_ROUTE_V1"
FRAGMENT_PREFIX = "/glyph/"


def canon(obj: Any) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def sha256_hex(domain: str, obj: Any) -> str:
    return "0x" + hashlib.sha256(domain.encode() + canon(obj)).hexdigest()


def b64url_encode(obj: Any) -> str:
    raw = canon(obj)
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def b64url_decode(token: str) -> Any:
    pad = "=" * (-len(token) % 4)
    return json.loads(base64.urlsafe_b64decode((token + pad).encode()).decode())


def normalize_address(value: str, field: str = "address") -> str:
    if not isinstance(value, str) or not value.startswith("0x") or len(value) != 42:
        raise ValueError(f"{field} must be a 20-byte hex address")
    int(value[2:], 16)
    return "0x" + value[2:].lower()


def uint_string(value: str | int, field: str) -> str:
    if isinstance(value, int):
        if value < 0:
            raise ValueError(f"{field} must be non-negative")
        return str(value)
    if not isinstance(value, str) or not value.isdigit():
        raise ValueError(f"{field} must be a decimal uint string")
    return str(int(value))


def normalize_route(route: dict[str, Any] | None, *, source_chain_id: int, destination_chain_id: int) -> dict[str, Any] | None:
    if route is None:
        return None
    if source_chain_id == destination_chain_id:
        raise ValueError("route is only valid for CROSS_CHAIN links")
    normalized = {
        "sourceApplication": normalize_address(route["sourceApplication"], "sourceApplication"),
        "destinationApplication": normalize_address(route["destinationApplication"], "destinationApplication"),
        "adapter": normalize_address(route["adapter"], "adapter"),
        "destinationEid": int(route["destinationEid"]),
        "gasLimit": int(route["gasLimit"]),
        "proof": str(route.get("proof", "AUTHENTICATED_ADAPTER")),
    }
    if normalized["destinationEid"] <= 0:
        raise ValueError("destinationEid must be nonzero")
    if normalized["gasLimit"] <= 0:
        raise ValueError("gasLimit must be nonzero")
    normalized["routeHash"] = sha256_hex(ROUTE_DOMAIN, {k: v for k, v in normalized.items() if k != "routeHash"})
    return normalized


def make_terms(
    *,
    mode: str,
    chain_id: int | None = None,
    source_chain_id: int | None = None,
    destination_chain_id: int | None = None,
    router: str,
    vault: str,
    source_asset: str,
    destination_asset: str,
    payer: str,
    recipient: str,
    recovery: str,
    provider: str,
    maximum_input: str | int,
    destination_amount: str | int,
    fees: dict[str, str | int],
    expiry: int,
    nonce: int,
    gatekeeper: str | None = None,
) -> dict[str, Any]:
    if mode not in ("PULL", "PUSH"):
        raise ValueError("mode must be PULL or PUSH")
    if chain_id is not None:
        if source_chain_id is not None or destination_chain_id is not None:
            raise ValueError("use either chain_id or source_chain_id/destination_chain_id")
        source_chain_id = destination_chain_id = int(chain_id)
    if source_chain_id is None or destination_chain_id is None:
        raise ValueError("source and destination chain ids are required")
    source_chain_id = int(source_chain_id)
    destination_chain_id = int(destination_chain_id)
    if source_chain_id <= 0 or destination_chain_id <= 0:
        raise ValueError("chain ids must be nonzero")
    topology = "LOCAL" if source_chain_id == destination_chain_id else "CROSS_CHAIN"
    terms = {
        "mode": mode,
        "topology": topology,
        "sourceChainId": source_chain_id,
        "destinationChainId": destination_chain_id,
        "router": normalize_address(router, "router"),
        "destinationVault": normalize_address(vault, "vault"),
        "sourceAsset": normalize_address(source_asset, "source_asset"),
        "destinationAsset": normalize_address(destination_asset, "destination_asset"),
        "payer": normalize_address(payer, "payer"),
        "recipient": normalize_address(recipient, "recipient"),
        "recovery": normalize_address(recovery, "recovery"),
        "provider": normalize_address(provider, "provider"),
        "maximumInput": uint_string(maximum_input, "maximum_input"),
        "destinationAmount": uint_string(destination_amount, "destination_amount"),
        "fees": {
            "protocol": uint_string(fees.get("protocol", 0), "protocol_fee"),
            "provider": uint_string(fees.get("provider", 0), "provider_fee"),
            "referrer": uint_string(fees.get("referrer", 0), "referrer_fee"),
            "gasSponsor": uint_string(fees.get("gasSponsor", 0), "gas_sponsor_fee"),
        },
        "expiry": int(expiry),
        "nonce": int(nonce),
    }
    if gatekeeper is not None:
        terms["claimGatekeeper"] = normalize_address(gatekeeper, "gatekeeper")
    return terms


def terms_hash(terms: dict[str, Any]) -> str:
    return sha256_hex(TERMS_DOMAIN, terms)


def operation_id(terms: dict[str, Any]) -> str:
    return sha256_hex(OPERATION_DOMAIN, {"termsHash": terms_hash(terms), "terms": terms})


def nullifier_hash(operation: str, claim_secret: str) -> str:
    if not claim_secret:
        raise ValueError("claim_secret is required")
    return "0x" + hashlib.sha256(NULLIFIER_DOMAIN.encode() + operation.encode() + claim_secret.encode()).hexdigest()


def compose_link(base_url: str, payload: dict[str, Any]) -> str:
    parts = urlsplit(base_url)
    if not parts.scheme or not parts.netloc:
        raise ValueError("base_url must include scheme and host")
    clean = urlunsplit((parts.scheme, parts.netloc, parts.path.rstrip("/"), parts.query, ""))
    return clean + "#" + FRAGMENT_PREFIX + b64url_encode(payload)


def decode_link(link: str) -> dict[str, Any]:
    parts = urlsplit(link)
    frag = parts.fragment
    if not frag.startswith(FRAGMENT_PREFIX):
        raise ValueError("not a Glyph link fragment")
    payload = b64url_decode(frag[len(FRAGMENT_PREFIX):])
    validate_payload(payload)
    return payload


def validate_payload(payload: dict[str, Any]) -> None:
    if payload.get("schemaVersion") != LINK_SCHEMA_VERSION:
        raise ValueError("unsupported schemaVersion")
    kind = payload.get("kind")
    if kind not in ("PULL", "PUSH", "RECEIPT"):
        raise ValueError("unsupported link kind")
    if kind in ("PULL", "PUSH"):
        terms = payload.get("terms")
        if not isinstance(terms, dict):
            raise ValueError("terms required")
        topology = "LOCAL" if terms.get("sourceChainId") == terms.get("destinationChainId") else "CROSS_CHAIN"
        if payload.get("topology") != topology or terms.get("topology") != topology:
            raise ValueError("topology mismatch")
        if topology == "CROSS_CHAIN":
            route = payload.get("route")
            if not isinstance(route, dict):
                raise ValueError("cross-chain links require route facts")
            expected_route = normalize_route(route, source_chain_id=terms["sourceChainId"], destination_chain_id=terms["destinationChainId"])
            if expected_route is None:
                raise ValueError("cross-chain links require route facts")
            if route.get("routeHash") != expected_route["routeHash"]:
                raise ValueError("routeHash mismatch")
        elif "route" in payload:
            raise ValueError("local links must not include route facts")
        if payload.get("termsHash") != terms_hash(terms):
            raise ValueError("termsHash mismatch")
        if payload.get("operationId") != operation_id(terms):
            raise ValueError("operationId mismatch")
        secrets = payload.get("secrets", {})
        if secrets is not None and not isinstance(secrets, dict):
            raise ValueError("secrets must be an object")
    if kind == "PUSH":
        claim = payload.get("claim", {})
        secret = payload.get("secrets", {}).get("claimSecret")
        if secret and claim.get("nullifierHash") != nullifier_hash(payload["operationId"], secret):
            raise ValueError("nullifierHash mismatch")
    if kind == "RECEIPT":
        receipt = payload.get("receipt")
        if not isinstance(receipt, dict) or "finalReceiptHash" not in receipt:
            raise ValueError("receipt link requires receipt finalReceiptHash")


def base_payload(kind: str, terms: dict[str, Any], secrets: dict[str, str] | None = None, route: dict[str, Any] | None = None) -> dict[str, Any]:
    op = operation_id(terms)
    payload = {
        "schemaVersion": LINK_SCHEMA_VERSION,
        "kind": kind,
        "topology": terms["topology"],
        "operationId": op,
        "termsHash": terms_hash(terms),
        "terms": terms,
        "display": {
            "sourceChainId": terms["sourceChainId"],
            "destinationChainId": terms["destinationChainId"],
            "chainId": terms["sourceChainId"],
            "amount": terms["destinationAmount"],
            "asset": terms["destinationAsset"],
            "payer": terms["payer"],
            "recipient": terms["recipient"],
            "expiry": terms["expiry"],
        },
        "secrets": secrets or {},
    }
    if route is not None:
        payload["route"] = route
    return payload


def create_pull_payload(**kwargs: Any) -> dict[str, Any]:
    secret = kwargs.pop("secret", "")
    route = kwargs.pop("route", None)
    terms = make_terms(mode="PULL", **kwargs)
    normalized_route = normalize_route(route, source_chain_id=terms["sourceChainId"], destination_chain_id=terms["destinationChainId"]) if route else None
    if terms["topology"] == "CROSS_CHAIN" and normalized_route is None:
        raise ValueError("cross-chain pull links require route")
    payload = base_payload("PULL", terms, {"secret": secret} if secret else {}, normalized_route)
    validate_payload(payload)
    return payload


def create_push_payload(**kwargs: Any) -> dict[str, Any]:
    claim_secret = kwargs.pop("claim_secret")
    gatekeeper = kwargs.pop("gatekeeper")
    route = kwargs.pop("route", None)
    terms = make_terms(mode="PUSH", gatekeeper=gatekeeper, **kwargs)
    normalized_route = normalize_route(route, source_chain_id=terms["sourceChainId"], destination_chain_id=terms["destinationChainId"]) if route else None
    if terms["topology"] == "CROSS_CHAIN" and normalized_route is None:
        raise ValueError("cross-chain push links require route")
    payload = base_payload("PUSH", terms, {"claimSecret": claim_secret}, normalized_route)
    payload["claim"] = {
        "claimSecretTransport": "fragment-only",
        "nullifierHash": nullifier_hash(payload["operationId"], claim_secret),
        "gatekeeper": terms["claimGatekeeper"],
    }
    validate_payload(payload)
    return payload


def create_pull_link(base_url: str, **kwargs: Any) -> str:
    return compose_link(base_url, create_pull_payload(**kwargs))


def create_push_link(base_url: str, **kwargs: Any) -> str:
    return compose_link(base_url, create_push_payload(**kwargs))


def create_crosschain_pull_link(base_url: str, **kwargs: Any) -> str:
    if "source_chain_id" not in kwargs or "destination_chain_id" not in kwargs:
        raise ValueError("cross-chain pull requires source_chain_id and destination_chain_id")
    return compose_link(base_url, create_pull_payload(**kwargs))


def create_crosschain_push_link(base_url: str, **kwargs: Any) -> str:
    if "source_chain_id" not in kwargs or "destination_chain_id" not in kwargs:
        raise ValueError("cross-chain push requires source_chain_id and destination_chain_id")
    return compose_link(base_url, create_push_payload(**kwargs))


def receipt_final_hash(receipt: dict[str, Any]) -> str:
    tmp = {k: v for k, v in receipt.items() if k != "finalReceiptHash"}
    return "0x" + hashlib.sha256(RECEIPT_DOMAIN.encode() + canon(tmp)).hexdigest()


def create_receipt_payload(receipt_path: pathlib.Path) -> dict[str, Any]:
    receipt = json.loads(pathlib.Path(receipt_path).read_text())
    payload = {
        "schemaVersion": LINK_SCHEMA_VERSION,
        "kind": "RECEIPT",
        "topology": receipt.get("topology"),
        "operationId": receipt.get("operationId"),
        "receipt": {
            "path": str(pathlib.Path(receipt_path).as_posix()),
            "schemaVersion": receipt.get("schemaVersion"),
            "mode": receipt.get("mode"),
            "status": receipt.get("status"),
            "topology": receipt.get("topology"),
            "finalReceiptHash": receipt.get("finalReceiptHash"),
            "termsHash": receipt.get("termsHash"),
        },
    }
    validate_payload(payload)
    return payload


def create_receipt_link(base_url: str, receipt_path: pathlib.Path | str) -> str:
    return compose_link(base_url, create_receipt_payload(pathlib.Path(receipt_path)))


def verify_receipt_link(payload: dict[str, Any], root: pathlib.Path) -> dict[str, Any]:
    if payload.get("kind") != "RECEIPT":
        raise ValueError("not a receipt link")
    path = pathlib.Path(payload["receipt"]["path"])
    if not path.is_absolute():
        path = root / path
    receipt = json.loads(path.read_text())
    expected = receipt_final_hash(receipt)
    ok = expected == receipt.get("finalReceiptHash") == payload["receipt"].get("finalReceiptHash")
    return {"ok": ok, "expectedFinalReceiptHash": expected, "finalReceiptHash": receipt.get("finalReceiptHash"), "path": str(path)}


def public_index_record(payload: dict[str, Any]) -> dict[str, Any]:
    validate_payload(payload)
    record = {
        "schemaVersion": LINK_SCHEMA_VERSION,
        "kind": payload["kind"],
        "topology": payload.get("topology"),
        "operationId": payload.get("operationId"),
    }
    if payload["kind"] in ("PULL", "PUSH"):
        terms = payload["terms"]
        record.update({
            "termsHash": payload["termsHash"],
            "chainId": terms["sourceChainId"],
            "sourceChainId": terms["sourceChainId"],
            "destinationChainId": terms["destinationChainId"],
            "mode": terms["mode"],
            "asset": terms["destinationAsset"],
            "amount": terms["destinationAmount"],
            "expiry": terms["expiry"],
        })
        if payload.get("route"):
            record.update({
                "sourceApplication": payload["route"]["sourceApplication"],
                "destinationApplication": payload["route"]["destinationApplication"],
                "adapter": payload["route"]["adapter"],
                "destinationEid": payload["route"]["destinationEid"],
                "gasLimit": payload["route"]["gasLimit"],
                "routeHash": payload["route"]["routeHash"],
            })
        if payload["kind"] == "PUSH":
            record["nullifierHash"] = payload["claim"]["nullifierHash"]
    elif payload["kind"] == "RECEIPT":
        record["finalReceiptHash"] = payload["receipt"]["finalReceiptHash"]
        record["status"] = payload["receipt"].get("status")
    return record


def write_json(path: str | None, obj: Any) -> None:
    text = json.dumps(obj, indent=2, sort_keys=True) + "\n"
    if path:
        p = pathlib.Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    else:
        print(text, end="")


def add_common_terms_args(p: argparse.ArgumentParser, *, crosschain: bool = False) -> None:
    p.add_argument("--base-url", required=True)
    if crosschain:
        p.add_argument("--source-chain-id", required=True, type=int)
        p.add_argument("--destination-chain-id", required=True, type=int)
        p.add_argument("--source-application", required=True)
        p.add_argument("--destination-application", required=True)
        p.add_argument("--adapter", required=True)
        p.add_argument("--destination-eid", required=True, type=int)
        p.add_argument("--gas-limit", required=True, type=int)
        p.add_argument("--proof", default="AUTHENTICATED_ADAPTER")
    else:
        p.add_argument("--chain-id", required=True, type=int)
    p.add_argument("--router", required=True)
    p.add_argument("--vault", required=True)
    p.add_argument("--source-asset", required=True)
    p.add_argument("--destination-asset", required=True)
    p.add_argument("--payer", required=True)
    p.add_argument("--recipient", required=True)
    p.add_argument("--recovery", required=True)
    p.add_argument("--provider", required=True)
    p.add_argument("--maximum-input", required=True)
    p.add_argument("--destination-amount", required=True)
    p.add_argument("--protocol-fee", default="0")
    p.add_argument("--provider-fee", default="0")
    p.add_argument("--referrer-fee", default="0")
    p.add_argument("--gas-sponsor-fee", default="0")
    p.add_argument("--expiry", required=True, type=int)
    p.add_argument("--nonce", required=True, type=int)
    p.add_argument("--out")


def kwargs_from_args(a: argparse.Namespace) -> dict[str, Any]:
    kwargs = {
        "router": a.router,
        "vault": a.vault,
        "source_asset": a.source_asset,
        "destination_asset": a.destination_asset,
        "payer": a.payer,
        "recipient": a.recipient,
        "recovery": a.recovery,
        "provider": a.provider,
        "maximum_input": a.maximum_input,
        "destination_amount": a.destination_amount,
        "fees": {"protocol": a.protocol_fee, "provider": a.provider_fee, "referrer": a.referrer_fee, "gasSponsor": a.gas_sponsor_fee},
        "expiry": a.expiry,
        "nonce": a.nonce,
    }
    if hasattr(a, "source_chain_id"):
        kwargs["source_chain_id"] = a.source_chain_id
        kwargs["destination_chain_id"] = a.destination_chain_id
        kwargs["route"] = {
            "sourceApplication": a.source_application,
            "destinationApplication": a.destination_application,
            "adapter": a.adapter,
            "destinationEid": a.destination_eid,
            "gasLimit": a.gas_limit,
            "proof": a.proof,
        }
    else:
        kwargs["chain_id"] = a.chain_id
    return kwargs


def emit_link(out: str | None, base_url: str, payload: dict[str, Any]) -> None:
    write_json(out, {"link": compose_link(base_url, payload), "payload": payload, "publicIndex": public_index_record(payload)})


def main() -> None:
    ap = argparse.ArgumentParser(description="Glyph link protocol helper")
    sub = ap.add_subparsers(dest="cmd", required=True)

    pull = sub.add_parser("pull")
    pull_sub = pull.add_subparsers(dest="subcmd", required=True)
    pull_create = pull_sub.add_parser("create")
    add_common_terms_args(pull_create)
    pull_create.add_argument("--secret", default="")

    push = sub.add_parser("push")
    push_sub = push.add_subparsers(dest="subcmd", required=True)
    push_create = push_sub.add_parser("create")
    add_common_terms_args(push_create)
    push_create.add_argument("--gatekeeper", required=True)
    push_create.add_argument("--claim-secret", required=True)

    cross = sub.add_parser("crosschain")
    cross_sub = cross.add_subparsers(dest="crosscmd", required=True)
    cross_pull = cross_sub.add_parser("pull")
    cross_pull_sub = cross_pull.add_subparsers(dest="subcmd", required=True)
    cross_pull_create = cross_pull_sub.add_parser("create")
    add_common_terms_args(cross_pull_create, crosschain=True)
    cross_pull_create.add_argument("--secret", default="")
    cross_push = cross_sub.add_parser("push")
    cross_push_sub = cross_push.add_subparsers(dest="subcmd", required=True)
    cross_push_create = cross_push_sub.add_parser("create")
    add_common_terms_args(cross_push_create, crosschain=True)
    cross_push_create.add_argument("--gatekeeper", required=True)
    cross_push_create.add_argument("--claim-secret", required=True)

    rec = sub.add_parser("receipt")
    rec_sub = rec.add_subparsers(dest="subcmd", required=True)
    rec_create = rec_sub.add_parser("create")
    rec_create.add_argument("--base-url", required=True)
    rec_create.add_argument("--receipt", required=True)
    rec_create.add_argument("--out")

    inspect = sub.add_parser("inspect")
    inspect.add_argument("link")
    inspect.add_argument("--out")

    index = sub.add_parser("index")
    index.add_argument("link")
    index.add_argument("--out")

    verify = sub.add_parser("verify-receipt")
    verify.add_argument("link")
    verify.add_argument("--root", default=".")
    verify.add_argument("--out")

    a = ap.parse_args()
    if a.cmd == "pull" and a.subcmd == "create":
        emit_link(a.out, a.base_url, create_pull_payload(**kwargs_from_args(a), secret=a.secret))
    elif a.cmd == "push" and a.subcmd == "create":
        emit_link(a.out, a.base_url, create_push_payload(**kwargs_from_args(a), gatekeeper=a.gatekeeper, claim_secret=a.claim_secret))
    elif a.cmd == "crosschain" and a.crosscmd == "pull" and a.subcmd == "create":
        emit_link(a.out, a.base_url, create_pull_payload(**kwargs_from_args(a), secret=a.secret))
    elif a.cmd == "crosschain" and a.crosscmd == "push" and a.subcmd == "create":
        emit_link(a.out, a.base_url, create_push_payload(**kwargs_from_args(a), gatekeeper=a.gatekeeper, claim_secret=a.claim_secret))
    elif a.cmd == "receipt" and a.subcmd == "create":
        payload = create_receipt_payload(pathlib.Path(a.receipt))
        emit_link(a.out, a.base_url, payload)
    elif a.cmd == "inspect":
        write_json(a.out, decode_link(a.link))
    elif a.cmd == "index":
        write_json(a.out, public_index_record(decode_link(a.link)))
    elif a.cmd == "verify-receipt":
        result = verify_receipt_link(decode_link(a.link), pathlib.Path(a.root))
        write_json(a.out, result)
        sys.exit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
