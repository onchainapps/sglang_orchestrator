#!/bin/bash
# =============================================================================
# SGLang Dynamic Orchestrator - Phase 1: Core Infrastructure
# =============================================================================
# Re-engineered for robustness, version-agnosticism, and local execution.
# =============================================================================

set -euo pipefail

# --- PATHS & ENV ---
BASE_DIR="/home/don/llms/sglang_orchestrator"
REPO_DIR="/home/don/llms/sglang_repo"
VENV_DIR="/home/don/llms/sglang_venv"
MODELS_DIR="/home/don/llms/models"
LOG_DIR="$BASE_DIR/logs"
CONFIG_DIR="$BASE_DIR/config"

# Detect if terminal is interactive
IS_TTY=false
[[ -t 0 ]] && IS_TTY=true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- LOGGING ---
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- PHASE 1: SETUP & RECOVERY ---

check_dependencies() {
    log "Checking system dependencies..."

    # 1. Rust Detection & Installation
    if ! command -v cargo &> /dev/null; then
        warn "Rust/Cargo not found. Attempting auto-install via rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        log "Rust found: $(cargo --version)"
    fi

    # 2. Protoc Detection
    if ! command -v protoc &> /dev/null; then
        warn "protoc not found. SGLang compilation may fail."
        log "Tip: Install via 'sudo apt install protobuf-compiler'"
    else
        log "Protoc found: $(protoc --version)"
    fi

    # 3. Python Discovery
    log "Discovering stable Python (3.10-3.12)..."
    PYTHON_EXE=""
    for ver in python3.12 python3.11 python3.10 python3; do
        if command -v "$ver" &> /dev/null; then
            PYTHON_EXE=$(command -v "$ver")
            log "Found Python: $PYTHON_EXE"
            break
        fi
    done

    if [[ -z "$PYTHON_EXE" ]]; then
        error "No compatible Python 3.x found."
    fi

    # 4. Venv Management
    if [[ ! -d "$VENV_DIR" ]]; then
        log "Creating virtual environment at $VENV_DIR..."
        "$PYTHON_EXE" -m venv "$VENV_DIR"
    fi
    VENV_PYTHON="$VENV_DIR/bin/python"
    VENV_PIP="$VENV_DIR/bin/pip"
    
    log "Python Environment ready: $VENV_PYTHON"
}

nuke_reset() {
    warn "!!! NUCLEAR RESET INITIATED !!!"
    read -p "This will delete $REPO_DIR and $VENV_DIR. Are you sure? (y/N) " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log "Wiping $REPO_DIR..."
        rm -rf "$REPO_DIR"
        log "Wiping $VENV_DIR..."
        rm -rf "$VENV_DIR"
        success "Clean slate achieved. Please run --setup again."
    else
        log "Reset aborted."
    fi
}

show_status() {
    echo -e "${BLUE}=== SGLang Orchestrator Status ===${NC}"
    echo "--- System ---"
    echo "Python: $($VENV_PYTHON --version 2>/dev/null || echo 'Not in venv')"
    echo "Rust:   $(cargo --version 2>/dev/null || echo 'Not found')"
    echo "Protoc: $(protoc --version 2>/dev/null || echo 'Not found')"
    
    echo -e "\n--- GPU ---"
    nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu --format=csv,noheader || echo "No NVIDIA GPU detected."

    echo -e "\n--- SGLang Engines ---"
    if pgrep -f "sglang.launch_server" > /dev/null; then
        echo "Status: RUNNING"
        ps aux | grep "sglang.launch_server" | grep -v grep
    else
        echo "Status: STOPPED"
    fi
}

# --- MAIN DISPATCHER ---

case "${1:-}" in
    --setup)
        check_dependencies
        ;;
    --nuke)
        nuke_reset
        ;;
    --status)
        show_status
        ;;
    --help|*)
        echo "SGLang Dynamic Orchestrator"
        echo "Usage: $0 {--setup|--nuke|--status|--help}"
        echo ""
        echo "  --setup    Install/Configure Rust, Protoc, Python venv, and sglang_repo"
        echo "  --nuke     Wipe venv and sglang_repo for a fresh start"
        echo "  --status   Deep diagnostics of system and SGLang engines"
        ;;
esac
