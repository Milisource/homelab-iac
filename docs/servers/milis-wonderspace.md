# milis-wonderspace

**IP**: 192.168.50.115 | **Role**: Storage & Downloads
**OS**: Ubuntu 24.04 LTS | **CPU**: Intel Kaby Lake (8 cores) | **RAM**: 16GB

## Hardware

Dell Inspiron 3668 with H110 chipset (4 SATA ports). All 5 data drives are in a
Yottamaster PS500RU3 USB 3.0 enclosure connected via a JMS578 bridge chip.

## Services

| Service | Type | Purpose |
|---------|------|---------|
| mergerFS | Pool | JBOD pool of 5 drives → `/mnt/network` (29TB) |
| NFS server | Export | Shares `/mnt/network` and `/DATA` to LAN |
| Gluetun | Docker | VPN gateway (PIA) for the download client |
| qBittorrent | Docker | Download client (shares Gluetun's network namespace) |
| *Arr suite | Docker | Radarr, Sonarr, Lidarr, Prowlarr, Bazarr, Cleanuparr |
| Navidrome | Docker | Music streaming |
| Komga | Docker | Comic/manga/e-book reader |
| slskd | Docker | Soulseek client |
| CopyParty | Docker | Web file sharing over the mergerFS pool |
| ArchiveBox | Docker | Self-hosted web archiving |
| Borgmatic | Docker | Daily encrypted backups to an off-site repo |

> Vaultwarden and n8n run on heavensfeel, not here — they were moved off this node.

## Storage

All 5 USB drives merged via mergerFS. Files are distributed across disks using
`epmfs` policy (existing path, most free space). See `docs/storage/overview.md`.
