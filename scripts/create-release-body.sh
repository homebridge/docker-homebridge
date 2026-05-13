#! /bin/bash

# If used in GitHub Actions, ensure we have a full git history
#     - name: Checkout
#      uses: actions/checkout@v4
#      with:
#        fetch-depth: 0

# Exit on error
set -e

# Logging functions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2; }
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

group_log "Extracting package manifest and changes for tag: ${GITHUB_TAG}, stream: ${PKG_RELEASE_STREAM}"

docker create --name temp-homebridge ghcr.io/homebridge/homebridge:${GITHUB_TAG}
docker cp temp-homebridge:/opt/homebridge/Docker.manifest ${DOCKER_MANIFEST}
docker rm temp-homebridge

group_end

log "Adding package manifest section for stream: ${PKG_RELEASE_STREAM}"

# Add current manifest section
echo -e "\n## Current Package Manifest:\n" >> "$MANIFEST"

for OUTPUT_MANIFEST in ${OUTPUT_DIR}/*manifest; do

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
  echo "### ${MANIFEST_HEADER}" >> "$MANIFEST"
  echo >> "$MANIFEST"
  cat "$OUTPUT_MANIFEST" >> "$MANIFEST"
  echo >> "$MANIFEST"
done

# Get the latest tag to compare against, filtered by release type
if [[ "${PKG_RELEASE_STREAM:-stable}" == "beta" ]]; then
  # For beta releases, only look at beta tags
  LATEST_TAG=$(git tag -l | grep -E "beta" | sort -V | tail -1 2>/dev/null || echo "")
elif [[ "${PKG_RELEASE_STREAM:-stable}" == "alpha" ]]; then
  # For alpha releases, only look at alpha tags
  LATEST_TAG=$(git tag -l | grep -E "alpha" | sort -V | tail -1 2>/dev/null || echo "")
elif [[ "${PKG_RELEASE_STREAM:-stable}" == "legacy" ]]; then
  # For legacy releases, only look at legacy tags
  LATEST_TAG=$(git tag -l | grep -E "legacy" | sort -V | tail -1 2>/dev/null || echo "")
elif [[ "${PKG_RELEASE_STREAM:-stable}" == "synology" ]]; then
  # For synology releases, only look at synology tags
  LATEST_TAG=$(git tag -l | grep -E "synology" | sort -V | tail -1 2>/dev/null || echo "")
else
  # For stable releases, only look at stable tags (no beta, alpha, legacy, or synology in name)
  LATEST_TAG=$(git tag -l | grep -v -E "(beta|alpha|legacy|synology)" | sort -V | tail -1 2>/dev/null || echo "")
fi

log "Latest tag for stream '${PKG_RELEASE_STREAM:-stable}': ${LATEST_TAG:-none}"

# Check for package manifest changes if we have a previous tag
HAS_PACKAGE_CHANGES=false
if [ -n "$LATEST_TAG" ]; then
  # Get the previous package.json for comparison
  PACKAGE_JSON_PATH=""
  case "${PKG_RELEASE_STREAM:-stable}" in
    beta)
      PACKAGE_JSON_PATH="beta/package.json"
      ;;
    alpha)
      PACKAGE_JSON_PATH="alpha/package.json"
      ;;
    legacy)
      PACKAGE_JSON_PATH="legacy/package.json"
      ;;
    synology)
      PACKAGE_JSON_PATH="synology/package.json"
      ;;
    *)
      PACKAGE_JSON_PATH="package.json"
      ;;
  esac
  
  log "Previous package.json path for comparison: ${PACKAGE_JSON_PATH:-none}"

  # Compare package versions with previous tag
  if [ -n "$PACKAGE_JSON_PATH" ] && git show "$LATEST_TAG:$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
    # Define the list of dependencies to check
    DEPENDENCIES=(
      "@homebridge/homebridge-apt-pkg"
      "ffmpeg-for-homebridge"
    )

    # Iterate through the dependencies
    for DEP in "${DEPENDENCIES[@]}"; do
      # Get the previous version of the dependency from the latest tag
      PREV_VERSION=$(git show "$LATEST_TAG:$PACKAGE_JSON_PATH" 2>/dev/null | jq -r ".dependencies[\"$DEP\"] // \"unknown\"")

      # Get the current version of the dependency from the current package.json
      CURR_VERSION=$(jq -r ".dependencies[\"$DEP\"] // \"unknown\"" "${REPO_ROOT}/${PACKAGE_JSON_PATH}")

      # Check if the version has changed and add it to the changelog
      if [[ "$PREV_VERSION" != "$CURR_VERSION" && "$CURR_VERSION" != "unknown" ]]; then
        log "Dependency ${DEP} changed from ${PREV_VERSION} to ${CURR_VERSION}, ${HAS_PACKAGE_CHANGES}"
        if [ "$HAS_PACKAGE_CHANGES" = false ]; then

          log "Adding Package Manifest Changes section to release body"
          echo -e "## Docker Build Instruction Changes" >> "$MANIFEST"
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



if gh release download "$LATEST_TAG" --pattern "*.manifest" --dir ${PREVIOUS_DIR} 2>/dev/null; then
  echo -e "\n## Changes Since Previous Release ($LATEST_TAG):\n" >> "$MANIFEST"
  
  # Iterate through all manifest files in ${OUTPUT_DIR}
  for OUTPUT_MANIFEST in ${OUTPUT_DIR}/*manifest; do
    # Extract the base name of the manifest file
    MANIFEST_NAME=$(basename "$OUTPUT_MANIFEST")
    log "Processing manifest for changes: $MANIFEST_NAME"
    # Check if a corresponding file exists in ${PREVIOUS_DIR}
    PREVIOUS_MANIFEST="${PREVIOUS_DIR}/${MANIFEST_NAME}"
    if [[ -f "$PREVIOUS_MANIFEST" ]]; then
      TMP_DIFF="/tmp/manifest.diff.$$"
      # Compare the manifests and capture differences
      info "diff -u \"$PREVIOUS_MANIFEST\" \"$OUTPUT_MANIFEST\" "
      if ! diff -u "$PREVIOUS_MANIFEST" "$OUTPUT_MANIFEST" > ${TMP_DIFF} 2>/dev/null; then
        # Check if there are any meaningful changes in the diff
        if grep -qE "^[+-] \|" ${TMP_DIFF}; then
          echo "### Changes in ${MANIFEST_NAME}" >> "$MANIFEST"
          echo "\`\`\`diff" >> "$MANIFEST"
          # Include the diff output, sorted for readability
          grep -E "^[+-] \|" ${TMP_DIFF} | sort -k2 | head -20 >> "$MANIFEST"
          echo "\`\`\`" >> "$MANIFEST"
        else
          warn "No meaningful changes detected in ${MANIFEST_NAME}."
          echo "No meaningful changes detected in ${MANIFEST_NAME}." >> "$MANIFEST"
          cat ${TMP_DIFF}
        fi
        rm -f ${TMP_DIFF} || true
      else
        warn "No changes detected in ${MANIFEST_NAME}."
        echo "No changes detected in ${MANIFEST_NAME}." >> "$MANIFEST"
      fi
    else
      # If no corresponding file exists in ${PREVIOUS_DIR}, note it in the manifest
      echo "No previous manifest found for ${MANIFEST_NAME}." >> "$MANIFEST"
    fi
  done
  
  # Show Docker image specific changes

  # echo "See [commit history](https://github.com/homebridge/homebridge-vm-image/compare/$LATEST_TAG...${{ needs.set-versions.outputs.DOCKER_HOMEBRIDGE_VERSION }}) for Docker-specific changes." >> "$MANIFEST"
else
  echo -e "\n## Changes Since Previous Release\n" >> "$MANIFEST"
  echo "Previous release manifest not available for comparison." >> "$MANIFEST"
fi

echo -e "\n### Docker Homebridge Changes" >> "$MANIFEST"
if [ -n "$LATEST_TAG" ]; then
  # Get commits since the latest tag of the same type
  CHANGELOG_COMMITS=$(git log --oneline --no-merges "$LATEST_TAG"..HEAD 2>/dev/null)
  
  if [ -n "$CHANGELOG_COMMITS" ]; then
    # Add code changes section header
    if [ "$HAS_PACKAGE_CHANGES" = true ]; then
      echo "### Code Changes" >> "$MANIFEST"
      echo >> "$MANIFEST"
    fi
    # Format commits as changelog entries
    while IFS= read -r commit; do
      if [ -n "$commit" ]; then
        # Extract commit hash and message
        COMMIT_HASH=$(echo "$commit" | cut -d' ' -f1)
        COMMIT_MSG=$(echo "$commit" | cut -d' ' -f2-)
        echo "* $COMMIT_MSG (\`$COMMIT_HASH\`)" >> "$MANIFEST"
      fi
    done <<< "$CHANGELOG_COMMITS"
  else
    if [ "$HAS_PACKAGE_CHANGES" = false ]; then
      echo "* No new commits since last ${PKG_RELEASE_STREAM:-stable} release" >> "$MANIFEST"
    fi
  fi
else
  # If no tags of this type exist, show recent commits
  RECENT_COMMITS=$(git log --oneline --no-merges -5 2>/dev/null)
  if [ -n "$RECENT_COMMITS" ]; then
    echo "### Recent Changes" >> "$MANIFEST"
    echo >> "$MANIFEST"
    while IFS= read -r commit; do
      if [ -n "$commit" ]; then
        COMMIT_HASH=$(echo "$commit" | cut -d' ' -f1)
        COMMIT_MSG=$(echo "$commit" | cut -d' ' -f2-)
        echo "* $COMMIT_MSG (\`$COMMIT_HASH\`)" >> "$MANIFEST"
      fi
    done <<< "$RECENT_COMMITS"
  else
    echo "* No commit history available" >> "$MANIFEST"
  fi
fi

echo >> "$MANIFEST"