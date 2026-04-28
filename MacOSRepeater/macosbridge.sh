#!/bin/bash
#
# Advertises a Homebridge HAP service on the local network via mDNS.
#
# Required because Apple's `container` tool runs containers in isolated VMs
# that cannot broadcast multicast/mDNS to the host network. This script uses
# the macOS `dns-sd` tool to proxy the mDNS advertisement on the host.
#
# Usage:
#   ./macosbridge.sh --name "Homebridge" --id "0E:22:22:E2:22:22" --port 51169
#   ./macosbridge.sh -n "Homebridge" -i "0E:22:22:E2:22:22" -p 51169
#
# All three arguments are required and must match your homebridge/config.json:
#   --name (-n)  bridge.name
#   --id   (-i)  bridge.username
#   --port (-p)  bridge.port

set -euo pipefail

usage() {
  echo "Usage: $0 --name <bridge-name> --id <device-id> --port <port>"
  echo ""
  echo "  -n, --name   Bridge name (must match bridge.name in config.json)"
  echo "  -i, --id     Device ID (must match bridge.username in config.json)"
  echo "  -p, --port   HAP port (must match bridge.port in config.json)"
  echo ""
  echo "Example:"
  echo "  $0 --name \"Homebridge 2222\" --id \"2F:22:22:E2:22:22\" --port 51169"
  exit 1
}

BRIDGE_NAME=""
BRIDGE_ID=""
BRIDGE_PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  -n | --name)
    BRIDGE_NAME="$2"
    shift 2
    ;;
  -i | --id)
    BRIDGE_ID="$2"
    shift 2
    ;;
  -p | --port)
    BRIDGE_PORT="$2"
    shift 2
    ;;
  -h | --help)
    usage
    ;;
  *)
    echo "Unknown option: $1"
    usage
    ;;
  esac
done

if [[ -z "$BRIDGE_NAME" || -z "$BRIDGE_ID" || -z "$BRIDGE_PORT" ]]; then
  echo "Error: --name, --id, and --port are all required."
  echo ""
  usage
fi

echo "Advertising \"$BRIDGE_NAME\" ($BRIDGE_ID) on port $BRIDGE_PORT..."

exec dns-sd -R "$BRIDGE_NAME" _hap._tcp local "$BRIDGE_PORT" \
  "c#=2" \
  "ff=0" \
  "id=$BRIDGE_ID" \
  "md=Homebridge" \
  "pv=1.1" \
  "s#=1" \
  "sf=1" \
  "ci=2"
