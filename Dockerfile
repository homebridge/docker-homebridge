FROM ubuntu:20.04 as base

ENV S6_OVERLAY_VERSION=3.1.1.2 \
    HOMEBRIDGE_PKG_VERSION=1.0.33

RUN set -x \
  && apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates

RUN case "$(uname -m)" in \
    x86_64) \
      export S6_ARCH='x86_64'; \
      export FFMPEG_ARCH='x86_64'; \
      export DEB_ARCH='amd64'; \
    ;; \
    armv7l) \
      export S6_ARCH='armhf'; \
      export FFMPEG_ARCH='armv7l'; \
      export DEB_ARCH='armhf'; \
    ;; \
    aarch64) \
      export S6_ARCH='aarch64'; \
      export FFMPEG_ARCH='aarch64'; \
      export DEB_ARCH='arm64'; \
    ;; \
    *) echo "unsupported architecture"; exit 1 ;; \
    esac \
   && cd /tmp \
   && curl -sSLf -o /tmp/s6-overlay-noarch.tar.xz https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz \
   && curl -sSLf -o /tmp/s6-overlay-arch.tar.xz   https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz \
   && curl -sSLf -o /tmp/ffmpeg-debian-${FFMPEG_ARCH}.tar.gz https://github.com/homebridge/ffmpeg-for-homebridge/releases/download/v0.1.0/ffmpeg-debian-${FFMPEG_ARCH}.tar.gz \
   && curl -sSLf -o /tmp/homebridge_${HOMEBRIDGE_PKG_VERSION}.deb https://github.com/homebridge/homebridge-apt-pkg/releases/download/${HOMEBRIDGE_PKG_VERSION}/homebridge_${HOMEBRIDGE_PKG_VERSION}_${DEB_ARCH}.deb 

FROM ubuntu:20.04
COPY --from=base /tmp/* /tmp/

LABEL org.opencontainers.image.title="Homebridge in Docker"
LABEL org.opencontainers.image.description="Official Homebridge Docker Image"
LABEL org.opencontainers.image.authors="oznu"
LABEL org.opencontainers.image.url="https://github.com/oznu/docker-homebridge"
LABEL org.opencontainers.image.licenses="GPL-3.0"

ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
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
    && apt-get install -y --no-install-recommends curl wget ca-certificates jq sudo nano tzdata locales psmisc procps iputils-ping \
    logrotate libnss-mdns xz-utils libatomic1 net-tools python3 python3-pip make g++ avahi-discover libavahi-compat-libdnssd1\
    && locale-gen en_US.UTF-8 \
    && ln -snf /usr/share/zoneinfo/Etc/GMT /etc/localtime \
    && echo Etc/GMT > /etc/timezone \
    && pip3 install tzupdate \
    && chmod 4755 /bin/ping \
    && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz \
    && tar -C / -xzf /tmp/ffmpeg-debian-*.tar.gz --no-same-owner \
    && dpkg -i /tmp/homebridge_*.deb \
    && chown -R root:root /opt/homebridge \
    && apt-get clean \
    && rm -rf /var/lib/homebridge /tmp/* /var/lib/apt/lists/* /var/tmp/* \
    && rm -rf /etc/cron.daily/apt-compat /etc/cron.daily/dpkg /etc/cron.daily/passwd /etc/cron.daily/exim4-base

COPY rootfs /

EXPOSE 8581/tcp
VOLUME /homebridge
WORKDIR /homebridge

ENTRYPOINT [ "/init" ]
