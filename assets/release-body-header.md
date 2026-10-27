## Homebridge Docker Image

This Ubuntu Linux-based Docker image allows you to run [Homebridge](https://github.com/homebridge/homebridge), developed by [Nfarina](https://github.com/nfarina), on your home network. Homebridge emulates the iOS HomeKit API, allowing you to integrate smart home devices with Apple Home.

The image supports multiple CPU architectures. Docker automatically pulls a compatible image for your system when one is available.

**Ubuntu 26.04 rollout and 32-bit ARM:** During fall 2026, every Homebridge Docker image except `synology` moves to Ubuntu 26.04, one release stream at a time. Node.js no longer publishes 32-bit builds, so images based on Ubuntu 26.04 no longer include the `arm32v7` (32-bit ARM) architecture. If you run Homebridge in Docker on a 32-bit ARM device, move to a 64-bit (`arm64v8`) OS to keep receiving updates. Images already published stay available under their dated tags (for example `2026-10-23`).

| Image Tag | Architectures | Release Type |
| :--- | :--- | :--- |
| `latest`, `ubuntu` | `amd64`, `arm32v7`*, `arm64v8` | Stable |
| `synology` | `amd64`, `arm32v7`, `arm64v8` | Stable |
| `beta` | `amd64`, `arm32v7`*, `arm64v8` | Beta |
| `alpha` | `amd64`, `arm64v8` | Alpha |
| `legacy` | `amd64`, `arm32v7`*, `arm64v8` | Legacy |

\* `arm32v7` is dropped when that release stream moves to Ubuntu 26.04. `synology` stays on Ubuntu 22.04 and is not part of this rollout.

### Release Types

- **Stable** (`latest`, `ubuntu`): Stable releases using the latest stable versions of Homebridge and its plugins.
- **Legacy** (`legacy`): Stable releases using Homebridge 1.x and compatible plugin versions.
- **Beta** (`beta`): Pre-release versions of Homebridge and the Homebridge UI for testing upcoming features.
- **Alpha** (`alpha`): Early pre-release versions of Homebridge and the Homebridge UI for development and early testing.