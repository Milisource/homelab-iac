#!/bin/bash
#
# Weekly SMART Health Check Script
# Run on: milis-wonderspace (192.168.50.115)
# Location: /opt/scripts/smart-health-check.sh
# Schedule: Weekly via systemd timer (smart-health-check.timer)
#
# Requires root (smartctl). Do NOT run directly.
# Trigger via systemd:
#   systemctl start smart-health-check.service
#
# Or enable the weekly timer:
#   sudo systemctl enable --now smart-health-check.timer
#
# Install:
#   sudo cp smart-health-check.sh /usr/local/bin/
#   sudo cp smart-health-check.{service,timer} /etc/systemd/system/
#   sudo cp homelab-scripts.polkit /usr/share/polkit-1/rules.d/
#   sudo systemctl daemon-reload

set -euo pipefail

DRIVE_MOUNTS=("/mnt/disk1" "/mnt/disk2" "/mnt/disk3" "/mnt/disk4" "/mnt/disk5")
OUTPUT_DIR="/DATA/Logs/smart-health"
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

mkdir -p "$OUTPUT_DIR" 2>/dev/null || echo "Warning: cannot create $OUTPUT_DIR — output files disabled" >&2

log() {
    echo "[$(date +'%H:%M:%S')] $*"
}

get_device_for_mount() {
    local mount_point="$1"

    # Preferred: parse /proc/mounts directly (fast, no I/O, can't hang on stale FS)
    local dev_path
    dev_path=$(awk -v m="$mount_point" '$2 == m { print $1; exit }' /proc/mounts 2>/dev/null) || true

    if [[ -z "$dev_path" ]]; then
        # Fallback: try df (may hang if mount is stale)
        dev_path=$(df --output=source "$mount_point" 2>/dev/null | tail -1) || true
    fi

    echo "$dev_path"
}

check_drive() {
    local mount_point="$1"
    local drive_name
    drive_name=$(basename "$mount_point")

    log "Checking $drive_name..."

    local dev_path
    dev_path=$(get_device_for_mount "$mount_point")

    if [[ -z "$dev_path" ]] || [[ "$dev_path" == "source" ]]; then
        echo "  Status: UNABLE TO DETECT DEVICE"
        return 1
    fi

    local smart_output
    smart_output=$(smartctl -a -d sat "$dev_path" 2>&1) || smart_output=$(smartctl -a "$dev_path" 2>&1) || {
        # smartctl accepts both full device (/dev/sda) and partition (/dev/sda1)
        echo "  Status: SMART NOT ACCESSIBLE"
        return 1
    }

    # Save full report
    if [[ -d "$OUTPUT_DIR" ]]; then
        echo "$smart_output" > "$OUTPUT_DIR/${drive_name}-${DATE}.txt"
    fi

    # Parse SMART attributes (output varies by vendor; empty = unknown)
    local health="" temp="" reallocated="" pending="" unc_errors="" power_on_hours="" model=""

    health=$(echo "$smart_output" | grep -i "SMART overall-health" | awk '{print $NF}')
    temp=$(echo "$smart_output" | grep "Temperature_Celsius" | awk '{print $10}' | head -1)
    [[ -z "$temp" ]] && temp=$(echo "$smart_output" | grep "Temperature:" | awk '{print $2}')
    reallocated=$(echo "$smart_output" | grep "Reallocated_Sector_Ct" | awk '{print $10}')
    pending=$(echo "$smart_output" | grep "Current_Pending_Sector" | awk '{print $10}')
    unc_errors=$(echo "$smart_output" | grep "Reported_Uncorrect\|Uncorrectable" | head -1 | awk '{print $10}')
    power_on_hours=$(echo "$smart_output" | grep "Power_On_Hours" | awk '{print $10}')
    model=$(echo "$smart_output" | grep "Device Model\|Model Family" | head -1 | awk -F: '{print $2}' | xargs)

    # Defaults for numeric fields
    reallocated="${reallocated:-0}"
    pending="${pending:-0}"
    unc_errors="${unc_errors:-0}"

    local status_icon="PASS"
    if [[ "${health:-}" != "PASSED" ]] && [[ -n "${health:-}" ]]; then
        status_icon="FAIL"
    elif [[ "${pending:-0}" -gt 0 ]] || [[ "${reallocated:-0}" -gt 100 ]]; then
        status_icon="WARN"
    fi

    echo "  Status: $status_icon ${health:-unknown}"
    echo "  Model: ${model:-unknown}"
    echo "  Power-On Hours: ${power_on_hours:-N/A}"
    echo "  Temperature: ${temp:-N/A}C"
    echo "  Reallocated Sectors: $reallocated"
    echo "  Pending Sectors: $pending"
    echo "  Uncorrectable Errors: $unc_errors"

    if [[ "${pending:-0}" -gt 0 ]]; then
        echo "  WARNING: Pending sectors detected!"
    fi
    if [[ "${reallocated:-0}" -gt 100 ]]; then
        echo "  WARNING: High reallocated sector count!"
    fi

    return 0
}

echo "========================================="
echo "SMART Health Check - $TIMESTAMP"
echo "========================================="

overall_status="OK"

for mount in "${DRIVE_MOUNTS[@]}"; do
    echo ""
    echo ">>> $(basename "$mount")"
    if check_drive "$mount"; then
        :
    else
        overall_status="ISSUES"
    fi
done

echo ""
echo "========================================="
echo "Summary: $overall_status"
echo "========================================="
echo ""
echo "Full reports saved to: $OUTPUT_DIR"
echo ""

if [[ "$overall_status" != "OK" ]]; then
    exit 1
fi

exit 0
