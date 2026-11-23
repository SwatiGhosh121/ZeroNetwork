#!/bin/bash
# Caching: Cache-Control + ETag on 200, then 304 on a conditional request.
set -e
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
URL="https://$DOMAIN/api/cached"
HDR=$(curl -sI --cacert "$CA" "$URL" | tr -d '\r'); echo "$HDR"
ETAG=$(echo "$HDR" | awk -F': ' 'tolower($1)=="etag"{print $2}')
echo "$HDR" | grep -qi "cache-control: public, max-age=60" && echo "[PASS] Cache-Control" || { echo "[FAIL] Cache-Control"; exit 1; }
for i in 1 2 3 4; do
  CODE=$(curl -s --cacert "$CA" -o /dev/null -w "%{http_code}" -H "If-None-Match: $ETAG" "$URL")
  echo "conditional request $i -> $CODE"; [ "$CODE" = "304" ] || { echo "[FAIL]"; exit 1; }
done
echo "[PASS] 304 from whichever backend answers (same ETag on A and B)"
