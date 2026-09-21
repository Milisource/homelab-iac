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
