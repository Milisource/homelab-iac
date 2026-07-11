# Traefik Reverse Proxy

**Swarm service**: `traefik` (2 replicas across manager nodes)
**Ports**: 80, 443, 8080

## Configuration

Static config is set via CLI args on the Swarm service. Dynamic config is in files:

| File | Purpose |
|------|---------|
| `traefik/dynamic/standalone.yml` | All service routers & backends |
| `traefik/dynamic/dashboard.yml` | Dashboard router + basic auth |
| `traefik/dynamic/dynamic.yml` | Shared middleware definitions |

**Path on each node**: `/etc/traefik/dynamic/`

### Syncing across nodes

The dynamic config directory is a local bind mount, not shared storage. After updating:

```bash
for f in standalone.yml dashboard.yml dynamic.yml; do
  scp node1:/etc/traefik/dynamic/$f node2:/etc/traefik/dynamic/$f
done
```

Traefik's file watcher picks up changes within seconds — no restart needed.

## Architecture

```
Request → Node:80/443 → Traefik
  → entrypoint middleware: crowdsec-bouncer → secure-headers
  → per-router middleware (rate-limit only where configured)
  → Backend service
```

Rate limiting (`average: 100, burst: 50`) is applied **per-router**, not at the entrypoint.
This prevents SPA static-asset bursts (50–150+ JS chunks on load) from triggering 429s:

- **Non-SPA services**: `middlewares: [rate-limit]` on the full host.
- **SPA services**: a dedicated API-path router with `rate-limit`, plus a catch-all router for static assets without it.

## Routed Services

All services defined in `traefik/dynamic/standalone.yml`. Each service gets a CNAME record in Cloudflare for public access, or uses the wildcard `*.example.com → 192.168.50.99` for local DNS.

### Backends with Self-Signed TLS

If the backend uses HTTPS with a self-signed cert, add a `serversTransport` with `insecureSkipVerify: true`:

```yaml
http:
  serversTransports:
    example-transport:
      insecureSkipVerify: true

  services:
    example:
      loadBalancer:
        servers:
          - url: "https://example:9090"
        serversTransport: example-transport
```

## Known Pitfalls

### Duplicate YAML mapping keys break the file provider

**Symptom:** Domains stop responding. Traefik logs `middleware "secure-headers@file" does not exist` and the file provider error: `yaml: unmarshal errors: mapping key "service" already defined at line N`.

**Root cause:** `standalone.yml` had duplicate router keys. YAML spec says duplicate mapping keys SHOULD produce an error; Traefik's parser rejects the entire file, causing the file provider to load **nothing**.

**Fix:** Remove the duplicate router block. The file watcher reloads automatically.

**Prevention:** Validate YAML before writing:

```bash
python3 -c "import yaml; yaml.safe_load(open('/etc/traefik/dynamic/standalone.yml'))"
```

## Dashboard

Access at `http://192.168.50.x:8080/dashboard/` — LAN/Tailscale only, not exposed via Cloudflare.

## Let's Encrypt

- DNS-01 challenge via Cloudflare API
- ACME email configured in `traefik/traefik.yml`
- Certs stored in `acme.json` on a Docker volume
