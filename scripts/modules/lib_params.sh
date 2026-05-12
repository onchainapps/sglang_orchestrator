#!/bin/bash
# =============================================================================
# SGLang Orchestrator - Parameter Library (Simplified v3.0)
# =============================================================================
# Clean structure - only core model info. All launch flags moved to lib_docker.sh
# =============================================================================

set -uo pipefail

declare -A MODEL_PARAMS

# Format: DOCKER_IMAGE|HF_REPO|PRECISION|MTP_SUPPORTED(true/false)
MODEL_PARAMS["gemma4"]="lmsysorg/sglang:cu13-gemma4|google/gemma-4-26B-A4B-it|bfloat16|true"
MODEL_PARAMS["qwen3.6-35b"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-35B-A3B|bfloat16|true"
MODEL_PARAMS["qwen3.6-27b"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-27B|bfloat16|true"
MODEL_PARAMS["nemotron"]="lmsysorg/sglang:dev-cu13-nemotronh-nano-omni-reasoning-v3|nvidia/nemotron-nano-omni|bfloat16|false"
MODEL_PARAMS["mistral"]="lmsysorg/sglang:dev-cu13-mistral-medium-3.5|mistralai/Mistral-Medium-3.5|bfloat16|false"
MODEL_PARAMS["deepseek"]="lmsysorg/sglang:deepseek-v4-blackwell|deepseek-ai/DeepSeek-V4-Flash|bfloat16|true"

get_profile_data() {
    local key=$1
    echo "${MODEL_PARAMS[$key]:-}"
}

get_all_profiles() {
    for key in "${!MODEL_PARAMS[@]}"; do
        echo "$key"
    done
}

get_mtp_capability() {
    local key=$1
    local data="${MODEL_PARAMS[$key]:-}"
    IFS='|' read -r _ _ _ mtp_cap <<< "$data"
    echo "$mtp_cap"
}

get_drafter_repo() {
    local key=$1
    if [[ "$key" == "gemma4" ]]; then
        echo "google/gemma-4-26B-A4B-it-assistant"
    else
        echo ""
    fi
}

get_profile_description() {
    local key=$1
    case $key in
        gemma4)          echo "Dense • 27B • Google Gemma 4 (MTP supported)" ;;
        qwen3.6-35b)     echo "MoE • 35B-A3B • Qwen3.6 Hybrid Mamba+MoE" ;;
        qwen3.6-27b)     echo "Dense • 27B • Qwen3.6" ;;
        nemotron)        echo "MoE • Nano Omni • NVIDIA Nemotron 3" ;;
        mistral)         echo "MoE • Medium 3.5 • Mistral AI" ;;
        deepseek)        echo "Dense • V4 • DeepSeek Blackwell Optimized" ;;
        *)               echo "Unknown profile" ;;
    esac
}
