#!/usr/bin/env bash
set -euo pipefail

# detect-stale-network.sh — Detect stale /mnt/network and recover
# Deployed to all 3 homelab nodes. Runs as root via systemd timer.
#
# Install:
#   sudo cp detect-stale-network.sh /usr/local/bin/
#   sudo cp detect-stale-network.{service,timer} /etc/systemd/system/
#   sudo systemctl daemon-reload
#   sudo systemctl enable --now detect-stale-network.timer
#
# Manual trigger (user without sudo, requires polkit rules):
#   systemctl start detect-stale-network.service

LOG=/var/log/stale-network-recovery.log
TIMEOUT_SEC=10
RETRY_COUNT=2
HOSTNAME=$(hostname -s)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

# Ensure docker-compose-plugin is in PATH for systemd
export PATH="/usr/local/bin:/usr/bin:/bin"

# ---- Per-node configuration ----
case "$HOSTNAME" in
  milis-wonderspace)
    COMPOSE_DIR="/home/user/docker/compose"
    COMPOSE_FILE="milis-wonderspace.yml"
    CONTAINERS="download-client sonarr radarr lidarr bazarr navidrome komga slskd copyparty"
    MOUNT_TYPE="mergerfs"
    PRE_CLEANUP_CMD="/usr/local/bin/cleanup-stale-mounts.sh"
    ;;
  milkymiracle)
    COMPOSE_DIR="/home/user/docker/compose"
    COMPOSE_FILE="milkymiracle.yml"
    CONTAINERS="jellyfin"
    MOUNT_TYPE="nfs"
    PRE_CLEANUP_CMD=""
    ;;
  heavensfeel)
    COMPOSE_DIR="/home/user/docker/compose"
    COMPOSE_FILE="heavensfeel.yml"
    CONTAINERS="n8n qui"
    MOUNT_TYPE="nfs"
    PRE_CLEANUP_CMD=""
    ;;
  *)
    log "Unknown hostname: $HOSTNAME, not a homelab node — skipping"
    exit 0
    ;;
esac

# ---- Detection ----
is_mount_healthy() {
  # First: verify /mnt/network is actually a mount point (not an empty dir)
  if ! mountpoint -q "/mnt/network"; then
    return 1
  fi

  # Second: verify the mount is responsive (not hung in I/O)
  # NOTE: If the NFS server is dead and the mount is in D-state (uninterruptible
  # kernel sleep), timeout cannot help. This is extremely rare with NFS v4.
  # The 10-minute timer ensures the next cycle catches any transient recovery.
  timeout "$TIMEOUT_SEC" ls "/mnt/network/" >/dev/null 2>&1
}

stale=false
for ((i=1; i<=RETRY_COUNT; i++)); do
  if is_mount_healthy; then
    stale=false
    break
  else
    log "Attempt $i/$RETRY_COUNT: /mnt/network not responsive"
    stale=true
    if [ "$i" -lt "$RETRY_COUNT" ]; then
      sleep 5
    fi
  fi
done

if [ "$stale" = false ]; then
  exit 0
fi

log "STALE DETECTED: /mnt/network ($MOUNT_TYPE) on $HOSTNAME"

# ---- Pre-cleanup (USB disks on server) ----
if [ -n "$PRE_CLEANUP_CMD" ]; then
  log "Running pre-cleanup: $PRE_CLEANUP_CMD"
  "$PRE_CLEANUP_CMD" >> "$LOG" 2>&1 || log "Pre-cleanup returned non-zero (continuing)"
fi

# ---- Remount ----
log "Force-unmounting /mnt/network..."
if ! umount -fl "/mnt/network" 2>/dev/null; then
  log "umount -fl failed, trying lazy umount..."
  umount -l "/mnt/network" 2>/dev/null || true
fi

sleep 2

log "Remounting /mnt/network..."
if mount "/mnt/network" 2>> "$LOG"; then
  log "Remount successful"
else
  log "Remount FAILED — giving up this cycle"
  exit 1
fi

if is_mount_healthy; then
  log "Post-remount verification passed"
else
  log "Post-remount verification FAILED — mount appears broken"
  exit 1
fi

# ---- Restart containers ----
if [ -n "$CONTAINERS" ]; then
  log "Restarting containers: $CONTAINERS"
  COMPOSE_PATH="$COMPOSE_DIR/$COMPOSE_FILE"
  if cd "$COMPOSE_DIR" && docker compose -f "$COMPOSE_PATH" restart $CONTAINERS >> "$LOG" 2>&1; then
    log "All containers restarted successfully"
  else
    log "Some containers failed to restart"
  fi
else
  log "No containers configured for restart on $HOSTNAME"
fi

log "Recovery cycle complete"
