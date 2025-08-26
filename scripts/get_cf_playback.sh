#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/get_cf_playback.sh [cookies|url]
# Default mode is 'cookies'.
#
# Outputs (cookies mode):
#  - CF_EMP_URL: CloudFront HLS URL
#  - Set-Cookie lines to paste in browser DevTools
#
# Outputs (url mode):
#  - CF_BROWSER_URL: CloudFront signed URL (note: won't authorize child manifests; use cookies for HLS)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-cookies}"

# Ensure terraform outputs are accessible
CF_EMP_URL=$(terraform output -raw cloudfront_emp_playback_url)
CF_EMP_DOMAIN=$(terraform output -raw cloudfront_emp_domain_name)
CF_KEY_ID=$(terraform output -raw cloudfront_public_key_id)

# Ensure private key exists locally
PK_FILE="$ROOT_DIR/cf_private_key.pem"
if [ ! -f "$PK_FILE" ]; then
  terraform output -raw cloudfront_signer_private_key_pem > "$PK_FILE"
  chmod 600 "$PK_FILE"
fi

if [ "$MODE" = "cookies" ]; then
  # Generate cookies JSON
  COOKIES_JSON="$ROOT_DIR/cf_cookies.json"
  python3 "$ROOT_DIR/scripts/sign_cf_cookies.py" \
    --resource "https://$CF_EMP_DOMAIN/*" \
    --key-pair-id "$CF_KEY_ID" \
    --private-key "$PK_FILE" \
    --expire-seconds 3600 \
    --format json > "$COOKIES_JSON"

  echo "CF_EMP_URL=$CF_EMP_URL"
  echo "\nSet-Cookie headers (paste into browser DevTools → Application → Cookies → $CF_EMP_DOMAIN):"
  python3 - "$COOKIES_JSON" <<'PY'
import sys, json
with open(sys.argv[1]) as f:
  data=json.load(f)
cookies=data["cookies"]
for k,v in cookies.items():
  print(f"Set-Cookie: {k}={v}; Path=/; Secure; HttpOnly")
PY
  echo "\nOpen this URL after setting cookies:"
  echo "$CF_EMP_URL"
else
  # Fallback: single signed URL (note: child manifests require cookies)
  CF_BROWSER_URL=$(python3 "$ROOT_DIR/scripts/sign_cf_url.py" \
    --domain "$CF_EMP_DOMAIN" \
    --path "/index.m3u8" \
    --key-pair-id "$CF_KEY_ID" \
    --private-key "$PK_FILE" \
    --expire-seconds 3600)
  echo "CF_BROWSER_URL=$CF_BROWSER_URL"
  echo "$CF_BROWSER_URL"
fi

