#!/bin/bash
# =============================================================================
# lib_models.sh v1.0 — Shared model utilities (read-only)
# =============================================================================
# Sourced by: intelligence.sh, lib_venv.sh, orchestrator.sh
# NOT for business logic or menus — pure utilities only.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# MODELS_DIR, VENV_DIR, VENV_PYTHON, LOG_DIR must be set by the caller
# (orchestrator.sh, intelligence.sh, or lib_venv.sh)

# --- Python environment ---
get_python_env() {
    if [ -f "$VENV_PYTHON" ]; then
        echo "$VENV_PYTHON"
    else
        echo "python3"
    fi
}

# --- Model flag detection ---
detect_model_flags() {
    local MODEL_PATH="$1"
    local MODEL_NAME=$(basename "$MODEL_PATH" | tr '[:upper:]' '[:lower:]')
    local CONFIG="$MODEL_PATH/config.json"

    local REASONING="" TOOLCALL="" EXTRA_FLAGS="--trust-remote-code --allow-auto-truncate --log-level warning"

    local ARCH=""
    if [ -f "$CONFIG" ]; then
        ARCH=$("$VENV_PYTHON" -c "
import json
try:
    with open('$CONFIG') as f: data = json.load(f)
    print(data.get('architectures', [''])[0])
except: print('')
" 2>/dev/null || echo "")
    fi

    if [[ "$MODEL_NAME" == *qwen3* ]] || [[ "$ARCH" == *Qwen3* ]]; then
        REASONING="qwen3"
        TOOLCALL="qwen3_coder"
    elif [[ "$MODEL_NAME" == *gemma-4* ]]; then
        REASONING="gemma4"
    fi

    [ -n "$REASONING" ] && echo "🔍 Detected: $REASONING" >&2
    echo "$REASONING|$TOOLCALL|$EXTRA_FLAGS"
}

# --- Model scanning (formatted table output) ---
scan_models_internal() {
    local PY_EXEC=$(get_python_env)
    local TMP_FILE=$(mktemp)

    "$PY_EXEC" << PYEOF 2>/dev/null > "$TMP_FILE"
import json, os
models_dir = "$MODELS_DIR"
models = []
for root, _, files in os.walk(models_dir):
    if "config.json" in files:
        try:
            with open(os.path.join(root, "config.json")) as f:
                data = json.load(f)
            arch = data.get('architectures', ['unknown'])[0]
            models.append((root, arch))
        except: continue
for i, (path, arch) in enumerate(models, 1):
    print(f"{i}|{path}|{arch}")
PYEOF

    echo "------------------------------------------------------------"
    printf "%-4s | %-60s | %-20s\n" "ID" "MODEL PATH" "ARCH"
    echo "------------------------------------------------------------"
    while IFS='|' read -r id path arch; do
        if [ -n "$id" ]; then
            printf "%-4s | %-60s | %-20s\n" "$id" "${path: -60}" "$arch"
        fi
    done < "$TMP_FILE"
    echo "------------------------------------------------------------"

    rm -f "$TMP_FILE"
}

# --- Raw model scan — returns pipe-delimited lines only (no table) ---
scan_models_raw() {
    local PY_EXEC=$(get_python_env)
    "$PY_EXEC" << PYEOF
import json, os
models_dir = "$MODELS_DIR"
for root, _, files in os.walk(models_dir):
    if "config.json" in files:
        try:
            with open(os.path.join(root, "config.json")) as f:
                data = json.load(f)
            arch = data.get('architectures', ['unknown'])[0]
            print(f"{root}|{arch}")
        except: continue
PYEOF
}

# --- Model download (with hf CLI fallback) ---
download_model() {
    local REPO_ID="$1"
    [ -z "$REPO_ID" ] && echo -e "\033[0;31m[ERROR]\033[0m Usage: --download <repo>" && return 1
    echo -e "\033[0;34m[INFO]\033[0m Downloading $REPO_ID..."

    mkdir -p "$MODELS_DIR/$REPO_ID"

    if command -v hf &> /dev/null; then
        echo -e "\033[0;34m[INFO]\033[0m Using 'hf' CLI for download..."
        hf download "$REPO_ID" --local-dir "$MODELS_DIR/$REPO_ID" && {
            echo -e "\033[0;32m[SUCCESS]\033[0m Download complete (via hf CLI)!"
            return 0
        }
    fi

    local PY_EXEC=$(get_python_env)
    echo -e "\033[0;34m[INFO]\033[0m Using Python ($PY_EXEC) for download..."

    if [[ "$PY_EXEC" == "python3" ]]; then
        $PY_EXEC -m pip install -q huggingface_hub --break-system-packages || true
    else
        $PY_EXEC -m pip install -q huggingface_hub || true
    fi

    $PY_EXEC -c "
from huggingface_hub import snapshot_download
try:
    snapshot_download(repo_id='$REPO_ID', local_dir='$MODELS_DIR/$REPO_ID')
    print('SUCCESS')
except Exception as e:
    print(f'ERROR: {e}')
    exit(1)
" | grep -q "SUCCESS" && echo -e "\033[0;32m[SUCCESS]\033[0m Download complete! (via Python)" || echo -e "\033[0;31m[ERROR]\033[0m Download failed. Ensure huggingface_hub is available."
}
