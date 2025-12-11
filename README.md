<div align="center">

# Homebridge Docker

[![Release Stage 2 - Build and Push Docker Images](https://github.com/homebridge/docker-homebridge/actions/workflows/release-stage-2_build_and_push_docker_images.yml/badge.svg)](https://github.com/homebridge/docker-homebridge/actions/workflows/release-stage-2_build_and_push_docker_images.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/homebridge/homebridge.svg)](https://hub.docker.com/r/homebridge/homebridge/)
[![Discord](https://img.shields.io/discord/432663330281226270?color=728ED5&logo=discord&label=discord)](https://discord.gg/Cmq8a44)

**Official Docker image for [Homebridge](https://github.com/homebridge/homebridge)** - Emulate the iOS HomeKit API on your network

</div>

---

## 📢 Important Update

We have migrated the official Homebridge Docker image from **`oznu/homebridge`** to **`homebridge/homebridge`**.  
Please update your configurations to use the new image location for the latest updates and features.

---

## 🚀 Quick Start

### Prerequisites
- Docker Engine with networking access
- Host network mode support (**required for HomeKit**)

> ⚠️ **Compatibility Note**: This image does **not** work with Docker Desktop for Mac or Windows due to networking limitations ([details](https://github.com/homebridge/docker-homebridge/issues/570)).

---

## 📦 Available Images

This is a **multi-architecture** Ubuntu 24.04-based image supporting x86_64, ARM32v7 (Raspberry Pi), and ARM64v8 platforms.

| Image Tag | Architectures | Base Image | Release Type | Description |
|:----------|:--------------|:-----------|:-------------|:------------|
| `latest`, `ubuntu` | amd64, arm32v7, arm64v8 | Ubuntu 24.04 | **Stable** | Production-ready with latest stable releases |
| `beta` | amd64, arm32v7, arm64v8 | Ubuntu 24.04 | **Beta** | Pre-release with beta versions for testing |
| `alpha` | amd64, arm32v7, arm64v8 | Ubuntu 24.04 | **Alpha** | Early access with alpha versions for development |

---

## 🛠️ Installation

### Using Docker Compose (Recommended)

Create a `docker-compose.yml` file:

```yaml
services:
  homebridge:
    image: homebridge/homebridge:latest
    restart: always
    network_mode: host
    hostname: docker-desktop  # Optional: Set container hostname
    volumes:
      - ./volumes/homebridge:/homebridge
    environment:
      - TZ=America/Toronto  # Optional: Set your timezone
      - ENABLE_AVAHI=1      # Optional: Enable/disable Avahi (1=enabled, 0=disabled)
    logging:
      driver: json-file
      options:
        max-size: '10m'
        max-file: '1'
    healthcheck:
      test: ["CMD-SHELL", "curl --fail http://localhost:8581 || exit 1"]
      interval: 60s
      retries: 5
      start_period: 300s
      timeout: 2s
```

Start the container:

```bash
docker compose up -d
```

### Using Docker CLI

```bash
docker run \
  --net=host \
  --name=homebridge \
  -e TZ=America/Toronto \
  -v $(pwd)/homebridge:/homebridge \
  homebridge/homebridge:latest
```

---

## ⚙️ Configuration

### Required Parameters

| Parameter | Docker Compose | Docker CLI | Description |
|:----------|:---------------|:-----------|:------------|
| Network Mode | `network_mode: host` | `--net=host` | **Required** - Enables host networking for HomeKit discovery |
| Volume Mount | `volumes:` | `-v /path:/homebridge` | **Required** - Persistent storage for config and plugins |

### Optional Parameters

| Parameter | Docker Compose | Docker CLI | Default | Description |
|:----------|:---------------|:-----------|:--------|:------------|
| Hostname | `hostname: homebridge` | `--hostname=homebridge` | Container ID | Set custom hostname for the container |
| Timezone | `environment:`<br/>`- TZ=America/Toronto` | `-e TZ=America/Toronto` | `UTC` | Set timezone ([list](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)) |
| Avahi mDNS | `environment:`<br/>`- ENABLE_AVAHI=1` | `-e ENABLE_AVAHI=1` | `1` | Set to `0` to disable Avahi mDNS service |

> **Note**: When running with `ENABLE_AVAHI=0`, you can mount the host's mDNS service to enable mDNS usage in the container:
> ```yaml
> volumes:
>   - ./volumes/homebridge:/homebridge
>   - /var/run/dbus:/var/run/dbus  # Mount host D-Bus socket
>   - /var/run/avahi-daemon/socket:/var/run/avahi-daemon/socket  # Mount host Avahi socket
> ```

---

## 🖥️ Homebridge UI

Access the **Homebridge UI** at `http://<your-server-ip>:8581`

The UI allows you to:
- ✅ Install, update, and remove plugins
- ✅ Edit Homebridge configuration
- ✅ View logs and restart Homebridge
- ✅ Manage accessories and bridges

<p align="center">
  <img width="700px" src="https://user-images.githubusercontent.com/3979615/71886653-b16d3f80-3190-11ea-9ff8-49dc4ae4fff0.png" alt="Homebridge UI Screenshot">
</p>

---

## 🔧 Custom Startup Script

For advanced customization, use the **Startup Script** feature in the UI (`Settings` → `Startup & Environment`).

<p align="center">
  <img width="600px" src="https://github.com/homebridge/docker-homebridge/blob/latest/assets/settings-startup-script.png" alt="Startup Script Settings">
</p>

The `startup.sh` script:
- Runs on every container start
- Persists across container recreations
- Can install packages, copy files, or execute custom commands

**Example:**

```bash
#!/bin/sh

# Install custom Node.js packages
npm install -g some-custom-package

# Install Python dependencies
pip3 install some-python-library

# Copy configuration from host
cp /homebridge/custom-config.json /etc/custom-config.json
```

<p align="center">
  <img width="600px" src="https://github.com/homebridge/docker-homebridge/blob/latest/assets/sample-startup-script.png" alt="Sample Startup Script">
</p>

---

## 📚 Step-by-Step Guides

- [Running Homebridge with Docker on Linux](https://github.com/homebridge/homebridge/wiki/Install-Homebridge-on-Docker)
- [Running Homebridge on Synology NAS](https://github.com/homebridge/docker-homebridge/wiki/Homebridge-on-Synology)
- [Running Homebridge on Unraid](https://github.com/homebridge/docker-homebridge/wiki/Homebridge-on-Unraid)

---

## 🔄 Updates

### Manual Updates

Pull the latest image and recreate your container:

```bash
docker compose pull
docker compose up -d
```

### Automated Updates

> ⚠️ **Not Recommended**: Automated updates using tools like Watchtower are **strongly discouraged** and done at your own risk

### In-Container Updates

Since the `2025-06-25` release, updates to  
- Homebridge core
- Homebridge UI
- Node.js runtime

will be overwritten if the container is updated.

---

## 🎥 FFmpeg Support

This image includes **FFmpeg** with `libfdk-aac` audio support for camera streaming and video processing.

---

## ✅ Container Validation

This repository includes automated validation to ensure container builds work correctly.

### Manual Validation

To validate a specific release:

1. Go to [Actions](https://github.com/homebridge/docker-homebridge/actions)
2. Select **"Validate Docker Container"**
3. Click **"Run workflow"**
4. Choose the release tag:
   - `latest` - Stable release
   - `beta` - Beta pre-release
   - `alpha` - Alpha early release

The validation workflow will:
- ✅ Start the container and verify it runs
- ✅ Check Homebridge UI accessibility on port 8581
- ✅ Verify Homebridge service starts with version detection
- ✅ Validate container health checks
- ✅ Extract and validate the Docker manifest

---

## 🐛 Troubleshooting

### 1. FFmpeg Issues

FFmpeg with `libfdk-aac` audio support is **included** in this image. No additional installation required.

### 2. Container Won't Start on Older Raspbian

If you see errors like:

```
Node.js[445]: ../src/util.cc:188:double node::GetCurrentTimeInMicroseconds(): Assertion `(0) == (uv_gettimeofday(&tv))' failed.
```

```
s6-svscan: warning: unable to iopause: Operation not permitted
```

Your host OS needs to be updated. See [#434](https://github.com/homebridge/docker-homebridge/issues/434) and [#441](https://github.com/homebridge/docker-homebridge/issues/441) for solutions.

### 3. Get Help on Discord

Join the [Official Homebridge Discord](https://discord.gg/Cmq8a44) and ask in the [#docker](https://discord.gg/Cmq8a44) channel.

---

## 📄 License

Copyright (C) 2024 homebridge  
Copyright (C) 2017-2022 oznu

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the [GNU General Public License](./LICENSE) for more details.

---

<div align="center">

**Made with ❤️ by the Homebridge community**

</div>