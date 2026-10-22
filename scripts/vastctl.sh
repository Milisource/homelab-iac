#!/usr/bin/env bash
set -euo pipefail

# vastctl.sh — rent a single-GPU Vast.ai box, serve an abliterated
# Qwen3-Coder-30B-A3B over an OpenAI-compatible API, then destroy the box.
#
# Why this shape
# ──────────────
# An on-demand Vast instance is the cheapest way to run a ~30B MoE model for
# occasional use, and *destroying* it (not stopping it) leaves nothing billing.
# The official `ollama/ollama` image is used unmodified — its default command
# is `ollama serve` — so the only moving part is a model pull driven through
# the Vast exec API. No ports are published: the endpoint is reached over an
# SSH tunnel, so the box is never exposed to the internet.
#
# Vast Serverless is deliberately NOT used here: it bills GPU compute during
# the model-load state and storage for idle "cold" workers, so for a single
# occasional user it costs the same as this pod while adding an endpoint +
# workergroup + template. It is the right tool only if this becomes a shared,
# continuously-bursty endpoint. See services/vast-llm.md.
#
# Prereqs (once, as the invoking user)
# ────────────────────────────────────
#   curl -fsSL https://vast.ai/install.sh | bash      # or: pip install vastai
#   vastai set api-key <KEY>                          # https://console.vast.ai/manage-keys/
#   vastai create ssh-key "$(cat ~/.ssh/id_ed25519.pub)"   # key material, not the path
#
# Usage
# ─────
#   vastctl.sh up      [--profile P] [--ttl-hours N] [--offer-id N] [--wait-min N] [--retries N]
#   vastctl.sh hosts             # per-host run history (provision/pull times, failures)
#   vastctl.sh status            # state, uptime, accrued cost
#   vastctl.sh tunnel            # ssh -L: OpenAI API at http://127.0.0.1:$PORT/v1
#   vastctl.sh ssh               # interactive shell
#   vastctl.sh logs              # container logs
#   vastctl.sh down              # destroy the box (stops all billing)
#   vastctl.sh reap              # destroy managed boxes past TTL (label-based,
#                                #   stateless — safe to run on an always-on node)
#   vastctl.sh offers [--profile P]   # show the shortlist without renting
#
# Profiles (GPU → quant → disk)
#   cheap   (default) RTX_3090 24GB → Q4_K_M   ~$0.14/h   lowest floor
#   fast              RTX_4090 24GB → Q4_K_M   ~$0.40/h
#   quality           L40S     46GB → Q8_0     ~$0.54/h
#   max               A100_SXM4 80GB → Q8_0    ~$1.2/h
#
# The open weights are the `huihui-ai` abliteration of Qwen3-Coder-30B-A3B,
# served from mradermacher's GGUF mirror. Override with VASTCTL_HF_GGUF_REPO.

# ── config (env-overridable) ─────────────────────────────────────────
STATE_DIR="${VASTCTL_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/vastctl}"
STATE_FILE="$STATE_DIR/current.env"
SCORE_FILE="$STATE_DIR/hosts.tsv"
DEFAULT_TTL_HOURS="${VASTCTL_TTL_HOURS:-4}"
MIN_RELIABILITY="${VASTCTL_MIN_RELIABILITY:-0.98}"
OLLAMA_PORT="${VASTCTL_OLLAMA_PORT:-11434}"
# Pinned by digest (tag `latest` as of 2026-10-11) so a re-pull can't change
# the runtime under us.
OLLAMA_IMAGE="${VASTCTL_OLLAMA_IMAGE:-ollama/ollama@sha256:adca95a12c2b386a8f9a995e7fa0600e187e3323b5e5522f5a6c3b1ec73eff99}"
HF_GGUF_REPO="${VASTCTL_HF_GGUF_REPO:-mradermacher/Huihui-Qwen3-Coder-30B-A3B-Instruct-abliterated-GGUF}"
# Short in-box alias, so the harness has a clean model id.
MODEL_ALIAS="${VASTCTL_MODEL_ALIAS:-qwen3-coder-abliterated}"
CONTEXT_LEN="${VASTCTL_CONTEXT_LEN:-32768}"
LABEL="vastctl-llm"
PROVISION_TIMEOUT_MIN="${VASTCTL_PROVISION_TIMEOUT_MIN:-6}"
# Host eligibility: a modern enough driver (Ollama needs ≥550 / CUDA ~12.4 to use
# the GPU at all, else it silently falls back to CPU) and enough bandwidth that
# an 18 GB pull doesn't crawl. The pull is HF-CDN-bound above ~500-700 Mbps, so a
# higher floor only buys pricier hosts for no faster download: 400 excludes the
# crawl-speed tier (~150 Mbps -> ~24 min pull) without paying for bandwidth the
# CDN cannot deliver.
MIN_CUDA="${VASTCTL_MIN_CUDA:-12.4}"
MIN_INET_DOWN="${VASTCTL_MIN_INET_DOWN:-400}"
# Assumed session length, used only to amortise the one-time model download
# against the hourly rate when ranking offers.
SESSION_HOURS="${VASTCTL_SESSION_HOURS:-2}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die()  { log "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found${2:+ — $2}"; }

# ── profile → GPU / quant / disk ─────────────────────────────────────
profile_settings() {
  case "$1" in
    cheap)   GPU_NAME="RTX_3090";  MIN_VRAM=24; QUANT="Q4_K_M"; DISK=40; MODEL_GB=18 ;;
    fast)    GPU_NAME="RTX_4090";  MIN_VRAM=24; QUANT="Q4_K_M"; DISK=40; MODEL_GB=18 ;;
    quality) GPU_NAME="L40S";      MIN_VRAM=45; QUANT="Q8_0";   DISK=70; MODEL_GB=32 ;;
    max)     GPU_NAME="A100_SXM4"; MIN_VRAM=79; QUANT="Q8_0";   DISK=90; MODEL_GB=32 ;;
    *) die "unknown profile '$1' (cheap|fast|quality|max)" ;;
  esac
}

# ── state ────────────────────────────────────────────────────────────
state_write() { mkdir -p "$STATE_DIR"; umask 077; cat > "$STATE_FILE"; }
state_load() {
  [[ -f "$STATE_FILE" ]] || die "no managed instance (run: vastctl.sh up)"
  # shellcheck disable=SC1090
  source "$STATE_FILE"
  [[ -n "${VAST_INSTANCE_ID:-}" ]] || die "state file has no instance id"
}
state_clear() { rm -f "$STATE_FILE"; }

# ── Vast helpers ─────────────────────────────────────────────────────
preflight() {
  need vastai "install: curl -fsSL https://vast.ai/install.sh | bash"
  # The CLI exits 0 even on a 403 and prints {"error": true, ...}, so the exit
  # code cannot be trusted — inspect the payload.
  if ! vastai show user --raw 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(1 if (not isinstance(d, dict)) or d.get("error") else 0)'; then
    die "vastai not authenticated (run: vastai set api-key <KEY>)"
  fi
  if ! vastai show ssh-keys 2>/dev/null | grep -q 'ssh-'; then
    die "no SSH key registered (run: vastai create ssh-key ~/.ssh/id_ed25519.pub)"
  fi
}

# Resolve the user/host/port of the instance's SSH endpoint.
ssh_parts() {
  local raw; raw="$(vastai ssh-url "$1" --raw 2>/dev/null || true)"
  [[ -n "$raw" ]] || return 1
  python3 - "$raw" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    d = json.loads(raw)
    url = d if isinstance(d, str) else (d.get("ssh_url") or d.get("url") or "")
except Exception:
    url = raw.strip().strip('"')
rest = url.split("ssh://", 1)[-1]
user = rest.split("@", 1)[0]
hostport = rest.split("@", 1)[1] if "@" in rest else rest
host, _, port = hostport.partition(":")
print("%s\t%s\t%s" % (user, host, port or "22"))
PY
}

# Run a command on the instance over SSH. `vastai execute` rejects compound
# commands (400), so SSH is the reliable path for anything non-trivial.
ssh_run() {  # <instance-id> <remote command>
  local parts user host port
  parts="$(ssh_parts "$1")" || return 1
  IFS=$'\t' read -r user host port <<<"$parts"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
      -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -p "$port" "$user@$host" "$2"
}

# Cheapest verified, reliable, big-enough offer — ranked by total *session*
# cost, not headline $/h. Every host charges ingress (inet_down_cost), and the
# model is re-pulled every session, so a host at $0.15/h + $0.016/GB can lose
# to one at $0.18/h + $0.003/GB. Filtered in python3, not query-syntax quirks.
find_offer() {
  local query="gpu_name=$GPU_NAME num_gpus=1 verified=true rentable=true disk_space>=$DISK"
  log "searching: $query" >&2
  vastai search offers "$query" -o 'dph_total' --limit 150 --raw 2>/dev/null \
  | python3 -c '
import json, os, sys
minrel = float(sys.argv[1]); need_gb = int(sys.argv[2])
model_gb = float(sys.argv[3]); sess_h = float(sys.argv[4])
min_cuda = float(sys.argv[5]); min_inet = float(sys.argv[6])
score = sys.argv[7]
good = set(); bad = set()
if score and os.path.exists(score):
    for line in open(score):
        p = line.rstrip("\n").split("\t")
        if len(p) >= 7:
            if p[6] == "1":
                good.add(p[2])
            elif p[6] == "0":
                bad.add(p[2])
try:
    offers = json.load(sys.stdin)
except Exception:
    offers = []
if not isinstance(offers, list):
    offers = []

def session_cost(o):
    return o["dph_total"] * sess_h + (o.get("inet_down_cost") or 0) * model_gb

def rank(o):
    h = str(o.get("host_id"))
    tier = 0 if h in good else (2 if h in bad else 1)
    return (tier, session_cost(o))

ok = [o for o in offers
      if o.get("verification") == "verified"
      and (o.get("reliability") or 0) >= minrel
      and (o.get("cuda_max_good") or 0) >= min_cuda
      and (o.get("inet_down") or 0) >= min_inet
      and (o.get("gpu_ram") or 0) >= need_gb * 1024 - 1024
      and (o.get("disk_space") or 0) >= need_gb]
# Prefer hosts with a prior success, then unknown, then known-bad.
ok.sort(key=rank)
for o in ok[:12]:
    print("%s\t%.4f\t%.5f\t%.3f\t%s\t%.1f\t%.0f\t%s\t%.3f\t%s\t%s" % (
        o["id"], o["dph_total"], o.get("inet_down_cost") or 0, session_cost(o),
        o.get("gpu_name"), o.get("cuda_max_good") or 0, o.get("inet_down") or 0,
        (o.get("geolocation") or "?"), o.get("reliability") or 0,
        round((o.get("cpu_ram") or 0) / 1024), o.get("host_id") or "?"))
' "$MIN_RELIABILITY" "$MIN_VRAM" "$MODEL_GB" "$SESSION_HOURS" "$MIN_CUDA" "$MIN_INET_DOWN" "$SCORE_FILE"
}

cmd_offers() {
  local profile="cheap"
  while [[ $# -gt 0 ]]; do
    case "$1" in --profile) profile="$2"; shift 2 ;; *) die "bad arg: $1" ;; esac
  done
  profile_settings "$profile"
  printf 'id\tdph/hr\tinet$/GB\test$/session\tgpu\tcu\tinet_Mbps\tgeo\treliability\tcpu_ram_gb\thost\n'
  find_offer || true
}

# ── scorecard: per-host outcomes, for predictable host choice ─────────
record_host() {  # <offer_id> <host_id> <gpu> <provision_s> <pull_s> <ok:0|1> <note>
  mkdir -p "$STATE_DIR"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" "$3" "${4:--}" "${5:--}" "$6" "${7:-}" \
    >> "$SCORE_FILE"
}

cmd_hosts() {
  if [[ ! -f "$SCORE_FILE" ]]; then echo "no runs recorded yet"; return 0; fi
  printf 'time\toffer\thost\tgpu\tprov_s\tpull_s\tok\tnote\n'
  if command -v column >/dev/null 2>&1; then column -t -s$'\t' "$SCORE_FILE"; else cat "$SCORE_FILE"; fi
}

discard() {  # <instance_id> — destroy and clear state (any failed attempt)
  vastai destroy instance "$1" -y >/dev/null 2>&1 || true
  rm -f "$STATE_FILE"
  CUR_INSTANCE=""
}

write_state() {  # <id> <offer> <profile> <ttl> <created_epoch>
  state_write <<EOF
VAST_INSTANCE_ID=$1
VAST_OFFER_ID=$2
VAST_PROFILE=$3
VAST_GPU=$GPU_NAME
VAST_MODEL=hf.co/${HF_GGUF_REPO}:${QUANT}
VAST_DISK=$DISK
VAST_CREATED_EPOCH=$5
VAST_TTL_HOURS=$4
EOF
}

# One provisioning attempt on one offer. Returns 0 only if the instance is up
# and serving the model; on any failure it destroys the box and returns 1.
up_one() {  # <offer_id> <ttl> <wait_min> <profile>
  local offer_id="$1" ttl="$2" wait_min="$3" profile="$4"
  local model_ref="hf.co/${HF_GGUF_REPO}:${QUANT}"
  local env_str="-e OLLAMA_HOST=127.0.0.1:${OLLAMA_PORT} -e OLLAMA_KEEP_ALIVE=-1 -e OLLAMA_CONTEXT_LENGTH=${CONTEXT_LEN}"

  # No --onstart: Vast's launcher keeps the container alive but does not run a
  # third-party image's CMD, and a custom onstart stalls the `running`
  # transition. Provision plainly, then start the server over SSH.
  log "creating instance on offer $offer_id ($GPU_NAME, $DISK GB disk)"
  local create_json instance_id
  create_json="$(vastai create instance "$offer_id" \
      --image "$OLLAMA_IMAGE" --disk "$DISK" --ssh --direct \
      --label "${LABEL}-${ttl}h" --env "$env_str" --cancel-unavail --raw 2>/dev/null)" \
    || { log "create failed (offer gone?)"; record_host "$offer_id" "?" "$GPU_NAME" - - 0 create-failed; return 1; }
  instance_id="$(printf '%s' "$create_json" | python3 -c \
      'import json,sys; d=json.load(sys.stdin); print(d.get("new_contract") or "")' 2>/dev/null)"
  if [[ -z "$instance_id" ]]; then
    log "create returned no contract: $create_json"; record_host "$offer_id" "?" "$GPU_NAME" - - 0 no-contract; return 1
  fi
  log "instance $instance_id created"
  CUR_INSTANCE="$instance_id"
  local created_epoch; created_epoch="$(date +%s)"
  write_state "$instance_id" "$offer_id" "$profile" "$ttl" "$created_epoch"

  # ── wait for running ───────────────────────────────────────────────
  local host_id="?" status="" deadline=$(( $(date +%s) + wait_min*60 ))
  while (( $(date +%s) < deadline )); do
    read -r status host_id < <(vastai show instance "$instance_id" --raw 2>/dev/null | python3 -c '
import json, sys
try:
    i = json.load(sys.stdin)
except Exception:
    print("- ?"); raise SystemExit
print("%s %s" % (i.get("actual_status") or "-",
                 i.get("host_id") or i.get("machine_id") or "?"))')
    case "$status" in
      running) break ;;
      exited|unknown|offline)
        log "instance entered '$status'"
        record_host "$offer_id" "$host_id" "$GPU_NAME" - - 0 "$status"; discard "$instance_id"; return 1 ;;
      *) printf '.'; sleep 10 ;;
    esac
  done
  echo
  local provision_s=$(( $(date +%s) - created_epoch ))
  if [[ "$status" != "running" ]]; then
    log "not running after ${wait_min}m (last: '$status')"
    record_host "$offer_id" "$host_id" "$GPU_NAME" "$provision_s" - 0 "timeout:$status"
    discard "$instance_id"; return 1
  fi
  log "running in ${provision_s}s (host $host_id)"

  # ── GPU preflight: bail before a pointless 18 GB pull ──────────────
  if ! ssh_run "$instance_id" "nvidia-smi -L 2>/dev/null" 2>/dev/null | grep -qi nvidia; then
    log "no usable GPU on this host"
    record_host "$offer_id" "$host_id" "$GPU_NAME" "$provision_s" - 0 no-gpu
    discard "$instance_id"; return 1
  fi

  # ── start the server ───────────────────────────────────────────────
  log "starting ollama serve over ssh"
  # Fully detach: the whole remote command's stdio must be /dev/null, otherwise
  # the backgrounded server keeps the SSH channel open and `ssh` never returns.
  ssh_run "$instance_id" \
    "( pgrep -x ollama >/dev/null 2>&1 || setsid ollama serve >/tmp/serve.log 2>&1 ) </dev/null >/dev/null 2>&1 &" \
    >/dev/null 2>&1 || true
  local i up=""
  for i in $(seq 1 30); do
    if ssh_run "$instance_id" "ollama list" >/dev/null 2>&1; then up=1; break; fi
    sleep 3
  done
  if [[ -z "$up" ]]; then
    log "ollama serve did not come up"
    record_host "$offer_id" "$host_id" "$GPU_NAME" "$provision_s" - 0 no-serve
    discard "$instance_id"; return 1
  fi
  if ssh_run "$instance_id" "grep -q 'library=cpu' /tmp/serve.log" >/dev/null 2>&1; then
    log "ollama fell back to CPU (driver too old?)"
    record_host "$offer_id" "$host_id" "$GPU_NAME" "$provision_s" - 0 cpu-fallback
    discard "$instance_id"; return 1
  fi

  # ── pull the model ─────────────────────────────────────────────────
  log "pulling $model_ref (~${MODEL_GB} GB, detached)"
  ssh_run "$instance_id" \
    "( setsid ollama pull '$model_ref' >/tmp/pull.log 2>&1 ) </dev/null >/dev/null 2>&1 &" >/dev/null 2>&1 || true
  local pull_start; pull_start="$(date +%s)"
  local pull_deadline=$(( pull_start + 40*60 )) listing=""
  while (( $(date +%s) < pull_deadline )); do
    listing="$(ssh_run "$instance_id" "ollama list" 2>&1 || true)"
    if printf '%s' "$listing" | grep -qi 'could not connect'; then
      log "ollama serve died mid-pull"
      record_host "$offer_id" "$host_id" "$GPU_NAME" "$provision_s" - 0 serve-died
      discard "$instance_id"; return 1
    fi
    if printf '%s' "$listing" | grep -q "$QUANT"; then break; fi
    printf '.'; sleep 20
  done
  echo
  local pull_s=$(( $(date +%s) - pull_start ))
  if ! printf '%s' "$listing" | grep -q "$QUANT"; then
    log "model not ready after 40m"
    record_host "$offer_id" "$host_id" "$GPU_NAME" "$provision_s" "$pull_s" 0 pull-timeout
    discard "$instance_id"; return 1
  fi

  # `ollama cp` creates "<alias>:latest", so match both spellings.
  ssh_run "$instance_id" "ollama cp '$model_ref' '$MODEL_ALIAS'" >/dev/null 2>&1 || true
  local model_id
  model_id="$(ssh_run "$instance_id" "ollama list" 2>/dev/null \
    | awk -v n="$MODEL_ALIAS" '$1==n || $1==n":latest" {print $2}')"
  if [[ -z "$model_id" ]]; then
    log "alias '$MODEL_ALIAS' missing"
    record_host "$offer_id" "$host_id" "$GPU_NAME" "$provision_s" "$pull_s" 0 no-alias
    discard "$instance_id"; return 1
  fi

  local ssh_url; ssh_url="$(vastai ssh-url "$instance_id" 2>/dev/null | tail -1 || true)"
  { cat "$STATE_FILE"
    echo "VAST_SSH_URL=$ssh_url"
    echo "VAST_MODEL_ALIAS=$MODEL_ALIAS"
    echo "VAST_MODEL_ID=$model_id"
  } > "$STATE_FILE.tmp" && mv -f "$STATE_FILE.tmp" "$STATE_FILE"

  record_host "$offer_id" "$host_id" "$GPU_NAME" "$provision_s" "$pull_s" 1 ""
  log "ONLINE in $(( provision_s + pull_s ))s (provision ${provision_s}s + pull ${pull_s}s)"

  cat <<EOF

──────────────────────────────────────────────────────────────
instance : $instance_id  ($profile / $GPU_NAME, host $host_id)
model    : $model_ref
alias    : $MODEL_ALIAS   (harness model id)
online   : $(( provision_s + pull_s ))s  (provision ${provision_s}s + pull ${pull_s}s)
ttl      : ${ttl}h  (auto-destroy via: vastctl.sh reap)
ssh      : $ssh_url

Open a tunnel, then talk to the OpenAI-compatible API:
  vastctl.sh tunnel                # leave running in its own terminal
  curl http://127.0.0.1:${OLLAMA_PORT}/v1/chat/completions \\
    -H 'Content-Type: application/json' \\
    -d '{"model":"$MODEL_ALIAS","messages":[{"role":"user","content":"hi"}]}'

OpenCode: provider 'vastctl', model '$MODEL_ALIAS' (works once the tunnel is up).

Destroy it (stops all billing):
  vastctl.sh down
──────────────────────────────────────────────────────────────
EOF
  CUR_INSTANCE=""
  return 0
}

cmd_up() {
  local profile="cheap" ttl="$DEFAULT_TTL_HOURS" offer_id="" wait_min="$PROVISION_TIMEOUT_MIN"
  local retries="${VASTCTL_RETRIES:-5}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)   profile="$2";  shift 2 ;;
      --ttl-hours) ttl="$2";      shift 2 ;;
      --offer-id)  offer_id="$2"; shift 2 ;;
      --wait-min)  wait_min="$2"; shift 2 ;;
      --retries)   retries="$2";  shift 2 ;;
      *) die "bad arg: $1" ;;
    esac
  done
  profile_settings "$profile"
  preflight
  if [[ -f "$STATE_FILE" ]]; then
    die "an instance is already tracked ($STATE_FILE) — run 'vastctl.sh down' first"
  fi

  # Candidate offers: a pinned one, or the scorecard-ranked shortlist.
  local -a candidates=()
  if [[ -n "$offer_id" ]]; then
    candidates=("$offer_id")
  else
    local id rest
    while IFS=$'\t' read -r id rest; do [[ -n "$id" ]] && candidates+=("$id"); done < <(find_offer)
  fi
  [[ ${#candidates[@]} -gt 0 ]] || die "no offer matched $GPU_NAME ≥${MIN_VRAM}GB (try 'offers')"

  # Clean up the in-flight instance if the script dies (Ctrl-C, etc.).
  trap 'if [[ -n "${CUR_INSTANCE:-}" ]]; then log "aborting — destroying $CUR_INSTANCE"; vastai destroy instance "$CUR_INSTANCE" -y >/dev/null 2>&1 || true; rm -f "$STATE_FILE"; fi' EXIT

  local n=0 cand
  for cand in "${candidates[@]}"; do
    n=$((n+1)); (( n > retries )) && break
    log "attempt $n/$retries — offer $cand"
    if up_one "$cand" "$ttl" "$wait_min" "$profile"; then
      trap - EXIT
      return 0
    fi
    log "offer $cand failed — trying next"
  done
  die "all attempts failed (see: vastctl.sh hosts)"
}

cmd_status() {
  state_load; preflight
  vastai show instance "$VAST_INSTANCE_ID" --raw | python3 -c '
import json, sys, time
i = json.load(sys.stdin)
created = float(sys.argv[1])
dph = i.get("dph_total") or 0
status = i.get("actual_status") or ""
msg = i.get("status_msg") or ""
start = i.get("start_date") or 0
now = time.time()
lifetime = (now - created) / 3600
run_h = (now - start) / 3600 if (start and status == "running") else 0
print("id        : %s" % i.get("id"))
print("status    : %s  %s" % (status, msg))
print("gpu       : %s" % (i.get("gpu_name") or ""))
print("rate      : $%.4f/h" % dph)
print("lifetime  : %.2fh (running %.2fh)" % (lifetime, run_h))
print("accrued   : ~$%.2f + storage" % (lifetime * dph))
ssh_host = i.get("ssh_host")
print(("ssh       : ssh://%s:%s" % (ssh_host, i.get("ssh_port")))
      if ssh_host else "ssh       : (pending)")
' "$VAST_CREATED_EPOCH"
}

cmd_tunnel() {
  state_load
  local parts user host port
  parts="$(ssh_parts "$VAST_INSTANCE_ID")" || die "could not resolve ssh url"
  IFS=$'\t' read -r user host port <<<"$parts"
  log "tunnelling 127.0.0.1:$OLLAMA_PORT -> $user@$host:$OLLAMA_PORT (Ctrl-C to close)"
  exec ssh -N -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 \
    -p "$port" -L "${OLLAMA_PORT}:localhost:${OLLAMA_PORT}" "${user}@${host}"
}

cmd_ssh() {
  state_load
  local parts user host port
  parts="$(ssh_parts "$VAST_INSTANCE_ID")" || die "could not resolve ssh url"
  IFS=$'\t' read -r user host port <<<"$parts"
  exec ssh -o StrictHostKeyChecking=accept-new -p "$port" "${user}@${host}"
}

cmd_logs() { state_load; vastai logs "$VAST_INSTANCE_ID" --tail 200; }

cmd_down() {
  state_load
  log "destroying instance $VAST_INSTANCE_ID"
  vastai destroy instance "$VAST_INSTANCE_ID" -y
  state_clear
  log "done — all billing stopped"
}

cmd_reap() {
  # Stateless and host-independent: only needs the API key, so it can run on an
  # always-on node (e.g. heavensfeel) even though `up` writes its state file on
  # the workstation. The TTL is encoded in the instance label, so no local
  # state is required.
  need vastai
  local rows
  rows="$(vastai show instances --raw 2>/dev/null | python3 -c '
import json, sys, time, re
try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    data = data.get("instances") or []
now = time.time()
for i in data:
    label = i.get("label") or ""
    if not label.startswith("vastctl-llm"):
        continue
    m = re.search(r"-(\d+(?:\.\d+)?)h$", label)
    ttl = float(m.group(1)) if m else 4.0
    start = i.get("start_date") or 0
    dur = i.get("duration") or 0
    age = (now - start) / 3600 if start else dur / 3600
    if age >= ttl:
        print("%s\t%s\t%.2f\t%.2f" % (i.get("id"), i.get("actual_status"), age, ttl))
' || true)"
  if [[ -z "$rows" ]]; then log "no managed instance past TTL"; return 0; fi
  local id st age ttl
  while IFS=$'\t' read -r id st age ttl; do
    [[ -n "$id" ]] || continue
    log "instance $id ($st) age ${age}h >= ttl ${ttl}h — destroying"
    vastai destroy instance "$id" -y || log "WARNING: destroy failed for $id"
    if [[ -f "$STATE_FILE" ]] && grep -q "VAST_INSTANCE_ID=$id\$" "$STATE_FILE"; then
      state_clear
    fi
  done <<<"$rows"
  log "reap complete"
}

usage() { awk 'NR==1{next} /^set /{next} /^#/{sub(/^# ?/,"");print;next} /^$/{print;next} {exit}' "$0"; }

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    up)      cmd_up "$@" ;;
    status)  cmd_status "$@" ;;
    tunnel)  cmd_tunnel "$@" ;;
    ssh)     cmd_ssh "$@" ;;
    logs)    cmd_logs "$@" ;;
    down)    cmd_down "$@" ;;
    reap)    cmd_reap "$@" ;;
    hosts)   cmd_hosts "$@" ;;
    offers)  cmd_offers "$@" ;;
    ''|-h|--help|help) usage ;;
    *) die "unknown command '$cmd' (try: --help)" ;;
  esac
}

main "$@"
