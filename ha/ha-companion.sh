#!/bin/sh
# Homebridge HA Companion Script
# Provides fault-tolerant pair support for Homebridge Docker containers.
#
# PRIMARY mode: periodically pushes config to the secondary host via rsync/SSH.
# SECONDARY mode: monitors the primary health endpoint, manages the local
#   Homebridge container (start/stop), and pulls config from the primary.
#
# Environment variables (all have defaults):
#   HA_NODE_ROLE         - "primary" or "secondary"  (default: primary)
#   HA_PEER_IP           - IP / hostname of the peer node
#   HA_PEER_PORT         - Homebridge UI port on peer  (default: 8581)
#   HA_CHECK_INTERVAL    - Seconds between health checks (default: 30)
#   HA_FAILOVER_TIMEOUT  - Seconds of consecutive failures before failover (default: 90)
#   HA_SYNC_INTERVAL     - Seconds between config-sync runs (default: 300)
#   HA_SYNC_USER         - SSH user on the peer host   (default: root)
#   HA_SYNC_PATH         - Absolute path to homebridge volume on PEER HOST
#                          (default: /homebridge)
#   HA_SSH_KEY           - Path to SSH private key inside this container
#                          (default: /root/.ssh/id_rsa)
#   HA_CONTAINER_NAME    - Local Homebridge container name (default: homebridge)

HA_NODE_ROLE="${HA_NODE_ROLE:-primary}"
HA_PEER_IP="${HA_PEER_IP:-}"
HA_PEER_PORT="${HA_PEER_PORT:-8581}"
HA_CHECK_INTERVAL="${HA_CHECK_INTERVAL:-30}"
HA_FAILOVER_TIMEOUT="${HA_FAILOVER_TIMEOUT:-90}"
HA_SYNC_INTERVAL="${HA_SYNC_INTERVAL:-300}"
HA_SYNC_USER="${HA_SYNC_USER:-root}"
HA_SYNC_PATH="${HA_SYNC_PATH:-/homebridge}"
HA_SSH_KEY="${HA_SSH_KEY:-/root/.ssh/id_rsa}"
HA_CONTAINER_NAME="${HA_CONTAINER_NAME:-homebridge}"

log() {
  echo "[HA $(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
is_peer_healthy() {
  curl -sf --connect-timeout 5 --max-time 10 \
    "http://${HA_PEER_IP}:${HA_PEER_PORT}" > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Config sync helpers
# ---------------------------------------------------------------------------
sync_config_to_peer() {
  if [ -z "$HA_PEER_IP" ] || [ ! -f "$HA_SSH_KEY" ]; then
    return 0
  fi
  log "Syncing config to secondary ${HA_PEER_IP}:${HA_SYNC_PATH} ..."
  # shellcheck disable=SC2086
  rsync -az --delete \
    --exclude='node_modules/' \
    --exclude='logs/' \
    -e "ssh -i ${HA_SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
    /homebridge/ \
    "${HA_SYNC_USER}@${HA_PEER_IP}:${HA_SYNC_PATH}/" 2>&1 \
    || log "WARNING: Config sync to peer failed (will retry)"
}

sync_config_from_peer() {
  if [ -z "$HA_PEER_IP" ] || [ ! -f "$HA_SSH_KEY" ]; then
    return 0
  fi
  log "Syncing config from primary ${HA_PEER_IP}:${HA_SYNC_PATH} ..."
  # shellcheck disable=SC2086
  rsync -az --delete \
    --exclude='node_modules/' \
    --exclude='logs/' \
    -e "ssh -i ${HA_SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
    "${HA_SYNC_USER}@${HA_PEER_IP}:${HA_SYNC_PATH}/" \
    /homebridge/ 2>&1 \
    || log "WARNING: Config sync from peer failed (will retry)"
}

# ---------------------------------------------------------------------------
# Container management (requires /var/run/docker.sock to be mounted)
# ---------------------------------------------------------------------------
start_homebridge() {
  if command -v docker > /dev/null 2>&1; then
    log "Starting Homebridge container '${HA_CONTAINER_NAME}' ..."
    docker start "$HA_CONTAINER_NAME" 2>&1 \
      || log "WARNING: Failed to start Homebridge container"
  else
    log "WARNING: docker CLI not available – cannot start container automatically"
  fi
}

stop_homebridge() {
  if command -v docker > /dev/null 2>&1; then
    log "Stopping Homebridge container '${HA_CONTAINER_NAME}' ..."
    docker stop "$HA_CONTAINER_NAME" 2>&1 \
      || log "WARNING: Failed to stop Homebridge container"
  else
    log "WARNING: docker CLI not available – cannot stop container automatically"
  fi
}

is_homebridge_running() {
  if command -v docker > /dev/null 2>&1; then
    docker inspect --format='{{.State.Running}}' "$HA_CONTAINER_NAME" 2>/dev/null \
      | grep -q "true"
  else
    # Assume running if we cannot check
    return 0
  fi
}

# ---------------------------------------------------------------------------
# PRIMARY logic
# ---------------------------------------------------------------------------
run_primary() {
  log "Running as PRIMARY  (peer: ${HA_PEER_IP:-<not set>})"
  if [ -z "$HA_PEER_IP" ]; then
    log "HA_PEER_IP is not set – config sync to secondary is disabled"
  fi

  last_sync=0
  while true; do
    current_time=$(date +%s)
    if [ $((current_time - last_sync)) -ge "$HA_SYNC_INTERVAL" ]; then
      if [ -n "$HA_PEER_IP" ]; then
        sync_config_to_peer
      fi
      last_sync=$current_time
    fi
    sleep "$HA_CHECK_INTERVAL"
  done
}

# ---------------------------------------------------------------------------
# SECONDARY logic
# ---------------------------------------------------------------------------
run_secondary() {
  log "Running as SECONDARY  (primary: ${HA_PEER_IP}:${HA_PEER_PORT})"

  if [ -z "$HA_PEER_IP" ]; then
    log "ERROR: HA_PEER_IP must be set in secondary mode"
    exit 1
  fi

  # Number of consecutive failures required before triggering failover
  required_failures=$(( HA_FAILOVER_TIMEOUT / HA_CHECK_INTERVAL ))
  [ "$required_failures" -lt 1 ] && required_failures=1

  consecutive_failures=0
  last_sync=0
  was_in_failover=0

  # --- Initial state evaluation ---
  log "Checking primary status on startup ..."
  if is_peer_healthy; then
    log "Primary is healthy – standing by (stopping local Homebridge)"
    stop_homebridge
    consecutive_failures=0
  else
    log "Primary is not reachable on startup – activating local Homebridge"
    start_homebridge
    consecutive_failures=$required_failures
    was_in_failover=1
  fi

  # --- Main monitoring loop ---
  while true; do
    sleep "$HA_CHECK_INTERVAL"
    current_time=$(date +%s)

    if is_peer_healthy; then
      if [ "$was_in_failover" -eq 1 ]; then
        log "Primary has recovered – syncing config then standing down"
        sync_config_from_peer
        stop_homebridge
        was_in_failover=0
      fi
      consecutive_failures=0

      # Periodic config sync while primary is healthy
      if [ $((current_time - last_sync)) -ge "$HA_SYNC_INTERVAL" ]; then
        sync_config_from_peer
        last_sync=$current_time
      fi
    else
      consecutive_failures=$(( consecutive_failures + 1 ))
      log "Primary unreachable (${consecutive_failures}/${required_failures} failures)"

      if [ "$consecutive_failures" -ge "$required_failures" ]; then
        if [ "$was_in_failover" -eq 0 ]; then
          log "Failover threshold reached – activating local Homebridge"
          start_homebridge
          was_in_failover=1
        elif ! is_homebridge_running; then
          log "Homebridge stopped unexpectedly during failover – restarting"
          start_homebridge
        fi
      fi
    fi
  done
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
# Validate required tools
for _cmd in curl; do
  command -v "$_cmd" > /dev/null 2>&1 || { log "ERROR: '$_cmd' is required"; exit 1; }
done

log "Homebridge HA Companion starting (role: ${HA_NODE_ROLE})"

case "$HA_NODE_ROLE" in
  primary)   run_primary   ;;
  secondary) run_secondary ;;
  *)
    log "ERROR: HA_NODE_ROLE must be 'primary' or 'secondary' (got: '${HA_NODE_ROLE}')"
    exit 1
    ;;
esac
