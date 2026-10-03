#!/usr/bin/env bash
set -euo pipefail

# vaultwarden-export.sh — Export Vaultwarden, encrypt with age, stage for pickup.
# Runs on HEAVENSFEEL (the node that owns the vault and its config.json).
#
# Produces an age-encrypted artifact at:
#   /DATA/Apps/vaultwarden/export/vaultwarden-YYYY-MM-DD.tar.gz.age
# which wonderspace pulls over SSH and pushes to Google Drive
# (vaultwarden-gdrive-upload.sh). The same directory is covered by
# heavensfeel's borgmatic /DATA/Apps job, so it also reaches Hetzner.
#
# The age PUBLIC key encrypts; the PRIVATE key is only needed to restore.
#   recipient file: /DATA/Apps/borgmatic/keys/age-vaultwarden.pub
#
# Install (heavensfeel):
#   sudo cp vaultwarden-export.sh /usr/local/bin/
#   sudo cp vaultwarden-export.service /etc/systemd/system/
#   sudo cp vaultwarden-export.timer /etc/systemd/system/
#   sudo systemctl daemon-reload && sudo systemctl enable --now vaultwarden-export.timer

VW_CONTAINER="${VW_CONTAINER:-vaultwarden}"
VW_URL="${VW_URL:-https://vault.example.com}"
VW_DATA="${VW_DATA:-/DATA/Apps/vaultwarden/data}"
VW_CONFIG="${VW_CONFIG:-$VW_DATA/config.json}"
EXPORT_DIR="${EXPORT_DIR:-/DATA/Apps/vaultwarden/export}"

PUBKEY_FILE="${PUBKEY_FILE:-/DATA/Apps/borgmatic/keys/age-vaultwarden.pub}"
AGE_IMAGE="${AGE_IMAGE:-alpine:latest}"

STAGE="${STAGE:-/tmp/vw-export.$$}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

command -v docker >/dev/null || die "docker not found"
[[ -f "$PUBKEY_FILE" ]] || die "age public key not found at $PUBKEY_FILE"

STAMP="$(date '+%Y-%m-%d')"
ARTIFACT="vaultwarden-$STAMP.tar.gz.age"
mkdir -p "$STAGE" "$EXPORT_DIR"
trap 'rm -rf "$STAGE"' EXIT

# ── 1. Admin API dump (cookie auth: POST token, then call the API) ────
# Supplementary metadata only — the database is the essential artifact, so a
# failure here (e.g. Vaultwarden's admin-login rate limit / HTTP 429) must not
# abort the backup.
log "fetching admin API export"
python3 - "$VW_CONFIG" "$VW_URL" "$STAGE" <<'PY' || log "WARNING: admin API export failed; continuing with database only"
import json, sys, urllib.request, urllib.parse, http.cookiejar

config_path, base, stage = sys.argv[1:4]
token = json.load(open(config_path)).get("admin_token")
if not token:
    raise SystemExit("no admin_token in config")

jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
opener.open(
    urllib.request.Request(
        f"{base}/admin",
        data=urllib.parse.urlencode({"token": token}).encode(),
        method="POST",
    ),
    timeout=20,
)

def get(path):
    with opener.open(urllib.request.Request(f"{base}{path}"), timeout=20) as r:
        return json.loads(r.read().decode())

users = get("/admin/users")
json.dump(users, open(f"{stage}/users.json", "w"), indent=2)
print(f"users: {len(users)}")

for name, path in (("organizations.json", "/admin/organizations"),):
    try:
        json.dump(get(path), open(f"{stage}/{name}", "w"), indent=2)
        print(f"wrote {name}")
    except Exception as e:
        print(f"skipped {name}: {e}")
PY

# ── 2. Consistent SQLite backup via the built-in command ─────────────
# `vaultwarden backup` writes data/db_YYYYMMDD_HHMMSS.sqlite3 (timestamped).
# Prefer that over touching the live db.sqlite3, which is WAL-mode and would
# be inconsistent if copied while the service is running.
log "running vaultwarden built-in backup"
docker exec "$VW_CONTAINER" /vaultwarden backup 2>&1 | tail -2 || log "backup command warned"

NEWEST_BAK="$(ls -1t "$VW_DATA"/db_*.sqlite3 2>/dev/null | head -1 || true)"
if [[ -n "$NEWEST_BAK" ]]; then
  cp "$NEWEST_BAK" "$STAGE/db.sqlite3"
  log "captured $(basename "$NEWEST_BAK")"
else
  log "WARNING: no timestamped backup produced; skipping database to avoid an inconsistent WAL copy"
fi

# config.json holds the admin token + SMTP creds — included, but encrypted.
cp "$VW_CONFIG" "$STAGE/config.json" 2>/dev/null || true
# Attachments are user files; include them if present.
[[ -d "$VW_DATA/attachments" ]] && cp -r "$VW_DATA/attachments" "$STAGE/" 2>/dev/null || true

# ── 3. Tar + age-encrypt ──────────────────────────────────────────────
log "encrypting with age"
RECIPIENT="$(grep -oE 'age1[0-9a-z]+' "$PUBKEY_FILE" | head -1)"
[[ -n "$RECIPIENT" ]] || die "could not derive recipient from $PUBKEY_FILE"

tar -C "$STAGE" -czf - . \
  | docker run --rm -i "$AGE_IMAGE" \
      sh -c "apk add --no-cache age >/dev/null 2>&1 && age -r '$RECIPIENT' -o -" \
  > "$EXPORT_DIR/$ARTIFACT"

log "artifact: $ARTIFACT ($(du -h "$EXPORT_DIR/$ARTIFACT" | cut -f1))"

# ── 4. Local retention ────────────────────────────────────────────────
find "$EXPORT_DIR" -maxdepth 1 -name 'vaultwarden-*.tar.gz.age' \
  ! -name "$ARTIFACT" -mtime "+$RETENTION_DAYS" -delete 2>/dev/null || true

# The built-in backup leaves timestamped copies in the data dir; keep only the
# one we just used so the vault directory does not grow without bound. The
# files are written as root by the container, so delete via the container.
if [[ -n "${NEWEST_BAK:-}" ]]; then
  KEEP="$(basename "$NEWEST_BAK")"
  docker exec "$VW_CONTAINER" sh -c \
    "find /data -maxdepth 1 -name 'db_*.sqlite3' ! -name '$KEEP' -delete" 2>/dev/null \
    || log "note: could not prune old db_* backups (permissions)"
fi

ln -sfn "$ARTIFACT" "$EXPORT_DIR/.latest.tmp" && mv -Tf "$EXPORT_DIR/.latest.tmp" "$EXPORT_DIR/latest"
log "done"
