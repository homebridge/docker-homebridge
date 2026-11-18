#!/usr/bin/env bash
# Runs the sandbox tests: every test_* function in test/unit/*.test.sh.
#
# Usage: test/unit/run.sh [name filter]
# Needs: bash, jq, git and a POSIX sh (dash is used when it is installed).

set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
# shellcheck source=test/unit/lib.sh
. ./lib.sh

FILTER="${1:-}"
TOTAL=0
BAD=0

for file in ./*.test.sh; do
  # shellcheck disable=SC1090
  . "$file"
done

for t in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
  if [ -n "$FILTER" ] && [[ "$t" != *"$FILTER"* ]]; then continue; fi
  TOTAL=$((TOTAL + 1))
  before=$FAILED
  "$t"
  if [ "$FAILED" -eq "$before" ]; then
    echo "ok   $t"
  else
    BAD=$((BAD + 1))
    echo "FAIL $t"
  fi
done

rm -rf "$WORK"
echo
echo "$TOTAL tests, $CHECKS checks passed, $FAILED checks failed"
[ "$BAD" -eq 0 ]
