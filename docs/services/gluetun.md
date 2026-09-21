# Gluetun (VPN)

**Host**: milis-wonderspace

## Overview

Gluetun is a VPN client container (PIA OpenVPN) that provides a network namespace for qBittorrent. All torrent traffic is routed through this VPN tunnel.

## VPN Configuration

| Setting | Value |
|---------|-------|
| Provider | Private Internet Access |
| Protocol | OpenVPN UDP |
| Region | ca montreal |
| Port forwarding | enabled |
| DNS | DoT via Cloudflare |
| Malicious blocking | enabled |

## Firewall

| Direction | Ports |
|-----------|-------|
| VPN input | 6881 (qBittorrent) |
| Input | 8090 (qBittorrent Web UI) |
| Outbound subnets | 192.168.0.0/16, 100.64.0.0/10, 172.16.0.0/12 |

## Exposed Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 6789 | TCP | Gluetun control/metrics |
| 6881 | TCP/UDP | qBittorrent DHT/tracking |
| 8090 | TCP | qBittorrent Web UI (via Traefik) |
| 8388 | TCP/UDP | Shadowsocks (PIA proxy) |
| 8888 | TCP | HTTP proxy |

## Network

Connected to `traefik-overlay` (external overlay — the old `vpn` overlay was removed).
qbittorrent shares gluetun's network namespace (`network_mode: service:gluetun`).
Traefik routes `qbt.example.com` → `192.168.50.115:8090` (direct host IP, since the
web UI is only reachable via the VPN namespace).

## Health

Health check every 5s via `/gluetun-entrypoint healthcheck`.

## Secrets

- `openvpn_user` (external Docker secret)
- `openvpn_password` (external Docker secret)

## Port Forwarding Sync

Gluetun's forwarded port is synced to qBittorrent by a systemd timer on milis-wonderspace:
`sync-qbit-port.timer` (every 2 min) runs `/usr/local/bin/sync-qbit-port`, which reads
`/tmp/gluetun/forwarded_port` and updates `Session\Port` in qBittorrent's config (restarting
qBittorrent on change). Log: `/var/log/qbit-port-sync.log`.
