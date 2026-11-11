#!/usr/bin/env python3
"""Publisher-only Ed25519 license issuer. No private keys in Git or the app.

Requires Python 3 and OpenSSL 3 (bundled with most modern Linux distributions).

On a trusted machine, OUTSIDE THE REPOSITORY:
  python3 tool/license_admin.py generate --directory /secure/pos-license-keys
  python3 tool/license_admin.py issue \
    --private-key /secure/pos-license-keys/issuer-private.pem \
    --customer "Customer Name" --device-id AABB... --output /secure/issued/shop.license

Only the 32-byte public key (Base64) belongs in the Flutter release build.
"""
import argparse
import base64
import datetime as dt
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import tempfile


DOMAIN = b"ALIKHLAS-POS-LICENSE-V1\n"
SPKI_PREFIX = bytes.fromhex("302a300506032b6570032100")
REPO_ROOT = Path(__file__).resolve().parents[3]


def outside_repo(path: Path):
    path = path.expanduser().resolve()
    if path == REPO_ROOT or REPO_ROOT in path.parents:
        raise ValueError("Keep private keys and issued license files OUTSIDE Git checkout")
    return path


def openssl(*args, input_bytes=None):
    result = subprocess.run(
        ["openssl", *map(str, args)],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError("OpenSSL operation failed: " + result.stderr.decode(errors="replace"))
    return result.stdout


def generate(directory: Path):
    folder = outside_repo(directory)
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    private = folder / "issuer-private.pem"
    public = folder / "issuer-public.pem"
    if private.exists() or public.exists():
        raise ValueError("Key files exist already. Refusing to overwrite them.")
    # Only local trusted machine ever sees this private key.
    original_umask = os.umask(0o077)
    try:
        openssl("genpkey", "-algorithm", "Ed25519", "-out", private)
        os.chmod(private, 0o600)
        openssl("pkey", "-in", private, "-pubout", "-out", public)
    finally:
        os.umask(original_umask)
    der = openssl("pkey", "-pubin", "-in", public, "-outform", "DER")
    if not der.startswith(SPKI_PREFIX) or len(der) != len(SPKI_PREFIX) + 32:
        raise ValueError("Unexpected Ed25519 public key encoding")
    print("ALIKHLAS_LICENSE_PUBLIC_KEY=" + base64.b64encode(der[-32:]).decode())
    print("The private key remains at: " + str(private))


def issue(private: Path, customer: str, device_id: str, output: Path,
          license_id: str | None, expires_at: str | None):
    key = outside_repo(private)
    dest = outside_repo(output)
    if not key.is_file():
        raise ValueError("Private key not found")
    if dest.exists():
        raise ValueError("The destination already exists: " + str(dest))
    if not re.fullmatch(r"[A-F0-9]{64}", device_id):
        raise ValueError("Device ID must be 64 uppercase hexadecimal characters")
    if not customer.strip() or len(customer) > 180:
        raise ValueError("Invalid customer name")
    lid = license_id or secrets.token_hex(12)
    if not re.fullmatch(r"[a-zA-Z0-9_-]{8,80}", lid):
        raise ValueError("Invalid license ID")
    if expires_at is not None:
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", expires_at):
            raise ValueError("Expiry must be an ISO UTC timestamp, e.g. 2027-12-31T23:59:59Z")
        # Reject impossible dates.
        dt.datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
    issued = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    payload = {
        "product": "alikhlas-pos",
        "license_id": lid,
        "customer": customer.strip(),
        "device_id": device_id,
        "issued_at": issued.isoformat().replace("+00:00", "Z"),
        "expires_at": expires_at,
    }
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True,
                           separators=(",", ":")).encode("utf-8")
    with tempfile.TemporaryDirectory() as temp:
        data = Path(temp) / "payload.bin"
        signature_file = Path(temp) / "signature.bin"
        data.write_bytes(DOMAIN + canonical)
        openssl("pkeyutl", "-sign", "-rawin", "-inkey", key, "-in", data,
                "-out", signature_file)
        signature = signature_file.read_bytes()
    if len(signature) != 64:
        raise ValueError("OpenSSL did not produce an Ed25519 signature")
    document = {
        "format": "alikhlas-license-v1",
        "payload": payload,
        "signature": base64.b64encode(signature).decode(),
    }
    dest.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    dest.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8")
    print("Issued " + lid + " for " + customer + " to " + str(dest))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    gen = sub.add_parser("generate", help="Generate publisher keys OUTSIDE Git")
    gen.add_argument("--directory", type=Path, required=True)
    sign = sub.add_parser("issue", help="Issue one-device license")
    sign.add_argument("--private-key", type=Path, required=True)
    sign.add_argument("--customer", required=True)
    sign.add_argument("--device-id", required=True)
    sign.add_argument("--output", type=Path, required=True)
    sign.add_argument("--license-id")
    sign.add_argument("--expires-at")
    args = parser.parse_args()
    try:
        if args.command == "generate":
            generate(args.directory)
        else:
            issue(args.private_key, args.customer, args.device_id, args.output,
                  args.license_id, args.expires_at)
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()
