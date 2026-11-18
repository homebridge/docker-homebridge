#!/usr/bin/env bash
# raspbian-installer.sh, run with fake sudo, docker, curl and apt-get.
# shellcheck shell=bash disable=SC2016,SC2154

# installer_sandbox <name>: a fake Raspberry Pi OS (Debian 13, arm64) in $SB
installer_sandbox() {
  SB="$WORK/$1"
  rm -rf "$SB"
  mkdir -p "$SB/bin" "$SB/home"
  export FAKELOG="$SB/fake.log"
  : > "$FAKELOG"
  printf 'VERSION_ID="13"\nPRETTY_NAME="Debian GNU/Linux 13 (trixie)"\nVERSION_CODENAME=trixie\n' > "$SB/os-release"
  sed -e "s#/etc/os-release#$SB/os-release#g" -e "s#/etc/timezone#$SB/timezone#g" "$REPO/raspbian-installer.sh" > "$SB/installer.sh"

  local c
  for c in docker apt-get usermod install tee chmod; do
    printf '#!/bin/sh\necho "%s $*" >> "$FAKELOG"\n' "$c" > "$SB/bin/$c"
  done
  printf '#!/bin/sh\necho "sudo $*" >> "$FAKELOG"\nexec "$@"\n' > "$SB/bin/sudo"
  printf '#!/bin/sh\necho arm64\n' > "$SB/bin/dpkg"
  printf '#!/bin/sh\necho "192.168.1.50 fe80::1"\n' > "$SB/bin/hostname"
  printf '#!/bin/sh\nexit 0\n' > "$SB/bin/sleep"
  # curl: the UI answers after $UI_UP_AFTER tries (default: at once)
  printf '#!/bin/sh\necho "curl" >> "$FAKELOG"\n[ "$(grep -c "^curl" "$FAKELOG")" -gt "${UI_UP_AFTER:-0}" ]\n' > "$SB/bin/curl"
  # timedatectl: prints $FAKE_TIMEZONE, fails when it is not set
  printf '#!/bin/sh\n[ -n "$FAKE_TIMEZONE" ] || exit 1\necho "$FAKE_TIMEZONE"\n' > "$SB/bin/timedatectl"
  chmod +x "$SB/bin"/*
}

run_installer() {
  (cd "$SB" && HOME="$SB/home" USER=pi PATH="$SB/bin:$PATH" bash "$SB/installer.sh" > "$SB/out" 2>&1)
  RC=$?
  COMPOSE="$SB/home/homebridge/docker-compose.yml"
}

test_installer_writes_the_compose_file() {
  installer_sandbox inst-ok
  FAKE_TIMEZONE=Europe/London run_installer
  assert_eq "$RC" 0 "exit code"
  assert_contains "$COMPOSE" "image: homebridge/homebridge:latest"
  assert_contains "$COMPOSE" "- TZ=Europe/London" "time zone from timedatectl"
  assert_contains "$COMPOSE" "network_mode: host"
  assert_contains "$FAKELOG" "docker compose up -d"
  assert_contains "$SB/out" "http://192.168.1.50:8581"
  assert_contains "$SB/out" "same power as root" "note about the docker group"
}

test_installer_time_zone_from_the_file() {
  installer_sandbox inst-tzfile
  echo "America/Toronto" > "$SB/timezone"
  run_installer
  assert_contains "$COMPOSE" "- TZ=America/Toronto" "time zone from /etc/timezone"
}

test_installer_time_zone_default() {
  installer_sandbox inst-tzutc
  run_installer
  assert_eq "$RC" 0 "exit code"
  assert_contains "$COMPOSE" "- TZ=UTC" "time zone when nothing is known"
}

test_installer_keeps_a_copy_of_an_existing_compose_file() {
  installer_sandbox inst-again
  mkdir -p "$SB/home/homebridge"
  echo "# my own changes" > "$SB/home/homebridge/docker-compose.yml"
  FAKE_TIMEZONE=Europe/London run_installer
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(cat "$SB"/home/homebridge/docker-compose.yml.*.bak 2> /dev/null)" "# my own changes" "copy of the old file"
  assert_contains "$COMPOSE" "image: homebridge/homebridge:latest"
}

test_installer_stops_waiting_after_ten_minutes() {
  installer_sandbox inst-hang
  UI_UP_AFTER=100000 FAKE_TIMEZONE=Europe/London run_installer
  assert_eq "$RC" 1 "exit code"
  assert_contains "$SB/out" "did not answer on port 8581 within 10 minutes"
  assert_contains "$SB/out" "sudo docker compose logs"
  assert_eq "$(grep -c '^curl' "$FAKELOG")" 121 "number of tries (every 5 seconds for 10 minutes)"
}

test_installer_waits_for_a_slow_start() {
  installer_sandbox inst-slow
  UI_UP_AFTER=30 FAKE_TIMEZONE=Europe/London run_installer
  assert_eq "$RC" 0 "exit code"
  assert_contains "$SB/out" "Homebridge Installation Complete!"
}

test_installer_refuses_a_32_bit_system() {
  installer_sandbox inst-32bit
  printf '#!/bin/sh\necho armhf\n' > "$SB/bin/dpkg"
  run_installer
  assert_eq "$RC" 1 "exit code"
  assert_no_file "$SB/home/homebridge/docker-compose.yml"
}
