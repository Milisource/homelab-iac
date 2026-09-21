# redlib-instances (Redlib instance list)

**Host**: heavensfeel (192.168.50.129) | **Port**: 8192 | **Domain**: none (internal only)

A tiny `nginx:alpine` container that serves a curated
[Redlib](https://github.com/redlib-org/redlib) instance list (`instances.json`) as static files.
It exists to feed the **ASFFreeGames** plugin on ArchiSteamFarm: Reddit/Redlib access is blocked or
rate-limited, so the plugin resolves a working instance from this list instead of hardcoding one.

## Configuration

| Item | Value |
|------|-------|
| Image | `nginx:alpine` |
| Compose file | `compose/apps/redlib-instances.yml` |
| Content | `/DATA/Apps/redlib-instances` (mounted read-only at `/usr/share/nginx/html`) |
| Port | `8192:80` |
| Consumer | ASF `freegames.json` → `redlibInstanceUrl: http://192.168.50.129:8192/instances.json` |

`instances.json` is seeded from
[redlib-org/redlib-instances](https://github.com/redlib-org/redlib-instances) and trimmed to a
short, reachable set (the official copy is kept alongside as `instances.json.official-backup`).

## Deployment note

This service runs as its **own compose project** (`redlib-instances.yml`), separate from the
`heavensfeel.yml` file that the Ansible deploy playbook converges. It is therefore **out-of-band**:
a deploy will not recreate it if it disappears. Treat it as a candidate for folding into the
per-node compose file.

It replaces an earlier Python proxy adapter that fronted a captcha-bypass browser on the same port.
