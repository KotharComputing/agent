#!/usr/bin/env bash
set -euo pipefail
DEFAULT_API_BASE="https://api.kotharcomputing.com"
BIN=/opt/agents/current

API_BASE="$DEFAULT_API_BASE"
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  if [[ "${args[$i]}" == "--kothar-api-url" && $((i+1)) -lt ${#args[@]} ]]; then
    API_BASE="${args[$((i+1))]}"
    ((i+=2))
  else
    ((i+=1))
  fi
done
API_BASE="${API_BASE%/}"

arch=$(uname -m)
case "$arch" in
  x86_64|amd64)
    arch="amd64"
    ;;
  arm64|aarch64)
    arch="arm64"
    ;;
esac

DL_URL="${API_BASE}/v1/agents/\$dl?arch=${arch}&imageVersion=${KOTHAR_AGENT_DOCKER_IMAGE_VERSION}"

download_bin() {
  local target_tmp="$BIN.tmp"
  echo "Downloading agent..."
  curl -fsS --retry 5 --retry-delay 2 --retry-max-time 60 "$DL_URL" -o "$target_tmp"
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
term() { [[ -n "$child_pid" ]] && kill -TERM "$child_pid" 2>/dev/null || true; wait "$child_pid" 2>/dev/null || true; exit 143; }
trap term TERM INT

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
