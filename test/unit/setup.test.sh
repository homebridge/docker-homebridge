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

test_jq_failure_shows_the_real_error() {
  new_sandbox jq-fail
  fake jq 'echo "jq: error: cannot allocate memory" >&2
exit 5'
  run_setup
  assert_eq "$RC" 1 "setup.sh exit code"
  assert_contains "$SB/setup.sh.out" "ERROR: jq failed during setup check (exit code 5): jq: error: cannot allocate memory"
  assert_not_contains "$FAKELOG" "npm" "nothing was installed"
}

test_npm_failure_is_reported() {
  new_sandbox npm-fail
  fake npm 'echo "npm $*" >> "$FAKELOG"
exit 7'
  run_setup
  assert_eq "$RC" 0 "setup.sh exit code"
  assert_contains "$SB/setup.sh.out" "WARNING: 'npm install' failed with exit code 7"
}

test_npm_success_prints_no_warning() {
  new_sandbox npm-ok
  run_setup
  assert_not_contains "$SB/setup.sh.out" "npm install' failed"
}

test_image_without_version_never_asks_npm_for_latest() {
  new_sandbox no-version
  echo '{"dependencies":{"node":"24.11.1"}}' > "$SB/opt/package.json"
  run_setup
  assert_eq "$RC" 1 "setup.sh exit code on a new volume"
  assert_not_contains "$FAKELOG" "curl" "no look-up of the latest version"
  assert_no_file "$SB/homebridge/package.json"
  assert_contains "$SB/setup.sh.out" "does not say which Homebridge version to install"
}

test_image_without_version_keeps_an_existing_volume() {
  IMAGE_TAG=2026-11-20 new_sandbox no-version-existing
  echo '{"dependencies":{"homebridge":null}}' > "$SB/opt/package.json"
  echo '{"docker_tag":"2026-11-15"}' > "$SB/homebridge/homebridgeContainer.json"
  echo '{"dependencies":{"homebridge":"1.11.4","homebridge-foo":"^1.0.0"}}' > "$SB/homebridge/package.json"
  run_setup
  assert_eq "$RC" 0 "setup.sh exit code"
  assert_json "$SB/homebridge/package.json" '.dependencies.homebridge' "1.11.4" "Homebridge version in the volume"
  assert_not_contains "$FAKELOG" "curl" "no look-up of the latest version"
}

test_startup_script_failure_is_reported() {
  new_sandbox startup-fail
  printf '#!/bin/sh\necho "my startup script"\nexit 3\n' > "$SB/homebridge/startup.sh"
  run_script userdata.sh
  assert_eq "$RC" 0 "userdata.sh exit code"
  assert_contains "$SB/userdata.sh.out" "my startup script"
  assert_contains "$SB/userdata.sh.out" "WARNING: the startup script $SB/homebridge/startup.sh ended with exit code 3"
}

test_startup_script_success_prints_no_warning() {
  new_sandbox startup-ok
  printf '#!/bin/sh\nexit 0\n' > "$SB/homebridge/startup.sh"
  run_script userdata.sh
  assert_not_contains "$SB/userdata.sh.out" "WARNING"
}

# plugin_command <name>: a command that an npm package of a plugin put into
# node_modules/.bin. It fails loudly when it is used.
plugin_command() {
  mkdir -p "$SB/homebridge/node_modules/.bin"
  printf '#!/bin/sh\necho "PLUGIN %s WAS USED" >&2\necho "plugin-%s $*" >> "$FAKELOG"\nexit 9\n' "$1" "$1" > "$SB/homebridge/node_modules/.bin/$1"
  chmod +x "$SB/homebridge/node_modules/.bin/$1"
}

test_plugin_commands_do_not_replace_system_tools_in_setup() {
  new_sandbox path-setup
  ln -s "$SB/homebridge" "$SB/varlib/homebridge"
  echo '{"docker_tag":"2026-11-13"}' > "$SB/homebridge/homebridgeContainer.json"
  echo '{"dependencies":{"homebridge":"2.4.0","homebridge-config-ui-x":"5.0.0"}}' > "$SB/homebridge/package.json"
  for tool in jq sed grep cat cp mv rm ln; do plugin_command "$tool"; done
  run_setup
  assert_eq "$RC" 0 "setup.sh exit code"
  assert_not_contains "$FAKELOG" "plugin-" "commands from node_modules/.bin used by setup.sh"
  assert_json "$SB/homebridge/package.json" '.dependencies.homebridge' "2.5.0" "setup.sh still did its work"
  assert_json "$SB/homebridge/package.json" '.dependencies | has("homebridge-config-ui-x")' "false" "work done after source.sh was loaded"
}

test_plugin_commands_do_not_replace_system_tools_in_startup_script() {
  new_sandbox path-userdata
  ln -s "$SB/homebridge" "$SB/varlib/homebridge"
  plugin_command jq
  printf '#!/bin/sh\necho "{}" | jq -c . > "%s/jq-result"\ncommand -v plugin-only-tool > "%s/plugin-tool"\n' "$SB" "$SB" > "$SB/homebridge/startup.sh"
  plugin_command plugin-only-tool
  run_script userdata.sh
  assert_eq "$(cat "$SB/jq-result" 2> /dev/null)" "{}" "the startup script got the real jq"
  assert_eq "$(cat "$SB/plugin-tool" 2> /dev/null)" "$SB/varlib/homebridge/node_modules/.bin/plugin-only-tool" "other plugin commands are still found"
}

# hb_service <uid> <args...>: runs the container's hb-service wrapper as that user id
hb_service() {
  local uid="$1"
  shift
  fake id "echo $uid"
  printf '#!/bin/sh\necho "s6-svc $*" >> "$FAKELOG"\n' > "$SB/command/s6-svc"
  printf '#!/bin/sh\necho "hb-service-shim $*" >> "$FAKELOG"\n' > "$SB/opt/hb-service-shim"
  chmod +x "$SB/command/s6-svc" "$SB/opt/hb-service-shim"
  run_script hb-service-docker.sh "$@"
}

test_hb_service_restart_goes_to_s6() {
  new_sandbox hbs-restart
  hb_service 0 restart
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(cat "$FAKELOG")" "s6-svc -r /run/service/homebridge" "command run"
}

test_hb_service_stop_and_start_go_to_s6() {
  new_sandbox hbs-stop
  hb_service 0 stop
  hb_service 0 start
  assert_eq "$(tr '\n' ';' < "$FAKELOG")" "s6-svc -d /run/service/homebridge;s6-svc -u /run/service/homebridge;" "commands run"
}

test_hb_service_restart_needs_root() {
  new_sandbox hbs-user
  hb_service 1000 restart
  assert_eq "$RC" 1 "exit code"
  assert_not_contains "$FAKELOG" "s6-svc"
}

test_hb_service_other_commands_go_to_the_apt_wrapper() {
  new_sandbox hbs-other
  hb_service 0 add 'homebridge-foo@>=2.0.0'
  hb_service 0 status
  assert_eq "$(tr '\n' ';' < "$FAKELOG")" "hb-service-shim add homebridge-foo@>=2.0.0;hb-service-shim status;" "commands run"
}

test_avahi_host_name_default() {
  new_sandbox avahi-default
  run_setup
  assert_contains "$SB/etc/avahi/avahi-daemon.conf" "#host-name="
  assert_eq "$(grep -c 'host-name' "$SB/etc/avahi/avahi-daemon.conf")" 1 "host-name lines"
  assert_contains "$SB/etc/avahi/avahi-daemon.conf" "use-ipv4=yes" "rest of the avahi config"
}

test_avahi_host_name_from_dsm_hostname() {
  new_sandbox avahi-dsm
  DSM_HOSTNAME=my-nas.local run_setup
  assert_eq "$(grep 'host-name' "$SB/etc/avahi/avahi-daemon.conf")" "host-name=my-nas.local" "host-name line"
}

test_avahi_host_name_with_other_characters_is_refused() {
  # "/" and "&" mean something to sed: they must never reach it
  local bad
  for bad in 'nas/x' 'nas&x' 'nas x' 'a
b'; do
    new_sandbox avahi-bad
    DSM_HOSTNAME="$bad" run_setup
    assert_eq "$RC" 0 "setup.sh exit code for DSM_HOSTNAME='$bad'"
    assert_eq "$(grep 'host-name' "$SB/etc/avahi/avahi-daemon.conf")" "#host-name=" "host-name line for DSM_HOSTNAME='$bad'"
    assert_contains "$SB/setup.sh.out" "WARNING: DSM_HOSTNAME may only hold"
    assert_contains "$SB/etc/avahi/avahi-daemon.conf" "[rlimits]" "rest of the avahi config"
  done
}

test_new_volume_gets_the_default_startup_script() {
  new_sandbox startup-default
  rmdir "$SB/homebridge"
  run_setup
  assert_eq "$RC" 0 "setup.sh exit code"
  assert_eq "$(cat "$SB/homebridge/startup.sh")" "$(cat "$REPO/rootfs/defaults/startup.sh")" "startup.sh in a volume folder that did not exist"
}

test_old_pnpm_install_keeps_the_plugin_list() {
  new_sandbox pnpm
  echo '{"docker_tag":"2026-11-15"}' > "$SB/homebridge/homebridgeContainer.json"
  echo '{"dependencies":{"homebridge":"2.5.0","homebridge-foo":"^1.0.0"}}' > "$SB/homebridge/package.json"
  mkdir -p "$SB/homebridge/node_modules/homebridge-foo"
  : > "$SB/homebridge/pnpm-lock.yaml"
  : > "$SB/homebridge/package-lock.json"
  run_setup
  assert_no_file "$SB/homebridge/pnpm-lock.yaml"
  assert_no_file "$SB/homebridge/package-lock.json"
  assert_no_file "$SB/homebridge/node_modules/homebridge-foo"
  assert_json "$SB/homebridge/package.json" '.dependencies["homebridge-foo"]' "^1.0.0" "plugin still listed, so npm installs it again"
}
