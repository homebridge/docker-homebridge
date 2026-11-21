#!/usr/bin/env bash
# The TZ variable sets the time zone of the container.
# shellcheck shell=bash disable=SC2154

# tz_sandbox <name>: zone files as in the image, /etc/localtime is a link to Etc/GMT
tz_sandbox() {
  new_sandbox "$1"
  mkdir -p "$SB/zoneinfo/Etc" "$SB/zoneinfo/America"
  echo "GMT-RULES" > "$SB/zoneinfo/Etc/GMT"
  echo "TORONTO-RULES" > "$SB/zoneinfo/America/Toronto"
  ln -s Etc/GMT "$SB/zoneinfo/GMT"
  ln -s "$SB/zoneinfo/Etc/GMT" "$SB/etc/localtime"
  echo "Etc/GMT" > "$SB/etc/timezone"
}

test_timezone_tz_set() {
  tz_sandbox tz-set
  TZ=America/Toronto run_script timezone.sh
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(readlink "$SB/etc/localtime")" "$SB/zoneinfo/America/Toronto" "/etc/localtime link"
  assert_eq "$(cat "$SB/etc/localtime")" "TORONTO-RULES" "rules used for local time"
  assert_eq "$(cat "$SB/zoneinfo/Etc/GMT")" "GMT-RULES" "the zone file Etc/GMT is not overwritten"
  assert_eq "$(cat "$SB/zoneinfo/GMT")" "GMT-RULES" "the zone file GMT is not overwritten"
  assert_eq "$(cat "$SB/etc/timezone")" "America/Toronto" "/etc/timezone"
}

test_timezone_tz_not_set_stays_on_utc() {
  tz_sandbox tz-unset
  fake tzupdate
  (unset TZ; run_script timezone.sh; echo "$RC" > "$SB/rc")
  assert_eq "$(cat "$SB/rc")" 0 "exit code"
  assert_eq "$(readlink "$SB/etc/localtime")" "$SB/zoneinfo/Etc/GMT" "/etc/localtime link"
  assert_not_contains "$FAKELOG" "tzupdate" "no look-up of the time zone by IP address"
}

test_timezone_invalid_tz() {
  tz_sandbox tz-bad
  TZ=Mars/Olympus run_script timezone.sh
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(readlink "$SB/etc/localtime")" "$SB/zoneinfo/Etc/GMT" "/etc/localtime link"
  assert_contains "$SB/timezone.sh.out" "WARNING: Mars/Olympus is not a valid time zone"
  assert_eq "$(cat "$SB/etc/timezone")" "Etc/GMT" "/etc/timezone"
}

test_timezone_path_tricks_are_refused() {
  tz_sandbox tz-dots
  echo "secret" > "$SB/secret"
  TZ=../secret run_script timezone.sh
  assert_eq "$(readlink "$SB/etc/localtime")" "$SB/zoneinfo/Etc/GMT" "/etc/localtime link"
}

test_image_has_no_tzupdate() {
  assert_not_contains "$REPO/Dockerfile" "tzupdate"
  assert_not_contains "$REPO/Dockerfile" "pipx"
}
