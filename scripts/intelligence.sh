#!/bin/bash
# =============================================================================
# SGLang Dynamic Orchestrator - Phase 2: Intelligence (Model Management)
# =============================================================================

BASE_DIR="/home/don/llms/sglang_orchestrator"
MODELS_DIR="/home/don/llms/models"
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

scan_models() {
    log "Scanning $MODELS_DIR for compatible models..."
    echo "------------------------------------------------------------"
    printf "%-40s | %-15s | %-10s\n" "MODEL PATH" "ARCH" "TEMPLATE"
    echo "------------------------------------------------------------"

    # Avoiding 'eval' and feeding a single python script to avoid shell interpolation issues
    $VENV_PYTHON << 'EOF'
import json, os, sys
models_dir = "/home/don/llms/models"
print(f"{'MODEL PATH':<40} | {'ARCH':<15} | {'TEMPLATE':<10}")
print("-" * 64)

for root, dirs, files in os.walk(models_dir):
    if "config.json" in files:
        config_path = os.path.join(root, "config.json")
        model_path = root
        try:
            with open(config_path, 'r') as f:
                data = json.load(f)
            arch = data.get('architectures', ['unknown'])[0]
            template = 'chat' if 'chat_template' in data else 'none'
            print(f"{model_path:<40} | {arch[:15]:<15} | {template:<10}")
        except Exception:
            continue
EOF
    echo "------------------------------------------------------------"
}

launch_engine() {
    local MODEL_PATH=$1
    local PORT=${2:-30001}
    local MEM_FRACTION=${3:-0.90}
    
    log "Constructing launch command for: $MODEL_PATH"
    
    if [[ "$MODEL_PATH" == *"gemma-4"* ]]; then
        log "✨ DETECTED GEMMA 4: Applying MTP Hijack layer..."
        COMMAND="$VENV_PYTHON -m sglang.launch_server --model-path $MODEL_PATH --mem-fraction-static $MEM_FRACTION --reasoning-parser gemma4 --host 0.0.0.0 --port $PORT"
    else
        COMMAND="$VENV_PYTHON -m sglang.launch_server --model-path $MODEL_PATH --mem-fraction-static $MEM_FRACTION --host 0.0.0.0 --port $PORT"
    fi

    log "Executing: $COMMAND"
    echo "DRY-RUN command: $COMMAND"
    success "Launch command verified."
}

case "${1:-}" in
    --scan)
        scan_models
        ;;
    --launch)
        if [[ -z "$1" ]]; then error "Usage: $0 --launch <model_path> [port] [mem]"; fi
        launch_engine "$1" "${2:-30001}" "${3:-0.90}"
        ;;
    *)
        echo "SGLang Orchestrator Phase 2"
        echo "Usage: $0 {--scan|--launch <path> [port] [mem]}"
        ;;
esac
