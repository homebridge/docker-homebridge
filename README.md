
 [![Docker Automated buil](https://img.shields.io/docker/automated/oznu/homebridge.svg)](https://hub.docker.com/r/oznu/homebridge/) [![Docker Pulls](https://img.shields.io/docker/pulls/oznu/homebridge.svg)](https://hub.docker.com/r/oznu/homebridge/) [![GitHub release](https://img.shields.io/github/release/oznu/docker-homebridge.svg)](https://github.com/oznu/docker-homebridge) [![Travis](https://img.shields.io/travis/oznu/docker-homebridge.svg)](https://travis-ci.org/oznu/docker-homebridge)

# Docker Homebridge

This Alpine Linux based Docker image allows you to run [Nfarina's](https://github.com/nfarina) [Homebridge](https://github.com/nfarina/homebridge) on your home network which emulates the iOS HomeKit API.

## Guides

- [Running Homebridge on a Raspberry Pi](https://github.com/oznu/docker-homebridge/wiki/Homebridge-on-Raspberry-Pi)
- [Running Homebridge on a Synology NAS](https://github.com/oznu/docker-homebridge/wiki/Homebridge-on-Synology)

## Compatibility

Homebridge requires full access to your local network to function correctly which can be achieved using the ```--net=host``` flag.
Currently this will not work when using [Docker for Mac](https://docs.docker.com/docker-for-mac/) due to [this issue](https://github.com/docker/for-mac/issues/68).

## Usage

```shell
docker run \
  --net=host \
  --name=homebridge \
  -e PUID=<UID> -e PGID=<GID> \
  -e TZ=<timezone> \
  -v </path/to/config>:/homebridge \
  oznu/homebridge
```

## Raspberry Pi

This image will also run on a Raspberry Pi using the ```raspberry-pi``` tag:

```
docker run --net=host --name=homebridge oznu/homebridge:raspberry-pi
```

This docker image has been tested on the following Raspberry Pi models:

* Raspberry Pi 1 Model B
* Raspberry Pi 3 Model B
* Raspberry Pi Zero W

[See the wiki for a guide on getting Homebridge up and running on a Raspberry Pi](https://github.com/oznu/docker-homebridge/wiki/Homebridge-on-Raspberry-Pi).

## Parameters

The parameters are split into two halves, separated by a colon, the left hand side representing the host and the right the container side.

* `--net=host` - Shares host networking with container, **required**
* `-v /homebridge` - The Homebridge config and plugin location
* `-e TZ` - for [timezone information](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) e.g. `-e TZ=Europe/London`
* `-e PGID` - for for GroupID - see below for explanation
* `-e PUID` - for for UserID - see below for explanation

*Optional Settings:*

* `-e PACKAGES` - Additional [packages](https://pkgs.alpinelinux.org/packages) to install (comma separated, no spaces) e.g. `-e PACKAGES=ffmpeg,openssh`

### User / Group Identifiers

Sometimes when using data volumes (`-v` flags) permissions issues can arise between the host OS and the container. We avoid this issue by allowing you to specify the user `PUID` and group `PGID`. Ensure the data volume directory on the host is owned by the same user you specify and it will "just work".

In this instance `PUID=1001` and `PGID=1001`. To find yours use `id user` as below:

```
  $ id <dockeruser>
    uid=1001(dockeruser) gid=1001(dockergroup) groups=1001(dockergroup)
```

## Homebridge Config

The Homebridge config file is located at ```</path/to/config>/config.json```
This file will be created the first time you run the container if it does not already exist.

## Homebridge Plugins

Plugins should be defined in the ```</path/to/config>/package.json``` file in the standard NPM format.
This file will be created the first time you run the container if it does not already exist.

Any plugins added to the `package.json` will be installed each time the container is restarted.
Plugins can be uninstalled by removing the entry from the `package.json` and restarting the container.

You can also install plugins using [yarn](https://yarnpkg.com) (an npm replacement) which will automatically update the package.json file as you add and remove modules.

**You must restart the container after installing or removing plugins for the changes to take effect.**

### To add plugins using yarn:

```
docker exec <container name or id> yarn add <module name>
```

Example:

```
docker exec homebridge yarn add homebridge-hue
```

### To remove plugins using yarn:

```
docker exec <container name or id> yarn remove <module name>
```

Example:

```
docker exec homebridge yarn remove homebridge-hue
```


## Docker Compose

If you prefer to use [Docker Compose](https://docs.docker.com/compose/):

```yml
version: '2'
services:
  homebridge:
    image: oznu/homebridge
    restart: always
    network_mode: host
    environment:
      - TZ=Australia/Sydney
      - PGID=911
      - PUID=911
    volumes:
      - ./volumes/homebridge:/homebridge
```

## Troubleshooting

### 1. Verify your config.json and package.json syntax

Many issues appear because of invalid JSON. A good way to verify your config is to use the [jsonlint.com](http://jsonlint.com/) validator.
