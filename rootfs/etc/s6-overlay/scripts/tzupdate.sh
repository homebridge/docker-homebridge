#!/command/with-contenv sh

echo "Running tzupdate script..."

if [ $TZ ]; then
    [ -f /usr/share/zoneinfo/$TZ ] && cp /usr/share/zoneinfo/$TZ /etc/localtime || echo "WARNING: $TZ is not a valid time zone."
    [ -f /usr/share/zoneinfo/$TZ ] && echo "$TZ" >  /etc/timezone
else
    echo "Running tzupdate..."
    tzupdate 2> /dev/null
fi

