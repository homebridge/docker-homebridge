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

OLD_NPMRC='audit = false
auto-install-peers = true
fund = false
global-style = true
loglevel = "error"
update-notifier = false
package-lock = false'

test_npmrc_user_lines_are_kept() {
  new_sandbox npmrc-user
  printf 'registry=https://npm.example.internal/\n//npm.example.internal/:_authToken=abc\nloglevel = "warn"' > "$SB/homebridge/.npmrc"
  run_setup
  assert_contains "$SB/homebridge/.npmrc" "registry=https://npm.example.internal/" "the user's registry"
  assert_contains "$SB/homebridge/.npmrc" "//npm.example.internal/:_authToken=abc" "the user's token line"
  assert_contains "$SB/homebridge/.npmrc" 'loglevel = "warn"' "the user's own value for a default setting"
  assert_not_contains "$SB/homebridge/.npmrc" 'loglevel = "error"' "default must not be added twice"
  assert_contains "$SB/homebridge/.npmrc" "package-lock = false" "missing default added"
  assert_contains "$SB/homebridge/.npmrc" 'install-strategy = "shallow"' "missing default added"
  assert_eq "$(grep -c 'abc' "$SB/homebridge/.npmrc")" 1 "token line stays one line"
}

test_npmrc_new_volume_gets_the_defaults() {
  new_sandbox npmrc-new
  run_setup
  assert_eq "$(cat "$SB/homebridge/.npmrc")" "$(cat "$REPO/rootfs/defaults/.npmrc")" ".npmrc"
}

test_npmrc_old_default_file_is_migrated() {
  new_sandbox npmrc-old
  printf '%s\n' "$OLD_NPMRC" > "$SB/homebridge/.npmrc"
  run_setup
  assert_not_contains "$SB/homebridge/.npmrc" "auto-install-peers"
  assert_not_contains "$SB/homebridge/.npmrc" "global-style"
  assert_contains "$SB/homebridge/.npmrc" 'install-strategy = "shallow"'
  assert_eq "$(wc -l < "$SB/homebridge/.npmrc" | tr -d ' ')" 6 "number of lines"
}

test_npmrc_is_not_rewritten_when_nothing_changes() {
  new_sandbox npmrc-same
  run_setup
  local npmrc_before
  npmrc_before=$(ls -li "$SB/homebridge/.npmrc"; cat "$SB/homebridge/.npmrc")
  run_setup
  assert_eq "$(ls -li "$SB/homebridge/.npmrc"; cat "$SB/homebridge/.npmrc")" "$npmrc_before" ".npmrc"
  assert_eq "$(find "$SB/homebridge" -name '.npmrc.tmp*' | wc -l | tr -d ' ')" 0 "no temporary file left"
}

test_default_npmrc_has_no_old_settings() {
  assert_not_contains "$REPO/rootfs/defaults/.npmrc" "auto-install-peers"
  assert_not_contains "$REPO/rootfs/defaults/.npmrc" "global-style"
}
