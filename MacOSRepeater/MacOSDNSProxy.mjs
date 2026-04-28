#!/usr/bin/env node
/**
 * MacOSDNSProxy.mjs
 *
 * A lightweight UDP DNS proxy that listens on the virtual-network host
 * interfaces (192.168.64.x / 192.168.65.x) and resolves queries using
 * the macOS native resolver (dns.lookup → getaddrinfo → mDNSResponder).
 *
 * This gives Docker containers instant resolution of .local hostnames
 * without the 10-second mDNS relay round-trip delay.
 *
 * Usage (requires root to bind port 53):
 *   sudo node MacOSDNSProxy.mjs
 *
 * Then configure your container to use the host virtual IP as DNS:
 *   docker run --dns 192.168.64.1 ...
 *
 *   # or in docker-compose.yml:
 *   dns:
 *     - 192.168.64.1
 *
 * Environment variables:
 *   LOG_LEVEL=debug|info|warn|error   (default: info)
 *   DNS_PORT=<port>                   (default: 53; use e.g. 5300 for testing without sudo)
 */

import dgram from 'dgram';
import dns   from 'dns';
import os    from 'os';

// ── Config ─────────────────────────────────────────────────────────────────

const VIRTUAL_SUBNETS = ['192.168.64.', '192.168.65.'];
const DNS_PORT        = Number(process.env.DNS_PORT ?? 53);

// ── Logging ────────────────────────────────────────────────────────────────

const LEVELS = { debug: 0, info: 1, warn: 2, error: 3 };
const LEVEL  = LEVELS[(process.env.LOG_LEVEL || 'info').toLowerCase()] ?? LEVELS.info;

function ts() { return new Date().toISOString().replace('T', ' ').replace('Z', ''); }

function debug(...a) { if (LEVELS.debug >= LEVEL) console.log( `[${ts()}] [DEBUG]`, ...a); }
function info(...a)  { if (LEVELS.info  >= LEVEL) console.log( `[${ts()}] [INFO ]`, ...a); }
function warn(...a)  { if (LEVELS.warn  >= LEVEL) console.warn(`[${ts()}] [WARN ]`, ...a); }
function error(...a) { if (LEVELS.error >= LEVEL) console.error(`[${ts()}] [ERROR]`, ...a); }

// ── DNS packet helpers ──────────────────────────────────────────────────────

/**
 * Read a DNS name from buf starting at offset.
 * Handles label compression pointers.
 */
function readName(buf, offset) {
  const labels = [];
  let jumped = false;
  let end    = -1;
  let safety = 0;

  while (safety++ < 100) {
    if (offset >= buf.length) break;
    const len = buf[offset];

    if (len === 0) {
      if (!jumped) end = offset + 1;
      break;
    }

    // Compression pointer
    if ((len & 0xc0) === 0xc0) {
      if (!jumped) end = offset + 2;
      offset = ((len & 0x3f) << 8) | buf[offset + 1];
      jumped = true;
      continue;
    }

    offset++;
    labels.push(buf.slice(offset, offset + len).toString('ascii'));
    offset += len;
  }

  return { name: labels.join('.'), end };
}

/**
 * Parse the first question from a DNS query packet.
 * Returns null if the packet is not a valid query.
 */
function parseDnsQuestion(buf) {
  if (buf.length < 12) return null;
  const id    = buf.readUInt16BE(0);
  const flags = buf.readUInt16BE(2);
  if (flags & 0x8000) return null;       // It's a response, not a query
  if (!buf.readUInt16BE(4)) return null; // QDCOUNT == 0

  try {
    const { name, end } = readName(buf, 12);
    const qtype  = buf.readUInt16BE(end);
    const qclass = buf.readUInt16BE(end + 2);
    return { id, name, qtype, qclass };
  } catch {
    return null;
  }
}

/**
 * Encode a hostname as DNS wire-format labels.
 */
function encodeName(hostname) {
  const parts = hostname.replace(/\.$/, '').split('.');
  const bufs  = [];
  for (const label of parts) {
    const b = Buffer.from(label, 'ascii');
    bufs.push(Buffer.from([b.length]), b);
  }
  bufs.push(Buffer.from([0]));
  return Buffer.concat(bufs);
}

/** DNS NOERROR response with a single A record (TTL 60 s). */
function buildAResponse(id, nameBuf, address) {
  const header = Buffer.alloc(12);
  header.writeUInt16BE(id,     0);
  header.writeUInt16BE(0x8180, 2); // QR=1, RD=1, RA=1, RCODE=0
  header.writeUInt16BE(1,      4); // QDCOUNT=1
  header.writeUInt16BE(1,      6); // ANCOUNT=1

  const question = Buffer.concat([nameBuf, Buffer.from([0, 1, 0, 1])]); // TYPE A CLASS IN

  // Answer RR: pointer 0xc00c (offset 12), A, IN, TTL 60, RDLENGTH 4
  const rr = Buffer.alloc(12);
  rr.writeUInt16BE(0xc00c, 0);
  rr.writeUInt16BE(1,      2);  // TYPE A
  rr.writeUInt16BE(1,      4);  // CLASS IN
  rr.writeUInt32BE(60,     6);  // TTL
  rr.writeUInt16BE(4,     10);  // RDLENGTH
  const rdata = Buffer.from(address.split('.').map(Number));

  return Buffer.concat([header, question, rr, rdata]);
}

/** DNS NXDOMAIN response. */
function buildNxDomain(id, nameBuf, qtype) {
  const header = Buffer.alloc(12);
  header.writeUInt16BE(id,     0);
  header.writeUInt16BE(0x8183, 2); // QR=1, RD=1, RA=1, RCODE=3 (NXDOMAIN)
  header.writeUInt16BE(1,      4); // QDCOUNT=1
  const qt = Buffer.alloc(4);
  qt.writeUInt16BE(qtype, 0);
  qt.writeUInt16BE(1,     2); // CLASS IN
  return Buffer.concat([header, nameBuf, qt]);
}

/** DNS NOERROR response with 0 answers — for non-A query types. */
function buildEmptyNoError(id, nameBuf, qtype) {
  const header = Buffer.alloc(12);
  header.writeUInt16BE(id,     0);
  header.writeUInt16BE(0x8180, 2); // QR=1, RD=1, RA=1, RCODE=0
  header.writeUInt16BE(1,      4); // QDCOUNT=1
  const qt = Buffer.alloc(4);
  qt.writeUInt16BE(qtype, 0);
  qt.writeUInt16BE(1,     2); // CLASS IN
  return Buffer.concat([header, nameBuf, qt]);
}

// ── Proxy server ────────────────────────────────────────────────────────────

function startProxy(bindIp, port) {
  return new Promise((resolve, reject) => {
    const sock = dgram.createSocket({ type: 'udp4', reuseAddr: true });

    sock.on('error', err => {
      error(`[dns-proxy:${bindIp}]`, err.message);
    });

    sock.on('message', async (msg, rinfo) => {
      const q = parseDnsQuestion(msg);
      if (!q) return;

      const { id, name, qtype } = q;
      const hostname = name.replace(/\.$/, '');
      const nameBuf  = encodeName(hostname);

      // Only proxy A record queries; for everything else return empty NOERROR
      // so the client doesn't hang waiting for a timeout.
      if (qtype !== 1 /* A */) {
        debug(`[dns-proxy:${bindIp}] ${hostname} type=${qtype} → empty NOERROR`);
        sock.send(buildEmptyNoError(id, nameBuf, qtype), rinfo.port, rinfo.address);
        return;
      }

      try {
        // dns.lookup() uses getaddrinfo() which goes through the macOS native
        // resolver stack — the only Node.js path that resolves .local names
        // via Bonjour / mDNSResponder without a multicast round-trip.
        const { address } = await dns.promises.lookup(hostname, { family: 4 });
        info(`[dns-proxy:${bindIp}] ${hostname} → ${address}  (from ${rinfo.address})`);
        sock.send(buildAResponse(id, nameBuf, address), rinfo.port, rinfo.address);
      } catch (err) {
        debug(`[dns-proxy:${bindIp}] ${hostname} → NXDOMAIN (${err.code})`);
        sock.send(buildNxDomain(id, nameBuf, qtype), rinfo.port, rinfo.address);
      }
    });

    sock.bind(port, bindIp, () => {
      info(`[dns-proxy] listening on ${bindIp}:${port}`);
      resolve(sock);
    });

    sock.once('error', reject);
  });
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  info(`Log level: ${(process.env.LOG_LEVEL || 'info').toUpperCase()}`);
  info(`DNS port:  ${DNS_PORT}${DNS_PORT !== 53 ? '  (set DNS_PORT=53 for production)' : ''}`);

  const nets = os.networkInterfaces();
  const bindAddresses = [];

  for (const addrs of Object.values(nets)) {
    for (const addr of addrs) {
      if (addr.family === 'IPv4' && VIRTUAL_SUBNETS.some(s => addr.address.startsWith(s))) {
        bindAddresses.push(addr.address);
      }
    }
  }

  if (!bindAddresses.length) {
    error('No virtual interfaces found (expected subnets:', VIRTUAL_SUBNETS.join(', ') + ')');
    error('Is Apple Virtualization / Docker running?');
    process.exit(1);
  }

  const started = [];
  for (const ip of bindAddresses) {
    try {
      await startProxy(ip, DNS_PORT);
      started.push(ip);
    } catch (err) {
      warn(`[dns-proxy] failed to bind ${ip}:${DNS_PORT} — ${err.message}`);
      if (DNS_PORT === 53) {
        warn('[dns-proxy] port 53 requires root — try: sudo node MacOSDNSProxy.mjs');
        warn('[dns-proxy] or test without root: DNS_PORT=5300 node MacOSDNSProxy.mjs');
      }
    }
  }

  if (!started.length) {
    error('Failed to start any DNS proxy; exiting.');
    process.exit(1);
  }

  info('');
  info('──────────────────────────────────────────────────────────────');
  info(`DNS proxy running on: [${started.join(', ')}]:${DNS_PORT}`);
  info('');
  info('To enable .local resolution in containers, use one of:');
  for (const ip of started) {
    info(`  docker run --dns ${ip} ...`);
  }
  info('');
  info('  # docker-compose.yml:');
  info(`  dns:`);
  for (const ip of started) {
    info(`    - ${ip}`);
  }
  info('──────────────────────────────────────────────────────────────');
}

main().catch(console.error);
