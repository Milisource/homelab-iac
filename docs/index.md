# Homelab Wiki

A public knowledge base for a **three-node Docker Swarm cluster** running Ubuntu 24.04.
Services are deployed as code — [Docker Compose](https://github.com/Milisource/homelab-iac/tree/main/compose)
for standalone apps and `docker stack deploy` for swarm services.

> This wiki is the documentation companion to the [homelab-iac](https://github.com/Milisource/homelab-iac)
> repository. Every doc here maps to real infrastructure in that repo.
>
> Use the **search bar** (top right) to find answers — everything on this site is
> full-text searchable.

---

## Quick Answers

| Question | Answer |
|----------|--------|
| How does traffic get from the internet to a service? | Cloudflare → router → VIP → Traefik. See [Architecture](architecture/overview.md) and [Traefik](services/traefik.md) |
| What happens if a node goes down? | Keepalived moves the VIP to a healthy node within seconds. See [Keepalived](services/keepalived.md) |
| Where does all the data live? | A 29TB mergerFS pool on milis-wonderspace, exported over NFS. See [Storage](storage/overview.md) |
| How is the network laid out? | LAN, Tailscale, and Docker overlay networks. See [Network Topology](network/topology.md) |
| How is the cluster monitored? | Prometheus + Loki + Grafana on heavensfeel. See [Monitoring](monitoring/README.md) |
| How is the cluster protected from attackers? | CrowdSec WAF + firewall bouncer. See [CrowdSec](services/crowdsec.md) |
| What are the hardware specs of each node? | See the [Servers](servers/milkymiracle.md) pages |
| How do downloads flow from indexer to playback? | Prowlarr → *Arr → download client → media apps. See [Media Pipeline](flows/media-pipeline.md) |

---

## Servers

| Node | IP | Role | Key Services |
|------|----|------|--------------|
| [milkymiracle](servers/milkymiracle.md) | 192.168.50.122 | Compute, Media, Proxy | Traefik, Jellyfin, CrowdSec LAPI |
| [milis-wonderspace](servers/milis-wonderspace.md) | 192.168.50.115 | Storage, Downloads | mergerFS, NFS, *Arr suite |
| [heavensfeel](servers/heavensfeel.md) | 192.168.50.129 | Monitoring, Automation | Grafana, Prometheus, n8n, SearXNG |

---

## Documentation

### [Architecture](architecture/overview.md)
Traffic flow, VIP failover, and how the pieces fit together.

### [Network](network/topology.md)
Subnets, Docker overlay networks, and the DNS chain (AdGuard → Unbound → Cloudflare DoT).

### [Monitoring](monitoring/README.md)
Metrics, logs, and dashboards: node_exporter, cAdvisor, Promtail, Prometheus, Loki, Grafana.

### [Storage](storage/overview.md)
Physical layout, mergerFS pool, and NFS exports.
See also the [USB migration deep-dive](storage/usb-migration.md) — why the pool lives on USB.

### [Servers](servers/milkymiracle.md)
Per-node hardware specs, roles, and service inventories.

### [Services](services/traefik.md)
Deep-dives on the core services: Traefik, CrowdSec, Keepalived, AdGuard Home, Vaultwarden.

### [Flows](flows/media-pipeline.md)
End-to-end pipelines like download → playback.

---

## Infrastructure as Code

Everything documented here is defined as code in the [repository](https://github.com/Milisource/homelab-iac):

| Path | Contents |
|------|----------|
| [`compose/`](https://github.com/Milisource/homelab-iac/tree/main/compose) | Per-node compose files, swarm stacks, standalone apps |
| [`traefik/dynamic/`](https://github.com/Milisource/homelab-iac/tree/main/traefik/dynamic) | Router, middleware, and dashboard configs |
| [`monitoring/`](https://github.com/Milisource/homelab-iac/tree/main/monitoring) | Prometheus, Promtail, Grafana provisioning |
| [`network/`](https://github.com/Milisource/homelab-iac/tree/main/network) | Keepalived VRRP configs |
| [`scripts/`](https://github.com/Milisource/homelab-iac/tree/main/scripts) | Operational scripts (SMART health, stale mount recovery) |

Secrets and personal identifiers are **not** in this repository — all configs use
environment-variable placeholders. See `.env.example` for the required variables.
