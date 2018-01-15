FROM oznu/s6-node:8.9.4

RUN apk add --no-cache git python make g++ avahi-compat-libdns_sd avahi-dev dbus \
  && npm config set package-lock false \
  && npm install -g --unsafe-perm homebridge-config-ui-x@latest \
  && mkdir /homebridge

ENV HOMEBRIDGE_VERSION=0.4.36
RUN npm install -g --unsafe-perm homebridge@$HOMEBRIDGE_VERSION

WORKDIR /homebridge
VOLUME /homebridge

COPY root /
