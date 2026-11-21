#!/usr/bin/env bash
# The release notes script, run in a small test repo with known tags and
# commits and with fake docker and gh commands.
# shellcheck shell=bash disable=SC2016,SC2154

# notes_repo <name>: makes $SB/repo, a git repo with the script and a history
notes_repo() {
  SB="$WORK/$1"
  rm -rf "$SB"
  mkdir -p "$SB/bin" "$SB/repo/scripts" "$SB/repo/assets" "$SB/repo/beta" "$SB/repo/alpha" "$SB/repo/rootfs"
  export FAKELOG="$SB/fake.log"
  : > "$FAKELOG"
  cp "$REPO/scripts/create-release-body.sh" "$SB/repo/scripts/"
  cp "$REPO/assets/release-body-header.md" "$SB/repo/assets/"

  # docker cp writes the manifest of "the image"; gh has no previous release to download
  cat > "$SB/bin/docker" << 'FAKE'
#!/bin/sh
echo "docker $*" >> "$FAKELOG"
if [ "$1" = "cp" ]; then printf ' | Package | Version |\n |Homebridge|2.5.1|\n' > "$3"; fi
FAKE
  printf '#!/bin/sh\necho "gh $*" >> "$FAKELOG"\nexit 1\n' > "$SB/bin/gh"
  chmod +x "$SB/bin/docker" "$SB/bin/gh"

  (
    cd "$SB/repo" || exit 1
    git init -q -b latest .
    git config user.email test@example.invalid
    git config user.name "Test"
    git config commit.gpgsign false
    git config tag.gpgsign false
    pkg() { printf '{"dependencies":{"@homebridge/homebridge-apt-pkg":"%s","ffmpeg-for-homebridge":"2.2.2"}}\n' "$2" > "$1"; }
    commit() { git add -A && git commit -q -m "$1"; }

    pkg package.json 2.0.25
    pkg beta/package.json 2.0.26-beta.1
    pkg alpha/package.json 2.0.26-alpha.1
    echo one > rootfs/setup.sh
    commit "Initial commit"
    git tag 2026-11-01
    git tag beta-2026-11-01
    git tag alpha-2026-11-01
    git tag v1.0.0-not-a-release-tag

    pkg alpha/package.json 2.0.26-alpha.2
    commit "ALPHA: Update alpha dependencies in alpha"
    git tag alpha-2026-11-10

    pkg beta/package.json 2.0.26-beta.2
    commit "BETA: Update beta dependencies in beta"
    git tag beta-2026-11-10

    echo two > rootfs/setup.sh
    commit "fix: a change to the start script"

    echo readme > README.md
    commit "docs: a change that is not in the image"

    pkg package.json 2.0.26
    commit "STABLE: Update stable dependencies in ."

    pkg beta/package.json 2.0.26-beta.3
    commit "BETA: Update beta dependencies in beta"
  ) > /dev/null 2>&1
}

release_notes() { # <tag> <stream>
  (cd "$SB/repo" && PATH="$SB/bin:$PATH" bash scripts/create-release-body.sh "$1" "$2" latest > "$SB/out" 2>&1)
  RC=$?
  NOTES="$SB/repo/output/release-body.md"
}

test_release_notes_stable_lists_only_its_own_changes() {
  notes_repo notes-stable
  release_notes 2026-11-15 stable
  assert_eq "$RC" 0 "exit code"
  assert_contains "$NOTES" "* **@homebridge/homebridge-apt-pkg**: Updated from 2.0.25 to 2.0.26" "package change of the stable stream"
  assert_contains "$NOTES" "* fix: a change to the start script" "commit that changes the image"
  assert_not_contains "$NOTES" "ALPHA: Update alpha dependencies" "bot commit of another stream"
  assert_not_contains "$NOTES" "BETA: Update beta dependencies" "bot commit of another stream"
  assert_not_contains "$NOTES" "STABLE: Update stable dependencies" "bot commit (already listed as a package change)"
  assert_not_contains "$NOTES" "docs: a change that is not in the image" "commit that does not change the image"
  assert_contains "$NOTES" "## Package Version Changes"
  assert_not_contains "$NOTES" "Docker Build Instruction Changes" "old heading"
  assert_contains "$FAKELOG" "docker create --name temp-homebridge ghcr.io/homebridge/homebridge:2026-11-15"
}

test_release_notes_beta_compares_with_the_last_beta() {
  notes_repo notes-beta
  release_notes beta-2026-11-15 beta
  assert_eq "$RC" 0 "exit code"
  assert_contains "$NOTES" "Updated from 2.0.26-beta.2 to 2.0.26-beta.3" "compared with beta-2026-11-10"
  assert_contains "$NOTES" "* fix: a change to the start script"
  assert_not_contains "$NOTES" "STABLE: Update stable dependencies"
}

test_release_notes_second_build_on_the_same_day() {
  # the tag of the release being made already exists: it is not "the previous release"
  notes_repo notes-same-day
  (cd "$SB/repo" && git tag beta-2026-11-15) > /dev/null 2>&1
  release_notes beta-2026-11-15 beta
  assert_contains "$NOTES" "Updated from 2.0.26-beta.2 to 2.0.26-beta.3" "compared with beta-2026-11-10, not with itself"
  assert_contains "$NOTES" "* fix: a change to the start script"
}

test_release_notes_no_image_changes() {
  notes_repo notes-nothing
  release_notes alpha-2026-11-15 alpha
  assert_eq "$RC" 0 "exit code"
  assert_contains "$NOTES" "* fix: a change to the start script"
  (cd "$SB/repo" && git tag alpha-2026-11-15) > /dev/null 2>&1
  release_notes alpha-2026-11-16 alpha
  assert_contains "$NOTES" "* No changes to the image scripts since the last alpha release"
}

test_release_notes_first_release_of_a_stream() {
  notes_repo notes-first
  mkdir -p "$SB/repo/legacy"
  cp "$SB/repo/package.json" "$SB/repo/legacy/package.json"
  release_notes legacy-2026-11-15 legacy
  assert_eq "$RC" 0 "exit code"
  assert_contains "$NOTES" "Previous release manifest not available for comparison."
  assert_not_contains "$FAKELOG" "gh release download" "no download without a previous release"
}

test_release_notes_unknown_stream_is_refused() {
  notes_repo notes-unknown
  release_notes 2026-11-15 nightly
  assert_eq "$RC" 1 "exit code"
}

test_release_notes_header_matches_the_readme() {
  # the table of image tags is in two places: keep them the same
  local header readme
  header=$(grep -E '^\| `' "$REPO/assets/release-body-header.md")
  readme=$(grep -E '^\| `(latest|synology|beta|alpha|legacy)`' "$REPO/README.md")
  assert_eq "$header" "$readme" "image tag table in the release notes header and in the README"
  assert_contains "$REPO/assets/release-body-header.md" '| `beta` | `amd64`, `arm64v8` | Beta |'
}
