#!/usr/bin/env bash
# Build checks: a download that does not match its checksum or its signature
# must stop the image build.
#
# Usage: test/container/build-checks.sh <stream>      (stable, beta, alpha, legacy or synology)
# Needs: docker with BuildKit, jq, and the network.
#
# Run it after a normal build of the same stream, so the first layers come
# from the build cache.

set -u

STREAM="${1:-stable}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO" || exit 1

if [ "$STREAM" = "stable" ]; then PKG_FILE=package.json; else PKG_FILE="$STREAM/package.json"; fi
ARGS=(
  --build-arg "HOMEBRIDGE_APT_PKG_VERSION=v$(jq -r '.dependencies["@homebridge/homebridge-apt-pkg"]' "$PKG_FILE")"
  --build-arg "FFMPEG_FOR_HOMEBRIDGE_VERSION=v$(jq -r '.dependencies["ffmpeg-for-homebridge"]' "$PKG_FILE")"
  --build-arg "DOCKER_HOMEBRIDGE_VERSION=build-check"
  --build-arg "BASE_IMAGE=$(jq -r '.docker.baseImage' "$PKG_FILE")"
)
FAILED=0
ZEROS=0000000000000000000000000000000000000000000000000000000000000000

# must_fail <what> <text expected in the output> <docker build arguments ...>
must_fail() {
  local what="$1" expect="$2" out
  shift 2
  if out=$(docker build "${ARGS[@]}" "$@" . 2>&1); then
    echo "FAIL $what: the build passed"
    FAILED=1
  elif ! printf '%s\n' "$out" | grep -q -- "$expect"; then
    echo "FAIL $what: the build failed, but not with '$expect'"
    printf '%s\n' "$out" | tail -15 | sed 's/^/     | /'
    FAILED=1
  else
    echo "ok   $what"
  fi
}

must_fail "s6-overlay (noarch) with a wrong checksum stops the build" "s6-overlay-noarch.tar.xz: FAILED" \
  --build-arg "S6_OVERLAY_SHA256_NOARCH=$ZEROS"

must_fail "s6-overlay (CPU part) with a wrong checksum stops the build" "computed checksum did NOT match" \
  --build-arg "S6_OVERLAY_SHA256_X86_64=$ZEROS" --build-arg "S6_OVERLAY_SHA256_AARCH64=$ZEROS" --build-arg "S6_OVERLAY_SHA256_ARMHF=$ZEROS"

# a different public key: apt must refuse the homebridge repository
WRONG_CONTEXT=$(mktemp -d)
trap 'rm -rf "$WRONG_CONTEXT"' EXIT
cp -R Dockerfile rootfs build "$WRONG_CONTEXT/"
docker run --rm --entrypoint /bin/sh "$(jq -r '.docker.baseImage' "$PKG_FILE")" -c \
  'apt-get update -qq > /dev/null 2>&1 && apt-get install -y -qq gnupg > /dev/null 2>&1 && gpg --batch --quiet --passphrase "" --quick-generate-key "wrong key <wrong@example.invalid>" rsa2048 sign never > /dev/null 2>&1 && gpg --armor --export' \
  > "$WRONG_CONTEXT/build/homebridge-apt-key.asc"
if ! grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$WRONG_CONTEXT/build/homebridge-apt-key.asc"; then
  echo "FAIL could not make a test key"
  FAILED=1
else
  REPO_SAVE="$REPO"
  cd "$WRONG_CONTEXT" || exit 1
  must_fail "a homebridge package that is not signed with our key stops the build" "NO_PUBKEY\|not signed\|Missing key\|no public key"
  cd "$REPO_SAVE" || exit 1
fi

exit "$FAILED"
