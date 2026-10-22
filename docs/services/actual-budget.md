# Actual Budget

**Host**: milkymiracle | **Port**: 5006 | **Domain**: `budget.example.com` — **internal only**
**Router**: `actual-budget` → `http://actual-budget:5006`

## Overview

[Actual Budget](https://actualbudget.org/) is the budgeting surface over the
[money-map](money-map.md) dataset. The server is `actualbudget/actual-server`, storing its data in a
`data/` subdirectory of `/DATA/Apps/actual/` — deliberately a subdirectory, so an abandoned
earlier install one level up is left untouched rather than adopted.

## Why a bridge instead of Actual's own sync

Actual can sync SimpleFIN itself, but that **restores history and balances while dropping every
category** — which is the whole reason money-map's categorisation rules exist. So money-map stays
the source of truth and a one-shot bridge pushes the register across, using `imported_id` as the
dedupe key: a repeated run imports nothing.

```
SimpleFIN → money-map (categories) → bridge → Actual (budget UI)
```

The bridge carries a compose `profile` (`bridge`), so `up -d` starts only the server:

```bash
docker compose -f /DATA/Apps/actual/docker-compose.yml --profile bridge run --rm actual-budget-bridge
```

The bridge's state directory (`/DATA/Apps/actual/bridge`) **must exist and be owned by uid 1000
before the first run** — Docker otherwise creates it root-owned, the container runs as `node`, and
it dies before printing anything, which reads like a silent no-op.

## Deployment

- `compose/apps/actual-budget.yml`
- Daily bridge from `scripts/actual-budget-bridge.{service,timer}` at 05:55 — ten minutes after
  money-map's 05:45 sync has pulled the day's transactions. Idempotent, so a missed run is skipped.
- Secrets (`ACTUAL_PASSWORD`, `ACTUAL_SYNC_ID`, the money-map service credentials) live in
  `.env` files on the host, never in this repo.

## Network

Internal-only: no Cloudflare record, no rate-limit middleware (this repo's convention for
internal routers). The data is personal finance — do not expose it.
