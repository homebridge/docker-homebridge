## Homebridge Docker Image

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
