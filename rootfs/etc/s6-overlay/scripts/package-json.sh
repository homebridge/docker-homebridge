# Shared helpers for package.json in the Homebridge volume. That file is the
# list of installed plugins, so it must never be left empty or cut short.
#
# This file is sourced, not executed.

# Returns 0 when the file holds a JSON object. An empty file is not valid.
hb_json_valid() {
  [ -s "$1" ] && jq -e 'type == "object"' "$1" > /dev/null 2>&1
}

# Writes standard input to the file named in $1. The content goes to a
# temporary file in the same folder first and is checked, so the real file is
# either the old one or the complete new one, even if the container is stopped
# half way.
hb_write_json() {
  hb_tmp="$1.tmp.$$"
  if cat > "$hb_tmp" && hb_json_valid "$hb_tmp"; then
    sync "$hb_tmp" 2> /dev/null
    if mv -f "$hb_tmp" "$1"; then
      return 0
    fi
  fi
  rm -f "$hb_tmp"
  return 1
}

# Prints the plugins (and Homebridge) found in the node_modules folder of the
# storage folder $1, as a JSON object of name and installed version.
hb_installed_plugins() {
  hb_found='{}'
  for hb_manifest in \
    "$1"/node_modules/homebridge/package.json \
    "$1"/node_modules/homebridge-*/package.json \
    "$1"/node_modules/@*/homebridge-*/package.json; do
    [ -f "$hb_manifest" ] || continue
    # a linked plugin (hb-service link) does not come from npm
    [ -L "${hb_manifest%/package.json}" ] && continue
    hb_next=$(jq -c --argjson found "$hb_found" '
      if (.name | type) == "string" and (.version | type) == "string" and .name != "homebridge-config-ui-x"
      then $found + {(.name): .version}
      else $found
      end' "$hb_manifest" 2> /dev/null) && [ -n "$hb_next" ] && hb_found="$hb_next"
  done
  printf '%s\n' "$hb_found"
}

# Checks package.json in the storage folder $1. A missing, empty or broken file
# is put back from the backup copy and from the plugins that are installed. A
# broken file is kept as package.json.broken. Nothing in node_modules is
# touched.
hb_package_json_repair() {
  hb_file="$1/package.json"

  if hb_json_valid "$hb_file"; then
    return 0
  fi

  hb_installed=$(hb_installed_plugins "$1")

  if [ -e "$hb_file" ]; then
    echo "WARNING: $hb_file is empty or is not valid JSON. It lists the installed plugins."
    if mv -f "$hb_file" "$hb_file.broken"; then
      echo "WARNING: The broken file was kept as $hb_file.broken"
    fi
  elif ! hb_json_valid "$hb_file.bak" && [ "$hb_installed" = "{}" ]; then
    # a new volume: nothing to repair
    return 0
  else
    echo "WARNING: $hb_file is missing."
  fi

  if hb_json_valid "$hb_file.bak"; then
    # the backup, plus any plugin that was installed after the backup was made
    if jq --argjson installed "$hb_installed" \
      '.dependencies = ($installed + (.dependencies // {}))' "$hb_file.bak" | hb_write_json "$hb_file"; then
      echo "WARNING: The plugin list was restored from the backup copy $hb_file.bak"
      return 0
    fi
  fi

  if [ "$hb_installed" != "{}" ]; then
    if jq -n --argjson installed "$hb_installed" '{dependencies: $installed}' | hb_write_json "$hb_file"; then
      echo "WARNING: The plugin list was rebuilt from the plugins found in $1/node_modules"
      return 0
    fi
  fi

  echo "WARNING: No backup copy and no installed plugins were found. A new plugin list will be created."
  return 0
}

# Saves a backup copy of a valid package.json in the storage folder $1.
hb_package_json_backup() {
  if hb_json_valid "$1/package.json"; then
    cp -p "$1/package.json" "$1/package.json.bak.tmp" 2> /dev/null &&
      mv -f "$1/package.json.bak.tmp" "$1/package.json.bak"
  fi
}
