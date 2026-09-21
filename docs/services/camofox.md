# Camofox Browser

**Host**: heavensfeel | **Port**: 9377
**Domain**: none (internal API)

## Overview

Camofox is a stealth headless browser server for AI agents. Wraps [Camoufox](https://camoufox.com) — a Firefox fork with C++ fingerprint spoofing — behind a REST API with element refs, accessibility snapshots, and search macros.

Used by Hermes for anti-detection browsing: bypasses Cloudflare, bot detection, and anti-scraping that blocks standard Playwright/Chromium.

## Configuration

| Setting | Value |
|---------|-------|
| Container | camofox |
| API port | 9377 |
| Data dir | /DATA/Apps/camofox (profiles, cookies, traces) |
| VNC port | 6080 (noVNC, disabled by default) |
| Image | Built locally from [jo-inc/camofox-browser](https://github.com/jo-inc/camofox-browser) |
| Node heap | 512MB (MAX_OLD_SPACE_SIZE) |

## How it works

Camoufox patches Firefox at the C++ implementation level — `navigator.hardwareConcurrency`, WebGL renderers, AudioContext, screen geometry, WebRTC — before JavaScript ever sees them. No shims, no wrappers, no tells.

Camofox wraps this in a REST API:
- `POST /tabs` — create a browsing session
- `GET /tabs/:id/snapshot` — accessibility tree with stable element refs
- `POST /tabs/:id/click` — interact by element ref
- `POST /tabs/:id/type` — fill forms

## Integration

Hermes connects automatically when `CAMOFOX_URL=http://192.168.50.129:9377` is set in `~/.hermes/.env`. All browser tools (navigate, click, type, snapshot) route through Camofox instead of Playwright.

## Build

Built from source since no pre-built image exists. The Dockerfile downloads Camoufox at build time.

```bash
cd /home/user/docker/build/camofox
git clone https://github.com/jo-inc/camofox-browser.git .
docker compose -f /home/user/docker/compose/heavensfeel.yml build camofox
```

## Swarm

Not deployed to swarm — standalone container on heavensfeel. Internal API only, no Traefik route.
