#!/bin/bash
# Load balancing: 20 requests must hit both backends in round-robin order.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
A=0; B=0
for i in $(seq 1 20); do
  R=$(curl -s --cacert "$CA" "https://$DOMAIN/api/status" -D - -o /dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="x-backend"{print $2}')
  echo "request $i -> backend $R"
  [ "$R" = "A" ] && A=$((A+1)); [ "$R" = "B" ] && B=$((B+1))
done
echo "A=$A B=$B"
[ "$A" -gt 0 ] && [ "$B" -gt 0 ] && echo "[PASS] both backends served" || { echo "[FAIL]"; exit 1; }
