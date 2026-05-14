#!/bin/sh

set -e
# Extract versions from package.json
export HOMEBRIDGE_APT_PKG_VERSION=$(jq -r '.dependencies["@homebridge/homebridge-apt-pkg"]' legacy/package.json | sed 's/\^//')
export HOMEBRIDGE_APT_PKG_FILE=$(echo "$HOMEBRIDGE_APT_PKG_VERSION" | sed 's/\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)-legacy\(\.[0-9][0-9]*\)/\1.legacy\2/')
export FFMPEG_FOR_HOMEBRIDGE_VERSION=$(jq -r '.dependencies["ffmpeg-for-homebridge"]' legacy/package.json | sed 's/\^//')
export DOCKER_HOMEBRIDGE_VERSION=legacy-$(date +'%Y-%m-%d')

export HOMEBRIDGE_IMAGE='docker-homebridge'

echo HOMEBRIDGE_APT_PKG_VERSION ${HOMEBRIDGE_APT_PKG_VERSION}
echo HOMEBRIDGE_APT_PKG_FILE ${HOMEBRIDGE_APT_PKG_FILE}
echo FFMPEG_FOR_HOMEBRIDGE_VERSION ${FFMPEG_FOR_HOMEBRIDGE_VERSION}
echo DOCKER_HOMEBRIDGE_VERSION ${DOCKER_HOMEBRIDGE_VERSION}

# Build Docker image
docker build -f ./Dockerfile \
  --build-arg HOMEBRIDGE_APT_PKG_VERSION=v${HOMEBRIDGE_APT_PKG_VERSION} \
  --build-arg HOMEBRIDGE_APT_PKG_FILE=v${HOMEBRIDGE_APT_PKG_FILE} \
  --build-arg FFMPEG_FOR_HOMEBRIDGE_VERSION=v${FFMPEG_FOR_HOMEBRIDGE_VERSION} \
  --build-arg DOCKER_HOMEBRIDGE_VERSION=${DOCKER_HOMEBRIDGE_VERSION} \
  --build-arg BASE_IMAGE=22.04 \
  -t ${HOMEBRIDGE_IMAGE} .

# Start container using docker-compose
cd test
docker compose up
