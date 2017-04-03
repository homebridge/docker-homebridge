FROM resin/raspberry-pi-alpine-node:6.10-slim

RUN apk add --no-cache tzdata curl git python make g++ libffi-dev openssl-dev avahi-compat-libdns_sd avahi-dev openrc dbus

RUN npm install -g yarn

RUN npm install -g node-gyp
RUN npm install -g homebridge

RUN mkdir /homebridge && mkdir -p /home/root/homebridge
WORKDIR /homebridge

COPY default.package.json /home/root/homebridge
COPY default.config.json /home/root/homebridge

VOLUME /homebridge

RUN mkdir /init.d
COPY init.d/ /init.d
ENTRYPOINT ["/init.d/entrypoint.sh"]

CMD ["homebridge", "-U", "/homebridge", "-P", "/homebridge/node_modules"]
