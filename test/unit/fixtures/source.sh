#!/bin/sh

NODE_BIN_PATH="/opt/homebridge/bin"
HB_SERVICE_STORAGE_PATH="/var/lib/homebridge"

export PATH="$NODE_BIN_PATH:$HB_SERVICE_STORAGE_PATH/node_modules/.bin:$PATH"

export npm_config_global_style=true
export npm_config_package_lock=false
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false
export npm_config_auto_install_peers=true
export npm_config_loglevel=error
export npm_config_prefix=/opt/homebridge

export HOMEBRIDGE_APT_PACKAGE=1
export UIX_CUSTOM_PLUGIN_PATH=$HB_SERVICE_STORAGE_PATH/node_modules
export UIX_BASE_PATH_OVERRIDE=/opt/homebridge/lib/node_modules/homebridge-config-ui-x
export UIX_USE_PNPM=0
export UIX_USE_PLUGIN_BUNDLES=1

# Source additional environment variables if the file exists
if [ -f "/opt/homebridge/source-vm.sh" ]; then
  . /opt/homebridge/source-vm.sh
fi
if [ -f "/opt/homebridge/source-docker.sh" ]; then
  . /opt/homebridge/source-docker.sh
fi
# End of appended block