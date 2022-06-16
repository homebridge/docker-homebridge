#!/command/with-contenv sh

if [ -f /opt/homebridge/source.sh ]; then
  . "/opt/homebridge/source.sh"
fi

# run user defined custom startup script
if [ -f /homebridge/startup.sh ]; then
  echo "Executing user startup script /homebridge/startup.sh"
  chmod +x /homebridge/startup.sh
  cd /homebridge
  /homebridge/startup.sh
fi

exit 0