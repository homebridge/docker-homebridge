#!/usr/bin/env bash
# Lints the shell scripts, the Dockerfile and the JSON files of this repository.
#
# Usage: test/lint.sh
# Needs: shellcheck, hadolint and jq. Set HADOLINT to another command to run
# hadolint from a container, for example:
#   HADOLINT="docker run --rm -i -v $PWD/.hadolint.yaml:/.config/hadolint.yaml hadolint/hadolint hadolint"

# The check functions below are called by name through run().
# (SC2317 is the same note in older shellcheck versions.)
# shellcheck disable=SC2317,SC2329

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

FAILED=0
run() { # <what> <command ...>
  local what="$1"
  shift
  if "$@"; then
    echo "ok   $what"
  else
    echo "FAIL $what"
    FAILED=1
  fi
}

# The scripts that run inside the image use /bin/sh, which is dash on Ubuntu.
# Their first line names the s6 program with-contenv, so shellcheck is told
# the shell. SC1091: the files they load only exist inside the image.
run "shellcheck: container scripts (sh)" shellcheck -s sh -e SC1091 \
  rootfs/etc/s6-overlay/scripts/*.sh rootfs/etc/s6-overlay/s6-rc.d/*/run build-local.sh

run "shellcheck: other scripts (bash)" shellcheck \
  rootfs/defaults/startup.sh raspbian-installer.sh scripts/*.sh \
  .github/actions/*/*.sh .github/scripts/*.sh \
  test/lint.sh test/unit/*.sh test/container/*.sh

# shellcheck disable=SC2086 # HADOLINT may hold a command with arguments
hadolint_dockerfile() { ${HADOLINT:-hadolint} - < Dockerfile; }
run "hadolint: Dockerfile" hadolint_dockerfile

json_files() {
  local f bad=0
  for f in package.json ./*/package.json .github/homebridge-dependency-bot-*.json; do
    if ! jq -e 'type == "object"' "$f" > /dev/null 2>&1; then
      echo "     not valid JSON: $f"
      bad=1
    fi
  done
  # every stream file must name its versions and its base image
  for f in package.json ./*/package.json; do
    if ! jq -e '(.dependencies["@homebridge/homebridge-apt-pkg"] | type == "string") and (.dependencies["ffmpeg-for-homebridge"] | type == "string") and (.docker.baseImage | type == "string")' "$f" > /dev/null 2>&1; then
      echo "     a version or the base image is missing: $f"
      bad=1
    fi
  done
  return "$bad"
}
run "jq: stream files and bot configs" json_files

# every script that the image or a workflow runs directly must be executable
executable_files() {
  local f bad=0
  for f in rootfs/etc/s6-overlay/scripts/healthcheck.sh rootfs/etc/s6-overlay/scripts/hb-service-docker.sh \
    rootfs/etc/s6-overlay/scripts/setup.sh rootfs/etc/s6-overlay/scripts/userdata.sh \
    rootfs/etc/s6-overlay/scripts/timezone.sh rootfs/etc/s6-overlay/scripts/credits.sh \
    rootfs/etc/s6-overlay/s6-rc.d/*/run \
    .github/actions/*/*.sh .github/scripts/*.sh scripts/*.sh build-local.sh \
    test/lint.sh test/unit/run.sh test/container/run.sh test/container/build-checks.sh; do
    if [ ! -x "$f" ]; then
      echo "     not executable: $f"
      bad=1
    fi
  done
  return "$bad"
}
run "file modes: scripts are executable" executable_files

exit "$FAILED"
