#!/bin/bash
# Runs the Phase 1 verification suites in order.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSED=0; TOTAL=4
for t in dns https load-balancing caching; do
  echo "------------------------------------------------------------------"
  echo "TEST: $t"
  if bash "$DIR/$t-test.sh"; then echo ">> $t PASSED"; PASSED=$((PASSED+1)); else echo ">> $t FAILED"; fi
done
echo "=================================================================="
echo "RESULT: $PASSED / $TOTAL passed"
[ "$PASSED" -eq "$TOTAL" ]
