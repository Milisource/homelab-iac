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
Traefik (reverse proxy, TLS termination, on whichever manager holds the VIP)
  │                              │
  │                    ┌─────────┴──────────────────┐
  │                    ▼                            ▼
  │         CrowdSec Bouncer (forwardAuth)   vpn overlay net
  │          (403 if banned, 200 if allowed)        │
  │                    │
  │            traefik-public net
  │                    │
  │    ┌───────────────┼───────────────┐
  │    ▼               ▼               ▼
  │ Jellyfin    Navidrome       n8n etc.
  │ (milkymiracle) (milis-wonderspace)
  │
  └── CrowdSec LAPI (milkymiracle:8585) ──► Firewall Bouncer (nftables)
       │                                    └── Blocks at network level on all 3 nodes
       ├── Community blocklist (18k+ IPs)
       ├── 57+ HTTP scenarios (CVEs, SQLi, XSS, probing)
       └── SSH bruteforce detection
```

## Traffic Flow — Internal

```
milis-wonderspace
  │
  ├── mergerfs pool: /mnt/network (29TB)
  │   ├── Torrents/ (downloads, media libraries)
  │   ├── Home/
  │   ├── DATA/ (appdata)
  │   │   ├── Arr/   (radarr, sonarr, lidarr, prowlarr, bazarr, etc.)
  │   │   ├── Apps/  (n8n, vaultwarden, asf, copyparty, foundry)
  │   │   ├── Media/ (jellyfin config, navidrome, komga, etc.)
  │   │   └── Net/   (adguard configs)
  │   │
  │   └── NFS export ───► milkymiracle
  │
  └── Docker Swarm worker node

milkymiracle
  │
  ├── Docker Swarm manager (leader)
  ├── Traefik (reverse proxy, port 80/443)
  ├── Jellyfin (hardware transcoding)
  ├── Immich (photo management, standalone compose)
  ├── Portfolio (resufolio.io, standalone stack)
  └── Vocard (Discord music bot suite)
```

## Node Responsibilities

### milis-wonderspace
- **Storage**: All 6 disks merged via mergerFS into `/mnt/network` (29TB usable)
- **Arr Suite**: Radarr, Sonarr, Lidarr, Prowlarr, Bazarr, Cleanuparr
- **Apps**: n8n, Vaultwarden, ArchiSteamFarm, CopyParty
- **Network isolation**: VPN gateway for isolated services
- **Security**: CrowdSec — firewall bouncer (nftables), community blocklist

### milkymiracle
- **Reverse Proxy**: Traefik with Let's Encrypt (Cloudflare DNS challenge)
- **Media Streaming**: Jellyfin (with GPU transcoding)
- **Music**: Navidrome
- **Reading**: Komga (comics, manga, books — unified reader)
- **Photos**: Immich (standalone compose)
- **Discord**: Vocard bot suite (music, dashboard)
- **Portfolio**: resufolio (SvelteKit, InfluxDB metrics)
- **Security**: CrowdSec — LAPI + Traefik bouncer (forwardAuth) + firewall bouncer

### heavensfeel
- **Swarm Quorum**: 3rd manager for fault tolerance
- **Standby**: Lightweight control plane, available for compute if needed
- **Failover**: Holds keepalived VIP (priority 100) if milkymiracle goes down
- **Security**: CrowdSec — firewall bouncer (nftables), Traefik HTTP protection, community blocklist

## Docker Swarm

3-node Swarm cluster (heavensfeel = leader, milkymiracle = reachable, milis-wonderspace = reachable).

Most services run as standalone `docker compose` per node rather than Swarm stacks.
The only active swarm services are global monitoring agents and Traefik.
