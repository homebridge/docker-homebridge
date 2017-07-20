#!/bin/sh

#
# Docker Homebridge Custom Startup Script - oznu/homebridge
#
# This script can be used to customise the environment and will be executed as
# the root user each time the container starts.
#
# If using this script to install Homebridge plugins please take note:
#   * DO NOT install plugins using the global flag (-g)
#   * ALWAYS install plugins using the npm --save flag, or just use yarn add
#
# Example:
#
# npm install --save homebridge-hue
#
# Consider using yarn to install plugins instead (it's much faster):
#
# yarn add homebridge-hue
#
