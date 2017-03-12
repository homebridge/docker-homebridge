FROM node:7.7.2-alpine

RUN apk add --no-cache git python make g++ libffi-dev openssl-dev avahi-compat-libdns_sd avahi-dev openrc dbus

RUN npm install --silent -g homebridge

RUN mkdir /homebridge && mkdir -p /home/root/homebridge
WORKDIR /homebridge

COPY default.package.json /home/root/homebridge
COPY default.config.json /home/root/homebridge
COPY entrypoint.sh /sbin/entrypoint.sh

VOLUME /homebridge

ENTRYPOINT ["/sbin/entrypoint.sh"]

CMD ["homebridge", "-U", "/homebridge", "-P", "/homebridge/node_modules"]
