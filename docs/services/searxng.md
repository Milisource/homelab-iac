# SearXNG

**Host**: heavensfeel | **Domain**: `search.example.com`
**Port**: 8080 (container) | **API**: JSON at `/search?format=json`

## Overview

SearXNG is a self-hosted metasearch engine — aggregates results from 70+ upstream engines (Google, DuckDuckGo, Brave, Startpage, Wikipedia, StackOverflow, GitHub) without tracking, profiling, or ads. It has no index of its own; it proxies queries and merges responses, so it's extremely lightweight (~250MB RAM active, 300MB disk).

Deployed to replace the Brave Search API used by Hermes and Open WebUI — eliminates API keys, rate limits, and external billing. All AI agents in the homelab now search for free.

## Why SearXNG vs alternatives

| Option | Verdict |
|--------|---------|
| **Whoogle Search** | Dead — Google broke JS-free search Jan 2025. Project has a banner acknowledging it. Single-engine dependency. |
| **LibreX** | PHP-based, fewer engines, no JSON API, minimal maintenance. |
| **YaCy** | P2P distributed index — requires bandwidth and crawl time to be useful. Overkill for agent search. |
| **Managed APIs** (Brave, Kagi, Google) | Rate limits, per-query cost, API keys, external dependency. |
| **SearXNG** | 70+ engines, native JSON API, zero rate limits self-hosted, 28k GitHub stars, actively maintained. |

## Architecture

```
AI Agents (Hermes, OpenCode, Open WebUI)
  │
  ├── via https://search.example.com (external/Traefik)
  │     └── VIP .99 → Traefik → searxng:8080
  │
  └── via http://searxng:8080 (internal, traefik-overlay)
        └── Only available from containers on the overlay network

SearXNG ──→ Redis (cache, rate-limiting state)
  │
  └──→ Upstream engines: Google, DuckDuckGo, Brave, Startpage, etc.
```

## Configuration

| Setting | Value |
|---------|-------|
| Container | searxng |
| Internal port | 8080 |
| Config dir | /DATA/Apps/searxng/config/ (mounted at /etc/searxng) |
| Redis data | /DATA/Apps/searxng/redis/ |
| Compose file | /DATA/Apps/searxng/compose.yml |
| Secret | /DATA/Apps/searxng/.env |
| Settings | /DATA/Apps/searxng/config/settings.yml |
| Merged bangs | /DATA/Apps/searxng/config/external_bangs.json (bind-mounted) |
| Image | docker.io/searxng/searxng:latest |
| Redis image | valkey/valkey:8-alpine |
| Web server | Granian (4 workers, 4 blocking threads) |
| Search time | ~0.8s (typical) |

### Performance tuning

SearXNG runs under Granian, which handles concurrent requests. Key performance settings in `settings.yml`:

| Setting | Value | Purpose |
|---------|-------|---------|
| `search.max_engine_time` | 1.5s | Cuts off engines that don't respond in time |
| `outgoing.request_timeout` | 2.0s | Per-engine HTTP timeout |
| `outgoing.pool_connections` | 200 | Connection pool for upstream engines |
| `outgoing.max_keepalive_connections` | 50 | Keep-alive connections |
| `outgoing.keepalive_expiry` | 10.0s | Keep-alive TTL |

Set in compose environment (`GRANIAN_WORKERS=4`, `GRANIAN_BLOCKING_THREADS=4`) to match the N95's 4 CPU cores. The old `UWSGI_WORKERS`/`UWSGI_THREADS` vars are unused by Granian.

### Engine weighting

Preferred engines are weighted higher so their results appear first in merged output:

| Engine | Weight | Reason |
|--------|--------|--------|
| Google | 3 | Best coverage and relevance for general queries |
| DuckDuckGo | 2 | Good fallback, privacy-first |
| Startpage | 2 | Google results without tracking |
| StackOverflow | 2 | Programming queries |
| Wikipedia | 1 | Background info |
| GitHub / GitLab | 1 | Code-related searches |

### Disabled / removed engines

**Removed entirely** (don't load at all): `radio browser` (crash on init), `ahmia` (Tor), `torch` (Tor).

**Disabled** (loaded but inactive): `bing`, `brave` (rate-limited), `yahoo`, `qwant`, `yep`, `presearch`, `wikidata` (timeout), `flickr`, `pexels`, `pinterest` (slow image engines).

### Container capabilities

The compose file adds `DAC_OVERRIDE` to allow writing to the config directory from within the container. Without it, the read-only container user can't update settings.yml or create files in `/etc/searxng/`.

```yaml
cap_drop:
  - ALL
cap_add:
  - CHOWN
  - SETGID
  - SETUID
  - DAC_OVERRIDE
```

## Integrations

### OpenCode MCP (WonderDreams)

Registered in `~/.config/opencode/opencode.json` as the `searxng` MCP server:

- **Tool**: `searxng_web_search` — general web search with configurable categories, language, max results
- **Tool**: `searxng_search_images` — image search
- **Tool**: `searxng_search_news` — news search
- **Server**: `scripts/searxng-mcp-server.py` — zero-dependency Python, implements JSON-RPC over stdio
- **URL**: `https://search.example.com` (via VIP .99 → Traefik)

### Open WebUI (milis-wonderspace)

Configured via environment variables in `compose/milis-wonderspace.yml`:

```yaml
WEBUI_SEARCH_ENGINE: "searxng"
SEARXNG_QUERY_URL: "http://192.168.50.129:8080/search"
```

Provides web search grounding for RAG queries. The SearXNG internal endpoint is accessed via LAN IP (cross-node).

### Hermes (heavensfeel)

MCP server registered in `~/.hermes/config.yaml`:

```yaml
mcp_servers:
  searxng:
    command: python3
    args:
    - /home/user/searxng-mcp-server.py
    env:
      SEARXNG_BASE_URL: "https://search.example.com"
```

Uses the public `search.example.com` URL because the MCP runs on the host (not in Docker), so the container-internal `searxng:8080` hostname is unresolvable. (Changed from `http://searxng:8080` on 2026-08-04.)

### Homepage

Bookmark added to `/DATA/Apps/homepage/services.yaml`:

```yaml
- SearXNG:
    icon: mdi-search-web
    href: https://search.example.com
    description: Self-hosted search engine
    server: heavensfeel
    container: searxng
```

### n8n

SearXNG has a built-in n8n node. Add it to any workflow using `https://search.example.com` as the base URL.

## JSON API

```
GET /search?q=<query>&format=json&language=en-US&categories=general&pageno=1
```

Returns structured JSON with `results[]`, `answers[]`, `infoboxes[]`, `suggestions[]`. Each result includes `title`, `url`, `content`, `engine`, `publishedDate`, `thumbnail`, `img_src`.

## MCP Server

`scripts/searxng-mcp-server.py` is a zero-dependency Python JSON-RPC server implementing the Model Context Protocol over stdio. Used by both OpenCode and Hermes.

**Environment variables:**
- `SEARXNG_BASE_URL` — defaults to `https://search.example.com` (external) or `http://searxng:8080` (internal)

## Traefik Route

`standalone.yml` router:

```yaml
searxng:
  entryPoints: [websecure]
  rule: "Host(`search.example.com`)"
  service: searxng
  tls: { certResolver: le }
```

## Engine stats & monitoring

The stats page at `https://search.example.com/stats` shows per-engine performance:

- **Response time** — median/P80/P95 for each engine
- **Result count** — how many results each engine typically returns
- **Reliability** — percentage of successful queries (engines below 80% should be investigated)

The JSON API returns unresponsive engines in the response: `curl -s "https://search.example.com/search?q=test&format=json" | jq '.unresponsive_engines'`.

## Firefox default search

SearXNG serves an OpenSearch description at `/opensearch.xml` with the title "Homelab Search". Firefox auto-detects this when you visit the instance.

To set as default:

1. Visit `https://search.example.com/` in Firefox
2. Click the search engine icon (magnifying glass) in the address bar — Firefox should offer to add "Homelab Search"
3. Go to Settings → Search → Default Search Engine → select **Homelab Search**

If auto-detection doesn't trigger, add manually via Settings → Search → Add Search Engine:
- **Name**: `Homelab Search`
- **URL**: `https://search.example.com/search?q=%s`

## Custom Bangs (`!!shortcut`)

SearXNG supports DuckDuckGo-style external bangs — type `!!<bang> <query>` in the search bar to redirect directly to a service's search page. Custom homelab bangs are merged into the DuckDuckGo bang database at deploy time.

### Available homelab bangs

| Bang | Service | Redirects to |
|------|---------|-------------|
| `!!jf` / `!!jellyfin` | Jellyfin | `jellyfin.example.com/web/#!/search.html?query=` |
| `!!son` / `!!sonarr` | Sonarr | `sonarr.example.com/search?q=` |
| `!!rad` / `!!radarr` | Radarr | `radarr.example.com/search?q=` |
| `!!lid` / `!!lidarr` | Lidarr | `lidarr.example.com/search?q=` |
| `!!navi` / `!!navidrome` | Navidrome | `navi.example.com/search?q=` |
| `!!immich` | Immich | `immich.example.com/search?query=` |
| `!!komga` | Komga | `komga.example.com/search?query=` |
| `!!prowlarr` | Prowlarr | `prowlarr.example.com/search?query=` |
| `!!bazarr` | Bazarr | `bazarr.example.com/search?q=` |
| `!!slskd` | slskd | `slskd.example.com/search?q=` |
| `!!n8n` | n8n | `n8n.example.com/search?q=` |
| `!!grafana` | Grafana | `grafana.example.com/search?q=` |
| `!!serr` / `!!jellyseerr` | Jellyseerr | `serr.example.com/search?q=` |

All 15,000+ DuckDuckGo bangs also continue to work (`!!gh`, `!!w`, `!!ddg`, etc.).

### How it works

SearXNG stores bang definitions in a trie at `/usr/local/searxng/searx/data/external_bangs.json`, synced from DuckDuckGo's [bang.js](https://duckduckgo.com/bang.js). Homelab bangs are pre-merged into this file at deploy time:

1. `scripts/homelab-bangs.json` defines custom bangs in DDG format (`t`, `u`, `r`)
2. `scripts/merge-homelab-bangs.py` merges them into `external_bangs.json`
3. The merged file is mounted at `/usr/local/searxng/searx/data/external_bangs.json:ro` via Docker bind mount
4. On container recreate, run `scripts/merge-homelab-bangs.py` to regenerate

### Re-generating merged bangs

```bash
# On WonderDreams (after updating scripts/homelab-bangs.json):
python3 scripts/merge-homelab-bangs.py

# Upload to heavensfeel:
scp /tmp/external_bangs_merged.json hserver:/DATA/Apps/searxng/config/external_bangs.json

# Restart the container:
ssh hserver
cd /DATA/Apps/searxng
docker compose -f compose.yml --env-file .env up -d
```

## Deployment

```bash
ssh hserver
cd /DATA/Apps/searxng
docker compose -f compose.yml --env-file .env pull
docker compose -f compose.yml --env-file .env up -d
```

### Updating settings

Settings are stored at `/DATA/Apps/searxng/config/settings.yml` (bind-mounted to `/etc/searxng/` inside the container). To update:

```bash
# Edit settings and apply without full recreate:
ssh hserver
docker exec -i searxng sh -c 'cat > /etc/searxng/settings.yml' < settings.yml
docker restart searxng
```

For persistent changes (surviving image updates), update the bind-mount source too:

```bash
# Sync container-level change back to host:
ssh hserver
docker exec searxng sh -c "cat /etc/searxng/settings.yml" | sudo tee /DATA/Apps/searxng/config/settings.yml > /dev/null
```

### Adding new bangs

1. Add an entry to `scripts/homelab-bangs.json` in DDG format (`t` = bang name, `u` = URL with `{{{s}}}`, `r` = rank)
2. Verify the target URL works: `curl -s -o /dev/null -w "%{http_code}" "https://service.example.com/search?q=test"`
3. Regenerate the merged bangs file on WonderDreams: `python3 scripts/merge-homelab-bangs.py`
4. Upload to heavensfeel: `scp /tmp/external_bangs_merged.json hserver:/DATA/Apps/searxng/config/external_bangs.json`
5. Restart: `ssh hserver "cd /DATA/Apps/searxng && docker compose -f compose.yml --env-file .env up -d"`

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Connection refused` on 192.168.50.129:8080 | No host port mapping; container only on overlay network | Use `search.example.com` instead, or add `ports: "8080:8080"` to compose |
| Engine timeouts in logs | Upstream engine rate-limiting the homelab IP | Disable the engine in settings.yml, or add more engine diversity |
| Slow search results | Too many engines queried in parallel | Reduce enabled engines to 3-4 fastest (DuckDuckGo, Google, Brave) |
| Redis connection error | searxng container on different network than redis | Verify both containers are on `traefik-overlay` (check with `docker inspect`) |
| Bang redirect not working (`!!jellyfin` doesn't redirect) | `external_bangs.json` bind mount missing or stale | Regenerate merged bangs and restart: `python3 scripts/merge-homelab-bangs.py && ssh hserver "docker compose -f /DATA/Apps/searxng/compose.yml up -d"` |
| `Permission denied` writing to /etc/searxng/ in container | Container lacks `DAC_OVERRIDE` capability | Ensure `cap_add: [DAC_OVERRIDE]` is in the compose file for the searxng service |
| Engine suspended / rate-limited (Brave: "too many requests") | Upstream engine throttling the homelab IP | Disable the engine in settings.yml; rate limits clear after a few hours |
| `radio browser` crash on init (`sqlite3.OperationalError: no such table`) | Bug in SearXNG 2026.5.31's radio_browser engine | Added `remove: true` for `radio browser` in settings.yml |
| `limiter.toml` warning in logs | Limiter disabled but config file doesn't exist | Run: `docker exec -i searxng sh -c 'cat > /etc/searxng/limiter.toml'` with empty content |
| Slow search (1.5s+) | Too many engines queried; some time out | Check `/stats` page for slow engines, disable them, reduce `search.max_engine_time` |

## See Also

- hermes — AI agent using SearXNG for search
- camofox — stealth browser used alongside SearXNG
- heavensfeel — server hosting the service
- traefik — reverse proxy routing `search.example.com`
