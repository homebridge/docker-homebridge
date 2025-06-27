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

# setup initial package.json with homebridge
if [ -e /opt/homebridge/package.json ]; then
  HOMEBRIDGE_VERSION=$(jq -r '.dependencies["homebridge"]' /opt/homebridge/package.json | sed 's/\^//')
fi

if [ -z "$HOMEBRIDGE_VERSION" ]; then
  HOMEBRIDGE_VERSION="$(curl -sf https://registry.npmjs.org/homebridge/latest | jq -r '.version')"
fi

if [ -f /homebridge/homebridgeContainer.json ]; then
  export INSTALLED_DOCKER_HOMEBRIDGE_VERSION=$(jq -r '.docker_tag' /homebridge/homebridgeContainer.json)
else
  export INSTALLED_DOCKER_HOMEBRIDGE_VERSION="Initial Install"
fi

if [ ! -e /homebridge/package.json ]; then
  echo "{ \"dependencies\": { \"homebridge\": \"$HOMEBRIDGE_VERSION\" }}" | jq . > /homebridge/package.json
else
  if [ "$INSTALLED_DOCKER_HOMEBRIDGE_VERSION" != "$DOCKER_HOMEBRIDGE_VERSION" ]; then
    # if package.json exists, change homebridge version to HOMEBRIDGE_VERSION
    packageJson="$(cat /homebridge/package.json | jq -rM --arg version "$HOMEBRIDGE_VERSION" '.dependencies."homebridge" = $version')"
    printf '%s' "$packageJson" > /homebridge/package.json
    echo "Updated homebridge to "$HOMEBRIDGE_VERSION
  fi
fi

if [ ! -z "$DOCKER_HOMEBRIDGE_VERSION" ]; then
  if [ "$INSTALLED_DOCKER_HOMEBRIDGE_VERSION" != "$DOCKER_HOMEBRIDGE_VERSION" ]; then
    echo "Docker version was updated from $INSTALLED_DOCKER_HOMEBRIDGE_VERSION to $DOCKER_HOMEBRIDGE_VERSION"
    if [ -f /homebridge/homebridgeContainer.json ]; then
      homebridgeContainerJson=$(jq -rM --arg version "$DOCKER_HOMEBRIDGE_VERSION" '.docker_tag = $version' /homebridge/homebridgeContainer.json 2>/dev/null) || homebridgeContainerJson='{"docker_tag": "'"$DOCKER_HOMEBRIDGE_VERSION"'"}'
    else
      homebridgeContainerJson='{"docker_tag": "'"$DOCKER_HOMEBRIDGE_VERSION"'"}'
    fi
    printf '%s' "$homebridgeContainerJson" > /homebridge/homebridgeContainer.json
  fi
fi

# remove homebridge-config-ui-x from the package.json
if [ -e /homebridge/package.json ]; then
  if [ "$(cat /homebridge/package.json | jq -r '.dependencies."homebridge-config-ui-x"')" != "null" ]; then
    packageJson="$(cat /homebridge/package.json | jq -rM 'del(."dependencies"."homebridge-config-ui-x")')"
    if [ "$?" = "0" ]; then
      printf "$packageJson" > /homebridge/package.json
      echo "Removed homebridge-config-ui-x from package.json"
    fi
  fi
fi

# source the setup script
if [ -f /opt/homebridge/source.sh ]; then
  . "/opt/homebridge/source.sh"
fi

# install plugins
echo "Installing Homebridge and user plugins, please wait..."
npm --prefix /homebridge install --omit=dev

exit 0
