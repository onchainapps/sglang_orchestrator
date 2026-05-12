#!/bin/bash
# =============================================================================
# SGLang Dynamic Orchestrator - Operations (Fixed & Portable)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

list_processes() {
    echo -e "${BLUE}=== Running SGLang Engines ===${NC}"

    if ! pgrep -f "sglang.launch_server" > /dev/null; then
        echo "No running SGLang engines."
        return
    fi

    printf "%-8s | %-60s | %-8s\n" "PID" "MODEL" "PORT"
    echo "----------------------------------------------------------------"

    ps aux | grep "sglang.launch_server" | grep -v grep | while read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        
        # Extract port and model path safely
        port=$(echo "$line" | grep -o '--port [0-9]*' | grep -o '[0-9]*' || echo "N/A")
        model_path=$(echo "$line" | grep -o '--model-path [^ ]*' | cut -d' ' -f2- || echo "unknown")
        model_name=$(basename "$model_path" 2>/dev/null || echo "$model_path")

        printf "%-8s | %-60s | %-8s\n" "$pid" "${model_name:0:58}" "$port"
    done
}

kill_engine() {
    local pid=$1
    [ -z "$pid" ] && error "Usage: --kill <PID>"
    log "Stopping PID $pid..."
    kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
    success "Engine stopped."
}

tail_logs() {
    local latest_log=$(ls -t "$LOG_DIR"/sglang_port*.log 2>/dev/null | head -1)
    if [ -n "$latest_log" ]; then
        log "Tailing latest log: $latest_log (Ctrl+C to stop)"
        tail -f "$latest_log"
    else
        error "No log files found in $LOG_DIR"
    fi
}

case "${1:-}" in
    --list) list_processes ;;
    --kill) kill_engine "${2:-}" ;;
    --logs) tail_logs ;;
    *) echo "Usage: $0 {--list|--kill <pid>|--logs}";;
esac
