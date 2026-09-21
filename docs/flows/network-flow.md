# Network & Traffic Flows

## External Access Flow

```
User Browser
  │
  ├── DNS: Cloudflare (example.com) / AGH wildcard *.example.com
  │
  ▼
VIP 192.168.50.99:80/443 (keepalived — floats to healthiest node)
  │
  ▼
Traefik (swarm replica on VIP holder)
  │
  ├── traefik-overlay network
  │   ├── jellyfin.example.com   → Jellyfin (milkymiracle)
  │   ├── foundry.example.com    → FoundryVTT (milkymiracle)
  │   ├── jobs.example.com       → Job-ops (milkymiracle)
  │   ├── immich.example.com     → Immich (milkymiracle)
  │   ├── iptv.example.com       → Masqueradarr (milkymiracle)
  │   ├── vault.example.com      → Vaultwarden (heavensfeel)
  │   ├── n8n.example.com        → n8n (heavensfeel)
  │   ├── asf.example.com        → ArchiSteamFarm (heavensfeel)
  │   ├── serr.example.com       → Jellyseerr (heavensfeel)
  │   ├── claims.example.com     → free-games-claimer (heavensfeel)
  │   ├── search.example.com     → SearXNG (heavensfeel)
  │   ├── status/watch/grafana.*    → monitoring hub (heavensfeel)
  │   ├── navi.example.com       → Navidrome (milis-wonderspace)
  │   ├── cloud.example.com      → CopyParty (milis-wonderspace)
  │   ├── sonarr/radarr/lidarr/bazarr/prowlarr/komga/slskd.* → milis-wonderspace
  │   ├── archive.example.com    → ArchiveBox (milis-wonderspace)
  │   │
  │   └── qbt.example.com → 192.168.50.115:8090 → Gluetun → qBittorrent (milis-wonderspace)
```

## DNS Flow

```
Any Service
  │
  ▼
AdGuard Home (on local node, port 53)
  │  Filters ads, tracks, malware
  ▼
Unbound (localhost:53, recursive resolver)
  │
  ▼
Cloudflare DoT (1.1.1.1, encrypted)
```

## Docker Internal Flow

### Swarm Service → Service
```
Container-A (traefik-overlay)
  │
  ▼ (overlay network DNS)
Service-Name:Port
  │
  ▼
Container-B (same overlay network)
```

### VPN Isolation
```
qBittorrent → Gluetun network namespace
  │
  ├── All traffic via PIA VPN tunnel
  ├── Outbound to LAN allowed via FIREWALL_OUTBOUND_SUBNETS
  │   (192.168.0.0/16, 100.64.0.0/10, 172.16.0.0/12)
  └── No direct internet without VPN
```

## Storage Flow

```
milis-wonderspace
  │
  ├── mergerFS: disk1+disk2+disk3+disk4+disk5 = /mnt/network (29TB)
  │
  ├── NFS export /mnt/network ──► milkymiracle:/mnt/network
  │
  └── NFS export /DATA ──► milkymiracle:/DATA (mounted locally on both)
```
