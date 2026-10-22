# milis-wonderspace (server)

**IP**: 192.168.50.115 | **Tailscale**: 100.x.x.x
**OS**: Ubuntu 24.04 LTS | **Kernel**: 6.17.0-generic
**CPU**: 8 cores | **RAM**: 31GB usable (32GB) | **Swap**: 4GB (742MB used)
**Docker Engine**: 29.6.1

## Role: Storage & Downloads Node

Primary storage server with all physical disks. Runs download clients and the "Arr" suite.

## Hardware

- **Model**: Custom tower — **Rosewill Helium NAS Max** (11× 3.5" bays). Rebuilt in 2026-10 from
  the original OEM desktop; see [Storage → USB migration](../storage/usb-migration.md) for the
  rationale and parts list.
  - **No OEM parts remain** — no proprietary PSU pinout, no 24→6 adapter, no USB bridge.
- **Motherboard**: Gigabyte GA-B250-HD3 (ATX, B250, 6× SATA, 4× DIMM)
- **Chipset**: Intel B250 (Kaby Lake native — no BIOS flash needed for the i7-7700)
- **CPU**: Intel Kaby Lake i7-7700 (4C/8T, 65W), integrated HD 630 graphics
- **RAM**: 32GB DDR4
- **PSU**: **Corsair RM750e 750W** — fully-modular, standard ATX 24-pin (+8-pin EPS), 7× SATA
  power. Replaces the 240W proprietary unit entirely; 750W is far above the 5-disk spin-up load
- **SATA**: 6 ports on-board (AHCI), **all 6 in use** — boot SSD + 5 HDDs, **native SATA**.
  No USB enclosure, no BOT bridge, no HBA
- **PCIe**:
  - 1× PCIe 3.0 x16 — empty
  - 1× PCIe 3.0 x4 — empty (future 10GbE/HBA)
  - 2× PCIe 3.0 x1 — empty
- **Internal drive bays**: 11× 3.5"; 5 in use + boot SSD on a 2.5"→3.5" bracket
- **NIC**: enp2s0 (Intel I219-V, gigabit, on-board). No WiFi card installed

## Users

| User | Purpose |
|------|---------|
| root | System admin |
| user | Primary user |
| demi | Secondary user |
| devmon | Disk monitoring (CasaOS) |

## Running Services (systemd)

| Service | Purpose |
|---------|---------|
| docker | Container runtime |
| containerd | Container runtime |
| tailscaled | Tailscale mesh VPN |
| unbound | Recursive DNS resolver |
| nfs-* | NFS server (exporting /mnt/network and /DATA) |
| smbd/nmbd | Samba file shares (CasaOS managed) |
| postfix | Mail transport (local only) |
| crowdsec + crowdsec-firewall-bouncer | IPS + nftables blocking |
| smartmontools | Disk health monitoring |
| ssh | SSH server |
| avahi-daemon | mDNS/Bonjour |
| keepalived | VIP 192.168.50.99 (priority 50, last resort) |
| fsidd | NFS FSID daemon |

### systemd timers (this node)

| Timer | Schedule | Purpose |
|-------|----------|---------|
| sync-qbit-port | every 2 min | Syncs Gluetun forwarded port → qBittorrent config, restarts it on change |
| detect-stale-network | every 5 min | Stale NFS handle detection |
| cleanup-stale-mounts | every 30 min | Cleans stale USB mount entries |
| bump-recent-media-mtime | every 1 min | Touches parent dirs of recently-written media (NFS readdir cache fix) |
| smart-health-check | weekly | SMART drive health |
| crowdsec-hubupdate | daily | CrowdSec hub/scenario updates |

### Cron (this node)

```
* * * * * /usr/local/bin/deadman-ping.sh 192.168.50.122 milkymiracle   # dead-man's switch on milkymiracle
0 4 * * 0 /home/user/scripts/lrc-sync.py                                # LRC lyrics sync (weekly)
```

## Docker Swarm Role: Manager (Reachable)

Part of the Docker Swarm. Manager node (not leader). Most media and apps services are constrained to run here.

### Swarm Containers on this node (global services)

| Container | Stack | Purpose |
|-----------|-------|---------|
| Traefik | traefik | Reverse proxy replica (ports 80, 443) |
| AdGuard Home | base-services | DNS filtering (global mode) |
| node-exporter | base-services | System metrics for Prometheus |
| promtail | base-services | Log shipping to Loki |
| cadvisor | base-services | Container metrics for Prometheus |
| portainer-agent | portainer-agent | Docker management agent |

### Standalone Containers (non-swarm)

| Container | Purpose |
|-----------|---------|
| qBittorrent | Torrent client (network: gluetun) |
| Gluetun | OpenVPN client (PIA, Montreal) |
| sonarr | TV show management |
| radarr | Movie management |
| lidarr | Music management |
| prowlarr | Indexer management |
| bazarr | Subtitle management |
| cleanuparr | Automatic media cleanup |
| Navidrome | Music streaming server |
| komga | Comics/manga/books reader (moved from milkymiracle) |
| slskd | Soulseek music sharing (moved from milkymiracle) |
| copyparty | File sharing/cloud |
| archivebox | Self-hosted web archiving (`archive.example.com`) |
| borgmatic | Automated backups of /DATA |
| docker-proxy | Read-only Docker API for Homepage |
| glances | System monitoring for Homepage |

> **Moved off this node:** n8n, vaultwarden, archisteamfarm, jellyseerr, byparr (→ heavensfeel).

## Storage

All application data lives at `/DATA/` and the mergerFS pool at `/mnt/network/`.
These are exported via NFS to milkymiracle and heavensfeel.

### NFS Client Compatibility

NFS exports work from Ubuntu 6.8.0 clients but **fail on CachyOS (kernel 7.0.10-1-cachyos)**:
- **NFSv4**: hangs in D-state (kernel regression — all versions)
- **NFSv3 + `/mnt/network`** (mergerfs FUSE): `mount(2): EIO` — FSINFO call causes nfsd+FUSE deadlock
- **NFSv3 + `/DATA`** (ext4): works fine

**Workaround on affected clients:** Use SSHFS instead (installed via `extra/sshfs`).

**WonderDreams setup** (`systemctl --user enable network-mount.service`):
- Uses `sshfs-mount.sh` wrapper that sources `~/.keychain/WonderDreams-sh` for the SSH agent
- Mounts `user@192.168.50.115:/mnt/network` at `/mnt/network` via systemd user service
- Enabled at boot via `loginctl enable-linger user`
- Key files:
  - Service: `~/.config/systemd/user/network-mount.service`
  - Wrapper: `~/.local/bin/sshfs-mount.sh`
- The `-f` flag is required to keep sshfs in the foreground (FUSE3 backgrounds by default)
- **Boot reliability (2026-06-16):** Keychain was only in `~/.bashrc`, so at boot the service found a stale agent. Moved `keychain --eval` to `~/.profile` so it runs on graphical login too. The service retries every 10s and picks up the refreshed agent automatically.

## Environment Variables

Minimal. No custom env vars in `/etc/environment`. Default Ubuntu 24.04 user env.

**Notable sysctl**: `net.ipv4.ip_forward = 1` (enabled for Docker)

## Tailscale (CRITICAL rule)

**This node MUST run `tailscale set --accept-routes=false`.**

milis-wonderspace is the Tailscale **subnet router** advertising `192.168.50.0/24`. If it *also* accepts routes (`--accept-routes=true`), it installs a Tailscale route for its own LAN subnet and starts sending intra-LAN traffic to the other swarm managers out via `tailscale0` (source IP `100.x.x.x`) instead of the LAN NIC. The other nodes reach it directly over the LAN, so the path becomes asymmetric and the swarm-manager Raft channel (TCP 2377) breaks → this node gets marked `Down`/`Unreachable` and its overlay endpoints stop reconciling cluster-wide. See the [2026-07-17 incident](../changelog.md#2026-07-17-milis-wonderspace-swarm-partition-tailscale-accept-routes).

Rule of thumb for the whole tailnet: **LAN-resident nodes → `accept-routes=false`; remote clients (laptop, phone, laptops) → `accept-routes=true`** (they need the subnet route to reach `192.168.50.x`).

Verify: `tailscale debug prefs | grep RouteAll` should show `false`, and `ip route get 192.168.50.122` should egress `dev enp2s0` (LAN), **not** `dev tailscale0`.

## Issues / Notes

- **Ansible-managed (2026-08-15):** `compose/milis-wonderspace.yml` (repo → `/home/user/docker/compose/`) and `/etc/traefik/dynamic/{standalone,dynamic}.yml` are converged by `ansible/playbooks/deploy.yml`. See ansible.
- swap is actively being used (742MB/4GB)
- Tailscale DNS health check warning (`--accept-dns=true` overwrites `/etc/resolv.conf` and the `unbound-resolvconf.service` helper fails because the interface is `tailscale0` not `tailscale`). Cosmetic — AdGuard/unbound DNS is unaffected. Set `--accept-dns=false` on this DNS-server node to silence it.
- SSH `ListenAddress` set to `192.168.50.115` + `100.x.x.x` via `/etc/ssh/sshd_config.d/10-hardening.conf` — caused boot failure on 2026-05-16 when sshd started before network had IPs. Fixed by systemd override: `After=network-online.target` in `/etc/systemd/system/ssh.service.d/override.conf`.
- Moving Off USB — migration plan to replace the dying 5-bay USB enclosure with native SATA/SAS.
- Stale mount cleanup runs every 30min via `cleanup-stale-mounts.timer` (remove after USB→SATA migration is complete).
- Docker compose stacks live at `/home/user/docker/compose/` (synced from this repo); historically also managed via Portainer agent.
