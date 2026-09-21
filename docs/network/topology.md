> Adapted from internal documentation. Some details have been generalized for public reference.

# Network Topology

## Subnets

| Network | Purpose |
|---------|---------|
| 192.168.50.0/24 | LAN (local network) |
| 100.x.x.x/10 | Tailscale |
| 172.17.0.0/16 | docker0 (default bridge) |
| 192.168.240.0/20 | docker_gwbridge |

### Docker Overlay Networks (Swarm-wide)

| Network | Driver | Purpose |
|---------|--------|---------|
| traefik-overlay | overlay | Primary cross-node network — all app containers + Traefik |
| traefik-public | overlay | Legacy (replaced by traefik-overlay); still present |
| base-services_default | overlay | Internal to the base-services stack (AdGuard, exporters) |
| portainer-agent_agent_network | overlay | Portainer agent ↔ server |
| ingress | overlay | Swarm routing mesh |

### Node-local Networks

| Network | Node | Purpose |
|---------|------|---------|
| masqueradarr-net | milkymiracle | bridge — masqueradarr ↔ mongo-masq (MongoDB not on an overlay) |
| immich_default | milkymiracle | bridge — Immich app ↔ Postgres ↔ Redis |
| vocard | milkymiracle | bridge — Vocard bot suite (internal) |
| compose_default | milis-wonderspace | bridge — local compose helper network |
| redlib-instances_default | heavensfeel | bridge — static Redlib instance list container |

## External Access

```
Internet (Cloudflare)
  │
  ▼
Router
  │  - Port forward 80/443 → 192.168.50.99
  │  - DHCP DNS option 6 → 192.168.50.99
  ▼
192.168.50.99  (keepalived VIP — floats to healthiest node)
  ├── milkymiracle (priority 150)
  ├── heavensfeel (priority 100)
  └── milis-wonderspace (priority 50)
```

## DNS Chain

```
Client DNS Request
  │
  ▼
VIP: 192.168.50.99:53 → AdGuard Home (on whichever node holds the VIP)
  │  - DHCP, DNS filtering, ad blocking
  │  - Runs on ALL 3 nodes (swarm global mode)
  ▼
Unbound (localhost:5335 on each node)
  │  - Recursive DNS resolver
  ▼
Cloudflare (DoT — DNS over TLS)
```

- Tailscale MagicDNS: `100.100.100.100`
- Tailscale custom nameservers: the Tailscale IPs of the AdGuard nodes
- Tailscale subnet route: `192.168.50.0/24` (advertised by milis-wonderspace) — remote clients reach LAN IPs directly
- Fallback: `8.8.8.8`, `1.1.1.1`

### AdGuard Home ports (base-services global)

| Port | Purpose |
|------|---------|
| 53 | TCP/UDP DNS |
| 67 | DHCP |
| 3020 | Admin web UI |
| 853 | DNS-over-TLS |
| 443 | DNS-over-HTTPS/QUIC (UDP) |

## Public DNS, DDNS & the WAN

Inbound access from the wider internet is a **different chain** from the internal one above:

```
Cloudflare (authoritative for example.com)
  │  one CNAME per public service → <router-ddns>.asuscomm.com
  ▼
<router>.asuscomm.com    (router DDNS — tracks the router's public WAN address)
  │
  ▼
Router WAN   (dynamically assigned public IPv4 — changes on reboots / WAN events)
  │  port-forward 80/443 → 192.168.50.99
  ▼
VIP 192.168.50.99 → Traefik
```

- **Only public services get a Cloudflare CNAME.** Everything else is internal-only: LAN/Tailscale
  clients resolve it through the AdGuard wildcard `*.example.com → 192.168.50.99`, and public
  resolvers return NXDOMAIN. This is intentional. See [Traefik → Public vs internal-only](../services/traefik.md#public-vs-internal-only).
- **The router's WAN address is a real public IP, but it is not static** — it can change on a
  reboot or WAN event. Nothing should hardcode it: the Cloudflare CNAMEs point at the DDNS name
  so they follow the address automatically.
- The **apex domain** is itself a CNAME to the DDNS name (so it self-heals too), but no Traefik
  router serves the bare apex. Mail is handled by a hosted provider (MX + SPF/DKIM/DMARC),
  independent of the web chain.

### Failure mode: stale DDNS after a router reboot

The router reboots on a weekly schedule. If the reboot returns a **new** WAN address and the DDNS
update fails, **every** public CNAME stays pinned to the old, dead address — and because all
public hostnames resolve through the DDNS name, the whole fleet disappears from the wider
internet at once while remaining perfectly reachable on the LAN.

This happened once (2026-09-07): the DDNS client logged `update ddns token failed` and retried
every 5 minutes for ~6 hours without recovering. **Fix:** re-authenticate the DDNS client on the
router (refresh the DDNS token) and let it push — there is no DNS propagation delay to wait out;
the record is genuinely stuck.

**Fast diagnosis:**
- Resolve the router's DDNS name from a public resolver and compare it to the router's actual WAN
  address. A mismatch means the DDNS push failed — check the router's DDNS log.
- *Every* service down at once while LAN access is fine → suspect the WAN/DDNS chain, **not**
  Traefik, keepalived, or the swarm (all of which are internal to the VIP and independent of the
  WAN address).

### Internal-only hostnames (no Cloudflare record)

`claims`, `5etools`, `search`, `status`, `watch`, `grafana`, `termix`, `slskd`, `immich`, `rss`,
`iptv`, plus `cockpit` / `cockpite` / `cockpith`. All resolve internally via the AdGuard wildcard
and are reachable over LAN/Tailscale; none are exposed to the internet. `cloud` and `jobs` are the
two Cloudflare-**proxied** (orange-cloud) hosts.

### Tailscale accept-routes policy (CRITICAL)

| Device class | `--accept-routes` | Why |
|---|---|---|
| **LAN nodes** | **`false`** | Physically on `192.168.50.0/24`; must use the direct LAN. Accepting the subnet route makes them hairpin intra-LAN swarm traffic (Raft 2377, VXLAN 4789) through `tailscale0`, causing asymmetric routing that partitions the swarm. |
| **Remote clients** | **`true`** | Off-LAN; need the subnet route to reach `192.168.50.x` services. |

milis-wonderspace advertises the subnet route **and** must NOT accept it. After changing
`accept-routes` on a Swarm node, restart Docker on that node to rebuild the VXLAN tunnels — the
routing fix alone leaves stale data-plane egress.

## Firewall

- CrowdSec firewall bouncer (nftables) active on all 3 nodes (native systemd, not Docker)
- Gluetun firewall restricts inbound traffic for the VPN-isolated services
- Traefik exposes ports 80, 443, 8080

## Tailscale ACLs

- Direct connections between nodes (both LAN and Tailscale IPs work)
- Tailscale serves as fallback VPN/overlay when a direct connection is possible

## VPN (PIA via Gluetun)

- Provider: Private Internet Access (OpenVPN, UDP)
- Port forwarding: enabled (forwarded port synced into the download client by a systemd timer)
- Download client runs inside Gluetun's network namespace; the old dedicated `vpn` overlay was removed
