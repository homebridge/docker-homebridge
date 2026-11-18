ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

# Re-declare ARG after FROM to make it available in RUN steps
ARG BASE_IMAGE

LABEL org.opencontainers.image.title="Homebridge in Docker"
LABEL org.opencontainers.image.description="Official Homebridge Docker Image"
LABEL org.opencontainers.image.authors="homebridge"
LABEL org.opencontainers.image.url="https://github.com/homebridge/docker-homebridge"
LABEL org.opencontainers.image.licenses="GPL-3.0"

# Latest release is supplied as a build argument
ARG HOMEBRIDGE_APT_PKG_VERSION
ARG FFMPEG_FOR_HOMEBRIDGE_VERSION
ARG DOCKER_HOMEBRIDGE_VERSION
# Tells two images with the same version (built on the same day) apart
ARG DOCKER_HOMEBRIDGE_BUILD

# Set version label using the Docker Homebridge version
LABEL org.opencontainers.image.version="${DOCKER_HOMEBRIDGE_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive

# S6_BEHAVIOUR_IF_STAGE2_FAILS=2: when a start-up script fails (setup.sh), stop
# the container. Without it the container stays "Up" with nothing running.
ENV S6_OVERLAY_VERSION=3.2.0.2 \
  S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
  S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
  S6_KEEP_ENV=1 \
  ENABLE_AVAHI=1 \
  USER=root \
  HOMEBRIDGE_APT_PACKAGE=1 \
  UIX_CUSTOM_PLUGIN_PATH="/var/lib/homebridge/node_modules" \
  PATH="/opt/homebridge/bin:/var/lib/homebridge/node_modules/.bin:$PATH" \
  HOME="/home/homebridge" \
  npm_config_prefix=/opt/homebridge

RUN set -x \
  && apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y curl wget tzdata locales psmisc procps iputils-ping logrotate \
  libatomic1 apt-transport-https apt-utils jq openssl sudo nano net-tools \
  && locale-gen en_US.UTF-8 \
  && ln -snf /usr/share/zoneinfo/Etc/GMT /etc/localtime && echo Etc/GMT > /etc/timezone \
  && apt-get install -y python3 python3-pip python3-setuptools git make g++ libnss-mdns \
  avahi-discover libavahi-compat-libdnssd-dev python3-venv python3-dev vim \
  && chmod 0755 /bin/ping \
  && rm -rf /etc/cron.daily/apt-compat /etc/cron.daily/dpkg /etc/cron.daily/passwd /etc/cron.daily/exim4-base

# s6-overlay is the first program that runs in every container. Each archive is
# checked against the SHA-256 that the s6-overlay project publishes next to it.
# When S6_OVERLAY_VERSION changes, these four values must change with it.
ARG S6_OVERLAY_SHA256_NOARCH=6dbcde158a3e78b9bb141d7bcb5ccb421e563523babbe2c64470e76f4fd02dae
ARG S6_OVERLAY_SHA256_X86_64=59289456ab1761e277bd456a95e737c06b03ede99158beb24f12b165a904f478
ARG S6_OVERLAY_SHA256_AARCH64=8b22a2eaca4bf0b27a43d36e65c89d2701738f628d1abd0cea5569619f66f785
ARG S6_OVERLAY_SHA256_ARMHF=c8b8532fe4ec432898960e9ec9c903926454ce73588d4c94ad0e023f0b34fe39

RUN case "$(uname -m)" in \
  x86_64) S6_ARCH='x86_64'; S6_SHA256="${S6_OVERLAY_SHA256_X86_64}";; \
  armv7l) S6_ARCH='armhf'; S6_SHA256="${S6_OVERLAY_SHA256_ARMHF}";; \
  aarch64) S6_ARCH='aarch64'; S6_SHA256="${S6_OVERLAY_SHA256_AARCH64}";; \
  *) echo "unsupported architecture"; exit 1 ;; \
  esac \
  && set -x \
  && S6_URL="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}" \
  && curl -fsSL -o /tmp/s6-overlay-noarch.tar.xz "${S6_URL}/s6-overlay-noarch.tar.xz" \
  && curl -fsSL -o "/tmp/s6-overlay-${S6_ARCH}.tar.xz" "${S6_URL}/s6-overlay-${S6_ARCH}.tar.xz" \
  && echo "${S6_OVERLAY_SHA256_NOARCH}  /tmp/s6-overlay-noarch.tar.xz" | sha256sum -c - \
  && echo "${S6_SHA256}  /tmp/s6-overlay-${S6_ARCH}.tar.xz" | sha256sum -c - \
  && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
  && tar -C / -Jxpf "/tmp/s6-overlay-${S6_ARCH}.tar.xz" \
  && rm -f /tmp/s6-overlay-*.tar.xz

# ffmpeg-for-homebridge publishes no checksum file, so this archive can not be
# checked. It is saved to a file first, so a download that stops half way
# fails the build and is never unpacked.
RUN case "$(uname -m)" in \
  x86_64) FFMPEG_ARCH='x86_64';; \
  armv7l) FFMPEG_ARCH='arm32v7';; \
  aarch64) FFMPEG_ARCH='aarch64';; \
  *) echo "unsupported architecture"; exit 1 ;; \
  esac \
  && set -x \
  && curl -fsSL -o /tmp/ffmpeg.tar.gz "https://github.com/homebridge/ffmpeg-for-homebridge/releases/download/${FFMPEG_FOR_HOMEBRIDGE_VERSION}/ffmpeg-alpine-${FFMPEG_ARCH}.tar.gz" \
  && tar xzf /tmp/ffmpeg.tar.gz -C / --no-same-owner \
  && rm -f /tmp/ffmpeg.tar.gz

# The homebridge package comes from the signed apt repository, the same one
# every apt user installs from, so apt checks the signature and the checksum.
# The public key is kept in this repo (build/homebridge-apt-key.asc, a copy of
# https://repo.homebridge.io/KEY.gpg). The repository is taken out of the image
# again, so a later "apt-get upgrade" in the container can not replace Homebridge.
#
# HOMEBRIDGE_APT_PKG_VERSION is the npm form with a "v" (v2.0.27-beta.20261117).
# The apt form is 2.0.27~beta.20261117, in the channel "beta". A version with
# no pre-release part is in the channel "stable".
RUN --mount=type=bind,source=build/homebridge-apt-key.asc,target=/usr/share/keyrings/homebridge.asc \
  set -x \
  && APT_VERSION="$(printf '%s' "${HOMEBRIDGE_APT_PKG_VERSION#v}" | sed 's/-/~/')" \
  && case "${APT_VERSION}" in \
  *~*) APT_CHANNEL="$(printf '%s' "${APT_VERSION}" | sed 's/^[^~]*~\([a-z]*\).*$/\1/')";; \
  *) APT_CHANNEL='stable';; \
  esac \
  && echo "deb [signed-by=/usr/share/keyrings/homebridge.asc] https://repo.homebridge.io ${APT_CHANNEL} main" > /etc/apt/sources.list.d/homebridge.list \
  && apt-get update \
  && apt-get install -y "homebridge=${APT_VERSION}" \
  && rm -f /etc/apt/sources.list.d/homebridge.list \
  && chown -R root:root /opt/homebridge \
  && rm -rf /var/lib/homebridge \
  && if id -u ubuntu > /dev/null 2>&1; then userdel -r ubuntu; fi \
  && apt-get clean \
  && rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

RUN HB_CONFIG_UI_X_VERSION=$(jq -r '.dependencies["homebridge-config-ui-x"]' /opt/homebridge/package.json) && \
  echo "Homebridge Docker Package Manifest\n\n" \
  "Release Version: ${DOCKER_HOMEBRIDGE_VERSION}\n\n" \
  "| Package | Version |\n" \
  "|:-------:|:-------:|\n" \
  "|Ubuntu|${BASE_IMAGE}|\n" \
  "|ffmpeg for homebridge|${FFMPEG_FOR_HOMEBRIDGE_VERSION}|\n" \
  "|Homebridge APT Package|${HOMEBRIDGE_APT_PKG_VERSION}|\n" \
  "|NodeJS|$(jq -r '.dependencies.node' /opt/homebridge/package.json)|\n" \
  "|Homebridge UI|${HB_CONFIG_UI_X_VERSION}|\n" \
  "|Homebridge|$(jq -r '.dependencies.homebridge' /opt/homebridge/package.json)|\n" \
  > /opt/homebridge/Docker.manifest

# Fix Docker-Homebridge Update info wrong #645

# Append environment variables to source.sh and source-vm.sh if not already present
RUN if ! grep -q "source /opt/homebridge/source-docker.sh" /opt/homebridge/source.sh; then \
  echo "\n# Appended by docker-homebridge" >> /opt/homebridge/source.sh && \
  echo "if [ -f '/opt/homebridge/source-docker.sh' ]; then" >> /opt/homebridge/source.sh && \
  echo "  . /opt/homebridge/source-docker.sh" >> /opt/homebridge/source.sh && \
  echo "fi" >> /opt/homebridge/source.sh ; \
  fi && \
  echo "export DOCKER_HOMEBRIDGE_VERSION=${DOCKER_HOMEBRIDGE_VERSION}" > /opt/homebridge/source-docker.sh && \
  echo "export DOCKER_HOMEBRIDGE_BUILD=${DOCKER_HOMEBRIDGE_BUILD}" >> /opt/homebridge/source-docker.sh && \
  echo "export FFMPEG_FOR_HOMEBRIDGE_VERSION=${FFMPEG_FOR_HOMEBRIDGE_VERSION}" >> /opt/homebridge/source-docker.sh && \
  echo "export HOMEBRIDGE_APT_PKG_VERSION=${HOMEBRIDGE_APT_PKG_VERSION}" >> /opt/homebridge/source-docker.sh && \
  chmod 755 /opt/homebridge/source-docker.sh

COPY rootfs /

EXPOSE 8581/tcp
VOLUME /homebridge
WORKDIR /homebridge

# The container is "healthy" when the Homebridge UI answers. The first five
# minutes do not count against it: a first start installs Homebridge.
HEALTHCHECK --interval=60s --timeout=10s --start-period=300s --retries=5 \
  CMD [ "/etc/s6-overlay/scripts/healthcheck.sh" ]

ENTRYPOINT [ "/init" ]
