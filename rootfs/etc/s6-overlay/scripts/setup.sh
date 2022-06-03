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

dpkg -l homebridge > /dev/null
if [ "$?" != "0" ]; then
  # this will trigger a re-install user plugins if they exist
  if [ -e /homebridge/package.json ]; then
    mkdir -p /tmp/homebridge-tmp
    cp /homebridge/package.json /tmp/homebridge-tmp/package.json
    rm -rf /homebridge/node_modules /var/lib/homebridge/pnpm-lock.yaml /var/lib/homebridge/package.json /var/lib/homebridge/package-lock.json
  fi

  echo "Installing Homebridge..."
  dpkg -i /homebridge_${HOMEBRIDGE_PKG_VERSION}.deb
fi

# set homebridge UID and GID
PUID=${PUID:-1000}
PGID=${PGID:-1000}

# create homebridge group
groupadd -g ${PGID} homebridge -f

# set the gid of homebridge group
groupmod -o -g "$PGID" homebridge

# set the uid of homebridge user
usermod -o -u "$PUID" homebridge

# set the homebridge group as the homebridge users primary group
usermod -g homebridge homebridge

# add homebridge user to sudo group
usermod -a -G sudo homebridge 2> /dev/null
