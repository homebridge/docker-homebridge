#!/usr/bin/env bash
# Cleans up after local test builds: removes the Homebridge containers and
# images from this machine.
#
# Usage: scripts/purge-docker.sh [--yes]
#
# - Only images with these names are removed: docker-homebridge (the name the
#   local build script uses), homebridge/homebridge and ghcr.io/homebridge/homebridge,
#   and only the containers made from them.
# - No other container or image is touched. Volumes and networks are never
#   removed: a volume may hold a real Homebridge set-up.
# - It lists what it found and asks first. --yes skips the question.

set -euo pipefail

IMAGE_NAMES=(docker-homebridge homebridge/homebridge ghcr.io/homebridge/homebridge)
ASSUME_YES=false
if [[ "${1:-}" == "--yes" ]]; then
  ASSUME_YES=true
fi

IMAGES=()
CONTAINERS=()
for name in "${IMAGE_NAMES[@]}"; do
  while IFS= read -r image; do
    if [[ -n "$image" ]]; then IMAGES+=("$image"); fi
  done < <(docker images --format '{{.Repository}}:{{.Tag}}' "$name" | sort -u)
done
for image in "${IMAGES[@]}"; do
  while IFS= read -r container; do
    if [[ -n "$container" ]]; then CONTAINERS+=("$container"); fi
  done < <(docker ps -a -q --filter "ancestor=${image}")
done

if [[ ${#IMAGES[@]} -eq 0 ]]; then
  echo "No Homebridge images found. Nothing to do."
  exit 0
fi

echo "Homebridge images found:"
printf '  %s\n' "${IMAGES[@]}"
echo "Containers made from them: ${#CONTAINERS[@]}"
if [[ ${#CONTAINERS[@]} -gt 0 ]]; then
  printf '  %s\n' "${CONTAINERS[@]}"
fi

if [[ "$ASSUME_YES" != "true" ]]; then
  read -r -p "Stop and remove these containers and images? Volumes are kept. [y/N] " answer
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Nothing was removed."
    exit 0
  fi
fi

if [[ ${#CONTAINERS[@]} -gt 0 ]]; then
  docker rm -f "${CONTAINERS[@]}"
fi
docker rmi "${IMAGES[@]}"
echo "Done."
