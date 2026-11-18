#!/usr/bin/env bash
# The optional non-root mode: HOMEBRIDGE_RUN_AS_USER, PUID and PGID.
# shellcheck shell=bash disable=SC2016,SC2154

# user_sandbox <name>: the accounts of the Ubuntu image that matter here.
# The homebridge account is 858:858, group 100 is "users", uid 100 is another account.
user_sandbox() {
  new_sandbox "$1"
  fake getent 'case "$1 $2" in
  "group 100") echo "users:x:100:" ;;
  "group 858") echo "homebridge:x:858:" ;;
  "passwd 100") echo "messagebus:x:100:101::/nonexistent:/usr/sbin/nologin" ;;
  "passwd 858") echo "homebridge:x:858:858::/home/homebridge:/usr/sbin/nologin" ;;
  *) exit 2 ;;
esac'
  fake id 'case "$1" in -u) echo "${FAKE_UID:-858}" ;; -g) echo "${FAKE_GID:-858}" ;; esac'
}

apply_ids() { # runs hb_apply_requested_ids with the environment given by the caller
  (cd "$SB" && PATH="$SB/opt/bin:$PATH" "$TEST_SH" -c ". '$SB/scripts/service-user.sh'; hb_resolve_service_user && hb_apply_requested_ids" > "$SB/out" 2>&1)
  RC=$?
}

test_pgid_of_an_existing_group_is_used() {
  # Unraid: user 99, group 100. Group 100 is "users" in the image.
  user_sandbox ids-unraid
  HOMEBRIDGE_RUN_AS_USER=1 PUID=99 PGID=100 apply_ids
  assert_eq "$RC" 0 "exit code"
  assert_contains "$FAKELOG" "usermod -g 100 homebridge" "group 100 becomes the main group"
  assert_contains "$FAKELOG" "usermod -u 99 homebridge" "user id applied"
  assert_not_contains "$FAKELOG" "groupmod" "the users group is not renumbered"
  assert_not_contains "$SB/out" "WARNING"
}

test_pgid_that_is_free_renumbers_the_homebridge_group() {
  user_sandbox ids-free
  HOMEBRIDGE_RUN_AS_USER=1 PUID=1000 PGID=1000 apply_ids
  assert_contains "$FAKELOG" "groupmod -g 1000 homebridge"
  assert_contains "$FAKELOG" "usermod -g homebridge homebridge"
  assert_contains "$FAKELOG" "usermod -u 1000 homebridge"
}

test_puid_of_another_account_is_refused() {
  user_sandbox ids-taken
  HOMEBRIDGE_RUN_AS_USER=1 PUID=100 apply_ids
  assert_contains "$SB/out" "WARNING: uid 100 is already used by the messagebus account"
  assert_not_contains "$FAKELOG" "usermod -u"
}

test_ids_that_are_not_numbers_are_refused() {
  user_sandbox ids-bad
  HOMEBRIDGE_RUN_AS_USER=1 PUID=abc PGID=0 apply_ids
  assert_contains "$SB/out" "WARNING: PUID must be a non-zero number"
  assert_contains "$SB/out" "WARNING: PGID must be a non-zero number"
  assert_eq "$(grep -c 'mod' "$FAKELOG")" 0 "accounts changed"
}

test_ids_already_applied_change_nothing() {
  user_sandbox ids-same
  HOMEBRIDGE_RUN_AS_USER=1 PUID=858 apply_ids
  assert_not_contains "$FAKELOG" "usermod -u" "the uid is already right"
}

test_ids_are_ignored_in_root_mode() {
  user_sandbox ids-root
  PUID=1000 PGID=1000 run_setup
  assert_contains "$SB/setup.sh.out" "PUID / PGID are ignored unless HOMEBRIDGE_RUN_AS_USER is enabled"
  assert_not_contains "$FAKELOG" "usermod"
  assert_not_contains "$FAKELOG" "s6-setuidgid" "npm runs as root"
}

# run_homebridge <CapBnd value>: runs the homebridge service script in non-root mode
run_homebridge() {
  printf 'Name:\tsh\nCapPrm:\t%s\nCapBnd:\t%s\nCapAmb:\t0000000000000000\n' "$1" "$1" > "$SB/proc/self/status"
  printf '#!/bin/sh\necho "start.sh $*" >> "$FAKELOG"\n' > "$SB/opt/start.sh"
  chmod +x "$SB/opt/start.sh"
  # setpriv: logs the call. The trial run ("true") gives $SETPRIV_RC.
  fake setpriv 'echo "setpriv $*" >> "$FAKELOG"
for last; do :; done
if [ "$last" = "true" ]; then exit "${SETPRIV_RC:-0}"; fi
exit 0'
  printf '#!/bin/sh\necho "s6-setuidgid $*" >> "$FAKELOG"\n' > "$SB/command/s6-setuidgid"
  HOMEBRIDGE_RUN_AS_USER=1 run_script homebridge-run
}

# the default capability set of a Docker container
DOCKER_DEFAULT_CAPS=00000000a80425fb

test_caps_default_container_gets_ports_and_raw_packets() {
  user_sandbox caps-default
  run_homebridge "$DOCKER_DEFAULT_CAPS"
  assert_contains "$FAKELOG" "--ambient-caps +net_bind_service,+net_raw $SB/opt/start.sh" "rights handed to Homebridge"
  assert_contains "$FAKELOG" "setpriv --reuid 858 --regid 858 --init-groups" "user and group"
  assert_not_contains "$FAKELOG" "net_admin" "a right the container does not have"
  assert_not_contains "$FAKELOG" "start.sh --allow-root" "not started as root"
  assert_not_contains "$FAKELOG" "s6-setuidgid" "started with setpriv, not without rights"
}

test_caps_net_admin_when_the_container_has_it() {
  user_sandbox caps-admin
  # the default set plus NET_ADMIN (docker run --cap-add NET_ADMIN)
  run_homebridge 00000000a80435fb
  assert_contains "$FAKELOG" "--ambient-caps +net_bind_service,+net_admin,+net_raw $SB/opt/start.sh"
}

test_caps_none_available_still_starts_as_the_user() {
  user_sandbox caps-none
  run_homebridge 0000000000000000
  assert_contains "$FAKELOG" "s6-setuidgid homebridge $SB/opt/start.sh"
  assert_not_contains "$FAKELOG" "setpriv"
  assert_contains "$SB/homebridge-run.out" "NOTE: no network rights could be handed to the homebridge user"
}

test_caps_setpriv_failure_falls_back() {
  user_sandbox caps-fail
  SETPRIV_RC=1 run_homebridge "$DOCKER_DEFAULT_CAPS"
  assert_contains "$FAKELOG" "s6-setuidgid homebridge $SB/opt/start.sh"
  assert_not_contains "$FAKELOG" "start.sh --allow-root"
}

test_privileged_ui_port_works_as_the_user_with_the_right() {
  user_sandbox port-80
  ln -s "$SB/homebridge" "$SB/varlib/homebridge"
  echo '{"platforms":[{"platform":"config","port":80}]}' > "$SB/homebridge/config.json"
  run_homebridge "$DOCKER_DEFAULT_CAPS"
  assert_contains "$FAKELOG" "--ambient-caps +net_bind_service,+net_raw $SB/opt/start.sh"
  assert_not_contains "$FAKELOG" "start.sh --allow-root"
}

test_privileged_ui_port_without_the_right_runs_as_root() {
  user_sandbox port-80-root
  ln -s "$SB/homebridge" "$SB/varlib/homebridge"
  echo '{"platforms":[{"platform":"config","port":80}]}' > "$SB/homebridge/config.json"
  run_homebridge 0000000000000000
  assert_contains "$FAKELOG" "start.sh --allow-root"
  assert_contains "$SB/homebridge-run.out" "privileged port (80)"
}

test_root_mode_start_is_unchanged() {
  user_sandbox root-mode
  printf '#!/bin/sh\necho "start.sh $*" >> "$FAKELOG"\n' > "$SB/opt/start.sh"
  chmod +x "$SB/opt/start.sh"
  fake setpriv
  run_script homebridge-run
  assert_contains "$FAKELOG" "start.sh --allow-root"
  assert_not_contains "$FAKELOG" "setpriv"
  assert_not_contains "$FAKELOG" "chown"
}

# The fake chown changes nothing, so "the owner is already right" is tested
# with the ids of the user who runs the tests.
MY_UID=$(id -u)
MY_GID=$(id -g)

owner_changes() { grep -cE '^chown -(h|R) ' "$FAKELOG"; }

test_owner_right_tree_is_only_read() {
  user_sandbox own-right
  mkdir -p "$SB/homebridge/node_modules/homebridge-foo"
  echo '{}' > "$SB/homebridge/node_modules/homebridge-foo/package.json"
  HOMEBRIDGE_RUN_AS_USER=1 FAKE_UID=$MY_UID FAKE_GID=$MY_GID run_setup
  assert_eq "$RC" 0 "setup.sh exit code"
  assert_eq "$(owner_changes)" 0 "files that had their owner changed"
  assert_contains "$FAKELOG" "s6-setuidgid homebridge npm" "npm ran as the homebridge user"
}

test_owner_wrong_files_are_changed() {
  user_sandbox own-wrong
  mkdir -p "$SB/homebridge/node_modules/homebridge-foo" "$SB/opt/lib"
  echo '{}' > "$SB/homebridge/node_modules/homebridge-foo/package.json"
  : > "$SB/opt/lib/file"
  HOMEBRIDGE_RUN_AS_USER=1 FAKE_UID=4321 FAKE_GID=4321 run_setup
  assert_contains "$FAKELOG" "chown -h 4321:4321"
  assert_contains "$FAKELOG" "$SB/homebridge/node_modules/homebridge-foo/package.json" "file deep in the volume"
  assert_contains "$FAKELOG" "$SB/opt/lib/file" "file in /opt/homebridge"
  assert_not_contains "$FAKELOG" "chown -R" "no blind recursive chown"
}

test_owner_links_are_not_followed() {
  user_sandbox own-link
  mkdir -p "$SB/outside" "$SB/homebridge/node_modules"
  : > "$SB/outside/keep-my-owner"
  ln -s "$SB/outside" "$SB/homebridge/node_modules/homebridge-dev"
  HOMEBRIDGE_RUN_AS_USER=1 FAKE_UID=4321 FAKE_GID=4321 run_setup
  assert_not_contains "$FAKELOG" "$SB/outside/keep-my-owner" "file behind a link"
}

test_owner_volume_is_checked_once_per_container_start() {
  user_sandbox own-once
  HOMEBRIDGE_RUN_AS_USER=1 FAKE_UID=4321 FAKE_GID=4321 run_setup
  : > "$FAKELOG"
  : > "$SB/homebridge/written-by-the-startup-script"
  FAKE_UID=4321 FAKE_GID=4321 run_homebridge "$DOCKER_DEFAULT_CAPS"
  assert_contains "$FAKELOG" "$SB/homebridge/written-by-the-startup-script" "first Homebridge start checks the volume"
  assert_file "$SB/run/homebridge-permissions-checked"

  # Homebridge is restarted from the UI: no second walk over the volume
  : > "$FAKELOG"
  FAKE_UID=4321 FAKE_GID=4321 run_homebridge "$DOCKER_DEFAULT_CAPS"
  assert_not_contains "$FAKELOG" "written-by-the-startup-script" "no walk over the volume on a restart"
  assert_contains "$FAKELOG" "chown -h 4321:4321 $SB/homebridge/package.json" "files written by the script itself"

  # the container is restarted: setup.sh runs again and asks for a new check
  HOMEBRIDGE_RUN_AS_USER=1 FAKE_UID=4321 FAKE_GID=4321 run_setup
  assert_no_file "$SB/run/homebridge-permissions-checked"
}

test_owner_change_fails_falls_back_to_root() {
  user_sandbox own-fail
  fake chown 'echo "chown $*" >> "$FAKELOG"
case "$1" in -h) exit 1 ;; esac'
  HOMEBRIDGE_RUN_AS_USER=1 FAKE_UID=4321 FAKE_GID=4321 run_setup
  assert_contains "$SB/setup.sh.out" "the Homebridge service will run as root"
  assert_not_contains "$FAKELOG" "s6-setuidgid homebridge npm" "npm ran as root"
}
