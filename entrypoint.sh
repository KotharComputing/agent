#!/usr/bin/env bash
set -euo pipefail
DEFAULT_API_BASE="https://api.kotharcomputing.com"
AGENT_DIR=/opt/agents/current
BIN="${AGENT_DIR}/agent"

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

extract_agent_archive() {
  local archive_path="$1"
  local destination="$2"
  unzip -q "$archive_path" -d "$destination"
}

install_agent_tree() {
  local extracted_root="$1"
  local staging_dir="$extracted_root"
  mapfile -t top_entries < <(find "$extracted_root" -mindepth 1 -maxdepth 1 -print)
  if [[ ${#top_entries[@]} -eq 1 && -d "${top_entries[0]}" ]]; then
    staging_dir="${top_entries[0]}"
  fi

  if [[ ! -f "${staging_dir}/agent" ]]; then
    echo "Agent archive missing expected 'agent' binary" >&2
    return 1
  fi

  chmod +x "${staging_dir}/agent"
  rm -rf "$AGENT_DIR"
  mkdir -p "$(dirname "$AGENT_DIR")"
  mv "$staging_dir" "$AGENT_DIR"
  if [[ "$staging_dir" != "$extracted_root" ]]; then
    rm -rf "$extracted_root"
  fi
  return 0
}

download_bin() {
  local archive_tmp
  archive_tmp=$(mktemp)
  local extract_dir
  extract_dir=$(mktemp -d)
  echo "Downloading agent..."
  curl -fsSL \
    --retry 5 \
    --retry-delay 2 \
    --retry-max-time 60 \
    -H "Authorization: Bearer ${TOKEN}" \
    "$DL_URL" \
    -o "$archive_tmp"

  if ! extract_agent_archive "$archive_tmp" "$extract_dir"; then
    rm -f "$archive_tmp"
    rm -rf "$extract_dir"
    exit 1
  fi

  rm -f "$archive_tmp"
  if ! install_agent_tree "$extract_dir"; then
    rm -rf "$extract_dir"
    exit 1
  fi
  rm -rf "$extract_dir"
  echo "Installed agent."
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
  exit 0
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
    agent_tmp_dir="${AGENT_DIR}.tmp"
    agent_tmp_archive="${agent_tmp_dir}.zip"

    if [[ -d "$agent_tmp_dir" ]]; then
      echo "Applying agent update…"
      if install_agent_tree "$agent_tmp_dir"; then
        continue
      else
        echo "Failed to install agent update from ${agent_tmp_dir}; removing and retrying download." >&2
        rm -rf "$agent_tmp_dir"
      fi
    elif [[ -f "$agent_tmp_archive" ]]; then
      echo "Applying agent update from archive…"
      tmp_extract_dir=$(mktemp -d)
      if extract_agent_archive "$agent_tmp_archive" "$tmp_extract_dir" && install_agent_tree "$tmp_extract_dir"; then
        rm -f "$agent_tmp_archive"
        rm -rf "$tmp_extract_dir"
        continue
      else
        echo "Failed to install agent update from ${agent_tmp_archive}; removing and retrying download." >&2
      fi
      rm -f "$agent_tmp_archive"
      rm -rf "$tmp_extract_dir"
    fi

    echo "Update requested (rc=75) but no usable agent bundle found; attempting fresh download."
    download_bin
    continue
  fi

  # Any other exit code stops the container
  exit "$rc"
done
