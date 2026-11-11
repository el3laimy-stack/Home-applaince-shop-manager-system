#!/usr/bin/env python3
"""No-network issuer verification. Executes with Python stdlib and OpenSSL."""
import base64
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
import license_admin as admin


class OfflineLicenseIssuerTest(unittest.TestCase):
    def test_issue_is_signed_and_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="pos-issuer-test-") as temp:
            root = Path(temp)
            keys = root / "keys"
            admin.generate(keys)
            public = keys / "issuer-public.pem"
            private = keys / "issuer-private.pem"
            self.assertTrue(public.is_file())
            self.assertTrue(private.is_file())
            self.assertEqual(private.stat().st_mode & 0o077, 0)
            license_path = root / "client.license"
            admin.issue(private, "متجر الاختبار", "A" * 64, license_path, "LIC-TEST-001", None)
            document = json.loads(license_path.read_text(encoding="utf-8"))
            payload = document["payload"]
            self.assertEqual(payload["customer"], "متجر الاختبار")
            self.assertEqual(payload["device_id"], "A" * 64)
            signature = base64.b64decode(document["signature"])
            self.assertEqual(len(signature), 64)
            canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True,
                                   separators=(",", ":")).encode("utf-8")
            message = admin.DOMAIN + canonical
            with tempfile.TemporaryDirectory(prefix="pos-sig-test-") as staging:
                message_file = Path(staging) / "signed.bin"
                sig_file = Path(staging) / "signature.bin"
                message_file.write_bytes(message)
                sig_file.write_bytes(signature)
                admin.openssl("pkeyutl", "-verify", "-pubin", "-inkey", public,
                              "-rawin", "-in", message_file, "-sigfile", sig_file)
                message_file.write_bytes(message.replace("متجر الاختبار".encode(),
                                                        "متجر آخر".encode()))
                with self.assertRaises(ValueError):
                    admin.openssl("pkeyutl", "-verify", "-pubin", "-inkey", public,
                                  "-rawin", "-in", message_file, "-sigfile", sig_file)
            with self.assertRaises(ValueError):
                admin.issue(private, "second", "A" * 64, license_path, None, None)
            with self.assertRaises(ValueError):
                admin.issue(private, "second", "abc", root / "wrong.license", None, None)


if __name__ == "__main__":
    unittest.main()
