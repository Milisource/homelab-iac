# Full Service Placement Analysis

Applying the logic from the external review: data locality, storage latency, CPU/GPU needs, NIC quality, power envelope, and uptime criticality to every service.

> **Status (2026-08-01):** This was a planning document. **All recommended moves below are now
> executed.** Current placement: komga + slskd on milis-wonderspace; n8n, vaultwarden,
> archisteamfarm, byparr, jellyseerr, qui, termix on heavensfeel; vocard suite, job-ops,
> immich, portainer, masqueradarr on milkymiracle. See the [Post-Migration Map](#post-migration-map)
> and migration-plan for the live state.

**Drive comparison**: Only milkymiracle has NVMe (Samsung PM981). Both heavensfeel and milis-wonderspace use SATA SSDs. For anything that isn't DB-heavy, SATA is fine.

---

## Data-Local Services → milis-wonderspace

These services write to or read from the mergerFS pool. Moving them off-node forces NFS round-trips.

| Service | Current | Reason to stay/put on milis-wonderspace |
|---------|---------|------------------------------------------|
| sonarr | milis-wonderspace | Renames, hardlinks, scans TV/movie files locally via mergerFS |
| radarr | milis-wonderspace | Same — movie library operations need direct FS access |
| lidarr | milis-wonderspace | Music library scanning and hardlinking |
| prowlarr | milis-wonderspace | Indexer management, config local to the node |
| bazarr | milis-wonderspace | Subtitle downloads/renaming near the media |
| cleanuparr | milis-wonderspace | Scans and prunes local media files |
| gluetun | milis-wonderspace | VPN tunnel — downloads land on the node with the storage |
| qbittorrent | milis-wonderspace | Network-coupled to gluetun; downloads → mergerFS |
| copyparty | milis-wonderspace | File server — serves mergerFS directly; `/root` = `/mnt/network` |
| navidrome | milis-wonderspace | Music library is on mergerFS; i7-7700 handles multiple transcode clients |

## Should Move to milis-wonderspace (currently elsewhere)

These run on milkymiracle but would benefit from direct mergerFS access:

| Service | Current Node | Why move |
|---------|-------------|----------|
| **komga** | milkymiracle | Comic/manga library (`/mnt/network/Torrents/Books/Manga`) — thumbnail generation, library scanning over NFS is slower than local |
| ~~kavita~~ | ~~milkymiracle~~ | **Decommissioned 2026-05-08** — replaced by Calibre-web on milis-wonderspace. Books library imported into Calibre metadata DB; no scanning latency dependency. |
| **slskd** | milkymiracle | Downloads to `/mnt/network/Torrents/Soulseek Hell/` — writes over NFS vs local filesystem |

**Risk**: komga/kavita data (`/DATA/Media/Komga/`, `/DATA/Media/kavita/`) is currently on milkymiracle's local `/DATA/`. Must be rsynced to milis-wonderspace before migration.

---

## Compute/Serving Services → milkymiracle

These benefit from the NVMe (Samsung PM981), Intel I219-LM NIC, or 9th-gen UHD 630 QuickSync:

| Service | Current | Why milkymiracle |
|---------|---------|------------------|
| jellyfin | milkymiracle | UHD 630 QuickSync, I219-LM for stream delivery, media via NFS (reads only) |
| foundryvtt | milkymiracle | Node.js websocket server — NVMe for world/LevelDB data, I219-LM for low-latency player connections |
| immich | milkymiracle | NVMe + UHD 630 for ML inference; photo library on local `/mnt/remote-storage` |

## Should Move to heavensfeel (currently elsewhere)

| Service | Current Node | Why move |
|---------|-------------|----------|
| **n8n** | milis-wonderspace | Automation — SQLite is modest, webhook-driven, /Home via NFS. Too lightweight to need NVMe. |
| **jellyseerr** | milis-wonderspace | Media request UI — ~200MB Node.js process. Talks to *arrs over HTTP regardless of node. |

**Risk**: n8n data (`/DATA/Apps/n8n/.n8n`) and jellyseerr data (`/DATA/Media/Jellyserr/`) must be rsynced from milis-wonderspace → heavensfeel.

---

## Always-On Daemons → heavensfeel

15W TDP, never-goes-down, minimal resources. Critical services that just need to be alive:

| Service | Current Node | Why heavensfeel |
|---------|-------------|-----------------|
| **vaultwarden** | milis-wonderspace | 40MB binary + SQLite. Arguably the most critical service — if it's down, you can't log in to anything. The 15W node is perfect for "don't ever let this die." |
| **archisteamfarm** | milis-wonderspace | Idles 24/7 poking Steam APIs. Zero storage needs, near-zero CPU. |
| **byparr** | milis-wonderspace | Captcha/proxy service for Prowlarr. Lightweight, no storage. |
| **n8n** | milis-wonderspace | Automation workflows — SQLite is modest, /Home accessible via NFS. Lighter than it looks. |
| **jellyseerr** | milis-wonderspace | Media request UI — talks to *arrs over HTTP. ~200MB RAM, no disk dependency. |
| **vocard** | milkymiracle | Discord bot. Keep where it is — stable, tightly coupled stack. |
| **vocard-dashboard** | milkymiracle | Web dashboard for bot. |
| **vocard-db** | milkymiracle | MongoDB. ~1GB RAM. |
| **lavalink** | milkymiracle | Audio streaming. Keep with the rest of vocard. |
| **spotify-tokener** | milkymiracle | Spotify token. Keep in vocard stack. |
| **yt-cipher** | milkymiracle | YouTube cipher. Keep in vocard stack. |
| **qui** | milkymiracle | autobrr — 15MB Go binary. Move to heavensfeel. |
| **termix** | milkymiracle | Terminal sharing — move to heavensfeel. |

**Risk**: vaultwarden data (`/DATA/Apps/vaultwarden/data`), archisteamfarm config (`/DATA/Apps/asf`), and vocard MongoDB data (`/home/user/vocard/mongodb_data`) must be migrated to heavensfeel. Byparr has no persistent data.

---

## Services That Stay Where They Are

| Service | Node | Why |
|---------|------|-----|
| immich | milkymiracle | Deeply tied to local storage (`/mnt/remote-storage`, PostgreSQL, ML models). Too complex to move. |
| portainer | milkymiracle | Already standalone. Fine where it is. |
| vocard suite (6 containers) | milkymiracle | Tightly coupled stack (MongoDB + Lavalink + Python services). Stable where it is. |
| job-ops | milkymiracle | Uses Playwright (Chromium) for browser automation — CPU-heavy when running jobs. The N95 would struggle.

---

## Services That Stay Where They Are

| Service | Node | Why |
|---------|------|-----|
| immich | milkymiracle | Deeply tied to local storage (`/mnt/remote-storage`, PostgreSQL, ML models). Too complex to move. |
| portainer | milkymiracle | Already standalone. Fine where it is. |
| vocard suite (6 containers) | milkymiracle | Tightly coupled stack (MongoDB + Lavalink + Python services). Stable where it is. |
| job-ops | milkymiracle | Uses Playwright (Chromium) for browser automation — CPU-heavy when running jobs. The N95 would struggle.

---

## Migration Priority Summary

**Phase 1 — Quick wins (low risk):**
- byparr → heavensfeel (no persistent data to move)
- archisteamfarm → heavensfeel (config rsync only)
- termix → heavensfeel (trivial)
- qui → heavensfeel (config rsync only)

**Phase 2 — Medium impact:**
- komga → milis-wonderspace (must rsync /DATA/Media/Komga)
- ~~kavita~~ → **Decommissioned** (replaced by Calibre-web, already on milis-wonderspace)
- slskd → milis-wonderspace (must rsync /DATA/Media/slskd)
- vaultwarden → heavensfeel (must rsync /DATA/Apps/vaultwarden)

**Phase 3 — Requires data migration:**
- n8n → milkymiracle (must rsync /DATA/Apps/n8n and reconfigure webhook URLs)
- jellyseerr → milkymiracle (must rsync /DATA/Media/Jellyserr)

**Phase 4 — Optional / debatable:**
- vocard suite → heavensfeel or stays on milkymiracle
- job-ops → heavensfeel or stays on milkymiracle

---

## Swarm Global Services (No Placement Decision)

These run on **every node** regardless of role — one replica per node via swarm global mode:

| Service | Reason |
|---------|--------|
| **Cockpit** | Multi-node management dashboard. Each instance manages its local node via SSH + cockpit-bridge. Traefik load-balances across all replicas. |
| **Traefik** | Reverse proxy on all nodes for HA ingress via keepalived VIP. |
| **AdGuard** | Local DNS resolution everywhere with keepalived failover. |
| **Node Exporter** | Prometheus metrics collection per host. |
| **Promtail** | Loki log shipping per host. |
| **cAdvisor** | Container metrics per host. |
| **Portainer Agent** | Container management agent per host. |

## Post-Migration Map

```
milis-wonderspace (storage + downloads + media scanning):
  sonarr, radarr, lidarr, prowlarr, bazarr, cleanuparr
  gluetun + qbittorrent
  navidrome, komga (unified reader — books, comics, manga), slskd
  copyparty

milkymiracle (compute + streaming + databases):
  jellyfin, foundryvtt, immich
  n8n, jellyseerr
  job-ops, vocard suite (or heavensfeel)

heavensfeel (always-on critical daemons):
  vaultwarden, archisteamfarm, byparr
  qui, termix
  vocard suite (if moved)
```
