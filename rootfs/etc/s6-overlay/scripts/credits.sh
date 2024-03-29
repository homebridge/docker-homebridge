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

  If you find this project useful please ${BYELLOW}STAR${NC} it on GitHub:

         ${UWHITE}https://github.com/homebridge/docker-homebridge${NC}

                Or donate to the project:

            ${UWHITE}https://github.com/sponsors/oznu${NC}
                  ${UWHITE}https://paypal.me/oznu${NC}

"

exit 0
