# Changelog

Nodes:
- **milis-wonderspace** (192.168.50.115) — i7-7700, 16GB, ~29TB storage. mergerFS pool, *Arr stack, qBittorrent, Navidrome/Komga/slskd, ArchiveBox, borgmatic.
- **milkymiracle** (192.168.50.122) — i5-9500T, 16GB, NVMe. Jellyfin, FoundryVTT, Immich, Masqueradarr (IPTV), Vocard, Portainer. keepalived VIP holder.
- **heavensfeel** (192.168.50.129) — N95, 16GB, 512GB SSD. Always-on daemons (n8n, free-games-claimer, Vaultwarden, ASF), SearXNG, monitoring hub (Prometheus/Grafana/Loki/Uptime Kuma), Hermes.

Ops: **Ansible** (GitOps: compose + traefik configs converged from this repo) · **CI + Trivy** on public homelab-iac · **Diun** image-update notifications · changelog below.

---

## Changelog

### 2026-09-21 (live audit) — fleet re-audit: leader moved, Immich v3, redlib-instances documented, DNS exposure mapped

Re-inventoried all three nodes against the docs (`docker ps`, `docker node ls`, swarm services, systemd timers, crontabs, Traefik routers, and the Cloudflare zone). Drift found and reconciled:

- **Swarm leader moved to heavensfeel** (was milkymiracle) — it is an elected Raft role and the docs had it pinned to milkymiracle. Updated Docker Swarm and `architecture/overview.md`, both server pages, and noted that the leader is dynamic.
- **Immich is on `v3`** (`immich-server:v3`, `immich-machine-learning:v3`) — docs said `v2`. Updated Immich.
- **New undocumented service: `redlib-instances`** on heavensfeel — an `nginx:alpine` container serving a curated Redlib instance list (`instances.json`, :8192) for the **ASFFreeGames** plugin on ASF (deployed 2026-09-06, replacing an earlier Python/Byparr adapter). It runs as its **own compose project** (`redlib-instances.yml`), so it is *not* in the Ansible deploy set — out-of-band, the same class as the ArchiveBox gap reconciled earlier today. Now in other-services + the heavensfeel page, and flagged for folding into `compose/heavensfeel.yml`.
- **`fabula` documented** (static nginx serving the Fabula Ultima campaign log) — previously visible only as a Traefik router row.
- **DNS exposure mapped.** Only a subset of `*.example.com` hosts have a Cloudflare CNAME; the rest are internal-only and resolve solely through the AdGuard wildcard `*.example.com → 192.168.50.99`. The full internal-only list is now in traefik + topology, so "has a router" is no longer conflated with "is public facing".
- **Confirmed clean:** Traefik `standalone.yml`/`dynamic.yml` are byte-identical to the repo on all nodes; no stopped or orphaned containers; no service present that is not documented (after the additions above).

No infrastructure was changed — documentation only.

### 2026-09-21 — Ollama + Open WebUI retired; ArchiveBox drift reconciled

Decommissioned the AI stack on **milis-wonderspace** — both containers were idle, and **Ollama had zero models downloaded** (`/DATA/Apps/ollama` was 36K; Open WebUI's `webui.db` was last written 2026-09-11). No active n8n workflow referenced either (the 3 matches were inactive drafts).

- **Removed**: `ollama` + `open-webui` from `compose/milis-wonderspace.yml`; the `chat` router + service from `infra/traefik/dynamic/standalone.yml` (`chat.example.com` now 404 — cert expires naturally); Uptime Kuma monitor "OpenWebUI" (id 13) + its history rows.
- **Reclaimed**: ~560MB RAM (wonderspace swap also 1.3G → 1.1G), 968M on `/DATA`, 2 containers, ports 11434/3000. `OPENWEBUI_SECRET_KEY` dropped from the node's `.env`.
- **Archived first**: `webui.db` (9.5MB — RAG index, MCP tool configs, community tools, OpenCode Go config) → `/home/user/archives/retired/open-webui-webui.db.2026-09-21` on wonderspace, deliberately **outside** `/DATA` so borgmatic does not carry it.

**Drift found during the deploy (the important part).** The first `deploy.yml --check` reported `changed` on the compose files of *all three* nodes. Diffing live vs repo showed the fleet had drifted **ahead** of the repo — the live files were the deliberate operator state:

| Node | Live | Repo (stale) |
|------|------|--------------|
| wonderspace | `archivebox` service running (healthy, 304M, `archive.example.com`) | **no ArchiveBox block at all** |
| milkymiracle | `iflip721/masqueradarr:latest` + `NODE_OPTIONS=--max-old-space-size=4096` | `:dev`, no `NODE_OPTIONS` |
| heavensfeel | `louislam/uptime-kuma:2` | `:latest` |

ArchiveBox was the dangerous one: it had run **undocumented since ~June** (only its Traefik router was in the repo), so a plain deploy would have dropped its definition and the planned `--remove-orphans` would have **deleted the container**. All three were folded into the repo first, making the deploy a no-op for them — this is the v2-roadmap 1.4 "prune stale cross-node compose copies" item surfacing for real. ArchiveBox is now documented in other-services and the wonderspace server page.

**Control node moved to heavensfeel (same session).** `deploy.yml` is documented as the only repo→live path, but `ansible-playbook` was installed nowhere, and the docs' stated control node was *"the operator's laptop"*. A control node does **not** need to be always-on — Ansible is push-based and only has to exist when a playbook is invoked — but tying the GitOps controller to a machine that's off for most of the day also blocks roadmap 2.2's scheduled drift audit. Moved it to **heavensfeel** (always-on): `ansible-core 2.19.13` via `uv tool install` (no sudo needed — `ensurepip` is absent on that node, so a plain venv can't bootstrap pip), and it already reaches both other nodes by key. The deploy set (`ansible/`, `compose/*.yml`, Traefik `standalone.yml` + `dynamic.yml`) is published to `/home/user/homelab/` by `scripts/publish-to-control.sh`, which **excludes** `compose/job-ops.env` and `infra/traefik/dynamic/dashboard.yml`. Verified end-to-end: `deploy.yml --check` run *from heavensfeel* → all 3 nodes, `changed=0 failed=0 unreachable=0`. The vault stays the authoring copy; heavensfeel is the deploy runtime.

**Tooling gap left open:** `deploy.yml` runs `docker compose up -d` **without `--remove-orphans`**, so removing a service from a compose file leaves its container running as an orphan. Removals currently need a manual `up -d --remove-orphans` (done here for wonderspace). Candidate for v2 Track 1.4.

**Vault under version control (same session).** The vault — the *authoring* copy of everything above — had no `.git` at all, so the "source of truth" had no history: a stray un-published edit would have stayed invisible until someone ran a stale deploy. Created **private `<private-iac-repo>`** (117 files, 0.48M) and pushed. Deliberately **not** folded into `homelab-iac`: that repo is public *and* restructured (`compose/nodes/`, `docs/`, `/home/user/`), while the vault is the real tree with live values — a pre-commit scan found several real credentials in the authoring tree, so the files that carry them are `.gitignore`d alongside `.playwright-mcp/` and node_modules. Also `.stignore`d `.git` — Homelab is a Syncthing folder (id `8be0b5`) and syncing git internals across peers corrupts the index. The control node now holds a **read-only deploy-key clone** of the private repo at `/home/user/homelab`, so `publish-to-control.sh` became push → `git pull --ff-only` instead of rsync.

### 2026-09-21 (later) — homelab-iac republished; sanitization slips fixed; CI green again

Republished the public mirror from the vault (its first sync since 2026-08-15) and fixed three pre-existing leaks found during the sweep.

**Content brought over:**
- `compose/nodes/milis-wonderspace.yml` — AI stack removed, ArchiveBox added
- `traefik/dynamic/standalone.yml` — `chat` router + service → `archivebox` (`archive.example.com`)
- `compose/nodes/heavensfeel.yml` — uptime-kuma pinned to `:2`
- `.env.example` — dropped `OPENWEBUI_*` + `SEARXNG_QUERY_URL`, added `ARCHIVEBOX_*`
- `ansible/` inventory + group_vars comments; a generic "where to run the control node" note in `ansible/README.md`
- `PLAN.md` file inventory

**Leaks fixed (pre-existing, not introduced this session):**
- `scripts/homelab-scripts.polkit` — `subject.user` was the **real username**, in a published polkit rule
- `.trivyignore` — three real hostnames in triage comments
- `AGENT.md` + `PLAN.md` — the substitution rules named the real domain, home path and username verbatim (self-defeating: the rule forbidding `/home/user/` contained `/home/user/`)

**CI fixed — and the gate redesigned.** The Trivy CRITICAL gate had failed **every** weekly run since 2026-08-31. Two separate causes:

1. **vaultwarden** — 3 CRITICALs on `perl-base` (Debian base lag). Accepted individually in `.trivyignore` with a dated note (vaultwarden is Rust; perl is inherited cruft, never invoked). Re-scan: 0 CRITICAL.
2. **Four more images** (diun 3, seerr 2, komga 4, n8n 7) plus **uptime-kuma at 125** — all upstream rebuild-lag. Hand-accepting 141 CVEs would hollow the gate out, so it gained a coarser second mechanism: **`.trivy-lag-images`**, a per-image advisory list. Listed images are reported in the job summary but do not fail; **any image not listed still fails on a CRITICAL**, so the gate stays meaningful for anything new. It emits a warning when a listed image scans clean, so entries get pruned rather than accumulating.

**The uptime-kuma trap (worth remembering).** The mirror pinned `uptime-kuma:latest`; the live node pins `:2`. Mirroring the live value sent the count 3 → 125, which looked like a regression. It isn't: `:latest` is built on **Debian 10, which went EOL** — and Trivy stops tracking advisories for EOL distros, so `:latest` "scanned clean" while being the *less* safe image. `:2` is Debian 12 and reports honestly (106 of the 125 are chromium, shipped for browser-based monitors). Recorded in `.trivy-lag-images` so nobody "fixes" it back to `:latest`. CI green as of `7fde210`.

**Still manual:** the sanitize step is clone → edit → push, with no rules file driving it. Mirror git history also retains the pre-fix username in older commits; purging needs a history rewrite + force-push (not done). See ansible for the related publish path.

### 2026-09-07 — DDNS outage: whole fleet unreachable externally after a router reboot

*(Recollected 2026-09-21 — this session predates the vault's git history and was never written up.)*

The homelab became unreachable from the wider internet. Triage ruled out the entire internal stack (Traefik routers, LE certs, keepalived VIP, AdGuard, the swarm) — all healthy; the failure was one layer upstream.

- **Symptom:** public resolvers returned the *old* WAN address for `your-ddns.asuscomm.com` — and therefore for every CNAME through it. LAN access was unaffected. Uptime Kuma and the rest looked fine from inside.
- **Root cause:** the router's weekly scheduled reboot (~09:31) returned a **new Verizon FiOS WAN address** (`100.x.x.x → 100.x.x.x`), but the DDNS update **failed** — `ddns: update ddns token failed(-3)` — and the 5-minute retry cron kept failing from 09:35 through 15:20. The DDNS name, and so every Cloudflare CNAME, stayed pinned to the dead address.
- **Fix:** re-authenticated the DDNS client in the ASUS router (refreshed the DDNS token). The record updated on the next push and external reachability returned.
- **Correction to the in-session diagnosis:** the initial hypothesis was **ISP CGNAT** (the WAN lives in `100.0.0.0/8`, which superficially resembles RFC 6598 space). It is not — rDNS is `pool-100-11-207-34.phlapa.fios.verizon.net`, a routable Verizon FiOS public address. RFC 6598 is `100.64.0.0/10`; `100.11.x` is outside it. The outage was purely stale DDNS, and framing it as CGNAT would have sent future triage down the wrong path (port-forwarding *was* working).
- **Follow-on:** the apex `example.com` was still hard-pointed at the dead address at the time. It is now a CNAME to the DDNS name (self-healing), so it follows future WAN changes.

See topology → *Public DNS, DDNS & the WAN* for the chain and the fast-diagnosis checklist.

### 2026-08-31 — patreon-archive: pawchive 403-storm fixed (attachments were not downloading)

- **Incident**: the largest creator pawchive backfill was stuck for 26h in a `file.pawchive.pw` 403
  storm — only 7 files saved across ~800 posts; 103/106 local post-folders had `post.json`
  but no media.
- **Root cause A (concurrency)**: a manual backfill left running since Aug 30 + the 05:45
  cron were running **two concurrent pullers** from the same egress IP, doubling request
  rate and keeping the throttle permanently tripped.
- **Root cause B (it was the operator, not an auto-limit)**: the 403 body was a message
  from the pawchive.pw operator — *"stop before I block every single one of your IPs,
  either download reasonably or contact me with your reasoning, but TBs a day is just
  abusive."* Successfully-served files still return 200; the URLs we hammered stay
  selectively blacklisted. Health-check probes after stopping confirmed the IP itself was
  fine.
- **Fixes**: flock guards (no parallel runs); 403 → 10/30-min cooldown + abort-after-3
  consecutive (bounded, safe); media-target dedupe (API lists the same file under
  `attachments` and `file`); cookie via `$PAWCHIVE_COOKIE` env; **re-paced to polite** —
  `--file-sleep` 8s (jittered) + 10 GiB/day byte budget.
- **Status**: cron re-enabled at 05:45; polite backfill running and resuming partial posts
  from state.json. Blacklisted URLs should decay on the ~day scale as our request rate
  drops. See **patreon-archive** → Incidents.

### 2026-08-30 — Patreon archival pipeline (patreon-archive)

- New **patreon-archive** (services/patreon-archive.md) — archives 6 Patreon creators into `/mnt/network/Archives/Patreon/` (all creators under one root, with `Patreon/README.md` self-documenting it).
  - **Direct pulls** (memberships) via `patreon-dl` v3.9 in a `node:22-slim` Docker image (`patreon-archive:latest`, built on milis-wonderspace, node:22 for better-sqlite3 ABI) — three smaller creators. Output: `<creator> - <name>/posts/<post_id> - <title>/{images,post_info,campaign_info}` with full metadata sidecars.
  - **pawchive backfill** via new `pawchive-pull.py` (kemono-compatible `/api/v1` + `file.pawchive.pw`) — the largest creator full pull (786/792 posts have_full), gap-fill for the direct creators (skips post ids already in `patreon-dl/`). Handles pawchive's burst 403 throttling with curl + 30/60/90s cooldowns.
  - **Consolidated layout**: `/mnt/network/Archives/Patreon/<Creator>/{patreon-dl,pawchive}` — moved the existing per-creator folders (incl. the legacy a legacy series Discord series dump, now `Patreon/<legacy>/`) under the single `Patreon/` root; `Patreon/README.md` documents it.
  - Secrets at `~/.config/patreon/` on wonderspace (0600): `patreon-cookies.txt` (Netscape), `cookie-string.txt`, `pawchive-cookie.txt` — mounted ro into the container.
  - Schedule: wonderspace user crontab `30 5 * * *` (direct) + `45 5 * * *` (pawchive), incremental via patreon-dl status cache + pawchive state.json. Initial backfills running.
  - Open: one further creator (not on pawchive, no membership → skipped).
  - **a legacy series dropped from the pipeline same-day (2026-08-30)**: existing `Patreon/<legacy>/` archive (incl. legacy Discord dumps) kept as-is, no further direct/pawchive pulls — removed from `run-direct.sh` / `run-pawchive.sh`, archive `README.md` + this page updated.

### 2026-08-15 (late) — V2 roadmap drafted

- New **v2-roadmap** (architecture/v2-roadmap.md) — consolidated plan: Track 1 Ansible depth (privileged scope, systemd units/timers as code, NFS post-migration, housekeeping), Track 2 CI evolution (self-hosted runner → CI-triggered deploys, scheduled drift audit), Track 3 security backlog (Vaultwarden secrets, DR drills, SMART alerts, Immich backup, inventories), Track 4 platform expansion (k3s lab, OpenTofu, OTel/Tempo, Authentik, MinIO). Phases A/B/C + definition of done.
- `architecture/improvements.md` + `services/ansible.md` now link to the roadmap.

### 2026-08-15 (late) — Ansible dedicated doc + full doc sweep

- New **ansible** page (services/ansible.md): control-node setup, layout, v1 scope, change workflow, troubleshooting, history.
- **architecture/overview.md** — new "Infrastructure-as-Code / GitOps" section (Ansible + CI + Diun loop).
- **servers/*.md** — all 3 node pages now note which files are Ansible-converged (ansible).
- **architecture/improvements.md** — config-drift row promoted to resolved for the v1 scope; eserver traefik-dir item marked done.
- **services/other-services.md** — added Diun + FreshRSS entries.
- Public `homelab-iac` re-aligned: `common.yml` privileged-draft tasks removed (mirror drift fixed), README sudo-model wording corrected — CI green.

### 2026-08-15 — Recollected 2026-08-11 session: off-site borg backups (fixed)

The 2026-08-11 session (not documented in this repo) set up **off-site borg backups** to heavensfeel and left them half-working:

- **Design found live:** wonderspace borgmatic → `ssh://user@192.168.50.129/repos/homelab`. hserver runs `borg-repo` (borgmatic image, idle, `/home/user/borg-repos` → `/repos`) and user's `authorized_keys` has a restricted forced command (`docker exec -i borg-repo borg serve --restrict-to-path /repos`, `restrict`). Key pair at `/DATA/Apps/borgmatic/ssh/`.
- **What was broken:** (1) the borgmatic compose service never mounted `/DATA/Apps/borgmatic/ssh:/root/.ssh:ro` → every cron since Aug 11 failed with `Permission denied (publickey)` (last successful write: 2026-08-11 19:53); (2) the repo was init'd **unencrypted** while config.yaml declares a passphrase; (3) `borg-repo` was defined only in the node's compose file — a repo sync had orphaned it (container ran but was no longer reproducible).
- **Fixes:** mount added + deployed; repo re-initialized `repokey-blake2` with the configured passphrase; `ssh_command` gains `-o UserKnownHostsFile=/root/.config/borg/ssh/known_hosts` (`.ssh` mount is ro); `borg-repo` recollected into `compose/heavensfeel.yml`; first full backup of `/DATA` (14GB, `auto,lzma`) verified end-to-end through the forced-command path.
- **Notes:** repo is on a second physical node (heavensfeel) but same site — still no true off-site copy (see improvements.md). Retention 7d/4w/6m. Test archive from the migration deleted.

### 2026-08-15 — Diun, FreshRSS, first IaC layer (Ansible) + GitOps CI

- **Diun** deployed on heavensfeel — 3 instances (`diun`, `diun-milkymiracle`, `diun-wonderspace`), one per node, each watching its node's read-only docker-proxy (:2376). Image updates → Telegram every 6h. Note: Diun supports only ONE endpoint per instance (verified against v4.33 source — no multi-host option), hence 3 containers. `IMAGES: 1` added to docker-proxy env on all 3 nodes (read-only GET only). Telegram token/chatID reused from Hermes config. See diun.
- **FreshRSS** deployed on heavensfeel — `rss.example.com`, auto-installed (SQLite, admin user, API enabled), feeds refresh every 30 min. Password in hserver `/home/user/docker/compose/.env` (`FRESHRSS_ADMIN_PASSWORD`). LE cert issued. See freshrss.
  - **Same-day security fix:** the new Trivy CI gate flagged `freshrss:latest` with 28 CRITICAL findings (2 unique: CVE-2026-17543 PHP ext-pgsql SQLi, CVE-2026-17544 bccomp OOB-write RCE — PHP 8.4.21, fixed 8.4.24). `:latest` hadn't been rebuilt since 2026-05-20 → switched to `freshrss/freshrss:edge` (PHP 8.4.24, verified). Data untouched.
- **Ansible layer v1** added (`ansible/` in repo): inventory (3 nodes, RFC1918 IPs kept), `common.yml` (users, docker/compose plugin, dirs, timezone — audit vs deploy separation), `deploy.yml` (GitOps path: sync per-node compose + traefik dynamic config → `docker compose up -d`). Explicitly out of scope v1: sudoers whitelist (Hermes watchdog monitors it), NFS/fstab, systemd units, nftables. Sanitized copy mirrored to the public `homelab-iac` repo.
- **CI/CD pipeline** added to `homelab-iac` (public repo): yamllint + ansible-lint + compose `config -q` validation + Trivy image scan. Closes the "No CI/CD" improvement.
  - **Gate design** (after first-run triage): CRITICAL fails the build; HIGH reported per-image in the job summary; `.trivyignore` holds dated, evidenced accepts (17 upstream-lag CRITICALs across job-ops/changedetection/homepage/prarr/seerr/komga/uptime-kuma — all already at current releases, Diun closes the rebuild loop); weekly Monday schedule. First scan caught 2 real CRITICALs in the FreshRSS stable image (→ edge fix above) — the pipeline earned its keep on day one.
  - **First real pipeline run (2026-08-15):** `ansible-playbook playbooks/site.yml` (audit + apply) and `playbooks/deploy.yml` (sync + deploy) executed against all 3 nodes from a local control node — clean pass, zero drift. Convergence test: deliberately appended a comment line to hserver's live `heavensfeel.yml`; `deploy.yml` detected it (`changed=1`), restored the repo checksum, kept `heavensfeel.yml.bak` for rollback, restarted 0 containers, left other nodes untouched.
  - **Findings from the real run:** (1) eserver's `/etc/traefik/dynamic` is root-owned (server/hserver are user-owned) — deploy sync works today only because file content matches; the dir needs `sudo chown user:user /etc/traefik/dynamic` before the next config change. (2) Docs claimed "read-only sudo whitelist" as the whole story, but reality is a two-layer model: password-gated `%sudo` (human admin, stock Ubuntu) + NOPASSWD read-only whitelist (Hermes/automation, watchdog-monitored) + `docker` group = root-equivalent for user. **Docs corrected the same day** (hermes): the docs' "read-only whitelist" language now explicitly refers to the NOPASSWD automation layer.
- Traefik `standalone.yml` gained the `freshrss` router; file re-synced to all 3 nodes (md5-identical, backups `standalone.yml.bak-20260815`).

### 2026-08-04 — OpenWebUI: MCP tools, RAG, sub-agents, community tools

Follow-up to the OpenCode Go connection fix. Added to Open WebUI (`chat.example.com`, v0.11.0):

- **MCP tool servers** (Streamable HTTP, native — no `mcpo` needed): **GitHub** (`api.githubcopilot.com/mcp/` + GH PAT header) and **n8n** (`n8n.example.com/mcp-server/http` + Bearer). Both verified + saved to `tool_server.connections` via `POST /api/v1/configs/tool_servers`. Chat models can now use GitHub/n8n tools via the per-chat `+ → Integrations → Tools`.
- **RAG knowledge base "Homelab Docs"** — 31 repo docs uploaded + embedded with the local `all-MiniLM-L6-v2` sentence-transformer (already cached). Verify answers via chat RAG; reindex after doc changes.
- **Sub-agents enabled** (`subagents.enable=true`) — model can hand sub-tasks to parallel helper agents.
- **Community tools** installed + reviewed: `jellyfin_media_player` (needs `JELLYFIN_HOST`/`JELLYFIN_API_KEY` in valves — not yet configured) and `wikipedia_lookup`. From iChristGit/OpenWebui-Tools.
- **Key scrub**: removed the Go API key from the retired pipe's `valves` column (was still stored in the DB). Active key remains in `openai.api_keys` only.

See other-services.

### 2026-08-04 — OpenWebUI: OpenCode Go via native connection (pipe retired)

OpenCode Go models in Open WebUI (`chat.example.com`) were broken. Root causes (confirmed against the live API):

1. The `opencode-go-anthropic-pipe.py` Pipe proxied the Anthropic `/v1/messages` endpoint, but the Go API uses **split auth**: `/models` accepts `Authorization: Bearer`, while `/messages` requires the `x-api-key` header → every chat failed `401 "Missing API key."`
2. OpenWebUI passes the `{pipe.id}.{sub_id}` model id (`opencode_go_to_anthropic.minimax-m2.7`) to `body["model"]`, which the pipe forwarded verbatim → `Model ... is not supported`.
3. The Go models run extended thinking by default; without a thinking budget, small `max_tokens` produced empty replies.

**Fix — native OpenAI-compatible connection (no custom code):** OpenCode Go is natively OpenAI-compatible (`https://opencode.ai/zen/go/v1`, Bearer auth — verified: `/chat/completions` works non-stream + stream + system prompt). Added via `POST /openai/config/update` (stored in `openai.api_*` config keys; ConfigVar, so DB wins over env). Exposes `opencode-go.*`: `deepseek-v4-flash`, `qwen3.5-plus`, `qwen3.6-plus`, `qwen3.7-max`, `minimax-m2.5`, `minimax-m2.7`. Pipe deactivated (`opencode_go_to_anthropic`), file kept as reference. E2E verified: non-stream + streaming through OpenWebUI return text.

### 2026-08-04 — Hermes persona reset + OpenCode Go provider fix

Reset the Hermes agent (heavensfeel) to a clean **homelab assistant & technician** baseline — rewrote `SOUL.md` (new Technician Posture section: autonomous within the sudo whitelist, ask before anything outside it), `MEMORY.md`, `USER.md`. Backups in `~/.hermes/backups/20260804-214647/`.

Also fixed the OpenCode Go provider: `OPENCODE_GO_BASE_URL` pointed at `https://api.opencode.ai/v1` (returns `Not Found`); correct endpoint is `https://opencode.ai/zen/go/v1`. Fixed in `.env` + `config.yaml` fallback_model. Verified `deepseek-v4-flash` via opencode-go responds. See hermes.

Same day follow-ups:
- **Dashboard 500 fixed**: `HERMES_DASHBOARD_FILES_ROOT=%h/.hermes/managed-files` added to `hermes-dashboard.service` (was defaulting to Docker-hosted `/opt/data` → Permission denied).
- **Skills trimmed 108 → 40** and **MCP trimmed 6 → 3** (see hermes changelog). Removed `godmode` jailbreak skill. Disabled skills kept on disk.
- **searxng MCP base URL fixed**: `http://searxng:8080` → `https://search.example.com` (Docker hostname was unresolvable from host-run MCP).
- **Sudo whitelist tightened + smart approval gate**: removed write-capable sudo entries (`sysctl -w`, `ethtool`, `ip link set`, `cp /etc/sysctl.d`); `approvals.mode: smart` — see hermes.
- **Sudo escalation watchdog deployed**: `sudo-watchdog.py` cron (every 30m, Telegram) — tripwire for non-TTY sudo escalation attempts + whitelist-bypass detection, checks all 3 nodes. Watchdog surfaced cross-node gaps: milkymiracle (old write-capable whitelist) and milis-wonderspace (`NOPASSWD: ALL` via undocumented `/etc/sudoers.d/user-nopass`). **All fixed 2026-08-05** — read-only whitelist on all 3 nodes, `user-nopass` removed; watchdog passes everywhere. Wonderspace is the NFS server, so NFS client auto-recovery is unaffected. *(Clarified 2026-08-15: "read-only whitelist" refers to the NOPASSWD automation layer — the stock `%sudo` password-gated rule for the human admin remains, by design. See the 2026-08-15 entry + hermes.)*
- **Hermes auto-updated itself** (22:56 UTC, `v2026.6.5-810` → `-10007`): dashboard broke (npm EBADENGINE, fixed by `npm install -g npm@11.17.0`), and the June-2026 hardening made `--insecure` a no-op — dashboard now requires **basic auth** (`dashboard.basic_auth`, user `admin`). See hermes.

### 2026-08-01 — Documentation audit: services not documented / out of date

Audited all 3 nodes against the repo docs and reconciled discrepancies:

- **Newly documented service:** masqueradarr (IPTV aggregator, `iptv.example.com` on milkymiracle) — was running with no doc. Compose block added to `compose/milkymiracle.yml`.
- **Moved services corrected across all docs:** n8n, vaultwarden, archisteamfarm, jellyseerr, byparr, qui, termix → heavensfeel; slskd, komga → milis-wonderspace. Server pages, `other-services.md`, `traefik.md`, `flows/*` updated.
- **Cockpit:** no longer a swarm global service — now native per-node (`cockpit.socket`, 9090/9091), routed per-node. `services/cockpit.md` rewritten.
- **CrowdSec:** the Docker Traefik bouncer (`crowdsec-bouncer` container) is retired; enforcement is native `crowdsec-firewall-bouncer` (nftables) on all 3 nodes. `services/crowdsec.md` updated.
- **Swarm state:** milkymiracle is Leader (not heavensfeel), engine 29.6.1, Traefik is 3 replicas (was 2). All 3 nodes are managers with `traefik=true`. `swarms/swarm.md` + `architecture/overview.md` updated.
- **Networks:** old overlay nets (`vpn`, `media-net`, `apps-net`, `adguard_default`) gone; gluetun on `traefik-overlay`; `masqueradarr-net` added. `network/topology.md` updated.
- **Immich:** now behind Traefik (`immich.example.com`); image v2 / postgres vectorchord. `services/immich.md` updated.
- **Undocumented ops tooling documented:** `sync-qbit-port` timer (gluetun forwarded-port → qBittorrent), `deadman-ping.sh` cron (all 3 nodes), `heartbeat` timer (milkymiracle) — see `servers/milis-wonderspace.md`.

### 2026-07-17 — milis-wonderspace swarm partition (Tailscale accept-routes)

**Symptom:** Several services behind Traefik reported down — `lidarr.example.com` unreachable in the browser, and `status.example.com` (Uptime Kuma) flagged `lidarr`, `sonarr`, `radarr`, `prowlarr`, `bazarr`, `slskd`, and `cloud` (copyparty) as down. Suspected to be fallout from recent Tailscale changes. It was.

**What was NOT wrong (ruled out during triage):**
- milis-wonderspace was fully up (uptime 2d 18h, no reboot), reachable via SSH over its Tailscale IP.
- All Docker containers were `Up` and healthy; lidarr answered `302` locally on `:8686`.
- AdGuard on both DNS nodes correctly resolved `*.example.com` → `192.168.50.99` (VIP).
- Traefik routers/services for the affected hosts were present and correct in `infra/traefik/dynamic/standalone.yml`.
- LE certs for all affected hosts were present in **both** Traefik replicas' `acme.json`.
- Key clue: affected services returned **HTTP 000** (connection hang) via the `.99` VIP but **302/200** via milis-wonderspace's own Traefik (`127.0.0.1`). Traefik on the VIP holder *resolved* the backend container names but *timed out* connecting to their overlay IPs — while other containers on the same node/overlay (navidrome, jellyseerr) worked. That pointed at the overlay data plane, not certs or routing config.

**Root cause:** milis-wonderspace is the Tailscale subnet router advertising `192.168.50.0/24`, but it had **`--accept-routes=true`**, so it installed a Tailscale route for its own LAN subnet. Its routes to the other swarm managers then egressed `dev tailscale0` with source IP `100.x.x.x`:

```
# on milis-wonderspace, BEFORE fix
192.168.50.122 dev tailscale0 ... src 100.x.x.x   # milkymiracle
192.168.50.129 dev tailscale0 ... src 100.x.x.x   # heavensfeel
```

milkymiracle/heavensfeel (both `accept-routes=false`) reached wonderspace directly over the LAN (`eno1`/`enp2s0`). The resulting **asymmetric path broke the swarm-manager Raft channel (TCP 2377)**:

1. `docker node ls` showed `milis-wonderspace  Down  Unreachable`; from wonderspace, `docker info` errored `"The swarm does not have a leader"`. Cluster kept quorum (2/3: milkymiracle Leader + heavensfeel).
2. With wonderspace partitioned, the overlay control plane stopped reconciling its container endpoints cluster-wide.
3. Services **recreated after the partition** (lidarr, the arr stack, slskd, copyparty) had stale cross-node overlay routes → the VIP-holder's Traefik timed out → HTTP 000. Services with **stable, pre-partition endpoints** (navidrome, jellyseerr, vaultwarden) kept working from cached routes — which is why only a *subset* looked down.

**Fix:**
```bash
# on milis-wonderspace
sudo tailscale set --accept-routes=false
```
Routes to `.122`/`.129` immediately reverted to the LAN NIC (`dev enp2s0 src 192.168.50.115`). The manager mesh healed (`Unreachable → Reachable`), then the node-agent heartbeat flipped `Down → Ready` after ~30–60s. All seven services returned to `200`/`302` via the VIP. Preference persists across reboot (stored in tailscaled; nothing in systemd/rc.local re-runs `tailscale up --accept-routes`).

**Follow-on ~40 min later — stale overlay data plane (required a docker restart):** After wonderspace rejoined `Ready`, the swarm rescheduled global tasks onto it and *all* wonderspace-hosted services (now including navidrome) started timing out cross-node (HTTP 000), bidirectionally, even though the control plane was healthy (`netPeers:3`), VTEP peer IPs were correct (`.115`/`.122`/`.129`), the LAN underlay was clean, and the overlay is unencrypted. A `tcpdump -ni any udp port 4789` on wonderspace showed the cause: the **gossip/ingress overlay (vni 4098) egressed correctly over `enp2s0` (LAN), but the service overlay `traefik-overlay` (vni 4100) was still leaving via `tailscale0` with source `100.x.x.x`** — stale vxlan tunnel state from the `accept-routes=true` window. The `--accept-routes=false` change fixes the host routing table and the swarm control plane, but it does **not** rewrite already-established kernel vxlan devices. Combined with Tailscale's `ts-input -s 100.64.0.0/10 ! -i tailscale0 -j DROP` rule, that asymmetric path is silently dropped.

Fix: `sudo systemctl restart docker` on wonderspace — rebuilds the overlay vxlan devices over the corrected LAN path. Post-restart tcpdump confirmed **0 packets via tailscale0, all via enp2s0**; cross-node backends reachable; all services `200`/`302`. Note: **qbittorrent** exited (137) during the restart and did not auto-recover (it shares gluetun's netns and lost the race) — needed a manual `docker start qbittorrent` once gluetun was healthy.

**Prevention rule (now documented):** LAN-resident nodes run `--accept-routes=false`; only remote clients (laptop, phone, laptops) use `--accept-routes=true`. A subnet-router node must never accept its own advertised subnet. **And: after changing `accept-routes` on a node that participates in a Docker Swarm overlay, `systemctl restart docker` on that node** to rebuild vxlan tunnels — the routing fix alone leaves stale data-plane egress. See [network/topology.md](network/topology.md#tailscale-accept-routes-policy-critical) and [servers/milis-wonderspace.md](servers/milis-wonderspace.md#tailscale-critical-rule).

**Fast diagnosis next time:**
- Subset of one node's services HTTP 000 from the VIP but fine on that node's own Traefik → `docker node ls` for a `Down/Unreachable` manager → on the suspect node `ip route get <other-node-LAN-IP>`; if it egresses `dev tailscale0`, run `tailscale set --accept-routes=false`.
- Services still 000 cross-node *after* the control plane is healthy → `tcpdump -ni any udp port 4789` on the node; if VXLAN egresses `tailscale0` instead of the LAN NIC, `systemctl restart docker` to rebuild the tunnels.

### 2026-07-17 — free-games-claimer deployed

Deployed [feldorn/free-games-claimer](https://github.com/feldorn/free-games-claimer) on **heavensfeel** — auto-claims free games from Epic, Steam, Prime Gaming, and GOG on a daily schedule.

- **Node:** heavensfeel (always-on, already runs ArchiSteamFarm + Camofox browser)
- **Image:** `ghcr.io/feldorn/free-games-claimer:latest` (v2.8.71)
- **Data:** `/DATA/Apps/free-games-claimer/data` (PUID 1000)
- **Schedule:** Daily at 10:00 (`LOOP=86400`, `START_TIME=10:00`)
- **Access:** Panel at [claims.example.com](https://claims.example.com). noVNC available directly on heavensfeel when needed.
- **Traefik:** Split-subdomain — panel (7080) + noVNC (6080) routed via Traefik on all 3 nodes

**Files changed:**
- `compose/heavensfeel.yml` — added `free-games-claimer` service
- `infra/traefik/dynamic/standalone.yml` — added router + service entries for claims/browser subdomains
- `servers/heavensfeel.md` — added to service table

**First-run setup:** Log into each store via the noVNC browser, click **I'm Logged In** in the panel, then set per-store credentials (`EG_PASSWORD`, `STEAM_PASSWORD`, etc.) via env or Settings tab.

### 2026-07-27 — mergerFS + NFS readdir cache staleness fix

**Problem:** Newly imported media files on the mergerFS server (milis-wonderspace) were invisible to the NFS client on milkymiracle until the affected directory was manually `touch`ed. This caused Jellyfin (and `ls` on the client) to miss episodes/movies. Root cause: a file written to one physical disk branch did not update the pool-level directory mtime, so the NFS client kept serving its cached `readdir` listing.

**Solutions added:**

- **Post-import hook in `arr-notify-jellyfin.sh`** — After notifying Jellyfin, the script now touches the imported file's parent directory on the mergerFS server. This bumps the pool-level mtime and invalidates the stale NFS client cache. The script is bind-mounted into the Sonarr/Radarr containers.

- **Periodic safety-net timer** — `scripts/bump-recent-media-mtime.sh` + systemd timer runs every minute on milis-wonderspace. It finds media files modified in the last 2 minutes and touches their parent directories, catching any imports that bypass the post-import hook.

**Files changed:**
- `scripts/arr-notify-jellyfin.sh`
- `compose/milis-wonderspace.yml`
- `scripts/bump-recent-media-mtime.sh`
- `scripts/bump-recent-media-mtime.service`
- `scripts/bump-recent-media-mtime.timer`
- `EchoesVault/pages/mergerfs-nfs-cache-staleness.md`

### 2026-07-15 — Jellyfin media detection & NFS staleness hardening

**Problem:** Jellyfin misses newly imported media from Sonarr/Radarr because its scheduled scans run on a fixed cadence (daily at 1AM) and can miss files that arrive moments after the scan, or hit NFS hiccups. NFS staleness detection only checked the root mount, missing partial failures on subdirectories.

**Solutions added:**

- **n8n workflow "Arr → Jellyfin Notify"** — Two webhook endpoints at `n8n.example.com/webhook/{sonarr,radarr}-notify-jellyfin`. Sonarr/Radarr POST on import/upgrade/rename, n8n translates the path (e.g. `/mnt/network/Torrents/TV Shows/` → `/TV/`) and calls Jellyfin's `/Library/Media/Updated` API immediately. No more waiting for the 1AM scan.

- **Midnight Jellyfin restart** — systemd timer on milkymiracle (`jellyfin-restart.timer`) restarts the Jellyfin container daily at midnight. Safety net for any NFS state that drifted over the day.

- **Hardened `detect-stale-network.sh`** — Updated on all 3 nodes with three improvements:
  1. **Deep-path probing** — checks each critical media subdirectory (`TV Shows/`, `Movies/`, `Anime/`, `Home/`) via `stat`, not just the root mount. Catches stale handles on individual paths.
  2. **ESTALE detection** — `stat` returns stale-handle errors that `ls` misses.
  3. **D-state detection** — logs and kills stuck NFS processes before attempting unmount.

**Config changes:**
- `compose/heavensfeel.yml` — n8n: added `N8N_API_KEY` env var. (Note: API key is managed via n8n UI → Settings → n8n API, not via .env.)
- `compose/milis-wonderspace.yml` — no changes (Sonarr/Radarr webhooks point directly to n8n, no script mount needed).
