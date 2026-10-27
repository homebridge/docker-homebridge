## Homebridge Docker Image

This Ubuntu Linux-based Docker image allows you to run [Homebridge](https://github.com/homebridge/homebridge), developed by [Nfarina](https://github.com/nfarina), on your home network. Homebridge emulates the iOS HomeKit API, allowing you to integrate smart home devices with Apple Home.

The image supports multiple CPU architectures. Docker automatically pulls a compatible image for your system when one is available.

**Ubuntu 26.04 rollout:** During fall 2026, Ubuntu 26.04 will be rolled out across all Homebridge Docker images except Synology. Images based on Ubuntu 26.04 and later will no longer provide the `arm32v7` (32-bit ARM) architecture.

| Image Tag | Architectures | Release Type |
| :--- | :--- | :--- |
| `latest`, `ubuntu` | `amd64`, `arm32v7`*, `arm64v8` | Stable |
| `synology` | `amd64`, `arm32v7`, `arm64v8` | Stable |
| `beta` | `amd64`, `arm32v7`*, `arm64v8` | Beta |
| `alpha` | `amd64`, `arm32v7`*, `arm64v8` | Alpha |
| `legacy` | `amd64`, `arm32v7`*, `arm64v8` | Legacy |

\* The `arm32v7` architecture will no longer be provided as each release stream moves to Ubuntu 26.04. Synology is excluded from this rollout.

### Release Types

- **Stable** (`latest`, `ubuntu`): Stable releases using the latest stable versions of Homebridge and its plugins.
- **Legacy** (`legacy`): Stable releases using Homebridge 1.x and compatible plugin versions.
- **Beta** (`beta`): Pre-release versions of Homebridge and the Homebridge UI for testing upcoming features.
- **Alpha** (`alpha`): Early pre-release versions of Homebridge and the Homebridge UI for development and early testing.