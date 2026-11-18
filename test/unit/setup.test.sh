#!/usr/bin/env bash
# Tests for the other parts of setup.sh.
# shellcheck shell=bash disable=SC2016,SC2154

test_varlib_with_user_data_is_never_deleted() {
  # the user mounted their data at /var/lib/homebridge, the path of the apt package
  new_sandbox varlib-data
  mkdir -p "$SB/varlib/homebridge/node_modules/homebridge-foo"
  echo '{"bridge":{"name":"My Home"}}' > "$SB/varlib/homebridge/config.json"
  run_setup
  assert_eq "$RC" 1 "setup.sh exit code"
  assert_contains "$SB/varlib/homebridge/config.json" "My Home" "the user's config.json"
  assert_file "$SB/varlib/homebridge/node_modules/homebridge-foo"
  assert_contains "$SB/setup.sh.out" "Mount your data folder there"
  assert_not_contains "$FAKELOG" "npm" "nothing was installed"
}

test_varlib_empty_folder_becomes_the_link() {
  new_sandbox varlib-empty
  mkdir -p "$SB/varlib/homebridge"
  run_setup
  assert_eq "$RC" 0 "setup.sh exit code"
  assert_eq "$(readlink "$SB/varlib/homebridge")" "$SB/homebridge" "link target"
}

test_varlib_missing_becomes_the_link() {
  new_sandbox varlib-missing
  run_setup
  assert_eq "$(readlink "$SB/varlib/homebridge")" "$SB/homebridge" "link target"
}

test_varlib_wrong_link_is_corrected() {
  new_sandbox varlib-wrong
  mkdir -p "$SB/elsewhere"
  echo keep > "$SB/elsewhere/file"
  ln -s "$SB/elsewhere" "$SB/varlib/homebridge"
  run_setup
  assert_eq "$(readlink "$SB/varlib/homebridge")" "$SB/homebridge" "link target"
  assert_file "$SB/elsewhere/file"
  assert_no_file "$SB/homebridge/homebridge"
}

test_varlib_link_is_not_made_twice() {
  # ln without -n used to make a second link inside the volume on the next start
  new_sandbox varlib-twice
  run_setup
  run_setup
  assert_no_file "$SB/homebridge/homebridge"
}
