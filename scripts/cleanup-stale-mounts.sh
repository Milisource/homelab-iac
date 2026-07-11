#!/usr/bin/env bash
set -euo pipefail

# cleanup-stale-mounts.sh — Force-unmount stale USB mount points
# Deployed to milis-wonderspace. Runs as root via systemd.
#
# Requires root (umount -fl, blkid). Do NOT run directly.
# Trigger via systemd:
#   systemctl start cleanup-stale-mounts.service
#
# Install:
#   sudo cp cleanup-stale-mounts.sh /usr/local/bin/
#   sudo cp cleanup-stale-mounts.service /etc/systemd/system/
#   sudo cp homelab-scripts.polkit /usr/share/polkit-1/rules.d/
#   sudo systemctl daemon-reload
#
# Then the homelab user can run without sudo:
#   systemctl start cleanup-stale-mounts.service
#   systemctl status cleanup-stale-mounts.service

STALE_LOG=/var/log/stale-mount-cleanup.log

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$STALE_LOG" 2>/dev/null || true
}

get_fstab_uuid() {
  local mount_point="$1"
  grep -E "^UUID=[a-f0-9-]+[[:space:]]+$mount_point[[:space:]]" /etc/fstab | awk '{print $1}' | sed 's/^UUID=//'
}

clean_mount_point() {
  local mount_point="$1"
  local fstab_uuid
  fstab_uuid=$(get_fstab_uuid "$mount_point")

  if [[ -z "$fstab_uuid" ]]; then
    log "No fstab UUID for $mount_point, skipping"
    return
  fi

  while read -r dev mnt; do
    local uuid_dev
    uuid_dev=$(blkid -s UUID -o value "$dev" 2>/dev/null || echo "")

    if [[ "$uuid_dev" != "$fstab_uuid" ]]; then
      log "Stale: $dev on $mnt (uuid=$uuid_dev, expected=$fstab_uuid)"
      if umount -fl "$dev" 2>/dev/null; then
        log "  cleaned"
      else
        log "  busy (skipped)"
      fi
    fi
  done < <(mount | { grep " $mount_point " || true; })
}

case "${1:-all}" in
  all)
    for mp in /mnt/disk1 /mnt/disk2 /mnt/disk3 /mnt/disk4 /mnt/disk5; do
      clean_mount_point "$mp"
    done
    ;;
esac
