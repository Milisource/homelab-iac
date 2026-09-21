> Adapted from internal documentation. Some details have been generalized for public reference.

# Architecture Overview

## Traffic Flow

```
Internet
  │
  ▼
Cloudflare (DNS / Proxy for *.example.com)
  │
  ▼
Router (port 80/443 → 192.168.50.99)
  │
  ▼
VIP: 192.168.50.99  (keepalived — floats to healthiest node)
  │
  ▼
Traefik (reverse proxy, TLS termination, 3 replicas; on whichever node holds the VIP)
  │
  │   traefik-overlay net
  │
  │    ┌───────────────┼───────────────┐
  │    ▼               ▼               ▼
  │ Jellyfin    Navidrome      n8n etc.
  │ (milkymiracle) (milis-wonderspace) (heavensfeel)
  │                                    │
  │                                    ▼
  │                               Gluetun → qBittorrent
  │                               (VPN, milis-wonderspace)
  │
  └── CrowdSec (native on all 3 nodes)
       ├── Community blocklist (18k+ IPs)
       ├── HTTP scenarios (CVEs, SQLi, XSS, probing)
       ├── SSH bruteforce detection
       └── Firewall Bouncer (nftables) — blocks at network level on all 3 nodes
```

> The Docker-based Traefik forwardAuth bouncer (`crowdsec-bouncer`) was **retired**;
> CrowdSec enforcement is now purely the native firewall bouncer on each node.

## Traffic Flow — Internal

```
milis-wonderspace (storage node)
  │
  ├── mergerFS pool: /mnt/network (~29TB)
  │   ├── Torrents/ (downloads, media libraries)
  │   ├── Home/
  │   ├── Photos/ (immich library)
  │   └── DATA/ (appdata)
  │       ├── Arr/   (radarr, sonarr, lidarr, prowlarr, bazarr)
  │       ├── Apps/  (copyparty, archivebox, borgmatic)
  │       ├── Media/ (navidrome, komga, slskd configs)
  │       └── Net/   (gluetun, qbittorrent, adguard configs)
  │
  └── NFS export ───► milkymiracle + heavensfeel
  │
  └── Docker Swarm manager node

milkymiracle (compute node)
  │
  ├── Docker Swarm manager (leadership is elected; currently heavensfeel)
  ├── Traefik replica (port 80/443)
  ├── Jellyfin (hardware transcoding)
  ├── Immich (photo management, standalone compose)
  ├── Masqueradarr (IPTV) + mongo-masq
  └── Vocard (Discord music bot suite)

heavensfeel (always-on daemon + monitoring hub)
  ├── Docker Swarm manager
  ├── Prometheus / Grafana / Loki / Uptime Kuma
  ├── n8n, Hermes, SearXNG
  └── Vaultwarden, ArchiSteamFarm, free-games-claimer
```

## DNS and Public Exposure

- **Internal DNS** — LAN/Tailscale clients resolve *any* `*.example.com` host through the AdGuard
  wildcard to the VIP (`192.168.50.99`). See [Network Topology](../network/topology.md).
- **Public exposure** — only a subset of hosts have an explicit Cloudflare CNAME (chained to the
  router's DDNS name). Everything else is internal-only and returns NXDOMAIN from public
  resolvers. "Has a Traefik router" does **not** mean "is reachable from the internet". See
  [Network Topology → Public DNS, DDNS & the WAN](../network/topology.md#public-dns-ddns-the-wan)
  and [Traefik → Public vs internal-only](../services/traefik.md#public-vs-internal-only).

## Node Responsibilities

### milis-wonderspace
- **Storage**: All 5 disks merged via mergerFS into `/mnt/network` (~29TB usable)
- **Downloads**: qBittorrent routed through Gluetun (PIA VPN)
- **Arr Suite**: Radarr, Sonarr, Lidarr, Prowlarr, Bazarr, Cleanuparr
- **Media**: Navidrome, Komga, slskd, CopyParty
- **Archiving**: ArchiveBox (self-hosted web archiving)
- **Backups**: Borgmatic (`/DATA`, daily)
- **Security**: CrowdSec — native firewall bouncer (nftables)

### milkymiracle
- **Reverse Proxy**: Traefik replica + keepalived VIP (priority 150)
- **Media Streaming**: Jellyfin (with GPU transcoding)
- **Games**: FoundryVTT
- **Photos**: Immich (standalone compose)
- **IPTV**: Masqueradarr + mongo-masq
- **Discord**: Vocard bot suite (music, dashboard)
- **Jobs**: Job-ops automation tool
- **Security**: CrowdSec — native firewall bouncer

### heavensfeel
- **Swarm Manager**: 3rd manager for quorum (currently the leader)
- **Monitoring Hub**: Prometheus, Grafana, Loki, Uptime Kuma
- **Automation**: n8n, Hermes, Camofox, SearXNG
- **Always-On Daemons**: Vaultwarden, ArchiSteamFarm, free-games-claimer
- **Failover**: Holds keepalived VIP (priority 100) if milkymiracle goes down
- **Security**: CrowdSec — native firewall bouncer

## Docker Swarm

3-node Swarm cluster (heavensfeel = leader, milkymiracle = reachable,
milis-wonderspace = reachable as of 2026-09-21). Leadership is an elected Raft role and can
move between nodes; what matters is that **all three are managers**, so quorum survives the
loss of any single node.

Most services run as standalone `docker compose` per node rather than Swarm stacks. The only
active swarm services are the global monitoring agents (`base-services`), the Portainer agent,
and Traefik (3 replicas — one per node).

## Infrastructure as Code

The per-node compose files and Traefik dynamic configs are the source of truth and are
converged onto the nodes by an Ansible playbook. A public CI pipeline lints, validates, and
image-scans the repo (yamllint + ansible-lint + compose config + Trivy).
