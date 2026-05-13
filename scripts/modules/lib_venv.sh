#!/bin/bash
# =============================================================================
# SGLang Orchestrator - VENV Module (lib_venv.sh) v2.1
# =============================================================================
# Standalone module for VENV-based model launch.
# Sources lib_models.sh for shared utilities.
# NOT sourced by orchestrator.sh — used as independent tool.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$HOME/llms/models"
VENV_DIR="$HOME/llms/sglang_venv"
VENV_PYTHON="$VENV_DIR/bin/python"
LOG_DIR="$HOME/llms/sglang_orchestrator/logs"

source "$SCRIPT_DIR/lib_models.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; return 1; }

# --- VENV Launch (standalone — mirrors Docker path but independent) ---
venv_launch_model() {
    local PY_EXEC=$(get_python_env)
    log "Using Python: $PY_EXEC"

    mapfile -t MODEL_ENTRIES < <(scan_models_raw)

    if [ ${#MODEL_ENTRIES[@]} -eq 0 ]; then
        error "No models found!"
        return 1
    fi

    echo "------------------------------------------------------------"
    printf "%-4s | %-60s | %-20s\n" "ID" "MODEL PATH" "ARCH"
    echo "------------------------------------------------------------"
    idx=1
    for entry in "${MODEL_ENTRIES[@]}"; do
        path=$(echo "$entry" | cut -d'|' -f1)
        arch=$(echo "$entry" | cut -d'|' -f2)
        printf "%-4s | %-60s | %-20s\n" "$idx" "${path: -60}" "$arch"
        ((idx++))
    done
    echo "------------------------------------------------------------"

    read -p "Select model ID (q to quit): " choice
    [[ "$choice" =~ ^[qQ]$ ]] && return 0

    SELECTED_LINE="${MODEL_ENTRIES[$((choice-1))]}"
    MODEL_PATH=$(echo "$SELECTED_LINE" | cut -d'|' -f1)

    IFS='|' read -r REASONING TOOLCALL EXTRA_FLAGS <<< "$(detect_model_flags "$MODEL_PATH")"

    read -p "Port [30001]: " PORT; PORT=${PORT:-30001}
    read -p "Memory fraction [0.82]: " MEM; MEM=${MEM:-0.82}
    read -p "TP size [1]: " TP; TP=${TP:-1}

    # Auto-download if model missing
    if [ ! -d "$MODEL_PATH" ] || [ ! -f "$MODEL_PATH/config.json" ]; then
        echo -e "${YELLOW}⚠️  Model path not found or incomplete: $MODEL_PATH${NC}"
        read -p "Would you like to download from Hugging Face? (y/n): " dl_choice
        if [[ "$dl_choice" =~ ^[yY]$ ]]; then
            read -p "Enter HF Repo ID: " hf_repo
            [ -z "$hf_repo" ] && { error "No Repo ID provided."; return 1; }
            download_model "$hf_repo"
            MODEL_PATH=$(find "$MODELS_DIR/$hf_repo" -name "config.json" -exec dirname {} \; | head -n 1)
            [ -z "$MODEL_PATH" ] && { error "Download failed to locate config.json"; return 1; }
            echo -e "${GREEN}✅ Model located at: $MODEL_PATH${NC}"
        else
            error "Model path required for launch."
            return 1
        fi
    fi

    CMD="$PY_EXEC -m sglang.launch_server \
    --model-path \"$MODEL_PATH\" \
    --mem-fraction-static $MEM \
    --context-length 1048576 \
    --max-running-requests 16 \
    --max-total-tokens 1048576 \
    --chunked-prefill-size 8192 \
    --allow-auto-truncate \
    --schedule-policy lru \
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
    echo "📋 RUNTIME PARAMETERS REVIEW (VENV)"
    echo "------------------------------------------------------------"
    echo "  Model Path:         $MODEL_PATH"
    echo "  Port:               $PORT"
    echo "  Memory Frac:        $MEM"
    echo "  Context Length:     1048576"
    echo "  Max Running Reqs:   16"
    echo "  Max Total Tokens:   1048576"
    echo "  Chunked Prefill:    8192"
    echo "  Schedule Policy:    lru"
    echo "  TP Size:            $TP"
    echo "  Reasoning:          ${REASONING:-None}"
    echo "  Tool Call:          ${TOOLCALL:-None}"
    echo "  Extra Flags:        $EXTRA_FLAGS"
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
