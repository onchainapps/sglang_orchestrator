#!/bin/bash
# =============================================================================
# SGLang Dynamic Orchestrator - Intelligence (Stable + Clean)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

MODELS_DIR="$PROJECT_ROOT/models"
VENV_DIR="$PROJECT_ROOT/sglang_venv"
VENV_PYTHON="$VENV_DIR/bin/python"
LOG_DIR="$PROJECT_ROOT/logs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [ ! -f "$VENV_PYTHON" ]; then
    error "Venv not found! Run option 6 first."
fi

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

select_and_launch() {
    log "Using venv: $VENV_PYTHON"

    mapfile -t MODEL_ENTRIES < <("$VENV_PYTHON" << EOF 2>/dev/null
import json, os
models_dir = "$MODELS_DIR"
models = []
for root, _, files in os.walk(models_dir):
    if "config.json" in files:
        try:
            with open(os.path.join(root, "config.json")) as f:
                data = json.load(f)
            arch = data.get('architectures', ['unknown'])[0]
            models.append(f"{root}|{arch}")
        except: continue
for i, m in enumerate(models, 1):
    print(f"{i}|{m}")
EOF
    )

    [ ${#MODEL_ENTRIES[@]} -eq 0 ] && error "No models found!"

    echo "------------------------------------------------------------"
    printf "%-4s | %-60s | %-20s\n" "ID" "MODEL PATH" "ARCH"
    echo "------------------------------------------------------------"
    for entry in "${MODEL_ENTRIES[@]}"; do
        id=$(echo "$entry" | cut -d'|' -f1)
        path=$(echo "$entry" | cut -d'|' -f2)
        arch=$(echo "$entry" | cut -d'|' -f3)
        printf "%-4s | %-60s | %-20s\n" "$id" "${path: -60}" "$arch"
    done
    echo "------------------------------------------------------------"

    read -p "Select model ID (q to quit): " choice
    [[ "$choice" =~ ^[qQ]$ ]] && return 0

    SELECTED_LINE="${MODEL_ENTRIES[$((choice-1))]}"
    MODEL_PATH=$(echo "$SELECTED_LINE" | cut -d'|' -f2)

    IFS='|' read -r REASONING TOOLCALL EXTRA_FLAGS <<< "$(detect_model_flags "$MODEL_PATH")"

    read -p "Port [30001]: " PORT; PORT=${PORT:-30001}
    read -p "Memory fraction [0.80]: " MEM; MEM=${MEM:-0.80}
    read -p "TP size [1]: " TP; TP=${TP:-1}

    # Clean stable configuration for Gemma-4 (and other models)
    CMD="CUDA_HOME=/usr/local/cuda \
    $VENV_PYTHON -m sglang.launch_server \
    --model-path \"$MODEL_PATH\" \
    --mem-fraction-static 0.8 \
    --host 0.0.0.0 \
    --port $PORT \
    --tp $TP \
    --disable-cuda-graph \
    --disable-piecewise-cuda-graph \
    --disable-radix-cache \
    --disable-overlap-schedule \
    $EXTRA_FLAGS"

    [ -n "$REASONING" ] && CMD+=" --reasoning-parser $REASONING"
    [ -n "$TOOLCALL" ] && CMD+=" --tool-call-parser $TOOLCALL"

    echo "------------------------------------------------------------"
    echo "🚀 LAUNCH COMMAND (Stable Mode):"
    echo "$CMD"
    echo "------------------------------------------------------------"

    read -p "Launch? (Y/n): " confirm
    [[ "$confirm" =~ ^[nN]$ ]] && { log "Cancelled."; return 0; }

    mkdir -p "$LOG_DIR"
    LOGFILE="$LOG_DIR/sglang_port${PORT}.log"

    log "Starting server → $LOGFILE"
    nohup bash -c "$CMD" > "$LOGFILE" 2>&1 &

    PID=$!
    echo "$PID" > "$LOG_DIR/sglang_port${PORT}.pid"

    success "✅ Server launched! PID=$PID | Port=$PORT"
    success "🌐 OpenAI endpoint: http://localhost:$PORT/v1"
}

# Legacy helpers
scan_models() {
    log "Scanning models..."
    "$VENV_PYTHON" << EOF
import json, os
models_dir = "$MODELS_DIR"
print(f"{'MODEL PATH':<70} | {'ARCH':<25}")
print("-" * 100)
for root, _, files in os.walk(models_dir):
    if "config.json" in files:
        try:
            with open(os.path.join(root, "config.json")) as f:
                data = json.load(f)
            arch = data.get('architectures', ['unknown'])[0]
            print(f"{root:<70} | {arch:<25}")
        except: continue
EOF
}

download_model() {
    local REPO_ID=$1
    [ -z "$REPO_ID" ] && error "Usage: --download <repo>"
    log "Downloading $REPO_ID..."
    if ! "$VENV_PYTHON" -c "import huggingface_hub" &> /dev/null; then
        "$VENV_PYTHON" -m pip install huggingface_hub
    fi
    mkdir -p "$MODELS_DIR/$REPO_ID"
    "$VENV_PYTHON" -c "
from huggingface_hub import snapshot_download
snapshot_download(repo_id='$REPO_ID', local_dir='$MODELS_DIR/$REPO_ID', local_dir_use_symlinks=False)
print('SUCCESS')
" && success "Download complete!" || error "Download failed"
}

case "${1:-}" in
    --scan) scan_models ;;
    --select-launch|--launch) select_and_launch ;;
    --download) download_model "${2:-}" ;;
    *) echo "Usage: $0 {--scan|--select-launch|--download <repo>}";;
esac
