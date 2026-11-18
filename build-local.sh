#!/bin/sh

# Builds the image of one release stream on this machine, then starts it with
# test/docker-compose.yml (host networking, data in test/volumes/homebridge).
#
# Usage: ./build-local.sh [stream] [--build-only]
#   stream        stable (default), beta, alpha, legacy or synology
#   --build-only  build the image, do not start a container
#
# The versions come from the package.json of the stream, the same file the
# release workflow reads. BASE_IMAGE can be set in the environment to try
# another base image.
#
# Needs: docker (with BuildKit) and jq.

set -e

STREAM="${1:-stable}"
BUILD_ONLY="${2:-}"

case "$STREAM" in
  stable)
    PKG_FILE="package.json"
    DOCKER_HOMEBRIDGE_VERSION="$(date +'%Y-%m-%d')"
    ;;
  beta | alpha | legacy | synology)
    PKG_FILE="${STREAM}/package.json"
    DOCKER_HOMEBRIDGE_VERSION="${STREAM}-$(date +'%Y-%m-%d')"
    ;;
  *)
    echo "Unknown stream '${STREAM}'. Use stable, beta, alpha, legacy or synology." >&2
    exit 1
    ;;
esac

cd "$(dirname "$0")"

HOMEBRIDGE_APT_PKG_VERSION=$(jq -r '.dependencies["@homebridge/homebridge-apt-pkg"]' "$PKG_FILE" | sed 's/\^//')
FFMPEG_FOR_HOMEBRIDGE_VERSION=$(jq -r '.dependencies["ffmpeg-for-homebridge"]' "$PKG_FILE" | sed 's/\^//')
BASE_IMAGE=${BASE_IMAGE:-$(jq -r '.docker.baseImage // "ubuntu:24.04"' "$PKG_FILE")}
HOMEBRIDGE_IMAGE='docker-homebridge'
export HOMEBRIDGE_IMAGE

echo "STREAM ${STREAM}"
echo "HOMEBRIDGE_APT_PKG_VERSION ${HOMEBRIDGE_APT_PKG_VERSION}"
echo "FFMPEG_FOR_HOMEBRIDGE_VERSION ${FFMPEG_FOR_HOMEBRIDGE_VERSION}"
echo "DOCKER_HOMEBRIDGE_VERSION ${DOCKER_HOMEBRIDGE_VERSION}"
echo "BASE_IMAGE ${BASE_IMAGE}"

# Build Docker image
docker build -f ./Dockerfile \
  --build-arg "HOMEBRIDGE_APT_PKG_VERSION=v${HOMEBRIDGE_APT_PKG_VERSION}" \
  --build-arg "FFMPEG_FOR_HOMEBRIDGE_VERSION=v${FFMPEG_FOR_HOMEBRIDGE_VERSION}" \
  --build-arg "DOCKER_HOMEBRIDGE_VERSION=${DOCKER_HOMEBRIDGE_VERSION}" \
  --build-arg "DOCKER_HOMEBRIDGE_BUILD=local.$(date +'%Y%m%d%H%M%S')" \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  -t "${HOMEBRIDGE_IMAGE}" .

if [ "$BUILD_ONLY" = "--build-only" ]; then
  echo "Built the image ${HOMEBRIDGE_IMAGE}. Test it with: test/container/run.sh ${HOMEBRIDGE_IMAGE}"
  exit 0
fi

# Start container using docker-compose
echo "Starting the container. Press Ctrl+C to stop it."
echo "To start it again later: cd test && HOMEBRIDGE_IMAGE=${HOMEBRIDGE_IMAGE} docker compose up"
cd test
docker compose up
