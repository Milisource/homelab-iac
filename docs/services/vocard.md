# Vocard (Discord Music Bot Suite)

**Host**: milkymiracle

## Overview

Vocard is a Discord music bot with a web dashboard. Supports YouTube, Spotify, SoundCloud, and more.

## Stack

| Service | Image | Purpose |
|---------|-------|---------|
| vocard | ghcr.io/chocomeow/vocard:beta | Discord music bot |
| vocard-dashboard | ghcr.io/chocomeow/vocard-dashboard:latest | Web dashboard (port 8084) |
| vocard-db | mongo:8 | MongoDB database |
| lavalink | ghcr.io/lavalink-devs/lavalink:latest | Audio streaming node |
| spotify-tokener | ghcr.io/topi314/spotify-tokener:master | Spotify token service |
| yt-cipher | ghcr.io/kikkia/yt-cipher:master | YouTube cipher resolver |

## Network

All services on `vocard` network (bridge, milkymiracle only).

## Data Locations

- `/home/user/vocard/settings.json` - Bot config (includes Discord token, MongoDB, Lavalink)
- `/home/user/vocard/dashboard/settings.json` - Dashboard config (OAuth2, secret key)
- `/home/user/vocard/mongodb_data/` - MongoDB database
- `/home/user/vocard/lavalink/` - Lavalink config, plugins, logs
