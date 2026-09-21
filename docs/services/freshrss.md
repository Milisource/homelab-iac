# FreshRSS

**Host**: heavensfeel | **Domain**: rss.example.com

## Overview

Self-hosted [FreshRSS](https://freshrss.github.io/FreshRSS/) — lightweight RSS/Atom feed aggregator with multi-user support, WebSub push, and web scraping. Deployed with SQLite (single user), auto-installed via the official `FRESHRSS_INSTALL`/`FRESHRSS_USER` env vars on first run.

## Configuration

| Setting | Value |
|---------|-------|
| Container | freshrss |
| Image | `freshrss/freshrss:edge` (rolling since 2026-08-15 — `:latest` was 3 months stale with CRITICAL PHP 8.4.21 CVEs: CVE-2026-17543 SQLi + CVE-2026-17544 RCE, caught by the homelab-iac Trivy gate; edge ships PHP 8.4.24) |
| Port | 80 (internal, overlay network only) |
| Feed refresh | `CRON_MIN=5,35` (every 30 min, in-container cron) |
| TZ | America/New_York |
| TRUSTED_PROXY | `172.16.0.0/12 192.168.0.0/16` (Docker overlay + LAN) |
| Data | `/DATA/Apps/freshrss/data` → `/var/www/FreshRSS/data` |
| Extensions | `/DATA/Apps/freshrss/extensions` |
| Logging | max-size 10m |
| Compose file | `/home/user/docker/compose/heavensfeel.yml` |

## Access

- Login: `https://rss.example.com` — user `admin`, password in hserver `/home/user/docker/compose/.env` → `FRESHRSS_ADMIN_PASSWORD`
- API enabled (`--api-enabled`), for use with mobile clients (FreshRSS API is compatible with Google Reader-ish clients)

## Route

Traefik router defined in `infra/traefik/dynamic/standalone.yml` (synced to all 3 nodes):

- `freshrss` — Host(`rss.example.com`), `middlewares: [rate-limit]` → `http://freshrss:80`
- LE cert issued automatically (verified 2026-08-15)

## Notes

- Add an Uptime Kuma monitor for `https://rss.example.com` (pending as of 2026-08-15).
- Default feed has ~10 articles actualized from initial install.
