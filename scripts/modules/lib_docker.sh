#!/bin/bash
# =============================================================================
# SGLang Orchestrator - Docker Module (lib_docker.sh)
# =============================================================================

set -uo pipefail

# These will be provided by the caller (orchestrator.sh)
# PROJECT_ROOT, MODELS_DIR, LOG_DIR

# Specialized Docker Image Mapping
declare -A DOCKER_PROFILES
DOCKER_PROFILES["gemma4"]="lmsysorg/sglang:cu13-gemma4|google/gemma-4-27b|bf16|true"
DOCKER_PROFILES["qwen3.6-35b"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-35B-MoE|bf16|false"
DOCKER_PROFILES["qwen3.6-27b"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-27B|bf16|false"
DOCKER_PROFILES["nemotron"]="lmsysorg/sglang:dev-cu13-nemotronh-nano-omni-reasoning-v3|nvidia/nemotron-nano-omni|bf16|false"
DOCKER_PROFILES["mistral"]="lmsysorg/sglang:dev-cu13-mistral-medium-3.5|mistralai/Mistral-Medium-3.5|bf16|false"
DOCKER_PROFILES["deepseek"]="lmsysorg/sglang:deepseek-v4-blackwell|deepseek-ai/DeepSeek-V4|bf16|false"

docker_launch_model() {
    local profile_key=$1
    local use_mtp=${2:-false}

    if [[ -z "${DOCKER_PROFILES[$profile_key]:-}" ]]; then
        echo -e "\033[0;31m[ERROR]\033[0m Unknown Docker profile: $profile_key"
        return 1
    fi

    IFS='|' read -r docker_img hf_id precision mtp_cap <<< "${DOCKER_PROFILES[$profile_key]}"

    # --- AUTO-DOWNLOAD LOGIC ---
    local target_model_path="$MODELS_DIR/$hf_id"
    if [ ! -d "$target_model_path" ] || [ ! -f "$target_model_path/config.json" ]; then
        echo -e "\033[1;33m⚠️  Model not found locally: $hf_id\033[0m"
        read -p "Would you like to download it from Hugging Face? (y/n): " dl_choice
        if [[ "$dl_choice" =~ ^[yY]$ ]]; then
            echo "Starting download for $hf_id..."
            bash "$SCRIPT_DIR/intelligence.sh" --download "$hf_id"
            if [ $? -ne 0 ]; then
                echo -e "\033[0;31m[ERROR] Download failed. Aborting launch.\033[0m"
                return 1
            fi
            target_model_path="$MODELS_DIR/$hf_id"
            echo -e "\033[0;32m✅ Download complete. Model located at: $target_model_path\033[0m"
        else
            echo -e "\033[0;31m[ERROR] Model required for this profile. Aborting.\033[0m"
            return 1
        fi
    fi
    # --------------------------------

    # --- BUILD COMMAND ---
    local mem_fraction="0.75"
    local max_tokens="131072"
    local extra_args=""
    
    if [[ "$profile_key" == "gemma4" ]]; then
        extra_args="--reasoning-parser gemma4 --tool-call-parser gemma4"
    fi

    local mtp_args=""
    if [[ "$use_mtp" == "true" && "$mtp_cap" == "true" ]]; then
        echo "  [MTP] Applying Speculative Decoding..."
        mtp_args="--speculative-algorithm NEXTN \
                  --speculative-draft-model-path /models/google/gemma-4-26B-A4B-it-assistant \
                  --speculative-num-steps 5 \
                  --speculative-num-draft-tokens 6"
    fi

    # --- RUNTIME PARAMETER REVIEW ---
    echo "------------------------------------------------------------"
    echo "📋 RUNTIME PARAMETERS REVIEW (DOCKER)"
    echo "------------------------------------------------------------"
    echo "  Profile:       $profile_key"
    echo "  Docker Image:  $docker_img"
    echo "  Model Path:    $target_model_path"
    echo "  Port:          30001"
    echo "  Memory Frac:   $mem_fraction"
    echo "  MTP Mode:      $use_mtp"
    echo "  Extra Args:    $extra_args"
    echo "  MTP Args:      $mtp_args"
    echo "------------------------------------------------------------"
    
    read -p "Proceed with launch? (Y/n): " confirm
    [[ "$confirm" =~ ^[nN]$ ]] && { echo "Cancelled."; return 0; }

    echo "Executing: docker run ..."
    docker stop "sglang-$profile_key" 2>/dev/null || true
    docker rm "sglang-$profile_key" 2>/dev/null || true

    docker run --gpus all --shm-size 32g -p 30001:30001 \
        -v "$MODELS_DIR:/models" \
        --name "sglang-$profile_key" \
        -d \
        "$docker_img" \
        python -m sglang.launch_server \
            --model-path "$target_model_path" \
            --host 0.0.0.0 \
            --port 30001 \
            --dtype "$precision" \
            --mem-fraction-static "$mem_fraction" \
            --max-total-tokens "$max_tokens" \
            $extra_args \
            $mtp_args \
            --trust-remote-code

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
    for key in "${!DOCKER_PROFILES[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "sglang-$key"; then
            printf "%-20s | \033[0;32m%-10s\033[0m | sglang-$key\n" "$key" "RUNNING"
        else
            printf "%-20s | \033[0;31m%-10s\033[0m | --\n" "$key" "STOPPED"
        fi
    done
    echo "------------------------------------------------------------"
}
