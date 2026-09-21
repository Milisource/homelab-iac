# slskd (Soulseek)

**Host**: milis-wonderspace | **Ports**: 5030-5031, 50300 | **Domain**: slskd.example.com

> Moved from milkymiracle to milis-wonderspace (data-locality — downloads land on mergerFS directly).

## Overview

Soulseek file sharing client for music discovery. Shares 144.5GB+ of music.

## Configuration

| Setting | Value |
|---------|-------|
| Username | user |
| Shared dir | /music → /mnt/network/Torrents/Music (read-only) |
| Downloads dir | /downloads → /mnt/network/Torrents/Soulseek Hell |
| Remote config | enabled |
| HTTP port | 5030 |
| HTTPS port | 5031 |
| SLSK listen port | 50300 |

## Health Check

- Runs every 60s with 1-hour start period (Soulseek is slow to connect)
- Command: `wget -q -O - http://localhost:5030/health`

## Storage

- Downloads go to `/mnt/network/Torrents/Soulseek Hell/`
- Shared music from `/mnt/network/Torrents/Music/`
- Config at `/DATA/Media/slskd/`
