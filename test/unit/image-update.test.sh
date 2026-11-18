#!/usr/bin/env bash
# What an image update does to the Homebridge version in the volume.
# Rule (decided by BP, 2026-11-18): a newer Homebridge in the volume is kept,
# unless the user changed release stream. Then the version of the image wins.
# shellcheck shell=bash disable=SC2154

# volume <docker tag the volume last ran> <homebridge version in the volume>
volume() {
  printf '{"docker_tag":"%s"}\n' "$1" > "$SB/homebridge/homebridgeContainer.json"
  printf '{"dependencies":{"homebridge":"%s","homebridge-foo":"^1.0.0"}}\n' "$2" > "$SB/homebridge/package.json"
}

hb_version() { jq -r '.dependencies.homebridge' "$SB/homebridge/package.json"; }

test_update_keeps_a_newer_beta_from_the_ui() {
  IMAGE_HB=2.5.0 IMAGE_TAG=2026-11-15 new_sandbox upd-keep-beta
  volume 2026-11-13 2.5.1-beta.4
  run_setup
  assert_eq "$(hb_version)" "2.5.1-beta.4" "Homebridge version in the volume"
  assert_json "$SB/homebridge/package.json" '.dependencies["homebridge-foo"]' "^1.0.0" "plugin kept"
  assert_contains "$SB/setup.sh.out" "keeping the Homebridge version"
}

test_update_legacy_image_does_not_move_down() {
  # the legacy images of November 2026 held Homebridge 1.6.1
  IMAGE_HB=1.6.1 IMAGE_TAG=legacy-2026-11-16 new_sandbox upd-legacy
  volume legacy-2026-11-02 1.11.4
  run_setup
  assert_eq "$(hb_version)" "1.11.4" "Homebridge version in the volume"
}

test_update_moves_up() {
  IMAGE_HB=2.5.1 IMAGE_TAG=2026-11-20 new_sandbox upd-up
  volume 2026-11-15 2.5.0
  run_setup
  assert_eq "$(hb_version)" "2.5.1" "Homebridge version in the volume"
  assert_json "$SB/homebridge/package.json" '.dependencies["homebridge-foo"]' "^1.0.0" "plugin kept"
}

test_update_final_release_replaces_its_own_beta() {
  IMAGE_HB=2.5.1 IMAGE_TAG=2026-11-20 new_sandbox upd-final
  volume 2026-11-15 2.5.1-beta.4
  run_setup
  assert_eq "$(hb_version)" "2.5.1" "Homebridge version in the volume"
}

test_update_stream_change_image_wins() {
  # from the beta tag back to latest: the stable version wins, even if lower
  IMAGE_HB=2.5.0 IMAGE_TAG=2026-11-20 new_sandbox upd-stream
  volume beta-2026-11-18 2.6.0-beta.3
  run_setup
  assert_eq "$(hb_version)" "2.5.0" "Homebridge version in the volume"
  assert_contains "$SB/setup.sh.out" "the release stream changed from beta to stable"
}

test_update_same_stream_beta_keeps_newer() {
  IMAGE_HB=2.6.0-beta.2 IMAGE_TAG=beta-2026-11-19 new_sandbox upd-beta-same
  volume beta-2026-11-18 2.6.0-beta.10
  run_setup
  assert_eq "$(hb_version)" "2.6.0-beta.10" "Homebridge version in the volume"
}

test_update_unknown_old_tag_is_not_a_stream_change() {
  IMAGE_HB=2.5.0 IMAGE_TAG=2026-11-20 new_sandbox upd-unknown
  volume "something-else" 2.5.1
  run_setup
  assert_eq "$(hb_version)" "2.5.1" "Homebridge version in the volume"
}

test_update_custom_version_is_kept() {
  IMAGE_HB=2.5.0 IMAGE_TAG=2026-11-20 new_sandbox upd-custom
  volume 2026-11-15 "github:homebridge/homebridge#some-branch"
  run_setup
  assert_eq "$(hb_version)" "github:homebridge/homebridge#some-branch" "Homebridge version in the volume"
}

test_update_caret_range_is_compared() {
  IMAGE_HB=2.5.1 IMAGE_TAG=2026-11-20 new_sandbox upd-caret
  volume 2026-11-15 "^2.5.0"
  run_setup
  assert_eq "$(hb_version)" "2.5.1" "Homebridge version in the volume"
}

test_update_missing_homebridge_entry_is_added() {
  IMAGE_HB=2.5.0 IMAGE_TAG=2026-11-20 new_sandbox upd-missing
  echo '{"docker_tag":"2026-11-15"}' > "$SB/homebridge/homebridgeContainer.json"
  echo '{"dependencies":{"homebridge-foo":"^1.0.0"}}' > "$SB/homebridge/package.json"
  run_setup
  assert_eq "$(hb_version)" "2.5.0" "Homebridge version in the volume"
}

test_same_image_does_not_touch_the_version() {
  IMAGE_HB=2.5.1 IMAGE_TAG=2026-11-15 new_sandbox upd-same
  volume 2026-11-15 2.5.0
  run_setup
  assert_eq "$(hb_version)" "2.5.0" "Homebridge version in the volume"
}

semver() { (cd "$SB" && "$TEST_SH" -c ". '$SB/scripts/image-update.sh'; hb_semver_compare '$1' '$2'"); }

test_semver_compare() {
  new_sandbox semver
  while read -r a b want; do
    [ -n "$a" ] || continue
    assert_eq "$(semver "$a" "$b")" "$want" "compare $a with $b"
  done << 'PAIRS'
1.6.1 1.11.4 lt
1.11.4 1.6.1 gt
2.5.0 2.5.0 eq
2.5.0 2.5.1 lt
2.10.0 2.9.9 gt
10.0.0 9.9.9 gt
2.5.1-beta.4 2.5.0 gt
2.5.1-beta.4 2.5.1 lt
2.5.1 2.5.1-beta.4 gt
2.5.1-beta.4 2.5.1-beta.10 lt
2.5.1-beta.10 2.5.1-beta.9 gt
2.5.1-alpha.9 2.5.1-beta.1 lt
2.5.1-beta 2.5.1-beta.1 lt
2.5.1-beta.1 2.5.1-beta.1 eq
2.5.1-1 2.5.1-beta lt
2.5.1-beta.20261118 2.5.1-beta.20261117 gt
2.5.0+build.1 2.5.0+build.2 eq
2.5.0-rc.1+x 2.5.0-rc.1 eq
PAIRS
}

test_semver_valid() {
  new_sandbox semver-valid
  for v in 2.5.0 1.11.4 2.5.1-beta.4 2.6.0-alpha.20261118 2.5.0+build.1; do
    (cd "$SB" && "$TEST_SH" -c ". '$SB/scripts/image-update.sh'; hb_semver_valid '$v'")
    assert_eq "$?" 0 "$v is a version"
  done
  for v in "" null latest beta "^2.5.0" 2.5 "2.5.0 " "github:homebridge/homebridge" "2.5.0-"; do
    (cd "$SB" && "$TEST_SH" -c ". '$SB/scripts/image-update.sh'; hb_semver_valid '$v'")
    assert_eq "$?" 1 "'$v' is not a version"
  done
}

test_stream_of() {
  new_sandbox stream
  while read -r tag want; do
    got=$(cd "$SB" && "$TEST_SH" -c ". '$SB/scripts/image-update.sh'; hb_stream_of '$tag'")
    assert_eq "$got" "${want#-}" "stream of '$tag'"
  done << 'TAGS'
2026-11-15 stable
beta-2026-11-18 beta
alpha-2026-11-18 alpha
legacy-2026-11-16 legacy
synology-2026-11-15 synology
latest -
ubuntu -
2026-11 -
TAGS
}
