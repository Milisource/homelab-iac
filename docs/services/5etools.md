# 5etools

**Host**: heavensfeel | **Domain**: 5etools.example.com

## Overview

Self-hosted [5e.tools](https://5e.tools) — Dungeons & Dragons 5e reference site (SRD content). Static SPA served via lighttpd inside a Docker container, routed through Traefik.

## Configuration

| Setting | Value |
|---------|-------|
| Container | 5etools |
| Web server | lighttpd 1.4 |
| Port | 80 (internal, overlay network) |
| Image | `5etools:local` (built from source) |
| Build context | `/home/user/docker/build/5etools` |
| Compose file | `/home/user/docker/compose/heavensfeel.yml` |

## Build & Update

The repo is mirrored from `5etools-mirror-3/5etools-src`. 

### Auto-update

A cron job runs daily at midnight (`0 0 * * *`) via `/home/user/scripts/update-5etools.sh`. It fetches the upstream repo, checks for new commits, and if found, pulls, rebuilds the image, and restarts the container. Logs at `~/scripts/logs/5etools-update.log`.

### Manual update

```bash
cd /home/user/docker/build/5etools
git pull

cd /home/user/docker/compose
docker compose -f heavensfeel.yml build 5etools
docker compose -f heavensfeel.yml up -d 5etools
```

## Data

All data is bundled in the image at build time (no runtime volumes). The repo includes data from the 5e SRD. Updates require a rebuild.

## Route

Traefik router defined in `infra/traefik/dynamic/standalone.yml`:

- `5etools` — Host(`5etools.example.com`) → `http://5etools:80`
- No rate-limit (all static assets, no API endpoints)

