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
| Download Client | Docker | Handles automated downloads with isolated network |
| VPN gateway | Docker | Routes traffic for isolated services |
| *Arr suite | Docker | Radarr, Sonarr, Lidarr, Prowlarr, Bazarr |
| Navidrome | Docker | Music streaming |
| Komga | Docker | Comic/manga/e-book reader |
| Vaultwarden | Docker | Password manager |
| n8n | Docker | Workflow automation |
| Borgmatic | System | Daily encrypted backups |

## Storage

All 5 USB drives merged via mergerFS. Files are distributed across disks using
`epmfs` policy (existing path, most free space). See `docs/storage/overview.md`.
