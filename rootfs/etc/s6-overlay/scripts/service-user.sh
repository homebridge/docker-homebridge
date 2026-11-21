# Shared helper for resolving the user the Homebridge service runs as.
#
# This file is sourced, not executed.
#
# HOMEBRIDGE_RUN_AS_USER is optional. When set to a true value, the Homebridge
# service runs as the "homebridge" account created by the homebridge apt
# package instead of root. PUID / PGID optionally change that account's uid /
# gid, and only take effect when HOMEBRIDGE_RUN_AS_USER is enabled.
#
# See https://github.com/homebridge/docker-homebridge/issues/750

HB_SERVICE_USER=root
HB_SERVICE_UID=0
HB_SERVICE_GID=0

hb_is_true() {
  case "$1" in
    1 | true | TRUE | True | yes | YES | Yes) return 0 ;;
  esac
  return 1
}

# Returns 0 when the service should run as the homebridge user, 1 when it
# should run as root. On success HB_SERVICE_USER, HB_SERVICE_UID and
# HB_SERVICE_GID describe the homebridge account as it currently exists.
hb_resolve_service_user() {
  HB_SERVICE_USER=root
  HB_SERVICE_UID=0
  HB_SERVICE_GID=0

  hb_is_true "$HOMEBRIDGE_RUN_AS_USER" || return 1

  if ! id -u homebridge > /dev/null 2>&1; then
    echo "WARNING: the homebridge account does not exist; the Homebridge service will run as root."
    return 1
  fi

  HB_SERVICE_USER=homebridge
  HB_SERVICE_UID=$(id -u homebridge)
  HB_SERVICE_GID=$(id -g homebridge)
  return 0
}

# Applies PUID / PGID to the homebridge account. Each value is applied
# independently and skipped, with a warning, if it is not numeric or is 0.
#
# PGID: when the number is free, the homebridge group gets it. When the number
# already belongs to another group of the image, that group becomes the main
# group of the homebridge user. Group 100 ("users") is the usual value on
# Unraid and Synology, and it exists in every Ubuntu image.
#
# PUID: skipped, with a warning, when another account of the image has it.
hb_apply_requested_ids() {
  if [ -n "$PGID" ]; then
    case "$PGID" in
      *[!0-9]* | 0)
        echo "WARNING: PGID must be a non-zero number (got PGID=${PGID}); keeping the default homebridge gid."
        ;;
      *)
        hb_gid_owner=$(getent group "$PGID" | cut -d: -f1)
        if [ -z "$hb_gid_owner" ]; then
          groupmod -g "$PGID" homebridge
          usermod -g homebridge homebridge
        elif [ "$hb_gid_owner" = "homebridge" ]; then
          usermod -g homebridge homebridge
        else
          echo "gid ${PGID} is the ${hb_gid_owner} group of this image; using it as the main group of the homebridge user."
          usermod -g "$PGID" homebridge
        fi
        ;;
    esac
  fi

  if [ -n "$PUID" ]; then
    hb_uid_owner=$(getent passwd "$PUID" | cut -d: -f1)
    case "$PUID" in
      *[!0-9]* | 0)
        echo "WARNING: PUID must be a non-zero number (got PUID=${PUID}); keeping the default homebridge uid."
        ;;
      *)
        if [ -n "$hb_uid_owner" ] && [ "$hb_uid_owner" != "homebridge" ]; then
          echo "WARNING: uid ${PUID} is already used by the ${hb_uid_owner} account; keeping the default homebridge uid."
        elif [ "$(id -u homebridge)" != "$PUID" ]; then
          usermod -u "$PUID" homebridge
        fi
        ;;
    esac
  fi
}

# Prints the network rights (Linux capabilities) that can be handed to the
# homebridge user, in the form that setpriv wants: "+net_bind_service,+net_raw".
#
# On an apt install, systemd gives the Homebridge service three rights:
# ports below 1024 (net_bind_service), raw network packets such as ping
# (net_raw) and changing network settings (net_admin). Without them a plugin
# that works as root fails as the homebridge user.
#
# Only the rights the container itself has can be handed over. Docker gives a
# container the first two by default, and net_admin only with
# "--cap-add NET_ADMIN". They are read from the bounding set of this process.
hb_network_capabilities() {
  hb_capbnd=$(sed -n 's/^CapBnd:[[:space:]]*//p' /proc/self/status 2> /dev/null)
  hb_caps=""
  case "$hb_capbnd" in
    '' | *[!0-9a-fA-F]*) ;;
    *)
      # the number after each name is its bit in the capability mask
      for hb_cap in net_bind_service:10 net_admin:12 net_raw:13; do
        if [ $(((0x$hb_capbnd >> ${hb_cap#*:}) & 1)) -eq 1 ]; then
          hb_caps="${hb_caps:+$hb_caps,}+${hb_cap%:*}"
        fi
      done
      ;;
  esac
  printf '%s' "$hb_caps"
}

# Takes ownership of the paths passed as arguments so the Homebridge service
# can write to them. A no-op when running as root. Returns non-zero if the
# ownership could not be changed, in which case the caller should fall back to
# running Homebridge as root.
#
# Only files and folders with a wrong owner are changed. A tree that is already
# right is only read, not written: that is much faster on a NAS disk or an SD
# card, and Docker does not have to copy the files of the image
# (/opt/homebridge) into the container. Links are changed themselves, never the
# file they point to, and other volumes mounted below a path are left alone.
hb_fix_permissions() {
  if [ "$HB_SERVICE_USER" = "root" ]; then
    return 0
  fi

  for hb_path in "$@"; do
    [ -e "$hb_path" ] || continue
    find "$hb_path" -xdev \( ! -user "$HB_SERVICE_UID" -o ! -group "$HB_SERVICE_GID" \) \
      -exec chown -h "${HB_SERVICE_UID}:${HB_SERVICE_GID}" {} + || return 1
  done
}

# Sets the owner of single files that a root script has just written. Files
# that do not exist are skipped. A no-op when running as root.
hb_own_files() {
  if [ "$HB_SERVICE_USER" = "root" ]; then
    return 0
  fi

  for hb_file in "$@"; do
    if [ -e "$hb_file" ]; then
      chown -h "${HB_SERVICE_UID}:${HB_SERVICE_GID}" "$hb_file" 2> /dev/null
    fi
  done
  return 0
}
