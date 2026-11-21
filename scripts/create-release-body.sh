#!/usr/bin/env bash

# Writes the release notes (output/release-body.md) and the package manifest
# (output/Docker.manifest) for one release.
#
# Usage: create-release-body.sh <release tag> <stream> <build branch>
#   <release tag>   for example 2026-11-18 or beta-2026-11-18
#   <stream>        stable, beta, alpha, legacy or synology
#   <build branch>  the branch the image was built from (default: latest)
#
# Environment:
#   HOMEBRIDGE_IMAGE_REPO   where the image is (default: ghcr.io/homebridge/homebridge)
#
# Needs: docker, gh, git with the full history and the tags (fetch-depth: 0), jq.

# Exit on error
set -e

# Logging functions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $*" >&2; }
group_log() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo -e "::group::$*"
  else
    log "===> $* <==="
  fi
}
group_end() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo -e "::endgroup::"
  fi
}

# Determine repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PREVIOUS_DIR="${REPO_ROOT}/.previous"
rm -rf "$PREVIOUS_DIR"
mkdir -p "$PREVIOUS_DIR"

OUTPUT_DIR="${REPO_ROOT}/output"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

MANIFEST="${OUTPUT_DIR}/release-body.md"
DOCKER_MANIFEST="${OUTPUT_DIR}/Docker.manifest"

info "Creating release body at ${MANIFEST}"

log "Adding header to release body"
cp "${REPO_ROOT}/assets/release-body-header.md" "$MANIFEST"
echo >> "$MANIFEST"

GITHUB_TAG="${1:-latest}"
PKG_RELEASE_STREAM="${2:-stable}"
BUILD_BRANCH="${3:-latest}"
IMAGE_REPO="${HOMEBRIDGE_IMAGE_REPO:-ghcr.io/homebridge/homebridge}"

case "$PKG_RELEASE_STREAM" in
  stable) PACKAGE_JSON_PATH="package.json" ;;
  beta | alpha | legacy | synology) PACKAGE_JSON_PATH="${PKG_RELEASE_STREAM}/package.json" ;;
  *)
    echo "Unknown stream '${PKG_RELEASE_STREAM}'. Use stable, beta, alpha, legacy or synology." >&2
    exit 1
    ;;
esac

group_log "Extracting package manifest and changes for tag: ${GITHUB_TAG}, stream: ${PKG_RELEASE_STREAM}"

docker create --name temp-homebridge "${IMAGE_REPO}:${GITHUB_TAG}"
docker cp temp-homebridge:/opt/homebridge/Docker.manifest "${DOCKER_MANIFEST}"
docker rm temp-homebridge

group_end

# Builds from a pre-release branch (e.g. beta-2026.11.18) carry changes that are not in
# stable yet: say where the build came from and list what it adds on top of latest.
if [[ "$BUILD_BRANCH" != "latest" ]]; then
  REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-homebridge/docker-homebridge}"
  log "Adding pre-release branch section for branch: ${BUILD_BRANCH}"
  {
    echo -e "\n## Pre-release Changes (not yet in stable)\n"
    echo "Built from branch [\`${BUILD_BRANCH}\`](${REPO_URL}/tree/${BUILD_BRANCH})."
    echo
  } >> "$MANIFEST"
  if git rev-parse --verify --quiet origin/latest > /dev/null; then
    # Pull requests merged into the branch, then the individual commits they brought in
    BRANCH_PRS=$(git log --merges --format='%s' origin/latest..HEAD | grep -oE 'pull request #[0-9]+' | grep -oE '#[0-9]+' | sort -u || true)
    for PR in $BRANCH_PRS; do
      echo "* Pull request ${PR}" >> "$MANIFEST"
    done
    # Skip the dependency bot's daily package.json bumps; those are covered further down
    BRANCH_COMMITS=$(git log --no-merges --format='%h %s' origin/latest..HEAD | grep -vE '^[0-9a-f]+ [A-Z]+: Update [a-z]+ dependencies' || true)
    if [ -n "$BRANCH_COMMITS" ]; then
      while IFS= read -r commit; do
        echo "* ${commit#* } (\`${commit%% *}\`)" >> "$MANIFEST"
      done <<< "$BRANCH_COMMITS"
    elif [ -z "$BRANCH_PRS" ]; then
      echo "* No changes beyond latest" >> "$MANIFEST"
    fi
  else
    warn "origin/latest not available; cannot list pre-release changes."
  fi
fi

log "Adding package manifest section for stream: ${PKG_RELEASE_STREAM}"

# Add current manifest section
echo -e "\n## Current Package Manifest:\n" >> "$MANIFEST"

for OUTPUT_MANIFEST in "${OUTPUT_DIR}"/*manifest; do

  # Extract the base name of the manifest file
  MANIFEST_NAME=$(basename "$OUTPUT_MANIFEST")

  # Create this line based on the manifest name - ### AMD64 Manifest
  if [[ "$MANIFEST_NAME" == *"amd64.manifest" ]]; then
    MANIFEST_HEADER="AMD64 Manifest"
  elif [[ "$MANIFEST_NAME" == *"arm64.manifest" ]]; then
    MANIFEST_HEADER="ARM64 Manifest"
  else
    MANIFEST_HEADER="$MANIFEST_NAME"
  fi

  log "Including manifest: $MANIFEST_NAME"
  {
    echo "### ${MANIFEST_HEADER}"
    echo
    cat "$OUTPUT_MANIFEST"
    echo
  } >> "$MANIFEST"
done

# The release tags of one stream, oldest first. A stable tag is only a date
# (2026-11-15). The other streams have the stream name in front (beta-2026-11-18).
stream_tags() {
  local pattern
  if [[ "$1" == "stable" ]]; then
    pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  else
    pattern="^$1-[0-9]{4}-[0-9]{2}-[0-9]{2}\$"
  fi
  git tag -l | grep -E "$pattern" | sort -V || true
}

# The previous release of this stream. The tag of the release being made is
# left out: on a second build on the same day it already exists.
LATEST_TAG=$(stream_tags "$PKG_RELEASE_STREAM" | grep -vxF -- "$GITHUB_TAG" | tail -1 || true)

log "Previous release for stream '${PKG_RELEASE_STREAM}': ${LATEST_TAG:-none}"

# Check for package version changes if we have a previous tag
HAS_PACKAGE_CHANGES=false
if [ -n "$LATEST_TAG" ]; then
  log "package.json path for comparison: ${PACKAGE_JSON_PATH}"

  # Compare package versions with previous tag
  if git show "$LATEST_TAG:$PACKAGE_JSON_PATH" > /dev/null 2>&1; then
    # Define the list of dependencies to check
    DEPENDENCIES=(
      "@homebridge/homebridge-apt-pkg"
      "ffmpeg-for-homebridge"
    )

    # Iterate through the dependencies
    for DEP in "${DEPENDENCIES[@]}"; do
      # Get the previous version of the dependency from the latest tag
      PREV_VERSION=$(git show "$LATEST_TAG:$PACKAGE_JSON_PATH" 2> /dev/null | jq -r --arg dep "$DEP" '.dependencies[$dep] // "unknown"')

      # Get the current version of the dependency from the current package.json
      CURR_VERSION=$(jq -r --arg dep "$DEP" '.dependencies[$dep] // "unknown"' "${REPO_ROOT}/${PACKAGE_JSON_PATH}")

      # Check if the version has changed and add it to the changelog
      if [[ "$PREV_VERSION" != "$CURR_VERSION" && "$CURR_VERSION" != "unknown" ]]; then
        log "Dependency ${DEP} changed from ${PREV_VERSION} to ${CURR_VERSION}"
        if [ "$HAS_PACKAGE_CHANGES" = false ]; then
          log "Adding Package Version Changes section to release body"
          echo -e "## Package Version Changes" >> "$MANIFEST"
          echo >> "$MANIFEST"
          HAS_PACKAGE_CHANGES=true
        fi
        echo "* **${DEP}**: Updated from $PREV_VERSION to $CURR_VERSION" >> "$MANIFEST"
      fi
    done
  else
    warn "Could not find previous package.json at tag ${LATEST_TAG} for comparison."
  fi
fi

if [ -n "$LATEST_TAG" ] && gh release download "$LATEST_TAG" --pattern "*.manifest" --dir "${PREVIOUS_DIR}" 2> /dev/null; then
  echo -e "\n## Changes Since Previous Release ($LATEST_TAG):\n" >> "$MANIFEST"

  # Iterate through all manifest files in ${OUTPUT_DIR}
  for OUTPUT_MANIFEST in "${OUTPUT_DIR}"/*manifest; do
    # Extract the base name of the manifest file
    MANIFEST_NAME=$(basename "$OUTPUT_MANIFEST")
    log "Processing manifest for changes: $MANIFEST_NAME"
    # Check if a corresponding file exists in ${PREVIOUS_DIR}
    PREVIOUS_MANIFEST="${PREVIOUS_DIR}/${MANIFEST_NAME}"
    if [[ -f "$PREVIOUS_MANIFEST" ]]; then
      TMP_DIFF="$(mktemp)"
      # Compare the manifests and capture differences
      info "diff -u \"$PREVIOUS_MANIFEST\" \"$OUTPUT_MANIFEST\" "
      if ! diff -u "$PREVIOUS_MANIFEST" "$OUTPUT_MANIFEST" > "${TMP_DIFF}" 2> /dev/null; then
        # Check if there are any meaningful changes in the diff
        if grep -qE "^[+-] \|" "${TMP_DIFF}"; then
          {
            echo "### Changes in ${MANIFEST_NAME}"
            echo "\`\`\`diff"
            # Include the diff output, sorted for readability
            grep -E "^[+-] \|" "${TMP_DIFF}" | sort -k2 | head -20
            echo "\`\`\`"
          } >> "$MANIFEST"
        else
          warn "No meaningful changes detected in ${MANIFEST_NAME}."
          echo "No meaningful changes detected in ${MANIFEST_NAME}." >> "$MANIFEST"
          cat "${TMP_DIFF}"
        fi
      else
        warn "No changes detected in ${MANIFEST_NAME}."
        echo "No changes detected in ${MANIFEST_NAME}." >> "$MANIFEST"
      fi
      rm -f "${TMP_DIFF}" || true
    else
      # If no corresponding file exists in ${PREVIOUS_DIR}, note it in the manifest
      echo "No previous manifest found for ${MANIFEST_NAME}." >> "$MANIFEST"
    fi
  done
else
  echo -e "\n## Changes Since Previous Release\n" >> "$MANIFEST"
  echo "Previous release manifest not available for comparison." >> "$MANIFEST"
fi

# Commits that change the image of THIS stream: its own package.json and the
# files every stream shares. The daily version bumps of the dependency bot are
# left out (they are listed under "Package Version Changes"), and so are the
# commits that only touch another stream.
STREAM_PATHS=("$PACKAGE_JSON_PATH" Dockerfile rootfs build)
stream_commits() { # <git log arguments ...>
  git log --no-merges --format='%h %s' "$@" -- "${STREAM_PATHS[@]}" 2> /dev/null \
    | grep -vE '^[0-9a-f]+ [A-Z]+: Update [a-z]+ dependencies' || true
}
write_commits() { # <list of "hash subject" lines>
  local commit
  while IFS= read -r commit; do
    if [ -n "$commit" ]; then
      echo "* ${commit#* } (\`${commit%% *}\`)" >> "$MANIFEST"
    fi
  done <<< "$1"
}

echo -e "\n### Docker Homebridge Changes" >> "$MANIFEST"
if [ -n "$LATEST_TAG" ]; then
  # Get commits since the previous release of the same stream
  CHANGELOG_COMMITS=$(stream_commits "$LATEST_TAG"..HEAD)

  if [ -n "$CHANGELOG_COMMITS" ]; then
    echo >> "$MANIFEST"
    write_commits "$CHANGELOG_COMMITS"
  else
    echo >> "$MANIFEST"
    echo "* No changes to the image scripts since the last ${PKG_RELEASE_STREAM} release" >> "$MANIFEST"
  fi
else
  # If no tags of this type exist, show recent commits
  RECENT_COMMITS=$(stream_commits -5)
  if [ -n "$RECENT_COMMITS" ]; then
    echo "### Recent Changes" >> "$MANIFEST"
    echo >> "$MANIFEST"
    write_commits "$RECENT_COMMITS"
  else
    echo "* No commit history available" >> "$MANIFEST"
  fi
fi

echo >> "$MANIFEST"
