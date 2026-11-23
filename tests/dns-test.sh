#!/bin/bash
# DNS verification: app.zeronetwork.test must resolve to the edge through our private DNS.
set -e
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
echo "=== DNS RESOLUTION TEST ==="
echo "Target: $DOMAIN   Expected: $EDGE_IP"
for NS in "$DNS_PRIMARY" "$DNS_BACKUP"; do
  GOT=$(dig +short +time=2 +tries=1 @"$NS" "$DOMAIN" | tail -n1)
  if [ "$GOT" = "$EDGE_IP" ]; then echo "[PASS] @$NS -> $GOT"; else echo "[FAIL] @$NS -> '$GOT'"; exit 1; fi
done
echo; echo "TTL check (expect 30):"
dig +noall +answer @"$DNS_PRIMARY" "$DOMAIN"
echo; echo "Unknown name (expect NXDOMAIN):"
dig @"$DNS_PRIMARY" nope.zeronetwork.test | grep -E "status:"
echo "=== DNS TEST PASSED ==="
