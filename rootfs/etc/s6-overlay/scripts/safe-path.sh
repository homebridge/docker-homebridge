# Sets the PATH for the start scripts that run as root.
#
# This file is sourced, not executed.
#
# The system folders come before node_modules/.bin. Any npm package that a
# plugin brings along can put a command into .bin. With .bin first, a command
# there with the name of a system tool (jq, curl, sed ...) would be used by the
# root start scripts in place of the real one.
#
# Homebridge itself is not changed by this: start.sh from the apt package sets
# its own PATH for the Homebridge process.

PATH="/opt/homebridge/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/var/lib/homebridge/node_modules/.bin"
export PATH
