#!/command/with-contenv sh

# Compare dotted versions, e.g.: 1.9.0
# Supports supports versions with up to four components up to three digits each
function version {
    echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

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
if [ "$(realpath /var/lib/homebridge)" != "/homebridge" ]; then
  rm -rf /var/lib/homebridge
  ln -sf /homebridge /var/lib/homebridge
fi

# fix a mistake where we were creating a symlink loop
if [ -h "/homebridge/homebridge" ] && [ "$(realpath /homebridge/homebridge)" = "/homebridge" ]; then
  rm /homebridge/homebridge
fi

cd /homebridge

# set the .npmrc file
cp /defaults/.npmrc /homebridge/.npmrc

# remove the package-lock.json
if [ -e /homebridge/package-lock.json ]; then
  rm -rf /homebridge/package-lock.json
fi

# if coming from an old pnpm based install, delete plugins so they are freshly installed
if [ -e /homebridge/pnpm-lock.yaml ]; then
  rm -rf /homebridge/node_modules
  rm -rf /homebridge/pnpm-lock.yaml
  rm -rf /homebridge/package-lock.json
fi

# Get image provided versions of Homebridge and Homebridge UI
hb_update="$(cat /package-config-docker.json | jq -r '.dependencies."homebridge"' | tr -dc [0-9\.])"
hbui_update="$(cat /package-config-docker.json | jq -r '.dependencies."homebridge-config-ui-x"' | tr -dc [0-9\.])"

# setup initial package.json with Homebridge and Homebridge UI image versions
if [ ! -e /homebridge/package.json ]; then
  echo "{ \"dependencies\": { \"homebridge\": \"$hb_update\", \"homebridge-config-ui-x\": \"$hbui_update\" }}" | jq . > /homebridge/package.json
else
  # Update Homebridge version if update is ahead of current
  # Handles if no current version is found - update is ahead of no version
  hb_current="$(cat /homebridge/package.json | jq -r '.dependencies."homebridge"' | tr -dc [0-9\.])"

  if [ $(version $hb_update) -gt $(version $hb_current) ]; then
      packageJson="$(jq --arg hb_version "$hb_update" '.dependencies += { "homebridge":$hb_version }' /homebridge/package.json)"
      echo $packageJson | jq . > /homebridge/package.json
  fi

  # Update Homebridge UI version if update is ahead of current
  # Handles if no current version is found - update is ahead of no version
  hbui_current="$(cat /homebridge/package.json | jq -r '.dependencies."homebridge-config-ui-x"' | tr -dc [0-9\.])"

  if [ $(version $hbui_update) -gt $(version $hbui_current) ]; then
      packageJson="$(jq --arg hbui_version "$hbui_update" '.dependencies += { "homebridge-config-ui-x":$hbui_version }' /homebridge/package.json)"
      echo $packageJson | jq . > /homebridge/package.json
  fi
fi

# source the setup script
if [ -f /opt/homebridge/source.sh ]; then
  . "/opt/homebridge/source.sh"
fi

# install plugins
echo "Installing Homebridge and user plugins, please wait..."
npm --prefix /homebridge install

exit 0
