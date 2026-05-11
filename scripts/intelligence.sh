#!/bin/bash
# =============================================================================
# SGLang Orchestrator - Intelligence (Resilient Hybrid Download)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

MODELS_DIR="$PROJECT_ROOT/models"
VENV_DIR="$PROJECT_ROOT/sglang_venv"
VENV_PYTHON="$VENV_DIR/bin/python"
LOG_DIR="$PROJECT_ROOT/logs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; return 1; }

get_python_env() {
    if [ -f "$VENV_PYTHON" ]; then
        echo "$VENV_PYTHON"
    else
        echo "python3"
    fi
}

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

scan_models_internal() {
    local PY_EXEC=$(get_python_env)
    # Use a temporary file to avoid the pipe-to-while syntax error in some bash versions
    local TMP_FILE=$(mktemp)
    
    "$PY_EXEC" << EOF 2>/dev/null > "$TMP_FILE"
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
EOF

    echo "------------------------------------------------------------"
    printf "%-4s | %-60s | %-20s\n" "ID" "MODEL PATH" "ARCH"
    echo "------------------------------------------------------------"
    while IFS='|' read -r id path arch; do
        if [ -n "$id" ]; then
            printf "%-4s | %-60s | %-20s\n" "$id" "${path: -60}" "$arch"
        fi
    done < "$TMP_FILE"
    echo "------------------------------------------------------------"
    
    rm "$TMP_FILE"
}

select_and_launch() {
    local PY_EXEC=$(get_python_env)
    log "Using Python: $PY_EXEC"

    # Capture the output of scan_models_internal into an array
    # We extract just the lines that match the ID|PATH|ARCH pattern
    mapfile -t MODEL_ENTRIES < <(scan_models_internal | grep "|")

    if [ ${#MODEL_ENTRIES[@]} -eq 0 ]; then
        error "No models found!"
        return 1
    fi

    # Re-print header for selection context
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

    # --- AUTO-DOWNLOAD LOGIC ---
    if [ ! -d "$MODEL_PATH" ] || [ ! -f "$MODEL_PATH/config.json" ]; then
        echo -e "${YELLOW}⚠️  Model path not found or incomplete: $MODEL_PATH${NC}"
        read -p "Would you like to download from Hugging Face? (y/n): " dl_choice
        if [[ "$dl_choice" =~ ^[yY]$ ]]; then
            read -p "Enter HF Repo ID: " hf_repo
            [ -z "$hf_repo" ] && { error "No Repo ID provided."; return 1; }
            bash "$SCRIPT_DIR/intelligence.sh" --download "$hf_repo"
            MODEL_PATH=$(find "$MODELS_DIR/$hf_repo" -name "config.json" -exec dirname {} \; | head -n 1)
            if [ -z "$MODEL_PATH" ]; then
                error "Download failed to locate config.json"
                return 1
            fi
            echo -e "${GREEN}✅ Model located at: $MODEL_PATH${NC}"
        else
            error "Model path required for launch."
            return 1
        fi
    fi
    # --------------------------------

    CMD="$PY_EXEC -m sglang.launch_server \
    --model-path \"$MODEL_PATH\" \
    --mem-fraction-static $MEM \
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
    echo "🚀 LAUNCH COMMAND:"
    echo "$CMD"
    echo "------------------------------------------------------------"
    
    read -p "Launch? (Y/n): " confirm
    [[ "$confirm" =~ ^[nN]$ ]] && { log "Cancelled."; return 0; }
    
    mkdir -p "$LOG_DIR"
    LOGFILE="$LOG_DIR/sglang_venv_port${PORT}.log"
    
    log "Starting server → $LOGFILE"
    nohup bash -c "$CMD" > "$LOGFILE" 2>&1 &
    
    PID=$!
    echo "$PID" > "$LOG_DIR/sglang_venv_port${PORT}.pid"
    
    success "✅ VENV Server launched! PID=$PID | Port=$PORT"
    success "🌐 OpenAI endpoint: http://localhost:$PORT/v1"
}

download_model() {
    local REPO_ID=$1
    [ -z "$REPO_ID" ] && error "Usage: --download <repo>"
    local PY_EXEC=$(get_python_env)
    log "Downloading $REPO_ID using $PY_EXEC..."
    
    # Try to ensure huggingface_hub is present in the selected env
    $PY_EXEC -m pip install -q huggingface_hub || true
    
    mkdir -p "$MODELS_DIR/$REPO_ID"
    $PY_EXEC -c "
from huggingface_hub import snapshot_download
import os
try:
    snapshot_download(repo_id='$REPO_ID', local_dir='$MODELS_DIR/$REPO_ID', local_dir_use_symlinks=False)
    print('SUCCESS')
except Exception as e:
    print(f'ERROR: {e}')
    exit(1)
" | grep -q "SUCCESS" && success "Download complete!" || error "Download failed. Ensure $PY_EXEC has huggingface_hub installed."
}

case "${1:-}" in
    --scan) scan_models_internal ;;
    --select-launch|--launch) select_and_launch ;;
    --download) download_model "${2:-}" ;;
    *) echo "Usage: $0 {--scan|--select-launch|--download <repo>}";;
esac
