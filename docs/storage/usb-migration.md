## Hardware Constraints (Dell Inspiron 3668)
The primary storage node in this Homelab setup is a Dell Inspiron 3668 with an **Intel H110 chipset** (not B250).

### Motherboard — Dell 07KY25
| Component | Detail |
|-----------|--------|
| Chipset | Intel H110 |
| SATA | **4 ports** (SATA 0–3, AHCI), 3 free (1 used for boot SSD) |
| PSU | 240W stock Dell (proprietary pinout, standard ATX size, **limited** SATA Power) |
| PCIe x16 | PCIe 3.0, direct to CPU — full speed for HBA |
| PCIe x1 | PCIe 2.0 from PCH (~500 MB/s ceiling) |
| M.2 | Key E only (WiFi/BT) — not usable for storage |

### Internal Drive Bays

- **1× 3.5"** — holds boot SSD
- **1× 5.25" optical** — can be adapted to hold a 3.5" HDD ($10–15 bracket)
- **Max internal capacity**: 2× 3.5" HDDs (one native, one optical bay adapter)
- **Remaining 3 drives**: must go external regardless

### PSU Concern

The 240W PSU is marginal when adding 5× 3.5" HDDs (~25W peak spin-up each) and an HBA (~10-15W). Staggered spin-up helps, but long-term the PSU should be upgraded. The Dell Inspiron 3668 uses a standard **ATX form factor PSU** but with a **Dell-proprietary 8-pin motherboard pinout**. This can be handled either by:
- Buying a Dell OEM replacement PSU (higher wattage variant, up to 300W existed for this model)
- Using a standard ATX PSU + Dell 8-pin to standard 24-pin adapter cable ($10)

## Revised Paths
### Path A: Internal SATA + PCIe SATA Card (Not Recommended!)
Use the 3 free native SATA ports + a SATA controller in the x16 slot. This is a pain. We're likely going to have to replace the case, motherboard and PSU to make this work. It's really not gonna be fun and I would entirely rather just not do this. It's a homelab, not Enterprise hardware.

---

### Path B: SAS HBA + External JBOD (Recommended-ish!)
An LSI/Broadcom SAS HBA in IT (passthrough) mode in the x16 slot, connected to a proper external JBOD enclosure. Unfortunately, it **is**, actually, Enterprise hardware. But it should be *cheap* Enterprise hardware..?

#### Required Hardware

| Item | Purpose | Est. Cost |
|------|---------|-----------|
| **LSI SAS 9207-8e** (used, pre-flashed IT mode) | HBA with external SFF-8088 ports | $25–55 |
| **Full-height bracket** | 9207-8e ships low-profile; 3668 needs full-height | $5–10 |
| **SFF-8088 to SFF-8088 cable** | HBA → enclosure, 1–2m | $15–25 |
| **SAS2/SAS3 JBOD shelf** (separately powered) | Houses drives with proper backplane | $100–250 |
| **PSU upgrade** (optional, technically) | Replace 240W with 400W+ ATX | $50–80 |
| **Dell PSU adapter cable** | Standard ATX → Dell motherboard pinout | $10 |

**Total: ~$170–400** without PSU upgrade, ~$230–490 with.

#### Enclosure Options (Recommended: Supermicro SAS Shelves)

The best value per bay is a used Supermicro JBOD. Many, many more bayst than we will ever use, but we don't necessarily have to use all of them, and it's much cheaper than trying to find a 5-6 bay enclosure.

| Chassis | Type | Bays | Backplane | Est. Cost | Notes |
|---------|------|------|-----------|-----------|-------|
| **Supermicro SC826** | 2U rackmount | **12× 3.5"** | SAS2 (SFF-8088) | $100–200 | Best balance — quiet enough with PSU swap, 2U fits anywhere, I think. |
| Supermicro SC846 | 4U rackmount | **24× 3.5"** | SAS2 (SFF-8088) | $150–250 | Endgame, but loud stock PSUs |
| Supermicro SC836 | 3U rackmount | **16× 3.5"** | SAS2 (SFF-8088) | $100–180 | Good middle ground, but rarer, probably more expensive |
| Dell PowerVault MD1200 | 2U rackmount | **12× 3.5"** | SAS2 (SFF-8088) | $80–150 | Cheap but loud, needs Dell→generic cable |

**Likely Candidate: Supermicro SC826** — 12 bays for $100-200, SAS2 backplane with SFF-8088 input, dual PSU (one removable for quiet), hot-swap trays included.
**SC826 N.T.S**: Stock PSUs are 80+ gold and relatively quiet at idle. If noise becomes unbearable somewhere along the line still, we might need a quieter PSU or just use the single PSU.

#### LSI Card Comparison

| Card | PCIe | External Ports | Notes |
|------|------|----------------|-------|
| **LSI SAS 9207-8e** | 3.0 x8 | 2× SFF-8088 | **PLEASE PICK THIS** — external ports on bracket, no routing hack needed, path of least resistance and it's proper |
| LSI SAS 9300-8e | 3.0 x12 | 2× SFF-8644 | SAS3, future-proof if you ever get a SAS3 shelf, costs more |
| LSI SAS 9207-8i | 3.0 x8 | 2× SFF-8087 (internal) | Only if 8e is unavailable — requires passthrough bracket |
| LSI SAS 9211-8i | 2.0 x8 | 2× SFF-8087 (internal) | Older gen, PCIe 2.0, fine for HDDs |

The 9207-8e is the sweet spot — PCIe 3.0 x8, external ports, $25-55 used, widely available pre-flashed in IT mode. Thank god for Homelab communities.

#### Cable Routing in the Dell 3668

With a 9207-8e card, the SFF-8088 ports are on the card's bracket itself — no passthrough needed.

```
Rear panel (simplified):
┌─────────────────────┐
│ [I/O shield]         │
│ [HBA — x16 slot]     │ ← 9207-8e with SFF-8088 ports on bracket
│ [  SFF-8088 ports]   │   ← Cable plugs directly here → to SC826
│ [blank / empty]      │
│ [PSU fan]            │
└─────────────────────┘
```

One SFF-8088 cable from the HBA to the JBOD shelf. That's it. Seriously.