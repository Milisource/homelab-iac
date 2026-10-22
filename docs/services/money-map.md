# money-map (Finance Sync)

**Host**: milkymiracle | **Port**: 8080 | **Domain**: `money.example.com` — **internal only**
**Router**: `money-map` → `http://money-map:8080`

## Overview

A personal-finance pipeline: pulls transactions from a bank aggregator (SimpleFIN) into SQLite,
applies local categorisation rules, and serves a **read-only** query page. It is the data layer
under [Actual Budget](actual-budget.md) — the budgeting UI runs on top of it.

The container holds no state of its own; everything meaningful is mounted:

| Mount | Contents |
|---|---|
| `/data` | SQLite database + the claimed SimpleFIN credential |
| `/app/config` | Connectors and categorisation rules (read-only) |
| `/app/inbox` | Raw statements and exports for the maintenance importers (read-only) |

**Both config files must be mounted.** Without `categories.local.toml` a sync silently falls back
to the template rules and reclassifies every transaction.

## Deployment

- `compose/apps/money-map.yml`; built from `./app` rather than pulled from a registry.
- **Not managed by the Ansible deploy** — a standalone app, like SearXNG and Job Ops.
- Daily sync from `scripts/money-map-sync.{service,timer}` at 05:45, after the overnight backup
  jobs. It runs `docker exec money-map money-map sync`, so the venv, config and credential all stay
  inside the container. A sync is idempotent, so a missed run is safe to skip.

## Network

Internal-only by design: there is no Cloudflare record, so the host resolves only through the
AdGuard wildcard. Per this repo's convention, internal-only routers carry **no** rate-limit
middleware. Do not add a Cloudflare record for it.

The credential and rules live in `/DATA/Apps/money-map/.env` and `/DATA/Apps/money-map/config/` on
the host, never in this repo.
