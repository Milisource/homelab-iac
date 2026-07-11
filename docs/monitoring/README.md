> Adapted from internal documentation. Some details have been generalized for public reference.

# Monitoring Stack

## Architecture

Three-node Docker Swarm cluster, each node runs:

| Component | What it provides | Port |
|-----------|-----------------|------|
| `node_exporter` (Swarm global) | System metrics: CPU, RAM, disk, network | 9100 |
| Docker engine metrics (`daemon.json`) | Container state counts (running/stopped/paused) | 9323 |
| `cadvisor` (Swarm global) | Per-container CPU, memory, restart events | 9300 |
| `promtail` (Swarm global) | Reads container logs → pushes to Loki | — |

All data flows to **Prometheus** (metrics) and **Loki** (logs), both running on heavensfeel as standalone containers. **Grafana** reads from both.

## Grafana

| URL | Credentials |
|-----|-------------|
| https://grafana.example.com | admin / `${GRAFANA_ADMIN_PASSWORD}` |

Datasources are auto-provisioned from `/DATA/Apps/grafana/provisioning/`:
- **Prometheus** → `http://prometheus:9090`
- **Loki** → `http://loki:3100`

Dashboards are auto-provisioned from `monitoring/dashboards/*.json` in this repo.

### Dashboards

#### Homelab Overview (`homelab-overview.json`)

The main system dashboard. 9 panels:

| Row | Panels | What |
|-----|--------|------|
| 1 | CPU, Memory, Load (15m) | Per-node timeseries |
| 2 | Uptime, Nodes Online | Stat panels |
| 3 | Disk — Root, Disk by Mount, Net — Receive, Net — Transmit | Gauges + table + timeseries |

**Pattern used in every query:**
- Filter by `instance=~"$node"` (always reliable — `instance` is set by Prometheus)
- Exclude stale data with `hostname!=""` (filters out series from before labels were configured)
- Aggregate with `avg by(hostname)` or `sum by(hostname)` to collapse any duplicates into one value per node
- Legend uses `{{ hostname }}`

#### Homelab Drilldown (`homelab-drilldown.json`)

Experiment dashboard for advanced features:

- **Chained variables**: Node selector → Container selector (auto-populates from cAdvisor)
- **Annotations**: Red vertical markers on timeseries when a container restarts
- **Dashboard links**: Link button at top navigates between dashboards
- **Container tables**: Top 10 by CPU and Memory, filterable by container variable
- **Loki logs**: Log volume + recent errors stream

## Prometheus

Config at `monitoring/prometheus/prometheus.yml`.

### Scrape targets

```yaml
- job_name: node       # 192.168.50.115:9100, .122, .129
- job_name: docker-engine  # 192.168.50.115:9323, .122, .129
- job_name: cadvisor   # 192.168.50.115:9300, .122, .129
- job_name: prometheus # localhost:9090
```

### Hostname labels

Each target gets a `hostname` label via `static_configs.labels`:

```yaml
- targets: [192.168.50.115:9100]
  labels: { hostname: milis-wonderspace }
- targets: [192.168.50.122:9100]
  labels: { hostname: milkymiracle }
- targets: [192.168.50.129:9100]
  labels: { hostname: heavensfeel }
```

This label is used for friendly display names in dashboards.

## Infrastructure deployed

### Docker engine metrics

Added to `/etc/docker/daemon.json` on all 3 nodes:
```json
{ "metrics-addr": "0.0.0.0:9323" }
```

Applied by restarting Docker via nsenter:
```bash
docker run --rm --privileged --pid=host alpine \
  nsenter -t 1 -m -u -i -n -p -- systemctl restart docker
```

### cAdvisor

Deployed as a Swarm global service:
```bash
docker service create \
  --name base-services_cadvisor --mode global \
  --mount type=bind,source=/,target=/rootfs,ro \
  --mount type=bind,source=/var/run,target=/var/run,ro \
  --mount type=bind,source=/sys,target=/sys,ro \
  --mount type=bind,source=/var/lib/docker,target=/var/lib/docker,ro \
  --publish target=9300,published=9300,mode=host \
  -e CADVISOR_HEALTHCHECK_URL=http://localhost:9300/healthz \
  gcr.io/cadvisor/cadvisor:latest \
  --port=9300 --housekeeping_interval=30s \
  --disable_metrics=disk,network,tcp,udp,advtcp,sched,process,hugetlb,referenced_memory,resctrl,cpu_topology,memory_numa
```

Key: the `CADVISOR_HEALTHCHECK_URL` env var is required because cAdvisor's built-in healthcheck defaults to port 8080.

### Log shipping (Promtail)

Already deployed as a Swarm global service (`base-services_promtail`). Config at `monitoring/promtail/promtail.yml`. Reads `/var/lib/docker/containers/*/*-json.log` and pushes to `http://192.168.50.129:3100/loki/api/v1/push`.

### Grafana provisioning

Grafana auto-loads datasources and dashboards from `/DATA/Apps/grafana/provisioning/`:
- `datasources/datasources.yaml` — Prometheus + Loki
- `dashboards/dashboards.yaml` — file provider pointing at the same directory
- `dashboards/*.json` — the dashboard JSON files

## Lessons learned

### PromQL label matching

**`{hostname=~".*"}` matches series where `hostname` doesn't exist.** In PromQL, `=~ ".*"` matches the empty string, which is the value of a missing label. So filtering by `{hostname=~".*"}` includes ALL data, not just data with the label.

**Use `{hostname!=""}` to exclude series without the label.** `!= ""` rejects the empty/missing value, so only series where the label exists with a real value match.

### Hostname labels from containerized exporters

`node_uname_info.nodename` from a containerized node_exporter reports the **container's hostname** (a container ID), not the node's actual hostname. Don't use it for friendly names.

Instead, add `hostname` labels in the Prometheus scrape config via `static_configs.labels`. Per-target labels reliably propagate to all metrics from that scrape.

### Relabel configs vs static labels

`relabel_configs` with `source_labels: [instance]` won't work for adding labels — `instance` isn't set yet during the relabeling phase. Use `source_labels: [__address__]` instead, or skip relabeling entirely and use `static_configs.labels`.

### `on()` drops extra labels

In PromQL, `X / on(instance) Y` keeps only the `instance` label in the result. Use `group_left(hostname)` to bring back labels from the left side: `X / on(instance) group_left(hostname) Y`.

### cAdvisor image healthcheck

`gcr.io/cadvisor/cadvisor:latest` has a built-in HEALTHCHECK that checks port 8080 by default. If running on a different port, set `CADVISOR_HEALTHCHECK_URL=http://localhost:PORT/healthz`.

### Prometheus data from config changes

Each Prometheus config change with different labels creates separate time series in the TSDB. Old series persist for the retention period (default 15 days). This causes duplicate entries until old data ages out. Filter with `hostname!=""` or similar to exclude obsolete label variants.
