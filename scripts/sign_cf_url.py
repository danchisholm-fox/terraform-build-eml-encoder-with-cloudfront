#!/usr/bin/env python3
import argparse
import base64
import hashlib
import json
import sys
import time
from urllib.parse import urlparse, urlunparse, urlencode, parse_qsl

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


def sign_policy(key, policy: str) -> str:
    signature = key.sign(policy.encode("utf-8"), padding.PKCS1v15(), hashes.SHA1())
    return cloudfront_safe_b64(signature)


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


def main():
    parser = argparse.ArgumentParser(description="Generate a CloudFront signed URL")
    parser.add_argument("--domain", required=True, help="CloudFront domain name (e.g., dxxxxx.cloudfront.net)")
    parser.add_argument("--path", required=True, help="Path to object (e.g., /slates/slate-sky-5s.mp4)")
    parser.add_argument("--key-pair-id", required=True, help="CloudFront public key ID (Key-Pair-Id)")
    parser.add_argument("--private-key", required=True, help="Path to private key PEM")
    parser.add_argument("--expire-seconds", type=int, default=3600, help="Expiry in seconds from now (default 3600)")

    args = parser.parse_args()

    resource = f"https://{args.domain}{args.path}"
    expires = int(time.time()) + args.expire_seconds

    policy = build_canned_policy(resource, expires)
    key = load_private_key(args.private_key)
    signature = sign_policy(key, policy)

    # Signed URL params
    params = {
        "Expires": str(expires),
        "Key-Pair-Id": args.key_pair_id,
        "Signature": signature,
        "Policy": cloudfront_safe_b64(policy.encode("utf-8")),
    }

    parsed = urlparse(resource)
    query = dict(parse_qsl(parsed.query))
    query.update(params)
    signed_url = urlunparse(parsed._replace(query=urlencode(query)))
    print(signed_url)


if __name__ == "__main__":
    sys.exit(main())

