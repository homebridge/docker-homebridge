#!/bin/sh

/init.d/set-timezone.sh

rm -rf /var/run/dbus.pid
rm -rf /var/run/avahi-daemon//pid

dbus-daemon --system
avahi-daemon -D

[ -f /homebridge/package.json ] || cp /home/root/homebridge/default.package.json /homebridge/package.json
[ -f /homebridge/config.json ] || cp /home/root/homebridge/default.config.json /homebridge/config.json

echo "Removing old plugins..."
npm prune
echo "Installing plugins..."
yarn install

sleep 5

exec "$@"
