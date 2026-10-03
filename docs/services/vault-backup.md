# Personal Vault Backup (The Compendium)

**Status**: Live (2026-10-03)
**Source**: workstation `WonderDreams` — `~/Documents/The Compendium`
**Destination**: `milis-wonderspace` — `/mnt/network/Backups/vault`
**Mechanism**: Syncthing (one-way) → Borg (LAN + Hetzner)

## The gap this closes

`~/Documents/The Compendium` (264 notes, ~112 MB) is the personal Obsidian
vault: `Chapters`, `Lore`, `TTRPGs`, `Programming`, `IMG Dump`, and the
`Homelab` subfolder. It was in **no** backup path:

- not a git repo,
- not a Syncthing folder as a whole,
- not in any Borg source list.

Only the `Homelab` subfolder had coverage (its own Syncthing folder plus the
private git repo and the control-node clone). The creative/writing content
had nothing — a single disk failure from gone.

The phone also carries a partial copy at
`/sdcard/Elements/The Compendium` (150 notes), captured by the phone bundle
under `misc/elements-vault`.

## Architecture

```
WonderDreams (laptop, not always on)
  ~/Documents/The Compendium                [Syncthing folder: compendium-backup, sendonly]
        │  Syncthing, tcp 22000
        ▼
milis-wonderspace (always on)
  /mnt/network/Backups/vault                [Syncthing folder: compendium-backup, receiveonly]
        │  borgmatic (both configs already source this path)
        ▼
  LAN repo (heavensfeel)  +  off-site repo (Hetzner BX11)
```

- **Send-only → receive-only.** The NAS cannot push changes back, so a
  corrupt or wrong copy on the NAS cannot propagate to the laptop.
- **Borg covers the received path.** `/source/network/Backups/vault` was added
  to both `config.yaml` (LAN) and `borgmatic.d/10-offsite.yaml` (Hetzner).

## Syncthing instance (wonderspace)

| | |
|---|---|
| Image | `syncthing/syncthing:latest` |
| Config | `/DATA/Apps/syncthing` |
| Received data | `/mnt/network/Backups/vault` |
| Web UI | `http://192.168.50.115:8384/` (LAN only, not behind Traefik) |
| Sync port | 22000 (TCP+UDP), + 21027/udp discovery |
| Device ID | `KEZSAGU-XNBCNNJ-PKUWYBD-IDNLXIQ-JWTGVVN-2RHR6EY-3HOJUGK-Z3J2EQ3` |
| Folder ID | `compendium-backup` |

Folder IDs must match on both ends — Syncthing pairs by ID, not by label.
The configuration was applied through the REST API (`/rest/config`), then
verified with `/rest/db/status`.

## Exclusions

`~/Documents/The Compendium/.stignore`:

```
(?d)Homelab          # has its own Syncthing folder (id homelab); nesting it
                     # here would cause index/conflict churn
(?d).git             # never sync git internals
(?d)node_modules
(?d)__pycache__
(?d).playwright-mcp
```

The NAS Borg config also excludes `/source/DATA/Apps/syncthing/index-v2`
(the Syncthing database — not restorable and it churns on every sync).

## Verified

First sync on 2026-10-03: **218 files / 43.8 MB**, `needFiles: 0`,
`errors: 0`, `localFiles` == `globalFiles`. `Homelab` confirmed absent from
the received tree.

## Operational notes

- The laptop is not always on; Syncthing catches up whenever it is. A
  long-off laptop simply means an older backup, never a failed one.
- Syncthing is bidirectional by nature; the one-way guarantee here comes
  from the folder **types** (`sendonly` on the laptop, `receiveonly` on the
  NAS), not from the transport.
- Adding another Syncthing peer later (e.g. a second node as an extra
  replica) is a matter of sharing `compendium-backup` with it.
