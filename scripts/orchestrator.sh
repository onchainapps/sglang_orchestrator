#!/bin/bash
# =============================================================================
# SGLang Dynamic Orchestrator v9.1 (Interactive Profile Engine)
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
    echo " SGLang Dynamic Orchestrator v9.1 (Interactive Profile Engine)"
    echo "============================================================"
    echo " Workspace: $PROJECT_ROOT"
    echo "------------------------------------------------------------"
}

# ====================== PROFILE ENGINE ======================

declare -A MODEL_PROFILES
MODEL_PROFILES["gemma4"]="lmsysorg/sglang:cu13-gemma4|google/gemma-4-27b|bf16|true"
MODEL_PROFILES["qwen3.6-35b"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-35B-MoE|bf16|false"
MODEL_PROFILES["qwen3.6-27b"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-27B|bf16|false"
MODEL_PROFILES["nemotron"]="lmsysorg/sglang:dev-cu13-nemotronh-nano-omni-reasoning-v3|nvidia/nemotron-nano-omni|bf16|false"
MODEL_PROFILES["mistral"]="lmsysorg/sglang:dev-cu13-mistral-medium-3.5|mistralai/Mistral-Medium-3.5|bf16|false"
MODEL_PROFILES["deepseek"]="lmsysorg/sglang:deepseek-v4-blackwell|deepseek-ai/DeepSeek-V4|bf16|false"

# ====================== CORE LAUNCHER ======================

launch_model() {
    local profile_key=$1
    local use_mtp=${2:-false}
    
    if [[ -z "${MODEL_PROFILES[$profile_key]:-}" ]]; then
        error "Unknown profile: $profile_key"
    fi

    IFS='|' read -r docker_img hf_id precision mtp_cap <<< "${MODEL_PROFILES[$profile_key]}"

    print_header
    echo "--- 🚀 Launching $profile_key Profile ---"
    echo "  Docker Image: $docker_img"
    echo "  HF Repository: $hf_id"
    echo "  Precision: $precision"
    [[ "$use_mtp" == "true" ]] && echo "  MTP Mode: ENABLED" || echo "  MTP Mode: DISABLED"
    echo "------------------------------------------------------------"

    docker stop "sglang-$profile_key" 2>/dev/null || true
    docker rm "sglang-$profile_key" 2>/dev/null || true

    local mem_fraction="0.75"
    local max_tokens="131072"
    local extra_args=""
    
    if [[ "$profile_key" == "gemma4" ]]; then
        extra_args="--reasoning-parser gemma4 --tool-call-parser gemma4"
    fi

    local mtp_args=""
    if [[ "$use_mtp" == "true" && "$mtp_cap" == "true" ]]; then
        echo "  [MTP] Applying Speculative Decoding (NextN)..."
        mtp_args="--speculative-algorithm NEXTN \
                  --speculative-draft-model-path /models/google/gemma-4-26B-A4B-it-assistant \
                  --speculative-num-steps 5 \
                  --speculative-num-draft-tokens 6"
    fi

    echo "  Executing: docker run ..."
    
    docker run --gpus all --shm-size 32g -p 30001:30001 \
        -v "$MODELS_DIR:/models" \
        --name "sglang-$profile_key" \
        -d \
        "$docker_img" \
        python -m sglang.launch_server \
            --model-path "/models/$hf_id" \
            --host 0.0.0.0 \
            --port 30001 \
            --dtype "$precision" \
            --mem-fraction-static "$mem_fraction" \
            --max-total-tokens "$max_tokens" \
            $extra_args \
            $mtp_args \
            --trust-remote-code

    if [ $? -eq 0 ]; then
        echo "✅ Container 'sglang-$profile_key' is starting in background."
    else
        error "Failed to launch Docker container."
    fi
}

show_status() {
    print_header
    echo "--- 📊 ACTIVE SGLANG ENGINES ---"
    printf "%-20s | %-10s | %-15s\n" "PROFILE" "STATUS" "CONTAINER"
    echo "------------------------------------------------------------"
    for key in "${!MODEL_PROFILES[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "sglang-$key"; then
            printf "%-20s | \033[0;32m%-10s\033[0m | sglang-$key\n" "$key" "RUNNING"
        else
            printf "%-20s | \033[0;31m%-10s\033[0m | --\n" "$key" "STOPPED"
        fi
    done
    echo "------------------------------------------------------------"
}

# ====================== MAIN MENU ======================

if [ ! -t 0 ]; then
    cmd_opt=$(cat -)
    case $cmd_opt in
        "launch"*) 
            read -r _ p_key p_mtp <<< "$cmd_opt"
            launch_model "$p_key" "$p_mtp"
            ;;
        "status") show_status ;;
        *) exit 1 ;;
    esac
else
    while true; do
        print_header
        echo "=== [🚀] SGLang Profile Orchestrator v9.1 ==="
        echo "  Optimized for RTX 6000 PRO (96GB VRAM)"
        echo "------------------------------------------------------------"
        echo "1) [🚀] Launch Model Profile"
        echo "2) [📊] Show Engine Status"
        echo "3) [🛠️] Rebuild Workspace"
        echo "4) [❌] Exit"
        echo "------------------------------------------------------------"
        printf "Select option: "
        read -r opt

        case $opt in
            1)
                echo "Available Profiles:"
                i=1
                mapfile -t keys < <(for k in "${!MODEL_PROFILES[@]}"; do echo "$k"; done)
                for k in "${keys[@]}"; do
                    echo "$i) $k"
                    ((i++))
                done
                
                read -p "Select Profile #: " p_idx
                if [[ ! "$p_idx" =~ ^[0-9]+$ ]] || [ "$p_idx" -lt 1 ] || [ "$p_idx" -gt "${#keys[@]}" ]; then
                    echo "Invalid selection."
                    sleep 1
                    continue
                fi
                
                selected_key="${keys[$((p_idx-1))]}"
                
                IFS='|' read -r _ _ _ mtp_cap <<< "${MODEL_PROFILES[$selected_key]}"
                mtp_choice="false"
                if [[ "$mtp_cap" == "true" ]]; then
                    read -p "Enable MTP (Multi-Token Prediction)? (y/n): " mtp_input
                    [[ "$mtp_input" == "y" ]] && mtp_choice="true"
                fi

                launch_model "$selected_key" "$mtp_choice"
                read -p "Press enter to continue..."
                ;;
            2) show_status ; read -p "Press enter..." ;;
            3) bootstrap_workspace ; echo "Workspace rebuilt." ; read -p "Press enter..." ;;
            4) exit 0 ;;
            *) echo "Invalid option." ; sleep 1 ;;
        esac
    done
fi
