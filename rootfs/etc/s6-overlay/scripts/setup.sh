#!/command/with-contenv sh

# make folders
mkdir -p /var/run/dbus
mkdir -p /var/run/avahi-daemon

# delete existing pid if found
[ -e /var/run/dbus.pid ] && rm -f /var/run/dbus.pid
[ -e /var/run/dbus/pid ] && rm -f /var/run/dbus/pid
[ -e /var/run/avahi-daemon/pid ] && rm -f /var/run/avahi-daemon/pid

# service permissions
chown messagebus:messagebus /var/run/dbus
chown avahi:avahi /var/run/avahi-daemon
dbus-uuidgen --ensure
sleep 1

# avahi config
cp /defaults/avahi-daemon.conf /etc/avahi/avahi-daemon.conf

# fix for synology dsm - see #35
if [ ! -z "$DSM_HOSTNAME" ]; then
  sed -i "s/.*host-name.*/host-name=${DSM_HOSTNAME}/" /etc/avahi/avahi-daemon.conf
else
  sed -i "s/.*host-name.*/#host-name=/" /etc/avahi/avahi-daemon.conf
fi

# user defaults
[ -e /homebridge/startup.sh ] || cp /defaults/startup.sh /homebridge/startup.sh

# setup homebridge
mkdir -p /homebridge
ln -sf /homebridge /var/lib/homebridge

cd /homebridge

if [ ! -e /homebridge/package-lock.json ]; then
  rm -rf /homebridge/node_modules
  rm -rf /homebridge/pnpm-lock.yaml
fi

if [ -e /homebridge/pnpm-lock.yaml ]; then
  rm -rf /homebridge/node_modules
  rm -rf /homebridge/pnpm-lock.yaml
fi

if [ ! -e /homebridge/package.json ]; then
  HOMEBRIDGE_VERSION="$(curl -sf https://registry.npmjs.org/homebridge/latest | jq -r '.version')"
  echo "{ \"dependencies\": { \"homebridge\": \"$HOMEBRIDGE_VERSION\" }}" | jq . > /homebridge/package.json
fi

# install plugins
echo "Installing plugins, please wait..."
npm --prefix /homebridge install

exit 0
