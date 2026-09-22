#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="${WECHAT_CERT_DIR:-$ROOT_DIR/auth/1725975775_20260619_cert}"

APP_ID="${WECHAT_APP_ID:-wx81e9c1c8ad43aad2}"
MCH_ID="${WECHAT_MCH_ID:-1725975775}"
API_V3_KEY="${WECHAT_API_V3_KEY:-${WECHAT_API_KEY:-}}"

if [[ -z "$API_V3_KEY" ]]; then
  echo "请设置 WECHAT_API_V3_KEY（商户平台 -> API安全 -> APIv3密钥）" >&2
  exit 1
fi

CERT_FILE="$CERT_DIR/apiclient_cert.pem"
KEY_FILE="$CERT_DIR/apiclient_key.pem"

if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
  echo "证书目录不存在或缺少文件: $CERT_DIR" >&2
  exit 1
fi

SERIAL_NO="$(openssl x509 -in "$CERT_FILE" -noout -serial | sed 's/serial=//' | tr '[:lower:]' '[:upper:]')"
PRIVATE_KEY="$(cat "$KEY_FILE")"

python3 - <<'PY' "$APP_ID" "$MCH_ID" "$API_V3_KEY" "$SERIAL_NO" "$KEY_FILE"
import json, pathlib, sys
app_id, mch_id, api_v3_key, serial_no, key_file = sys.argv[1:]
private_key = pathlib.Path(key_file).read_text()
print(json.dumps({
    "app_id": app_id,
    "mch_id": mch_id,
    "api_v3_key": api_v3_key,
    "serial_no": serial_no,
    "private_key": private_key,
}, ensure_ascii=False, indent=2))
PY
