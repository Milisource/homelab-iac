# Jellyfin

**Host**: milkymiracle | **Domain**: jellyfin.example.com

## Overview

Media server for Movies, TV Shows, and Anime. Runs on milkymiracle with GPU-accelerated transcoding.

## Hardware Transcoding

- Device: `/dev/dri` (Intel/AMD integrated GPU)
- Only available on milkymiracle (placement constraint)
- No explicit HW transcoding config found (uses default detection)

## Libraries

| Library | Path | Type |
|---------|------|------|
| Movies | /Movies → /mnt/network/Torrents/Movies | Movies |
| TV Shows | /TV → /mnt/network/Torrents/TV Shows | TV Shows |
| Anime | /Anime → /mnt/network/Torrents/Anime | TV Shows |

## Configuration

- Config: /DATA/Media/Jellyfin/JellyConfig
- User groups: 1000 (user), 44 (video), 107 (render) - for hardware transcoding access
- Additional library path mapping: /opt/vc/lib for VC4/VideoCore on Raspberry Pi (may be vestigial)

## Deployment

Standalone container (compose `milkymiracle.yml`), on `traefik-overlay`.
No direct port published (traffic goes through Traefik at `jellyfin.example.com`).
