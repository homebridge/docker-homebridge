FROM oznu/s6-node:6.11.0

RUN apk add --no-cache git python make g++ libffi-dev openssl-dev avahi-compat-libdns_sd avahi-dev openrc dbus \
  && yarn global add node-gyp \
  && mkdir /homebridge \
  && mkdir -p /home/root/homebridge

ENV HOMEBRIDGE_VERSION 0.4.22
RUN yarn global add homebridge@$HOMEBRIDGE_VERSION

WORKDIR /homebridge

COPY default.package.json /home/root/homebridge
COPY default.config.json /home/root/homebridge

VOLUME /homebridge

ENV S6_KEEP_ENV=1

COPY root /
