#!/usr/bin/env bash
# Works out which branch a release stream is built from.
#
# Usage: resolve-stream-branch.sh <stream>
# Needs: gh (with GH_TOKEN set) and GITHUB_REPOSITORY.
#
# - beta and alpha build from the newest <stream>-YYYY.M.D branch when one
#   exists (for example beta-2026.11.18). Everything else builds from latest.
# - Prints the branch name. In a workflow it is also written to $GITHUB_OUTPUT.
# - Warns when such a branch does not hold all changes of latest: until latest
#   is merged into it (or the branch is deleted) that stream is built from
#   older scripts.

set -u

STREAM="${1:?stream missing}"
BRANCH="latest"

if [[ "$STREAM" == "beta" || "$STREAM" == "alpha" ]]; then
  CANDIDATE=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/git/matching-refs/heads/${STREAM}-" \
    --jq '.[].ref | sub("^refs/heads/"; "")' \
    | grep -E "^${STREAM}-[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}$" \
    | sort -V | tail -n 1 || true)
  if [[ -n "$CANDIDATE" ]]; then
    BRANCH="$CANDIDATE"
  fi
fi

if [[ "$BRANCH" != "latest" ]]; then
  # Files that differ on latest since the branch left it. The daily version
  # changes of the dependency bot (the package.json files) do not count.
  MISSING=$(gh api "repos/${GITHUB_REPOSITORY}/compare/${BRANCH}...latest" \
    --jq '[.files[]?.filename | select(test("^((beta|alpha|legacy|synology)/)?package\\.json$") | not)] | length' || true)
  case "$MISSING" in
    '' | *[!0-9]*)
      echo "::warning::Could not compare ${BRANCH} with latest."
      ;;
    0) ;;
    *)
      echo "::warning::${BRANCH} does not have ${MISSING} file change(s) that are on latest. The ${STREAM} image is built from older scripts until latest is merged into ${BRANCH}, or ${BRANCH} is deleted after its work is merged."
      ;;
  esac
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "branch=${BRANCH}" >> "$GITHUB_OUTPUT"
fi
echo "::notice::${STREAM} stream builds from branch ${BRANCH}"
echo "$BRANCH"
