# Improvements & Known Issues

> **Planned work lives in v2-roadmap** (Ansible depth, CI evolution, security backlog, platform expansion). This page is the living backlog — items get struck through here as they close; the roadmap sequences them.

## Resolved

| Issue | Resolution |
|-------|------------|
| **spotify-tokener unhealthy** | Health check used `nc` which wasn't installed in the container. Changed to `timeout 1 bash -c 'echo > /dev/tcp/localhost/49152'`. Container now healthy. |
| **Plaintext passwords in old apps.yml** | Sanitized `/home/user/docker/apps.yml` — replaced `ADMIN_TOKEN=monkeypenis`, `FOUNDRY_PASSWORD=...`, and `FOUNDRY_ADMIN_KEY=password!` with placeholders. |
| **2026-05-16: USB enclosure brownout → cascade failure** | Orico PSU brownout corrupted GPT on WD Red 6TB (disk2). Reformatted, new UUID `088be75c-...`, updated fstab. |
| **2026-05-16: NFS `soft` mode → stale file handles → load 3376** | Switched both NFS clients to `hard,bg`. Processes now wait for NFS recovery instead of getting stale handles. |
| **2026-05-16: Duplicate USB mounts after enclosure reset** | Deployed `cleanup-stale-mounts` script + systemd timer (every 30min) — unmounts stale `/dev/sdX` devices that don't match fstab UUID. |
| **2026-05-16: USB autosuspend still enabled** | Added `61-usb-disable-autosuspend.rules` — prevents kernel from suspending the JMicron bridge. |
| **2026-05-16: Jellyseerr 502 via Traefik** | Container was on `bridge` network, not `traefik-public`. Connected to correct network with DNS alias. |
| **2026-05-16: Jellyfin shows 64 movies** | NFS mount dropped, stale file handles. Restarted after NFS recovery + library scan. Disabled broken Streamyfin plugin. |
| **2026-05-16: heavensfeel NIC drops** | Bad ethernet cable — only negotiating 100Mbps. Replaced cable → gigabit restored. |
| **2026-05-16: SSH fails to start after reboot** | `ListenAddress` in sshd config binds to specific IPs, but service starts before network has them. Added `After=network-online.target` override to `ssh.service` on all nodes. |
| **2026-05-27: Orico enclosure → Yottamaster PS500RU3** | Failed Orico JMS567 5-bay (backplane thermal dropout) retired. Replaced with Yottamaster PS500RU3 (JMS578 bridge). USB 3.0 confirmed working (204 MB/s reads). |
| **2026-08-01: CrowdSec Traefik bouncer retired** | The `crowdsec-bouncer` Docker forwardAuth service removed — enforcement is now native `crowdsec-firewall-bouncer` (nftables) on all 3 nodes. |
| **2026-08-15: eserver traefik dir root-owned** | `/etc/traefik/dynamic` on milkymiracle was root-owned (other nodes user-owned) — would have broken the Ansible traefik sync on the next config change. Fixed with `sudo chown user:user /etc/traefik/dynamic`. |

## Critical / High Priority

| Issue | Severity | Details |
|-------|----------|---------|
| ~~steamserver offline~~ | ~~High~~ | ~~192.168.50.145 unreachable — machine powered off permanently. Removed from docs.~~ |
| No off-site backups | **Resolved 2026-08-11 + fixed 2026-08-15** — borgmatic now targets `ssh://user@192.168.50.129/repos/homelab` (heavensfeel, borg serve in the `borg-repo` container via restricted forced command). Aug 11 session missed the ssh key volume mount → every cron silently failed; mount added + repo re-initialized encrypted (repokey-blake2) + first backup verified 2026-08-15. Remaining: restore drill + Immich photos excluded. |
| ~~Quorum~~ | ~~High~~ | ~~2-node swarm has no quorum if manager fails.~~ **Resolved** |
| ~~Immich not behind Traefik~~ | ~~Medium~~ | **Resolved 2026-08-01** — now at immich.example.com (router added) |
| ~~USB 2.0 bottleneck~~ | ~~Medium~~ | **Resolved 2026-05-27** — connected at USB 3.0 (5Gbps), 204 MB/s reads |

## Medium Priority

| Issue | Details |
|-------|---------|
| ~~No monitoring/alerts~~ | ~~Uptime, disk space, or service health tracking~~ | **Resolved** — CrowdSec provides IPS monitoring across all 3 nodes with Traefik bouncer, firewall bouncer, and community blocklist (18k+ IPs). Still missing: uptime/disk monitoring (Grafana). |
| **Vaultwarden still uses plaintext token** | Live `apps_vaultwarden` service uses `ADMIN_TOKEN=monkeypenis` from old config. The Docker Swarm Stacks file (`/home/user/docker/Stacks/apps.yml`) defines it as a Docker secret, but the live stack was never redeployed from that file. Needs `docker stack deploy -c Stacks/apps.yml apps` to switch to secrets. |
| **No disaster recovery plan** | No tested procedure for node failure |
| **Tailscale DNS warning** | Non-critical cosmetic issue — resolvconf tries to reference `tailscale` interface but the interface is `tailscale0`. DNS actually works fine via MagicDNS. |
| ~~**Config drift**~~ | **Resolved for v1 scope (2026-08-15)** — Ansible layer live: per-node compose + traefik dynamic configs converged from the repo (`ansible/playbooks/deploy.yml`), drift-detection + convergence proven. Remaining (systemd units/timers, sudoers, NFS/fstab, swarm-stack reconciliation) is sequenced in **v2-roadmap**. |
| ~~**No CI/CD**~~ | ~~No automated deployment pipeline for stack updates~~ | **Resolved (2026-08-15)** — `homelab-iac` GitHub Actions: yamllint, ansible-lint, compose `config -q` validation, Trivy image scan (CRITICAL gate + HIGH trend + weekly cron). Deploy half: `ansible-playbook playbooks/deploy.yml` (manual trigger until a self-hosted runner or runner-on-tailnet is added). **Control node moved to heavensfeel 2026-09-21** (always-on; the vault stays the authoring copy and `scripts/publish-to-control.sh` syncs the deploy set) — an always-on host was the precondition for automating the deploy half. |

## Improvements

### Storage
- [ ] **Backup strategy**: Implement automated off-site backups for critical data (Vaultwarden, databases, Docker volumes)
- [x] **Local backup**: Borgmatic deployed on milis-wonderspace — versioned/encrypted backups of /DATA/ to local repo (2026-05-27)
- [ ] **Disk monitoring**: Set up SMART monitoring alerts (requires sudo — `sudo smartctl` works on all 5 ATA drives)
- [ ] **RAID vs mergerFS**: Consider if redundancy is needed (mergerFS has no parity)
- [ ] **Immich photos**: No backup of photo library

### Security
- [x] **Clean up old compose files**: Removed plaintext passwords from `/home/user/docker/apps.yml`
- [x] **Install CrowdSec on milis-wonderspace** (2026-05-08)
- [x] **Add Traefik bouncer** — forwardAuth on all 12 routers (2026-05-08)
- [x] **Add HTTP protection on heavensfeel** — Traefil log acquis + 57 HTTP scenarios (2026-05-08)
- [ ] **Immich behind Traefik**: Add Immich to `*.example.com`
- [ ] **Redeploy Vaultwarden with Docker secrets**: Live service still uses plaintext admin token
- [ ] **SSH security**: Review fail2ban config, consider SSH key-only auth
- [ ] **Network segmentation**: Review Docker network isolation

### Operations
- [ ] **Crontabs**: Set up automated maintenance tasks (log rotation, cleanup, backup)
- [x] **Monitoring stack**: Deploy Grafana + Prometheus + Loki on heavensfeel (2026-05-27)
- [x] **Multi-node management dashboard**: Deploy Cockpit as swarm global service (2026-05-29) — manage all 3 nodes via web UI at cockpit.example.com
- [ ] **Update strategy**: Document/automate Docker image update process
- [ ] **Immich updates**: Manual update process - automate via n8n
- [x] **Log management**: Centralized logging via Loki on heavensfeel + Promtail on all 3 nodes (2026-05-27)

### Reliability
- [ ] **Docker resource limits**: Some services lack CPU/memory limits
- [ ] **Health checks**: Not all services have health checks defined
- [x] **Quorum**: 2-node swarm has no quorum if manager fails — **Resolved** by adding heavensfeel as 3rd manager node
- [x] **USB enclosure PSU**: The Orico 5-bay PSU was the single point of failure for all storage. **Resolved 2026-05-27** — replaced with Yottamaster PS500RU3 (JMS578 bridge).
- [x] **Traefik HA**: Traefik now runs as a 3-replica Swarm service on all 3 nodes. Configs copied to server via helper container (2026-05-27).

### Documentation
- [ ] **Secrets inventory**: Document all Docker secrets and where they're used
- [ ] **Network diagram**: Create visual network topology diagram
- [ ] **Recovery runbook**: Document step-by-step node recovery procedures
- [ ] **Port inventory**: Full list of all exposed ports and their purposes

## Disk Inventory (milis-wonderspace) — Stale

Device names shift on USB re-enumeration. See Storage Overview for current UUID-keyed table.

| Device | Model | Size | Mount | Notes |
|--------|-------|------|-------|-------|
| sda | (OS drive) | 111.8G | / | SSD |

SMART data requires sudo — run `sudo smartctl -H /dev/sdX` on milis-wonderspace to check disk health.
