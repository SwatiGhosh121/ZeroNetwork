#!/bin/bash
# HTTPS verification: strict TLS against our own CA.
set -e
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
echo "=== HTTPS / TLS TEST ==="
OUT=$(openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" -CAfile "$CA" </dev/null 2>/dev/null)
echo "$OUT" | grep -E "subject=|issuer=|Verify return code"
echo "$OUT" | grep -q "Verify return code: 0" && echo "[PASS] certificate verifies" || { echo "[FAIL] verify"; exit 1; }
curl -sv --cacert "$CA" "https://$DOMAIN/api/status" 2>&1 | grep -E "SSL connection|ALPN|subjectAltName|SSL certificate verify|HTTP/"
echo "=== HTTPS TEST PASSED ==="
