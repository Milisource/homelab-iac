# Homelab Drive Health Report
**Date:** March 14, 2026 (last full SMART dump)  
**Updated:** 2026-05-27 (new enclosure, health checks)  
**Source:** SMART data collected via smartctl

---

## Overview

All 5 drives are in the **Yottamaster PS500RU3** enclosure (JMS578 bridge, replaced the failed Orico JMS567 on 2026-05-27). All are **pre-owned** except disk5 and show varying degrees of historical wear. Current SMART overall-health self-assessment: **ALL PASSED** (as of 2026-05-27)

| Drive | Mount Point | Model | Capacity | Age (POH) | Health | Status |
|-------|-------------|-------|----------|-----------|--------|--------|
| disk1 | /mnt/disk1 | Seagate MB6000GEXXV | 6TB | 55,900+ hrs (~6.4 yrs) | PASSED | ⚠️ Stable but worn |
| disk2 | /mnt/disk2 | WD Red WD60EFRX | 6TB | 54,400+ hrs (~6.2 yrs) | PASSED | ⚠️ **Needs monitoring** |
| disk3 | /mnt/disk3 | Toshiba MB6000GEXXV | 6TB | 6,900+ hrs (~10 mos) | PASSED | ✅ Healthy |
| disk4 | /mnt/disk4 | Seagate ST6000NM0115 | 6TB | 54,500+ hrs (~6.2 yrs) | PASSED | ⚠️ Worn but stable |
| disk5 | /mnt/disk5 | Seagate ST8000DM004 | **8TB** | 433+ hrs (~18 days) | PASSED | ✅ Newest |

**Total Raw Capacity:** ~30.5TB  
**Effective Capacity (MergerFS):** ~29TB

---

## Individual Drive Details

### disk1: Toshiba MB6000GEXXV 6TB

**Identification**
- Serial: 27L5K0YMFUUB
- Firmware: HPG2
- Rotation: 7200 rpm
- Interface: SATA 3.0 (6.0 Gb/s)

**Usage Statistics**
- Power-On Hours: 54,531 (~6.2 years)
- Sectors Written: 486,426,683,168 (~227 TB)
- Sectors Read: 293,449,516,001 (~137 TB)
- Spin-Up Time: 10,559 ms (elevated)

**SMART Attributes**
| ID | Attribute | Value | Worst | Threshold | Status |
|----|-----------|-------|-------|-----------|--------|
| 5 | Reallocated Sector Ct | 16 | 100 | 10 | OK |
| 9 | Power-On Hours | 54,531 | 1 | 0 | Normal wear |
| 197 | Current Pending Sector | 0 | 200 | 0 | OK |
| 194 | Temperature | 30°C | 100 | 0 | OK |

**Error History**
- 44 Uncorrectable Errors (UNC) - all occurred at ~50,944 power-on hours (historical, pre-acquisition)
- No recent errors logged

**Assessment:** ⚠️ **Stable but worn**
- Has reallocated sectors (16) indicating past bad sectors
- Historical errors from previous owner era
- Currently operating normally with no pending issues
- Write cache disabled (suboptimal performance)

---

### disk2: WD Red WD60EFRX-68MYMN1 6TB

**Identification**
- Serial: WD-WXL1H8468YE5
- Firmware: 82.00A82
- Model Family: Western Digital Red
- Rotation: 5700 rpm
- Interface: SATA 3.1 (6.0 Gb/s)

**Usage Statistics**
- Power-On Hours: 52,917 (~6.0 years)
- Load Cycle Count: 14,448 (elevated - WD Red characteristic)
- Spin-Up Time: 8,925 ms

**SMART Attributes**
| ID | Attribute | Value | Worst | Threshold | Status |
|----|-----------|-------|-------|-----------|--------|
| 5 | Reallocated Sector Ct | 0 | 200 | 140 | OK |
| 197 | Current Pending Sector | **2** | 200 | 0 | ⚠️ **Warning** |
| 199 | UDMA CRC Error Count | **45** | 200 | 0 | ⚠️ **Warning** |
| 194 | Temperature | 30°C | 122 | 0 | OK |

**Error History**
- **1,108 Uncorrectable Read Errors** - concentrated at LBA 0x76f5d7b8 (~1.99 TB mark)
- 45 CRC errors (indicates interface/cable issues)
- Multiple read errors on the same LBA region

**Assessment:** ⚠️ **Needs Attention**
- **2 pending sectors** - drive is having trouble reading these and may reallocate if they fail
- **45 CRC errors** strongly suggest a loose SATA data cable or poor connection in the Orico enclosure
- High number of UNC errors at a specific LBA suggests possible physical damage or media degradation in one region

**Recommendations:**
1. ~~Check and reseat SATA cables~~ ✅ Enclosure replaced — the 45 CRC errors were likely from the Orico's aged backplane
2. Monitor pending sector count monthly
3. Consider replacing if pending sectors increase

---

### disk3: Toshiba MB6000GEXXV 6TB

**Identification**
- Serial: Z5IEK08EFUUB
- Firmware: HPG0
- Rotation: 7200 rpm
- Interface: SATA 3.0 (6.0 Gb/s)

**Usage Statistics**
- Power-On Hours: 5,529 (~8 months) - **youngest drive**
- Sectors Written: 19,000,068,824 (~8.9 TB)
- Sectors Read: 89,016,802,463 (~41.6 TB)

**SMART Attributes**
| ID | Attribute | Value | Worst | Threshold | Status |
|----|-----------|-------|-------|-----------|--------|
| 5 | Reallocated Sector Ct | 0 | 100 | 10 | OK |
| 9 | Power-On Hours | 5,529 | 87 | 0 | Healthy |
| 197 | Current Pending Sector | 0 | 200 | 0 | OK |
| 194 | Temperature | 32°C | 100 | 0 | OK |

**Error History**
- 1 Uncorrectable Error at 1,366 power-on hours (early life, likely from initial testing)
- Self-test was aborted (interrupted by host)

**Assessment:** ✅ **Healthy**
- Newest drive with lowest runtime
- No reallocated or pending sectors
- Temperature stable
- Write cache disabled (minor performance impact)

---

### disk4: Seagate ST6000NM0115-1YZ110 6TB

**Identification**
- Serial: ZAD95RAE
- Firmware: SN05
- Model Family: Seagate Enterprise Capacity 3.5 HDD
- Rotation: 7200 rpm
- Interface: SATA 3.1 (6.0 Gb/s)

**Usage Statistics**
- Power-On Hours: 53,144 (~6.1 years)
- Total LBAs Written: 134,913,883,632 (~63 TB)
- Total LBAs Read: 85,860,761,269 (~40 TB)
- Load Cycle Count: 162,043 (high but expected for this model)

**SMART Attributes**
| ID | Attribute | Value | Worst | Threshold | Status |
|----|-----------|-------|-------|-----------|--------|
| 1 | Raw Read Error Rate | 88,309,248 | 79 | 44 | OK |
| 5 | Reallocated Sector Ct | 0 | 100 | 10 | OK |
| 7 | Seek Error Rate | 4,036,296,929 | 96 | 45 | OK |
| 9 | Power-On Hours | 53,144 | 40 | 0 | Normal wear |
| 187 | Reported Uncorrect | 0 | 100 | 0 | OK |
| 188 | Command Timeout | 1 | 100 | 0 | OK |
| 194 | Temperature | 33°C | 67 | 0 | OK |
| 197 | Current Pending Sector | 0 | 100 | 0 | OK |

**Error History**
- No uncorrectable errors logged
- No pending defects

**Assessment:** ⚠️ **Worn but stable**
- Enterprise-grade drive, handling age well
- High seek error rate is normalized (common in older drives)
- No reallocated sectors
- Write cache enabled (good)
- Highest temperature readings but within acceptable range

---

## Summary & Recommendations

### Immediate Actions
1. **disk2:** Monitor pending sector count — if it increases, plan for replacement (CRC errors from old Orico backplane should not recur in Yottamaster)
2. **Enclosure:** Fix USB 3.0 speed — verify cable/adapter supports SuperSpeed, use rear blue port
3. **Performance:** Re-run fio benchmarks after USB 3.0 fix

### General Recommendations
- **Backup strategy:** With MergerFS providing no redundancy, maintain off-site backups of critical data
- **disk3** is your most reliable drive (newest, no issues)
- Consider adding a 5th drive for SnapRAID parity if you want data protection

### Monitoring
- Review SMART data monthly
- Check disk2 pending sectors especially
- Monitor temperatures (all within acceptable range)

---

## Notes
- All drives pre-owned from previous owner (except disk5)
- All drives passed SMART overall-health assessment
- MergerFS pool provides capacity but NO redundancy
- Enclosure: **Yottamaster PS500RU3** (5-bay, JMS578 bridge) — replaced the failed Orico JMS567 on 2026-05-27
- ⚠️ Enclosure currently connected at **USB 3.0 5Gbps (SuperSpeed)** — confirmed working on front blue port, but BOT-only (no UAS), queue depth 1
- ⚠️ **2026-07-10:** USB bus re-enumeration occurred under I/O load, changing all disk device nodes. See Storage Overview
- See Storage Overview for full enclosure comparison and current performance notes
