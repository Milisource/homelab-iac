# Tailscale

**Nodes**: 6 (3 homelab + 3 clients) | **Tailnet**: `your-tailnet.ts.net` | **Owner**: admin@example.com

## Overview

Tailscale provides a WireGuard-based overlay network across all homelab nodes and remote clients. DNS and subnet routing are configured to extend the LAN DNS chain (AdGuard → Unbound → Cloudflare) to remote clients without additional layers.

## Tailnet Nodes

| Hostname | Tailscale IP | LAN IP | Role |
|---|---|---|---|
| milkymiracle | `100.x.x.x` | `192.168.50.122` | DNS resolver, VIP holder |
| milis-wonderspace | `100.x.x.x` | `192.168.50.115` | DNS resolver, storage |
| heavensfeel | `100.x.x.x` | `192.168.50.129` | Daemon host |
| laptop | `100.x.x.x` | `192.168.50.x` | Laptop (roams) |
| phone | `100.x.x.x` | — | Mobile phone |
| desktop | `100.x.x.x` | `192.168.50.x` | Desktop (LAN-only, no Tailscale DNS) |

## DNS Architecture

Tailscale's custom nameservers point to the homelab nodes running AdGuard Home, giving remote clients the same DNS chain as local LAN clients.

### DNS Chain

```
Tailscale client (laptop / phone)
  │
  ▼
Tailscale DNS proxy (100.100.100.100)
  │
  ├── *.your-tailnet.ts.net  →  MagicDNS (native, not forwarded)
  │
  └── everything else      →  Tailscale backbone
                                │
                                ├── milkymiracle:100.x.x.x:53
                                │     └── AdGuard → Unbound → Cloudflare DoT
                                │
                                └── milis-wonderspace:100.x.x.x:53
                                      └── AdGuard → Unbound → Cloudflare DoT
```

### Configuration

- **MagicDNS**: Enabled — all nodes reachable at `<hostname>.your-tailnet.ts.net`
- **Custom nameservers** (global): the homelab nodes' Tailscale IPs
- **Split DNS**: `ts.net.` → Tailscale internal resolver (keeps MagicDNS native)
- **Search domain**: `your-tailnet.ts.net`

### Node DNS Settings

| Node | `--accept-dns` | System DNS |
|---|---|---|
| milkymiracle | enabled | `127.0.0.1` (AdGuard local, immutable) |
| milis-wonderspace | enabled | `100.100.100.100` (Tailscale-managed) |
| heavensfeel | enabled | `100.100.100.100` (Tailscale-managed) |
| laptop | enabled | Tailscale-managed |
| phone | enabled (VPN mode) | Tailscale-managed |
| desktop | disabled | `192.168.50.99` (LAN VIP directly) |

## Subnet Routing

The `192.168.50.0/24` LAN subnet is advertised by all 3 homelab nodes and approved in the admin console. This allows remote clients to reach LAN IPs directly through the Tailscale tunnel — required for internal-only services that resolve to the VIP or node LAN IPs.

### Advertised Routes

```bash
# Configured on each homelab node:
sudo tailscale set --advertise-routes=192.168.50.0/24
```

Approved in Tailscale admin console → Subnet routes tab for all 3 nodes.

### How It Works

```
Remote client → resolves status.example.com
  → Tailscale DNS → AdGuard → returns 192.168.50.99 (VIP)
  → routes 192.168.50.99 through Tailscale tunnel (subnet route)
  → Traefik on VIP serves the request
```

## Notes

- `--accept-dns=true` is set via `tailscale set` (not `tailscale up`) to avoid re-authentication
- milkymiracle has `chattr +i /etc/resolv.conf` to prevent Tailscale from overwriting its local DNS config (it serves DNS, doesn't consume it)
- Mobile clients (Android/iOS) accept subnet routes automatically via full-VPN mode
- Public Cloudflare-proxied services work independently of Tailscale; this setup is for internal-only services behind Traefik
