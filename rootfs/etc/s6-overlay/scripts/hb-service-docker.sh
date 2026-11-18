#!/bin/sh

# /usr/local/bin/hb-service inside the container. This is the program that
# "sudo hb-service ..." runs.
#
# The hb-service wrapper of the apt package uses systemd to start, stop and
# restart Homebridge. A container has no systemd: s6 runs Homebridge here. So
# these three commands are sent to s6, and every other command is passed on to
# the wrapper of the apt package unchanged.

case "$1" in
  start | stop | restart)
    if [ "$(id -u)" -ne 0 ]; then
      echo "This command must be executed as root or with sudo."
      exit 1
    fi
    ;;
esac

case "$1" in
  start)
    echo "Starting Homebridge..."
    exec /command/s6-svc -u /run/service/homebridge
    ;;
  stop)
    echo "Stopping Homebridge..."
    exec /command/s6-svc -d /run/service/homebridge
    ;;
  restart)
    echo "Restarting Homebridge..."
    exec /command/s6-svc -r /run/service/homebridge
    ;;
esac

exec /opt/homebridge/hb-service-shim "$@"
