# Docker Swarm

## Overview

Three-node Docker Swarm (all three are managers — quorum of 3). **heavensfeel is the current leader** (moved from milkymiracle; leadership is an elected Raft role that can move on failover/restart, so treat it as dynamic). Engine 29.6.1 on all nodes. Most services run as standalone `docker compose` per-node; a small set of infrastructure runs as true swarm services (global agents + Traefik).

## Nodes

| Node | ID | Status | Availability | Role | Engine |
|------|-----|--------|-------------|------|--------|
| milkymiracle | jk3q2mq44crn6g615o7b5au64 | Ready | Active | Reachable | 29.6.1 |
| heavensfeel | ioppn3f65e52ysahdv5pe3p1j | Ready | Active | **Leader** | 29.6.1 |
| milis-wonderspace | p7vzxudv7blxvpa6dje4ocusw | Ready | Active | Reachable | 29.6.1 |

Node label on all three: `traefik=true` (places a Traefik replica on each node).

## Deployment Model

Most services are deployed via **standalone `docker compose`** per node. The per-node compose files live at `/home/user/docker/compose/` on every machine and are **converged from this repo by Ansible** (`ansible/playbooks/deploy.yml` syncs `compose/<node>.yml` + Traefik dynamic configs, then `docker compose up -d`). Manual edits on nodes get healed back to the repo on the next deploy.

| Compose File | Deploys On | Services |
|-------------|------------|----------|
| `milis-wonderspace.yml` | server (115) | *Arr stack, Navidrome, Komga, Gluetun/qBittorrent, slskd, CopyParty, ArchiveBox, Borgmatic |
| `heavensfeel.yml` | hserver (129) | Vaultwarden, ASF, Byparr, n8n, Jellyseerr, Qui, Termix, Homepage, Camofox, SearXNG, 5etools, Uptime Kuma, Prometheus, Grafana, Loki, Change Detection, Diun ×3, FreshRSS |
| `milkymiracle.yml` | eserver (122) | Jellyfin, FoundryVTT, Masqueradarr (IPTV), Glances, Docker-proxy |
| `job-ops.yml` | eserver (122) | Job-ops automation |
| `searxng.yml` | hserver (129) | SearXNG + Valkey redis (also in heavensfeel.yml) |

## Active Swarm Services

| Stack | Service | Mode | Replicas | Port |
|-------|---------|------|----------|------|
| `traefik` | traefik | replicated | 3/3 | 80, 443 |
| `portainer-agent` | agent | global | 3/3 | 9001 |
| `base-services` | adguard | global | 3/3 | 53, 67, 80, 443, 853 |
| `base-services` | node-exporter | global | 3/3 | 9100 |
| `base-services` | promtail | global | 3/3 | — |
| `base-services` | cadvisor | global | 3/3 | 9300 |

## Docker Networks

| Network | Driver | Notes |
|---------|--------|-------|
| traefik-overlay | overlay | attachable — cross-node container DNS for all services; replaced bridge `traefik-public` 2026-05-27 |
| traefik-public | overlay | attachable — legacy network; still present but most services moved to `traefik-overlay` |
| base-services_default | overlay | internal for the base-services stack |
| portainer-agent_agent_network | overlay | attachable — for agent communication |
| ingress | overlay | Swarm default routing mesh |

## Docker Secrets

| Secret | Used By |
|--------|---------|
| cf_dns_api_token | Traefik (Let's Encrypt DNS challenge) |
| openvpn_user | Gluetun |
| openvpn_password | Gluetun |

(Other secrets formerly documented were migrated to env vars / `.env` files in the standalone compose model.)

## Service Placement

| Node | Workload |
|------|----------|
| **milis-wonderspace** (115) | Storage, *Arr, VPN/downloads, media serving (Navidrome, Komga, slskd), web archiving (ArchiveBox), backups (borgmatic) |
| **milkymiracle** (122) | Jellyfin (GPU), FoundryVTT, Job-ops, Masqueradarr (IPTV), Vocard, Immich, Portainer |
| **heavensfeel** (129) | Monitoring hub (Prometheus/Grafana/Loki/Uptime Kuma), automation (n8n), Vaultwarden, SearXNG, always-on daemons (ASF, free-games-claimer) |

## Access

- **Portainer UI**: https://192.168.50.122:9443
- **Traefik Dashboard**: http://192.168.50.122:8080 (secured)
- **CLI**: `ssh eserver` (or `hserver`, `server`) and use `docker compose`
