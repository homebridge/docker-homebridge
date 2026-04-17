#! /bin/bash

# If used in GitHub Actions, ensure we have a full git history
#     - name: Checkout
#      uses: actions/checkout@v4
#      with:
#        fetch-depth: 0

# Exit on error
set -e

# Require Bash 4.0+ for associative array support
if ((BASH_VERSINFO[0] < 4)); then
  echo "ERROR: Bash 4.0 or higher is required (found ${BASH_VERSION})" >&2
  exit 1
fi

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

# Regex that matches manifest data rows (package/version pairs).
# Lines start with optional whitespace then '|' followed by a non-colon, non-space char,
# which excludes the header row ('| Package |') and the separator row ('|:-------:|').
readonly MANIFEST_DATA_ROW='^\s*\|[^: ]'

# Trim leading and trailing whitespace from a string.
trim() { echo "$1" | xargs; }

# Get the latest tag to compare against, filtered by release type
if [[ "${PKG_RELEASE_STREAM:-stable}" == "beta" ]]; then
  # For beta releases, only look at beta tags
  LATEST_TAG=$(git tag -l | grep -E "beta" | sort -V | tail -1 2>/dev/null || echo "")
elif [[ "${PKG_RELEASE_STREAM:-stable}" == "alpha" ]]; then
  # For alpha releases, only look at alpha tags
  LATEST_TAG=$(git tag -l | grep -E "alpha" | sort -V | tail -1 2>/dev/null || echo "")
else
  # For stable releases, only look at stable tags (no beta or alpha in name)
  LATEST_TAG=$(git tag -l | grep -v -E "(beta|alpha|v)" | sort -V | tail -1 2>/dev/null || echo "")
fi

log "Latest tag for stream '${PKG_RELEASE_STREAM:-stable}': ${LATEST_TAG:-none}"

# Check for package.json dependency changes and collect them for later output
HAS_PACKAGE_CHANGES=false
PACKAGE_CHANGES_TEXT=""
if [ -n "$LATEST_TAG" ]; then
  # Get the previous package.json for comparison
  PACKAGE_JSON_PATH=""
  case "${PKG_RELEASE_STREAM:-stable}" in
    beta)  PACKAGE_JSON_PATH="beta/package.json" ;;
    alpha) PACKAGE_JSON_PATH="alpha/package.json" ;;
    *)     PACKAGE_JSON_PATH="package.json" ;;
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

      # Check if the version has changed and collect it
      if [[ "$PREV_VERSION" != "$CURR_VERSION" && "$CURR_VERSION" != "unknown" ]]; then
        log "Dependency ${DEP} changed from ${PREV_VERSION} to ${CURR_VERSION}"
        HAS_PACKAGE_CHANGES=true
        PACKAGE_CHANGES_TEXT+="* **${DEP}**: Updated from $PREV_VERSION to $CURR_VERSION\n"
      fi
    done
  else
    warn "Could not find previous package.json at tag ${LATEST_TAG} for comparison."
  fi
fi

# Extract a release version string from a manifest file.
manifest_release_version() {
  grep "Release Version:" "$1" | sed 's/.*Release Version:[[:space:]]*//' | tr -d '\r\n '
}

# Write a single-column manifest table: Package | Version (release).
# Usage: write_manifest_table_current <manifest_file> <output_file>
write_manifest_table_current() {
  local src="$1" out="$2"
  local release
  release=$(manifest_release_version "$src")
  echo "| Package | Version (${release}) |" >> "$out"
  echo "|:--------|:-----------------:|" >> "$out"
  while IFS='|' read -r _ package version _; do
    package=$(trim "$package")
    version=$(trim "$version")
    if [[ -n "$package" && -n "$version" ]]; then
      echo "| ${package} | ${version} |" >> "$out"
    fi
  done < <(grep -E "$MANIFEST_DATA_ROW" "$src")
}

# Write a two-column manifest table: Package | Previous Version | Current Version.
# Changed packages are highlighted in bold.
# Usage: write_manifest_table_comparison <current_manifest> <previous_manifest> <output_file>
write_manifest_table_comparison() {
  local current_src="$1" previous_src="$2" out="$3"
  local current_release prev_release
  current_release=$(manifest_release_version "$current_src")
  prev_release=$(manifest_release_version "$previous_src")

  # Pre-load previous manifest versions into an associative array for O(1) lookup.
  declare -A prev_versions
  while IFS='|' read -r _ pkg ver _; do
    pkg=$(trim "$pkg")
    ver=$(trim "$ver")
    if [[ -n "$pkg" && -n "$ver" ]]; then
      prev_versions["$pkg"]="$ver"
    fi
  done < <(grep -E "$MANIFEST_DATA_ROW" "$previous_src")

  log "Creating combined manifest table: ${prev_release} → ${current_release}"
  echo "| Package | Previous Version (${prev_release}) | Current Version (${current_release}) |" >> "$out"
  echo "|:--------|:-----------------:|:----------------:|" >> "$out"

  while IFS='|' read -r _ package version _; do
    package=$(trim "$package")
    version=$(trim "$version")
    if [[ -n "$package" && -n "$version" ]]; then
      prev_version="${prev_versions[$package]:-N/A}"
      if [[ "$prev_version" != "$version" ]]; then
        echo "| **${package}** | ${prev_version} | **${version}** |" >> "$out"
      else
        echo "| ${package} | ${version} | ${version} |" >> "$out"
      fi
    fi
  done < <(grep -E "$MANIFEST_DATA_ROW" "$current_src")
}

# Build the Package Manifest section.
# If a previous release manifest is available, produce a side-by-side
# "Previous Version | Current Version" table.  Otherwise show current only.
log "Building package manifest section"
echo -e "\n## Package Manifest\n" >> "$MANIFEST"

if [ -n "$LATEST_TAG" ] && gh release download "$LATEST_TAG" --pattern "*.manifest" --dir ${PREVIOUS_DIR} 2>/dev/null; then
  log "Previous manifests downloaded from tag ${LATEST_TAG}"

  for OUTPUT_MANIFEST in ${OUTPUT_DIR}/*manifest; do
    MANIFEST_NAME=$(basename "$OUTPUT_MANIFEST")
    PREVIOUS_MANIFEST="${PREVIOUS_DIR}/${MANIFEST_NAME}"

    if [[ -f "$PREVIOUS_MANIFEST" ]]; then
      write_manifest_table_comparison "$OUTPUT_MANIFEST" "$PREVIOUS_MANIFEST" "$MANIFEST"
    else
      log "No previous manifest found for ${MANIFEST_NAME}, showing current only"
      write_manifest_table_current "$OUTPUT_MANIFEST" "$MANIFEST"
    fi
    echo >> "$MANIFEST"
  done
else
  # No previous release available — show current versions only
  log "No previous manifests available, showing current versions only"

  for OUTPUT_MANIFEST in ${OUTPUT_DIR}/*manifest; do
    write_manifest_table_current "$OUTPUT_MANIFEST" "$MANIFEST"
    echo >> "$MANIFEST"
  done
fi

# Docker Build Instruction Changes (package.json dependency changes)
if [ "$HAS_PACKAGE_CHANGES" = true ]; then
  echo -e "\n## Docker Build Instruction Changes\n" >> "$MANIFEST"
  echo -e "$PACKAGE_CHANGES_TEXT" >> "$MANIFEST"
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
