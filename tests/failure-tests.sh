#!/bin/bash
# Layered diagnosis: DNS -> TCP -> TLS -> HTTP. The first failing layer is the fault.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
echo "== 1. DNS";  dig +short +time=2 +tries=1 "$DOMAIN"
echo "== 2. TCP";  nc -vz -G 3 "$DOMAIN" 443
echo "== 3. TLS";  openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" -CAfile "$CA" </dev/null 2>/dev/null | grep -E "subject=|issuer=|Verify return code"
echo "== 4. HTTP"; curl -s --cacert "$CA" -o /dev/null -w "HTTP %{http_code}\n" "https://$DOMAIN/api/status"
