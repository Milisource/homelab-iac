# Cockpit — Multi-Node System Management Dashboard

**Deployment**: Native per-node (apt `cockpit` package) — one instance on each of the 3 nodes
**Access**: `https://cockpit.example.com` (internal-only, no Cloudflare proxying)
**DNS**: Local via AGH wildcard `*.example.com → 192.168.50.99`

> **2026-08-01 update:** Cockpit was originally deployed as a swarm global service
> (`cockpit_cockpit`), but that is no longer the case — it now runs **natively** on each node
> (`cockpit.socket`, ports 9090/9091) and is routed by Traefik directly to each node's IP.
> The old `compose/cockpit-stack.yml` is superseded by the native install.

## Overview

Cockpit is a web-based server management tool. Unlike Grafana (metrics/statistics), Cockpit is about **doing things** on the node — start/stop services, manage storage, view logs, open terminals, inspect system state.

Each session targets **one node** via the "Connect to" field on the login page. Switch between nodes by logging out and back in with a different IP.

## Login

Open `https://cockpit.example.com` and enter:

| Field | Value |
|-------|-------|
| Username | `user` |
| Password | your system password |
| Connect to | `192.168.50.115` (server), `.122` (eserver), or `.129` (hserver) |

Do **not** leave "Connect to" blank — the container's `127.0.0.1` doesn't reach the host's SSH.

SSH authentication is **key-only** (PasswordAuthentication is disabled on all nodes). The host's `~/.ssh/id_ed25519` is used for `cockpit-ssh` (libssh backend).

## Architecture

```
cockpit.example.com        (milis-wonderspace, 9090)
cockpite.example.com       (milkymiracle, 9090)
cockpith.example.com       (heavensfeel, 9091)
  │
  ▼
Traefik (replica on VIP holder) → https://<node-LAN-IP>:9090/9091
  │  (serversTransport insecureSkipVerify — self-signed cert)
  ▼
cockpit-ws on the target node → cockpit-bridge (local SSH)
```

- Traefik routers are **per-node** in `infra/traefik/dynamic/standalone.yml`
  (`cockpit-user` → 192.168.50.115:9090, `cockpit-eserver` → 192.168.50.122:9090,
  `cockpit-heaven` → 192.168.50.129:9091)
- `cockpit.socket` listens on 9090 (9091 on heavensfeel) via `systemd socket activation`
- No separate Traefik `serversTransport` needed if backend is plain HTTP — but Cockpit's
  container serves HTTPS with a self-signed cert, so `cockpit-transport`
  (`insecureSkipVerify: true`) is defined and used

## Prerequisites (per node)

```bash
sudo apt install -y cockpit-bridge cockpit-system cockpit-storaged cockpit-networkmanager
```

No daemon, no open ports — just the bridge client Cockpit talks to over SSH.

## Usage

1. Open `https://cockpit.example.com` (or the per-node host)
2. Enter `user`, your password, and a **Connect to** IP
3. Manage that node — services, storage, terminal, logs, network
4. To manage a different node: log out, re-enter with a different **Connect to**

## Failover

| Scenario | What happens |
|----------|-------------|
| Node dies | That node's cockpit-ws stops listening; Traefik route for its host fails but others still work. |
| VIP floats | Keepalived moves VIP → Traefik follows → unaffected. |

## Key Commands

```bash
systemctl status cockpit.socket        # socket activation on each node
systemctl restart cockpit-wsinstance-https@*  # restart cockpit web service
ss -tlnp | grep 9090                   # confirm listener
```
