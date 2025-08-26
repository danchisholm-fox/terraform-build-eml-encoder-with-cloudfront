#!/usr/bin/env python3
import argparse
import base64
import json
import sys
import time
from http.cookies import SimpleCookie

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend


def cloudfront_safe_b64(raw: bytes) -> str:
    # CloudFront-safe base64 per AWS docs:
    # replace '+' with '-', '=' with '_', and '/' with '~'
    b64 = base64.b64encode(raw).decode("utf-8")
    return b64.replace("+", "-").replace("=", "_").replace("/", "~")


def load_private_key(pem_path: str):
    with open(pem_path, "rb") as f:
        key_data = f.read()
    return serialization.load_pem_private_key(key_data, password=None, backend=default_backend())


def build_canned_policy(resource_url: str, expires_unix: int) -> str:
    policy = {
        "Statement": [
            {
                "Resource": resource_url,
                "Condition": {"DateLessThan": {"AWS:EpochTime": expires_unix}},
            }
        ]
    }
    return json.dumps(policy, separators=(",", ":"))


def sign_policy(key, policy: str) -> str:
    signature = key.sign(policy.encode("utf-8"), padding.PKCS1v15(), hashes.SHA1())
    return cloudfront_safe_b64(signature)


def main():
    parser = argparse.ArgumentParser(description="Generate CloudFront signed cookies for HLS playback")
    parser.add_argument("--resource", required=True, help="Resource pattern, e.g., https://dxxx.cloudfront.net/*")
    parser.add_argument("--key-pair-id", required=True, help="CloudFront public key ID (Key-Pair-Id)")
    parser.add_argument("--private-key", required=True, help="Path to private key PEM")
    parser.add_argument("--expire-seconds", type=int, default=3600, help="Expiry in seconds from now (default 3600)")
    parser.add_argument("--cookie-domain", required=False, help="Optional cookie Domain attribute (e.g., .example.com)")
    parser.add_argument("--cookie-path", default="/", help="Cookie Path attribute (default /)")
    parser.add_argument("--format", choices=["text", "json"], default="text", help="Output format (text or json)")

    args = parser.parse_args()

    expires = int(time.time()) + args.expire_seconds
    policy = build_canned_policy(args.resource, expires)
    key = load_private_key(args.private_key)
    signature = sign_policy(key, policy)

    # Construct cookies (values without attributes)
    cookies = {
        "CloudFront-Policy": cloudfront_safe_b64(policy.encode("utf-8")),
        "CloudFront-Signature": signature,
        "CloudFront-Key-Pair-Id": args.key_pair_id,
    }

    if args.format == "json":
        out = {
            "resource": args.resource,
            "expires": expires,
            "cookies": cookies,
            "cookie_attributes": {
                "path": args.cookie_path,
                "domain": args.cookie_domain if args.cookie_domain else None,
                "secure": True,
                "httponly": True,
            },
        }
        print(json.dumps(out))
        return 0

    # text output with Set-Cookie lines and curl example
    ck = SimpleCookie()
    for k, v in cookies.items():
        ck[k] = v
    for name in cookies.keys():
        morsel = ck[name]
        morsel["path"] = args.cookie_path
        if args.cookie_domain:
            morsel["domain"] = args.cookie_domain
        morsel["secure"] = True
        morsel["httponly"] = True

    print("\n# Set-Cookie headers:")
    for m in ck.values():
        print(f"Set-Cookie: {m.OutputString()}")

    print("\n# curl example:")
    hdrs = " ".join([f"-H 'Cookie: {m.key}={m.value}'" for m in ck.values()])
    print(f"curl {hdrs} '<HLS_MANIFEST_URL>'")

    return 0


if __name__ == "__main__":
    sys.exit(main())

