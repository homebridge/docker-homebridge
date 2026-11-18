#!/bin/sh
# Docker health check: does the Homebridge UI answer?
#
# The port and the address are read from config.json, because the user can
# change them in the UI settings. The UI may run with or without HTTPS, so
# both are tried.

CONFIG=/homebridge/config.json
PORT="${HOMEBRIDGE_CONFIG_UI_PORT:-8581}"
HOST=localhost

if [ -f "$CONFIG" ]; then
  UI=$(/usr/bin/jq -c '[.platforms[]? | select(.platform == "config")][0] // {}' "$CONFIG" 2> /dev/null)

  CONFIG_PORT=$(printf '%s' "$UI" | /usr/bin/jq -r '.port // empty' 2> /dev/null)
  case "$CONFIG_PORT" in
    '' | *[!0-9]*) ;;
    *) PORT="$CONFIG_PORT" ;;
  esac

  CONFIG_HOST=$(printf '%s' "$UI" | /usr/bin/jq -r '.host // empty' 2> /dev/null)
  case "$CONFIG_HOST" in
    '' | '::' | '0.0.0.0') ;;
    *[!0-9A-Za-z.:-]*) ;;
    *:*) HOST="[$CONFIG_HOST]" ;;
    *) HOST="$CONFIG_HOST" ;;
  esac
fi

case "$PORT" in
  '' | *[!0-9]*) PORT=8581 ;;
esac

/usr/bin/curl --silent --fail --max-time 4 --output /dev/null "http://${HOST}:${PORT}/" && exit 0
/usr/bin/curl --silent --fail --insecure --max-time 4 --output /dev/null "https://${HOST}:${PORT}/" && exit 0

echo "The Homebridge UI does not answer on ${HOST} port ${PORT}"
exit 1
