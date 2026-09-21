# heavensfeel

**IP**: 192.168.50.129 | **Role**: Monitoring, Automation
**OS**: Ubuntu 24.04 LTS | **CPU**: Intel N95 (4 cores) | **RAM**: 16GB

## Hardware

Intel N95 (Alder Lake-N) mini PC. 512GB NVMe SSD, dual HDMI, USB 3.2.

## Role

Swarm manager node providing quorum — and the cluster's **current leader** (an elected Raft role; leadership can move between the three managers). Runs the monitoring stack and automation services.

## Services

| Service | Type | Purpose |
|---------|------|---------|
| Grafana | Docker | Metrics dashboards |
| Prometheus | Docker | Metrics collection (node, docker, cAdvisor) |
| Loki | Docker | Log aggregation |
| Promtail | Global | Log shipping to Loki |
| Vaultwarden | Docker | Password manager |
| n8n | Docker | Workflow automation |
| Uptime Kuma | Docker | Uptime monitoring |
| Change Detection | Docker | Website change monitoring |
| SearXNG | Docker | Private search engine |
| Homepage | Docker | Service dashboard |
| ArchiSteamFarm | Docker | Steam idle/card farming |
| redlib-instances | Docker | Static Redlib instance list for the ASF free-games plugin (internal only) |
| Fabula | Docker | Static campaign-log site |
| Hermes | Systemd | AI agent gateway + dashboard |

## Storage

`/mnt/network` mounted via NFS from milis-wonderspace. All monitoring data
stored on local SSD or NFS.
