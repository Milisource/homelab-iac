# Phone & Personal-Data Backup

**Status**: Live (verified on Galaxy S25+, Android 16, 2026-10-03)
**Nodes**: milis-wonderspace (execution + storage), heavensfeel (Borg repo), milkymiracle (Immich)

## Goal

A phone breakage showed a gap: photos and passwords were partially covered,
but contacts, SMS, call log, calendar, notes and app data were not backed up
anywhere, and the off-site story was missing entirely.

## Design principles

1. **Don't duplicate what already exists.** Photos → Immich. Passwords →
   Vaultwarden. The phone bundle captures only what those two don't.
2. **Everything that *can* be backed up, is.** Android 12+ blocks
   app-internal data (WhatsApp/Signal DBs) from ADB by design; those use
   in-app export. Everything else is pulled or DAV-synced.
3. **Bundles are portable.** A dated directory plus `MANIFEST.json` and
   `README.md` means a new phone can be repopulated without the homelab.
4. **Backups are Borg-covered.** The bundle lives on the mergerfs pool so
   borgmatic picks it up, and it replicates off-site.

## Layer 1 — Phone bundle (milis-wonderspace)

`scripts/phone-backup.sh` + `.service` + `.timer` pull portable personal
data over adb (TCP/IP) into:

```
/mnt/network/Backups/phone/
├── README.md              # restore instructions, regenerated each run
├── MANIFEST.json          # sha256 + size per file
├── latest -> 2026-10-03
└── 2026-10-03/
    ├── contacts/          # contacts.vcf (importable) + data.raw.txt
    ├── sms/               # sms-calls.xml (SMS + calls + MMS) + sms.raw.txt
    ├── mms/               # mms/addr/part raw dumps + attachments/<partid>.<ext>
    ├── calllog/           # calls.raw.txt (XML copy lives in sms/)
    ├── calendar/          # calendar.ics + events.raw.txt
    ├── callrecordings/    # /sdcard/Recordings/Call
    ├── notes/             # note stores found on shared storage
    ├── misc/              # elements-vault, documents, music, movies, ringtones,
    │                      # download-docs (pdf/xlsx/txt/ovpn/doc/csv)
    ├── appdata/           # installed-package inventory
    └── device-info.txt
```

Retention: dated bundles older than `RETENTION_DAYS` (default 90) pruned.

Each source is captured **twice**: a raw `content query` dump (nothing lost)
and a **standard, importable artifact**. The raw dump is not restorable by any
tool on its own, and the `contacts` table carries no phone numbers (only a
`has_phone_number` flag), so the conversions are what make the bundle useful:

| Source | Importable artifact | Restore with |
|--------|--------------------|--------------|
| contacts | `contacts.vcf` (from the `data` table: name + TEL + EMAIL) | Contacts app → Import |
| calendar | `calendar.ics` | Calendar app → Import |
| sms + calls + MMS | `sms-calls.xml` (SMS Backup & Restore schema) | SMS Backup & Restore → Restore |

**MMS attachments** are streamed with `adb exec-out content read
--uri content://mms/part/<id>` — the parts table's `_data` path points into
private app storage and is unreadable, so the bytes cannot be pulled by path.
Binary parts (images, video, PDF) land in `mms/attachments/`; `text/plain`
parts are the message bodies and stay in the raw dump. All attachments are
kept (no age filter).

### Verified against the real device (Galaxy S25+, Android 16)

A test run on 2026-10-03 captured, **via the shell user with no root and no
helper app**:

- **Contacts**: 130 vCards, **with phone numbers** (query `content://com.android.contacts/data`,
  not `…/contacts`).
- **Calendar**: 736 events → valid ICS.
- **SMS**: 913 messages → well-formed XML (multi-line bodies preserved).
- **Call log**: 2000 rows → XML. **This is a provider cap**; older calls are
  not retrievable over adb. Recent history is what matters for a fresh restore.
- **Packages**: 170 third-party apps.

Contrary to the original assumption (that Android 12+ blocks these providers
from the shell user), **Samsung's Android 16 permits all four** — no DAVx5 and
no CalDAV/CardDAV server are required. That assumption is why the doc
previously recommended DAVx5; it is superseded by this result.

### Why adb-over-TCP and not USB

Runs headless on the NAS on a timer. Pair once:

```bash
adb pair <phone-ip>:<pair-port>     # 6-digit code shown on the phone
adb connect <phone-ip>:<connect-port>
```

Requires *Wireless debugging* enabled on the phone. **Both ports rotate**
whenever Wi-Fi reconnects or Wireless debugging is toggled — on this device
the pairing port and the connect port were the *same* (`42215`), which is not
guaranteed. `adb mdns services` found nothing here (mDNS is not propagated
across the network), so the port is read manually from
*Settings → Developer options → Wireless debugging* and set in the unit's
`PHONE_ADB_PORT`. A drifted port shows up as a failed run, not a silent one.

## Layer 2 — Borg coverage (the actual gap)

The existing borgmatic job on milis-wonderspace covers
`/source/DATA/{Apps,Arr,Media}` → `ssh://user@192.168.50.129/repos/homelab`.
Two things fall outside it:

| Gap | Where | Why it matters |
|-----|-------|----------------|
| heavensfeel `/DATA/Apps` | pearls of the daemon node | **Vaultwarden, n8n, grafana, actual** — none Borg-covered |
| mergerfs pool `/mnt/network` | phone bundle, Immich assets | Not in any source list |

### Implemented: a second borgmatic config

borgmatic applies all options **globally within one config file**, so the
off-site repo (which needs `remote_path: borg-1.4`) cannot share a file with
the LAN repo (served via a forced command that must not get that flag).
The documented pattern is one config file per repository, discovered via
`/etc/borgmatic.d`.

```
/DATA/Apps/borgmatic/
├── config.yaml                    # LAN repo (heavensfeel), unchanged
└── borgmatic.d/
    └── 10-offsite.yaml            # Hetzner, remote_path: borg-1.4
```

The compose service bind-mounts that directory to `/etc/borgmatic.d` (it is
auto-discovered) and adds `/mnt/network:/source/network:ro`.

New sources in **both** configs (LAN and off-site), so the pool state is
covered by both repositories:

```yaml
source_directories:
  - /source/network/Backups/phone          # the portable bundle
  - /source/network/Backups/vaultwarden    # age-encrypted VW export mirror
  - /source/network/Photos/immich/backups  # Immich app-level pg dumps
```

`/source/network/Backups/vaultwarden` is populated by
`vaultwarden-gdrive-upload.sh` (the local mirror step) — the Google Drive
copy is a convenience artifact, not a Borg repo, so this mirror is what
actually gets the encrypted export into Borg.

Because a missing source directory fails the run, `/mnt/network/Backups/phone`
is created with a `PLACEHOLDER.md` until the phone job performs its first run.

Immich's 17 GB asset tree (`library/`, `thumbs/`, `encoded-video/`) is
explicitly excluded from the off-site job — it is not worth the bandwidth
when the DB dump plus Immich itself covers restore. Remove those excludes if
you want photos off-site too.

Note: Borg on the full 29 TB media pool is the wrong tool — that content is
replaceable and huge. Cover *state* (configs, DBs, bundles), not media.

**Pool root is not writable.** `/mnt/network`, `/mnt/disk2`, `/mnt/disk3`
and `/mnt/disk5` are root-owned, so mergerfs refuses `mkdir` at the pool
root. Create new top-level dirs with `sudo`, or place them under an existing
writable parent. `/mnt/network/Backups` now exists (created with sudo,
owned by `mili`).

**Watched failure mode.** Any directory created *as root* under the pool
(e.g. by an earlier systemd run before the service was switched to
`User=user`) will be unwritable by the job — silently, if the script swallows
the error. `vaultwarden-gdrive-upload.sh` now `die`s loudly on a failed
mirror write for this reason.

### Immich app-level dump

Immich already writes `immich-db-backup-*.sql.gz` to
`/mnt/network/Photos/immich/backups` daily (`pg_dumpall`, version-tagged).
Borg-covering that directory gives a version-independent restore path that
doesn't need a matching Immich image.

## Layer 3 — Off-site (Hetzner Storage Box BX11)

| | |
|---|---|
| Size | 1 TB (homelab state is ~25 GB compressed) |
| Cost | €3.20/mo excl. VAT, no setup fee, no minimum term |
| Borg | native, SSH on port 23, `--remote-path=borg-1.4` to pin version |
| Extras | unlimited traffic, 10 snapshots, EU/DE or FI, GDPR DPA |

Free tiers were evaluated and rejected: Google Drive/Dropbox/MEGA have no
SSH and cannot host a Borg repo safely (FUSE + Borg is a known footgun);
B2/R2 free tiers are 10 GB and S3-only. Oracle Cloud Always Free (200 GB
VPS) is the only genuine free option but requires maintaining a VPS.

### Setup

```bash
# on milis-wonderspace (run inside the borgmatic container)
borg init --encryption=repokey-blake2 \
  --remote-path=borg-1.4 \
  ssh://uXXXXX@uXXXXX.your-storagebox.de:23/./backups/homelab
borg key export <repo> /repos/offsite-key-export.txt
```

Prerequisites confirmed against live state:
- Host key pinned in `/root/.config/borg/ssh/known_hosts` (container uses
  `ssh_command` for borgmatic runs, but bare `borg` needs `BORG_RSH` — set
  it explicitly for init/key operations).
- Remote `borg-1.4` resolves to 1.4.4; container runs 1.4.5 (wire-compatible).
  Hetzner's default is 1.2.9, which *would* mismatch.
- The remote parent dir must exist first — `borg init` does not create it:
  `ssh -p23 ... mkdir backups`.
- Paths are relative (`./backups/...`); a leading slash fails as only
  `/home/` is writable.

Then add the repo to `borgmatic.d/10-offsite.yaml`. **Use an append-only
SSH key** so a compromised NAS cannot delete the off-site copy:

```
restrict,command="borg serve --append-only --restrict-to-path /backups"
```

Verify restores periodically: `borg mount` and diff against the live tree.

## Outstanding findings

- **Vaultwarden backups stopped 2025-11-28** — RESOLVED 2026-10-03.
  `/DATA/Apps/backups/` holds daily tarballs only through November; the
  producing cron is gone. Fixed by adding a borgmatic job *on heavensfeel*
  that covers `/source/DATA/Apps` and uses the `sqlite_databases` hook, which
  runs `sqlite3 .backup` for a consistent snapshot. **This matters:** the live
  `db.sqlite3` is WAL-mode with an active 4 MB `-wal` file, so a plain file
  copy would yield a stale or corrupt restore. Verified present in the
  archive as `borgmatic/sqlite_databases/localhost/vaultwarden`.
- **No Borg repo for the daemon node** — RESOLVED 2026-10-03. A borgmatic
  container now runs on heavensfeel and covers its own `/DATA/Apps`:
    - `config.yaml` → `/repos/self` (local, via the bind mount)
    - `borgmatic.d/10-offsite.yaml` → Hetzner `./backups/heavensfeel`
  Cron staggered (05:00 heavensfeel, 06:00 wonderspace) so the two off-site
  pushes do not contend for the Box's 10-connection limit.
- **GDrive off-site copy** — pipeline built 2026-10-03, blocked on auth:
  - `scripts/vaultwarden-export.sh` (heavensfeel): admin API dump +
    `vaultwarden backup` → tar → `age`-encrypt → `/DATA/Apps/vaultwarden/export/`.
    Also covered by heavensfeel's borgmatic job, so it reaches Hetzner too.
  - `scripts/vaultwarden-gdrive-upload.sh` (wonderspace): `scp` the artifact
    from heavensfeel, verify the age header, `rclone copy` to
    `gdrive:homelab-backups/vaultwarden/`, prune to 7d/4w/6m, mirror locally.
  - Timers: export 04:00 heavensfeel, upload 05:30 wonderspace.
  - **Blocked:** `gdrive:` rclone token expired 2025-05-02 (518 days ago).
    `invalid_grant` with a refresh_token present means the OAuth app is in
    **Testing** mode in Google Cloud Console, where refresh tokens are revoked
    after 7 days of non-use. Fix: reconnect (`rclone config reconnect gdrive:`
    on wonderspace; headless — open the printed URL elsewhere and paste the
    code), then publish the app to stop it recurring weekly.
  - Key material: age keypair at `heavensfeel:/DATA/Apps/borgmatic/keys/`
    (`age-vaultwarden.key` mode 600, `.pub` for encryption). The private key
    is never uploaded and must be backed up offline — without it the Drive
    copies are unrecoverable.
  - Notes: GDrive is **not** a Borg target (no SSH; FUSE is unsafe) — this is
    an encrypted-artifact copy, not a Borg repo. Vaultwarden's admin login
    rate-limits (HTTP 429) under repeated calls; the exporter treats the API
    dump as supplementary and continues with the database only.
  - **Weak `ADMIN_TOKEN`** (11-char plaintext, acts as the vault admin
    password) — left as-is by choice 2026-10-03. Harden with
    `docker exec vaultwarden /vaultwarden hash --preset owasp` if desired.
- Immich DB dumps are accumulating unpruned (~50 MB/day).

## Architecture decision (2026-10-03)

**borgmatic runs per node; repos are central.** Rejected the alternative of
centralising all backups on wonderspace via SSH/NFS because:
- borgmatic's `source_directories` are local paths; covering another machine
  would need NFS (none exists between these nodes) or a pull mechanism Borg
  does not natively provide.
- The 2026-08-11 changelog entry records wonderspace's borgmatic failing
  *silently* for days on a bad SSH mount — centralising means one config
  error breaks every backup at once.
- Least privilege and fault isolation: each node holds exactly one restricted
  key, and one node being down does not stop the others.

Topology per node: `borgmatic → heavensfeel /repos/<node>` (LAN, primary)
and `→ Hetzner ./backups/<node>` (off-site).

## Restore runbook

1. Passwords → `borg extract` Vaultwarden data, or restore the tarball, then
   start the container. Log in with Bitwarden app on the new phone.
2. Contacts/calendar → DAVx5 pointed at the CalDAV/CardDAV server.
3. Photos → connect Immich app; the library is already server-side.
4. Phone bundle → `adb push` notes back, import SMS/calllog, reinstall from
   the package inventory.
5. Off-site → `borg extract` from Hetzner if local copies are gone.
