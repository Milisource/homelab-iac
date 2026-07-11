# Media Pipeline

## Flow: Download to Playback

```
Indexer (Prowlarr)
  │
  ├── IRC announce → autobrr (qui) → Download Client
  └── Manual search → *Arr app → Download Client
                              │
                              ▼
                    /mnt/network/Torrents/
                    ├── Movies/
                    ├── TV Shows/
                    ├── Music/
                    ├── Anime/
                    └── Books/ (Comics, Manga, Artbooks)
                              │
                              ▼
                    *Arr (post-processing, rename, organize)
                    Radarr (Movies)
                    Sonarr (TV Shows)
                    Lidarr (Music)
                              │
                              ▼
                    /mnt/network/Torrents/
                    (organized library paths)
                              │
                              ▼
                    Media Servers:
                    ├── Jellyfin (Movies, TV, Anime) → clients
                    ├── Navidrome (Music)
                    ├── Komga (Comics/Manga)
                    └── Kavita (Books/Ebooks)
```

## Request Flow

```
User Request
  │
  ▼
jellyseerr (serr.example.com)
  │
  ▼
Radarr / Sonarr (automatic search)
  │
  ▼
Download Client
  │
  ▼
Post-processing → Library update
  │
  ▼
Available in Jellyfin/Navidrome
```

## Subtitle Flow

Bazarr watches Radarr/Sonarr libraries and automatically downloads subtitles
for all media.

## Key Details

- Download Client runs with its traffic isolated through a VPN gateway
- All paths on milis-wonderspace (or via NFS on milkymiracle)
