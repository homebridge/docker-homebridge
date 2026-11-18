#!/usr/bin/env bash
# Checks on the text of the Dockerfile. The real build checks are in
# test/container/build-checks.sh.
# shellcheck shell=bash disable=SC2016,SC2154

test_dockerfile_downloads_are_checked() {
  assert_contains "$REPO/Dockerfile" 'sha256sum -c -' "s6-overlay checksum check"
  assert_contains "$REPO/Dockerfile" 'signed-by=/usr/share/keyrings/homebridge.asc' "signed apt repository"
  if grep -Eq 'curl[^|&]*\|[[:space:]]*tar' "$REPO/Dockerfile"; then fail "a download is piped straight into tar"; else ok; fi
  if grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$REPO/build/homebridge-apt-key.asc"; then ok; else fail "the apt key file is missing"; fi
}

test_dockerfile_s6_checksums_match_the_version() {
  # the four checksums belong to one s6-overlay version: changing the version
  # without the checksums must be noticed in review
  assert_contains "$REPO/Dockerfile" 'S6_OVERLAY_VERSION=3.2.0.2'
  assert_contains "$REPO/Dockerfile" 'S6_OVERLAY_SHA256_NOARCH=6dbcde158a3e78b9bb141d7bcb5ccb421e563523babbe2c64470e76f4fd02dae'
}
