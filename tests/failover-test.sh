#!/bin/bash
# Phase 2 Ext D: run this on the client while backend A is stopped on MAC-3.
# Every line should be 200, served by B, with no failures.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
for i in $(seq 1 40); do
  curl -s --cacert "$CA" -o /dev/null -w "$(date +%T)  %{http_code}  backend=%header{x-backend}  edge=%header{x-edge}\n" "https://$DOMAIN/api/status"
  sleep 1
done
