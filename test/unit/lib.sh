#!/usr/bin/env bash
# Helpers for the sandbox tests in this folder.
#
# How the tests work:
# - The container scripts are COPIED to a scratch folder and their fixed paths
#   (/homebridge, /opt/homebridge, /etc ...) are rewritten to that folder.
# - Fake commands (npm, chown, usermod ...) are put on the PATH. They only log
#   their arguments to $FAKELOG.
# - The copies are run with dash where it exists, because /bin/sh is dash in
#   the Ubuntu image.
# - Nothing needs root, Docker or the network.
#
# The fake commands are written with single quotes on purpose, and RC is read
# by the test files.
# shellcheck disable=SC2016,SC2034

REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
UNIT_DIR="$REPO/test/unit"
WORK="${WORK:-$(mktemp -d)}"
TEST_SH="$(command -v dash || command -v sh)"

FAILED=0
CHECKS=0

fail() {
  FAILED=$((FAILED + 1))
  echo "    FAIL: $*"
}

ok() { CHECKS=$((CHECKS + 1)); }

assert_eq() { # <actual> <expected> <what>
  if [ "$1" = "$2" ]; then ok; else fail "$3: expected '$2', got '$1'"; fi
}

assert_contains() { # <file> <fixed text> <what>
  if grep -qF -- "$2" "$1" 2> /dev/null; then ok; else fail "${3:-$1}: '$2' not found"; fi
}

assert_not_contains() { # <file> <fixed text> <what>
  if grep -qF -- "$2" "$1" 2> /dev/null; then fail "${3:-$1}: '$2' found"; else ok; fi
}

assert_valid_json() { # <file>
  if [ -s "$1" ] && jq -e 'type == "object"' "$1" > /dev/null 2>&1; then
    ok
  else
    fail "$1 is not a valid JSON object ($(wc -c < "$1" 2> /dev/null | tr -d ' ') bytes)"
  fi
}

assert_json() { # <file> <jq filter> <expected> <what>
  assert_eq "$(jq -r "$2" "$1" 2> /dev/null)" "$3" "${4:-$2}"
}

assert_file() { if [ -e "$1" ]; then ok; else fail "$1 does not exist"; fi; }
assert_no_file() { if [ -e "$1" ] || [ -L "$1" ]; then fail "$1 exists"; else ok; fi; }

# rewrite <file>: prints <file> with the container paths pointed at the sandbox $SB
rewrite() {
  sed -E \
    -e "s#github\.com/homebridge#@GITHUB@#g" \
    -e "s#/etc/s6-overlay/scripts#@SCRIPTS@#g" \
    -e "s#/var/lib/homebridge#@VARLIB@#g" \
    -e "s#/opt/homebridge#@OPT@#g" \
    -e "s#/home/homebridge#@HOME@#g" \
    -e "s#/usr/share/zoneinfo#@ZONEINFO@#g" \
    -e "s#/var/run#@RUN@#g" \
    -e "s#/defaults#@DEFAULTS@#g" \
    -e "s#/command/#@COMMAND@/#g" \
    -e "s#/proc/#@PROC@/#g" \
    -e "s#/etc/#@ETC@/#g" \
    -e "s#(^|[^A-Za-z0-9_./-])/homebridge([^A-Za-z-]|\$)#\\1@HB@\\2#g" \
    -e "s#(^|[^A-Za-z0-9_./-])/homebridge([^A-Za-z-]|\$)#\\1@HB@\\2#g" \
    -e "s#@SCRIPTS@#$SB/scripts#g" \
    -e "s#@VARLIB@#$SB/varlib/homebridge#g" \
    -e "s#@OPT@#$SB/opt#g" \
    -e "s#@HOME@#$SB/home#g" \
    -e "s#@ZONEINFO@#$SB/zoneinfo#g" \
    -e "s#@RUN@#$SB/run#g" \
    -e "s#@DEFAULTS@#$SB/defaults#g" \
    -e "s#@COMMAND@#$SB/command#g" \
    -e "s#@PROC@#$SB/proc#g" \
    -e "s#@ETC@#$SB/etc#g" \
    -e "s#@HB@#$SB/homebridge#g" \
    -e "s#@GITHUB@#github.com/homebridge#g" \
    "$1"
}

# fake <name> [body]: makes a fake command in the sandbox. The default body
# logs the call and exits 0.
fake() {
  {
    echo '#!/bin/sh'
    if [ -n "${2:-}" ]; then
      echo "$2"
    else
      echo "echo \"$1 \$*\" >> \"\$FAKELOG\""
    fi
  } > "$SB/opt/bin/$1"
  chmod +x "$SB/opt/bin/$1"
}

# new_sandbox <name>: makes $SB, a fake container file system.
#   IMAGE_HB    Homebridge version the "image" holds   (default 2.5.0)
#   IMAGE_TAG   DOCKER_HOMEBRIDGE_VERSION of the image (default 2026-11-15)
#   IMAGE_BUILD DOCKER_HOMEBRIDGE_BUILD of the image   (default: not set)
new_sandbox() {
  SB="$WORK/$1"
  rm -rf "$SB"
  mkdir -p "$SB/homebridge" "$SB/opt/bin" "$SB/etc/avahi" "$SB/etc/sudoers.d" "$SB/run" \
    "$SB/varlib" "$SB/home" "$SB/command" "$SB/scripts" "$SB/proc/self"
  cp -R "$REPO/rootfs/defaults" "$SB/defaults"

  # what setup.sh reads from /opt/homebridge in the image
  printf '{"dependencies":{"homebridge":"%s","homebridge-config-ui-x":"5.30.1","node":"24.11.1"}}\n' \
    "${IMAGE_HB:-2.5.0}" > "$SB/opt/package.json"
  {
    printf 'export DOCKER_HOMEBRIDGE_VERSION=%s\n' "${IMAGE_TAG:-2026-11-15}"
    if [ -n "${IMAGE_BUILD:-}" ]; then printf 'export DOCKER_HOMEBRIDGE_BUILD=%s\n' "$IMAGE_BUILD"; fi
  } > "$SB/opt/source-docker.sh"
  rewrite "$UNIT_DIR/fixtures/source.sh" > "$SB/opt/source.sh"
  : > "$SB/opt/bashrc"

  # the container scripts
  for f in "$REPO"/rootfs/etc/s6-overlay/scripts/*; do
    rewrite "$f" > "$SB/scripts/$(basename "$f")"
  done
  if [ -f "$REPO/rootfs/etc/s6-overlay/s6-rc.d/homebridge/run" ]; then
    rewrite "$REPO/rootfs/etc/s6-overlay/s6-rc.d/homebridge/run" > "$SB/scripts/homebridge-run"
  fi

  export FAKELOG="$SB/fake.log"
  : > "$FAKELOG"
  for c in npm chown dbus-uuidgen curl groupmod usermod; do fake "$c"; done
  fake sleep 'exit 0'
  # s6-setuidgid <user> <command...>: run the command as we are
  printf '#!/bin/sh\necho "s6-setuidgid $*" >> "$FAKELOG"\nshift\nexec "$@"\n' > "$SB/command/s6-setuidgid"
  chmod +x "$SB/command/s6-setuidgid"
}

# run_script <name> [args]: runs a rewritten script from $SB/scripts.
# Output goes to $SB/<name>.out and the exit code to $RC.
run_script() {
  local name="$1"
  shift
  (cd "$SB" && PATH="$SB/opt/bin:$PATH" "$TEST_SH" "$SB/scripts/$name" "$@" > "$SB/$name.out" 2>&1)
  RC=$?
}

run_setup() { run_script setup.sh; }

fakelog() { sed "s#$SB##g" "$FAKELOG"; }
