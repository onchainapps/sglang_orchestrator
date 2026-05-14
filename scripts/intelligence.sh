#!/bin/bash
# =============================================================================
# SGLang Orchestrator - Intelligence (Resilient Hybrid Download) v2.1
# =============================================================================
# Standalone CLI for model download/scan/launch.
# Sources lib_models.sh for shared utilities.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

source "$SCRIPT_DIR/modules/lib_models.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; return 1; }

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

    # --- AUTO-DOWNLOAD LOGIC (FIXED - removed broken $profile_key reference) ---
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
    --max-running-requests 2 \
    --max-queued-requests 8 \
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

case "${1:-}" in
    --scan) scan_models_internal ;;
    --select-launch|--launch) select_and_launch ;;
    --download) download_model "${2:-}" ;;
    *) echo "Usage: $0 {--scan|--select-launch|--download <repo>}";;
esac
