# Ansible — Homelab Configuration Management

First Ansible layer for the 3-node Docker Swarm homelab
(milis-wonderspace / milkymiracle / heavensfeel).

## Why

- The repo is already the source of truth for compose + Traefik configs;
  this directory is the **apply** half of that GitOps loop.
- Audit-first: everything is idempotent and `--check`-friendly, so the
  same playbooks serve as drift audit and deploy path.
- Deliberately conservative v1: Ansible only owns what humans don't
  hand-tune (see "Out of scope v1" below).

## Layout

| Path | Purpose |
|---|---|
| `ansible.cfg` | Connection + defaults for this inventory |
| `inventory/homelab.yml` | Group definitions + per-host connection vars |
| `inventory/group_vars/all.yml` | Shared vars (timezone, paths, managed file lists) |
| `inventory/group_vars/<node>.yml` | Per-node role, service inventory, notes |
| `playbooks/site.yml` | Entrypoint: common state (audit/apply) |
| `playbooks/common.yml` | Idempotent node baseline (user, docker, dirs, timezone) |
| `playbooks/deploy.yml` | GitOps sync + `docker compose up -d` (explicit) |

## Quickstart

All commands run from inside `ansible/` (ansible.cfg paths are
cwd-relative):

    cd ansible

    # 1. Audit — dry run, touches nothing:
    ansible-playbook playbooks/site.yml --check

    # 2. Apply common state (user / dirs / timezone):
    ansible-playbook playbooks/site.yml

    # 3. Preview the deploy, then sync + deploy:
    ansible-playbook playbooks/deploy.yml --check
    ansible-playbook playbooks/deploy.yml

`deploy.yml` syncs `compose/nodes/<node>.yml` per host and
`traefik/dynamic/{standalone,dynamic}.yml` to all hosts, then runs
`docker compose -f <node>.yml up -d`. A timestamped `.bak` is kept on
every change for cheap rollback.

> This is the **sanitized public copy** — usernames, home paths, and
> domains are placeholders (`user`, `/home/user`, `example.com`). Replace
> every value with your own before running anything against real hosts.

## Managed in v1 (common.yml)

- User `user` present (`/bin/bash`, groups `sudo` + `docker`, appended
  only — passwords/keys untouched)
- `docker-ce` + `docker-compose-plugin` present (apt sources NOT managed;
  keys pre-exist from the hand setup)
- `/home/user/docker/compose/` exists
- `/etc/traefik/dynamic/` exists (user-owned subdir — no root escalation)
- Timezone `America/New_York` (plus apt: the only two privileged tasks,
  both no-ops when state is correct)

## Out of scope v1 (and why)

| Area | Why |
|---|---|
| sudoers whitelist | Hermes' watchdog monitors it — Ansible writing it would fight the agent and risk locking out automation |
| NFS (exports + client fstab) | Live-tuned around the dying USB enclosure; templatizing now would drift post-migration |
| systemd units/timers + cron | Hand-deployed and stable (sync-qbit-port, cleanup-stale-mounts, bump-recent-media-mtime, deadman-ping, lrc-sync, smart-health-check, ...) |
| nftables / firewall | CrowdSec firewall-bouncer owns the rules dynamically |
| unattended-upgrades / borgmatic | Host-specific, secret-adjacent config |
| swarm stacks (`traefik-stack.yml`, `infra.yml`, `cockpit-stack.yml`) | `docker stack deploy` from milkymiracle `/home/user/docker/Stacks/`; `infra.yml` + `cockpit-stack.yml` are retired/superseded anyway |
| `compose/apps/job-ops.yml`, `compose/apps/searxng.yml` | Live copies live elsewhere (`/home/user/job-ops/`, `/DATA/Apps/searxng/`) |
| `traefik/dynamic/dashboard.yml` | Embeds the basicAuth password hash — treated as a credential, synced by hand |

Rule of thumb: **if a human hand-tunes it on the node, Ansible does not
own it yet.**

## GitOps story

- CI (`.github/workflows/ci.yml`) lints this directory with `yamllint` +
  `ansible-lint`; `deploy.yml` is the only path from repo → live
  containers; `site.yml --check` gives the drift audit.
- Audit vs. deploy separation is intentional: `site.yml` never imports
  `deploy.yml`, so an audit run can never touch containers.
- No `.env` files, no `dashboard.yml`, no secrets live in this public
  mirror — the internal copy stays out of git.
