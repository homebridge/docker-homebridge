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
# independently and skipped, with a warning, if it is not numeric, is 0, or is
# already owned by another account or group.
hb_apply_requested_ids() {
  if [ -n "$PGID" ]; then
    hb_gid_owner=$(getent group "$PGID" | cut -d: -f1)
    case "$PGID" in
      *[!0-9]* | 0)
        echo "WARNING: PGID must be a non-zero number (got PGID=${PGID}); keeping the default homebridge gid."
        ;;
      *)
        if [ -n "$hb_gid_owner" ] && [ "$hb_gid_owner" != "homebridge" ]; then
          echo "WARNING: gid ${PGID} is already used by the ${hb_gid_owner} group; keeping the default homebridge gid."
        else
          groupmod -g "$PGID" homebridge
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
        else
          usermod -u "$PUID" homebridge
        fi
        ;;
    esac
  fi
}

# Takes ownership of the paths passed as arguments so the Homebridge service
# can write to them. A no-op when running as root. Returns non-zero if the
# ownership could not be changed, in which case the caller should fall back to
# running Homebridge as root.
hb_fix_permissions() {
  if [ "$HB_SERVICE_USER" = "root" ]; then
    return 0
  fi

  chown -R "${HB_SERVICE_UID}:${HB_SERVICE_GID}" "$@"
}
