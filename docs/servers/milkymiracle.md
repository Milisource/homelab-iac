# milkymiracle

**IP**: 192.168.50.122 | **Role**: Compute, Media, Proxy
**OS**: Ubuntu 24.04 LTS | **CPU**: 6 cores | **RAM**: 16GB

## Hardware

Single NVMe SSD (256GB). Integrated GPU for Jellyfin hardware transcoding (`/dev/dri`).

## Role

Swarm manager node and primary VIP holder. Runs Traefik reverse proxy, media
streaming with GPU transcoding, and compute-heavy services.

## Services

| Service | Type | Purpose |
|---------|------|---------|
| Traefik | Swarm | Reverse proxy (2 replicas, ports 80/443) |
| CrowdSec LAPI | Native | Centralized WAF decision server |
| Jellyfin | Docker | Media streaming (HW transcoded) |
| Immich | Standalone | Photo management (PostgreSQL, ML) |
| Foundry VTT | Docker | Self-hosted virtual tabletop |
| Vocard suite | Standalone | Discord music bot + dashboard |
| Job-ops | Docker | Job application automation |

## Storage

`/mnt/network` mounted via NFS from milis-wonderspace. No local storage beyond OS
and Docker volumes.
