# Homebridge Docker Repository - Copilot Instructions

## Repository Overview

This repository creates the official multi-architecture Docker images for Homebridge - an iOS HomeKit bridge that runs on your home network. The images are Ubuntu 24.04-based and support x86_64, ARM32v7, and ARM64v8 architectures.

**Key Technologies:**
- Docker multi-arch builds (amd64, arm32v7, arm64v8)
- Ubuntu 24.04 base image
- Node.js/npm for Homebridge runtime
- S6 overlay for process supervision
- GitHub Actions for CI/CD automation
- FFmpeg for video streaming support
- Avahi mDNS for HomeKit discovery

**Repository Size:** ~460 lines of scripts/configs, primarily Docker configuration and build automation.

## Build Instructions & Validation

### Prerequisites
- Docker with buildx support for multi-arch builds
- `jq` for JSON parsing (required for version extraction)
- Node.js ecosystem familiarity helpful but not required

### Local Development Build Commands

**Always run these commands from the repository root.**

1. **Standard Build (Latest Stable):**
   ```bash
   # Extracts versions from package.json automatically
   ./test-build-local.sh
   ```
   - Duration: 10-15 minutes for full multi-arch build
   - Validates: Dockerfile syntax, dependency resolution, container startup
   - Creates image tagged as `docker-homebridge`
   - Automatically starts test container via docker-compose

2. **Beta Build:**
   ```bash
   # Extracts versions from beta/package.json automatically
   ./beta-build-local.sh
   ```
   - Duration: 10-15 minutes
   - Uses beta package versions from `beta/package.json`
   - Creates beta-tagged image

### Automated Beta Updates (homebridge-beta-bot)

**Overview:**
This repository uses the homebridge-beta-bot from `homebridge/.github` to automatically update beta dependencies and trigger beta releases. The bot runs daily via scheduled workflows and can also be triggered manually.

**Beta Automation Workflow:**
1. **Stage 1** (`beta-stage-1_update_beta_dependencies.yml`):
   - Runs daily at 10:00 UTC (6 AM Eastern)
   - Calls the reusable `homebridge-beta-bot.yml` workflow
   - Updates dependencies in `beta/package.json` based on configuration
   - Creates and auto-merges PR if changes detected
   - Triggers Stage 2 on successful merge

2. **Stage 2** (`beta-stage-2_build_beta_release_and_store.yml`):
   - Triggered automatically after Stage 1 completes
   - Builds and releases beta Docker images
   - Uses updated beta dependencies from merged PR

**Configuration (`.github/homebridge-beta-bot.json`):**
```json
{
  "auto_merge": true,
  "git_user": {
    "name": "Homebridge Beta Bot", 
    "email": "actions@github.com"
  },
  "directories": [
    {
      "directory": "beta",
      "packages": [
        {
          "name": "@homebridge/homebridge-apt-pkg",
          "tag": "beta"
        },
        {
          "name": "ffmpeg-for-homebridge", 
          "tag": "latest"
        }
      ]
    }
  ]
}
```

**Manual vs Automated Beta Process:**
- **Manual:** Use `./beta-build-local.sh` for local development and testing
- **Automated:** homebridge-beta-bot handles dependency updates and release builds
- Both processes use the same `beta/package.json` file
- Automated process ensures beta releases stay current with upstream changes

**Troubleshooting Beta Bot:**
- Check workflow run logs in Actions tab
- Verify `homebridge-beta-bot.json` syntax with `jq . .github/homebridge-beta-bot.json`
- Manual trigger available via workflow_dispatch in GitHub Actions UI
- Bot requires `GH_TOKEN` secret for PR approval (auto-configured)

### Build Process Details

**Version Management:**
- Versions are automatically extracted from `package.json` (stable) or `beta/package.json` (beta)
- Key dependencies: `@homebridge/homebridge-apt-pkg`, `ffmpeg-for-homebridge`
- Build args: `HOMEBRIDGE_APT_PKG_VERSION`, `FFMPEG_FOR_HOMEBRIDGE_VERSION`, `DOCKER_HOMEBRIDGE_VERSION`

**Build Arguments Required:**
```bash
docker build \
  --build-arg HOMEBRIDGE_APT_PKG_VERSION=v1.7.5 \
  --build-arg FFMPEG_FOR_HOMEBRIDGE_VERSION=v2.1.7 \
  --build-arg DOCKER_HOMEBRIDGE_VERSION=2025-08-26 \
  -t homebridge .
```

**Testing Container:**
```bash
cd test
docker compose up
# Access Homebridge UI at http://localhost:8581
```

### Common Build Issues & Solutions

1. **Missing jq:** Install with `apt-get install jq` or `brew install jq`
2. **Docker buildx not available:** Enable experimental features in Docker settings
3. **Architecture-specific failures:** Check platform compatibility in Dockerfile architecture detection logic
4. **Version extraction failures:** Verify package.json contains required dependencies with proper semver format

## Project Architecture & Layout

### Core Structure
```
├── Dockerfile                    # Multi-arch Ubuntu-based image definition
├── package.json                  # Stable release dependency versions
├── beta/package.json            # Beta release dependency versions
├── rootfs/                      # Files copied into Docker image
│   ├── defaults/                # Default configuration files
│   │   ├── startup.sh          # User-customizable startup script template
│   │   ├── .npmrc              # npm configuration
│   │   └── avahi-daemon.conf   # mDNS configuration
│   └── etc/s6-overlay/         # S6 process supervision configuration
│       ├── scripts/            # Container startup scripts
│       │   ├── setup.sh       # Main setup script (125 lines)
│       │   ├── tzupdate.sh    # Timezone management
│       │   ├── userdata.sh    # User data initialization
│       │   └── credits.sh     # Version info display
│       └── s6-rc.d/           # S6 service definitions
├── test/                       # Local testing configuration
│   └── docker-compose.yml     # Test container setup
└── .github/                    # CI/CD automation and configuration
    ├── homebridge-beta-bot.json  # Beta bot configuration
    └── workflows/
        ├── build_and_push.yml  # Main build and release workflow
        ├── beta-stage-1_update_beta_dependencies.yml  # Automated beta updates
        └── beta-stage-2_build_beta_release_and_store.yml  # Beta release builds
```

### Key Configuration Files
- **Dockerfile:** Main image definition with multi-arch support
- **rootfs/etc/s6-overlay/scripts/setup.sh:** Primary container initialization (npm installs, config setup)
- **test/docker-compose.yml:** Local testing environment
- **build scripts:** `test-build-local.sh` (stable), `beta-build-local.sh` (beta)
- **.github/homebridge-beta-bot.json:** Configuration for automated beta dependency updates

### CI/CD Pipeline 

**Main Release Pipeline (.github/workflows/build_and_push.yml):**
1. **Version extraction** from package.json files
2. **Multi-architecture builds** (amd64, arm32v7, arm64v8)
3. **Container registry pushes** (GitHub Container Registry + Docker Hub)
4. **Release creation** with auto-generated manifests
5. **Discord notifications** for release announcements

**Manual Trigger Required:** Workflow runs via `workflow_dispatch` only.

**Beta Automation Pipeline:**
- **Stage 1:** Daily automated dependency updates via homebridge-beta-bot (10:00 UTC)
- **Stage 2:** Automated beta builds and releases triggered after dependency updates
- **Schedule:** Runs daily, updates after 4 AM Eastern APT package builds
- **Auto-merge:** Enabled for beta dependency PRs to maintain currency

**Build Matrix:**
- Stable: `latest`, `ubuntu`, `YYYY-MM-DD` tags
- Beta: `beta`, `beta-YYYY-MM-DD` tags

### Dependencies & Requirements

**Runtime Dependencies (automatically installed):**
- Ubuntu base packages: curl, wget, jq, python3, git, make, g++
- S6 overlay v3.2.0.2 for process supervision
- Avahi for mDNS/HomeKit discovery
- FFmpeg with libfdk-aac for camera streams

**Environment Variables:**
- `ENABLE_AVAHI=1` (default) - Controls mDNS service
- `TZ` - Timezone configuration
- Network mode must be `host` for HomeKit functionality

### Container Behavior
- **Exposed Port:** 8581 (Homebridge UI)
- **Volume Mount:** `/homebridge` (configuration and plugin storage)
- **Network Mode:** `host` required for HomeKit protocol
- **Startup Script:** `/homebridge/startup.sh` runs at container start if present
- **Health Check:** `curl --fail localhost:8581`

### File Locations in Running Container
- Homebridge config: `/homebridge/config.json`
- Plugin storage: `/homebridge/node_modules/`
- Log files: Standard S6 logging
- Startup customizations: `/homebridge/startup.sh`

## Validation Steps

**Before Code Changes:**
1. Run `./test-build-local.sh` to verify build works
2. Check container starts: `docker logs` should show successful Homebridge startup
3. Verify UI accessible at `http://localhost:8581`

**After Code Changes:**
1. Re-run build script to test changes
2. For Dockerfile changes: Test all three architectures if possible
3. For script changes: Verify in running container
4. For workflow changes: Test with workflow_dispatch trigger

**Always validate:**
- JSON syntax in package.json files (`jq . package.json`)
- JSON syntax in beta bot config (`jq . .github/homebridge-beta-bot.json`)
- Shell script syntax (`bash -n script.sh`)
- Docker build completes without errors
- Container starts and reaches healthy state

---

**Trust these instructions first.** Only search or explore if information here is incomplete or incorrect. Most development tasks can be accomplished using the documented build scripts and testing procedures above.