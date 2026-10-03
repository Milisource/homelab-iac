#!/usr/bin/env bash
set -euo pipefail

# vaultwarden-gdrive-upload.sh — Pull the age-encrypted Vaultwarden export from
# heavensfeel and push it to Google Drive, mirroring Borg-style retention.
# Runs on MILIS-WONDERSPACE (the only node with rclone + the gdrive remote).
#
# The artifact is already encrypted (age) by vaultwarden-export.sh on
# heavensfeel, so Google only ever sees ciphertext. The age PRIVATE key is
# NOT on this host and is never uploaded — without it the Drive copies are
# unrecoverable, so keep an offline copy.
#
# Install (milis-wonderspace):
#   sudo cp vaultwarden-gdrive-upload.sh /usr/local/bin/
#   sudo cp vaultwarden-gdrive-upload.service /etc/systemd/system/
#   sudo cp vaultwarden-gdrive-upload.timer /etc/systemd/system/
#   sudo systemctl daemon-reload && sudo systemctl enable --now vaultwarden-gdrive-upload.timer

HF_HOST="${HF_HOST:-192.168.50.129}"               # heavensfeel (IP, not an alias)
HF_EXPORT_DIR="${HF_EXPORT_DIR:-/DATA/Apps/vaultwarden/export}"
GDRIVE_REMOTE="${GDRIVE_REMOTE:-gdrive:homelab-backups/vaultwarden}"
LOCAL_MIRROR="${LOCAL_MIRROR:-/mnt/network/Backups/vaultwarden}"

STAGE="${STAGE:-/tmp/vw-upload.$$}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

command -v rclone >/dev/null || die "rclone not found"
mkdir -p "$STAGE" "$LOCAL_MIRROR"
trap 'rm -rf "$STAGE"' EXIT

# ── 1. Health check: is the gdrive remote usable? ─────────────────────
# GDRIVE_REMOTE is "gdrive:homelab-backups/vaultwarden"; the remote itself is
# everything up to and INCLUDING the colon. Stripping the colon makes rclone
# treat it as a local folder ("gdrive"), which fails.
#
# This runs as root under systemd, where $HOME is /root and has no rclone
# config — so default to the owning user's config explicitly. Override with
# RCLONE_CONF if the token lives elsewhere.
GDRIVE_NAME="${GDRIVE_REMOTE%%:*}"
RCLONE_CONF="${RCLONE_CONF:-/home/user/.config/rclone/rclone.conf}"
[[ -r "$RCLONE_CONF" ]] || die "rclone config not readable at $RCLONE_CONF"
RCLONE=(rclone --config "$RCLONE_CONF")

if ! "${RCLONE[@]}" lsd "$GDRIVE_NAME:" >/dev/null 2>&1; then
  die "rclone remote '$GDRIVE_NAME:' unavailable using $RCLONE_CONF (token expired? run: rclone config reconnect $GDRIVE_NAME:)"
fi

# ── 2. Pull the newest artifacts from heavensfeel ─────────────────────
log "pulling exports from $HF_HOST"
REMOTE_FILES="$(ssh "${SSH_OPTS[@]}" "$HF_HOST" \
  "find '$HF_EXPORT_DIR' -maxdepth 1 -name 'vaultwarden-*.tar.gz.age' -printf '%f\n' 2>/dev/null" || true)"

[[ -n "$REMOTE_FILES" ]] || die "no export artifacts found on $HF_HOST at $HF_EXPORT_DIR"

while read -r f; do
  [[ -n "$f" ]] || continue
  scp "${SSH_OPTS[@]}" "$HF_HOST:$HF_EXPORT_DIR/$f" "$STAGE/" >/dev/null 2>&1 \
    && log "fetched $f" || log "failed to fetch $f"
done <<< "$REMOTE_FILES"

# ── 3. Verify every artifact actually decrypts (integrity check) ──────
# We cannot decrypt without the private key, but age files have a header we
# can sanity-check, and we confirm non-zero size + gzip magic after decrypt
# would require the key. Here we at least assert the age header.
for f in "$STAGE"/*.tar.gz.age; do
  [[ -e "$f" ]] || continue
  if head -c 30 "$f" | grep -q "age-encryption.org"; then
    log "verified age header: $(basename "$f")"
  else
    die "artifact $(basename "$f") is not a valid age file"
  fi
done

# ── 4. Upload to Google Drive ─────────────────────────────────────────
log "uploading to $GDRIVE_REMOTE"
"${RCLONE[@]}" copy "$STAGE" "$GDRIVE_REMOTE/" --include '*.age' --no-traverse 2>&1 | tail -3

# ── 5. Retention: 7 daily / 4 weekly / 6 monthly ──────────────────────
log "pruning Drive copies (7d / 4w / 6m)"
python3 - "$GDRIVE_REMOTE" "$RCLONE_CONF" <<'PY'
import subprocess, sys, json, datetime, re, collections

remote, rclone_conf = sys.argv[1], sys.argv[2]
RCLONE = ["rclone", "--config", rclone_conf]
raw = subprocess.run(
    RCLONE + ["lsjson", remote, "--files-only"],
    capture_output=True, text=True,
).stdout
try:
    files = json.loads(raw)
except Exception:
    print("could not list remote; skipping prune")
    raise SystemExit

dated = []
for f in files:
    m = re.match(r"vaultwarden-(\d{4}-\d{2}-\d{2})\.tar\.gz\.age$", f["Name"])
    if m:
        dated.append((datetime.date.fromisoformat(m.group(1)), f["Name"]))
dated.sort(reverse=True)

today = datetime.date.today()
keep, seen_days = set(), 0
weekly, monthly = collections.OrderedDict(), collections.OrderedDict()

for d, name in dated:
    age_days = (today - d).days
    if age_days <= 7 and seen_days < 7:
        keep.add(name); seen_days += 1
    elif age_days <= 28:
        wk = d.isocalendar()[:2]
        if wk not in weekly and len(weekly) < 4:
            weekly[wk] = name; keep.add(name)
    elif age_days <= 190:
        mo = (d.year, d.month)
        if mo not in monthly and len(monthly) < 6:
            monthly[mo] = name; keep.add(name)

for d, name in dated:
    if name not in keep:
        print(f"pruning {name}")
        subprocess.run(RCLONE + ["deletefile", f"{remote}/{name}"], check=False)
print(f"kept {len(keep)} of {len(dated)}")
PY

# ── 6. Local mirror for Borg to pick up ───────────────────────────────
# This is the bridge into the Borg source tree, so a failure here must be
# visible rather than silently skipped (it was previously masked by `|| true`).
log "mirroring locally for Borg"
mkdir -p "$LOCAL_MIRROR" || die "cannot create $LOCAL_MIRROR (wrong owner? created by root?)"
cp "$STAGE"/*.age "$LOCAL_MIRROR/" || die "cannot write to $LOCAL_MIRROR"
log "mirrored $(ls -1 "$LOCAL_MIRROR"/*.age 2>/dev/null | wc -l) artifact(s)"

log "done"
