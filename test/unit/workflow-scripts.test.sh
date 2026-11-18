#!/usr/bin/env bash
# Tests for the shell scripts that the release workflows call.
# shellcheck shell=bash disable=SC2016,SC2154

ACTION_DIR="$REPO/.github/actions/trigger-and-wait-workflow"

# gh_sandbox <name>: a folder with a fake gh on the PATH
gh_sandbox() {
  SB="$WORK/$1"
  rm -rf "$SB"
  mkdir -p "$SB/bin"
  export FAKELOG="$SB/fake.log"
  : > "$FAKELOG"
  printf '#!/bin/sh\nexit 0\n' > "$SB/bin/sleep"
  chmod +x "$SB/bin/sleep"
}

fake_gh() { # <body>
  printf '#!/bin/sh\necho "gh $*" >> "$FAKELOG"\n%s\n' "$1" > "$SB/bin/gh"
  chmod +x "$SB/bin/gh"
}

wait_for_run() { # <timeout minutes>
  (PATH="$SB/bin:$PATH" GITHUB_OUTPUT="$SB/output" bash "$ACTION_DIR/wait-for-run.sh" 123 beta "$1" > "$SB/out" 2>&1)
  RC=$?
}

test_wait_success_is_exit_0() {
  gh_sandbox wait-ok
  fake_gh 'case "$*" in *"--json status"*) echo completed ;; *"--json conclusion"*) echo success ;; esac'
  wait_for_run 30
  assert_eq "$RC" 0 "exit code"
  assert_contains "$SB/output" "conclusion=success"
}

test_wait_failed_run_is_exit_1() {
  gh_sandbox wait-fail
  fake_gh 'case "$*" in *"--json status"*) echo completed ;; *"--json conclusion"*) echo failure ;; esac'
  wait_for_run 30
  assert_eq "$RC" 1 "exit code"
  assert_contains "$SB/out" "::error::beta workflow failed with conclusion: failure"
  assert_contains "$SB/output" "conclusion=failure"
}

test_wait_cancelled_run_is_exit_1() {
  gh_sandbox wait-cancel
  fake_gh 'case "$*" in *"--json status"*) echo completed ;; *"--json conclusion"*) echo cancelled ;; esac'
  wait_for_run 30
  assert_eq "$RC" 1 "exit code"
}

test_wait_timeout_is_exit_1() {
  gh_sandbox wait-timeout
  fake_gh 'case "$*" in *"--json status"*) echo in_progress ;; esac'
  # a real one-second sleep, so the 0 minute limit is passed on the second loop
  printf '#!/bin/sh\nexec /bin/sleep 1\n' > "$SB/bin/sleep"
  wait_for_run 0
  assert_eq "$RC" 1 "exit code"
  assert_contains "$SB/out" "::error::beta workflow timed out after 0 minutes"
}

test_wait_unknown_status_is_exit_1() {
  gh_sandbox wait-unknown
  fake_gh 'case "$*" in *"--json status"*) echo something_new ;; esac'
  wait_for_run 30
  assert_eq "$RC" 1 "exit code"
  assert_contains "$SB/out" "unexpected status: something_new"
}

test_wait_keeps_waiting_while_queued() {
  gh_sandbox wait-queued
  fake_gh 'n=$(grep -c "json status" "$FAKELOG")
case "$*" in
  *"--json status"*) if [ "$n" -lt 3 ]; then echo queued; else echo completed; fi ;;
  *"--json conclusion"*) echo success ;;
esac'
  wait_for_run 30
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(grep -c 'json status' "$FAKELOG")" 3 "number of status checks"
}

find_run() { # <after id>
  OUT=$(PATH="$SB/bin:$PATH" MAX_RETRIES=3 bash "$ACTION_DIR/find-run.sh" stage2.yml beta-2026.11.18 "Scheduled - Build and Push beta" "$1" 2> "$SB/err")
  RC=$?
}

test_find_run_skips_the_run_of_the_day_before() {
  gh_sandbox find-old
  # only yesterday's beta run is listed: same branch, same name
  fake_gh 'echo "[{\"databaseId\":100,\"name\":\"Release Stage 2 - Scheduled - Build and Push beta Docker Images\"}]"'
  find_run 100
  assert_eq "$RC" 1 "exit code"
  assert_eq "$OUT" "" "run id"
}

test_find_run_picks_the_new_run() {
  gh_sandbox find-new
  fake_gh 'echo "[{\"databaseId\":130,\"name\":\"Release Stage 2 - Scheduled - Build and Push alpha Docker Images\"},{\"databaseId\":120,\"name\":\"Release Stage 2 - Scheduled - Build and Push beta Docker Images\"},{\"databaseId\":100,\"name\":\"Release Stage 2 - Scheduled - Build and Push beta Docker Images\"}]"'
  find_run 100
  assert_eq "$RC" 0 "exit code"
  assert_eq "$OUT" "120" "run id"
}

test_find_run_waits_for_the_run_to_be_listed() {
  gh_sandbox find-wait
  fake_gh 'n=$(grep -c "run list" "$FAKELOG")
if [ "$n" -lt 3 ]; then echo "[]"; else echo "[{\"databaseId\":7,\"name\":\"x Scheduled - Build and Push beta y\"}]"; fi'
  find_run 0
  assert_eq "$RC" 0 "exit code"
  assert_eq "$OUT" "7" "run id"
}
