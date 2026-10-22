# Home Assistant

**Host**: heavensfeel | **Port**: 8123 | **Domain**: `ha.example.com` — **internal only**
**Image**: `ghcr.io/home-assistant/home-assistant:stable`
**Compose**: `compose/nodes/heavensfeel.yml` → `homeassistant` (Ansible-managed)
**Router**: `homeassistant` in `traefik/dynamic/standalone.yml` — no Cloudflare record, no rate-limit

## Overview

One dashboard for the cameras, the robot vacuum, TV routines, presence and the cluster itself.
Some of it is cloud-dependent and some is local — the distinction matters:

| Integration | Transport | Notes |
|---|---|---|
| Cameras (Blink) | **cloud** | HA logs in as the mobile app does; Amazon can break it (it did in July 2026) |
| Robot vacuum (Tuya) | **local** | Tuya protocol 3.4 via `tuya_local`; no cloud round-trip |
| Voice Assist | **local** | [wyoming-whisper + piper](voice.md) on the same node |
| Photos (Immich) | LAN | API key against `milkymiracle:2283` — see [Immich](immich.md) |
| DNS (AdGuard) | LAN | dedicated user on all three instances — see [AdGuard](adguard.md) |
| Metrics | LAN | Prometheus scrapes `/api/prometheus` (bearer token) |

> **Blink is still cloud-dependent.** This is the one integration that can fail without anything
> on the homelab changing.

## Why no host networking

Most Home Assistant guides use `network_mode: host` for mDNS/SSDP discovery. Nothing here needs
it: the cameras are cloud-only and the vacuum is addressed by a fixed IP. Overlay containers egress
through `docker_gwbridge` NAT, so outbound LAN traffic works. Staying on `traefik-overlay` keeps
normal Traefik-by-container-name routing and avoids host-network surprises.

Because Traefik's requests arrive from the overlay, `configuration.yaml` must trust the overlay
subnet (`docker network inspect traefik-overlay`). **If that subnet ever changes, every proxied
request returns 400.**

## Storage and backups

| Path | Purpose |
|---|---|
| `/DATA/Apps/homeassistant` → `/config` | Config, database, integrations |
| `/DATA/Cameras/blink` → `/media/blink` | Camera clips (pulled off Amazon's servers) |

Borg covers `/DATA/Apps`, **except** `home-assistant_v2.db*` — recorder history is excluded from
both heavensfeel backup configs. Clips sit outside `/DATA/Apps` on purpose, so they stay out of the
off-site box; they are rsynced nightly to the pool and never pruned.

## Cluster integration

The dashboard is also the cluster's status board: per-node CPU/RAM power, wall-power estimate,
storage headroom and service health. That depends on:

- `node_exporter` running as **root** so the `rapl` collector can read
  `/sys/class/powercap/*/energy_uj` (mode `0400 root` since the PLATYPUS fix). See
  [Monitoring](../monitoring/README.md).
- The HA Prometheus exporter, scraped by the Prometheus stack.
- Uptime checks that authenticate rather than probing anonymous endpoints — see the
  [CopyParty](copyparty.md) note.

The Steam Deck is counted as a node in the power estimate but is **not** a Swarm member; see
[Steam Deck](../servers/steamdeck.md).
