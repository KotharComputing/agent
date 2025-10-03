#!/usr/bin/env bash
set -euo pipefail
DEFAULT_API_BASE="https://api.kotharcomputing.com"
BIN=/opt/agents/current

API_BASE="$DEFAULT_API_BASE"
TOKEN=""
orig_args=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kothar-api-url)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --kothar-api-url" >&2
        exit 1
      fi
      API_BASE="$2"
      shift 2
      ;;
    --kothar-api-url=*)
      API_BASE="${1#--kothar-api-url=}"
      shift
      ;;
    --token)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --token" >&2
        exit 1
      fi
      TOKEN="$2"
      shift 2
      ;;
    --token=*)
      TOKEN="${1#--token=}"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
API_BASE="${API_BASE%/}"
if [[ -z "$TOKEN" ]]; then
  echo "Missing required --token argument" >&2
  exit 1
fi
set -- "${orig_args[@]}"

arch=$(uname -m)

DL_URL="${API_BASE}/v1/agents/\$dl?arch=${arch}&imageVersion=${KOTHAR_AGENT_DOCKER_IMAGE_VERSION}"

download_bin() {
  local target_tmp="$BIN.tmp"
  echo "Downloading agent..."
  curl -fsSL \
    --retry 5 \
    --retry-delay 2 \
    --retry-max-time 60 \
    -H "Authorization: Bearer ${TOKEN}" \
    "$DL_URL" \
    -o "$target_tmp"
  chmod +x "$target_tmp"
  mv -f "$target_tmp" "$BIN"
  echo "Installed agent"
}

# Seed once if missing
if [[ ! -x "$BIN" ]]; then
  download_bin
fi

# Forward TERM/INT to the child so Docker/K8s signals work properly
child_pid=""
forward_signal() {
  local sig="$1"
  if [[ -n "$child_pid" ]]; then
    kill "-$sig" "$child_pid" 2>/dev/null || true
    local exit_status=0
    if wait "$child_pid"; then
      exit_status=0
    else
      exit_status=$?
    fi
    exit "$exit_status"
  fi
  exit 1
}
trap 'forward_signal TERM' TERM
trap 'forward_signal INT' INT

while true; do
  # Run the agent with the *original* args unchanged
  "$BIN" "$@" &
  child_pid=$!
  if wait "$child_pid"; then
    rc=0
  else
    rc=$?
  fi

  if [[ $rc -eq 75 ]]; then
    # Convention: agent downloaded a new binary to $BIN.tmp and exited 75
    if [[ -f "$BIN.tmp" ]]; then
      echo "Applying agent update…"
      chmod +x "$BIN.tmp"
      mv -f "$BIN.tmp" "$BIN"
      continue
    else
      echo "Update requested (rc=75) but $BIN.tmp not found; attempting fresh download."
      download_bin
      continue
    fi
  fi

  # Any other exit code stops the container
  exit "$rc"
done
