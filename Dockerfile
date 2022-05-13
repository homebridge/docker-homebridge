FROM ${BASE_IMAGE:-library/ubuntu}:20.04

ENV S6_OVERLAY_VERSION=3.1.0.1 \
 S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
 PUID=911 \
 PGID=911 \
 PATH="/opt/homebridge/bin:/var/lib/homebridge/node_modules/.bin:$PATH" \
 npm_config_store_dir=/var/lib/homebridge/node_modules/.pnpm-store \
 npm_config_prefix=/opt/homebridge \
 npm_config_global_pnpmfile=/opt/homebridge/global_pnpmfile.cjs \
 npm_config_global_style=true \
 npm_config_audit=false \
 npm_config_fund=false \
 npm_config_update_notifier=false 

RUN set -x \
  && apt-get update \
  && apt-get install -y curl wget tzdata locales psmisc procps iputils-ping logrotate libatomic1 apt-transport-https apt-utils jq openssl psmisc sudo \
  && locale-gen en_US.UTF-8 \
  && ln -snf /usr/share/zoneinfo/Etc/GMT /etc/localtime && echo Etc/GMT > /etc/timezone \
  && apt-get install -y python3 python3-pip python3-setuptools git python make g++ libnss-mdns avahi-discover libavahi-compat-libdnssd-dev \
  && pip3 install tzupdate \
  && apt-get clean \
  && rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/* \
  && rm -rf /etc/cron.daily/apt-compat /etc/cron.daily/dpkg /etc/cron.daily/passwd /etc/cron.daily/exim4-base
  
RUN case "$(uname -m)" in \
    x86_64) S6_ARCH='x86_64';; \
    armv7l) S6_ARCH='armhf';; \
    aarch64) S6_ARCH='aarch64';; \
    *) echo "unsupported architecture"; exit 1 ;; \
    esac \
  && cd /tmp \
  && set -x \
  && curl -SLO https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz \
  && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
  && curl -SLO  https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz \
  && tar -C / -Jxpf /tmp/s6-overlay-${S6_ARCH}.tar.xz

RUN case "$(uname -m)" in \
    x86_64) FFMPEG_ARCH='x86_64';; \
    armv7l) FFMPEG_ARCH='armv7l';; \
    aarch64) FFMPEG_ARCH='aarch64';; \
    *) echo "unsupported architecture"; exit 1 ;; \
    esac \
    && set -x \
    && curl -Lfs https://github.com/oznu/ffmpeg-for-homebridge/releases/download/v0.1.0/ffmpeg-debian-${FFMPEG_ARCH}.tar.gz | tar xzf - -C / --no-same-owner

ENV HOMEBRIDGE_PKG_VERSION=1.0.20

RUN case "$(uname -m)" in \
    x86_64) DEB_ARCH='amd64';; \
    armv7l) DEB_ARCH='armhf';; \
    aarch64) DEB_ARCH='arm64';; \
    *) echo "unsupported architecture"; exit 1 ;; \
    esac \
  && set -x \
  && curl -sSfL https://repo.homebridge.io/KEY.gpg | gpg --dearmor | tee /usr/share/keyrings/homebridge.gpg  > /dev/null \
  && echo "deb [signed-by=/usr/share/keyrings/homebridge.gpg] https://repo.homebridge.io stable main" | tee /etc/apt/sources.list.d/homebridge.list > /dev/null \
  && curl -SL -o /homebridge_${HOMEBRIDGE_PKG_VERSION}.deb https://github.com/homebridge/homebridge-apt-pkg/releases/download/${HOMEBRIDGE_PKG_VERSION}/homebridge_${HOMEBRIDGE_PKG_VERSION}_${DEB_ARCH}.deb

COPY rootfs /

VOLUME /homebridge
WORKDIR /homebridge

ENTRYPOINT [ "/init" ]
