# Storage Architecture

## Physical Layout

All 5 data drives are in a USB 3.0 JBOD enclosure connected to **milis-wonderspace**.
Drives are mounted by UUID in `/etc/fstab` to `/mnt/disk[1-5]`.

| Mount | Size | Model |
|-------|------|-------|
| /mnt/disk1 | 6TB | Toshiba MB6000GEXXV |
| /mnt/disk2 | 6TB | WD Red WD60EFRX |
| /mnt/disk3 | 6TB | Toshiba MB6000GEXXV |
| /mnt/disk4 | 6TB | Seagate Enterprise ST6000NM0115 |
| /mnt/disk5 | 8TB | Seagate BarraCuda ST8000DM004 |

**Total raw**: ~32TB | **MergerFS pool**: ~29TB

## MergerFS Pool

All 5 disks are merged via mergerFS into a single pool at `/mnt/network`.

### Policies

| Setting | Value |
|---------|-------|
| Create | `epmfs` (existing path, most free space) |
| Readdir | `seq` (sequential) |
| Min free space | 100G per disk |
| Cache files | `off` (avoids double-caching with kernel page cache) |
| Cache attributes | 5s |

### fstab entry

```
/mnt/disk1:/mnt/disk2:/mnt/disk3:/mnt/disk4:/mnt/disk5
  /mnt/network  fuse.mergerfs
  defaults,allow_other,use_ino,nonempty,
  category.create=epmfs,moveonenospc=true,
  minfreespace=100G,cache.files=off,
  fsname=mergerfs-nas  0  0
```

## NFS Export

The pool and app data are exported via NFS to the other two nodes:

| Export | Clients | Options |
|--------|---------|---------|
| `/mnt/network` | 192.168.50.0/24 | rw,sync,no_subtree_check,no_root_squash |
| `/DATA` | 192.168.50.0/24 | rw,sync,no_subtree_check,no_root_squash |

### Client mounts (Ubuntu)

```
192.168.50.115:/mnt/network  /mnt/network  nfs
  rw,_netdev,nofail,hard,bg,timeo=600,retrans=5,actimeo=3  0  0
```

Uses `hard,bg` — processes hang until NFS recovers rather than returning stale file
handles. Background retries at boot prevent mount failures from blocking startup.

## Known Limitations

### USB Bridge (BOT Protocol)

The JMS578 bridge chip in the enclosure only exposes Bulk-Only Transport (BOT),
not USB Attached SCSI (UAS). This limits queue depth to 1 I/O at a time.

| Metric | BOT (current) | UAS (ideal) |
|--------|---------------|-------------|
| Queue depth | 1 | 32–256 |
| Sequential read | ~70 MB/s (fio) | ~200 MB/s |
| Random I/O | Poor | Good |

### Stale Mounts

Under heavy I/O, the USB bus can reset and re-enumerate all drives with new
device names. UUID-based fstab handles this on reboot, but live mounts become
stale. The `detect-stale-network` service (see `scripts/detect-stale-network.sh`) detects and recovers
from this automatically every 10 minutes.

### Drive Health

SMART health checks run weekly via `smart-health-check.service` (see `scripts/smart-health-check.sh`).
Results are saved to `/DATA/Logs/smart-health/`. Most drives are pre-owned with
significant power-on hours — monitor pending sector counts and plan replacements
as needed.
