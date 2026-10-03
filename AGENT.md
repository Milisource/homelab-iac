# Agent Instructions — Homelab IaC

Public Infrastructure-as-Code repo for a 3-node Docker Swarm homelab cluster.

## Structure

| Path | Contents |
|------|----------|
| `compose/nodes/` | Per-node compose files (milis-wonderspace, milkymiracle, heavensfeel) |
| `compose/stacks/` | Swarm stack files (traefik, infra, cockpit) |
| `compose/apps/` | Standalone apps (searxng, job-ops) |
| `ansible/` | Ansible layer (inventory, group_vars, playbooks — audit + deploy) |
| `traefik/dynamic/` | Traefik dynamic router/middleware configs |
| `monitoring/dashboards/` | Grafana dashboard JSON definitions |
| `scripts/` | Operational scripts (SMART health, stale mount recovery, etc.) |
| `docs/` | Architecture, network, monitoring, storage, servers, services, flows docs |

## Sanitization Rules

- **Domains**: `example.com` — never the real registered domain
- **IPs**: Keep `192.168.50.x` (RFC1918) — these are architecture-relevant
- **Secrets**: Always use `${VARIABLE}` placeholders, never hardcode
- **Paths**: Use `/home/user/` instead of the real home path
- **Usernames**: Use `user` instead of the real username

### Known limitation — sanitized paths are not deployable

`/home/user/` is safe for *documentation*, but **not** for paths that are
actually consumed by a deploy. The public mirror contains functional
bind-mount sources such as `compose/nodes/heavensfeel.yml`:

```yaml
  borg-repo:
    volumes:
      - /home/user/borg-repos:/repos      # does not exist on the real host
```

On the live hosts the real path is under the operator's home directory, and
`/home/user` does not exist. Deploying the public mirror as-is would mount a
missing source (and the same applies to the `docker/build/*` build contexts),
so **deploys must come from the private repo** (`Milisource/homelab`, the
control-node clone — `/home/user/homelab` in these docs), where the paths are
real. The public mirror is for reference and review.

## Key Decisions (documented in README)

- Docker Swarm over K8s (simpler for 3-node cluster)
- Traefik over nginx/caddy (Docker + Swarm provider support)
- NFS over Ceph/GlusterFS (3 nodes don't need distributed storage)
- mergerFS over ZFS (JBOD with no parity — content is replaceable)

## Before Publishing

1. Extract live configs: traefik static config, prometheus.yml, keepalived.conf
2. Add service docs from `Homelab/services/` in the Compendium
3. ~~Add CI (YAML lint + compose validation)~~ — done (`.github/workflows/ci.yml`)
4. Verify zero secrets in git history

## Source of Truth

Live infrastructure docs are at `~/Documents/The Compendium/Homelab/`. This repo is a
sanitized public subset. If adding new files, write both the sanitized public version
and update the internal docs.
