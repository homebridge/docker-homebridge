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
