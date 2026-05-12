#!/bin/bash
# =============================================================================
# SGLang Orchestrator - Docker Module (lib_docker.sh)
# =============================================================================

set -uo pipefail

# These will be provided by the caller (orchestrator.sh)
# PROJECT_ROOT, MODELS_DIR, LOG_DIR

# Load Parameters Module
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/lib_params.sh"

# --- CORE LAUNCHER ---

docker_launch_model() {
    local profile_key=$1
    local use_mtp=${2:-false}
    local mem_fraction=${3:-0.75}
    local context_length=${4:-262111}

    # 1. Get core profile data from lib_params
    local profile_data
    profile_data=$(get_profile_data "$profile_key")
    if [ $? -ne 0 ]; then
        echo -e "\033[0;31m[ERROR]\033[0m Unknown Docker profile: $profile_key"
        return 1
    fi

    IFS='|' read -r docker_img hf_id precision mtp_cap drafter_repo spec_args <<< "$profile_data"

    # 2. Target path for base model
    local target_model_path="$MODELS_DIR/$hf_id"

    # 3. Auto-Download Logic (Base Model)
    if [ ! -d "$target_model_path" ] || [ ! -f "$target_model_path/config.json" ]; then
        echo -e "\033[1;33m⚠️  Base Model not found locally: $hf_id\033[0m"
        read -p "Would you like to download it from Hugging Face? (y/n): " dl_choice
        if [[ "$dl_choice" =~ ^[yY]$ ]]; then
            echo "Starting download for $hf_id..."
            bash "$MODULE_DIR/../intelligence.sh" --download "$hf_id"
            if [ $? -ne 0 ]; then
                echo -e "\033[0;31m[ERROR] Download failed. Aborting launch.\033[0m"
                return 1
            fi
            target_model_path="$MODELS_DIR/$hf_id"
            echo -e "\033[0;32m✅ Base model located at: $target_model_path\033[0m"
        else
            echo -e "\033[0;31m[ERROR] Base model required for this profile. Aborting.\033[0m"
            return 1
        fi
    fi

    # 4. Handle Speculative Decoding (MTP) logic - supports both external drafter and built-in MTP
    local mtp_args=""
    if [[ "$use_mtp" == "true" && "$mtp_cap" == "true" ]]; then
        if [ -n "$drafter_repo" ]; then
            # Case 1: External drafter (e.g. Gemma 4)
            local drafter_path="$MODELS_DIR/$drafter_repo"

            if [ ! -d "$drafter_path" ] || [ ! -f "$drafter_path/config.json" ]; then
                echo -e "\033[1;33m⚠️  Drafter Model not found: $drafter_repo\033[0m"
                read -p "Download Drafter model now? (y/n): " dl_choice
                if [[ "$dl_choice" =~ ^[yY]$ ]]; then
                    bash "$MODULE_DIR/../intelligence.sh" --download "$drafter_repo"
                    drafter_path="$MODELS_DIR/$drafter_repo"
                else
                    echo -e "\033[0;31m[ERROR] Drafter required for MTP. Aborting.\033[0m"
                    return 1
                fi
            fi

            echo "  [MTP] Applying Speculative Decoding with external drafter ($spec_algo)..."
            mtp_args="--speculative-algorithm $spec_algo --speculative-draft-model-path $drafter_path --speculative-num-steps 5 --speculative-num-draft-tokens 6"
        else
            # Case 2: Built-in MTP (Qwen3.6, DeepSeek) - use EAGLE (more stable)
            echo "  [MTP] Applying built-in Speculative Decoding (EAGLE)..."
            mtp_args="--speculative-algorithm EAGLE --speculative-num-steps 3 --speculative-eagle-topk 1 --speculative-num-draft-tokens 4"
        fi
    fi

    # 5. Prepare Launch Command (clean flag building)
    # Lower memory when MTP is enabled (needs extra buffers)
    if [[ "$use_mtp" == "true" ]]; then
        local mem_fraction="0.60"   # Even lower for safety with MTP
    else
        local mem_fraction="0.75"
    fi
    local max_tokens="131072"

    # Base flags (common + memory management)
    local base_flags="--reasoning-parser qwen3 --tool-call-parser qwen3_coder --allow-auto-truncate --context-length $context_length --hf-chat-template-name qwen3 --max-running-requests 256 --schedule-policy lpm --chunked-prefill-size 8192 --trust-remote-code"

    # Model-specific overrides
    if [[ "$profile_key" == "gemma4" ]]; then
        base_flags="--reasoning-parser gemma4 --tool-call-parser gemma4 --allow-auto-truncate --context-length $context_length --hf-chat-template-name gemma --max-running-requests 256 --schedule-policy lpm --chunked-prefill-size 8192 --trust-remote-code"
    elif [[ "$profile_key" == "deepseek" ]]; then
        base_flags="--reasoning-parser deepseek-v4 --tool-call-parser deepseekv4 --allow-auto-truncate --context-length $context_length --hf-chat-template-name deepseek --max-running-requests 256 --schedule-policy lpm --chunked-prefill-size 4096 --moe-runner-backend flashinfer_mxfp4 --trust-remote-code"
    elif [[ "$profile_key" == "qwen3.6-35b" || "$profile_key" == "qwen3.6-27b" ]]; then
        base_flags="--mamba-scheduler-strategy extra_buffer --page-size 64 --reasoning-parser qwen3 --tool-call-parser qwen3_coder --allow-auto-truncate --context-length $context_length --hf-chat-template-name qwen3 --max-running-requests 256 --schedule-policy lpm --chunked-prefill-size 8192 --trust-remote-code"
    fi

    # Combine everything
    local final_flags="$base_flags $mtp_args"

    echo "------------------------------------------------------------"
    echo "📋 RUNTIME PARAMETERS REVIEW (DOCKER)"
    echo "------------------------------------------------------------"
    echo "  Profile:       $profile_key"
    echo "  Docker Image:  $docker_img"
    echo "  Base Model:    $hf_id"
    echo "  Drafter:       ${drafter_repo:-None}"
    echo "  Port:          30001"
    echo "  Memory Frac:   $mem_fraction"
    echo "  Context Len:   $context_length"
    echo "  MTP Mode:      $use_mtp"
    echo "  Final Flags:   $final_flags"
    echo "------------------------------------------------------------"
    
    read -p "Proceed with launch? (Y/n): " confirm
    [[ "$confirm" =~ ^[nN]$ ]] && { echo "Cancelled."; return 0; }

    echo "Executing: docker run ..."
    docker stop "sglang-$profile_key" 2>/dev/null || true
    docker rm "sglang-$profile_key" 2>/dev/null || true

    # Use container-internal path (because of -v "$MODELS_DIR:/models")
    local container_model_path="/models/$hf_id"

    docker run --gpus all --shm-size 32g -p 30001:30001 \
        -v "$MODELS_DIR:/models" \
        --name "sglang-$profile_key" \
        -d \
        "$docker_img" \
        python -m sglang.launch_server \
            --model-path "$container_model_path" \
            --host 0.0.0.0 \
            --port 30001 \
            --dtype "$precision" \
            --mem-fraction-static "$mem_fraction" \
            --max-total-tokens "$max_tokens" \
            $final_flags

    if [ $? -eq 0 ]; then
        echo "✅ Container 'sglang-$profile_key' is running."
    else
        echo "❌ Failed to launch Docker container."
        return 1
    fi
}

docker_show_status() {
    echo "--- 🐳 ACTIVE DOCKER ENGINES ---"
    printf "%-20s | %-10s | %-15s\n" "PROFILE" "STATUS" "CONTAINER"
    echo "------------------------------------------------------------"
    for key in $(get_all_profiles); do
        if docker ps --format '{{.Names}}' | grep -q "sglang-$key"; then
            printf "%-20s | \033[0;32m%-10s\033[0m | sglang-$key\n" "$key" "RUNNING"
        else
            printf "%-20s | \033[0;31m%-10s\033[0m | --\n" "$key" "STOPPED"
        fi
    done
    echo "------------------------------------------------------------"
}
