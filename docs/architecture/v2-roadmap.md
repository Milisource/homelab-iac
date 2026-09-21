# V2 Roadmap — Ansible depth, CI evolution, security backlog, platform expansion

**Status**: Draft (2026-08-15) | **Companion**: Improvements & Known Issues (living backlog) | **Canonical Ansible doc**: ansible

## Context

V1 (2026-08-15) proved the GitOps loop: per-node compose files + Traefik dynamic configs are converged from the repo by `ansible/playbooks/deploy.yml`, CI (public homelab-iac) lints/scans everything, Diun closes the upstream-rebuild loop. V2 deepens the same layer, closes the security backlog, and — separately — builds the resume-facing platform track.

Guiding rules (inherited from v1):
- **Audit vs. deploy separation** stays: `site.yml` never imports `deploy.yml`.
- **If a human hand-tunes it on the node, Ansible does not own it yet** — v2 items only land after they're modeled as code.
- **The Hermes watchdog owns the sudoers NOPASSWD layer** — any new privileged entry is a Hermes conversation first, not an Ansible edit.

---

## Track 1 — Ansible depth (finishes the GitOps story)

| # | Item | Dependencies | Status |
|---|------|--------------|--------|
| 1.1 | **Privileged tasks behind a watchdog-blessed NOPASSWD entry** — narrow scope only: `apt-get install` for the exact pinned package list + `systemctl restart <managed-units>` + `timedatectl set-timezone`. NOT a broad `apt*` grant (dpkg postinst = root escalation vector). Reintroduces the v1-dropped apt/timezone tasks (nodes already at Docker 29.6.1 / America/New_York, so these are pure drift-guarantees) | Hermes approval + sudoers update on all 3 nodes | ⬜ |
| 1.2 | **Systemd units/timers as code** — model "present with exact content" for: `sync-qbit-port`, `cleanup-stale-mounts`, `bump-recent-media-mtime`, `detect-stale-network` (+ timer), `smart-health-check` (+ timer), `jellyfin-restart` (+ timer), `deadman-ping` (cron), `lrc-sync` (cron). Templates in `ansible/`, `systemd` module, handlers restart on change. Live content is the spec (read from nodes, then freeze into templates) | — | ⬜ |
| 1.3 | **NFS/fstab as code** (client fstab on milkymiracle + heavensfeel, `/etc/exports` on milis-wonderspace) | **USB→SATA migration lands first** (see Moving Off USB) — templatizing now would drift from post-migration reality | ⬜ |
| 1.4 | **Housekeeping in deploy.yml**: prune stale cross-node compose copies (found in the 2026-08-15 drift audit: e.g. pre-`edge` `heavensfeel.yml` on server/eserver), post-sync `docker compose config -q` verification on each node, md5-check that `standalone.yml`/`dynamic.yml` are byte-identical across all 3 nodes (07-17 rule) | — | ⬜ |
| 1.5 | **Secrets story**: keep the per-node `/home/user/docker/compose/.env` pattern (never in repo), document the inventory (see Track 3 item 3.5); evaluate `ansible-vault` only if a secret must live in the repo | — | ⬜ |

## Track 2 — CI evolution

| # | Item | Dependencies | Status |
|---|------|--------------|--------|
| 2.1 | **Self-hosted runner on heavensfeel** (or ephemeral tailnet runner) → deploys become `workflow_dispatch` / PR-triggered: CI lints + scans, then runs `ansible-playbook deploy.yml` against the fleet. N95 can host a runner (idle ~100MB) | Track 1 items optional but recommended first (deploy should be fully automated before it's CI-triggered). **Partly unblocked 2026-09-21** — heavensfeel is now the Ansible control node (`ansible-core` + deploy set at `/home/user/homelab`), so this only needs the workflow, not a host decision | ⬜ |
| 2.2 | **Scheduled drift audit**: weekly `site.yml --check` via CI cron (or runner) → failure posts to Telegram (existing watchdog channel pattern) | 2.1 or a tailnet runner. **Now a plain systemd-timer candidate (2026-09-21)** — the control node is always-on, so the audit no longer depends on a workstation being awake | ⬜ |
| 2.3 | **Trivy gate refinement**: move accepted-lag entries out of `.trivyignore` as upstreams rebuild (Diun already notifies — the removal trigger exists); consider SARIF upload for GitHub code-scanning tab. **Added 2026-09-21**: per-image advisory list `.trivy-lag-images` for images whose CRITICALs are all upstream lag — unlisted images still fail, and the build warns when a listed image goes clean | — | ⬜ ongoing |

## Track 3 — Security backlog (from Improvements & Known Issues, unchanged scope)

| # | Item | Status |
|---|------|--------|
| 3.1 | **Vaultwarden → Docker secrets**: live service still uses the plaintext `ADMIN_TOKEN` from the old config; redeploy from `/home/user/docker/Stacks/apps.yml` (defines it as a secret) | ⬜ |
| 3.2 | **DR plan + restore drills**: tested node-failure procedure; borg restore drill into a throwaway container (off-site backups resolved 08-15 — restore is untested) | ⬜ |
| 3.3 | **SMART monitoring alerts** (all 5 ATA drives) — `smart-health-check` exists as a timer; wire results into Uptime Kuma/Grafana alerting | ⬜ |
| 3.4 | **Immich photo library backup** (currently excluded from borg) | ⬜ |
| 3.5 | **Secrets + port inventory** docs (docker secrets, exposed ports, where `.env` vars live) | ⬜ |
| 3.6 | **Network diagram** (visual topology — text version in network/topology) + **recovery runbook** per node | ⬜ |
| 3.7 | **SSH hardening review**: fail2ban config, key-only auth confirmation | ⬜ |
| 3.8 | **Network segmentation review**: Docker network isolation audit | ⬜ |

## Track 4 — Platform expansion (resume-facing, separate from Ansible)

Deliberately *not* production-critical work; these are the "industry experience" items. Sequence by value:

| # | Item | Why | Status |
|---|------|-----|--------|
| 4.1 | **k3s lab** — KVM VMs on milkymiracle: k3s + cert-manager + Traefik Ingress + Longhorn; Swarm stays production | Kubernetes is the #1 resume keyword; Swarm alone doesn't cover it | ⬜ |
| 4.2 | **OpenTofu/Terraform** for what's declarable (Tailscale ACLs, DNS records, Gitea orgs) | Third IaC pillar | ⬜ |
| 4.3 | **OTel + Tempo + Pyroscope** on heavensfeel (completes LGTM → LGTMP) | Tracing/profiling increasingly a job requirement | ⬜ |
| 4.4 | **Authentik SSO/OIDC** in front of `*.example.com` apps | Identity/access is its own job category | ⬜ |
| 4.5 | **MinIO** on the 29TB pool | S3 experience; borg/restic target | ⬜ |
| 4.6 | **Chaos/DR exercises** (kill a manager, partition a node, watch Grafana react) | SRE story material | ⬜ |

## Explicitly out of scope (for now)

- **Hermes isolation** (dedicated restricted user) — handled separately; Hermes-as-user inherits docker-group root, so this is the highest-value *security* item overall, but it's a Hermes project, not an Ansible one.
- **Swarm → k8s migration** — not planned; k3s is a parallel lab (4.1).
- **Swarm stacks reconciliation** (Portainer vs. compose-on-disk source of truth) — needs its own decision; tracked in Improvements & Known Issues.

## Sequencing

- **Phase A (next)**: Track 1 items 1.1–1.2 → Track 2 (runner + scheduled audit). This makes the fleet fully declarative and deploys one-click.
- **Phase B**: Track 3 security backlog (3.1–3.3 first — secrets, DR, monitoring).
- **Phase C**: Track 4 platform expansion, one item at a time; 4.1 (k3s) first.
- **Rolling**: 2.3 (Trivy ignore hygiene) runs continuously as Diun fires.

## Definition of done for V2

- `ansible-playbook playbooks/site.yml --check` covers systemd units, timers, and (post-migration) NFS — zero drift reported.
- Deploys triggerable from CI with human approval; scheduled drift audit alerts in Telegram.
- Security backlog items 3.1–3.3 closed; DR restore drill documented.
- k3s lab running a non-trivial workload (e.g. cert-manager + an ingress'd demo app).
