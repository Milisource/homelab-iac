# Vaultwarden

**Host**: heavensfeel | **Domain**: vault.example.com

> Moved from milis-wonderspace to heavensfeel (critical-uptime daemon on the 15W always-on node). Runs as a standalone container in `compose/heavensfeel.yml`, not a swarm service.

## Configuration

| Setting | Value |
|---------|-------|
| Domain | https://vault.example.com |
| Signups | Disabled |
| Admin token | env var `VAULTWARDEN_ADMIN_TOKEN` (in compose `.env`) |
| Data dir | /DATA/Apps/vaultwarden/data/ |

## Traefik

Traefik routes `vault.example.com` → vaultwarden:80 via `infra/traefik/dynamic/standalone.yml` (rate-limited).

## Backup

Vaultwarden has **two** independent backup paths, both live since 2026-10-03:

1. **Borg (structural).** heavensfeel's borgmatic job covers `/DATA/Apps`,
   including `data/db.sqlite3`. Because the DB is WAL-mode with an active
   `-wal` file, borgmatic's `sqlite_databases` hook runs `sqlite3 .backup` for
   a consistent snapshot (a plain file copy would be stale/corrupt). Restore
   point is in the archive at `borgmatic/sqlite_databases/localhost/vaultwarden`.
2. **Age-encrypted export → GDrive (portable).** `vaultwarden-export.sh`
   (heavensfeel, 04:00) exports the vault and encrypts it with `age`; the
   `.tar.gz.age` artifact is mirrored to the pool
   (`/mnt/network/Backups/vaultwarden`, captured by Borg) and uploaded to
   Google Drive (`gdrive:homelab-backups/`) by `vaultwarden-gdrive-upload.sh`
   (wonderspace, 05:30). GDrive is **not** a Borg repo — it holds the encrypted
   artifact only, retention mirrors Borg (7d/4w/6m).

**Recovery secret:** the age private key is
`/DATA/Apps/borgmatic/keys/age-vaultwarden.key` (mode 600) on heavensfeel. It
decrypts every Drive artifact, so it must be saved **offline** (password
manager / printed) — otherwise a total-site loss leaves the Drive copies
undecryptable. It is also inside Borg (heavensfeel `/DATA/Apps`), so it is
recoverable from the off-site repo, but offline is the durable answer.

Decrypt a Drive artifact:

```bash
age -d -i age-vaultwarden.key vaultwarden-2026-10-03.tar.gz.age | tar xz
```

The old tarball cron died 2025-11-28 (a 10-month silent gap, now closed).
Confirmed dead — no crontab, timer, or on-disk artifacts — so it cannot
double-write alongside the age pipeline.
