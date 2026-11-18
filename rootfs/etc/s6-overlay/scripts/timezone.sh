#!/command/with-contenv sh

# Sets the time zone of the container from the TZ variable, for example
# TZ=Europe/London. Without TZ the container stays on UTC.

if [ -n "$TZ" ]; then
  case "$TZ" in
    /* | *..*) TZ_FILE="" ;;
    *) TZ_FILE="/usr/share/zoneinfo/$TZ" ;;
  esac

  if [ -n "$TZ_FILE" ] && [ -f "$TZ_FILE" ]; then
    # /etc/localtime is a link to a zone file. Point the link at the new zone.
    # Copying over it would write through the link and change the zone file
    # it points to (Etc/GMT in this image).
    ln -snf "$TZ_FILE" /etc/localtime
    echo "$TZ" > /etc/timezone
  else
    echo "WARNING: $TZ is not a valid time zone. The time zone of the container was not changed."
  fi
fi

exit 0
