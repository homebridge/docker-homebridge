#!/bin/sh

/init.d/set-timezone.sh

dbus-daemon --system
avahi-daemon -D

[ -f /homebridge/package.json ] || cp /home/root/homebridge/default.package.json /homebridge/package.json
[ -f /homebridge/config.json ] || cp /home/root/homebridge/default.config.json /homebridge/config.json

echo "Removing old plugins..."
npm prune
echo "Installing plugins..."
npm install --silent

exec "$@"
