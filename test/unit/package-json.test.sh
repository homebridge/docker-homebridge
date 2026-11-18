#!/usr/bin/env bash
# package.json in the volume is the list of installed plugins. These tests
# check that a broken file never ends with the plugins lost.
# shellcheck shell=bash disable=SC2016,SC2154

BROKEN='{"dependencies":{"homebridge":"2.5.0","homebridge-foo":"^1.0'

# add_plugin <name> <version>: an installed plugin in the volume
add_plugin() {
  mkdir -p "$SB/homebridge/node_modules/$1"
  printf '{"name":"%s","version":"%s"}\n' "$1" "$2" > "$SB/homebridge/node_modules/$1/package.json"
}

test_package_json_fresh_volume() {
  new_sandbox pj-fresh
  run_setup
  assert_eq "$RC" 0 "setup.sh exit code"
  assert_valid_json "$SB/homebridge/package.json"
  assert_json "$SB/homebridge/package.json" '.dependencies.homebridge' "2.5.0"
  assert_no_file "$SB/homebridge/package.json.broken"
  assert_contains "$FAKELOG" "npm --prefix $SB/homebridge install --omit=dev" "npm install"
}

test_package_json_cut_short_same_image() {
  new_sandbox pj-cut-same
  echo '{"docker_tag":"2026-11-15"}' > "$SB/homebridge/homebridgeContainer.json"
  printf '%s' "$BROKEN" > "$SB/homebridge/package.json"
  add_plugin homebridge 2.5.0
  add_plugin homebridge-foo 1.2.3
  add_plugin @scope/homebridge-bar 4.0.0
  add_plugin lodash 4.17.21
  run_setup
  assert_eq "$RC" 0 "setup.sh exit code"
  assert_valid_json "$SB/homebridge/package.json"
  assert_json "$SB/homebridge/package.json" '.dependencies["homebridge-foo"]' "1.2.3" "plugin kept in the list"
  assert_json "$SB/homebridge/package.json" '.dependencies["@scope/homebridge-bar"]' "4.0.0" "scoped plugin kept in the list"
  assert_json "$SB/homebridge/package.json" '.dependencies.homebridge' "2.5.0"
  assert_json "$SB/homebridge/package.json" '.dependencies | has("lodash")' "false" "a package that is not a plugin"
  assert_eq "$(cat "$SB/homebridge/package.json.broken")" "$BROKEN" "the broken file is kept"
  assert_contains "$SB/setup.sh.out" "WARNING: $SB/homebridge/package.json is empty or is not valid JSON"
  assert_file "$SB/homebridge/node_modules/homebridge-foo/package.json"
}

test_package_json_cut_short_image_update() {
  new_sandbox pj-cut-update
  echo '{"docker_tag":"2026-11-13"}' > "$SB/homebridge/homebridgeContainer.json"
  printf '%s' "$BROKEN" > "$SB/homebridge/package.json"
  add_plugin homebridge-foo 1.2.3
  run_setup
  assert_valid_json "$SB/homebridge/package.json"
  assert_json "$SB/homebridge/package.json" '.dependencies["homebridge-foo"]' "1.2.3" "plugin kept in the list"
  assert_json "$SB/homebridge/package.json" '.dependencies.homebridge' "2.5.0"
}

test_package_json_empty_file() {
  new_sandbox pj-empty
  : > "$SB/homebridge/package.json"
  add_plugin homebridge-foo 1.2.3
  run_setup
  assert_valid_json "$SB/homebridge/package.json"
  assert_json "$SB/homebridge/package.json" '.dependencies["homebridge-foo"]' "1.2.3" "plugin kept in the list"
}

test_package_json_restored_from_backup() {
  new_sandbox pj-backup
  echo '{"docker_tag":"2026-11-15"}' > "$SB/homebridge/homebridgeContainer.json"
  echo '{"description":"mine","dependencies":{"homebridge":"2.5.0","homebridge-foo":"^1.0.0"}}' > "$SB/homebridge/package.json"
  run_setup
  assert_json "$SB/homebridge/package.json.bak" '.dependencies["homebridge-foo"]' "^1.0.0" "backup saved on a good start"

  # the file is cut short, and one more plugin was installed after the backup
  printf '%s' "$BROKEN" > "$SB/homebridge/package.json"
  add_plugin homebridge-new 3.0.0
  run_setup
  assert_valid_json "$SB/homebridge/package.json"
  assert_json "$SB/homebridge/package.json" '.dependencies["homebridge-foo"]' "^1.0.0" "version rule from the backup"
  assert_json "$SB/homebridge/package.json" '.dependencies["homebridge-new"]' "3.0.0" "plugin installed after the backup"
  assert_json "$SB/homebridge/package.json" '.description' "mine" "other fields from the backup"
  assert_contains "$SB/setup.sh.out" "restored from the backup copy"
}

test_package_json_missing_with_plugins() {
  new_sandbox pj-missing
  add_plugin homebridge-foo 1.2.3
  run_setup
  assert_json "$SB/homebridge/package.json" '.dependencies["homebridge-foo"]' "1.2.3" "plugin kept in the list"
}

test_package_json_linked_plugin_is_not_listed() {
  new_sandbox pj-linked
  mkdir -p "$SB/dev/homebridge-dev" "$SB/homebridge/node_modules"
  echo '{"name":"homebridge-dev","version":"0.0.1"}' > "$SB/dev/homebridge-dev/package.json"
  ln -s "$SB/dev/homebridge-dev" "$SB/homebridge/node_modules/homebridge-dev"
  add_plugin homebridge-foo 1.2.3
  : > "$SB/homebridge/package.json"
  run_setup
  assert_json "$SB/homebridge/package.json" '.dependencies | has("homebridge-dev")' "false" "linked plugin"
  assert_json "$SB/homebridge/package.json" '.dependencies["homebridge-foo"]' "1.2.3"
}

test_package_json_good_file_is_not_touched() {
  new_sandbox pj-good
  echo '{"docker_tag":"2026-11-15"}' > "$SB/homebridge/homebridgeContainer.json"
  printf '{"dependencies":{"homebridge":"2.5.0","homebridge-foo":"https://example.com/my%%20plugin.tgz"}}' > "$SB/homebridge/package.json"
  cp "$SB/homebridge/package.json" "$SB/before.json"
  run_setup
  assert_eq "$(cat "$SB/homebridge/package.json")" "$(cat "$SB/before.json")" "package.json unchanged"
  assert_no_file "$SB/homebridge/package.json.broken"
  assert_not_contains "$SB/setup.sh.out" "WARNING: $SB/homebridge/package.json"
}

test_package_json_repaired_before_each_homebridge_start() {
  new_sandbox pj-run
  printf '%s' "$BROKEN" > "$SB/homebridge/package.json"
  add_plugin homebridge-foo 1.2.3
  printf '#!/bin/sh\necho "start.sh $*" >> "$FAKELOG"\n' > "$SB/opt/start.sh"
  chmod +x "$SB/opt/start.sh"
  run_script homebridge-run
  assert_valid_json "$SB/homebridge/package.json"
  assert_json "$SB/homebridge/package.json" '.dependencies["homebridge-foo"]' "1.2.3"
  assert_contains "$FAKELOG" "start.sh --allow-root" "Homebridge was started"
}

test_write_json_refuses_bad_content() {
  new_sandbox pj-write
  echo '{"keep":"me"}' > "$SB/file.json"
  out=$(cd "$SB" && "$TEST_SH" -c ". '$SB/scripts/package-json.sh'; printf '{\"cut\":' | hb_write_json '$SB/file.json'; echo \"rc=\$?\"")
  assert_eq "$out" "rc=1" "hb_write_json result"
  assert_json "$SB/file.json" '.keep' "me" "old content kept"
  assert_eq "$(find "$SB" -maxdepth 1 -name 'file.json.tmp*' | wc -l | tr -d ' ')" "0" "no temporary file left"
}
