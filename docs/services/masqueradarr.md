# Masqueradarr (IPTV Aggregator)

**Host**: milkymiracle | **Domain**: [iptv.example.com](https://iptv.example.com) | **Port**: 3000

## Overview

Self-hosted IPTV aggregator. Ingests M3U playlist / EPG sources, proxies streams behind a
single unified identity, and exposes a management SPA plus exportable playlists. Think of it
as a privacy layer for scattered IPTV feeds — all streams are proxied through the homelab so
the upstream source only ever sees this server's IP.

Source: [TheBinaryNinja/masqueradarr](https://github.com/TheBinaryNinja/masqueradarr)

## Configuration

| Setting | Value |
|---------|-------|
| Container | masqueradarr |
| Image | `iflip721/masqueradarr:dev` |
| Backend | mongo-masq (MongoDB 7.0.15, port 27018 on loopback) |
| Port | 3000 (published) |
| User | 1000:1000 |
| Data dir | `/DATA/Apps/masqueradarr/` (compose, mongo, backups) |
| Compose file | `/home/user/docker/compose/milkymiracle.yml` |
| Networks | masqueradarr-net (bridge) + traefik-overlay (external) |

### Environment

| Variable | Value |
|----------|-------|
| `MONGO_ROOT_USER` / `MONGO_ROOT_PASS` | masqueradarr / (stored in compose) |
| `DOMAIN` | defaults to `http://localhost:3000` |
| `MONGO_HOST` | mongo-masq |
| `TZ` | America/New_York |
| `DNS_LOG_LEVEL` | 2 |

### Volumes

| Host | Container | Purpose |
|------|-----------|---------|
| `/DATA/Apps/masqueradarr/compose` | `/app/compose` | User-created IPTV compositions |
| `/DATA/Apps/masqueradarr/backups` | `/backups` | Config backups |
| `/DATA/Apps/masqueradarr/mongo` | `/data/db` (mongo-masq) | MongoDB data |

## Architecture

```
iptv.example.com
  │
  ▼
Traefik (milkymiracle) → Host(`iptv.example.com`)
  │
  ▼
masqueradarr:3000 (traefik-overlay)
  │
  ├── mongo-masq (27017, loopback 27018)
  └── upstream M3U/EPG sources (streams proxied via homelab)
```

Traefik routing is defined via **Docker labels** on the container (not the file provider):

```
traefik.http.routers.masqueradarr.rule = Host(`iptv.example.com`)
traefik.http.routers.masqueradarr.tls.certresolver = le
traefik.http.services.masqueradarr.loadbalancer.server.port = 3000
```

MongoDB is **not** exposed on the overlay — it lives on `masqueradarr-net` (bridge) and is only
published to `127.0.0.1:27018` for host-side administration.

## Usage

1. Open `https://iptv.example.com`
2. Add M3U/EPG sources in the management UI
3. Compositions are exported as playlists pointing at proxied stream URLs
4. Point any IPTV client at the exported playlist — streams egress via the homelab WAN IP

## Notes

- Image tag `:dev` — track upstream releases before production use
- Backups are written to `/DATA/Apps/masqueradarr/backups` (not part of the borgmatic /DATA backup? — verify `borgmatic/config.yaml` includes this path)
