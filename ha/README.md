# Homebridge HA Pair

Run two Homebridge Docker containers on separate hosts as a **fault-tolerant pair**.  
Only one instance is active at any time. If the primary fails, the secondary takes over automatically and resumes once the primary recovers.

---

## How it works

| Component | Responsibility |
|-----------|----------------|
| **homebridge** | The Homebridge service itself (same image used in normal deployments) |
| **ha-companion** | Sidecar container that handles health monitoring, failover, and config sync |

### Primary node
* Homebridge runs normally.
* The `ha-companion` periodically **pushes** (rsync over SSH) the `/homebridge` config directory to the secondary host so it always has an up-to-date copy.

### Secondary node
* Homebridge is **stopped** on startup as long as the primary is healthy.
* The `ha-companion` polls the primary's health endpoint (`http://<primary>:8581`) every `HA_CHECK_INTERVAL` seconds.
* After `HA_FAILOVER_TIMEOUT` seconds of consecutive failures, the companion **starts** the local Homebridge container (failover).
* When the primary recovers, the companion **syncs** the latest config back from the primary then **stops** local Homebridge (stand-down).

### Role swap (promotion)
To promote the secondary to primary (planned maintenance or permanent role change):

1. Stop the primary: `docker compose down` on the primary host.
2. On the secondary host set `HA_NODE_ROLE=primary` in `.env` and restart: `docker compose up -d`.
3. Reconfigure the old primary as the new secondary: set `HA_NODE_ROLE=secondary` and `HA_PEER_IP=<new-primary-ip>`, then `docker compose up -d`.

---

## Prerequisites

* Docker Engine with Compose v2 on both hosts.
* Both hosts reachable from each other on port `8581` (Homebridge UI) and SSH (port `22` by default).
* An SSH key pair for passwordless rsync between nodes.

---

## Setup

### Step 1 – Copy files to both hosts

Copy the entire `ha/` directory to the same path on each host:

```bash
scp -r ha/ user@primary-host:~/homebridge-ha/
scp -r ha/ user@secondary-host:~/homebridge-ha/
```

### Step 2 – Generate an SSH key pair

Run this **once** on either host (or your workstation):

```bash
ssh-keygen -t ed25519 -f ha-ssh-key -N ""
```

This creates:
* `ha-ssh-key`       – private key (kept secret, used by the companion container)
* `ha-ssh-key.pub`   – public key (copied to each peer host)

### Step 3 – Authorize the key on both hosts

The companion on each node needs SSH access to its peer host so it can rsync the config. Add the **public key** to the `authorized_keys` on **both** hosts:

```bash
# On the PRIMARY host (allows secondary companion to pull from it)
cat ha-ssh-key.pub >> ~/.ssh/authorized_keys

# On the SECONDARY host (allows primary companion to push to it)
cat ha-ssh-key.pub >> ~/.ssh/authorized_keys
```

Copy the **private key** (`ha-ssh-key`) to both hosts alongside the `docker-compose.yml`:

```bash
cp ha-ssh-key ~/homebridge-ha/ha-ssh-key        # on primary host
scp ha-ssh-key user@secondary-host:~/homebridge-ha/ha-ssh-key
```

Secure the key file:

```bash
chmod 600 ~/homebridge-ha/ha-ssh-key
```

### Step 4 – Configure each node

On the **primary host**, create `~/homebridge-ha/.env`:

```dotenv
HA_NODE_ROLE=primary
HA_PEER_IP=192.168.1.20       # IP of secondary host
HA_PEER_PORT=8581
HA_CHECK_INTERVAL=30
HA_FAILOVER_TIMEOUT=90
HA_SYNC_INTERVAL=300
HA_SYNC_USER=root             # SSH user on secondary host
HA_SYNC_PATH=/homebridge      # homebridge volume path on secondary HOST
HA_SSH_KEY_PATH=./ha-ssh-key
TZ=America/Toronto
```

On the **secondary host**, create `~/homebridge-ha/.env`:

```dotenv
HA_NODE_ROLE=secondary
HA_PEER_IP=192.168.1.10       # IP of primary host
HA_PEER_PORT=8581
HA_CHECK_INTERVAL=30
HA_FAILOVER_TIMEOUT=90
HA_SYNC_INTERVAL=300
HA_SYNC_USER=root             # SSH user on primary host
HA_SYNC_PATH=/homebridge      # homebridge volume path on primary HOST
HA_SSH_KEY_PATH=./ha-ssh-key
TZ=America/Toronto
```

> **HA_SYNC_PATH** is the **host-side** absolute path to the Homebridge config directory.  
> If you mount `./volumes/homebridge:/homebridge` in docker-compose.yml and your working  
> directory is `~/homebridge-ha`, the host path is `~/homebridge-ha/volumes/homebridge`.

### Step 5 – Start the stack on both hosts

```bash
# On the primary host first:
cd ~/homebridge-ha
docker compose up -d

# Then on the secondary host:
cd ~/homebridge-ha
docker compose up -d
```

---

## Verifying the setup

### Check companion logs

```bash
# On primary:
docker logs -f ha-companion

# On secondary:
docker logs -f ha-companion
```

Expected primary output:
```
[HA 2025-01-01 12:00:00] Running as PRIMARY  (peer: 192.168.1.20)
[HA 2025-01-01 12:05:00] Syncing config to secondary 192.168.1.20:/homebridge ...
```

Expected secondary output (primary healthy):
```
[HA 2025-01-01 12:00:00] Running as SECONDARY  (primary: 192.168.1.10:8581)
[HA 2025-01-01 12:00:01] Primary is healthy – standing by (stopping local Homebridge)
```

### Simulate a failover

1. Stop Homebridge on the primary: `docker stop homebridge` (on primary host).
2. Watch secondary logs: after `HA_FAILOVER_TIMEOUT` seconds you will see:
   ```
   [HA ...] Failover threshold reached – activating local Homebridge
   ```
3. Verify Homebridge UI is accessible on the secondary host at `http://<secondary-ip>:8581`.

### Restore the primary

1. Start Homebridge on the primary: `docker start homebridge` (on primary host).
2. The secondary companion will detect the recovery and:
   * Sync config from primary.
   * Stop local Homebridge.
3. The secondary returns to standby mode automatically.

---

## Environment variable reference

| Variable | Default | Description |
|----------|---------|-------------|
| `HA_NODE_ROLE` | `primary` | Role of this node: `primary` or `secondary` |
| `HA_PEER_IP` | _(empty)_ | IP / hostname of the peer node |
| `HA_PEER_PORT` | `8581` | Homebridge UI port on peer used for health checks |
| `HA_CHECK_INTERVAL` | `30` | Seconds between health-check polls |
| `HA_FAILOVER_TIMEOUT` | `90` | Seconds primary must be unreachable before failover |
| `HA_SYNC_INTERVAL` | `300` | Seconds between config-sync runs |
| `HA_SYNC_USER` | `root` | SSH username on the peer host (for rsync) |
| `HA_SYNC_PATH` | `/homebridge` | Absolute path to the homebridge volume on the **peer HOST** |
| `HA_SSH_KEY_PATH` | `./ha-ssh-key` | Host path to SSH private key (mounted into companion) |
| `TZ` | `UTC` | Timezone for Homebridge containers |

---

## Security considerations

* The `ha-companion` container mounts the **Docker socket** (`/var/run/docker.sock`).  
  This grants it full control over all containers on the host.  
  Restrict access to the compose directory and the socket accordingly.
* The SSH private key grants the companion passwordless access to the peer host.  
  Store it with `chmod 600` and never commit it to version control.
* Add `ha-ssh-key` and `ha-ssh-key.pub` to `.gitignore` if you manage config in git.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Companion exits immediately | Missing `curl` (install step failed) | Check Docker daemon internet access |
| Config sync always fails | SSH key not authorised on peer | Re-run Step 3 |
| Secondary never starts after failover | Docker socket not mounted | Verify `volumes:` in docker-compose.yml |
| Homebridge restarts immediately after companion stops it | Wrong restart policy | Ensure `restart: unless-stopped` (not `always`) |
| Role-swap – secondary keeps stopping new primary | Old `.env` not updated | Update `HA_NODE_ROLE` and `HA_PEER_IP` then `docker compose up -d` |
