# Keepalived (VRRP VIP Failover)

**Installed on**: All nodes | **VIP**: `192.168.50.99` | **Protocol**: VRRP (virtual router id 50)

## Overview

Keepalived manages a floating virtual IP across all homelab nodes using VRRP. The VIP
provides a single stable endpoint for DNS and external HTTP/HTTPS traffic. If the node
holding the VIP goes down, another node takes over within seconds.

## Why

- **Router port forward**: Ports 80/443 forward to the VIP. If that node dies, keepalived
  moves the VIP and traffic flows again.
- **DHCP DNS**: The router hands out `.99` as the only DNS server. All AdGuard instances
  are available behind it.
- **Single point of entry**: The router has one IP to forward to, and it always reaches a
  healthy node.

## Architecture

```
Router (DHCP DNS + port forward 80/443)
  │
  ▼
192.168.50.99 (VIP — always on the healthiest node)
  │
  ├── milkymiracle (priority 150) — primary
  ├── heavensfeel (priority 100) — backup
  └── milis-wonderspace (priority 50) — last resort
```

### How VRRP works

1. The primary node (highest priority) holds `192.168.50.99` on its LAN interface
2. It sends VRRP advertisements (multicast `224.0.0.18`) every 1 second
3. Backup nodes listen for advertisements. If 3 are missed (~3s), the next-highest priority
   node claims the VIP by assigning `.99` to its own NIC and sending a gratuitous ARP
4. When the primary recovers, it preempts the VIP back after a 10-second delay (prevents
   flapping)

### Health check

A DNS health check runs every 2 seconds: `dig +short @127.0.0.1 localhost A` — verifies
AdGuard is answering DNS queries. The VIP only moves to nodes where this succeeds.

## Configuration

See `network/keepalived/` for per-node config files and the health check script.

### Per-node differences

| Node | Interface | Priority | Config File |
|------|-----------|----------|-------------|
| milkymiracle | eno1 | 150 | `network/keepalived/keepalived-eserver.conf` |
| heavensfeel | enp2s0 | 100 | `network/keepalived/keepalived-hserver.conf` |
| milis-wonderspace | enp2s0 | 50 | `network/keepalived/keepalived-server.conf` |

## Failover behavior

| Scenario | Who gets `.99` | Impact |
|----------|---------------|--------|
| All nodes up | Primary (prio 150) | Normal |
| Primary dies | Backup 1 (prio 100) within ~5s | DNS + Traefik continue |
| Primary + Backup 1 die | Backup 2 (prio 50) within ~5s | DNS continues |
| Single non-VIP node dies | No change | No impact |

## Maintenance

```bash
# Restart (graceful — sends priority-0 on shutdown)
sudo systemctl restart keepalived

# Check VIP location
ip addr show eno1 | grep 192.168.50.99

# View logs
sudo journalctl -u keepalived --no-pager -n 50
```

Look for `Entering MASTER STATE` or `Entering BACKUP STATE` to see VIP transitions.
