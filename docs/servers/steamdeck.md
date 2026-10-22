# Steam Deck (burst-compute node)

**IP**: `192.168.50.145` (plain DHCP lease) · **Hostname**: `wondersteam`
**Hardware**: Steam Deck **LCD** (DMI `Jupiter`), Zen 2 4C/8T, 16 GB LPDDR5, RDNA2 8 CU
(`RADV VANGOGH`, ~8.4 GiB VRAM), 256 GB NVMe
**Role**: docked **burst-compute node** — **not a Swarm member; membership undecided**

!!! warning "Read this before adding it to the cluster"
    This box suspends, reboots into a different OS, and gets carried to the couch. A Swarm worker
    is a promise that tasks keep running, so joining it means leader-election churn,
    `Down`/`Ready` flapping, and services rescheduled for no reason. `--availability drain`
    reduces the damage but does not remove it from the raft quorum. It runs a **standalone**
    Docker Engine instead — observability without the cluster liability.

## State

| | |
|---|---|
| OS | Arch Linux (rolling), kernel 7.2.x, ~180 packages, **image deployment** (not hand-run `pacstrap`) |
| Boot | systemd-boot, Secure Boot disabled, 3 s timeout |
| Session | **headless** — `multi-user.target`, no DM, no X/Wayland/gamescope |
| Docker | 29.9.2, overlayfs, **Swarm inactive**, 0 containers |
| Compose | not installed (`docker compose` subcommand absent) |
| Inference | **native** `llama-cpp` + `ggml-vulkan`, `llama-server` build 11429 |
| GPU | `llama-server --list-devices` → `Vulkan0: AMD Custom GPU 0405 (RADV VANGOGH) (8433 MiB)` — offload works |
| Network | dock USB Ethernet, **negotiates 100 Mb/s, not 1 GbE** |
| Power | governor `powersave` (amd-pstate-epp), no TDP cap tooling, stock TDP |
| Sleep | suspend/hibernate **masked** |

Nothing is listening on `:8080` yet: there is no model file on the box and no `llama-server`
unit. Home Assistant treats the address as a placeholder LLM fallback.

## Why Arch, not SteamOS

The instinct ("least draw → Arch") is only half right. Idle draw is set by **which session is
running**, not by which packaging system owns `/usr`. A desktop session (gamescope + KDE) costs
2–3 GB RAM and 4–7 W before you run anything. Deleting the desktop is the optimisation; the
distro is incidental. Arch wins because it gives a current kernel, mesa/Vulkan and llama.cpp
without a read-only rootfs in the way.

## Model shortlist (8 GB VRAM, shared LPDDR5)

Measured 2026-10-22, `llama-server` b11429, `-ngl 99`, flash attention 1, ctx 2048:

| Model | pp512 | pp8192 | tg128 | tg128 @ 8k |
|---|---|---|---|---|
| **LFM2.5-8B-A1B** Q4_K_M | 426.1 | **389.2** | **53.8** | **47.9** |
| Qwen3.5-9B Q4_K_M | 113.2 | 100.8 | 12.5 | — |
| Granite-4.2-8B Q4_K_M | 116.3 | — | 14.4 | — |
| Qwen3.5-4B Q4_K_M | 195.7 | — | 22.0 | — |

**The MoE is the answer.** At the same ~5.3 GB footprint it decodes **4.3×** faster than the dense
9B and prefills **3.9×** faster at 8k. It also barely degrades with context (−8 % prefill,
−9 % decode from 2k to 8k) because only ~1.5B of 8.3B parameters are active per token — the memory
bus stops being the binding constraint. `MUL_MAT_ID` is confirmed on the Vulkan path, i.e. **not**
the CPU-fallback cliff that turns this class of model into ~3 tok/s.

Dense 12B–14B models are a known bad outcome here: they exceed 8 GB at Q4, partially offload, and
collapse to ~3 tok/s. Not worth re-confirming.

## Power: no headroom, but the battery is a UPS

On dock power with an **empty** battery, a sustained 8-CU load cut the box outright — the journal
stops mid-session. With an empty cell there is no buffer, so any transient above the supply is a
hard cut. Measured: ~8.8 W net into the battery while idle, 42.5 Wh pack, ~4.6 h from empty. The
supplied charger is therefore ~10–12 W, not the Deck's 45 W PSU, and the battery pays the
difference under load.

That is a **duty-cycle** question, not a capacity one: Assist bursts are seconds long at ~1 % duty,
and 8.8 W idle refills a burst in well under a minute. Keep the cell non-empty and it behaves like
a UPS.

## Caveats

- **Nothing durable lives here.** No backup source, no database, no Swarm volume. A wipe costs the
  model file.
- **No swap and no zram** — overshoot 14 GiB and it is an OOM kill. Keep weights ≤7 GB.
- Cheap docks can brown out USB-C power delivery and Ethernet on the same hub. If containers die
  when a model loads, that is the first suspect.
- Name resolution is inconsistent: the router resolves `wondersteam`, but the HA host's local
  resolver does not forward LAN names. **Use `192.168.50.145`, not the hostname.**

## Pending

1. DHCP reservation for the dock NIC.
2. A model file and a `llama-server` systemd unit.
3. Observability: `node_exporter` on `:9100`, Glances on `:61208`, Prometheus job, Uptime Kuma.
4. Optional TDP cap (`ryzenadj`) — stock TDP has no headroom on this supply.

```bash
ssh wondersteam 'llama-server --list-devices'   # → Vulkan0: AMD Custom GPU 0405 (RADV VANGOGH)
```
