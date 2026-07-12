# Homelab IaC Repo — Build Plan

## Status: Phase 2 Complete ✅

All scaffolding is built. The repo contains sanitized compose files, Traefik configs,
monitoring dashboards, scripts, and architecture docs ready for publication.

---

## Current State

| Section | Files | Status |
|---------|-------|--------|
| `compose/nodes/` | `milis-wonderspace.yml`, `milkymiracle.yml`, `heavensfeel.yml` | ✅ Sanitized, env-var-ized |
| `compose/stacks/` | `traefik-stack.yml`, `infra.yml`, `cockpit-stack.yml` | ✅ Clean |
| `compose/apps/` | `job-ops.yml`, `searxng.yml`, `searxng-settings.yml` | ✅ Clean |
| `traefik/dynamic/` | `standalone.yml`, `dynamic.yml`, `dashboard.yml` | ✅ Clean, domains → `example.com` |
| `monitoring/dashboards/` | `homelab-overview.json`, `homelab-drilldown.json` | ✅ Generic placeholders |
| `scripts/` | 7 scripts | ✅ Sanitized |
| `docs/` | architecture, network, monitoring, storage | ✅ Adapted from source |
| `README.md` | Full repo README | ✅ Written |
| `.env.example` | All required variables | ✅ Written |

### What's Sanitized

| Pattern | Replaced With | Rationale |
|---------|---------------|-----------|
| `milisource.org` | `example.com` | Real registered domain |
| `*.milisource.org` | `*.example.com` | Same |
| `192.168.50.x` | Kept as-is | RFC1918 private range, architecture-relevant |
| `/home/mili/` | `/home/user/` or env vars | Personal home path |
| API keys / tokens | `${VARIABLE}` placeholders | Sensitive credentials |
| `mili` (username) | `user` or env vars | Personal identifier |

### What Still Needs Work Before Publication

| Item | Effort | Priority | Notes |
|------|--------|----------|-------|
| GitHub repo description + topics | 5 min | When publishing | e.g., "homelab", "docker-swarm", "infrastructure-as-code" |
| Link to incident postmortems | 1 min | Before publish | Reference companion repo in README |

### Phase 3: Publish

1. Create GitHub repo under `Milisource/homelab-iac`
2. Push clean history (no `.env` or secrets in history)
3. Set topics: `homelab`, `docker-swarm`, `infrastructure-as-code`, `traefik`, `selfhosted`
4. Add badge: GitHub Actions, License

---

## Architecture Reference

### Node Mapping

| Hostname | Alias | IP | Role |
|----------|-------|----|------|
| milis-wonderspace | server | 192.168.50.115 | Storage + Downloads + AI |
| milkymiracle | eserver | 192.168.50.122 | Media + Compute + Proxy |
| heavensfeel | hserver | 192.168.50.129 | Monitoring + Automation |

### Traffic Flow

```
Internet → Cloudflare DNS → Router (80/443) → VIP 192.168.50.99
                                                  │
                                            keepalived failover
                                                  │
                                             Traefik (x2)
                                            /            \
                                CrowdSec Bouncer    Docker overlay
                                (forwardAuth)       (traefik-public)
                                        │                 │
                                  Blocked/Allowed     ┌────┴────┐
                                                      │         │
                                                  Internal    VPN gateway
                                                  services    Download client
```

### DNS Chain

```
Client → VIP:53 → AdGuard Home → Unbound → Cloudflare DoT
```

### Storage

```
5x USB HDD → mergerFS (JBOD, no parity) → /mnt/network (29TB)
                                                 │
                                          NFS export → milkymiracle
                                                 │
                                         Borgmatic backups (daily)
```

---

## File Inventory

### Compose Files

| File | Source | Services |
|------|--------|----------|
| `compose/nodes/milis-wonderspace.yml` | `milis-wonderspace.yml` (390 lines) | VPN gateway, Download client, *Arr suite, Navidrome, Komga, Open WebUI, slskd, CopyParty, Borgmatic |
| `compose/nodes/milkymiracle.yml` | `milkymiracle.yml` | Jellyfin, FoundryVTT, Vocard suite, Job-ops |
| `compose/nodes/heavensfeel.yml` | `heavensfeel.yml` | Grafana, Prometheus, Loki, Vaultwarden, n8n, Uptime Kuma, Change Detection, Homepage, SearXNG, Hermes |
| `compose/stacks/traefik-stack.yml` | `traefik-stack.yml` | Traefik (2 replicas) |
| `compose/stacks/infra.yml` | `infra.yml` | CrowdSec Traefik bouncer |
| `compose/stacks/cockpit-stack.yml` | `cockpit-stack.yml` | Cockpit (global) |
| `compose/apps/job-ops.yml` | `job-ops.yml` | Job-ops standalone |
| `compose/apps/searxng.yml` + `searxng-settings.yml` | `searxng.yml` | SearXNG search engine |

### Scripts

| File | Purpose | Notes |
|------|---------|-------|
| `smart-health-check.sh` | Weekly SMART checks | Inactive — needs cron setup |
| `cleanup-stale-mounts.sh` | Force-unmount stale USB devices | Manual only |
| `detect-stale-network.sh` | Auto-recover stale NFS/FUSE mounts | Runs as systemd timer |
| `detect-stale-network.service` | systemd unit for above | Needs user setup |
| `detect-stale-network.timer` | 10-minute timer for above | Needs user setup |
| `searxng-entrypoint.sh` | Bangs injection at SearXNG start | Auto-runs in container |
| `merge-homelab-bangs.py` | Custom search bangs builder | Called by entrypoint |

### Traefik Dynamic Configs

| File | Contents |
|------|----------|
| `traefik/dynamic/standalone.yml` | All service routers and backends (258 lines) |
| `traefik/dynamic/dynamic.yml` | Shared middleware (secure-headers, crowdsec, rate-limit) |
| `traefik/dynamic/dashboard.yml` | Dashboard router + basic auth |

### Monitoring

| File | Contents |
|------|----------|
| `monitoring/dashboards/homelab-overview.json` | 9-panel system dashboard |
| `monitoring/dashboards/homelab-drilldown.json` | Per-container drilldown |

### Docs

| File | Source Adaptation |
|------|-------------------|
| `docs/architecture/overview.md` | Compendium architecture doc |
| `docs/network/topology.md` | Subnets, Docker networks, DNS chain, firewall |
| `docs/monitoring/README.md` | Prometheus, Loki, Grafana deployment notes |
| `docs/storage/overview.md` | Storage architecture (not yet copied) |

---

## Remaining Gaps (pre-publish)

### ✅ Completed in Phase 2

**Live configs extracted:**
- `traefik/traefik.yml` — Static config (sanitized: email → `${ACME_EMAIL}`)
- `monitoring/prometheus/prometheus.yml` — Scrape config
- `monitoring/promtail/promtail.yml` — Log shipping config
- `monitoring/grafana/provisioning/datasources/datasources.yaml` — Datasource provisioning
- `monitoring/grafana/provisioning/dashboards/dashboards.yaml` — Dashboard provider
- `network/keepalived/keepalived-eserver.conf` — Primary node config (sanitized: auth_pass → placeholder)
- `network/keepalived/keepalived-server.conf` — Backup node config
- `network/keepalived/check_dns.sh` — DNS health check script

**Service docs (sanitized from Compendium):**
- `docs/services/traefik.md`
- `docs/services/crowdsec.md`
- `docs/services/keepalived.md`
- `docs/services/vaultwarden.md`
- `docs/services/adguard.md`
- `docs/services/hermes.md`

**Other:**
- ASCII diagrams → Mermaid flowcharts in README
- CI workflows: `.github/workflows/lint.yml`, `.github/workflows/validate-compose.yml`
- MIT License
- `.yamllint` config
- `.env.example` updated with new variables (`ACME_EMAIL`, `KEEPALIVED_AUTH_PASS`)
