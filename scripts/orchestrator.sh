#!/bin/bash
# =============================================================================
# SGLang Dynamic Orchestrator v8.37 (Gemma-4 Focused)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

SGLANG_REPO="$PROJECT_ROOT/sglang_repo"
SGLANG_VENV="$PROJECT_ROOT/sglang_venv"
MODELS_DIR="$PROJECT_ROOT/models"
LOG_DIR="$PROJECT_ROOT/logs"

error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }

bootstrap_workspace() {
    mkdir -p "$PROJECT_ROOT"/{sglang_repo,sglang_venv,models,logs,config,modules}
}
bootstrap_workspace

print_header() {
    if [ ! -t 0 ]; then return; fi
    clear
    echo "============================================================"
    echo " SGLang Dynamic Orchestrator v8.37 (Gemma-4 Focused)"
    echo "============================================================"
    echo " Workspace: $PROJECT_ROOT"
    echo "------------------------------------------------------------"
}

# ====================== DOCKER LAUNCHES ======================
launch_gemma4_normal() {
    print_header
    echo "--- 🚀 Launching Gemma-4 (Normal Mode) ---"

    docker stop sglang-gemma4 2>/dev/null || true
    docker rm sglang-gemma4 2>/dev/null || true

    docker run --gpus all --shm-size 32g -p 30001:30001 \
        -v "$MODELS_DIR:/models" \
        --name sglang-gemma4 \
        -d \
        lmsysorg/sglang:cu13-gemma4 \
        python -m sglang.launch_server \
            --model-path /models/unsloth/gemma-4-26B-A4B-it \
            --host 0.0.0.0 \
            --port 30001 \
            --mem-fraction-static 0.92 \
            --max-total-tokens 250000 \
            --reasoning-parser gemma4 \
            --tool-call-parser gemma4 \
            --chat-template /models/unsloth/gemma-4-26B-A4B-it/chat_template.jinja \
            --trust-remote-code
}

launch_gemma4_mtp() {
    print_header
    echo "--- 🚀 Launching Gemma-4 + MTP (NextN Speculative Decoding) ---"

    docker stop sglang-gemma4 2>/dev/null || true
    docker rm sglang-gemma4 2>/dev/null || true

    docker run --gpus all --shm-size 32g -p 30001:30001 \
        -v "$MODELS_DIR:/models" \
        --name sglang-gemma4-mtp \
        -d \
        lmsysorg/sglang:cu13-gemma4 \
        python -m sglang.launch_server \
            --model-path /models/unsloth/gemma-4-26B-A4B-it \
            --host 0.0.0.0 \
            --port 30001 \
            --mem-fraction-static 0.75 \
	    --max-total-tokens 180000 \
            --reasoning-parser gemma4 \
            --tool-call-parser gemma4 \
            --chat-template /models/unsloth/gemma-4-26B-A4B-it/chat_template.jinja \
            --trust-remote-code \
            --speculative-algorithm NEXTN \
            --speculative-draft-model-path /models/google/gemma-4-26B-A4B-it-assistant \
            --speculative-num-steps 5 \
            --speculative-num-draft-tokens 6 \
	    --speculative-eagle-topk 1
}

show_status() {
    print_header
    echo "--- 📊 SYSTEM STATUS ---"
    if docker ps | grep -q sglang-gemma4; then
        echo "Gemma-4 Docker: [RUNNING]"
    else
        echo "Gemma-4 Docker: [STOPPED]"
    fi
    echo "------------------------------------------------------------"
}

# Main menu
if [ ! -t 0 ]; then
    cmd_opt=$(cat -)
    case $cmd_opt in
        6) setup_environment ;;
        3) show_status ;;
        *) exit 1 ;;
    esac
else
    while true; do
        print_header
        echo "=== Local Launches ==="
        echo "1) [LAUNCH] Select & Start Model (Local Venv)"
        echo "2) [DOWNLOAD] HuggingFace Model"
        echo ""
        echo "=== Docker Launches (Recommended) ==="
        echo "9)  [🚀] Gemma-4 Normal Mode"
        echo "10) [🚀] Gemma-4 + MTP (NextN Speculative)"
        echo ""
        echo "=== Maintenance ==="
        echo "3) [MAINT] Show Status"
        echo "4) [MAINT] List / Stop Engines"
        echo "5) [MAINT] Show Logs"
        echo "6) [🛠️ SETUP] Rebuild Environment"
        echo "8) [EXIT]"
        echo "------------------------------------------------------------"
        printf "Select an option: "
        read -r opt

        case $opt in
            1) "$SCRIPT_DIR/intelligence.sh" --select-launch ; read -p "Press enter to continue..." ;;
            2) read -p "Enter HF Repo ID: " hf_repo && "$SCRIPT_DIR/intelligence.sh" --download "$hf_repo" ; read -p "Press enter..." ;;
            3) show_status ; read -p "Press enter to continue..." ;;
            4) "$SCRIPT_DIR/operations.sh" --list ; read -p "Press enter to continue..." ;;
            5) "$SCRIPT_DIR/operations.sh" --logs ; read -p "Press enter to continue..." ;;
            6) setup_environment ; read -p "Press enter to continue..." ;;
            9) launch_gemma4_normal ; read -p "Press enter to continue..." ;;
            10) launch_gemma4_mtp ; read -p "Press enter to continue..." ;;
            8) exit 0 ;;
            *) echo "Invalid option." ; sleep 1 ;;
        esac
    done
fi
