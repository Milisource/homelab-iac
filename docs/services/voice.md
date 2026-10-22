# Voice (Local Assist Pipeline)

**Satellite**: an old Android phone running the Home Assistant Companion app (minimal build)
**Pipeline host**: [heavensfeel](heavensfeel.md) — same node as Home Assistant, so STT/TTS is a
container-to-container hop
**Cloud dependency**: none

## Pipeline

```
phone (microWakeWord, on-device)
   │  wake → stream audio
   ▼
wyoming-whisper (STT, heavensfeel)  →  HA intent (built-in or openai_conversation)
   │                                        │
   ▼                                        ▼
wyoming-piper (TTS, heavensfeel)  ←─────────┘
```

The phone does **on-device** wake-word detection with **microWakeWord** inside the Companion app
(2026.3+). Audio is not streamed until the wake word fires, so no audio sits on the server and the
phone works while locked and in the background. That removes the usual `wyoming-openwakeword`
container entirely — only **two** pipeline services are needed.

If an LLM fallback is wanted, point HA's `openai_conversation` at a local `llama.cpp` server on the
[Steam Deck](../servers/steamdeck.md) instead of a cloud key (use the IP, not the hostname).

## Containers

Both live in `compose/nodes/heavensfeel.yml`, on `traefik-overlay`, with **no Traefik router** — HA
dials them by container name and the wire protocol is Wyoming protobuf, not HTTP.

| Container | Address from HA | Model / voice | Data |
|---|---|---|---|
| `wyoming-whisper` | `wyoming-whisper:10300` | `base.en` int8, `--beam-size 1`, entity prompt | `/DATA/Apps/wyoming-whisper` |
| `wyoming-piper` | `wyoming-piper:10200` | `en_US-lessac-medium` | `/DATA/Apps/wyoming-piper` |

The first start downloads the model into `/data`, so the container reports `health: starting` for a
minute or two. That is not a failure.

## Benchmark (N95, measured end-to-end over Wyoming)

A known sentence is synthesised with piper, the PCM is fed to whisper, and the round trip is
timed. Steady-state numbers:

| Config | 2.7 s utterance | RTF |
|---|---|---|
| `small-int8`, beam 5 | 3237 ms | **1.16** |
| `base-int8`, beam 5 | 1603 ms | 0.58 |
| **`base.en` int8, beam 1** | **1083 ms** | **0.41** |

`small-int8` is **slower than real time** — you wait longer than you spoke — which is why it is not
deployed. The live config is `base.en` + `--compute-type int8` + `--beam-size 1`, plus an
`--initial-prompt` listing entity names so proper nouns survive at 3× the speed. **If entities are
renamed, update the prompt or drop the flag** — a stale prompt biases the decoder toward names that
no longer exist.

Do not benchmark in parallel on this box: two concurrent transcriptions on four cores inverted the
result (RTF 1.16 vs 0.58) because they fought over the same threads.

## Gotchas

- **Wake word fires, then a text box and the on-screen keyboard appear.** That is not a wake-word
  fault: the Android app falls back to text when the selected Assist pipeline has no STT and/or TTS
  configured ([home-assistant/android#7201](https://github.com/home-assistant/android/issues/7201)).
  The fix is this pipeline, not the phone.
- **Saying the wake word again continues the session** without touching the screen (app ≥ 2026.4).
- **Deploy reporting is wrong, not the deploy.** `ansible-playbook playbooks/deploy.yml` can print
  `0 container(s) started/created` even when it created them, because `docker compose up` writes
  progress to stderr and the counter reads stdout. Check `docker ps`.

## Satellite security

The phone is a permanently unpatched Android device sitting on the same flat `/24` as the cluster.
Its only required endpoint is HA on `:8123`, so **block it from the WAN** and allow LAN only. If the
LAN is ever segmented, put it on the IoT VLAN with a single rule permitting `→ heavensfeel:8123`.
No Google account, no browser, no Play Store. This is risk reduction, not a clean bill of health —
the network rule is the actual control.
