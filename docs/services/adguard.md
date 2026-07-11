# AdGuard Home

**Hosts**: All nodes (global mode) | **Ports**: 53 (DNS), 3020 (web), 8031 (HTTP redirect)

## Overview

AdGuard Home runs as a Swarm global service (one instance per node). Provides network-wide
ad blocking, DNS filtering, and DHCP server.

## Configuration

- Config: `/DATA/Net/adguard/conf/AdGuardHome.yaml`
- Work dir: `/DATA/Net/adguard/work/`
- Updates disabled (`--no-check-update`)

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 53 | TCP/UDP | DNS server |
| 67 | UDP | DHCP server |
| 3020 | TCP | Admin web UI |
| 8031 | TCP | HTTP redirect |
| 853 | UDP | DNS-over-TLS |
| 443 | UDP | DNS-over-HTTPS/QUIC |

## DNS Chain

```
Client → AdGuard (53) → Unbound (localhost:53) → Cloudflare DoT
```

## Notes

- Running in global mode — one instance on each Swarm node
- All instances share config via NFS from the storage node
