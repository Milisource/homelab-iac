# Grafana

Runs on **heavensfeel** as part of `compose/heavensfeel.yml`.

| Service | URL |
|---------|-----|
| Grafana | https://grafana.example.com |
| Prometheus | http://192.168.50.129:9090 (not routed via Traefik — direct port) |
| Loki | http://192.168.50.129:3100 (not routed via Traefik) |

## Scrape targets

Prometheus scrapes all 3 nodes for:
- **node_exporter** — system metrics (CPU, RAM, disk, network) via Swarm global service on port 9100
- **Docker engine metrics** — container state counts via `metrics-addr` (port 9323) in daemon.json on each node
- **cAdvisor** — per-container CPU/memory via Swarm global service (port 9300)
- **Promtail** — log shipping to Loki via Swarm global service

## Dashboard

The dashboard JSON is at `monitoring/dashboards/homelab-overview.json`.

Grafana auto-provisions Prometheus + Loki datasources from `/DATA/Apps/grafana/provisioning/`.
