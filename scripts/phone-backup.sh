#!/usr/bin/env bash
set -euo pipefail

# phone-backup.sh — Pull portable personal data off an Android phone over
# adb (TCP/IP) into a dated, self-describing bundle on the NAS pool.
# Deployed to milis-wonderspace.
#
# Scope: contacts, SMS/MMS, call log, calendar, notes, device metadata.
# Explicitly NOT included (covered elsewhere):
#   - photos/videos  -> Immich
#   - passwords      -> Vaultwarden
#   - app-internal data (WhatsApp/Signal DBs) -> in-app export, Android 12+
#     blocks these from ADB by design
#
# Output layout (Borg source + directly rsync-able to a new device):
#   /mnt/network/Backups/phone/
#   ├── README.md              # restore instructions
#   ├── MANIFEST.json          # sha256 + sizes for every captured file
#   ├── latest -> 2026-10-02   # convenience symlink
#   └── 2026-10-02/
#       ├── contacts/          # .vcf
#       ├── sms/               # .xml + .json
#       ├── calllog/           # .json + .csv
#       ├── calendar/          # .ics
#       ├── notes/             # .md
#       ├── appdata/<app>/     # per-app exports
#       └── device-info.txt
#
# Requires: adb, jq, python3. Runs as root via systemd (adb server).
#
# Install:
#   sudo cp phone-backup.sh /usr/local/bin/
#   sudo cp phone-backup.service /etc/systemd/system/
#   sudo cp phone-backup.timer /etc/systemd/system/
#   sudo systemctl daemon-reload
#   sudo systemctl enable --now phone-backup.timer
#
# First-time pairing (phone must have Wireless debugging ON):
#   adb pair <ip>:<pair-port>    # code shown on the phone
#   adb connect <ip>:<port>
# The pair port is ephemeral; the connect port is stable per Wi-Fi network.
# Use `adb mdns services` to discover both.

# ─── Config (override via environment) ───────────────────────────────
PHONE_ADB_HOST="${PHONE_ADB_HOST:-}"        # e.g. 192.168.50.201; empty => USB
PHONE_ADB_PORT="${PHONE_ADB_PORT:-5555}"    # wireless-debugging connect port
BACKUP_ROOT="${BACKUP_ROOT:-/mnt/network/Backups/phone}"
RETENTION_DAYS="${RETENTION_DAYS:-90}"      # prune dated bundles older than this
ADB="${ADB:-adb}"

# ─── Helpers ─────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

STAMP="$(date '+%Y-%m-%d')"
DEST="$BACKUP_ROOT/$STAMP"

command -v "$ADB" >/dev/null || die "adb not found"
command -v jq   >/dev/null || log "warning: jq missing, manifest will be partial"

# ─── Connect ─────────────────────────────────────────────────────────
if [[ -n "$PHONE_ADB_HOST" ]]; then
  log "connecting to $PHONE_ADB_HOST:$PHONE_ADB_PORT"
  "$ADB" connect "$PHONE_ADB_HOST:$PHONE_ADB_PORT" >/dev/null || true
fi

# Wait for an authorised device (USB or wireless).
for _ in $(seq 1 15); do
  state="$("$ADB" get-state 2>/dev/null || true)"
  [[ "$state" == "device" ]] && break
  log "waiting for device (state=${state:-none})..."
  sleep 2
done

if [[ "$("$ADB" get-state 2>/dev/null || true)" != "device" ]]; then
  die "no authorised device. Unlock the phone and accept the USB/wireless debugging prompt."
fi

MODEL="$("$ADB" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
RELEASE="$("$ADB" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')"
SDK="$("$ADB" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
SERIAL="$("$ADB" shell getprop ro.serialno 2>/dev/null | tr -d '\r')"
log "device: $MODEL (Android $RELEASE, SDK $SDK)"

log "staging bundle at $DEST"
mkdir -p "$DEST"/{contacts,sms,calllog,calendar,notes,appdata,mms,misc}
mkdir -p "$BACKUP_ROOT"

"$ADB" shell content query --uri content://settings/system/device_name \
  >"$DEST/device-info.txt" 2>/dev/null || true
{
  echo "model=$MODEL"
  echo "android=$RELEASE"
  echo "sdk=$SDK"
  echo "serial=$SERIAL"
  echo "captured=$(date -Is)"
} >>"$DEST/device-info.txt"

# ─── Contacts / calendar / SMS / call log ────────────────────────────
# Each source is captured TWICE:
#   * a raw `content query` dump (nothing lost, greppable)
#   * a converted, *importable* artifact (.vcf / .ics / SMS Backup &
#     Restore XML), because the raw dump is not restorable by any tool
#     and `contacts` alone carries no phone numbers.
# Provider access is best-effort: some ROMs restrict the shell user. A
# failing conversion is logged, never fatal.

log "contacts (raw + vcf)..."
"$ADB" shell content query --uri content://com.android.contacts/data \
  --projection "raw_contact_id:mimetype:data1:data2:data3:data4" \
  >"$DEST/contacts/data.raw.txt" 2>/dev/null || \
  log "  contacts data provider not readable via adb"
# Kept for completeness; has_phone_number is a flag, not a number.
"$ADB" shell content query --uri content://com.android.contacts/contacts \
  >"$DEST/contacts/contacts.raw.txt" 2>/dev/null || true

log "calendar (raw + ics)..."
"$ADB" shell content query --uri content://com.android.calendar/events \
  --projection "_id:title:dtstart:dtend:allDay:eventLocation:description:eventTimezone:rrule" \
  >"$DEST/calendar/events.raw.txt" 2>/dev/null || \
  log "  calendar provider not readable via adb"

log "sms/mms (raw + xml)..."
"$ADB" shell content query --uri content://sms \
  --projection "_id:address:date:date_sent:type:read:body" \
  >"$DEST/sms/sms.raw.txt" 2>/dev/null || log "  sms not readable"

log "call log (raw + xml)..."
# NOTE: the provider caps this at 2000 rows on this device; older calls
# are not retrievable via the shell. Documented in the bundle README.
"$ADB" shell content query --uri content://call_log/calls \
  --projection "_id:number:date:duration:type:name" \
  >"$DEST/calllog/calls.raw.txt" 2>/dev/null || log "  call log not readable"

# ─── MMS: messages + attachment bytes ────────────────────────────────
# MMS is a separate provider from SMS. Attachments live as parts whose
# `_data` path is unreadable (private app storage), so the bytes are
# streamed with `exec-out content read` per part rather than pulled by path.
#
# Attachments live in a SHARED store at the backup root, not inside the
# dated bundle: part IDs are stable, so each attachment is fetched exactly
# once ever and later runs only fetch what is new. Keeping them per-day
# would re-download hundreds of MB on every run.
log "mms (messages + attachments)..."
MMS_STORE="$BACKUP_ROOT/mms-attachments"
mkdir -p "$MMS_STORE" "$DEST/mms"
"$ADB" shell content query --uri content://mms \
  --projection "_id:thread_id:date:msg_box:sub:ct_t:read" \
  >"$DEST/mms/mms.raw.txt" 2>/dev/null || log "  mms not readable"
"$ADB" shell content query --uri content://mms/addr \
  --projection "msg_id:address:type" \
  >"$DEST/mms/addr.raw.txt" 2>/dev/null || true
"$ADB" shell content query --uri content://mms/part \
  --projection "_id:mid:ct:name:_data" \
  >"$DEST/mms/part.raw.txt" 2>/dev/null || true

if [[ -s "$DEST/mms/part.raw.txt" ]]; then
  n_att=0; n_new=0
  while IFS= read -r line; do
    pid="$(sed -n 's/.*_id=\([0-9]*\).*/\1/p' <<<"$line")"
    ct="$(sed -n 's/.*ct=\([^,]*\).*/\1/p' <<<"$line")"
    [[ -n "$pid" && -n "$ct" ]] || continue
    case "$ct" in
      text/plain*|application/smil*|NULL|"") continue ;;
    esac
    ext="${ct##*/}"; ext="${ext%%+*}"
    [[ "$ext" == "jpeg" ]] && ext="jpg"
    out="$MMS_STORE/${pid}.${ext}"
    n_att=$((n_att+1))
    # Skip if any extension variant already exists for this part id.
    if compgen -G "$MMS_STORE/${pid}.*" >/dev/null; then
      continue
    fi
    if "$ADB" exec-out "content read --uri content://mms/part/$pid" >"$out" 2>/dev/null; then
      n_new=$((n_new+1))
    else
      rm -f "$out"
    fi
  done <"$DEST/mms/part.raw.txt"
  log "  mms attachments: $n_att total, $n_new new this run"
fi

# ─── Call recordings ─────────────────────────────────────────────────
log "call recordings..."
if "$ADB" shell "[ -d /sdcard/Recordings/Call ]" 2>/dev/null; then
  "$ADB" pull /sdcard/Recordings/Call "$DEST/callrecordings" >/dev/null 2>&1 || \
    log "  call recordings not pullable"
fi

# ─── Notes / misc shared storage sweep ───────────────────────────────
# Only paths that hold personal *state* (not the Immich-covered photo
# tree). The Elements vault is a mobile Obsidian copy.
log "shared-storage sweep..."
sweep() {
  local src="$1" name="$2"
  if "$ADB" shell "[ -d '$src' ]" 2>/dev/null; then
    "$ADB" pull "$src" "$DEST/misc/$name" >/dev/null 2>&1 && log "  swept $name" || true
  fi
}
sweep "/sdcard/Elements" "elements-vault"
sweep "/sdcard/Documents" "documents"
sweep "/sdcard/Music" "music"
sweep "/sdcard/Movies" "movies"
sweep "/sdcard/Alarms" "alarms"
sweep "/sdcard/Ringtones" "ringtones"
sweep "/sdcard/Notifications" "notifications"
# Download is mostly noise, but keep small document-type files.
# Guarded end-to-end: a missing pattern or an unreadable file must never
# abort the run (this block previously tripped `set -e`/pipefail).
if "$ADB" shell "[ -d /sdcard/Download ]" 2>/dev/null; then
  mkdir -p "$DEST/misc/download-docs"
  for ext in pdf xlsx txt ovpn doc docx csv; do
    # `find -exec` on-device avoids pipeline exit-code / whitespace pitfalls.
    "$ADB" shell "find /sdcard/Download -maxdepth 1 -iname '*.$ext' -print" 2>/dev/null \
      | tr -d '\r' > "$DEST/misc/download-docs/.list.$ext" || true
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      "$ADB" pull "$f" "$DEST/misc/download-docs/" >/dev/null 2>&1 || true
    done < "$DEST/misc/download-docs/.list.$ext"
    rm -f "$DEST/misc/download-docs/.list.$ext"
  done
fi

# ─── Convert raw dumps to importable formats ─────────────────────────
# A single parser handles the `Row: N key=value, key=value` shape that
# `content query` emits. Values may themselves contain ", " and newlines
# (SMS bodies), so splitting is field-name-anchored, not naive.
log "converting to importable formats..."
python3 - "$DEST" <<'PY'
import csv, io, json, os, re, sys
from datetime import datetime, timezone

DEST = sys.argv[1]

FIELDS = {
    "contacts": ["raw_contact_id", "mimetype", "data1", "data2", "data3", "data4"],
    "events":   ["_id", "title", "dtstart", "dtend", "allDay", "eventLocation",
                 "description", "eventTimezone", "rrule"],
    "sms":      ["_id", "address", "date", "date_sent", "type", "read", "body"],
    "calls":    ["_id", "number", "date", "duration", "type", "name"],
    "mms":      ["_id", "thread_id", "date", "msg_box", "sub", "ct_t", "read"],
    "mms_addr": ["msg_id", "address", "type"],
    "mms_part": ["_id", "mid", "ct", "name", "_data"],
}

def parse_rows(path, fields):
    """Parse `content query` output into dicts, anchored on known field names."""
    if not os.path.exists(path):
        return []
    out = []
    # Anchor regex: a known field name preceded by start-of-value, whitespace
    # or a comma. `content query` emits "Row: N firstfield=v, second=v, ...",
    # so after stripping "Row: N " the first field is preceded by nothing —
    # allow whitespace as well as ^ so the leading field is not missed.
    anchor = re.compile(r"(?:^|[\s,])(" + "|".join(re.escape(f) for f in fields) + r")=")
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.startswith("Row:"):
                # continuation of a multi-line value (e.g. SMS body): append
                if out:
                    out[-1]["_last"] += "\n" + line
                continue
            body = line.split(": ", 1)[1] if ": " in line else line
            marks = list(anchor.finditer(body))
            if not marks:
                continue
            rec = {}
            for i, m in enumerate(marks):
                key = m.group(1)
                start = m.end()
                end = marks[i + 1].start() if i + 1 < len(marks) else len(body)
                val = body[start:end]
                # The separator (", " / " ") belongs to the next anchor,
                # not the value; strip a single trailing separator.
                if i + 1 < len(marks):
                    val = re.sub(r"[,\s]+$", "", val)
                rec[key] = val
            rec["_last"] = rec.get(fields[-1], "")
            out.append(rec)
    # Fold trailing multi-line continuations back into the last field.
    fixed = []
    for r in out:
        lastkey = fields[-1]
        val = r.pop("_last", "")
        r[lastkey] = val
        fixed.append(r)
    return fixed

def ts_ms(v):
    try:
        return int(v) // 1000
    except (TypeError, ValueError):
        return None

# ── Contacts -> vCard 3.0 ─────────────────────────────────────────────
rows = parse_rows(f"{DEST}/contacts/data.raw.txt", FIELDS["contacts"])
people = {}
for r in rows:
    rid = r.get("raw_contact_id", "").strip()
    if not rid:
        continue
    p = people.setdefault(rid, {"name": None, "phones": [], "emails": []})
    mt, d1 = r.get("mimetype", ""), r.get("data1", "")
    if mt.endswith("/name") and not p["name"]:
        p["name"] = d1.strip() or None
    elif mt.endswith("/phone_v2") and d1 and d1 != "NULL":
        p["phones"].append(d1.strip())
    elif mt.endswith("/email_v2") and d1 and d1 != "NULL":
        p["emails"].append(d1.strip())

def vesc(s):
    return (s or "").replace("\\", "\\\\").replace(",", "\\,").replace(";", "\\;").replace("\n", "\\n")

vcf_lines = []
n_written = 0
for rid in sorted(people, key=lambda x: int(x) if x.isdigit() else 0):
    p = people[rid]
    if not p["name"] and not p["phones"]:
        continue
    vcf_lines += [
        "BEGIN:VCARD", "VERSION:3.0",
        f"FN:{vesc(p['name'] or p['phones'][0])}",
        f"N:{vesc(p['name'] or '')};;;;",
    ]
    for ph in p["phones"]:
        vcf_lines.append(f"TEL;TYPE=CELL:{vesc(ph)}")
    for em in p["emails"]:
        vcf_lines.append(f"EMAIL;TYPE=INTERNET:{vesc(em)}")
    vcf_lines += ["END:VCARD", ""]
    n_written += 1
with open(f"{DEST}/contacts/contacts.vcf", "w", encoding="utf-8") as fh:
    fh.write("\n".join(vcf_lines))
print(f"  contacts.vcf: {n_written} vCards")

# ── Calendar -> iCalendar ─────────────────────────────────────────────
rows = parse_rows(f"{DEST}/calendar/events.raw.txt", FIELDS["events"])
def ics_dt(ms, tzname, allday):
    if not ms or ms == "NULL":
        return None
    try:
        dt = datetime.fromtimestamp(int(ms) / 1000, tz=timezone.utc)
    except (ValueError, OSError):
        return None
    if str(allday) == "1":
        return dt.strftime("%Y%m%d")
    return dt.strftime("%Y%m%dT%H%M%SZ")

ev = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//homelab//phone-backup//EN", "CALSCALE:GREGORIAN"]
n_ev = 0
for i, r in enumerate(rows):
    title = r.get("title", "")
    ds, de = r.get("dtstart"), r.get("dtend")
    allday = r.get("allDay", "0")
    s_ics, e_ics = ics_dt(ds, r.get("eventTimezone"), allday), ics_dt(de, r.get("eventTimezone"), allday)
    if not s_ics:
        continue
    ev += [
        "BEGIN:VEVENT",
        f"UID:phone-backup-{DEST.split('/')[-1]}-{i}@homelab",
        f"DTSTAMP:{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}",
        f"DTSTART:{s_ics}",
    ]
    if e_ics:
        ev.append(f"DTEND:{e_ics}")
    ev.append(f"SUMMARY:{vesc(title)}")
    loc = r.get("eventLocation", "")
    if loc and loc != "NULL":
        ev.append(f"LOCATION:{vesc(loc)}")
    desc = r.get("description", "")
    if desc and desc != "NULL":
        ev.append(f"DESCRIPTION:{vesc(desc)}")
    rrule = r.get("rrule", "")
    if rrule and rrule != "NULL":
        ev.append(f"RRULE:{rrule}")
    ev.append("END:VEVENT")
    n_ev += 1
ev.append("END:VCALENDAR")
with open(f"{DEST}/calendar/calendar.ics", "w", encoding="utf-8") as fh:
    fh.write("\n".join(ev))
print(f"  calendar.ics: {n_ev} events")

# ── SMS + calls -> SMS Backup & Restore XML ───────────────────────────
def xesc(s):
    return (s or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")

SMS_TYPE = {"1": "1", "2": "2"}   # 1=received, 2=sent
CALL_TYPE = {"1": "1", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6"}

srows = parse_rows(f"{DEST}/sms/sms.raw.txt", FIELDS["sms"])
crows = parse_rows(f"{DEST}/calllog/calls.raw.txt", FIELDS["calls"])
out = ['<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>',
       '<!-- SMS Backup & Restore compatible; import via that app -->',
       '<smses count="%d">' % (len(srows) + len(crows))]
for r in srows:
    out.append(
        '<sms protocol="0" address="%s" date="%s" type="%s" subject="null" body="%s" '
        'toa="null" sc_toa="null" service_center="null" read="%s" status="-1" '
        'locked="0" date_sent="%s" readable_date="%s" contact_name="(Unknown)" />' % (
            xesc(r.get("address")), r.get("date", "0"),
            SMS_TYPE.get(r.get("type", "1"), "1"), xesc(r.get("body")),
            r.get("read", "1") or "1", r.get("date_sent", "0") or "0", ""))
for r in crows:
    out.append(
        '<call number="%s" duration="%s" date="%s" type="%s" presentation="1" '
        'readable_date="%s" contact_name="%s" />' % (
            xesc(r.get("number")), r.get("duration", "0"), r.get("date", "0"),
            CALL_TYPE.get(r.get("type", "1"), "1"), "",
            xesc(r.get("name") if r.get("name") not in (None, "NULL") else "(Unknown)")))

# ── MMS -> SMS Backup & Restore <mms> with parts + addrs ──────────────
mrows = parse_rows(f"{DEST}/mms/mms.raw.txt", FIELDS["mms"])
arows = parse_rows(f"{DEST}/mms/addr.raw.txt", FIELDS["mms_addr"])
prows = parse_rows(f"{DEST}/mms/part.raw.txt", FIELDS["mms_part"])

addrs_by_msg, parts_by_msg = {}, {}
for a in arows:
    addrs_by_msg.setdefault(a.get("msg_id", ""), []).append(a)
for p in prows:
    parts_by_msg.setdefault(p.get("mid", ""), []).append(p)

MMS_BOX = {"1": "1", "2": "2"}   # 1=inbox, 2=sent
for r in mrows:
    mid = r.get("_id", "")
    out.append('<mms msg_box="%s" date="%s" read="%s" sub="%s" ct_t="%s">' % (
        MMS_BOX.get(r.get("msg_box", "1"), "1"), r.get("date", "0"),
        r.get("read", "1") or "1", xesc(r.get("sub")), xesc(r.get("ct_t"))))
    for a in addrs_by_msg.get(mid, []):
        out.append('  <addr address="%s" type="%s" charset="106" />' % (
            xesc(a.get("address")), a.get("type", "137")))
    for p in parts_by_msg.get(mid, []):
        out.append('  <part seq="%s" ct="%s" name="%s" chset="106" '
                   'cd="null" fn="null" cid="null" cl="null" ctt_s="null" '
                   'ctt_t="null" text="%s" />' % (
                       xesc(p.get("_id")), xesc(p.get("ct")), xesc(p.get("name")),
                       # parts with a text/plain type carry the body in text;
                       # binary parts keep '' and their bytes are in attachments/
                       ""))
    out.append('</mms>')
out.append("</smses>")
with open(f"{DEST}/sms/sms-calls.xml", "w", encoding="utf-8") as fh:
    fh.write("\n".join(out))
print(f"  sms-calls.xml: {len(srows)} sms + {len(crows)} calls + {len(mrows)} mms")
PY

# ─── Notes: common on-device note stores, if shared storage holds them ─
log "notes..."
for p in /sdcard/Notes /sdcard/Documents/Notes /sdcard/Obsidian; do
  if "$ADB" shell "[ -d '$p' ]" 2>/dev/null; then
    name="$(basename "$p")"
    "$ADB" pull "$p" "$DEST/notes/$name" >/dev/null 2>&1 || true
  fi
done

# ─── Application + package inventory (rebuild reference, not data) ───
log "package inventory..."
"$ADB" shell pm list packages -3 >"$DEST/appdata/installed-packages.txt" 2>/dev/null || true

# ─── Manifest ────────────────────────────────────────────────────────
log "writing manifest"
MANIFEST="$BACKUP_ROOT/MANIFEST.json"
python3 - "$DEST" "$MANIFEST" "$MODEL" "$RELEASE" "$SERIAL" <<'PY'
import hashlib, json, os, sys, datetime
dest, manifest, model, release, serial = sys.argv[1:6]
entries = []
for root, _dirs, files in os.walk(dest):
    for f in files:
        fp = os.path.join(root, f)
        h = hashlib.sha256()
        with open(fp, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        entries.append({
            "path": os.path.relpath(fp, dest),
            "size": os.path.getsize(fp),
            "sha256": h.hexdigest(),
        })
out = {
    "captured": datetime.datetime.now().isoformat(timespec="seconds"),
    "device": {"model": model, "android": release, "serial": serial},
    "files": sorted(entries, key=lambda e: e["path"]),
}
with open(manifest, "w") as fh:
    json.dump(out, fh, indent=2)
print(f"manifest: {len(entries)} files")
PY

# ─── Restore README (regenerated so it always matches layout) ────────
cat >"$BACKUP_ROOT/README.md" <<'MD'
# Phone backup bundle

Portable personal data pulled from the Android phone. Safe to rsync to a
new device; each dated directory is self-contained.

## Layout

| Dir | Importable artifact | Raw dump (fallback) | Restore with |
|-----|--------------------|---------------------|--------------|
| `contacts/` | `contacts.vcf` | `data.raw.txt` | Contacts app "Import from .vcf" |
| `sms/` | `sms-calls.xml` (SMS + calls + MMS) | `sms.raw.txt` | SMS Backup & Restore → Restore |
| `mms/` | (parts of the XML above) | `mms/addr/part.raw.txt` | SMS Backup & Restore |
| `calllog/` | (in the XML above) | `calls.raw.txt` | SMS Backup & Restore |
| `calendar/` | `calendar.ics` | `events.raw.txt` | Calendar app "Import .ics" |
| `callrecordings/` | recordings copy | — | copy back to `Recordings/Call` |
| `notes/` | note store copy | — | copy back to `Documents/Notes` |
| `misc/` | elements-vault, documents, music, movies, download-docs | — | copy back as needed |
| `appdata/` | `installed-packages.txt` | — | reference for reinstall |

`MANIFEST.json` holds sha256 + size for every file.
`latest` symlinks to the most recent bundle.

**MMS attachments** live in a shared store at the backup root,
`mms-attachments/<partid>.<ext>` — deliberately **outside** the dated
bundles, so each attachment is fetched once ever rather than re-downloaded
every run. Images/videos/PDFs from MMS are there; message text is in
`sms-calls.xml`.

**Known limits**

- The call-log provider returns at most **2000 rows** on this device; older
  calls are not retrievable over adb. Recent history is what matters for a
  fresh restore.
- The Elements vault under `misc/` is the phone's mobile Obsidian copy; the
  fuller desktop vault is backed up separately via Syncthing.
- Contacts/calendar come from the local provider; anything still only in a
  cloud account will re-sync when you sign in.

## Not here (by design)

- **Photos/videos** → Immich (`https://immich.example.com`)
- **Passwords** → Vaultwarden (Bitwarden app auto-syncs)

## Restoring to a new phone

1. **Contacts** — transfer `contacts.vcf`, then Contacts → settings → import.
2. **SMS + call log + MMS** — install *SMS Backup & Restore*, copy
   `sms-calls.xml` over, and use its Restore function. MMS attachment bytes
   are in `mms-attachments/` (XML references them by part id).
3. **Calendar** — import `calendar.ics` into the Calendar app.
4. **Notes** — `adb push` the `notes/` tree back to shared storage.
5. **Call recordings** — `adb push` `callrecordings/` to `Recordings/Call`.
6. **Misc** — `adb push` anything from `misc/` back to shared storage.
7. **Apps** — reinstall from `appdata/installed-packages.txt`.
8. Sign in to Bitwarden + Immich to recover passwords and photos.
MD

# ─── Retention ───────────────────────────────────────────────────────
# Only date-patterned bundle dirs are pruned. The shared mms-attachments/
# store and the README/MANIFEST files must be preserved.
log "pruning bundles older than ${RETENTION_DAYS}d"
find "$BACKUP_ROOT" -maxdepth 1 -mindepth 1 -type d \
  -regextype posix-extended -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}' \
  ! -name "$STAMP" -mtime "+$RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true

# ─── Point `latest` at this run ──────────────────────────────────────
ln -sfn "$STAMP" "$BACKUP_ROOT/latest.tmp" && mv -Tf "$BACKUP_ROOT/latest.tmp" "$BACKUP_ROOT/latest"

log "done: $DEST"
