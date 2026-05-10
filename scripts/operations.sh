#!/bin/bash
# =============================================================================
# SGLang Dynamic Orchestrator - Phase 3: Operations (Pro Tools)
# =============================================================================

BASE_DIR="/home/don/llms/sglang_orchestrator"
VENV_DIR="/home/don/llms/sglang_venv"
VENV_PYTHON="$VENV_DIR/bin/python"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- PHASE 3: OPERATIONS ---

list_processes() {
    echo -e "${BLUE}=== Running SGLang Engines ===${NC}"
    if pgrep -f "sglang.launch_server" > /dev/null; then
        printf "%-8s | %-30s | %-10s | %-8s\n" "PID" "COMMAND" "USER" "PORT"
        echo "------------------------------------------------------------"
        ps aux | grep "sglang.launch_server" | grep -v grep | while read -r pid user cpu mem vsz rss tty time cmd; do
            # Extract port from command line if present
            port=$(echo "$cmd" | grep -oP '--port \K[0-9]+' || echo "N/A")
            cmd_brief=$(echo "$cmd" | cut -c 1-30)
            printf "%-8s | %-30s | %-10s | %-8s\n" "$pid" "$cmd_brief" "$user" "$port"
        done
    else
        echo "No running SGLang engines detected."
    fi
}

kill_engine() {
    local target_pid=$1
    if [[ -z "$target_pid" ]]; then
        error "Please provide a PID."
    fi

    log "Attempting to stop engine PID: $target_pid"
    kill "$target_pid" || kill -9 "$target_pid"
    
    # Confirmation loop
    for i in {1..5}; do
        if ! ps -p "$target_pid" > /dev/null; then
            success "Engine $target_pid stopped."
            return
        fi
        sleep 1
    done
    warn "Process $target_pid might still be hanging."
}

tail_logs() {
    log "Listening for SGLang logs (Press Ctrl+C to stop)..."
    # In a production environment, logs would go to files. 
    # Here we simulate 'tail -f' for the active process.
    local pid=$(pgrep -f "sglang.launch_server")
    if [[ -z "$pid" ]]; then
        error "No active SGLang process found."
    fi
    
    # Since we don't have a standard log file yet, we'll try to simulate 
    # either by reading from a redirected log or just showing the process state.
    # REAL IMPLEMENTATION: Launch command should include > $LOG_DIR/sglang.log 2>&1
    log "Note: Direct stdout tail is unavailable without file redirection."
    log "Check $BASE_DIR/logs/ or ensure launch command redirects output."
    list_processes
}

case "${1:-}" in
    --list)
        list_processes
        ;;
    --kill)
        kill_engine "${2:-}"
        ;;
    --logs)
        tail_logs
        ;;
    *)
        echo "SGLang Orchestrator Phase 3"
        echo "Usage: $0 {--list|--kill <pid>|--logs}"
        ;;
esac
