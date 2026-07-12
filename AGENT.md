# Agent Instructions — Homelab IaC

Public Infrastructure-as-Code repo for a 3-node Docker Swarm homelab cluster.

## Structure

| Path | Contents |
|------|----------|
| `compose/nodes/` | Per-node compose files (milis-wonderspace, milkymiracle, heavensfeel) |
| `compose/stacks/` | Swarm stack files (traefik, infra, cockpit) |
| `compose/apps/` | Standalone apps (searxng, job-ops) |
| `traefik/dynamic/` | Traefik dynamic router/middleware configs |
| `monitoring/dashboards/` | Grafana dashboard JSON definitions |
| `scripts/` | Operational scripts (SMART health, stale mount recovery, etc.) |
| `docs/` | Architecture, network, monitoring, storage, servers, services, flows docs |

## Sanitization Rules

- **Domains**: `example.com` — do NOT use `milisource.org`
- **IPs**: Keep `192.168.50.x` (RFC1918) — these are architecture-relevant
- **Secrets**: Always use `${VARIABLE}` placeholders, never hardcode
- **Paths**: Use `/home/user/` instead of `/home/mili/`
- **Usernames**: Use `user` instead of `mili`

## Key Decisions (documented in README)

- Docker Swarm over K8s (simpler for 3-node cluster)
- Traefik over nginx/caddy (Docker + Swarm provider support)
- NFS over Ceph/GlusterFS (3 nodes don't need distributed storage)
- mergerFS over ZFS (JBOD with no parity — content is replaceable)

## Before Publishing

1. Extract live configs: traefik static config, prometheus.yml, keepalived.conf
2. Add service docs from `Homelab/services/` in the Compendium
3. Add CI (YAML lint + compose validation)
4. Verify zero secrets in git history

## Source of Truth

Live infrastructure docs are at `~/Documents/The Compendium/Homelab/`. This repo is a
sanitized public subset. If adding new files, write both the sanitized public version
and update the internal docs.
