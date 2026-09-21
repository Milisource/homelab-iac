# Spec Sheets

### milis-wonderspace (server) — 192.168.50.115

| Component | Detail |
|-----------|--------|
| **CPU** | Intel i7-7700 @ 3.60GHz — 4C/8T, 65W TDP (Kaby Lake) |
| **GPU** | Intel HD Graphics 630 — QuickSync (7th gen, limited) |
| **RAM** | 16GB DDR4-2400 (2x8GB TEAMGROUP) |
| **OS Disk** | 120GB **SATA** SSD (Netac 2.5") — 66G used, 38G free |
| **Data Disks** | 30.5T raw HDD → 29T mergerFS pool |
| **NIC** | 1x Gigabit (RTL8111) + WiFi (RTL8821CE) |
| **Chassis** | Dell Inspiron 3668 Desktop |
| **Swap** | 716MB active (should investigate) |
| **Role** | Storage + Downloads + *Arr + Apps |

### milkymiracle (eserver) — 192.168.50.122

| Component | Detail |
|-----------|--------|
| **CPU** | Intel i5-9500T @ 2.20GHz — 6C/6T, 35W TDP (Coffee Lake) |
| **GPU** | Intel UHD Graphics 630 — QuickSync (9th gen, capable) |
| **RAM** | 16GB DDR4-2667/3200 (2x8GB Hynix, mixed speeds) |
| **OS Disk** | 256GB **NVMe** (Samsung PM981 M.2) — 108G used, 114G free |
| **NIC** | 1x Gigabit (Intel I219-LM) |
| **Chassis** | HP EliteDesk 800 G5 Desktop Mini |
| **Swap** | None active |
| **Role** | Compute + Media Streaming + Reverse Proxy |

### heavensfeel (hserver) — 192.168.50.129

| Component | Detail |
|-----------|--------|
| **CPU** | Intel N95 @ up to 3.4GHz — 4C/4T, 15W TDP (Alder Lake-N) |
| **GPU** | Intel UHD Graphics — QuickSync (12th gen, excellent) |
| **RAM** | 16GB DDR4-2667 (1x16GB Gowe Technology) |
| **OS Disk** | 512GB **SATA** SSD (GOFATOO M.2) — 6.7G used, **373G unallocated** in LVM |
| **NIC** | 1x Gigabit (Realtek) + WiFi (Realtek, currently down) |
| **Chassis** | Generic Mini PC (15W passively cooled) |
| **Swap** | None active |
| **Role** | Swarm Quorum + DNS + Standby Compute |

## Compute Comparison

| Metric | milis-wonderspace | milkymiracle | heavensfeel |
|--------|-------------------|--------------|-------------|
| **CPU** | i7-7700 (4C/8T) | i5-9500T (6C/6T) | N95 (4C/4T) |
| **Single-core** | ★★★★☆ | ★★★☆☆ | ★★★☆☆ |
| **Multi-core** | ★★★★☆ | ★★★★☆ | ★★★☆☆ |
| **GPU Transcode** | HD 630 (ok) | UHD 630 (good) | UHD (Alder Lake, best) |
| **TDP** | 65W | 35W | **15W** |
| **Free Disk** | 38G OS + 20T pool | 114G OS | **373G unallocated** |
| **RAM** | 16GB | 16GB | 16GB |

## Implications for Migration

### Jellyfin Standby on heavensfeel

heavensfeel has the **newest QuickSync implementation** (Alder Lake-N). It can handle several 1080p transcodes or 1-2 4K transcodes. If milkymiracle goes down, Jellyfin can be started on heavensfeel with the same NFS-mounted media:

```bash
# On heavensfeel (emergency only)
docker run -d \
  --name jellyfin \
  --device /dev/dri:/dev/dri \
  -v /mnt/network/Torrents:/media \
  -p 8096:8096 \
  linuxserver/jellyfin:latest
```

Not worth running permanently (no local storage benefit), but viable for failover.

### Backup Node

heavensfeel has **373GB unallocated** in LVM. This could be:
- A local backup target for critical Docker volumes (Vaultwarden DB, n8n data, etc.)
- A staging area for Docker image pulls/caches
- Extra space for logs or monitoring data

```bash
# Allocate space for backups
sudo lvextend -L +100G /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```

### Lightweight Service Host

heavensfeel can run services that don't need heavy storage or GPU:
- **qui** (autobrr) — lightweight, no storage needs
- **termix** — terminal sharing, tiny
- **job-ops** — automation tool
- **portainer** (UI) — if milkymiracle goes down

### What CAN'T Run on heavensfeel

| Service | Why |
|---------|-----|
| *Arr stack | Needs direct mergerFS access for hardlinks (NFS can't hardlink) |
| qBittorrent/Gluetun | Network namespace coupling, pinned to milis-wonderspace |
| slskd | Large music library, needs mergerFS directly |
| n8n | Currently accesses /Home on mergerFS for workflows |
| Vocard suite | Tightly coupled stack, already runs on milkymiracle |

## Migration Decision Matrix

| Service | Current | Target | Why |
|---------|---------|--------|-----|
| traefik | swarm | **swarm** | Manager failover across 3 nodes |
| adguard | swarm global | **swarm global** | DNS on every node |
| portainer_agent | swarm global | **swarm global** | Management agent |
| jellyfin | swarm | **compose** (milkymiracle) | GPU + media NFS |
| *Arr stack | swarm | **compose** (milis-wonderspace) | Needs local mergerFS |
| n8n | swarm | **compose** (heavensfeel) | Always-on automation; light for SATA SSD |
| vaultwarden | swarm | **compose** (heavensfeel) | Critical uptime on 15W always-on node |
| gluetun+qbittorrent | swarm | **compose** (milis-wonderspace) | Network coupling |
| slskd | compose | **compose** (milkymiracle) | Already standalone |
| vocard | compose | **compose** (milkymiracle) | Already standalone |
| immich | compose | **compose** (milkymiracle) | Already standalone |
| fundryvtt | swarm | **compose** (milkymiracle) | GPU irrelevant, just pinned |
| termix | compose | **compose** (heavensfeel) | Low resource, frees milkymiracle |
| qui | compose | **compose** (heavensfeel) | Lightweight, frees milkymiracle |
