#!/command/with-contenv sh

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

. /etc/s6-overlay/scripts/safe-path.sh

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

# avahi config. DSM_HOSTNAME sets the host name that avahi announces (fix for
# synology dsm - see #35). The value goes into a sed command, so only the
# characters of a host name are let through.
case "$DSM_HOSTNAME" in
  '')
    AVAHI_HOST_LINE='#host-name='
    ;;
  *[!A-Za-z0-9.-]*)
    echo "WARNING: DSM_HOSTNAME may only hold letters, digits, dots and dashes. It is ignored."
    AVAHI_HOST_LINE='#host-name='
    ;;
  *)
    AVAHI_HOST_LINE="host-name=${DSM_HOSTNAME}"
    ;;
esac
sed "s/^#*host-name=.*/${AVAHI_HOST_LINE}/" /defaults/avahi-daemon.conf > /etc/avahi/avahi-daemon.conf

# setup homebridge
mkdir -p /homebridge

# user defaults
[ -e /homebridge/startup.sh ] || cp /defaults/startup.sh /homebridge/startup.sh

# /var/lib/homebridge is the data path of the homebridge apt package. In this
# image it must be a link to the volume at /homebridge. Whatever is found
# there is never deleted: it may be the user's data, mounted at the wrong path.
if [ -L /var/lib/homebridge ]; then
  if [ "$(readlink /var/lib/homebridge)" != "/homebridge" ]; then
    ln -sfn /homebridge /var/lib/homebridge
  fi
elif [ -e /var/lib/homebridge ]; then
  # rmdir only removes an empty folder. It fails for a folder with files in it
  # and for a mounted volume.
  if ! rmdir /var/lib/homebridge 2> /dev/null; then
    echo "ERROR: /var/lib/homebridge is a mounted volume or holds files."
    echo "ERROR: This image keeps the Homebridge data in /homebridge. Mount your data folder there, for example:"
    echo "ERROR:   -v /path/to/your/homebridge:/homebridge"
    echo "ERROR: Nothing was changed or deleted. Stopping."
    exit 1
  fi
  ln -sfn /homebridge /var/lib/homebridge
else
  ln -sfn /homebridge /var/lib/homebridge
fi

# fix a mistake where we were creating a symlink loop
if [ -h "/homebridge/homebridge" ] && [ "$(realpath /homebridge/homebridge)" = "/homebridge" ]; then
  rm /homebridge/homebridge
fi

cd /homebridge || exit 1


# test jq is functioning correctly
JQ_TEST_ERROR="$(echo '{}' | jq . 2>&1)"
JQ_EXIT_CODE=$?
if [ "$JQ_EXIT_CODE" -ne 0 ]; then
  echo "ERROR: jq failed during setup check (exit code ${JQ_EXIT_CODE}): ${JQ_TEST_ERROR:-no error details captured}"
  echo "ERROR: See https://github.com/homebridge/docker-homebridge/issues/960 for details."
  echo "ERROR: Stopping setup script to prevent potential issues with Homebridge setup."
  exit 1
else
  echo "jq is functioning correctly, proceeding with setup"
fi

# package.json is the list of installed plugins: repair it if it is broken,
# before anything below reads or changes it, then keep a backup copy
. /etc/s6-overlay/scripts/package-json.sh
. /etc/s6-overlay/scripts/image-update.sh
hb_package_json_repair /homebridge
hb_package_json_backup /homebridge

# configure the user the Homebridge service will run as (HOMEBRIDGE_RUN_AS_USER)
. /etc/s6-overlay/scripts/service-user.sh
if hb_resolve_service_user; then
  # PUID / PGID optionally remap the homebridge account created by the apt package
  hb_apply_requested_ids
  hb_resolve_service_user
  echo "Configuring the homebridge service user with uid ${HB_SERVICE_UID} and gid ${HB_SERVICE_GID}"

  # allow the homebridge user to use sudo, which the Homebridge UI needs to
  # restart the container and to update Homebridge, the UI and Node.js
  usermod -a -G sudo homebridge 2> /dev/null
  printf '%s\n' \
    "homebridge ALL=(ALL) NOPASSWD: ALL" \
    > /etc/sudoers.d/010_homebridge-nopasswd
  chown root:root /etc/sudoers.d/010_homebridge-nopasswd
  chmod 0440 /etc/sudoers.d/010_homebridge-nopasswd

  mkdir -p /home/homebridge
  [ -e /home/homebridge/.bashrc ] || cp /opt/homebridge/bashrc /home/homebridge/.bashrc 2> /dev/null

  # the homebridge apt package scripts read this file to work out which user the
  # service runs as
  mkdir -p /etc/systemd/system/homebridge.service.d
  printf '%s\n' \
    "# this docker container does not use systemd" \
    "# the homebridge apt package just checks this file to see if the user has been changed from the default" \
    "" \
    "[Service]" \
    "User=homebridge" \
    > /etc/systemd/system/homebridge.service.d/override.conf
else
  if [ -n "$PUID" ] || [ -n "$PGID" ]; then
    echo "WARNING: PUID / PGID are ignored unless HOMEBRIDGE_RUN_AS_USER is enabled; the Homebridge service will run as root."
  fi
  # running as root, the sudo rule for the homebridge user is not needed
  rm -f /etc/sudoers.d/010_homebridge-nopasswd
fi

# npm settings. /homebridge/.npmrc belongs to the user: their own lines (a
# private registry, a proxy ...) are kept. Only settings that are missing are
# added from the defaults of the image.
hb_npmrc_merge() { # <defaults file> <the user's file>
  if [ ! -f "$2" ]; then
    cp "$1" "$2"
    return
  fi
  hb_npmrc_tmp="$2.tmp.$$"
  # two old settings that earlier images wrote. npm 11 and 12 warn about them:
  # global-style is now install-strategy, and auto-install-peers was never an npm setting.
  grep -v -E '^[[:space:]]*(auto-install-peers|global-style)[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$2" > "$hb_npmrc_tmp"
  if [ -n "$(tail -c 1 "$hb_npmrc_tmp")" ]; then
    echo >> "$hb_npmrc_tmp"
  fi
  while IFS= read -r hb_npmrc_line || [ -n "$hb_npmrc_line" ]; do
    hb_npmrc_key=$(printf '%s\n' "$hb_npmrc_line" | sed -n 's/^[[:space:]]*\([A-Za-z0-9_-]*\)[[:space:]]*=.*$/\1/p')
    [ -n "$hb_npmrc_key" ] || continue
    if ! grep -q -E "^[[:space:]]*${hb_npmrc_key}[[:space:]]*=" "$hb_npmrc_tmp"; then
      printf '%s\n' "$hb_npmrc_line" >> "$hb_npmrc_tmp"
    fi
  done < "$1"
  if cmp -s "$hb_npmrc_tmp" "$2"; then
    rm -f "$hb_npmrc_tmp"
  else
    mv -f "$hb_npmrc_tmp" "$2"
  fi
}
hb_npmrc_merge /defaults/.npmrc /homebridge/.npmrc

# if coming from an old pnpm based install, delete plugins so they are freshly
# installed (package.json, the list of plugins, is kept)
if [ -e /homebridge/pnpm-lock.yaml ]; then
  rm -rf /homebridge/node_modules
  rm -f /homebridge/pnpm-lock.yaml
fi

# remove the package-lock.json
rm -f /homebridge/package-lock.json

# source the setup script
if [ -f /opt/homebridge/source-docker.sh ]; then
  echo "Sourcing /opt/homebridge/source-docker.sh"
  . "/opt/homebridge/source-docker.sh"
fi

# The Homebridge version of this image. It is only ever read from the image:
# asking npm for "latest" here would move a legacy or beta user to another
# release line.
HOMEBRIDGE_VERSION=""
if [ -e /opt/homebridge/package.json ]; then
  HOMEBRIDGE_VERSION=$(jq -r '.dependencies["homebridge"] // empty' /opt/homebridge/package.json | sed 's/^[\^~]//')
fi

if hb_semver_valid "$HOMEBRIDGE_VERSION"; then
  echo "Manifest Homebridge version: ${HOMEBRIDGE_VERSION}"
else
  echo "WARNING: no usable Homebridge version found in /opt/homebridge/package.json (found: ${HOMEBRIDGE_VERSION:-nothing})."
fi

if [ -f /homebridge/homebridgeContainer.json ]; then
  echo "Found homebridgeContainer.json, retrieving installed Docker Homebridge version"
  INSTALLED_DOCKER_HOMEBRIDGE_VERSION=$(jq -r '.docker_tag // empty' /homebridge/homebridgeContainer.json 2> /dev/null)
  INSTALLED_DOCKER_HOMEBRIDGE_BUILD=$(jq -r '.docker_build // empty' /homebridge/homebridgeContainer.json 2> /dev/null)
else
  echo "No homebridgeContainer.json found, assuming initial install"
  INSTALLED_DOCKER_HOMEBRIDGE_VERSION="Initial Install"
  INSTALLED_DOCKER_HOMEBRIDGE_BUILD=""
fi
export INSTALLED_DOCKER_HOMEBRIDGE_VERSION

# Is this the first start with a new image? The version is only a date, so two
# images built on the same day share it. The build id tells them apart.
IMAGE_UPDATED=0
if [ -n "$DOCKER_HOMEBRIDGE_VERSION" ] && [ "$INSTALLED_DOCKER_HOMEBRIDGE_VERSION" != "$DOCKER_HOMEBRIDGE_VERSION" ]; then
  IMAGE_UPDATED=1
elif [ -n "$DOCKER_HOMEBRIDGE_BUILD" ] && [ "$INSTALLED_DOCKER_HOMEBRIDGE_BUILD" != "$DOCKER_HOMEBRIDGE_BUILD" ]; then
  IMAGE_UPDATED=1
fi

echo "Installed Docker Homebridge version: ${INSTALLED_DOCKER_HOMEBRIDGE_VERSION:-unknown} (build ${INSTALLED_DOCKER_HOMEBRIDGE_BUILD:-unknown})"
echo "Image Docker Homebridge version: ${DOCKER_HOMEBRIDGE_VERSION:-unknown} (build ${DOCKER_HOMEBRIDGE_BUILD:-unknown})"

if [ ! -e /homebridge/package.json ]; then
  if ! hb_semver_valid "$HOMEBRIDGE_VERSION"; then
    echo "ERROR: /homebridge has no package.json, and this image does not say which Homebridge version to install."
    echo "ERROR: The image is broken. Use another image tag. Stopping."
    exit 1
  fi
  echo "No package.json found in /homebridge, creating one with Homebridge version ${HOMEBRIDGE_VERSION}"
  jq -n --arg version "$HOMEBRIDGE_VERSION" '{dependencies: {homebridge: $version}}' | hb_write_json /homebridge/package.json
elif [ "$IMAGE_UPDATED" = "1" ]; then
  # The image was updated. The Homebridge version of the image is only
  # written into the volume when it is newer than the one in the volume, or
  # when the release stream changed (for example from beta to latest). So an
  # image update never moves Homebridge down by accident.
  VOLUME_HOMEBRIDGE_VERSION=$(jq -r '.dependencies."homebridge" // empty' /homebridge/package.json)
  if ! hb_semver_valid "$HOMEBRIDGE_VERSION"; then
    echo "WARNING: the image does not hold a usable Homebridge version (${HOMEBRIDGE_VERSION:-none}); keeping Homebridge ${VOLUME_HOMEBRIDGE_VERSION:-as it is} in the volume."
  else
    UPDATE_DECISION=$(hb_update_decision "$HOMEBRIDGE_VERSION" "$VOLUME_HOMEBRIDGE_VERSION" "$INSTALLED_DOCKER_HOMEBRIDGE_VERSION" "$DOCKER_HOMEBRIDGE_VERSION")
    UPDATE_REASON=$(printf '%s\n' "$UPDATE_DECISION" | sed -n 2p)
    if [ "$(printf '%s\n' "$UPDATE_DECISION" | sed -n 1p)" = "image" ]; then
      echo "Docker Container updated, setting the Homebridge version in package.json to ${HOMEBRIDGE_VERSION}: ${UPDATE_REASON}"
      jq -M --arg version "$HOMEBRIDGE_VERSION" '.dependencies."homebridge" = $version' /homebridge/package.json \
        | hb_write_json /homebridge/package.json \
        || echo "WARNING: could not update the Homebridge version in /homebridge/package.json; the file was left as it was."
    else
      echo "Docker Container updated, keeping the Homebridge version in package.json: ${UPDATE_REASON}"
    fi
  fi
fi

if [ "$IMAGE_UPDATED" = "1" ]; then
  printf '%bDocker version was updated from %b%s%b to %b%s%b\n' \
    "$GREEN" "$RED" "$INSTALLED_DOCKER_HOMEBRIDGE_VERSION" "$GREEN" "$RED" "$DOCKER_HOMEBRIDGE_VERSION" "$NC"
  # remember which image this volume was last started with
  if ! jq -M --arg version "$DOCKER_HOMEBRIDGE_VERSION" --arg build "$DOCKER_HOMEBRIDGE_BUILD" \
    '.docker_tag = $version | .docker_build = $build' /homebridge/homebridgeContainer.json 2> /dev/null \
    | hb_write_json /homebridge/homebridgeContainer.json; then
    jq -n --arg version "$DOCKER_HOMEBRIDGE_VERSION" --arg build "$DOCKER_HOMEBRIDGE_BUILD" \
      '{docker_tag: $version, docker_build: $build}' | hb_write_json /homebridge/homebridgeContainer.json
  fi
fi

# The Homebridge UI is part of the image. An old install may still list it as a
# plugin in package.json: take it out. One jq call, written through a temporary
# file, so text such as % or \n in the file is never changed.
if jq -e '.dependencies | has("homebridge-config-ui-x")' /homebridge/package.json > /dev/null 2>&1; then
  echo "Found homebridge-config-ui-x in package.json"
  if jq -M 'del(.dependencies."homebridge-config-ui-x")' /homebridge/package.json | hb_write_json /homebridge/package.json; then
    echo "Removed homebridge-config-ui-x from package.json"
  else
    echo "WARNING: could not remove homebridge-config-ui-x from /homebridge/package.json; the file was left as it was."
  fi
fi

# source the setup script
if [ -f /opt/homebridge/source.sh ]; then
  echo "Sourcing /opt/homebridge/source.sh"
  . "/opt/homebridge/source.sh"
  # source.sh puts node_modules/.bin in front of the system folders: undo that
  . /etc/s6-overlay/scripts/safe-path.sh
fi

# take ownership of the paths the service needs to write to, so that the plugin
# install below - and Homebridge itself - can run as the homebridge user
if ! hb_fix_permissions /homebridge /opt/homebridge /home/homebridge; then
  echo "Failed to set ownership of /homebridge to ${HB_SERVICE_UID}:${HB_SERVICE_GID}; the Homebridge service will run as root."
  HB_SERVICE_USER=root
fi

# install plugins
echo "Installing Homebridge and user plugins, please wait..."
cat /homebridge/package.json
if [ "$HB_SERVICE_USER" = "root" ]; then
  npm --prefix /homebridge install --omit=dev
  NPM_EXIT_CODE=$?
else
  echo "Installing as the homebridge user"
  /command/s6-setuidgid homebridge npm --prefix /homebridge install --omit=dev
  NPM_EXIT_CODE=$?
fi

if [ "$NPM_EXIT_CODE" -ne 0 ]; then
  echo "WARNING: 'npm install' failed with exit code ${NPM_EXIT_CODE}. Homebridge or some plugins may be missing or out of date."
  echo "WARNING: Check the network connection and the free disk space, then restart the container."
fi

exit 0
