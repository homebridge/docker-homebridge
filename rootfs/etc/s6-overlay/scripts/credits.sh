#!/bin/sh

if [ "$NO_BANNER" = "1" ]; then
  exit 0
fi

# the table of versions that this image was built with
cat /opt/homebridge/Docker.manifest

exit 0
