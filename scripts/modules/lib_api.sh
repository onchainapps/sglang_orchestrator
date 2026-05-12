#!/bin/bash
# =============================================================================
# SGLang Orchestrator - API Module (lib_api.sh) v2.0 (FIXED)
# =============================================================================

set -uo pipefail

# These will be provided by the caller (orchestrator.sh)
# PROJECT_ROOT

log() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; return 1; }

expose_api() {
    local port=${1:-30001}
    log "Starting API Exposure on port $port..."
    
    local expose_script="$PROJECT_ROOT/expose-api.sh"
    
    if [ -f "$expose_script" ]; then
        # FIXED: Use correct flags for expose-api.sh
        bash "$expose_script" --proxy --api-port "$port"
    else
        error "expose-api.sh not found at $expose_script"
        return 1
    fi
}
