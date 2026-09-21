# Immich (Photo Management)

**Host**: milkymiracle | **Port**: 2283 | **Domain**: [immich.example.com](https://immich.example.com)

> Now behind Traefik (router added to `infra/traefik/dynamic/standalone.yml`). Previously direct-port only.

## Overview

Immich is a self-hosted photo and video backup solution, similar to Google Photos. Runs as a standalone docker-compose (not in the swarm).

## Services

| Container | Image | Purpose |
|-----------|-------|---------|
| immich_server | ghcr.io/immich-app/immich-server:v3 | Main app server |
| immich_machine_learning | ghcr.io/immich-app/immich-machine-learning:v3 | ML inference (face/object recognition) |
| immich_postgres | ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0 | PostgreSQL with pgvector |
| immich_redis | valkey/valkey:9 | Cache/queue |

## Storage

| Purpose | Location |
|---------|----------|
| Uploads | /mnt/network/Photos/immich (NFS → milis-wonderspace mergerfs) |
| Database | ./postgres/ (local) |
| ML model cache | Docker volume `model-cache` |

## Network

- Port: 2283 (published)
- DNS: 192.168.50.122 (milkymiracle/AdGuard), 1.1.1.1 (fallback)
- Traefik route: `immich.example.com` → `http://immich_server:2283` (TLS via LE)

## Security

- Database password in .env file
- TLS termination at Traefik

## Data Layout

```
/mnt/network/Photos/immich/           (NFS → milis-wonderspace:mergerfs)
├── <user>/                           (per-user upload directories)
├── library/
├── thumbs/
├── upload/
├── profile/
├── encoded-video/
└── backups/

/home/user/immich-app/
├── docker-compose.yml
├── .env              (DB password, paths, etc.)
└── postgres/         (database files)
```

## Improvements

- No automated backup strategy for photos
- Upload location is on NFS mount (potential performance consideration)
- Data lives on milis-wonderspace's mergerfs pool, served via NFS to milkymiracle
