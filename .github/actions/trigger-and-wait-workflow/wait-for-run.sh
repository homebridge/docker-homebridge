#!/usr/bin/env bash
# Waits for a workflow run to finish.
#
# Usage: wait-for-run.sh <run id> <name for messages> <timeout in minutes>
# Needs: gh (with GH_TOKEN set).
#
# Exit code 0 only when the run ended with "success". A failed run, a
# cancelled run, a timeout and an unknown status all give exit code 1, so the
# calling job is red when the release did not happen.

set -u

RUN_ID="${1:?run id missing}"
NAME="${2:-workflow}"
TIMEOUT_MINUTES="${3:-30}"
POLL_SECONDS="${POLL_SECONDS:-30}"

case "$TIMEOUT_MINUTES" in
  '' | *[!0-9]*)
    echo "::error::timeout-minutes must be a whole number, got '${TIMEOUT_MINUTES}'"
    exit 1
    ;;
esac

MAX_WAIT_SECONDS=$((TIMEOUT_MINUTES * 60))
START_TIME=$(date +%s)

echo "::notice::Waiting for ${NAME} workflow (run ${RUN_ID}) to complete..."

while true; do
  ELAPSED_TIME=$(($(date +%s) - START_TIME))

  if [[ $ELAPSED_TIME -gt $MAX_WAIT_SECONDS ]]; then
    echo "::error::${NAME} workflow timed out after ${TIMEOUT_MINUTES} minutes"
    exit 1
  fi

  if ! STATUS=$(gh run view "$RUN_ID" --json status -q '.status'); then
    echo "::warning::Could not read the status of run ${RUN_ID}, trying again..."
    sleep "$POLL_SECONDS"
    continue
  fi

  case "$STATUS" in
    completed)
      CONCLUSION=$(gh run view "$RUN_ID" --json conclusion -q '.conclusion')
      if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "conclusion=${CONCLUSION}" >> "$GITHUB_OUTPUT"
      fi
      if [[ "$CONCLUSION" == "success" ]]; then
        echo "::notice::${NAME} workflow completed successfully"
        exit 0
      fi
      echo "::error::${NAME} workflow failed with conclusion: ${CONCLUSION}"
      exit 1
      ;;
    in_progress | queued | requested | waiting | pending)
      echo "::notice::${NAME} workflow status: ${STATUS} - continuing to wait... (elapsed: ${ELAPSED_TIME}s)"
      sleep "$POLL_SECONDS"
      ;;
    *)
      echo "::error::${NAME} workflow has unexpected status: ${STATUS}"
      exit 1
      ;;
  esac
done
