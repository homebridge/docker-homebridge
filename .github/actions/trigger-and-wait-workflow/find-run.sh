#!/usr/bin/env bash
# Finds the workflow run that was just started with "gh workflow run".
#
# Usage: find-run.sh <workflow file> <branch> <text in the run name> <newest run id before the trigger>
# Needs: gh (with GH_TOKEN set).
#
# Prints the run id. Only a run that is newer than the given run id counts, so
# the run of the day before (same branch, same name) is never picked.
# Exit code 1 when no such run shows up in time.

set -u

WORKFLOW_FILE="${1:?workflow file missing}"
REF="${2:?branch missing}"
RUN_NAME="${3:-}"
AFTER_ID="${4:-0}"
MAX_RETRIES="${MAX_RETRIES:-24}"
RETRY_SECONDS="${RETRY_SECONDS:-5}"

case "$AFTER_ID" in
  '' | *[!0-9]*) AFTER_ID=0 ;;
esac

attempt=0
while [[ $attempt -lt $MAX_RETRIES ]]; do
  attempt=$((attempt + 1))

  RUN_ID=$(gh run list --workflow "$WORKFLOW_FILE" \
    --event workflow_dispatch \
    --branch "$REF" \
    --limit 10 \
    --json databaseId,name \
    | jq -r --arg name "$RUN_NAME" --argjson after "$AFTER_ID" \
      '[.[] | select(.databaseId > $after) | select(.name | contains($name))] | sort_by(.databaseId) | .[0].databaseId // empty')

  if [[ -n "$RUN_ID" ]]; then
    echo "::notice::Found ${RUN_NAME} workflow run: ${RUN_ID}" >&2
    echo "$RUN_ID"
    exit 0
  fi

  echo "::notice::Retry ${attempt}/${MAX_RETRIES}: ${RUN_NAME} workflow run not found yet. Retrying in ${RETRY_SECONDS} seconds..." >&2
  sleep "$RETRY_SECONDS"
done

echo "::error::Could not find the triggered ${RUN_NAME} workflow run" >&2
gh run list --workflow "$WORKFLOW_FILE" --event workflow_dispatch --branch "$REF" --limit 5 --json databaseId,name,createdAt >&2
exit 1
