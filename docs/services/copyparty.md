# CopyParty (File Sharing)

**Host**: milis-wonderspace | **Domain**: [cloud.example.com](https://cloud.example.com)

## Overview

CopyParty is a lightweight, dependency-free file sharing web server. It serves the entire mergerFS pool and is used for one-off file sharing both inside the LAN and with external contacts.

## Configuration

| Setting | Value |
|---------|-------|
| Container | copyparty |
| Image | copyparty/ac:latest |
| Served path | `/root` → `/mnt/network` (whole mergerFS pool) |
| Config | `/DATA/Apps/Copyparty/` |
| Entrypoint | `python3 -m copyparty -c /z/initcfg` |
| Flags | `--xff-src=10.0.0.0/16`, `--rproxy=1` (reverse-proxy aware) |
| Allocator | mimalloc (`LD_PRELOAD=/usr/lib/libmimalloc-secure.so.2`) |
| Network | traefik-overlay |

## Traefik Route

`infra/traefik/dynamic/standalone.yml`:

- `copyparty` — Host(`cloud.example.com`) → `http://copyparty:3923` (TLS via LE)

## Notes

- Serves the full `/mnt/network` pool — be careful what you link/share externally
- Runs on the storage node (milis-wonderspace) so it reads directly from the pool — no NFS round-trip
- The root volume is not anonymous-readable: anonymous `GET /` returns **403** by design

## Monitoring

The uptime monitor was a permanent false positive until 2026-10-21 — it accepted only `200-299`
while the auth wall returned 401/403 to anonymous probes. It now authenticates with HTTP Basic as
a dedicated **`monitor`** account holding `r` on `/` only (read/list, no write). The auth wall was
not weakened. If `[accounts]` or the root `r:` line in `copyparty.conf` is rewritten, keep
`monitor` or the check goes red again.
