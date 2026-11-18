#!/command/with-contenv sh

if [ -f /opt/homebridge/source.sh ]; then
  . "/opt/homebridge/source.sh"
fi
# the startup script runs as root: system tools first, then node_modules/.bin
. /etc/s6-overlay/scripts/safe-path.sh

# run user defined custom startup script
if [ -f /homebridge/startup.sh ]; then
  echo "Executing user startup script /homebridge/startup.sh"
  chmod +x /homebridge/startup.sh
  cd /homebridge || exit 0
  /homebridge/startup.sh
  STARTUP_EXIT_CODE=$?
  if [ "$STARTUP_EXIT_CODE" -ne 0 ]; then
    echo "WARNING: the startup script /homebridge/startup.sh ended with exit code ${STARTUP_EXIT_CODE}. Homebridge is started anyway."
  fi
fi

exit 0
