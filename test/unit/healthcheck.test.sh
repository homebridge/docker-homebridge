#!/usr/bin/env bash
# The Docker health check asks the Homebridge UI on the port from config.json.
# shellcheck shell=bash disable=SC2016,SC2154

# the fake curl logs the address and passes when it matches $CURL_OK
fake_curl() {
  fake curl 'for last; do :; done
echo "curl $last" >> "$FAKELOG"
case "$last" in $CURL_OK) exit 0 ;; esac
exit 7'
}

test_healthcheck_default_port() {
  new_sandbox hc-default
  fake_curl
  CURL_OK='http://localhost:8581/' run_script healthcheck.sh
  assert_eq "$RC" 0 "exit code"
}

test_healthcheck_port_from_config() {
  new_sandbox hc-port
  fake_curl
  echo '{"bridge":{"port":51826},"platforms":[{"platform":"Other","port":1},{"platform":"config","name":"Config","port":8080}]}' > "$SB/homebridge/config.json"
  CURL_OK='http://localhost:8080/' run_script healthcheck.sh
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(head -1 "$FAKELOG")" "curl http://localhost:8080/" "address asked"
}

test_healthcheck_https() {
  new_sandbox hc-https
  fake_curl
  echo '{"platforms":[{"platform":"config","port":8581,"ssl":{"selfSigned":true}}]}' > "$SB/homebridge/config.json"
  CURL_OK='https://localhost:8581/' run_script healthcheck.sh
  assert_eq "$RC" 0 "exit code"
}

test_healthcheck_custom_host() {
  new_sandbox hc-host
  fake_curl
  echo '{"platforms":[{"platform":"config","port":8581,"host":"192.168.1.20"}]}' > "$SB/homebridge/config.json"
  CURL_OK='http://192.168.1.20:8581/' run_script healthcheck.sh
  assert_eq "$RC" 0 "exit code"
}

test_healthcheck_fails_when_the_ui_is_down() {
  new_sandbox hc-down
  fake_curl
  CURL_OK='nothing' run_script healthcheck.sh
  assert_eq "$RC" 1 "exit code"
  assert_contains "$SB/healthcheck.sh.out" "does not answer on localhost port 8581"
}

test_healthcheck_broken_config_uses_the_default() {
  new_sandbox hc-broken
  fake_curl
  printf '{"platforms":[{"platform":"config","port":80' > "$SB/homebridge/config.json"
  CURL_OK='http://localhost:8581/' run_script healthcheck.sh
  assert_eq "$RC" 0 "exit code"
}

test_dockerfile_stops_on_failed_start_and_has_a_healthcheck() {
  assert_contains "$REPO/Dockerfile" "S6_BEHAVIOUR_IF_STAGE2_FAILS=2"
  assert_contains "$REPO/Dockerfile" 'CMD [ "/etc/s6-overlay/scripts/healthcheck.sh" ]'
  if [ -x "$REPO/rootfs/etc/s6-overlay/scripts/healthcheck.sh" ]; then ok; else fail "healthcheck.sh is not executable"; fi
}
