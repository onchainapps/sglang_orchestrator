#!/bin/bash
# =============================================================================
# SGLang Orchestrator - VENV Module (lib_venv.sh)
# =============================================================================

set -uo pipefail

# These will be provided by the caller (orchestrator.sh)
# PROJECT_ROOT, MODELS_DIR, VENV_DIR, VENV_PYTHON, LOG_DIR

# Load Parameters Module
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/lib_params.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; return 1; }

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

scan_models_internal() {
    local PY_EXEC=$(get_python_env)
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
    
    rm -f "$TMP_FILE"
}

select_and_launch() {
    local PY_EXEC=$(get_python_env)
    log "Using Python: $PY_EXEC"

    mapfile -t MODEL_ENTRIES < <(scan_models_internal | grep "|")

    if [ ${#MODEL_ENTRIES[@]} -eq 0 ]; then
        error "No models found!"
        return 1
    fi

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
            [ -z "$MODEL_PATH" ] && { error "Download failed to locate config.json"; return 1; }
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

    # --- RUNTIME PARAMETER REVIEW ---
    echo "------------------------------------------------------------"
    echo "📋 RUNTIME PARAMETERS REVIEW (VENV)"
    echo "------------------------------------------------------------"
    echo "  Model Path:    $MODEL_PATH"
    echo "  Port:          $PORT"
    echo "  Memory Frac:   $MEM"
    echo "  TP Size:       $TP"
    echo "  Reasoning:     ${REASONING:-None}"
    echo "  Tool Call:     ${TOOLCALL:-None}"
    echo "  Extra Flags:   $EXTRA_FLAGS"
    echo "------------------------------------------------------------"
    
    read -p "Proceed with launch? (Y/n): " confirm
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
    $PY_EXEC -m pip install -q huggingface_hub
    mkdir -p "$MODELS_DIR/$REPO_ID"
    $PY_EXEC -c "
from huggingface_hub import snapshot_download
snapshot_download(repo_id='$REPO_ID', local_dir='$MODELS_DIR/$REPO_ID', local_dir_use_symlinks=False)
" && success "Download complete!" || error "Download failed"
}
