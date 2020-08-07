ARG S6_ARCH
FROM oznu/s6-node:12.18.3-ubuntu-${S6_ARCH:-amd64}

RUN apt-get update \
  && apt-get install -y git python make g++ libnss-mdns avahi-discover libavahi-compat-libdnssd-dev \
    net-tools iproute2 sudo nano \
  && apt-get clean \
  && rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/* \
  && chmod 4755 /bin/ping \
  && mkdir /homebridge \
  && npm set global-style=true \
  && npm set package-lock=false \
  && npm set audit=false \ 
  && npm set fund=false

RUN case "$(uname -m)" in \
    x86_64) FFMPEG_ARCH='x86_64';; \
    armv7l) FFMPEG_ARCH='armv7l';; \
    aarch64) FFMPEG_ARCH='aarch64';; \
    *) echo "unsupported architecture"; exit 1 ;; \
    esac \
    && set -x \
    && curl -Lfs https://github.com/oznu/ffmpeg-for-homebridge/releases/download/v0.0.6/ffmpeg-debian-${FFMPEG_ARCH}.tar.gz | tar xzf - -C / --no-same-owner

ENV HOMEBRIDGE_VERSION=1.1.1
RUN npm install -g --unsafe-perm homebridge@${HOMEBRIDGE_VERSION}

ENV CONFIG_UI_VERSION=4.24.0 HOMEBRIDGE_CONFIG_UI=0 HOMEBRIDGE_CONFIG_UI_PORT=8080
RUN npm install -g --unsafe-perm homebridge-config-ui-x@${CONFIG_UI_VERSION}

WORKDIR /homebridge
VOLUME /homebridge

COPY root /

ARG AVAHI
ENV ENABLE_AVAHI="${AVAHI:-1}"
