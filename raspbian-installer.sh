#!/bin/bash

#
# This script is meant for a quick and easy setup of homebridge/homebridge on Raspberry Pi OS
# It should be executed on a fresh install of 64-bit Raspberry Pi OS Lite (Debian 12 or 13)
#

set -e

INSTALL_DIR=$HOME/homebridge

. /etc/os-release

LP="[homebridge/homebridge installer]"

# Check OS

if [ "$VERSION_ID" != "12" ] && [ "$VERSION_ID" != "13" ]; then
  echo "$LP ERROR: $PRETTY_NAME is not supported. Use 64-bit Raspberry Pi OS based on Debian 12 or 13."
  exit 1
fi

# Check the OS is 64-bit. Node.js no longer makes 32-bit ARM builds, so the
# Homebridge Docker images are dropping 32-bit ARM (arm32v7)

ARCH=$(dpkg --print-architecture)

if [ "$ARCH" != "arm64" ] && [ "$ARCH" != "amd64" ]; then
  echo "$LP ERROR: this is a $ARCH (32-bit) system. Install the 64-bit version of Raspberry Pi OS and run this script again."
  exit 1
fi

echo "$LP Installing on $PRETTY_NAME ($ARCH)..."

# Step 1: Install Docker and the Docker Compose plugin from Docker's own repository
# https://docs.docker.com/engine/install/debian/

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "$LP Docker and Docker Compose are already installed"
else
  echo "$LP Installing Docker..."

  sudo apt-get update
  sudo apt-get -y install ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $VERSION_CODENAME stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  echo "$LP Docker Installed"
fi

sudo usermod -aG docker "$USER"

# Step 2: Create Docker Compose Manifest

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "$LP Created $INSTALL_DIR"

TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")

cat >"$INSTALL_DIR/docker-compose.yml" <<EOL
services:
  homebridge:
    image: homebridge/homebridge:latest
    restart: always
    network_mode: host
    environment:
      - TZ=$TZ
    volumes:
      - ./volumes/homebridge:/homebridge
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "1"
EOL

echo "$LP Created $INSTALL_DIR/docker-compose.yml"

# Step 3: Pull Docker Image

echo "$LP Pulling Homebridge Docker image (this may take up to 20 minutes)..."

sudo docker compose pull

# Step 4: Start Container

echo "$LP Starting Homebridge Docker container..."

sudo docker compose up -d

# Step 5: Wait for the Homebridge UI to come up

echo "$LP Waiting for Homebridge to start..."

until curl --output /dev/null --silent --head --fail http://localhost:8581; do
  printf '.'
  sleep 5
done

echo

# Step 6: Success

IP=$(hostname -I)

echo "$LP"
echo "$LP Homebridge Installation Complete!"
echo "$LP You can access the Homebridge UI via:"
echo "$LP"

for ip in $IP; do
  if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$LP http://$ip:8581"
  else
    echo "$LP http://[$ip]:8581"
  fi
done

echo "$LP"
echo "$LP Installed to: $INSTALL_DIR"
echo "$LP Log out and back in to run docker commands without sudo."
echo "$LP Thanks for installing homebridge/homebridge!"
