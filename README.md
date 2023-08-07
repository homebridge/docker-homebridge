[![Donate](https://img.shields.io/badge/donate-paypal-yellowgreen.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=ZEW8TFQCU2MSJ&source=url)
[![Docker Build Status](https://github.com/homebridge/docker-homebridge/workflows/Build/badge.svg)](https://github.com/homebridge/docker-homebridge/actions)
[![Docker Pulls](https://img.shields.io/docker/pulls/homebridge/homebridge.svg)](https://hub.docker.com/r/homebridge/homebridge/)
[![Discord](https://img.shields.io/discord/432663330281226270?color=728ED5&logo=discord&label=discord)](https://discord.gg/Cmq8a44)

<H1>Important Update</H1>

We have moved the hosting of the offical homebridge docker image from **oznu/homebridge** to **homebridge/homebridge**.  Please update your environments as needed to pickup the latest image.

# Homebridge Docker Image

This Ubuntu Linux based Docker image allows you to run [Nfarina's](https://github.com/nfarina) [Homebridge](https://github.com/homebridge/homebridge) on your home network which emulates the iOS HomeKit API.

This is a multi-arch image and will run on x86_64, Raspberry Pi 2, 3, 4, Zero 2 W, or other Docker-enabled ARMv7/8 devices. Docker will automatically pull the correct image for your system.

| Image Tag             | Architectures           | Base Image         | 
| :-------------------- | :-----------------------| :----------------- | 
| latest, ubuntu        | amd64, arm32v7, arm64v8 | Ubuntu 22.04       | 

## Step-By-Step Guides

- [Running Homebridge with Docker on Linux](https://github.com/homebridge/homebridge/wiki/Install-Homebridge-on-Docker)
- [Running Homebridge on a Synology NAS](https://github.com/homebridge/docker-homebridge/wiki/Homebridge-on-Synology)
- [Running Homebridge on Unraid](https://github.com/homebridge/docker-homebridge/wiki/Homebridge-on-Unraid)

## Compatibility

Homebridge requires full access to your local network to function correctly which can be achieved using the ```--net=host``` flag.

**This image will not work when using [Docker for Mac](https://docs.docker.com/docker-for-mac/) or [Docker for Windows](https://docs.docker.com/docker-for-windows/) due to [this](https://github.com/docker/for-mac/issues/68) and [this](https://github.com/docker/for-win/issues/543)**.


## Usage

Command Line:

```bash
docker run --net=host --name=homebridge -v $(pwd)/homebridge:/homebridge homebridge/homebridge:latest
```

Using [Docker Compose](https://docs.docker.com/compose/) (recommended):

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
        max-size: "10mb"
        max-file: "1"
```

## Parameters

The parameters are split into two halves, separated by a colon, the left hand side representing the host and the right the container side.

* `--net=host` - Shares host networking with container, **required**
* `-v /homebridge` - The Homebridge config and plugin location, **required**

##### *Optional Settings:*

* `-e TZ` - for [timezone information](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) e.g. `-e TZ=Australia/Canberra`
* `-e ENABLE_AVAHI` - default is `1`; set to `0` to prevent the Avahi mDNS service running in the container

## Homebridge UI

This image comes with the [Homebridge UI](https://github.com/homebridge/homebridge-config-ui-x) pre-installed and is the easiest way to manage all aspects of Homebridge.

To manage Homebridge go to `http://<ip of server>:8581` in your browser. For example, `http://192.168.1.20:8581`. From here you can install, remove and update plugins, modify the Homebridge config.json and restart Homebridge.

<p align="center">
  <img width="600px" src="https://user-images.githubusercontent.com/3979615/71886653-b16d3f80-3190-11ea-9ff8-49dc4ae4fff0.png">
</p>

## Automated Updates

Automated updates of the Homebridge Docker Image using tools such as Watchtower or similar are strongly discouraged and are done so at your own risk.

**NOTE** - The version of Homebridge **IS NOT** tied to the version of the container.  You can update Homebridge, the Homebridge UI and the Node.js runtime from inside the container.

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

## License

Copyright (C) 2023 homebridge
Copyright (C) 2017-2022 oznu

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the [GNU General Public License](./LICENSE) for more details.
