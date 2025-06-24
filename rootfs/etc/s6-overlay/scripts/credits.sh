#!/bin/sh

if [ "$NO_BANNER" = "1" ]; then
  exit 0
fi

BWHITE='\033[1;37m'
UWHITE='\033[4;37m'
BYELLOW='\033[1;33m'
CYAN='\033[4;36m'
NC='\033[0m'

printf "
    ${BWHITE}Thank you for using the ${CYAN}homebridge/homebridge${NC} ${BWHITE}docker image!${NC}
"
printf "\n${BWHITE}Contents of /opt/homebridge/Docker.manifest:${NC}\n"
cat /opt/homebridge/Docker.manifest

exit 0
