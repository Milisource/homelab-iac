# milkymiracle (eserver)

**IP**: 192.168.50.122 | **Tailscale**: 100.x.x.x
**OS**: Ubuntu 24.04 LTS | **Kernel**: 6.8.0-generic
**CPU**: 6 cores | **RAM**: 15GB | **Swap**: 4GB (0 used)
**Docker Engine**: 29.6.1

## Role: Compute & Media Streaming Node

Swarm manager node. Runs reverse proxy, media streaming, and compute-heavy services.

## Hardware

- Single NVMe SSD (LVM: ubuntu-vg/ubuntu-lv)
- `/dev/nvme0n1`: 232GB logical volume (108G used, 114G free)
- Intel/AMD CPU with integrated GPU for Jellyfin transcoding (`/dev/dri`)

## Users

| User | Purpose |
|------|---------|
| root | System admin |
| user | Primary user |
| pterodactyl | Pterodactyl game panel (not currently active) |

## Docker Swarm Role: Manager

Swarm node ID: `jk3q2mq44crn6g615o7b5au64`
Engine version: 29.6.1

Holds the keepalived VIP `192.168.50.99` (priority 150). It previously held the swarm **Leader** role, but as of 2026-09-21 **heavensfeel is Leader** — leadership is an elected Raft role and moves independently of the VIP.

### Swarm Containers on this node (global services)

| Container | Stack | Purpose |
|-----------|-------|---------|
| Traefik | traefik | Reverse proxy replica (ports 80, 443) |
| AdGuard Home | base-services | DNS filtering (global mode) |
| node-exporter | base-services | System metrics for Prometheus |
| promtail | base-services | Log shipping to Loki |
| cadvisor | base-services | Container metrics for Prometheus |
| portainer-agent | portainer-agent | Docker management agent (port 9001) |

### Standalone Containers (non-swarm)

| Container | Purpose |
|-----------|---------|
| Jellyfin | Media streaming server (GPU transcoding), `jellyfin.example.com` |
| foundryvtt | Virtual tabletop (D&D), `foundry.example.com` |
| job-ops | Job application automation, `jobs.example.com` |
| masqueradarr + mongo-masq | IPTV aggregator, `iptv.example.com` |
| Immich_server | Photo management |
| immich_machine_learning | ML face/object recognition |
| immich_postgres | PostgreSQL for Immich |
| immich_redis | Redis cache for Immich |
| Vocard | Discord music bot |
| vocard-dashboard | Vocard web dashboard |
| vocard-db | MongoDB for Vocard |
| lavalink | Audio streaming node for Vocard |
| spotify-tokener | Spotify token service for Vocard |
| yt-cipher | YouTube cipher resolver for Vocard |
| portainer | Docker management UI (ports 9443) |
| docker-proxy | Read-only Docker API for Homepage |
| glances | System monitoring for Homepage |

> **Moved off this node:** jellyseerr, termix, qui (→ heavensfeel); slskd, komga (→ milis-wonderspace). Kavita decommissioned 2026-05-08.

## Storage

- `/mnt/network` mounted via NFS from milis-wonderspace (192.168.50.115)
- `/mnt/remote-storage/Photos/immich` for Immich photo library
- Local SSD only for OS, Docker volumes, and databases

## Remote Storage Mounts

```
192.168.50.115:/mnt/network → /mnt/network (NFS, hard,bg)
```

> Changed from `soft,automount` to `hard,bg` on 2026-05-16. See Storage Overview.

## Network Fixes (2026-05-16)

- **Jellyseerr 502**: Container was on default `bridge` network, not `traefik-public`.
  Traefik couldn't resolve `jellyseerr:5055`. Connected to `traefik-public` with DNS alias.
  ```bash
  docker network connect --alias jellyseerr traefik-public jellyserr
  ```

## Compose File Locations

All swarm stacks are defined on this node:
- `/home/user/docker/Stacks/` - Primary swarm stacks (adguard, infra, media, apps, networking, bots)
- `/home/user/docker/Compose/milkymiracle.yml` - Local compose (dev/historical)
- `/home/user/docker/apps.yml` - Apps stack (older version)
- `/home/user/docker/media.yml` - Media stack (older version)

Standalone compose projects:
- `/home/user/immich-app/docker-compose.yml`
- `/home/user/vocard/docker-compose.yml`
- `/home/user/job-ops/docker-compose.yml`
- `/home/user/Portfolio/docker-compose.yml` (standalone) + `docker-stack.yml` (swarm)

## Data Directories

```
/DATA/
├── Apps/       → App configs (actual, asf, camofox, foundry, masqueradarr, n8n, vaultwarden)
├── Arr/        → Arr stack configs (bazarr, lidarr, prowlarr, radarr, sonarr, tunarr, kapowarr)
├── Media/      → Media app configs (Jellyfin, Navidrome, Komga, Kavita, slskd, Mylar)
└── Net/        → Network app configs (adguard, gluetun, qBittorrent, termix)
```

## Issues / Notes

- **Ansible-managed (2026-08-15):** `compose/milkymiracle.yml` (repo → `/home/user/docker/compose/`) and `/etc/traefik/dynamic/{standalone,dynamic}.yml` are converged by `ansible/playbooks/deploy.yml`. See ansible.
- swap is unused (good)
- No crontabs configured
- Pterodactyl user exists but no active game servers found
- Tailscale DNS health check warning (same as milis-wonderspace)
- Runs the live compose at `/home/user/docker/compose/milkymiracle.yml` — includes `masqueradarr` + `mongo-masq` (the repo copy was updated to match)
