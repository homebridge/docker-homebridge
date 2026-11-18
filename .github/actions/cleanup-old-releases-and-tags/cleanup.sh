#!/usr/bin/env bash
# Deletes the older GitHub releases (and their tags) of one release stream and
# keeps the newest ones.
#
# Usage: cleanup.sh <stream> <number to keep>
# Needs: gh (with GH_TOKEN set), jq.
#
# Only tags in the release tag form of that stream are looked at:
#   stable        YYYY-MM-DD
#   other streams <stream>-YYYY-MM-DD
# So a tag of another stream, or any other tag, is never deleted.

set -u

RELEASE_TYPE="${1:?stream missing}"
RELEASES_TO_KEEP="${2:?number of releases to keep missing}"

case "$RELEASES_TO_KEEP" in
  '' | *[!0-9]* | 0)
    echo "::error::releases-to-keep must be a number above 0, got '${RELEASES_TO_KEEP}'"
    exit 1
    ;;
esac

if [[ "$RELEASE_TYPE" == "stable" ]]; then
  PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
else
  PATTERN="^${RELEASE_TYPE}-[0-9]{4}-[0-9]{2}-[0-9]{2}\$"
fi

echo "::group::Finding releases for $RELEASE_TYPE"
if ! RELEASE_LIST=$(gh release list --limit 100 --json tagName); then
  echo "::endgroup::"
  echo "::error::Could not read the release list"
  exit 1
fi
# newest first: the date in the tag sorts as text
RELEASES=$(jq -r --arg pattern "$PATTERN" '.[].tagName | select(test($pattern))' <<< "$RELEASE_LIST" | sort -r)
echo "Found releases:"
echo "$RELEASES"
DELETE_TAGS=$(echo "$RELEASES" | tail -n "+$((RELEASES_TO_KEEP + 1))")
echo "::endgroup::"

if [[ -z "$DELETE_TAGS" ]]; then
  echo "::notice::No old $RELEASE_TYPE releases to delete."
  exit 0
fi

DELETE_COUNT=0
echo "::group::Deleting old $RELEASE_TYPE releases and tags"
for TAG in $DELETE_TAGS; do
  echo "Deleting release and tag: $TAG"
  if gh release delete "$TAG" --cleanup-tag --yes; then
    DELETE_COUNT=$((DELETE_COUNT + 1))
  else
    echo "::warning::Failed to delete $TAG"
  fi
done
echo "::notice::$DELETE_COUNT $RELEASE_TYPE releases/tags deleted."
echo "::endgroup::"
