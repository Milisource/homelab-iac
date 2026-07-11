> Adapted from internal documentation. Some details have been generalized for public reference.

# Network Topology

## Subnets

| Network | Purpose |
|---------|---------|
| 192.168.50.0/24 | LAN (local network) |
| 100.x.x.x/10 | Tailscale |
| 192.168.112.0/20 | gluetun_default (milis-wonderspace) |
| 10.20.0.0/24 | dns-net (milis-wonderspace) |
| 172.17.0.0/16 | docker0 (default bridge) |
| 192.168.240.0/20 | docker_gwbridge |

### Docker Overlay Networks (Swarm-wide)

| Network | Driver | Purpose |
|---------|--------|---------|
| traefik-public | overlay | Public-facing services behind Traefik |
| media-net | overlay | Media stack internal communication |
| apps-net | overlay | Apps stack internal |
| vpn | overlay | Isolated network for routed services |
| adguard_default | overlay | AdGuard Home services |
| portainer_agent_network | overlay | Portainer agent ↔ server |
| ingress | overlay | Swarm routing mesh |

### milkymiracle-specific Networks

| Network | Purpose |
|---------|---------|
| vocard | Vocard bot suite (internal) |
| web (traefik-web) | Portfolio web services |
| backend | Portfolio backend (internal, encrypted) |
| docker-proxy | Portfolio Docker API proxy (internal) |

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

- Tailscale MagicDNS: `100.x.x.x`
- Fallback: `8.8.8.8`, `1.1.1.1`
- Immich and other apps explicitly use `192.168.50.122` (milkymiracle) as DNS
- keepalived health-checks port 53 and moves the VIP if the current holder fails

## Firewall

- No iptables modifications detected beyond Docker's default rules
- VPN gateway firewall restricts inbound to specific ports
- Traefik exposes ports 80, 443, 8080

## Tailscale ACLs

- Direct connections between nodes (both LAN and Tailscale IPs work)
- Tailscale serves as fallback VPN/overlay when direct connection is possible
