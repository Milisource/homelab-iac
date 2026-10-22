# On-Demand GPU LLM (vastctl)

**Status**: live (verified 2026-10-11) · **Where**: operator workstation + a rented Vast.ai instance
**Cost model**: per session, destroyed afterwards — nothing bills between sessions

## Why

All three cluster nodes are CPU-only, and there is no hosted API for every model worth running.
Rather than buying a GPU to sit idle, `scripts/vastctl.sh` rents one for the length of a session,
serves an OpenAI-compatible endpoint over an SSH tunnel, and **destroys** the instance afterwards.

Vast.ai was chosen on price (~$0.10–0.14/h for an RTX 3090, verified Oct 2026). **Vast
Serverless was deliberately rejected** for this workload: it bills GPU compute during model load
and bills storage continuously for cold workers, so a single occasional user pays the same as a
pod plus an endpoint and workergroup to manage. Revisit only if this becomes a shared, always-warm
endpoint.

## Profiles

GPU and quantisation are chosen together so the weights fit in VRAM:

| Profile | GPU | VRAM | Quant | Disk | ~$/h |
|---|---|---|---|---|---|
| **cheap** (default) | RTX 3090 | 24 GB | Q4_K_M (~18 GB) | 40 GB | ~0.10–0.14 |
| fast | RTX 4090 | 24 GB | Q4_K_M | 40 GB | ~0.16–0.40 |
| quality | L40S | 46 GB | Q8_0 (~32 GB) | 70 GB | ~0.54 |
| max | A100 SXM4 | 80 GB | Q8_0 | 90 GB | ~1.2 |

## Architecture

- Image `ollama/ollama`, digest-pinned. **Vast does not run a third-party image's CMD** — its
  launcher only keeps the container alive — so `up` starts `ollama serve` over **SSH** once the
  instance reports `running`.
- `OLLAMA_HOST=127.0.0.1:11434` (loopback only), `OLLAMA_KEEP_ALIVE=-1`.
- **No published ports.** The client reaches the API through an **SSH tunnel**, so the box is
  never exposed to the internet. This is the main surface-area win.
- Host selection: `verified=true`, reliability ≥ 0.98, **`cuda_max_good ≥ 12.4`** (Ollama needs a
  ≥ 550 driver or it silently runs on **CPU**), **`inet_down ≥ 400` Mbps** (excludes the crawl tier
  where an 18 GB model pull takes ~24 min), then ranked by **estimated session cost**
  (`dph_total × session_hours + inet_down_cost × model_GB`) because nearly every host bills
  ingress and the model is re-pulled every session. `offers` prints the estimate.
- **No `--onstart`.** A custom onstart stalled the `running` transition; provisioning plainly and
  starting the server over SSH is faster and easier to debug.
- **`setsid` for detachment.** A plain `nohup … &` flaked, and a backgrounded serve launcher held
  the SSH channel open, hanging `up`.

## Usage

```bash
# one-time: vastai CLI authenticated, key in ~/.config/vastai/
./scripts/vastctl.sh offers                 # browse without renting
./scripts/vastctl.sh up                     # rent + serve (default TTL 4h, retries up to 5 offers)
./scripts/vastctl.sh tunnel                 # second terminal: expose the API on localhost
./scripts/vastctl.sh status | logs | hosts  # inspect
./scripts/vastctl.sh down                   # stop all billing
```

`up` auto-retries on bad offers (default 5), caps provisioning at 6 minutes, and keeps a per-host
scorecard (`hosts`). `vastctl-test.sh` is the acceptance probe — it checks that the model is on
GPU, reports throughput, and fails loudly instead of reporting a silent CPU fallback.

## Safety: the reaper

`vastctl.sh reap` is **stateless and label-based**. Every instance is labelled
`vastctl-llm-<ttl>h`, so the reaper can find and destroy expired instances without a local state
file — including instances rented from a different machine. It runs from a **user** timer
(`scripts/vastctl-reap.user.{service,timer}`, every 15 minutes, no root, API key stays in the
operator's home).

## Pinned versions

| Thing | Pin |
|---|---|
| Ollama image | digest, not the `latest` tag |
| Quant | `Q4_K_M` (override via `VASTCTL_HF_GGUF_REPO`) |
| CLI | `vastai` 1.8.3 (`uv tool install`) |

Ollama's Hugging Face pull (`hf.co/<repo>:<quant>`) can select a repo and quant but **not a
revision**. The model is therefore pinned **by verification**: `up` records the pulled model id in
state, and a later pull yielding a different id means the weights changed. The image itself is
digest-pinned, so the runtime cannot drift.

## Troubleshooting (observed, all fixed)

| Symptom | Cause | Fix |
|---|---|---|
| Instance `running` but no API | Vast ignored the image CMD | start `ollama serve` over SSH |
| Slow replies, GPU idle | old host driver → CPU inference | require `cuda_max_good ≥ 12.4` + preflight |
| Model pull crawls | slow host | require `inet_down ≥ 400` (800 proved over-strict) |
| `up` hangs | backgrounded launcher held the SSH channel | detach with `setsid` |
| `up` stalls in `loading` | custom `--onstart` | drop it; provision then start over SSH |
