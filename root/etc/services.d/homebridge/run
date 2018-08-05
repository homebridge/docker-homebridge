#!/usr/bin/with-localenv sh

# fix permissions
chown -R abc:abc /homebridge

# wait for services to come up
sleep 2

# prevent npm update checks
export NO_UPDATE_NOTIFIER=1

# Homebridge Startup Flags
_HOMEBRIDGE_OPTS='-U /homebridge -P /homebridge/node_modules -C'

if [ "$HOMEBRIDGE_INSECURE" = "1" ]; then
  _HOMEBRIDGE_OPTS=$_HOMEBRIDGE_OPTS' -I'
  echo "Starting homebridge in insecure mode..."
fi

if [ "$HOMEBRIDGE_DEBUG" = "1" ]; then
  _HOMEBRIDGE_OPTS=$_HOMEBRIDGE_OPTS' -D'
  echo "Starting homebridge in debug mode..."
fi

echo $_HOMEBRIDGE_OPTS

s6-setuidgid abc homebridge $_HOMEBRIDGE_OPTS 2>&1 | tee -a /homebridge/logs/homebridge.log
