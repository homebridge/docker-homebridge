#!/usr/bin/env bash
# Container tests: starts a real image with scratch volumes and checks what
# the start scripts do.
#
# Usage: test/container/run.sh <image> [scenario name filter]
#
# Environment:
#   PREVIOUS_IMAGE   an older image of the same stream. When set, the update
#                    test starts it first and then moves the volume to <image>.
#   HB_TEST_PREFIX   prefix for container and volume names (default: hbtest)
#   HB_TEST_PLUGIN   a small plugin from npm to install (default: homebridge-dummy)
#   HB_TEST_MAX_SIZE_MB  largest allowed size of the files in the image (default: 1400)
#   KEEP=1           keep the containers and volumes for a look afterwards
#
# Needs: docker, and the network (npm) for the scenarios that install Homebridge.
# Nothing is published on the host: every check runs with "docker exec".
#
# Text in single quotes below is meant for the shell inside the container, and
# the scenario functions are called by name at the end of this file.
# shellcheck disable=SC2016,SC2329

set -u

IMAGE="${1:?usage: run.sh <image> [scenario filter]}"
FILTER="${2:-}"
PREFIX="${HB_TEST_PREFIX:-hbtest}"
PLUGIN="${HB_TEST_PLUGIN:-homebridge-dummy}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILED=0
CHECKS=0
CONTAINERS=()
VOLUMES=()

fail() {
  FAILED=$((FAILED + 1))
  echo "    FAIL: $*"
}
ok() { CHECKS=$((CHECKS + 1)); }
assert_eq() { if [ "$1" = "$2" ]; then ok; else fail "$3: expected '$2', got '$1'"; fi; }
assert_ne() { if [ "$1" != "$2" ]; then ok; else fail "$3: must not be '$2'"; fi; }
assert_match() { if printf '%s\n' "$1" | grep -Eq -- "$2"; then ok; else fail "$3: '$1' does not match '$2'"; fi; }
assert_log() { if docker logs "$1" 2>&1 | grep -qF -- "$2"; then ok; else fail "log of $1: '$2' not found"; fi; }
assert_no_log() { if docker logs "$1" 2>&1 | grep -qF -- "$2"; then fail "log of $1: '$2' found"; else ok; fi; }

cleanup() {
  if [ "${KEEP:-0}" = "1" ]; then return; fi
  if [ "${#CONTAINERS[@]}" -gt 0 ]; then docker rm -f "${CONTAINERS[@]}" > /dev/null 2>&1; fi
  if [ "${#VOLUMES[@]}" -gt 0 ]; then docker volume rm -f "${VOLUMES[@]}" > /dev/null 2>&1; fi
}
trap cleanup EXIT

# new_volume <name>: a new empty volume. Prints its full name.
new_volume() {
  local vol="${PREFIX}-vol-$1"
  docker rm -f "${PREFIX}-$1" > /dev/null 2>&1
  docker volume rm -f "$vol" > /dev/null 2>&1
  docker volume create "$vol" > /dev/null
  VOLUMES+=("$vol")
  VOL="$vol"
}

# vol_sh <volume> <shell commands> [image]: runs commands in a throw-away
# container with the volume at /homebridge. The start scripts do not run.
vol_sh() {
  docker run --rm --entrypoint /bin/sh -v "$1:/homebridge" "${3:-$IMAGE}" -c "$2"
}

# image_sh <shell commands>: runs commands in a throw-away container, no volume
image_sh() {
  docker run --rm --entrypoint /bin/sh "$IMAGE" -c "$1"
}

# start <name> [docker run arguments ...]: starts the image as container <prefix>-<name>
start() {
  local name="${PREFIX}-$1"
  shift
  docker rm -f "$name" > /dev/null 2>&1
  CONTAINERS+=("$name")
  docker run -d --name "$name" --health-interval=5s "$@" "${RUN_IMAGE:-$IMAGE}" > /dev/null
  C="$name"
}

# wait_ui <container> [seconds]: waits until the Homebridge UI answers
wait_ui() {
  local i
  for ((i = 0; i < ${2:-180}; i += 3)); do
    if [ "$(docker inspect -f '{{.State.Running}}' "$1" 2> /dev/null)" != "true" ]; then
      fail "$1 stopped while waiting for the UI"
      docker logs --tail 30 "$1" 2>&1 | sed 's/^/      | /'
      return 1
    fi
    if docker exec "$1" curl -fs -o /dev/null http://localhost:8581/ 2> /dev/null; then
      ok
      return 0
    fi
    sleep 3
  done
  fail "$1: the UI did not answer within ${2:-180} seconds"
  docker logs --tail 30 "$1" 2>&1 | sed 's/^/      | /'
  return 1
}

# wait_exit <container> [seconds]: waits until the container has stopped
wait_exit() {
  local i
  for ((i = 0; i < ${2:-90}; i += 2)); do
    if [ "$(docker inspect -f '{{.State.Running}}' "$1" 2> /dev/null)" = "false" ]; then return 0; fi
    sleep 2
  done
  return 1
}

# wait_health <container> <status> [seconds]
wait_health() {
  local i
  for ((i = 0; i < ${3:-120}; i += 3)); do
    if [ "$(docker inspect -f '{{.State.Health.Status}}' "$1" 2> /dev/null)" = "$2" ]; then return 0; fi
    sleep 3
  done
  return 1
}

# setup_only <volume> [docker run arguments ...]: runs only setup.sh with the
# volume, with npm in dry-run mode. Fast, and it needs no network. The output
# is kept in $OUT and the exit code in $RC.
setup_only() {
  local vol="$1"
  shift
  OUT=$(docker run --rm -e npm_config_dry_run=true --entrypoint /bin/sh -v "$vol:/homebridge" "$@" "$IMAGE" /etc/s6-overlay/scripts/setup.sh 2>&1)
  RC=$?
}

IMAGE_TAG=$(image_sh '. /opt/homebridge/source-docker.sh; echo "$DOCKER_HOMEBRIDGE_VERSION"')
IMAGE_HB=$(image_sh "jq -r '.dependencies.homebridge' /opt/homebridge/package.json")
case "$IMAGE_TAG" in
  [0-9]*) IMAGE_STREAM=stable ;;
  *) IMAGE_STREAM="${IMAGE_TAG%-????-??-??}" ;;
esac
if [ "$IMAGE_STREAM" = "stable" ]; then OLDER_TAG="2020-01-01"; else OLDER_TAG="${IMAGE_STREAM}-2020-01-01"; fi
if [ "$IMAGE_STREAM" = "beta" ]; then OTHER_STREAM_TAG="2020-01-01"; else OTHER_STREAM_TAG="beta-2020-01-01"; fi

echo "image:      $IMAGE ($(docker image inspect -f '{{.Architecture}}' "$IMAGE"))"
echo "version:    $IMAGE_TAG (stream $IMAGE_STREAM), Homebridge $IMAGE_HB"
echo "previous:   ${PREVIOUS_IMAGE:-not set, the update test is skipped}"
echo

# ---------------------------------------------------------------- scenarios

scenario_fresh_volume() {
  new_volume fresh
  start fresh -v "$VOL:/homebridge" -e TZ=America/Toronto
  wait_ui "$C" || return
  assert_log "$C" "Homebridge v"
  assert_eq "$(docker exec "$C" jq -r '.dependencies.homebridge' /homebridge/package.json)" "$IMAGE_HB" "Homebridge version in package.json"
  assert_eq "$(docker exec "$C" jq -r '.docker_tag' /homebridge/homebridgeContainer.json)" "$IMAGE_TAG" "docker_tag in homebridgeContainer.json"
  assert_eq "$(docker exec "$C" readlink /var/lib/homebridge)" "/homebridge" "/var/lib/homebridge link"
  assert_eq "$(docker exec "$C" sh -c 'test -e /homebridge/homebridge; echo $?')" "1" "no link loop inside the volume"
  assert_eq "$(docker exec "$C" sh -c 'test -s /homebridge/node_modules/homebridge/package.json; echo $?')" "0" "Homebridge is installed"
  # the time zone from TZ, and the zone file for GMT is not overwritten
  assert_eq "$(docker exec "$C" readlink /etc/localtime)" "/usr/share/zoneinfo/America/Toronto" "/etc/localtime link"
  assert_match "$(docker exec "$C" date +%Z)" '^E[SD]T$' "local time zone name"
  assert_eq "$(docker exec -e TZ=Etc/GMT "$C" date +%z)" "+0000" "the zone Etc/GMT is still GMT"
  if wait_health "$C" healthy 120; then ok; else fail "health state is '$(docker inspect -f '{{.State.Health.Status}}' "$C")', expected healthy"; fi
}

scenario_existing_volume_keeps_plugins() {
  new_volume existing
  start existing -v "$VOL:/homebridge"
  wait_ui "$C" || return
  if ! docker exec "$C" npm --prefix /homebridge install --save "$PLUGIN" > /dev/null 2>&1; then
    fail "could not install the test plugin $PLUGIN"
    return
  fi
  local plugin_version
  plugin_version=$(docker exec "$C" jq -r '.version' "/homebridge/node_modules/$PLUGIN/package.json")

  # a new container on the same volume, as after "docker compose up" with the same image
  docker rm -f "$C" > /dev/null
  start existing -v "$VOL:/homebridge"
  wait_ui "$C" || return
  assert_eq "$(docker exec "$C" jq -r '.version' "/homebridge/node_modules/$PLUGIN/package.json")" "$plugin_version" "plugin still installed"
  assert_ne "$(docker exec "$C" jq -r --arg p "$PLUGIN" '.dependencies[$p] // "missing"' /homebridge/package.json)" "missing" "plugin still listed"
  assert_no_log "$C" "Docker version was updated"

  # package.json is cut short, as after a power loss. Start again.
  docker stop "$C" > /dev/null
  vol_sh "$VOL" 'printf "%s" "{\"dependencies\":{\"homebridge\":\"2" > /homebridge/package.json; rm -f /homebridge/package.json.bak'
  docker start "$C" > /dev/null
  wait_ui "$C" || return
  assert_eq "$(docker exec "$C" jq -r '.version' "/homebridge/node_modules/$PLUGIN/package.json" 2>&1)" "$plugin_version" "plugin still installed after a broken package.json"
  assert_eq "$(docker exec "$C" jq -r --arg p "$PLUGIN" '.dependencies[$p] // "missing"' /homebridge/package.json 2>&1)" "$plugin_version" "plugin listed again"
  assert_eq "$(docker exec "$C" sh -c 'test -s /homebridge/package.json.broken; echo $?')" "0" "the broken file is kept"
  assert_log "$C" "is empty or is not valid JSON"
  assert_no_log "$C" "deleting..."
}

scenario_update_decisions() {
  # image update, same stream, the volume holds a newer Homebridge: kept
  new_volume decide
  vol_sh "$VOL" "echo '{\"docker_tag\":\"$OLDER_TAG\"}' > /homebridge/homebridgeContainer.json; echo '{\"dependencies\":{\"homebridge\":\"99.0.0\",\"homebridge-foo\":\"^1.0.0\"}}' > /homebridge/package.json"
  setup_only "$VOL"
  assert_eq "$RC" 0 "setup.sh exit code"
  assert_eq "$(vol_sh "$VOL" "jq -r .dependencies.homebridge /homebridge/package.json")" "99.0.0" "a newer Homebridge in the volume is kept"
  assert_eq "$(vol_sh "$VOL" "jq -r .docker_tag /homebridge/homebridgeContainer.json")" "$IMAGE_TAG" "docker_tag updated"

  # image update, same stream, the volume holds an older Homebridge: moved up
  vol_sh "$VOL" "echo '{\"docker_tag\":\"$OLDER_TAG\"}' > /homebridge/homebridgeContainer.json; echo '{\"dependencies\":{\"homebridge\":\"1.0.0\",\"homebridge-foo\":\"^1.0.0\"}}' > /homebridge/package.json"
  setup_only "$VOL"
  assert_eq "$(vol_sh "$VOL" "jq -r .dependencies.homebridge /homebridge/package.json")" "$IMAGE_HB" "an older Homebridge is moved up"
  assert_eq "$(vol_sh "$VOL" "jq -r '.dependencies[\"homebridge-foo\"]' /homebridge/package.json")" "^1.0.0" "the plugin stays listed"

  # the user changed stream: the version of the image wins, even if lower
  vol_sh "$VOL" "echo '{\"docker_tag\":\"$OTHER_STREAM_TAG\"}' > /homebridge/homebridgeContainer.json; echo '{\"dependencies\":{\"homebridge\":\"99.0.0\"}}' > /homebridge/package.json"
  setup_only "$VOL"
  assert_eq "$(vol_sh "$VOL" "jq -r .dependencies.homebridge /homebridge/package.json")" "$IMAGE_HB" "after a stream change the image version is used"
  assert_match "$OUT" "the release stream changed" "log line"

  # same version, other build id (second image built on the same day)
  vol_sh "$VOL" "echo '{\"docker_tag\":\"$IMAGE_TAG\",\"docker_build\":\"some-other-build\"}' > /homebridge/homebridgeContainer.json; echo '{\"dependencies\":{\"homebridge\":\"1.0.0\"}}' > /homebridge/package.json"
  setup_only "$VOL"
  assert_eq "$(vol_sh "$VOL" "jq -r .dependencies.homebridge /homebridge/package.json")" "$IMAGE_HB" "a second build on the same day counts as an update"
}

scenario_wrong_mount_path() {
  # data mounted at /var/lib/homebridge, the path of the apt package
  new_volume wrongmount
  vol_sh "$VOL" "echo '{\"bridge\":{\"name\":\"My Home\"}}' > /homebridge/config.json; mkdir -p /homebridge/node_modules/homebridge-foo"
  start wrongmount -v "$VOL:/var/lib/homebridge"
  if wait_exit "$C" 90; then ok; else fail "the container did not stop"; fi
  assert_ne "$(docker inspect -f '{{.State.ExitCode}}' "$C")" "0" "container exit code"
  assert_log "$C" "Mount your data folder there"
  assert_eq "$(vol_sh "$VOL" "jq -r .bridge.name /homebridge/config.json")" "My Home" "the user's config.json"
  assert_eq "$(vol_sh "$VOL" 'test -d /homebridge/node_modules/homebridge-foo; echo $?')" "0" "the user's plugin folder"
}

scenario_failed_start_stops_the_container() {
  new_volume failedstart
  start failedstart -v "$VOL:/homebridge" -v "$HERE/fixtures/broken-jq:/usr/bin/jq:ro"
  if wait_exit "$C" 90; then ok; else fail "the container did not stop"; fi
  assert_ne "$(docker inspect -f '{{.State.ExitCode}}' "$C")" "0" "container exit code"
  assert_log "$C" "ERROR: jq failed during setup check"
}

scenario_image_settings() {
  assert_match "$(docker image inspect -f '{{.Config.Healthcheck.Test}}' "$IMAGE")" "healthcheck.sh" "HEALTHCHECK of the image"
  assert_match "$(docker image inspect -f '{{.Config.Env}}' "$IMAGE")" "S6_BEHAVIOUR_IF_STAGE2_FAILS=2" "image environment"
  assert_eq "$(image_sh 'ls /etc/apt/sources.list.d/ | grep -c homebridge')" "0" "the homebridge apt repository is not left in the image"
  assert_match "$(image_sh 'dpkg-query -W -f "\${Status}" homebridge')" "install ok installed" "homebridge package state"
  assert_eq "$(image_sh 'command -v tzupdate pipx; ls /home/homebridge/.local/bin/tzupdate 2> /dev/null' | wc -l | tr -d ' ')" "0" "tzupdate and pipx are not in the image"
  assert_eq "$(image_sh 'readlink /etc/localtime')" "/usr/share/zoneinfo/Etc/GMT" "default time zone of the image"

  # size: the files in the image, in MB. This catches a desktop package (GTK,
  # icon themes ...) or the apt package lists coming back.
  local size_mb
  size_mb=$(image_sh 'du -sxm / 2> /dev/null | cut -f1')
  if [ "${size_mb:-99999}" -le "${HB_TEST_MAX_SIZE_MB:-1400}" ]; then ok; else fail "the image holds ${size_mb} MB of files, more than ${HB_TEST_MAX_SIZE_MB:-1400} MB"; fi
  echo "    image size: ${size_mb} MB of files"
  assert_eq "$(image_sh 'ls /var/lib/apt/lists | wc -l')" "0" "apt package lists left in the image"
  assert_eq "$(image_sh 'dpkg-query -W -f "\${Package}\n" | grep -c -E "^(avahi-discover|libgtk-3-0.*|adwaita-icon-theme)$"')" "0" "desktop packages in the image"
  # tools that plugin installs and startup scripts need
  assert_eq "$(image_sh 'for t in node npm jq curl git make g++ python3 sudo xz gpg avahi-daemon avahi-browse; do command -v "$t" > /dev/null || echo "$t"; done' | tr '\n' ' ')" "" "tools missing from the image"
}

scenario_plugin_commands_do_not_replace_system_tools() {
  # a plugin's npm package brings a command called "jq" that always fails
  new_volume pluginbin
  vol_sh "$VOL" 'mkdir -p /homebridge/node_modules/.bin && printf "#!/bin/sh\necho PLUGIN-JQ-WAS-USED\nexit 9\n" > /homebridge/node_modules/.bin/jq && chmod +x /homebridge/node_modules/.bin/jq'
  setup_only "$VOL"
  assert_eq "$RC" 0 "setup.sh exit code"
  if printf '%s\n' "$OUT" | grep -q "PLUGIN-JQ-WAS-USED"; then fail "setup.sh used the jq from node_modules/.bin"; else ok; fi
  assert_eq "$(vol_sh "$VOL" "jq -r .dependencies.homebridge /homebridge/package.json")" "$IMAGE_HB" "setup.sh did its work"
  assert_match "$(image_sh 'echo "$PATH"')" '^/opt/homebridge/bin:.*/usr/bin:.*:/var/lib/homebridge/node_modules/\.bin$' "PATH of the image"
}

scenario_update_from_previous_image() {
  if [ -z "${PREVIOUS_IMAGE:-}" ]; then
    echo "    skipped: PREVIOUS_IMAGE is not set"
    return
  fi
  new_volume update
  RUN_IMAGE="$PREVIOUS_IMAGE" start update -v "$VOL:/homebridge"
  wait_ui "$C" || return
  if ! docker exec "$C" npm --prefix /homebridge install --save "$PLUGIN" > /dev/null 2>&1; then
    fail "could not install the test plugin $PLUGIN"
    return
  fi
  local plugin_version old_hb new_hb
  plugin_version=$(docker exec "$C" jq -r '.version' "/homebridge/node_modules/$PLUGIN/package.json")
  old_hb=$(docker exec "$C" jq -r '.version' /homebridge/node_modules/homebridge/package.json)
  docker rm -f "$C" > /dev/null

  start update -v "$VOL:/homebridge"
  wait_ui "$C" || return
  new_hb=$(docker exec "$C" jq -r '.version' /homebridge/node_modules/homebridge/package.json)
  assert_eq "$(docker exec "$C" jq -r '.version' "/homebridge/node_modules/$PLUGIN/package.json")" "$plugin_version" "plugin still installed after the image update"
  assert_ne "$(docker exec "$C" jq -r --arg p "$PLUGIN" '.dependencies[$p] // "missing"' /homebridge/package.json)" "missing" "plugin still listed after the image update"
  assert_eq "$(docker exec "$C" sh -c ". /etc/s6-overlay/scripts/image-update.sh; hb_semver_compare '$new_hb' '$old_hb'" | sed 's/gt/ok/; s/eq/ok/')" "ok" "Homebridge did not move down ($old_hb to $new_hb)"
  assert_log "$C" "Homebridge v"
}

# ---------------------------------------------------------------- run

TOTAL=0
BAD=0
for s in $(declare -F | awk '{print $3}' | grep '^scenario_'); do
  if [ -n "$FILTER" ] && [[ "$s" != *"$FILTER"* ]]; then continue; fi
  TOTAL=$((TOTAL + 1))
  before=$FAILED
  echo "--- $s"
  "$s"
  if [ "$FAILED" -eq "$before" ]; then echo "ok   $s"; else
    BAD=$((BAD + 1))
    echo "FAIL $s"
  fi
done

echo
echo "$TOTAL scenarios, $CHECKS checks passed, $FAILED checks failed"
if [ "$BAD" -eq 0 ]; then exit 0; fi
exit 1
