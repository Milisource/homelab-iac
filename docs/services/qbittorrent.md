# qBittorrent

**Host**: milis-wonderspace | **Port**: 8090
**Domain**: qbt.example.com | **Traefik**: routed through Gluetun VPN

## Architecture

```
Traefik (milkymiracle replica, via VIP)
  │
  ▼ (traefik-overlay → direct host IP 192.168.50.115:8090)
Gluetun VPN container (PIA, Montreal)
  │  network_mode: shared
  ▼
qBittorrent container
  │  network_mode: "service:gluetun"
  ▼
/mnt/network/Torrents/ (downloads on mergerFS pool)
```

qBittorrent shares Gluetun's network stack. All traffic routes through the PIA VPN tunnel.

## Network

- Uses Gluetun's network namespace (`network_mode: service:gluetun`)
- Torrenting port: 6881
- Web UI port: 8090
- Traefik routes `qbt.example.com` → `192.168.50.115:8090` (direct host IP — the web UI
  is only reachable from within the VPN namespace, so the router bypasses overlay DNS)

## Volumes

| Host | Container |
|------|-----------|
| /mnt/network/Torrents | /downloads |
| /DATA/Net (qBittorrent config) | /config |

## Image: qBittorrent Enhanced Edition

A custom `qbittorrent-ee:latest` image exists locally (229MB, built 2026-05-31). It layers the
[c0re100/qBittorrent-Enhanced-Edition](https://github.com/c0re100/qBittorrent-Enhanced-Edition)
(`release-5.2.1.10`) static binary over the stock linuxserver base.

**Build:**
```bash
docker build \
  --build-arg EE_VERSION=release-5.2.1.10 \
  -t qbittorrent-ee:latest \
  -f- . <<'DOCKERFILE'
FROM linuxserver/qbittorrent:latest
ARG EE_VERSION
ARG TARGETARCH
RUN case "$(uname -m)" in \
      x86_64) arch=x86_64 ;; \
      aarch64) arch=aarch64 ;; \
    esac && \
    apk add --no-cache curl unzip && \
    curl -fsSL \
      "https://github.com/c0re100/qBittorrent-Enhanced-Edition/releases/download/${EE_VERSION}/qbittorrent-enhanced-nox_${arch}-linux-musl_static.zip" \
      -o /tmp/qbittorrent-ee.zip && \
    unzip -o /tmp/qbittorrent-ee.zip -d /app/ && \
    chmod +x /app/qbittorrent-nox && \
    apk del curl unzip && \
    rm -rf /tmp/*
DOCKERFILE
```

**Status (2026-06-01):** Switched to `qbittorrent-ee:latest` in compose. s6 fix re-applied after swap.

### 2026-05-31 s6 Supervisor Fix

After the full-cluster reboot, qBittorrent's s6 service entered a restart loop. Root cause: the s6 run
script didn't pass `--confirm-legal-notice`, so the qBittorrent binary printed the legal banner and
exited before the `s6-notifyoncheck` readiness probe could succeed. The probe itself used
`nc -z 0.0.0.0 8090` which can't connect to 0.0.0.0 as a target, compounding the issue.

**Fix applied to running container's runtime copy** (`/run/s6-rc/servicedirs/svc-qbittorrent/run`):
```
#!/usr/bin/with-contenv bash
exec s6-setuidgid abc /app/qbittorrent-nox --webui-port=8090 --profile=/config --confirm-legal-notice
```
The source template (`/etc/s6-overlay/s6-rc.d/svc-qbittorrent/run`) was also updated.
**Note:** This is ephemeral — container recreation will restore the stock run script.
When switching to the EE image you'll need to test whether EE's binary also exhibits this behavior,
and if so, rebuild the image with the patched run script included in `root/`.

## Configuration

- User: 1000:1000 (user)
- WEBUI_PORT: 8090
- TZ: America/New_York
- Web UI auth credentials stored in Docker secret `QBT_WEBUI_PASSWORD`
