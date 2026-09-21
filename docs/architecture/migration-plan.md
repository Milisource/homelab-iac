# Migration Summary

## What We Did

Migrated 17 swarm services → standalone Docker Compose across 3 homelab nodes over 4 phases.

> **Status (2026-08-01):** All planned moves below are **complete**. Current placement:
> - milis-wonderspace: *Arr, Navidrome, **Komga**, **slskd**, copyparty, archivebox, gluetun/qbittorrent, borgmatic
> - milkymiracle: jellyfin, foundryvtt, vocard, immich, job-ops, portainer, **masqueradarr**
> - heavensfeel: vaultwarden, archisteamfarm, byparr, n8n, jellyseerr, qui, termix, searxng, 5etools, free-games-claimer, monitoring hub

## Pre-Migration State

```
milis-wonderspace (worker)     milkymiracle (manager)        heavensfeel (—)
─────────────────────────      ─────────────────────         ─────────────────
  swarm services:                swarm services:
  sonarr, radarr, lidarr         jellyfin, komga, kavita      (not in swarm yet)
  prowlarr, bazarr, cleanuparr   foundryvtt, traefik
  navidrome, n8n                 adguard, portainer_agent
  vaultwarden, ASF, copyparty
  jellyseerr

  standalone:                    standalone:
  gluetun + qbittorrent          vocard suite (6), immich
  byparr                         job-ops, portainer
                                 slskd, qui, termix
```

## Post-Migration State

Everything is standalone Docker Compose except 3 true swarm services.

### Swarm (keep forever)

| Service | Mode | Nodes |
|---------|------|-------|
| traefik | replicated 1/1 | managers (milkymiracle ↔ heavensfeel) |
| adguard | global | all 3 |
| portainer_agent | global | all 3 |

### milis-wonderspace (compose: `milis-wonderspace.yml`)

sonarr, radarr, lidarr, prowlarr, bazarr, cleanuparr
navidrome, copyparty
komga (unified reader), slskd
gluetun + qbittorrent

### milkymiracle (compose: `milkymiracle.yml` + standalone)

jellyfin, foundryvtt
vocard suite (6), immich (4), job-ops, portainer

### heavensfeel (compose: `heavensfeel.yml`)

vaultwarden, archisteamfarm, byparr, n8n, jellyseerr, qui, termix

## Key Changes

| Service | From | → To | Why |
|---------|------|------|-----|
| vaultwarden | milis-wonderspace | heavensfeel | critical uptime, 15W always-on |
| archisteamfarm | milis-wonderspace | heavensfeel | idle daemon, minimal resources |
| byparr | milis-wonderspace | heavensfeel | no persistent data |
| n8n | milis-wonderspace | heavensfeel | light enough for SATA SSD |
| jellyseerr | milis-wonderspace | heavensfeel | ~200MB, talks to *arrs over HTTP |
| komga | milkymiracle | milis-wonderspace | library scanning avoids NFS |
| kavita | milkymiracle | ~~milis-wonderspace~~ | **Decommissioned 2026-05-08** — replaced by Calibre-web (native on milis-wonderspace). Kavita's folder/filename parsing caused series-grouping issues with PDF books. Calibre-web uses a metadata DB instead. |
| slskd | milkymiracle | milis-wonderspace | downloads land on mergerFS directly |
| qui | milkymiracle | heavensfeel | frees milkymiracle, lightweight |
| termix | milkymiracle | heavensfeel | frees milkymiracle, minimal |
| jellyfin | swarm → compose | milkymiracle | GPU + NVMe + I219-LM |
| foundryvtt | swarm → compose | milkymiracle | NVMe + low-latency websockets |

## Issues Found & Fixed During Migration

### Traefik Standalone Container Routing
Standalone containers on different nodes aren't auto-discovered by Traefik's Docker provider (only sees local socket). Fixed with file-based routing at `/etc/traefik/dynamic/standalone.yml`, replicated to both manager nodes. Uses container DNS names (`sonarr:8989`) instead of static IPs, so routes survive restarts.

### Traefik `--providers.swarm.endpoint`
Explicitly setting `--providers.swarm.endpoint=unix:///var/run/docker.sock` broke the swarm provider. Removing it fixed auto-detection.

### Sudo + rsync Across Nodes
`sudo rsync` preserves SSH keys correctly when using `ssh -i /home/user/.ssh/id_ed25519` explicitly (sudo changes environment).

### AdGuard YAML Config
The `upstream_dns_file: ""` line was incorrectly indented under `upstream_mode`, causing YAML parse failures on fresh containers. Per-node configs fixed with correct indentation.

### Unbound DNS Chain
AdGuard on each node uses its local Unbound (port 5335) as primary, with the other two nodes' Unbound as fallback in `load_balance` mode.

## Remaining Cleanup (Phase 5 — after 48h stability)

```bash
docker stack rm apps media
docker network prune
```

## Compose File Locations

All 3 compose files + `.env` + `secrets/` are replicated to `~/docker/compose/` on every node.

## Service Status

All 12 Traefik-routed domains return 200/302 via Cloudflare (DNS-only, not proxied). Direct port access works via swarm ingress mesh. No open ports needed on any individual node.

## Key Learnings

1. **File provider over file routes** — doesn't conflict with auto-discovery, just shadows it
2. **Overlay DNS names** — use `container_name:service_port` in file config instead of IPs
3. **SATA is fine for light services** — n8n, vaultwarden, jellyseerr don't need NVMe
4. **heavensfeel's 15W** — perfect for critical always-on daemons
5. **Komga on storage node** — avoids NFS round-trips, handles books + comics + manga in one place
6. **Kavita & Calibre-web both decommissioned** — Kavita's filename parsing broke hat folders; Calibre-web was too book-only. Komga's folder-as-series model fits the homelab's organizational structure.
