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

# ---------------------------------------------------------------- workflow files

# the workflows that are in use (text checks; actionlint checks the rest in CI)
workflow_files() {
  find "$REPO/.github/workflows" -name '*.yml' | sort
}

test_workflows_start_with_no_rights() {
  local f
  for f in $(workflow_files); do
    if grep -Eq '^permissions: \{\}$' "$f"; then ok; else fail "$(basename "$f"): no top-level 'permissions: {}'"; fi
  done
}

test_workflows_pin_outside_actions_by_commit() {
  # actions from this repo (./) and from the homebridge organisation are exempt
  local bad
  bad=$({ workflow_files; ls "$REPO"/.github/actions/*/action.yml; } | xargs grep -HnE '^[[:space:]]*(- )?uses:' \
    | grep -vE 'uses: (\./|homebridge/)' \
    | grep -vE 'uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}( # .+)?$' || true)
  assert_eq "$bad" "" "actions that are not pinned by a full commit hash"
}

test_workflows_do_not_use_the_personal_token() {
  local bad
  bad=$(workflow_files | xargs grep -Hn 'secrets\.GH_TOKEN' || true)
  assert_eq "$bad" "" "uses of the personal access token secrets.GH_TOKEN"
}

# ---------------------------------------------------------------- stream branch

resolve_branch() { # <stream>
  OUT=$(PATH="$SB/bin:$PATH" GITHUB_REPOSITORY=homebridge/docker-homebridge GITHUB_OUTPUT="$SB/output" \
    bash "$REPO/.github/scripts/resolve-stream-branch.sh" "$1" 2> "$SB/err")
  RC=$?
}

# branch_gh <refs json> <files json>: a fake gh for the two API calls. It
# applies the --jq filter with the real jq.
branch_gh() {
  printf '%s' "$1" > "$SB/refs.json"
  printf '%s' "$2" > "$SB/compare.json"
  fake_gh 'for last; do :; done
case "$*" in
  *matching-refs*) jq -r "$last" "'"$SB"'/refs.json" ;;
  *compare*) jq -r "$last" "'"$SB"'/compare.json" ;;
esac'
}

REFS='[{"ref":"refs/heads/beta-2026.9.30"},{"ref":"refs/heads/beta-2026.11.18"},{"ref":"refs/heads/beta-2026.11.2"},{"ref":"refs/heads/beta-test"}]'

test_branch_stable_always_uses_latest() {
  gh_sandbox branch-stable
  branch_gh "$REFS" '{"files":[]}'
  resolve_branch stable
  assert_eq "$(printf '%s\n' "$OUT" | tail -1)" "latest" "branch"
  assert_contains "$SB/output" "branch=latest"
  assert_not_contains "$FAKELOG" "matching-refs" "no branch look-up for stable"
}

test_branch_beta_uses_the_newest_dated_branch() {
  gh_sandbox branch-beta
  branch_gh "$REFS" '{"files":[{"filename":"package.json"},{"filename":"legacy/package.json"}]}'
  resolve_branch beta
  assert_eq "$(printf '%s\n' "$OUT" | tail -1)" "beta-2026.11.18" "branch"
  assert_contains "$SB/output" "branch=beta-2026.11.18"
  assert_not_contains "$SB/err" "::warning::" "only bot version changes on latest: no warning"
  if printf '%s\n' "$OUT" | grep -q "::warning::"; then fail "warning printed for bot version changes only"; else ok; fi
}

test_branch_beta_without_a_dated_branch_uses_latest() {
  gh_sandbox branch-none
  branch_gh '[{"ref":"refs/heads/beta-test"}]' '{"files":[]}'
  resolve_branch beta
  assert_eq "$(printf '%s\n' "$OUT" | tail -1)" "latest" "branch"
}

test_branch_warns_when_it_is_missing_changes_from_latest() {
  gh_sandbox branch-stale
  branch_gh "$REFS" '{"files":[{"filename":"package.json"},{"filename":"rootfs/etc/s6-overlay/scripts/setup.sh"},{"filename":"Dockerfile"}]}'
  resolve_branch beta
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(printf '%s\n' "$OUT" | tail -1)" "beta-2026.11.18" "branch"
  if printf '%s\n' "$OUT" | grep -q "::warning::beta-2026.11.18 does not have 2 file change(s) that are on latest"; then ok; else fail "no warning about the stale branch: $OUT"; fi
}

# ---------------------------------------------------------------- scripts/purge-docker.sh

# purge_sandbox <name>: a fake docker with two Homebridge images, one
# container made from them, and other things that must not be touched
purge_sandbox() {
  gh_sandbox "$1"
  cat > "$SB/bin/docker" << 'FAKE'
#!/bin/sh
echo "docker $*" >> "$FAKELOG"
case "$*" in
  "images --format {{.Repository}}:{{.Tag}} docker-homebridge") echo "docker-homebridge:latest" ;;
  "images --format {{.Repository}}:{{.Tag}} homebridge/homebridge") echo "homebridge/homebridge:beta" ;;
  "ps -a -q --filter ancestor=docker-homebridge:latest") echo "c0ffee" ;;
esac
FAKE
  chmod +x "$SB/bin/docker"
}

run_purge() { # <answer on standard input> [arguments]
  local answer="$1"
  shift
  (printf '%s\n' "$answer" | PATH="$SB/bin:$PATH" bash "$REPO/scripts/purge-docker.sh" "$@" > "$SB/out" 2>&1)
  RC=$?
}

test_purge_only_removes_homebridge_things() {
  purge_sandbox purge-yes
  run_purge y
  assert_eq "$RC" 0 "exit code"
  assert_contains "$FAKELOG" "docker rm -f c0ffee"
  assert_contains "$FAKELOG" "docker rmi docker-homebridge:latest homebridge/homebridge:beta"
  assert_not_contains "$FAKELOG" "prune" "nothing is pruned"
  assert_not_contains "$FAKELOG" "docker volume" "volumes are never touched"
  if grep -qx "docker ps -a -q" "$FAKELOG" || grep -qx "docker images -a -q" "$FAKELOG"; then fail "all containers or images were listed"; else ok; fi
}

test_purge_asks_first() {
  purge_sandbox purge-no
  run_purge n
  assert_eq "$RC" 0 "exit code"
  assert_contains "$SB/out" "Nothing was removed."
  assert_not_contains "$FAKELOG" "docker rm"
}

test_purge_yes_flag_skips_the_question() {
  purge_sandbox purge-flag
  run_purge "" --yes
  assert_contains "$FAKELOG" "docker rmi docker-homebridge:latest homebridge/homebridge:beta"
}

# ---------------------------------------------------------------- build-local.sh

build_local() { # [arguments]
  (PATH="$SB/bin:$PATH" sh "$REPO/build-local.sh" "$@" > "$SB/out" 2>&1)
  RC=$?
}

# docker_fake <exit code of "docker build">
docker_fake() {
  printf '#!/bin/sh\necho "docker $*" >> "$FAKELOG"\nif [ "$1" = "build" ]; then exit %s; fi\n' "$1" > "$SB/bin/docker"
  chmod +x "$SB/bin/docker"
}

test_build_local_stable_is_the_default() {
  gh_sandbox build-stable
  docker_fake 0
  build_local
  assert_eq "$RC" 0 "exit code"
  assert_contains "$FAKELOG" "--build-arg HOMEBRIDGE_APT_PKG_VERSION=v$(jq -r '.dependencies["@homebridge/homebridge-apt-pkg"]' "$REPO/package.json")"
  assert_contains "$FAKELOG" "--build-arg DOCKER_HOMEBRIDGE_VERSION=$(date +'%Y-%m-%d') "
  assert_contains "$FAKELOG" "--build-arg BASE_IMAGE=$(jq -r '.docker.baseImage' "$REPO/package.json")"
  assert_contains "$FAKELOG" "docker compose up"
}

test_build_local_each_stream_reads_its_own_file() {
  local stream
  for stream in beta alpha legacy synology; do
    gh_sandbox "build-$stream"
    docker_fake 0
    build_local "$stream" --build-only
    assert_eq "$RC" 0 "exit code for $stream"
    assert_contains "$FAKELOG" "--build-arg HOMEBRIDGE_APT_PKG_VERSION=v$(jq -r '.dependencies["@homebridge/homebridge-apt-pkg"]' "$REPO/$stream/package.json")" "$stream package version"
    assert_contains "$FAKELOG" "--build-arg DOCKER_HOMEBRIDGE_VERSION=$stream-$(date +'%Y-%m-%d') " "$stream version"
    assert_contains "$FAKELOG" "--build-arg BASE_IMAGE=$(jq -r '.docker.baseImage' "$REPO/$stream/package.json")" "$stream base image"
    assert_not_contains "$FAKELOG" "docker compose up" "--build-only starts no container"
  done
}

test_build_local_failed_build_starts_nothing() {
  gh_sandbox build-fail
  docker_fake 1
  build_local stable
  assert_eq "$RC" 1 "exit code"
  assert_not_contains "$FAKELOG" "docker compose up" "no container after a failed build"
}

test_build_local_unknown_stream() {
  gh_sandbox build-unknown
  docker_fake 0
  build_local nightly
  assert_eq "$RC" 1 "exit code"
  assert_not_contains "$FAKELOG" "docker build"
}
