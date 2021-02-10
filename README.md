[![Donate](https://img.shields.io/badge/donate-paypal-yellowgreen.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=ZEW8TFQCU2MSJ&source=url)
[![Docker Build Status](https://github.com/oznu/docker-homebridge/workflows/Build/badge.svg)](https://github.com/oznu/docker-homebridge/actions)
[![Docker Pulls](https://img.shields.io/docker/pulls/oznu/homebridge.svg)](https://hub.docker.com/r/oznu/homebridge/)
[![Discord](https://img.shields.io/discord/432663330281226270?color=728ED5&logo=discord&label=discord)](https://discord.gg/Cmq8a44)

# Docker Homebridge

This Alpine/Ubuntu Linux based Docker image allows you to run [Nfarina's](https://github.com/nfarina) [Homebridge](https://github.com/nfarina/homebridge) on your home network which emulates the iOS HomeKit API.

This is a multi-arch image and will also run on a Raspberry Pi or other Docker-enabled ARMv6/7/8 devices.

| Image Tag             | Architectures           | Image OS           | 
| :-------------------- | :-----------------------| :----------------- | 
| latest                | amd64, arm32v6, arm64v8 | Alpine Linux 3.11  |
| ubuntu                | amd64, arm32v7, arm64v8 | Ubuntu 18.04       | 
| ubuntu-no-avahi       | amd64, arm32v7, arm64v8 | Ubuntu 18.04       | 

## Step-By-Step Guides

- [Running Homebridge with Docker on Linux](https://github.com/homebridge/homebridge/wiki/Install-Homebridge-on-Docker)
- [Running Homebridge on a Synology NAS](https://github.com/oznu/docker-homebridge/wiki/Homebridge-on-Synology)
- [Running Homebridge on Unraid](https://github.com/oznu/docker-homebridge/wiki/Homebridge-on-Unraid)

## Compatibility

Homebridge requires full access to your local network to function correctly which can be achieved using the ```--net=host``` flag. **This image will not work when using [Docker for Mac](https://docs.docker.com/docker-for-mac/) or [Docker for Windows](https://docs.docker.com/docker-for-windows/) due to [this](https://github.com/docker/for-mac/issues/68) and [this](https://github.com/docker/for-win/issues/543)**.


## Usage

Command Line:

```bash
docker run --net=host --name=homebridge -v $(pwd)/homebridge:/homebridge oznu/homebridge:ubuntu
```

Using [Docker Compose](https://docs.docker.com/compose/) (recommended):

```yml
version: '2'
services:
  homebridge:
    image: oznu/homebridge:ubuntu
    restart: always
    network_mode: host
    environment:
      - PGID=1000
      - PUID=1000
      - HOMEBRIDGE_CONFIG_UI=1
      - HOMEBRIDGE_CONFIG_UI_PORT=8581
      - TZ=Canberra/Australia
    volumes:
      - ./volumes/homebridge:/homebridge
```

## Parameters

The parameters are split into two halves, separated by a colon, the left hand side representing the host and the right the container side.

* `--net=host` - Shares host networking with container, **required**
* `-v /homebridge` - The Homebridge config and plugin location

##### *Optional Settings:*

* `-e PGID` - for group id - see below for explanation
* `-e PUID` - for user id - see below for explanation
* `-e TZ` - for [timezone information](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) e.g. `-e TZ=Canberra/Australia`

##### *Homebridge UI Options*:

* `-e HOMEBRIDGE_CONFIG_UI=1` - Set to `0` to disable the [Homebridge UI](https://github.com/oznu/homebridge-config-ui-x).
* `-e HOMEBRIDGE_CONFIG_UI_PORT=8581` - The port to run the [Homebridge UI](https://github.com/oznu/homebridge-config-ui-x) on. Defaults to port 8581.

### User / Group Identifiers

Sometimes when using data volumes (`-v` flags) permissions issues can arise between the host OS and the container. We avoid this issue by allowing you to specify the user `PUID` and group `PGID`. Ensure the data volume directory on the host is owned by the same user you specify and it will "just work".

In this instance `PUID=1001` and `PGID=1001`. To find yours use `id user` as below:

```
  $ id <dockeruser>
    uid=1001(dockeruser) gid=1001(dockergroup) groups=1001(dockergroup)
```

## Homebridge UI

This image comes with the [Homebridge UI](https://github.com/oznu/homebridge-config-ui-x) pre-installed and is the easiest way to manage all aspects of Homebridge.

To manage Homebridge go to `http://<ip of server>:8581` in your browser. For example, `http://192.168.1.20:8581`. From here you can install, remove and update plugins, modify the Homebridge config.json and restart Homebridge.

The default username is **`admin`** and the default password is **`admin`**.

<p align="center">
  <img width="600px" src="https://user-images.githubusercontent.com/3979615/71886653-b16d3f80-3190-11ea-9ff8-49dc4ae4fff0.png">
</p>

## Troubleshooting

#### 1. Need ffmpeg?

ffmpeg, with `libfdk-aac` audio support is included in this image.

#### 2. Try the ubuntu tag

Some plugins don't like Alpine Linux so this project also provides a Ubuntu based version of the image.

```
docker run oznu/homebridge:ubuntu
```

See the wiki for a list of image variants: https://github.com/oznu/docker-homebridge/wiki

#### 3. Ask on Discord

Join the [Official Homebridge Discord](https://discord.gg/Cmq8a44) community and ask in the [#docker](https://discord.gg/Cmq8a44) channel.

## License

Copyright (C) 2017-2021 oznu

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the [GNU General Public License](./LICENSE) for more details.
