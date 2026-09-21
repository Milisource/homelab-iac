# Navidrome

**Host**: milis-wonderspace | **Port**: 4533
**Domain**: navi.example.com

## Overview

Navidrome is a self-hosted music streaming server, compatible with Subsonic API clients.

## Configuration

| Setting | Value |
|---------|-------|
| Music folder | /mnt/network/Torrents/Music |
| Data folder | /DATA/Media/Navidrome |
| Config file | /data/navidrome.toml |
| Image cache | 4GB |
| Transcoding cache | 8GB |
| Sharing | enabled |
| Auth request limit | 50 per 25s window |
| Base URL | https://navi.example.com |

## Last.fm Integration

Uses Docker secrets:
- `navidrome_lastfm_apikey` (external secret)
- `navidrome_lastfm_secret` (external secret)

## Traefik

Deployed as a standalone container (compose `milis-wonderspace.yml`), on `traefik-overlay`.
Traefik routes `navi.example.com` → navidrome:4533 via `infra/traefik/dynamic/standalone.yml`.

## Access

- Web UI: https://navi.example.com
- Subsonic API: https://navi.example.com (compatible with all Subsonic clients)
