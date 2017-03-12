# Docker Homebridge

This a lightweight alpine-based docker image allows you to run [Nfarina's](https://github.com/nfarina) [Homebridge](https://github.com/nfarina/homebridge) on your home network that emulates the iOS HomeKit API.

## Compatibility

Homebridge requires full access to your local network to function correctly which can be achieved using the ```--net=host``` flag.
Currently this will not work when using [Docker for Mac](https://docs.docker.com/docker-for-mac/) due to [this issue](https://github.com/docker/for-mac/issues/68).

## Usage

Quick Setup:

```shell
docker run --net=host -v </path/to/config>:/homebridge oznu/homebridge
```

## Config

The Homebridge config file is located at ```/</path/to/config>/config.json```
This file will be created the first time you run the container with a sample [FakeBulb](https://www.npmjs.com/package/homebridge-fakebulb) accessory.

## Plugins

Plugins should be defined in the ```/</path/to/config>/package.json``` file in the standard NPM format.
This file will be created the first time you run the container with the [FakeBulb](https://www.npmjs.com/package/homebridge-fakebulb) module.

Any plugins added to the **package.json** will be installed each time the container is restarted.
Plugins can be uninstalled by removing the entry from the **package.json** and restarting the container.

## Troubleshooting

### 1. Verify your config.json and package.json syntax

Many issues appear because of invalid JSON. A good way to verify your config is to use the jsonlint.com validator.
