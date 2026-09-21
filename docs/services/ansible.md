# Ansible

**Type**: Configuration management / IaC | **Control node**: heavensfeel (always-on) | **Authoring copy**: workstation vault | **Targets**: all 3 nodes

## Overview

Ansible is the **GitOps layer** for the homelab: the repo is the source of truth for per-node compose files and Traefik dynamic configs, and Ansible converges the live nodes to it. Agentless — nothing runs on the nodes; the control node SSHes in as `user` per task and disconnects.

**Two machines, two roles** (since 2026-09-21):

- **Authoring copy** — the Compendium vault on the workstation, under version control at the **private** `<private-iac-repo>`. Edits are made and committed here. It is *not* always on, and that is fine.
- **Control node** — **heavensfeel**, at `/home/user/homelab/` — a read-only deploy-key clone of that private repo. Playbooks are run here. Always on, so a deploy or a drift audit never depends on a desktop being awake.

> **Never push the vault to `homelab-iac`.** That repo is public *and*
> restructured (`compose/nodes/`, `docs/`, `/home/user/`); the vault is the real
> tree holding real values. They are two separate histories — the sanitized
> mirror is generated *from* the vault, and the `.gitignore` on the vault side is
> what keeps that boundary structural rather than a promise.

Note that Ansible is push-based: the control node runs no daemon and is never polled, so it only has to exist at the moment a playbook is invoked. The reason to place it on an always-on node is **automation** (scheduled audits, CI-triggered deploys) — not manual deploys.

Three commands cover the whole lifecycle (run from `ansible/` in the repo):

| Command | What it does |
|---------|--------------|
| `ansible-playbook playbooks/site.yml --check` | **Audit** — dry-run: confirms all 3 nodes match declared state, touches nothing |
| `ansible-playbook playbooks/site.yml` | **Apply** — converges the common guarantees (idempotent no-op when already correct) |
| `ansible-playbook playbooks/deploy.yml --check` | **Deploy preview** — shows exactly what would sync |
| `ansible-playbook playbooks/deploy.yml` | **Deploy** — syncs repo → nodes, then `docker compose up -d` per node |

## Control node setup (one-time) — heavensfeel

```bash
# on heavensfeel
curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install ansible-core        # -> ~/.local/bin (already on PATH via ~/.bashrc)
# no collections needed: requirements.yml declares none
```

Repo access is a **read-only deploy key** (not the workstation's key), so the
control node can pull but never push:

```bash
# on heavensfeel
ssh-keygen -t ed25519 -f ~/.ssh/homelab_deploy -N "" -C "homelab-control-node@heavensfeel"
cat ~/.ssh/homelab_deploy.pub

# from the workstation, with gh authenticated:
gh repo deploy-key add <that-pubkey-file> \
  --title "heavensfeel control node (read-only)" --repo <private-iac-repo>
```

Then point SSH at that key and clone:

```bash
# ~/.ssh/config on heavensfeel
Host github.com
    User git
    IdentityFile ~/.ssh/homelab_deploy
    IdentitiesOnly yes

git clone git@github.com:<private-iac-repo>.git /home/user/homelab
cd /home/user/homelab/ansible
ansible-playbook playbooks/deploy.yml --check
```

`uv` rather than a plain venv because heavensfeel's Python ships without
`ensurepip` (`python3-venv` is not installed), so `python3 -m venv` cannot
bootstrap pip — and installing it would need sudo. `uv` is user-local and
needs no elevation.

Requirements: the deploy set published to `/home/user/homelab/` (below), and
SSH keys from heavensfeel to both other nodes — already in place
(`~/.ssh/id_ed25519`, verified reachable with `BatchMode=yes`). The inventory
targets plain `192.168.50.x` with `ansible_user: user`, so the control node
needs no per-node SSH aliases; `host_key_checking = False` covers known_hosts.

### Publishing changes to the control node

From the vault:

```bash
scripts/publish-to-control.sh
```

pushes the current commit to the **private** remote, then fast-forwards the
control node's read-only clone (`heavensfeel:/home/user/homelab`) with
`git pull --ff-only` — so a deploy always runs against an exact commit.
Secrets are never in the repo: `compose/*.env` (e.g. API keys) and
`infra/traefik/dynamic/dashboard.yml` (basicAuth hash) are `.gitignore`d, so
nothing sensitive is published or synced.


## Layout

```
ansible/
├── ansible.cfg                    # inventory path, forks=3, SSH multiplexing
├── requirements.yml               # community.general collection (v2+ needs)
├── inventory/
│   ├── homelab.yml                # 3 hosts + groups (swarm_managers/storage/media/daemons)
│   └── group_vars/
│       ├── all.yml                # compose_dir, traefik_dynamic_dir, repo paths
│       ├── milis-wonderspace.yml  # per-node roles + service lists
│       ├── milkymiracle.yml
│       └── heavensfeel.yml
└── playbooks/
    ├── site.yml                   # entrypoint → common.yml only (audit/apply)
    ├── common.yml                 # user, dirs — NO sudo anywhere in v1
    └── deploy.yml                 # sync compose + traefik → docker compose up -d
```

## What v1 manages

**common.yml** (all 3 nodes, idempotent):
- user `user` present, shell `/bin/bash`, groups `sudo`+`docker` (append-only)
- `/home/user/docker/compose/` exists
- `/etc/traefik/dynamic/` exists (user-owned subdir — no root escalation)

**deploy.yml**:
- `compose/<node>.yml` → `/home/user/docker/compose/<node>.yml` (per node)
- `infra/traefik/dynamic/{standalone,dynamic}.yml` → `/etc/traefik/dynamic/` on **all 3 nodes** (the 2026-07-17 rule: identical everywhere, now enforced by code)
- `docker compose -f <node>.yml up -d` — only containers whose file changed; `.bak` kept on every sync

**Sudo model:** v1 runs entirely without sudo. The nodes' sudoers is two-layer — password-gated `%sudo` (human admin, TTY only) + NOPASSWD read-only whitelist (`/etc/sudoers.d/hermes-agent`, for hermes, watchdog-monitored). v1 owns only paths `user` can write without elevation. See hermes.

## Explicitly NOT managed in v1 (and why)

| Area | Why |
|---|---|
| sudoers (NOPASSWD layer) | Hermes watchdog monitors it; Ansible writing it would fight the agent |
| apt / package state + timezone | Need root; dropped after the first audit hit "Missing sudo password" — nodes already correct. v2 candidate behind a narrowly-scoped, watchdog-blessed NOPASSWD entry (NOT a broad `apt*` grant — dpkg postinst = root escalation) |
| NFS fstab / exports | Live-tuned around the storage hardware; revisit post-migration |
| systemd units/timers + cron | Hand-deployed and stable (~10 units: sync-qbit-port, cleanup-stale-mounts, bump-recent-media-mtime, deadman-ping, lrc-sync, smart-health-check…) |
| nftables / firewall | CrowdSec firewall-bouncer owns rules dynamically |
| swarm stacks (`traefik-stack.yml`, `infra.yml`, `cockpit-stack.yml`) | `docker stack deploy` from milkymiracle `/home/user/docker/Stacks/`; `infra.yml`+`cockpit-stack.yml` retired/superseded |
| `compose/job-ops.yml`, `compose/searxng.yml` | Live copies live elsewhere (`/home/user/job-ops/`, `/DATA/Apps/searxng/`) |
| `infra/traefik/dynamic/dashboard.yml` | Embeds the basicAuth password hash — credential, synced by hand |

Rule of thumb: **if a human hand-tunes it on the node, Ansible does not own it yet.**

> **V2 is planned** — see v2-roadmap (Track 1 deepens Ansible: privileged scope, systemd units/timers, NFS, housekeeping).

## Change workflow (how to change a service)

1. **Edit the repo** — internal Compendium is the source of truth:
   - App changes → `compose/<node>.yml` (image tag, env, healthcheck…)
   - Routing changes → `infra/traefik/dynamic/standalone.yml` (+ `dynamic.yml` if middleware)
   - New secret → add to the node's `/home/user/docker/compose/.env` (never in the repo)
2. **Commit, publish + deploy** (publish from the vault, deploy from the control node):
   ```bash
   git add -A && git commit -m "…"
   scripts/publish-to-control.sh
   ssh hserver 'cd /home/user/homelab/ansible && ansible-playbook playbooks/deploy.yml --check'
   ssh hserver 'cd /home/user/homelab/ansible && ansible-playbook playbooks/deploy.yml'
   ```
3. **Verify** — `docker ps` on the node, the service's endpoint, and `site.yml --check` for drift.
4. **Mirror to homelab-iac** (public, sanitized: `example.com`, `${VAR}`, `user`) — CI lints, validates compose, scans images with Trivy (CRITICAL gates the build; HIGH trends; `.trivyignore` holds dated per-CVE accepts, `.trivy-lag-images` holds per-image advisory entries for known upstream lag).
5. **Document** — update `services/*.md`, server pages, and the Homelab.md changelog.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Missing sudo password` | A task needs root — v1 shouldn't. Check for drift from v1 scope; otherwise it's a v2 privileged task |
| Traefik sync fails on eserver | `/etc/traefik/dynamic` must be user-owned on **all 3** nodes (`sudo chown user:user /etc/traefik/dynamic` — fixed 2026-08-15) |
| `host_key_checking` warnings | Deliberate: `host_key_checking = False` (RFC1918 LAN, keys rotate on reimage) |
| Containers not recreated | `docker compose up -d` only touches changed services — expected. `docker compose -f <node>.yml up -d --force-recreate <svc>` for manual kicks |
| Compose config fails | Run `cd /home/user/docker/compose && docker compose -f <node>.yml config -q` on the node — usually a missing var in `.env` |

## History

- **2026-08-15** — v1 built, first real run (audit/apply/deploy all clean), drift-convergence demo (injected comment healed + `.bak` kept), public mirror + CI (yamllint/ansible-lint/compose validate/Trivy) live in homelab-iac.
- **2026-08-15 (later)** — sudo model clarified in docs; public `common.yml` realigned (privileged draft tasks removed).
- **2026-09-21** — control node moved off the workstation/laptop to **heavensfeel** (always-on): `ansible-core` installed via `uv` (user-local; `ensurepip` absent on that node), deploy set at `/home/user/homelab`. Verified `deploy.yml --check` *from the control node*: 3/3 nodes, zero drift.
- **2026-09-21 (later)** — the vault itself put under version control: new **private** `<private-iac-repo>` (public `homelab-iac` stays the sanitized mirror; secrets `.gitignore`d, `.git` `.stignore`d for Syncthing). The control node now holds a read-only **deploy-key clone**, replacing the rsync staging; `publish-to-control.sh` is push → `git pull --ff-only`.
