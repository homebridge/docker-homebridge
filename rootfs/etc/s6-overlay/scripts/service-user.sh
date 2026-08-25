# Shared helper for resolving the user the Homebridge service runs as.
#
# This file is sourced, not executed.
#
# PUID / PGID are optional. When either is set to a non-zero value, the
# Homebridge service runs as the "homebridge" user, remapped to that uid / gid.
# When both are unset - or either is 0 - Homebridge runs as root, which is the
# behaviour of every image since the 2022-06-24 release.
#
# See https://github.com/homebridge/docker-homebridge/issues/750

HB_SERVICE_USER=root
HB_SERVICE_UID=0
HB_SERVICE_GID=0

# Returns 0 when the service should run as the homebridge user, 1 when it
# should run as root. On success HB_SERVICE_USER, HB_SERVICE_UID and
# HB_SERVICE_GID describe the requested user.
hb_resolve_service_user() {
  HB_SERVICE_USER=root
  HB_SERVICE_UID=0
  HB_SERVICE_GID=0

  if [ -z "$PUID" ] && [ -z "$PGID" ]; then
    return 1
  fi

  # if only one of the two is set, use it for both
  hb_uid="${PUID:-$PGID}"
  hb_gid="${PGID:-$PUID}"

  case "${hb_uid}:${hb_gid}" in
    *[!0-9:]*)
      echo "WARNING: PUID / PGID must be numeric (got PUID=${PUID} PGID=${PGID}); the Homebridge service will run as root."
      return 1
      ;;
  esac

  # PUID / PGID of 0 means the user explicitly wants to run as root
  if [ "$hb_uid" -eq 0 ] || [ "$hb_gid" -eq 0 ]; then
    return 1
  fi

  HB_SERVICE_USER=homebridge
  HB_SERVICE_UID="$hb_uid"
  HB_SERVICE_GID="$hb_gid"
  return 0
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
