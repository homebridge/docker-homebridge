# Homebridge Docker Repository - Copilot Instructions

Read this first. It describes the repository as it is. If something here does not match the code, the code is right: fix this file in the same change.

## What this repository is

- It builds the official Homebridge Docker images: `homebridge/homebridge` (Docker Hub) and `ghcr.io/homebridge/homebridge`.
- There are five release streams. Each has its own `package.json` with the versions it is built from:

| Stream | Image tags | Versions file | Base image | CPU types |
| :--- | :--- | :--- | :--- | :--- |
| stable | `latest`, `ubuntu`, `YYYY-MM-DD` | `package.json` | see the file | see below |
| beta | `beta`, `beta-YYYY-MM-DD` | `beta/package.json` | see the file | see below |
| alpha | `alpha`, `alpha-YYYY-MM-DD` | `alpha/package.json` | see the file | see below |
| legacy | `legacy`, `legacy-YYYY-MM-DD` | `legacy/package.json` | see the file | see below |
| synology | `synology`, `synology-YYYY-MM-DD` | `synology/package.json` | see the file | see below |

- The base image is the `docker.baseImage` field of each versions file. Images on Ubuntu 26.04 are built for `amd64` and `arm64`. Images on older Ubuntu versions are also built for 32-bit ARM (`arm/v7`).
- The image installs the `homebridge` apt package (repository `homebridge/homebridge-apt-pkg`), which holds Node.js, Homebridge and the Homebridge UI. It adds ffmpeg (`homebridge/ffmpeg-for-homebridge`), avahi and s6-overlay.

## Layout

```
Dockerfile                      one Dockerfile for all streams (build arguments choose the versions)
build/homebridge-apt-key.asc    public key of the Homebridge apt repository (a copy of repo.homebridge.io/KEY.gpg)
build-local.sh                  local build of one stream: ./build-local.sh beta
package.json, <stream>/package.json   versions per stream, changed by the dependency bot
rootfs/                         copied into the image as /
  defaults/                     default .npmrc, avahi config and startup.sh for a new volume
  etc/s6-overlay/s6-rc.d/       the s6 services: setup, timezone, userdata, dbus, avahi, homebridge, homebridge-log, credits
  etc/s6-overlay/scripts/       the scripts those services run
    setup.sh                    runs as root on every start: links, package.json checks, image update rules, npm install
    package-json.sh             helpers: repair and backup of /homebridge/package.json
    image-update.sh             helpers: version compare and the "never move Homebridge down" rule
    safe-path.sh                PATH for the root scripts
    service-user.sh             helpers for the optional non-root mode (HOMEBRIDGE_RUN_AS_USER, PUID, PGID)
    healthcheck.sh              the HEALTHCHECK of the image
    hb-service-docker.sh        /usr/local/bin/hb-service inside the container
scripts/create-release-body.sh  writes the release notes
test/unit/                      sandbox tests of the scripts (no Docker needed)
test/container/                 tests that start a real image
.github/workflows/              CI and the release workflows (see below)
raspbian-installer.sh           installer for Raspberry Pi OS; the wiki links to this file on branch latest
homebridge.xml                  Unraid template; Unraid reads this file from branch latest
```

## How to test a change

Always run these from the repository root.

1. **Lint** (needs `shellcheck` and `hadolint`):
   ```bash
   test/lint.sh
   ```
2. **Sandbox tests** (seconds, no Docker): they copy the scripts to a scratch folder, point their paths at it, and run them with fake `npm`, `chown` and so on.
   ```bash
   test/unit/run.sh
   ```
3. **Build and container tests** (needs Docker, a few minutes):
   ```bash
   ./build-local.sh beta --build-only
   test/container/run.sh docker-homebridge
   ```
   `PREVIOUS_IMAGE=ghcr.io/homebridge/homebridge:beta test/container/run.sh docker-homebridge` also tests an update from the published image.

Every fix needs a test that fails without it. A change to a start script almost always belongs in `test/unit/`. A change to the Dockerfile belongs in `test/container/`.

The `CI` workflow runs all three on every pull request.

## How a release happens

- **Stage 1** (`release-stage-1_update_dependencies.yml`) runs every day at 10:00 UTC. For each stream, `homebridge/dependency-bot` updates the versions file (config: `.github/homebridge-dependency-bot-<stream>.json`). When a version changed, it starts Stage 2 and waits for it. Stage 1 fails when Stage 2 fails.
- **Stage 2** (`release-stage-2_build_and_push_docker_images.yml`):
  1. builds the image once and pushes it to the tag `candidate-<version>` on ghcr.io
  2. tests that candidate on amd64 and arm64 (`validate-docker-container.yml`, which runs `test/container/run.sh`)
  3. only then copies the tested image to the real tags on both registries
  4. creates the GitHub release, and tells Discord for stable
- Releases are fully automatic for all streams, also stable.
- beta and alpha build from the newest `beta-YYYY.M.D` / `alpha-YYYY.M.D` branch when one exists, otherwise from `latest`. **Delete such a branch once its work is merged into `latest`**, or that stream keeps building from old scripts (Stage 1 prints a warning).
- An image is only built when a version in the stream's file changes. A change to the `Dockerfile` or `rootfs/` reaches users with the next version change, or with a manual Stage 2 run.

## Things other projects depend on. Do not change them by accident

- Image names and tags (table above), and the release tag format `YYYY-MM-DD` / `<stream>-YYYY-MM-DD`. The Homebridge UI reads the releases of this repository to offer Docker updates, and shows the release notes to users.
- Inside the container: the volume path `/homebridge`, port 8581, `/homebridge/startup.sh`, `/homebridge/homebridgeContainer.json` (field `docker_tag`), `/opt/homebridge/Docker.manifest` and its table form.
- Environment variables: `TZ`, `ENABLE_AVAHI`, `DSM_HOSTNAME`, `NO_BANNER`, `HOMEBRIDGE_RUN_AS_USER`, `PUID`, `PGID`, and the ones the UI reads (`DOCKER_HOMEBRIDGE_VERSION`, `HOMEBRIDGE_CONFIG_UI`, `CONFIG_UI_VERSION`).
- From the apt package: `/opt/homebridge/start.sh`, `/opt/homebridge/source.sh` (which loads `/opt/homebridge/source-docker.sh`), `/usr/local/bin/hb-service`, and the apt repository `repo.homebridge.io` with its channels `stable`, `beta`, `alpha`, `legacy`.

## Rules for changes

- `/homebridge/package.json` is the user's list of plugins. Never write it directly: use `hb_write_json` from `package-json.sh`. Never delete anything in the volume.
- An image update must never move Homebridge down, unless the user changed stream. The rule is in `image-update.sh` and has tests.
- Shell scripts in `rootfs/` run with `/bin/sh` (dash). No bash-only syntax there.
- New workflows start with `permissions: {}`, give each job only what it needs, and pin actions from outside the homebridge organisation by full commit hash.
- Commit messages follow Conventional Commits (`fix(setup): ...`, `ci: ...`, `docs: ...`).
