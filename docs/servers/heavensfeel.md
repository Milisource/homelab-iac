# heavensfeel (hserver)

**IP**: 192.168.50.129 | **Tailscale**: 100.x.x.x
**OS**: Ubuntu 24.04 LTS | **CPU**: Intel N95 (4 cores, up to 3.4GHz)
**RAM**: 15GB | **Swap**: 4GB (0 used)
**Disk**: 512GB SSD — ~98GB LVM in use, ~400GB free
**Docker Engine**: 29.6.1

## Role: Swarm Manager Node (Quorum)

Lightweight control plane node providing Docker Swarm quorum. Previously the League of Legends machine; repurposed as the third swarm manager for fault tolerance.

## Hardware

- Intel N95 (Alder Lake-N, 4 cores, 4 threads)
- 16GB DDR4 RAM
- 512GB M.2 NVMe SSD (LVM: ubuntu-vg/ubuntu-lv)
- Dual HDMI, USB 3.2, BT 5.1, dual-band WiFi

## Users

| User | Purpose |
|------|---------|
| root | System admin |
| user | Primary user |

## Setup

- **Docker**: 29.6.1 (with docker-compose-plugin)
- **Tailscale**: Connected, direct links to both milis-wonderspace and milkymiracle
- **NFS mounts**: `/mnt/network` and `/DATA` from milis-wonderspace via fstab (hard,bg)

## Docker Swarm Role: Manager

Swarm node ID: `ioppn3f65e52ysahdv5pe3p1j`
Engine version: 29.6.1

One of 3 manager nodes, and **currently Leader** (as of 2026-09-21 — leadership moved here from milkymiracle; it is an elected Raft role, not a fixed assignment). Provides quorum for the 3-node swarm — the cluster can survive the loss of any single manager node.

### Node Labels

| Label | Value |
|-------|-------|
| traefik | true |

`traefik=true` places a Traefik replica on this node (replicated 3/3, one per node).

## Active Services

| Service | Type | Port | Details |
|---------|------|------|---------|
| Hermes | Systemd user | :9119 | AI agent gateway + dashboard, Telegram-connected |
| Camofox | Docker standalone | :9377, :6080 | Stealth browser backend for Hermes |
| vaultwarden | Docker standalone | :80 (internal) | Password manager, `vault.example.com` |
| n8n | Docker standalone | :5678 | Workflow automation, `n8n.example.com` |
| archisteamfarm | Docker standalone | :1242 | Steam card farming, `asf.example.com` |
| redlib-instances | Docker standalone | :8192 | Static Redlib instance list for the ASF free-games plugin (internal only). Own compose project — see other-services |
| jellyseerr | Docker standalone | :5055 | Media request UI, `serr.example.com` |
| homepage | Docker standalone | :3000 | Dashboard (`home.example.com`) |
| qui | Docker standalone | :7476 | Torrent IRC autodownload (autobrr), `qui.example.com` |
| byparr | Docker standalone | :8191 | Captcha proxy for Prowlarr |
| free-games-claimer | Docker standalone | :7080 | Free games auto-claimer (Epic, Steam, Prime, GOG). Panel: `claims.example.com` |
| diun ×3 | Docker standalone | — | Image update notifier, one instance per node via docker-proxy, Telegram (diun) |
| borg-repo | Docker standalone | — | Borg repo host for milis-wonderspace backups (`/home/user/borg-repos` → `/repos`, idle container serving `borg serve` via restricted ssh forced command) |
| freshrss | Docker standalone | :80 (internal) | RSS reader, `rss.example.com` |
| termix | Docker standalone | :5600 | Terminal sharing, `termix.example.com` |
| searxng | Docker standalone | :8080 (internal) | Metasearch engine, `search.example.com` |
| searxng-redis | Docker standalone | — | Valkey cache for searxng |
| 5etools | Docker standalone | :80 (internal) | Self-hosted D&D reference, `5etools.example.com` |
| fabula | Docker standalone | :80 (internal) | Static Fabula Ultima campaign log, `fabula.example.com` |
| changedetection | Docker standalone | :5000 | Website change monitor, `watch.example.com` |
| uptime-kuma | Docker standalone | :3001 | Service monitoring, `status.example.com` |
| prometheus | Docker standalone | :9090 | Metrics collection (all 3 nodes scraped) |
| grafana | Docker standalone | :3002→3000 | Dashboards, `grafana.example.com` |
| loki | Docker standalone | :3100 | Log aggregation |
| glances | Docker standalone | — | System monitoring for Homepage |
| docker-proxy | Docker standalone | :2376 | Read-only Docker API for Homepage |
| Traefik (swarm) | Swarm global | :80, :443 | Reverse proxy replica (traefik=true label) |
| AdGuard Home (swarm) | Swarm global | :53, :5335 | DNS + ad blocking |
| node-exporter (swarm) | Swarm global | :9100 | System metrics for Prometheus |
| promtail (swarm) | Swarm global | — | Log shipping to Loki |
| cadvisor (swarm) | Swarm global | :9300 | Container metrics for Prometheus |
| portainer-agent (swarm) | Swarm global | :9001 | Docker management agent |
| Cockpit | Native systemd | :9091 | Web-based server management (per-node) |

**Networks:** `traefik-overlay` (external overlay) — all app containers + Traefik connected here for cross-node Docker DNS resolution.

All services deployed via `docker compose -f heavensfeel.yml up -d` from `/home/user/docker/compose/`.

## Notes

- **Ansible-managed (2026-08-15):** `compose/milis-wonderspace.yml` (repo → `/home/user/docker/compose/`) and `/etc/traefik/dynamic/{standalone,dynamic}.yml` are converged by `ansible/playbooks/deploy.yml` — hand-edits get healed on the next deploy. See ansible.
- Runs the monitoring hub (Prometheus/Grafana/Loki/Uptime Kuma) plus the AI stack (Hermes, Camofox, n8n) — no longer idle standby
- 400GB free on root — plenty for Docker volumes, logs, and lightweight services
- NFS mounts via `hard,bg` (changed from automount on 2026-05-16)
- No swap usage (good)
- **2026-05-24:** Hermes incident — agent autonomously damaged Traefik configs, keepalived, and truncated the compose file. All recovered. See Hermes.

## Network Notes

- **Realtek RTL8111/8168** ethernet controller — uses in-kernel `r8169` driver
- Original cable negotiated at only **100Mb/s** (broken twisted pair). Replaced 2026-05-16 → gigabit restored.
- If link drops inexplicably again, check cable first (known failure mode on this hardware).
