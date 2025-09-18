[![Donate](https://img.shields.io/badge/donate-paypal-yellowgreen.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=ZEW8TFQCU2MSJ&source=url)
[![Build and Push Docker Images](https://github.com/homebridge/docker-homebridge/actions/workflows/build_and_push.yml/badge.svg)](https://github.com/homebridge/docker-homebridge/actions/workflows/build_and_push.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/homebridge/homebridge.svg)](https://hub.docker.com/r/homebridge/homebridge/)
[![Discord](https://img.shields.io/discord/432663330281226270?color=728ED5&logo=discord&label=discord)](https://discord.gg/Cmq8a44)

<H1>Important Update</H1>

We have moved the hosting of the offical homebridge docker image from **oznu/homebridge** to **homebridge/homebridge**.  Please update your environments as needed to pickup the latest image.

# Homebridge Docker Image

This Ubuntu Linux based Docker image allows you to run [Nfarina's](https://github.com/nfarina) [Homebridge](https://github.com/homebridge/homebridge) on your home network which emulates the iOS HomeKit API.

This is a multi-arch image and will run on x86_64, Raspberry Pi 2, 3, 4, Zero 2 W, or other Docker-enabled ARMv7/8 devices. Docker will automatically pull the correct image for your system.

| Image Tag             | Architectures           | Base Image         | Release Type |
| :-------------------- | :-----------------------| :----------------- | :----------- |
| latest, ubuntu        | amd64, arm32v7, arm64v8 | Ubuntu 24.04       | Stable       |
| beta                  | amd64, arm32v7, arm64v8 | Ubuntu 24.04       | Beta         |
| alpha                 | amd64, arm32v7, arm64v8 | Ubuntu 24.04       | Alpha        | 

### Release Types

- **Stable** (`latest`, `ubuntu`): Stable releases using the latest stable versions of Homebridge and plugins
- **Beta** (`beta`): Pre-release versions with beta versions of Homebridge and the Homebridge UI for testing new features
- **Alpha** (`alpha`): Early pre-release versions with alpha versions of Homebridge and the Homebridge UI for early testing and development 

## Step-By-Step Guides

- [Running Homebridge with Docker on Linux](https://github.com/homebridge/homebridge/wiki/Install-Homebridge-on-Docker)
- **Synology NAS:**
  - [DSM 6 - Using Docker](https://github.com/homebridge/docker-homebridge/wiki/Homebridge-on-Synology-DSM-6-with-Docker) *(Docker required)*
  - [DSM 7 - Native Package](https://github.com/homebridge/homebridge/wiki/Install-Homebridge-on-Synology-DSM) *(Package Center)*
- [Running Homebridge on Unraid](https://github.com/homebridge/docker-homebridge/wiki/Homebridge-on-Unraid)

> **Note for Synology DSM 6 Users:** DSM 6 requires using this Docker image as there's no native package available. Make sure to use the `DSM_HOSTNAME` environment variable with your NAS hostname for proper HomeKit discovery. DSM 7 users should use the [native Homebridge package](https://github.com/homebridge/homebridge/wiki/Install-Homebridge-on-Synology-DSM) instead of Docker.

## Compatibility

Homebridge requires full access to your local network to function correctly which can be achieved using the ```--net=host``` flag.

**This image will not work when using [Docker for Mac](https://docs.docker.com/docker-for-mac/) or [Docker for Windows](https://docs.docker.com/docker-for-windows/) due to [this](https://github.com/homebridge/docker-homebridge/issues/570)**.

## Usage

### Using [Docker Compose](https://docs.docker.com/compose/) (recommended):

1. Create the file `docker-compose.yml`

```yml
version: '2'
services:
  homebridge:
    image: homebridge/homebridge:latest
    restart: always
    network_mode: host
    volumes:
      - ./volumes/homebridge:/homebridge
    logging:
      driver: json-file
      options:
        max-size: '10m'
        max-file: '1'
    healthcheck:
      test: curl --fail localhost:8581 || exit 1
      interval: 60s
      retries: 5
      start_period: 300s
      timeout: 2s
```

2. Start docker with

```bash
docker compose up
```

### For Synology DSM 6:

If you're running on Synology DSM 6, use this docker-compose configuration that includes the DSM_HOSTNAME environment variable:

```yml
version: '2'
services:
  homebridge:
    image: homebridge/homebridge:latest
    restart: always
    network_mode: host
    environment:
      - DSM_HOSTNAME=your-synology-hostname
    volumes:
      - ./volumes/homebridge:/homebridge
    logging:
      driver: json-file
      options:
        max-size: '10m'
        max-file: '1'
    healthcheck:
      test: curl --fail localhost:8581 || exit 1
      interval: 60s
      retries: 5
      start_period: 300s
      timeout: 2s
```

Replace `your-synology-hostname` with your actual NAS hostname.

### Or Command Line:

```bash
docker run --net=host --name=homebridge -v $(pwd)/homebridge:/homebridge homebridge/homebridge:latest
```

## Parameters

The parameters are split into two halves, separated by a colon, the left hand side representing the host and the right the container side.

* `--net=host` - Shares host networking with container, **required**
* `-v /homebridge` - The Homebridge config and plugin location, **required**

##### *Optional Settings:*

* `-e TZ` - for [timezone information](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) e.g. `-e TZ=Australia/Canberra`
* `-e ENABLE_AVAHI` - default is `1`; set to `0` to prevent the Avahi mDNS service running in the container
* `-e DSM_HOSTNAME` - for Synology DSM 6 systems, set to your NAS hostname for proper mDNS configuration

## Custom Additions

If you have custom requirements for your Docker installation, the Docker image provides the `startup.sh` script. It can be accessed from the `Startup & Environment` section in `Settings`.

<p align="center">
  <img width="600px" src="https://github.com/homebridge/docker-homebridge/blob/latest/assets/settings-startup-script.png">
</p>

The `startup.sh` script survives restarting and recreating Docker containers and runs immediately after the container starts up. It's purpose is to execute custom commands, for example installing NodeJS packages, Python packages, copying files from the host to the container, etc. For example:

<p align="center">
  <img width="600px" src="https://github.com/homebridge/docker-homebridge/blob/latest/assets/sample-startup-script.png">
</p>

## Homebridge UI

This image comes with the [Homebridge UI](https://github.com/homebridge/homebridge-config-ui-x) pre-installed and is the easiest way to manage all aspects of Homebridge.

To manage Homebridge go to `http://<ip of server>:8581` in your browser. For example, `http://192.168.1.20:8581`. From here you can install, remove and update plugins, modify the Homebridge config.json and restart Homebridge.

<p align="center">
  <img width="600px" src="https://user-images.githubusercontent.com/3979615/71886653-b16d3f80-3190-11ea-9ff8-49dc4ae4fff0.png">
</p>

## Automated Updates

Automated updates of the Homebridge Docker Image using tools such as Watchtower or similar are strongly discouraged and are done so at your own risk.

**NOTE** - Since release `2025-06-25` the version of Homebridge **IS TIED** to the version of the container.  You can update Homebridge, the Homebridge UI and the Node.js runtime from inside the container.

## Troubleshooting

#### 1. Need ffmpeg?

ffmpeg, with `libfdk-aac` audio support is included in this image.

#### 2. Container will not start on older versions of Raspbian

If you're seeing errors like the following, your host operating system needs to be updated.

See [#434](https://github.com/homebridge/docker-homebridge/issues/434) and [#441](https://github.com/homebridge/docker-homebridge/issues/441) for potential solutions.

```
Node.js[445]: ../src/util.cc:188:double node::GetCurrentTimeInMicroseconds(): Assertion `(0) == (uv_gettimeofday(&tv))' failed.
Aborted (core dumped)
```

```
homebridge_1  | s6-svscan: warning: unable to iopause: Operation not permitted
homebridge_1  | s6-svscan: warning: executing into .s6-svscan/crash
homebridge_1  | s6-svscan crashed. Killing everything and exiting.
```

```
homebridge    | # Fatal error in , line 0
homebridge    | # unreachable code
```

#### 3. Ask on Discord

Join the [Official Homebridge Discord](https://discord.gg/Cmq8a44) community and ask in the [#docker](https://discord.gg/Cmq8a44) channel.

## Container Validation

This repository includes automated validation workflows to ensure container builds work correctly:

### Manual Container Validation

To validate a specific release manually, you can trigger the **Validate Docker Container** workflow:

1. Go to [Actions](https://github.com/homebridge/docker-homebridge/actions)
2. Select "Validate Docker Container" workflow
3. Click "Run workflow"  
4. Choose the release tag to validate:
   - `latest` - Stable release
   - `beta` - Beta pre-release  
   - `alpha` - Alpha early release

The validation workflow will:
- ✅ Start the container and verify it runs successfully
- ✅ Check that Homebridge UI is accessible on port 8581
- ✅ Verify Homebridge service starts properly with version detection
- ✅ Validate container health checks pass
- ✅ Extract and validate the Docker manifest

This ensures each release works correctly before users download and run it.

## License

Copyright (C) 2024 homebridge
Copyright (C) 2017-2022 oznu

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the [GNU General Public License](./LICENSE) for more details.
