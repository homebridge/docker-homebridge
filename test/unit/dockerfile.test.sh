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

test_dockerfile_does_not_add_to_source_sh() {
  # the apt package's source.sh already loads source-docker.sh
  if grep -q '>> /opt/homebridge/source.sh' "$REPO/Dockerfile"; then fail "the Dockerfile appends to /opt/homebridge/source.sh"; else ok; fi
  assert_contains "$REPO/Dockerfile" "does not load source-docker.sh" "build check that the apt package loads the file"
  assert_eq "$(grep -c '^ *\. /opt/homebridge/source-docker.sh' "$UNIT_DIR/fixtures/source.sh")" "1" "times the apt package source.sh loads source-docker.sh"
}

test_s6_dependencies_name_real_services() {
  # each file in a dependencies.d folder must be the name of a service
  local dir="$REPO/rootfs/etc/s6-overlay/s6-rc.d" dep
  for dep in "$dir"/*/dependencies.d/* "$dir"/user/contents.d/*; do
    if [ -d "$dir/$(basename "$dep")" ]; then ok; else fail "'$dep' is not the name of a service"; fi
  done
  assert_eq "$(find "$dir" -name dependencies -type f | wc -l | tr -d ' ')" "0" "old one-file dependency lists"
  assert_eq "$(find "$dir/homebridge/dependencies.d" -type f -exec basename {} \; | sort | tr '\n' ' ')" "avahi dbus setup userdata " "homebridge starts after"
}

test_dockerfile_homebridge_user_has_fixed_numbers() {
  assert_contains "$REPO/Dockerfile" 'ARG HOMEBRIDGE_UID=858'
  assert_contains "$REPO/Dockerfile" 'ARG HOMEBRIDGE_GID=858'
  assert_contains "$REPO/Dockerfile" 'useradd --system --uid "${HOMEBRIDGE_UID}" --gid homebridge' "the user is made before the package is installed"
  # the user must exist before apt installs the package, or the package picks the numbers
  local useradd_line install_line
  useradd_line=$(grep -n 'useradd --system' "$REPO/Dockerfile" | head -1 | cut -d: -f1)
  install_line=$(grep -n 'apt-get install -y --no-install-recommends "homebridge=' "$REPO/Dockerfile" | head -1 | cut -d: -f1)
  if [ -n "$useradd_line" ] && [ -n "$install_line" ] && [ "$useradd_line" -lt "$install_line" ]; then ok; else fail "useradd (line ${useradd_line:-?}) must come before the package install (line ${install_line:-?})"; fi
}
