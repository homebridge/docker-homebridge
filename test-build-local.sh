#!/bin/sh

# Extract versions from package.json
export HOMEBRIDGE_APT_PKG_VERSION=$(jq -r '.dependencies["@homebridge/homebridge-apt-pkg"]' package.json | sed 's/\^//')
export FFMPEG_FOR_HOMEBRIDGE_VERSION=$(jq -r '.dependencies["ffmpeg-for-homebridge"]' package.json | sed 's/\^//')
export DOCKER_HOMEBRIDGE_VERSION=$(date +'%Y-%m-%d')

export HOMEBRIDGE_IMAGE='docker-homebridge'

# Allow BASE_IMAGE to be overridden via environment variable (defaults to 24.04)
export BASE_IMAGE=${BASE_IMAGE:-24.04}

echo HOMEBRIDGE_APT_PKG_VERSION ${HOMEBRIDGE_APT_PKG_VERSION}
echo FFMPEG_FOR_HOMEBRIDGE_VERSION ${FFMPEG_FOR_HOMEBRIDGE_VERSION}
echo DOCKER_HOMEBRIDGE_VERSION ${DOCKER_HOMEBRIDGE_VERSION}
echo BASE_IMAGE ${BASE_IMAGE}

# Build Docker image
docker build -f ./Dockerfile \
  --build-arg HOMEBRIDGE_APT_PKG_VERSION=v${HOMEBRIDGE_APT_PKG_VERSION} \
  --build-arg FFMPEG_FOR_HOMEBRIDGE_VERSION=v${FFMPEG_FOR_HOMEBRIDGE_VERSION} \
  --build-arg DOCKER_HOMEBRIDGE_VERSION=${DOCKER_HOMEBRIDGE_VERSION} \
  --build-arg BASE_IMAGE=${BASE_IMAGE} \
  -t ${HOMEBRIDGE_IMAGE} .

# Start container using docker-compose
cd test
docker compose up
echo "Container started. Press Ctrl+C to stop."
echo "To rerun the container, use 'cd test &&   HOMEBRIDGE_IMAGE=\"docker-homebridge\" docker compose up' again."