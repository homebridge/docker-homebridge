#!/command/with-contenv sh

BWHITE='\033[1;37m'
UWHITE='\033[4;37m'
BYELLOW='\033[1;33m'
CYAN='\033[4;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

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


# test jq is functioning correctly
if ! JQ_TEST_ERROR="$(jq -n '{}' 2>&1 >/dev/null)"; then
  echo "ERROR: jq failed during setup check: ${JQ_TEST_ERROR:-jq test failed with no error output}"
  if echo "$JQ_TEST_ERROR" | grep -qi "cannot get entropy for arc4random"; then
    echo "ERROR: Detected the Synology kernel entropy issue from #960. See https://github.com/homebridge/docker-homebridge/issues/960 for details."
  fi
  echo "ERROR: Stopping setup script to prevent potential issues with Homebridge setup."
  exit 1
else
  echo "jq is functioning correctly, proceeding with setup"
fi

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
  echo "Found package.json in /opt/homebridge, retrieving Homebridge version from dependencies"
  HOMEBRIDGE_VERSION=$(jq -r '.dependencies["homebridge"]' /opt/homebridge/package.json | sed 's/\^//')
fi

if [ -z "$HOMEBRIDGE_VERSION" ]; then
  echo "Homebridge version not found in /opt/homebridge/package.json, retrieving latest version from npm registry"
  HOMEBRIDGE_VERSION="$(curl -sf https://registry.npmjs.org/homebridge/latest | jq -r '.version')"
fi

echo "Homebridge version to install: ${HOMEBRIDGE_VERSION}"

if [ -f /homebridge/homebridgeContainer.json ]; then
  echo "Found homebridgeContainer.json, retrieving installed Docker Homebridge version"
  export INSTALLED_DOCKER_HOMEBRIDGE_VERSION=$(jq -r '.docker_tag' /homebridge/homebridgeContainer.json)
else
  echo "No homebridgeContainer.json found, assuming initial install"
  export INSTALLED_DOCKER_HOMEBRIDGE_VERSION="Initial Install"
fi

echo "Installed Docker Homebridge version: ${INSTALLED_DOCKER_HOMEBRIDGE_VERSION}"
if [ ! -e /homebridge/package.json ]; then
  echo "No package.json found in /homebridge, creating one with Homebridge version ${HOMEBRIDGE_VERSION}"
  echo "{ \"dependencies\": { \"homebridge\": \"$HOMEBRIDGE_VERSION\" }}" | jq . > /homebridge/package.json
else
  if [ "$INSTALLED_DOCKER_HOMEBRIDGE_VERSION" != "$DOCKER_HOMEBRIDGE_VERSION" ]; then
    # if package.json exists, change homebridge version to HOMEBRIDGE_VERSION
    echo "Updating Homebridge version in package.json to ${HOMEBRIDGE_VERSION}"
    packageJson="$(jq -rM --arg version "$HOMEBRIDGE_VERSION" '.dependencies."homebridge" = $version' /homebridge/package.json)"
    printf '%s' "$packageJson" > /homebridge/package.json
  fi
fi

if [ ! -z "$DOCKER_HOMEBRIDGE_VERSION" ]; then
  echo "Checking if Docker Homebridge version has changed. Current: ${INSTALLED_DOCKER_HOMEBRIDGE_VERSION}, New: ${DOCKER_HOMEBRIDGE_VERSION}"
  if [ "$INSTALLED_DOCKER_HOMEBRIDGE_VERSION" != "$DOCKER_HOMEBRIDGE_VERSION" ]; then
    printf "${GREEN}Docker version was updated from ${RED}${INSTALLED_DOCKER_HOMEBRIDGE_VERSION}${GREEN} to ${RED}${DOCKER_HOMEBRIDGE_VERSION}${NC}\n"
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
  echo "Checking for homebridge-config-ui-x in package.json"
  if [ "$(cat /homebridge/package.json | jq -r '.dependencies."homebridge-config-ui-x"')" != "null" ]; then
    echo "Found homebridge-config-ui-x in package.json"
    packageJson="$(cat /homebridge/package.json | jq -rM 'del(."dependencies"."homebridge-config-ui-x")')"
    if [ "$?" = "0" ]; then
      printf "$packageJson" > /homebridge/package.json
      echo "Removed homebridge-config-ui-x from package.json"
    fi
  fi
fi


# source the setup script
if [ -f /opt/homebridge/source.sh ]; then
  echo "Sourcing /opt/homebridge/source.sh"
  . "/opt/homebridge/source.sh"
fi

# install plugins
echo "Installing Homebridge and user plugins, please wait..."
cat /homebridge/package.json
npm --prefix /homebridge install --omit=dev

exit 0
