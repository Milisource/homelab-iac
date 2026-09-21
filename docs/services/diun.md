# Diun

**Host**: heavensfeel | **Type**: Docker image update notifier | **Domain**: none (Telegram-only)

## Overview

[Diun](https://github.com/crazy-max/diun) watches running Docker images and notifies via Telegram when a newer tag/digest is published upstream. Deployed as **three instances on heavensfeel**, one per node — Diun's docker provider supports only **one endpoint per instance** (verified against v4.33 source; `DIUN_PROVIDERS_DOCKER_HOSTS` does not exist, maintainer-recommended setup is one instance per host).

Each instance connects to its node's read-only **docker-proxy** (port 2376, tecnativa/docker-socket-proxy with `CONTAINERS=1` + `IMAGES=1`), so no docker.sock is mounted.

## Instances

| Instance | Watches | Endpoint | Data dir |
|----------|---------|----------|----------|
| `diun` | heavensfeel (129) | `tcp://192.168.50.129:2376` | `/DATA/Apps/diun/data` |
| `diun-milkymiracle` | milkymiracle (122) | `tcp://192.168.50.122:2376` | `/DATA/Apps/diun/data-milkymiracle` |
| `diun-wonderspace` | milis-wonderspace (115) | `tcp://192.168.50.115:2376` | `/DATA/Apps/diun/data-wonderspace` |

## Configuration

All config via env vars in `compose/heavensfeel.yml` (no config file):

| Setting | Value |
|---------|-------|
| Schedule | `0 */6 * * *` (every 6h) + 30s jitter |
| Workers | 20 |
| Watch mode | `watchByDefault: true` (all containers, no labels needed) |
| Notification | Telegram — token + chatID from `/home/user/docker/compose/.env` (`DIUN_TELEGRAM_TOKEN`, `DIUN_TELEGRAM_CHATID`; token reused from Hermes, chatID from `TELEGRAM_ALLOWED_USERS`) |
| Image | `crazymax/diun:latest` |
| Compose file | `/home/user/docker/compose/heavensfeel.yml` |

## Notes

- First scan indexed 28 (heavensfeel) / 23 (milkymiracle) / 20 (wonderspace) images. Locally-built images (`5etools:local`, `camofox-browser:local`) can't be registry-checked and log a failure each scan — expected.
- First-run "new image" notifications for every image can be chat noise; tune with the `diun.notify_on` label per container if needed.
- Telegram test notification verified working (2026-08-15).

## Enabling IMAGES on docker-proxy

Diun needs read-only `/images/*` access. All 3 nodes' `docker-proxy` env now includes `IMAGES: 1` (alongside `CONTAINERS: 1`, `POST: 0`) in the per-node compose files.
