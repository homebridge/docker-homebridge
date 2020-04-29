ARG S6_ARCH
FROM oznu/s6-node:12.16.3-${S6_ARCH:-amd64}

RUN apk add --no-cache git python make g++ avahi-compat-libdns_sd avahi-dev dbus \
    iputils sudo nano \
  && chmod 4755 /bin/ping \
  && mkdir /homebridge \
  && npm set global-style=true \
  && npm set package-lock=false

RUN case "$(uname -m)" in \
    x86_64) FFMPEG_ARCH='x86_64';; \
    armv6l) FFMPEG_ARCH='armv6l';; \
    armv7l) FFMPEG_ARCH='armv6l';; \
    aarch64) FFMPEG_ARCH='aarch64';; \
    *) echo "unsupported architecture"; exit 1 ;; \
    esac \
    && set -x \
    && curl -Lfs https://github.com/oznu/ffmpeg-for-homebridge/releases/download/v0.0.1/ffmpeg-alpine-${FFMPEG_ARCH}.tar.gz | tar xzf - -C / --no-same-owner

ENV HOMEBRIDGE_VERSION=1.0.3
RUN npm install -g --unsafe-perm homebridge@${HOMEBRIDGE_VERSION}

ENV CONFIG_UI_VERSION=4.17.0 HOMEBRIDGE_CONFIG_UI=0 HOMEBRIDGE_CONFIG_UI_PORT=8080
RUN npm install -g --unsafe-perm homebridge-config-ui-x@${CONFIG_UI_VERSION}

WORKDIR /homebridge
VOLUME /homebridge

COPY root /

ARG AVAHI
RUN [ "${AVAHI:-1}" = "1" ] || (echo "Removing Avahi" && \
  rm -rf /etc/services.d/avahi \
    /etc/services.d/dbus \
    /etc/cont-init.d/40-dbus-avahi)
