# Other Services

## Diun (Docker Image Update Notifier)
- **Host**: heavensfeel (3 instances: `diun`, `diun-milkymiracle`, `diun-wonderspace`) | **Domain**: none — Telegram only
- Watches all 3 nodes' containers via their read-only docker-proxy (:2376), notifies on upstream image updates
- [Full documentation →](diun.md)

## FreshRSS (RSS Reader)
- **Host**: heavensfeel | **Domain**: [rss.example.com](https://rss.example.com)
- Lightweight feed aggregator; SQLite, feeds refresh every 30 min; runs `:edge` since 2026-08-15 (PHP CVE fix)
- [Full documentation →](freshrss.md)

## n8n (Workflow Automation)
- **Host**: heavensfeel | **Domain**: n8n.example.com
- Advanced workflow automation with access to `/Home` on the mergerFS pool
- Webhook URL: https://n8n.example.com
- Config: `/DATA/Apps/n8n/.n8n/`
- Webhooks: `/webhook/{sonarr,radarr}-notify-jellyfin` (Arr → Jellyfin immediate library notify)

## Komga (Unified Reader — Comics, Manga, Books)
- **Host**: milis-wonderspace | **Domain**: komga.example.com | **Port**: 25600
- Libraries: Manga, Books, Comics, Artbooks (all from Torrents/Books/)
- Folder = series — no filename parsing issues. Book hats (AI ML, Web Design, AWS) become series naturally.
- Replaces both Kavita and Calibre-web (decommissioned 2026-05-08)
- Config: `/DATA/Media/Komga/config/`
- Data: `/DATA/Media/Komga/data/` (metadata, bookmarks, reading progress)

## Kavita & Calibre-web — Both Decommissioned (2026-05-08)
- Kavita: filename-based series parsing broke "hat" folder grouping
- Calibre-web: too book-focused, didn't handle comics/manga
- All content now served via Komga — see Komga entry above

## Foundry Virtual Tabletop
- **Host**: milkymiracle | **Domain**: foundry.example.com
- Username: your-foundry-username
- Administrator key and password stored as Docker secrets
- Data: `/DATA/Apps/foundry/`
- Two installs: `foundry` and `gaia-foundry`

## CopyParty (File Sharing)
- **Host**: milis-wonderspace | **Domain**: cloud.example.com
- Serves whole mergerFS pool at `/root/`
- Config: `/DATA/Apps/Copyparty/`
- Uses mimalloc allocator for performance

## ArchiSteamFarm
- **Host**: heavensfeel | **Domain**: asf.example.com
- Steam card/idle farming
- Config: `/DATA/Apps/asf/`

## redlib-instances (Redlib instance list for ASF)
- **Host**: heavensfeel | **Port**: 8192 | **Domain**: none (internal only — `192.168.50.129:8192`)
- Tiny `nginx:alpine` container serving a curated Redlib instance list (`instances.json`) as static files from `/DATA/Apps/redlib-instances`
- Consumed by the **ASFFreeGames** plugin on ArchiSteamFarm (`freegames.json.config` → `redlibInstanceUrl: http://192.168.50.129:8192/instances.json`). Redlib/Reddit access is otherwise blocked/rate-limited, so the plugin resolves a working instance from this list instead of hardcoding one.
- The list is seeded from [redlib-org/redlib-instances](https://github.com/redlib-org/redlib-instances) and trimmed to a short, reachable set (official copy kept alongside as `instances.json.official-backup`)
- **Deployment:** runs as its own compose project (`redlib-instances.yml`, deployed 2026-09-06) from `/home/user/docker/compose/` — it is **not** part of the Ansible `deploy.yml` set (heavensfeel's `compose_file` is `heavensfeel.yml`), so it is out-of-band and would not be recreated by a deploy. Candidate for folding into `compose/heavensfeel.yml` (cf. the ArchiveBox drift on 2026-09-21).
- Replaces an earlier Python proxy adapter that fronted Byparr (`:8191`) on the same port. See asf-trimming-fixes.

## Masqueradarr (IPTV Aggregator)
- **Host**: milkymiracle | **Domain**: iptv.example.com | **Port**: 3000
- Aggregates M3U/EPG IPTV sources behind a single identity, proxies streams
- Backend: mongo-masq (MongoDB on loopback:27018)
- [Full documentation →](masqueradarr.md)

## Job-Ops
- **Host**: milkymiracle | **Domain**: [jobs.example.com](https://jobs.example.com)
- Automated job discovery, AI scoring, resume tailoring, and post-application tracking
- Personal-use tooling; its deep-dive is not published in this wiki

## Termix
- **Host**: heavensfeel | **Port**: 5600 | **Domain**: termix.example.com
- Terminal sharing tool
- Port 30001-30006 for terminal sessions

## Byparr
- **Host**: heavensfeel | **Port**: 8191
- Captcha/proxy service for Prowlarr
- Hardened: `USE_XVFB=true` + `USE_HEADLESS=false` avoids headless detection

## qui (autobrr)
- **Host**: heavensfeel | **Port**: 7476 | **Domain**: qui.example.com
- Torrent IRC autodownload (autobrr)
- Config: `/DATA/Net/qui` | Downloads: `/mnt/network/Torrents`

## Borgmatic (Automated Backups)
- **Host**: milis-wonderspace | **Config**: `/DATA/Apps/borgmatic/config.yaml`
- Versioned, encrypted (repokey-blake2), deduplicated backups of `/DATA/` (app configs, DBs — NOT media)
- Container runs borgmatic on cron schedule defined in config (`CRON=0 6 * * *`)
- **Repo target (off-site, since 2026-08-11):** `ssh://user@192.168.50.129/repos/homelab` (heavensfeel) — borg over SSH into the `borg-repo` container on heavensfeel (restricted forced command: `command="docker exec -i borg-repo borg serve --restrict-to-path /repos",restrict` in user's authorized_keys). Repo lives at `/home/user/borg-repos/homelab`.
- **SSH key:** `/DATA/Apps/borgmatic/ssh/id_ed25519` (generated `borgmatic@wonderspace`), mounted into the container at `/root/.ssh:ro`. `ssh_command` includes `-o UserKnownHostsFile=/root/.config/borg/ssh/known_hosts` (the `.ssh` mount is read-only — host-key file must live on the writable borg config volume).
- **Retention:** keep_daily 7, keep_weekly 4, keep_monthly 6
- **2026-08-15 fix:** the Aug 11 migration session never added the `/DATA/Apps/borgmatic/ssh:/root/.ssh:ro` volume to the compose borgmatic service — every cron run since silently failed (`Permission denied (publickey)`). Mount added, repo re-initialized encrypted (the original was created unencrypted while the config declared a passphrase), first full backup verified end-to-end.

## ArchiveBox (Self-Hosted Web Archiving)
- **Host**: milis-wonderspace | **Domain**: [archive.example.com](https://archive.example.com) | **Port**: 8000
- Archives web pages to `/mnt/network/Archives/archivebox/` (mergerFS pool — ~304M as of 2026-09-21)
- Image `archivebox/archivebox:dev`; env includes `BASE_URL` and `ADMIN_USERNAME`/`ADMIN_PASSWORD` (from `.env`)
- `shm_size: 1gb`, `pids_limit: 2048` — Chromium-based archiving needs the headroom
- Router defined in `infra/traefik/dynamic/standalone.yml`; monitored by Uptime Kuma ("ArchiveBox", id 27)
- **Doc history:** ran undocumented from ~June until 2026-09-21 — its compose block existed **only on the node** (only the Traefik router was in the repo). Folded into `compose/milis-wonderspace.yml` during the 2026-09-21 drift reconciliation, which is also what saved it from an accidental `--remove-orphans` deletion. See Homelab changelog.

## Retired: Ollama + Open WebUI (2026-09-21)
Decommissioned — both were idle. **Ollama had zero models downloaded** (`/DATA/Apps/ollama` was 36K); Open WebUI's `webui.db` was last written 2026-09-11 and it used ~548MB RSS. No active n8n workflow referenced either (3 inactive drafts did). Relocating was considered and rejected — Open WebUI isn't compute-bound, so moving bought nothing and neither destination node has headroom.

- Removed from `compose/milis-wonderspace.yml`; the `chat` router + service removed from `standalone.yml`; Uptime Kuma monitor "OpenWebUI" (id 13) deleted
- `chat.example.com` now returns 404; the LE cert expires naturally
- `webui.db` (9.5MB — held the RAG index, MCP tool configs, community tools, OpenCode Go config) archived to `/home/user/archives/retired/open-webui-webui.db.2026-09-21` on milis-wonderspace, deliberately **outside** `/DATA` so borgmatic does not capture it
- Data dirs `/DATA/Apps/{ollama,open-webui}` removed, plus a stale empty `/DATA/Apps/open-webui` on milkymiracle; `OPENWEBUI_SECRET_KEY` dropped from `/home/user/docker/compose/.env` (backup `.env.bak-20260921`)
- `services/opencode-go-anthropic-pipe.py` retained as a reference artifact

**If it is ever wanted back:** it is a two-service compose block plus one Traefik router — the archive above holds the configuration and RAG index.

## Uptime Kuma (Service Monitoring)
- **Host**: heavensfeel | **Domain**: [status.example.com](https://status.example.com) | **Port**: 3001
- Monitors all services — alerts via push notification
- Data: `/DATA/Apps/uptime-kuma/`

## Prometheus (Metrics Collection)
- **Host**: heavensfeel | **Port**: 9090
- Scrapes node exporters on all 3 nodes every 15s
- Config: `/DATA/Apps/prometheus/prometheus.yml`
- Data: `/DATA/Apps/prometheus/data/`

## Grafana (Metrics Dashboards)
- **Host**: heavensfeel | **Domain**: [grafana.example.com](https://grafana.example.com) | **Port**: 3002 → 3000
- Dashboards for Prometheus metrics, Loki logs
- Config: `/DATA/Apps/grafana/`
- See [monitoring/README.md](../monitoring/README.md) for dashboards & datasources

## Loki (Log Aggregation)
- **Host**: heavensfeel | **Port**: 3100
- Centralized log storage — Promtail ships logs from all 3 nodes
- Data: `/DATA/Apps/loki/`

## Change Detection (Website Monitor)
- **Host**: heavensfeel | **Domain**: [watch.example.com](https://watch.example.com) | **Port**: 5000
- Monitors websites for content changes (job postings, price changes, etc.)
- Data: `/DATA/Apps/changedetection/`

## 5etools (Self-hosted D&D Reference)
- **Host**: heavensfeel | **Domain**: 5etools.example.com
- Auto-updates daily via cron (`update-5etools.sh`)
- [Full documentation →](5etools.md)

## Fabula (Fabula Ultima campaign log)
- **Host**: heavensfeel | **Domain**: fabula.example.com | **Port**: 80 (internal)
- Static `nginx:alpine` site serving the Fabula Ultima campaign logs from `/DATA/Apps/fabula` (read-only mount)
- No application state — content is the bind-mounted html directory

## SearXNG (Metasearch Engine)
- **Host**: heavensfeel | **Domain**: [search.example.com](https://search.example.com)
- 70+ upstream engines, JSON API for AI agents (Hermes, OpenCode)
- [Full documentation →](searxng.md)

## Monitoring Agents (swarm global — all 3 nodes)
- **Node Exporter**: port 9100 — system metrics for Prometheus
- **Promtail**: ships container + system logs to Loki on heavensfeel
- **cAdvisor**: port 9300 — per-container CPU/memory metrics
- **AdGuard Home**: DNS filtering + ad blocking (global mode)
- Configs under `/DATA/Apps/{promtail,cadvisor}/` on each node

## Cockpit (Multi-Node Management)
- **Host**: native on all 3 nodes | **Ports**: 9090/9091
- Web-based server management — services, storage, terminal, logs
- Routed per-node: cockpit.example.com (115), cockpite.example.com (122), cockpith.example.com (129)
- [Full documentation →](cockpit.md)
