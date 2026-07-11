# CrowdSec

CrowdSec is an open-source, collaborative IPS (Intrusion Prevention System). It detects
malicious behavior, shares threat data via a community blocklist, and blocks attackers at
multiple layers.

## Architecture

```
Request ──► Traefik ──► CrowdSec Bouncer (forwardAuth) ──► Backend Service
                              │
                              ▼
                        CrowdSec LAPI
                        ├── Scenarios (attack patterns)
                        ├── Community blocklist (18k+ IPs)
                        └── Local decisions (ssh bf, http probes, CVEs)
                              │
                              ▼
                        Firewall Bouncer (nftables)
                        └── Blocks at network level (INPUT/FORWARD chains)
```

Two enforcement layers:
1. **Traefik bouncer** — HTTP-level: returns 403 before request reaches your app
2. **Firewall bouncer** — Network-level: drops packets at the kernel level

## Collections & Scenarios

| Collection | Purpose |
|------------|---------|
| `crowdsecurity/linux` | Linux system log parsing |
| `crowdsecurity/sshd` | SSH bruteforce detection |
| `crowdsecurity/traefik` | Traefik access log parsing |
| `crowdsecurity/http-cve` | 20+ CVE exploit detection (Log4j, Spring4Shell, etc.) |
| `crowdsecurity/base-http-scenarios` | Generic HTTP attacks (SQLi, XSS, path traversal, admin probing, bad user agents) |
| `crowdsecurity/whitelist-good-actors` | Allow known good IPs (CDNs, crawlers) |

## Traefik Bouncer

Deployed as a Docker Swarm service:

```yaml
crowdsec-bouncer:
  image: fbonalair/traefik-crowdsec-bouncer:latest
  environment:
    CROWDSEC_AGENT_HOST: "${CROWDSEC_AGENT_HOST}"
    CROWDSEC_BOUNCER_API_KEY: "${CROWDSEC_BOUNCER_API_KEY}"
    PORT: "7070"
    GIN_MODE: release
  networks:
    - traefik-public
```

Middleware applied to all routers via `traefik/dynamic/dynamic.yml`:

```yaml
crowdsec-bouncer:
  forwardAuth:
    address: "http://crowdsec-bouncer:7070/api/v1/forwardAuth"
    trustForwardHeader: true
    authResponseHeaders:
      - X-CrowdSec-Remote-IP
```

## CLI Cheatsheet

```bash
# View metrics
sudo cscli metrics

# List alerts
sudo cscli alerts list

# List active bans
sudo cscli decisions list

# Manually ban an IP
sudo cscli decisions add --ip 1.2.3.4

# Manually remove a ban
sudo cscli decisions delete --ip 1.2.3.4

# List bouncers
sudo cscli bouncers list

# List installed collections
sudo cscli collections list

# Reload after config changes
sudo systemctl reload crowdsec
```

## Notes

- Config owned by root:600 — use sudo for all cscli commands
- Community blocklist updated every ~2 hours via CAPI
- No console web UI configured (CLI-only management)
