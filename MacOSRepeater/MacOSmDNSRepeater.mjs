import dgram from 'dgram';
import os from 'os';

const MDNS_ADDR = '224.0.0.251';
const MDNS_PORT = 5353;

// ── Logging ────────────────────────────────────────────────────────────────
//
// Controlled by the LOG_LEVEL environment variable (case-insensitive).
// Levels in ascending order: debug < info < warn < error
//
//   LOG_LEVEL=debug  node MacOSmDNSRepeater.mjs   — show all output
//   LOG_LEVEL=info   node MacOSmDNSRepeater.mjs   — default (omits debug)
//   LOG_LEVEL=warn   node MacOSmDNSRepeater.mjs   — warnings and errors only
//   LOG_LEVEL=error  node MacOSmDNSRepeater.mjs   — errors only

const LEVELS = { debug: 0, info: 1, warn: 2, error: 3 };
const LEVEL  = LEVELS[(process.env.LOG_LEVEL || 'info').toLowerCase()] ?? LEVELS.info;

const DNS_TYPES = {
  1: 'A', 2: 'NS', 5: 'CNAME', 12: 'PTR', 15: 'MX',
  16: 'TXT', 28: 'AAAA', 33: 'SRV', 255: 'ANY',
};

function ts() {
  return new Date().toISOString().replace('T', ' ').replace('Z', '');
}

function log(level, num, ...args) {
  if (num < LEVEL) return;
  console.log(`[${ts()}] [${level}]`, ...args);
}

function debug(...args) { log('DEBUG', LEVELS.debug, ...args); }
function info(...args)  { log('INFO ', LEVELS.info,  ...args); }
function warn(...args)  { if (LEVELS.warn  >= LEVEL) console.warn( `[${ts()}] [WARN ]`, ...args); }
function error(...args) { if (LEVELS.error >= LEVEL) console.error(`[${ts()}] [ERROR]`, ...args); }


function readName(buf, offset) {
  const labels = [];
  let jumped = false;
  let end = -1;
  let safety = 0;

  while (safety++ < 100) {
    const len = buf[offset];

    if (len === 0) {
      if (!jumped) end = offset + 1;
      break;
    }

    // Pointer (compression)
    if ((len & 0xc0) === 0xc0) {
      if (!jumped) end = offset + 2;
      offset = ((len & 0x3f) << 8) | buf[offset + 1];
      jumped = true;
      continue;
    }

    offset++;
    labels.push(buf.slice(offset, offset + len).toString());
    offset += len;
  }

  return { name: labels.join('.'), end };
}

function parseRecords(buf, offset, count) {
  const records = [];

  for (let i = 0; i < count; i++) {
    const { name, end } = readName(buf, offset);
    offset = end;

    const type  = buf.readUInt16BE(offset);     offset += 2;
    const cls   = buf.readUInt16BE(offset);     offset += 2;
    const ttl   = buf.readUInt32BE(offset);     offset += 4;
    const rdlen = buf.readUInt16BE(offset);     offset += 2;
    const rdataOffset = offset;
    const rdata = buf.slice(offset, offset + rdlen);
    offset += rdlen;

    records.push({ name, type, cls, ttl, rdlen, rdataOffset, rdata });
  }

  return { records, offset };
}

function rewriteARecords(buf, virtualSubnets, lanIP) {
  // Header fields
  const qdcount = buf.readUInt16BE(4);
  const ancount = buf.readUInt16BE(6);
  const nscount = buf.readUInt16BE(8);
  const arcount = buf.readUInt16BE(10);

  let offset = 12;

  // Skip questions
  for (let i = 0; i < qdcount; i++) {
    const { end } = readName(buf, offset);
    offset = end + 4; // skip QTYPE + QCLASS
  }

  // Parse all record sections
  const totalRecords = ancount + nscount + arcount;
  const { records } = parseRecords(buf, offset, totalRecords);

  let rewritten = false;

  for (const rec of records) {
    // Type A = 1
    if (rec.type === 1 && rec.rdlen === 4) {
      const ip = Array.from(rec.rdata).join('.');
      const isVirtual = virtualSubnets.some(subnet => ip.startsWith(subnet));

      if (isVirtual) {
        debug(`  A record rewrite: ${rec.name}  ${ip} → ${lanIP}`);
        const parts = lanIP.split('.').map(Number);
        buf[rec.rdataOffset]     = parts[0];
        buf[rec.rdataOffset + 1] = parts[1];
        buf[rec.rdataOffset + 2] = parts[2];
        buf[rec.rdataOffset + 3] = parts[3];
        rewritten = true;
      }
    }
  }

  return rewritten;
}

// Returns a compact human-readable summary of a mDNS packet for logging.
// e.g. "RESPONSE 3 answers [PTR _hap._tcp.local., SRV Homebridge._hap._tcp.local., A 192.168.1.227]"
//      "QUERY    1 questions [ANY _hap._tcp.local.]"
function summarisePacket(buf) {
  try {
    const flags    = buf.readUInt16BE(2);
    const isResp   = (flags & 0x8000) !== 0;
    const qdcount  = buf.readUInt16BE(4);
    const ancount  = buf.readUInt16BE(6);
    const nscount  = buf.readUInt16BE(8);
    const arcount  = buf.readUInt16BE(10);

    let offset = 12;
    const parts = [];

    // Questions
    for (let i = 0; i < qdcount; i++) {
      const { name, end } = readName(buf, offset);
      offset = end;
      const qtype = buf.readUInt16BE(offset); offset += 2; // QTYPE
      offset += 2; // QCLASS
      parts.push(`${DNS_TYPES[qtype] || qtype} ${name}`);
    }

    // Answer / authority / additional records
    const total = ancount + nscount + arcount;
    const { records } = parseRecords(buf, offset, total);
    for (const rec of records) {
      const typeName = DNS_TYPES[rec.type] || rec.type;
      if (rec.type === 1 && rec.rdlen === 4) {
        // A record — show the IP
        parts.push(`${typeName} ${rec.name}→${Array.from(rec.rdata).join('.')}`);
      } else if (rec.type === 12) {
        // PTR — decode rdata name
        const { name: target } = readName(buf, rec.rdataOffset);
        parts.push(`${typeName} ${rec.name}→${target}`);
      } else if (rec.type === 33) {
        // SRV — show port from rdata (priority 2 + weight 2 + port 2)
        const port = rec.rdata.readUInt16BE(4);
        const { name: target } = readName(buf, rec.rdataOffset + 6);
        parts.push(`${typeName} ${rec.name}→${target}:${port}`);
      } else {
        parts.push(`${typeName} ${rec.name}`);
      }
    }

    const kind  = isResp ? 'RESPONSE' : 'QUERY   ';
    const counts = isResp
      ? `${ancount}ans/${nscount}auth/${arcount}add`
      : `${qdcount}q`;
    return `${kind} [${counts}] ${parts.join(', ')}`;
  } catch {
    return `(unparseable ${buf.length}b)`;
  }
}


// Looks for a PTR record (type 12) whose owner name contains '_hap._tcp' and
// returns its rdata decoded as a name — e.g. "Homebridge._hap._tcp.local." or
// "Homebridge 2._hap._tcp.local.".  This is unique per bridge name regardless
// of which IP the container happens to be on.
// Falls back to the first SRV/TXT record name containing '_hap._tcp' if no
// PTR is found, and ultimately returns null if no HAP record is present at all
// (so non-HAP packets are not cached).
function extractServiceKey(buf) {
  const qdcount = buf.readUInt16BE(4);
  const ancount = buf.readUInt16BE(6);
  const nscount = buf.readUInt16BE(8);
  const arcount = buf.readUInt16BE(10);

  let offset = 12;

  // Skip questions
  for (let i = 0; i < qdcount; i++) {
    const { end } = readName(buf, offset);
    offset = end + 4;
  }

  const totalRecords = ancount + nscount + arcount;
  const { records } = parseRecords(buf, offset, totalRecords);

  let fallback = null;

  for (const rec of records) {
    const nameLower = rec.name.toLowerCase();

    // PTR rdata is itself a domain name — decode it to get the instance name
    if (rec.type === 12 && nameLower.includes('_hap._tcp')) {
      const { name: instanceName } = readName(buf, rec.rdataOffset);
      if (instanceName) return instanceName; // e.g. "Homebridge 2._hap._tcp.local."
    }

    // SRV / TXT owner name is already the instance name
    if ((rec.type === 33 || rec.type === 16) && nameLower.includes('_hap._tcp')) {
      fallback = fallback || rec.name;
    }
  }

  return fallback; // null if no HAP records found
}



const VIRTUAL_SUBNETS = ['192.168.64.', '192.168.65.'];

function getInterfaces() {
  const nets = os.networkInterfaces();
  const lan = [], virtual = [];

  for (const [name, addrs] of Object.entries(nets)) {
    for (const addr of addrs) {
      if (addr.family !== 'IPv4' || addr.internal) continue;
      const entry = { name, ip: addr.address };
      if (VIRTUAL_SUBNETS.some(s => addr.address.startsWith(s))) {
        virtual.push(entry);
      } else if (!addr.address.startsWith('169.254.')) {
        lan.push(entry);
      }
    }
  }

  return { lan, virtual };
}

// ── UDP Broadcast Relay ────────────────────────────────────────────────────
//
// Relays UDP broadcast packets on configured ports between virtual and LAN
// interfaces.  This is needed for plugins that use UDP broadcast discovery —
// e.g. the Balboa BWG spa controller which sends to 255.255.255.255:30303.
//
// Discovery flow (container → LAN):
//   1. Container broadcasts to 255.255.255.255:<port>
//   2. Relay receives it on the virtual interface socket
//   3. Relay re-broadcasts it on the LAN interface so LAN devices can hear it
//
// Response flow (LAN → container):
//   1. LAN device replies unicast to the Mac's LAN IP (since that's where the
//      re-broadcast appeared to come from)
//   2. Relay receives the reply on the LAN socket
//   3. Relay forwards it to every virtual IP that recently sent a discovery
//      broadcast on this port (tracked for BROADCAST_PENDING_TTL_MS)
//
// Configuration:
//   BROADCAST_RELAY_PORTS=30303,<other>  comma-separated list (default: 30303)

const BROADCAST_RELAY_PORTS = (process.env.BROADCAST_RELAY_PORTS ?? '30303')
  .split(',').map(p => Number(p.trim())).filter(p => p > 0);

// How long to remember that a virtual IP is waiting for a broadcast response.
const BROADCAST_PENDING_TTL_MS = 30_000; // 30 s

/**
 * Start a UDP broadcast relay for a single port.
 * @param {number}   port        - UDP port to relay
 * @param {object[]} lanIfaces   - array of { name, ip } for LAN interfaces
 * @param {object[]} virtIfaces  - array of { name, ip } for virtual interfaces
 */
function startBroadcastRelay(port, lanIfaces, virtIfaces) {
  // pending: containerIP → last-seen timestamp (ms)
  const pending = new Map();

  // Track first-seen container IPs and LAN responders so we log at info level
  // on first occurrence and debug for repeats — avoids flooding the log.
  const seenContainers = new Set();
  const seenResponders = new Set();

  function prunePending() {
    const cutoff = Date.now() - BROADCAST_PENDING_TTL_MS;
    for (const [ip, ts] of pending.entries()) {
      if (ts < cutoff) {
        pending.delete(ip);
        seenContainers.delete(ip);
      }
    }
  }

  function createBroadcastSocket(bindIp, onMessage) {
    return new Promise((resolve, reject) => {
      const sock = dgram.createSocket({ type: 'udp4', reuseAddr: true });
      sock.on('error', err => error(`[broadcast:${port}:${bindIp}]`, err.message));
      sock.on('message', onMessage);
      // bind without an address when using 0.0.0.0 so Node picks the right default
      sock.bind(port, bindIp === '0.0.0.0' ? undefined : bindIp, () => {
        try {
          sock.setBroadcast(true);
          info(`[broadcast:${port}] listening on ${bindIp}:${port}`);
          resolve(sock);
        } catch (err) { reject(err); }
      });
      sock.once('error', reject);
    });
  }

  // ── Single socket on 0.0.0.0 for all virtual interfaces ────────────────
  // Binding to 0.0.0.0 catches broadcasts from BOTH virtual subnets
  // (192.168.64.x and 192.168.65.x) with one socket.  It is also used to
  // send unicast replies back to individual container IPs.
  let virtSock = null;

  createBroadcastSocket('0.0.0.0', (msg, rinfo) => {
    // Only process packets originating from a virtual subnet
    if (!VIRTUAL_SUBNETS.some(s => rinfo.address.startsWith(s))) return;

    prunePending();
    const isNew = !seenContainers.has(rinfo.address);
    seenContainers.add(rinfo.address);
    pending.set(rinfo.address, Date.now());

    const logFn = isNew ? info : debug;
    logFn(`[broadcast:${port}] VIRTUAL→LAN  ${rinfo.address}:${rinfo.port} → 255.255.255.255:${port}  ${msg.length}b${isNew ? '  (new container)' : ''}`);

    for (const { sock, ip } of lanSocks) {
      sock.send(msg, 0, msg.length, port, '255.255.255.255', err => {
        if (err) error(`[broadcast:${port}] relay to LAN ${ip} failed:`, err.message);
      });
    }
  }).then(sock => { virtSock = sock; })
    .catch(err => warn(`[broadcast:${port}] failed to bind 0.0.0.0: ${err.message}`));

  // ── Sockets on LAN interfaces ───────────────────────────────────────────
  // When we hear a reply from a LAN device, forward it unicast to every
  // container IP that recently sent a discovery broadcast.  We use virtSock
  // (bound to 0.0.0.0) to send, so it works for both virtual subnets.
  const lanSocks = [];

  for (const lIface of lanIfaces) {
    createBroadcastSocket(lIface.ip, (msg, rinfo) => {
      if (rinfo.address === lIface.ip) return; // ignore own traffic
      // Ignore traffic from virtual subnets
      if (VIRTUAL_SUBNETS.some(s => rinfo.address.startsWith(s))) return;

      prunePending();
      if (pending.size === 0 || !virtSock) return;

      const isNew = !seenResponders.has(rinfo.address);
      seenResponders.add(rinfo.address);
      const logFn = isNew ? info : debug;
      logFn(`[broadcast:${port}] LAN→VIRTUAL  ${rinfo.address}:${rinfo.port} → ${pending.size} container(s)  ${msg.length}b${isNew ? '  (new responder)' : ''}`);

      for (const [containerIp] of pending.entries()) {
        virtSock.send(msg, 0, msg.length, rinfo.port, containerIp, err => {
          if (err) error(`[broadcast:${port}] relay to container ${containerIp} failed:`, err.message);
          else debug(`[broadcast:${port}] forwarded LAN response → ${containerIp}`);
        });
      }
    }).then(sock => lanSocks.push({ sock, ip: lIface.ip }))
      .catch(err => warn(`[broadcast:${port}] failed to bind ${lIface.ip}: ${err.message}`));
  }
}

// ── Socket Setup ───────────────────────────────────────────────────────────

function createSocket(iface, onMessage) {
  return new Promise((resolve, reject) => {
    const sock = dgram.createSocket({ type: 'udp4', reuseAddr: true });

    sock.on('error', err => error(`[${iface.name}] socket error:`, err.message));

    sock.on('message', (msg, rinfo) => {
      if (rinfo.address === iface.ip) return; // ignore own packets
      try {
        onMessage(msg, rinfo, iface);
      } catch (err) {
        warn(
          `[${iface.name}] dropped invalid packet from ${rinfo.address}:${rinfo.port}:`,
          err?.message || err
        );
      }
    });

    sock.bind(MDNS_PORT, () => {
      try {
        sock.addMembership(MDNS_ADDR, iface.ip);
        sock.setMulticastInterface(iface.ip);
        sock.setMulticastTTL(255);
        sock.setMulticastLoopback(false);
        info(`[${iface.name}] listening on ${iface.ip}:${MDNS_PORT} (${MDNS_ADDR})`);
        resolve(sock);
      } catch (err) {
        reject(err);
      }
    });
  });
}

// ── Main ───────────────────────────────────────────────────────────────────

// mDNS re-announcement interval (ms).  RFC 6762 recommends re-announcing at
// 80% of TTL (TTL is typically 4500s → 3600s).  We use a shorter interval so
// the LAN cache stays warm even if the container goes quiet.
const REANNOUNCE_INTERVAL_MS = 60_000; // 60 s

// How long (ms) to hold a cached announcement before discarding it.
const CACHE_MAX_AGE_MS = 5 * 60_000;  // 5 min

function isQuery(buf) {
  // Ignore malformed/truncated packets that do not contain a full DNS header.
  if (buf.length < 12) return false;
  // DNS header flags word: bit 15 = QR (0 = query, 1 = response)
  return (buf.readUInt16BE(2) & 0x8000) === 0;
}

async function main() {
  const { lan, virtual } = getInterfaces();

  info(`Log level: ${(process.env.LOG_LEVEL || 'info').toUpperCase()}  (set LOG_LEVEL=debug for packet-level output)`);

  if (!lan.length) { error('No LAN interface found'); process.exit(1); }

  // Use the first LAN IP as the rewrite target; ignore any additional LAN interfaces.
  const primaryLan = lan[0];
  const LAN_IP = primaryLan.ip;

  info('Primary LAN interface:', `${primaryLan.name}=${primaryLan.ip}`);

  if (lan.length > 1) {
    for (const extra of lan.slice(1)) {
      warn(`Additional LAN interface found — ignoring: ${extra.name}=${extra.ip}`);
    }
  }

  info('Virtual interfaces:', virtual.length
    ? virtual.map(i => `${i.name}=${i.ip}`).join(', ')
    : '(none detected yet)');
  info('Rewriting A records to:', LAN_IP);

  const allIfaces = [primaryLan, ...virtual];
  const sockets = new Map(); // ip → { sock, iface }

  // ── Announcement cache ─────────────────────────────────────────────────
  // Stores the last rewritten mDNS announcement per advertised service.
  // Keyed by the service instance key returned by extractServiceKey(pkt),
  // rather than by source virtual IP, so each Homebridge service instance
  // has its own independent cached entry. A single object was used previously,
  // which caused later announcements to overwrite earlier ones — only one
  // service would ever be answered or re-announced on the LAN.
  //
  // When the relay receives a query on the LAN, instead of only forwarding it
  // to the container and *hoping* the container responds in time (it may not,
  // due to RFC 6762 duplicate-suppression), the relay immediately re-sends
  // every cached announcement. This is what dns-sd / mDNSResponder does: it
  // is always the authoritative responder for all registered services and
  // answers queries instantly from its local registration state.
  const announcementCache = new Map(); // serviceKey → { pkt: Buffer, ts: number }

  // Periodically re-announce all cached services on LAN so caches don't expire.
  const reannounceTimer = setInterval(() => {
    const now = Date.now();
    if (announcementCache.size === 0) return;
    info(`[re-announce] ${announcementCache.size} cached service(s)`);
    for (const [key, entry] of announcementCache.entries()) {
      const ageS = Math.round((now - entry.ts) / 1000);
      if (now - entry.ts > CACHE_MAX_AGE_MS) {
        announcementCache.delete(key);
        warn(`[cache] expired "${key}" (last seen ${ageS}s ago)`);
        continue;
      }
      for (const [ip, { sock, iface }] of sockets.entries()) {
        const isLan = !VIRTUAL_SUBNETS.some(s => ip.startsWith(s));
        if (!isLan) continue;
        sock.send(entry.pkt, MDNS_PORT, MDNS_ADDR, err => {
          if (err) error(`Re-announce error → ${ip}:`, err.message);
          else debug(`[${iface.name}] re-announced "${key}" (cached ${ageS}s ago)`);
        });
      }
    }
  }, REANNOUNCE_INTERVAL_MS);
  reannounceTimer.unref(); // don't prevent process exit

  for (const iface of allIfaces) {
    try {
      const sock = await createSocket(iface, (msg, rinfo, sourceIface) => {
        // Only rewrite packets coming FROM the virtual network
        const comingFromVirtual = VIRTUAL_SUBNETS.some(s =>
          rinfo.address.startsWith(s)
        );

        // Work on a copy so we don't corrupt the buffer for other listeners
        const pkt = Buffer.from(msg);
        const direction = comingFromVirtual ? 'VIRTUAL→LAN' : 'LAN→VIRTUAL';

        debug(`[${sourceIface.name}] ${direction} from ${rinfo.address}:${rinfo.port}  ${msg.length}b  ${summarisePacket(pkt)}`);

        if (comingFromVirtual) {
          rewriteARecords(pkt, VIRTUAL_SUBNETS, LAN_IP);

          // Cache the rewritten announcement keyed by the service instance name
          // extracted from the PTR record (e.g. "Homebridge 2._hap._tcp.local.").
          // Keying by IP would collapse all instances sharing the same container
          // VM IP into a single slot.  The service name is unique per bridge.
          if (!isQuery(pkt)) {
            const key = extractServiceKey(pkt);
            if (key) {
              const isNew = !announcementCache.has(key);
              announcementCache.set(key, { pkt, ts: Date.now() });
              if (isNew) {
                info(`[cache] new service registered: "${key}"  (cache size: ${announcementCache.size})`);
              } else {
                debug(`[cache] updated: "${key}"`);
              }
            }
          }
        } else {
          // Packet came from the LAN.  If it is a query AND we have cached
          // announcements, respond immediately with ALL of them — one per
          // registered Homebridge instance — just like dns-sd / mDNSResponder
          // does.  We still forward the query to the virtual network so the
          // containers stay in sync.
          if (isQuery(pkt)) {
            if (announcementCache.size > 0) {
              debug(`[cache] LAN query from ${rinfo.address} — replying with ${announcementCache.size} cached entry(s)`);
              for (const [key, entry] of announcementCache.entries()) {
                for (const [ip, { sock: targetSock, iface: targetIface }] of sockets.entries()) {
                  const isLan = !VIRTUAL_SUBNETS.some(s => ip.startsWith(s));
                  if (!isLan) continue;
                  targetSock.send(entry.pkt, MDNS_PORT, MDNS_ADDR, err => {
                    if (err) error(`Cache-reply error → ${ip}:`, err.message);
                    else debug(`[${targetIface.name}] cache-reply sent for "${key}"`);
                  });
                }
              }
            } else {
              debug(`[cache] LAN query from ${rinfo.address} — cache empty, forwarding only`);
            }
          }
        }

        // Forward to all other interfaces
        const targets = [...sockets.keys()].filter(ip => ip !== sourceIface.ip);
        debug(`[relay] forwarding ${msg.length}b from ${sourceIface.name}(${sourceIface.ip}) → [${targets.join(', ')}]`);
        for (const ip of targets) {
          const { sock: targetSock } = sockets.get(ip);
          targetSock.send(pkt, MDNS_PORT, MDNS_ADDR, err => {
            if (err) error(`Relay error → ${ip}:`, err.message);
          });
        }
      });

      sockets.set(iface.ip, { sock, iface });
    } catch (err) {
      error(`Failed to bind on ${iface.ip}:`, err.message);
    }
  }

  if (sockets.size === 0) {
    error('Failed to bind any mDNS sockets; exiting.');
    process.exit(1);
  }

  const hasLanSocket = lan.some(iface => sockets.has(iface.ip));
  if (!hasLanSocket) {
    error('Failed to bind any LAN interface sockets; exiting.');
    process.exit(1);
  }
  info(`mDNS proxy running — ${sockets.size} interface(s): [${[...sockets.keys()].join(', ')}]`);
  info(`Cache re-announce interval: ${REANNOUNCE_INTERVAL_MS / 1000}s  |  Max cache age: ${CACHE_MAX_AGE_MS / 1000}s`);

  // ── UDP broadcast relay ────────────────────────────────────────────────
  if (BROADCAST_RELAY_PORTS.length > 0) {
    info(`UDP broadcast relay ports: [${BROADCAST_RELAY_PORTS.join(', ')}]  (set BROADCAST_RELAY_PORTS=<ports> to override)`);
    for (const port of BROADCAST_RELAY_PORTS) {
      startBroadcastRelay(port, [lan[0]], virtual);
    }
  }
}

main().catch(console.error);
