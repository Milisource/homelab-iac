# Backups — Coverage Map

**One page that answers: what is backed up, where does it go, how do I verify
it, and how do I restore it.** Per-source detail lives in the linked docs.

Three independent layers:

1. **Borg (versioned, encrypted, deduplicated)** — app configs/DBs and the
   personal-data artifacts, to a LAN repo **and** an off-site Hetzner Storage
   Box.
2. **Syncthing (live mirror)** — the personal Obsidian vault from the
   workstation to a pool path Borg then captures.
3. **Age-encrypted artifact** — the Vaultwarden export, mirrored to Google
   Drive (not a Borg repo).

## Coverage matrix

| Data | Source | Artifact | Borg | Off-site | Restore with |
|------|--------|----------|:----:|:--------:|--------------|
| App configs + DBs (`/DATA/Apps`, `/DATA/Arr`, `/DATA/Media`) | milis-wonderspace | files | ✅ LAN + Hetzner | ✅ | `borg extract` |
| App configs + DBs (`/DATA/Apps`) | heavensfeel | files + sqlite hook | ✅ local + Hetzner | ✅ | `borg extract` |
| Contacts / SMS / MMS / calls / calendar / notes / misc | Android phone (adb) | `contacts.vcf`, `calendar.ics`, `sms-calls.xml`, attachments | ✅ | ✅ | see [phone-backup](phone-backup.md) |
| Personal Obsidian vault ("The Compendium") | workstation | live files (Syncthing) | ✅ | ✅ | see [vault-backup](vault-backup.md) |
| Vaultwarden export | heavensfeel | `*.tar.gz.age` | ✅ (mirror) | ✅ | age-decrypt, see [vaultwarden](vaultwarden.md) |
| Immich DB dumps | milkymiracle → pool | `immich-db-backup-*.sql.gz` | ✅ | ✅ | `gunzip` + `psql` |

**Deliberately NOT backed up:**

- **Photos/videos** — owned by Immich (its own storage + DB). The 17 GB asset
  tree is excluded from Borg; only the DB dumps ride along.
- **Passwords in the clear** — Vaultwarden is the source; the export is
  age-encrypted and the private key is the recovery secret.
- **Docker images / container layers** — rebuilt from Compose.
- **Immich DB dumps are unpruned** (~50 MB/day accumulate in
  `/mnt/network/Photos/immich/backups`). Borg dedupes them, but the source
  dir grows unbounded — trim manually or add a retention job.

## Topology

```
                     ┌─────────────────────────── milis-wonderspace ───────────────────────────┐
 phone (adb 5555) ──▶│ /mnt/network/Backups/phone        (dated bundle + mms-attachments)       │
                     │ /mnt/network/Backups/vaultwarden  (age artifact mirror)                  │
 workstation ──Sync──▶│ /mnt/network/Backups/vault       (Compendium)                            │
                     │ /mnt/network/Photos/immich/backups (DB dumps)                            │
                     │ borgmatic 06:00 ──▶ LAN  ssh://user@192.168.50.129/repos/homelab        │
                     │                 └─▶ OFF  ssh://uXXXXX@…:23/./backups/homelab            │
                     └──────────────────────────────────────────────────────────────────────────┘

                     ┌───────────────────────────── heavensfeel ───────────────────────────────┐
                     │ borgmatic 05:00 ──▶ LAN  /repos/self                                     │
                     │                 └─▶ OFF  ssh://uXXXXX@…:23/./backups/heavensfeel         │
                     │ borg-repo container serves wonderspace's LAN repo (forced command)       │
                     └──────────────────────────────────────────────────────────────────────────┘
```

## Schedule (America/New_York)

| Time | Job | Node |
|------|-----|------|
| 04:30 | Phone bundle (adb pull) | milis-wonderspace |
| 05:00 | borgmatic — local + Hetzner | heavensfeel |
| 06:00 | borgmatic — LAN + Hetzner | milis-wonderspace |

Heavensfeel runs **one hour before** wonderspace so the two off-site pushes do
not contend for the Storage Box connection limit.

## Repositories

| Repo | Path | Label | Where |
|------|------|-------|-------|
| LAN | `ssh://user@192.168.50.129/repos/homelab` | `heavensfeel` | borg-repo container on heavensfeel |
| Local | `/repos/self` | `heavensfeel-local` | heavensfeel (`/home/user/borg-repos/self`) |
| Off-site | `ssh://uXXXXX@uXXXXX.your-storagebox.de:23/./backups/homelab` | `hetzner` | Hetzner Storage Box BX11 |
| Off-site | `ssh://uXXXXX@uXXXXX.your-storagebox.de:23/./backups/heavensfeel` | `hetzner` | Hetzner Storage Box BX11 |

- Paths on the Box are **relative to the remote home** (`./` prefix) — only
  `/home/` is writable on a Storage Box.
- Remote Borg pinned to `borg-1.4` (`remote_path: borg-1.4`): the Box default is
  1.2.9, the containers run 1.4.5. That pin is why the off-site job is a
  **separate config file** (`borgmatic.d/10-offsite.yaml`) — borgmatic applies
  options per file, and `remote_path`/`ssh_command` must not leak into the LAN
  repo, which is served via a forced command.
- Retention (both repos): **7 daily / 4 weekly / 6 monthly**.

## Verify

```bash
# --- wonderspace: both configs load? (must print "All configuration files are valid") ---
ssh user@192.168.50.115 'cd /home/user/docker/compose && \
  docker compose -f milis-wonderspace.yml exec -T borgmatic borgmatic config validate'

# --- both repo labels present? (expect heavensfeel AND hetzner) ---
ssh user@192.168.50.115 'cd /home/user/docker/compose && \
  docker compose -f milis-wonderspace.yml exec -T borgmatic borgmatic repo-list'

# --- archive history (LAN + Hetzner) ---
ssh user@192.168.50.115 'cd /home/user/docker/compose && \
  docker compose -f milis-wonderspace.yml exec -T borgmatic \
  borgmatic list --config /etc/borgmatic.d/10-offsite.yaml --match-archives "*" --short'

# --- Box contents, directly (no container needed) ---
ssh user@192.168.50.115 'ssh -i /DATA/Apps/borgmatic/ssh/id_ed25519 -p 23 \
  -o UserKnownHostsFile=/DATA/Apps/borgmatic/ssh/known_hosts \
  -o StrictHostKeyChecking=accept-new -o BatchMode=yes \
  uXXXXX@uXXXXX.your-storagebox.de "du -sh ./backups/homelab ./backups/heavensfeel"'
```

**A healthy run logs one `Repository:` line per configured repo.** If
`docker logs borgmatic` shows only the LAN repo, the off-site config is not
being loaded — see the 2026-10-03 incident below.

## Restore

```bash
# 1. Find the archive
docker compose -f milis-wonderspace.yml exec -T borgmatic \
  borgmatic list --config /etc/borgmatic.d/10-offsite.yaml --match-archives "*"

# 2. Extract a path (run from /tmp — never extract over the read-only source mount)
cd /tmp && mkdir restore && cd restore
docker compose -f milis-wonderspace.yml exec -T borgmatic sh -c '
  export BORG_REPO=ssh://uXXXXX@uXXXXX.your-storagebox.de:23/./backups/homelab
  export BORG_PASSPHRASE=<passphrase>
  export BORG_RSH="ssh -i /root/.ssh/id_ed25519 -p 23 -o BatchMode=yes"
  borg extract --remote-path borg-1.4 "::<archive>" "source/network/Backups/phone"'
```

Phone-specific restore steps are in the bundle's own `README.md` (regenerated
each run) and in [phone-backup](phone-backup.md).

## Known gaps / limits

- **milkymiracle has no borgmatic job.** Immich is covered by its built-in DB
  dumps (which land under the pool and are picked up by the wonderspace job),
  but any *other* milkymiracle-local `/DATA` app data is in **no** repo.
- **Photos are excluded by design** — Immich owns them. A total Immich storage
  loss needs the Immich asset tree (not in Borg) or an Immich-level restore.
- **Call log is capped at 2000 rows** by the Android provider.
- **`/mnt/network` root is not writable by the container user** (mergerFS
  branches are root-owned), so artifacts live under the writable
  `/mnt/network/Backups` and `/mnt/network/Photos` subtrees.
- **Append-only Borg hardening is deferred** — the daily key can create *and*
  prune/compact. Making it append-only needs a split create-only + offline-prune
  key pair.

## Incident history

- **2026-08-15 — SSH volume miss.** The compose borgmatic service never got the
  `/DATA/Apps/borgmatic/ssh:/root/.ssh:ro` mount; every cron run silently failed
  with `Permission denied (publickey)`.
- **2026-10-03 — off-site config never ran.** The Hetzner job is auto-discovered
  only if `/etc/borgmatic.d` is mounted. The compose file gained the mount, but
  the **running container predated the edit**, so every 06:00 run touched only
  the LAN repo (the one Hetzner archive was a manual create). Fixed by
  recreating the container. **Lesson: a compose edit does not change a running
  container — recreate it and verify the live mounts with `docker inspect`.**

## See also

- [phone-backup](phone-backup.md) — Android bundle design + restore
- [vault-backup](vault-backup.md) — Compendium via Syncthing
- [vaultwarden](vaultwarden.md) — age-encrypted export → GDrive
- [other-services](other-services.md) — borgmatic service notes
