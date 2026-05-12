#!/bin/bash
# =============================================================================
# SGLang Orchestrator - Parameter Library (lib_params.sh) v2.0 (FIXED)
# =============================================================================
# SINGLE SOURCE OF TRUTH for all model launch configurations.
# =============================================================================

set -uo pipefail

# --- DATA STRUCTURE ---
# Format: PROFILE_KEY|DOCKER_IMG|HF_BASE_REPO|PRECISION|MTP_CAP|DRAFTER_REPO|ALGO|SPECIAL_ARGS
# MTP_CAP: true/false
# DRAFTER_REPO: HF repo for speculative/assistant model (if MTP enabled)
# ALGO: Speculative algorithm (NEXTN, DraftModel, etc.)

declare -A MODEL_PARAMS

# 1. Gemma 4 (Full MTP Support)
MODEL_PARAMS["gemma4"]="lmsysorg/sglang:cu13-gemma4|google/gemma-4-27b|bfloat16|true|google/gemma-4-26B-A4B-it-assistant|NEXTN|--reasoning-parser gemma4 --tool-call-parser gemma4"

# 2. Qwen 3.6 Series (Mamba Scheduler Support)
MODEL_PARAMS["qwen3.6-35b"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-35B-MoE|bfloat16|false|||--mamba-scheduler-strategy extra_buffer"
MODEL_PARAMS["qwen3.6-27b"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-27B|bfloat16|false|||--mamba-scheduler-strategy extra_buffer"

# 3. NVIDIA Nemotron (Specialized Kernels)
MODEL_PARAMS["nemotron"]="lmsysorg/sglang:dev-cu13-nemotronh-nano-omni-reasoning-v3|nvidia/nemotron-nano-omni|bfloat16|false|||"

# 4. Mistral (Specialized Kernels)
MODEL_PARAMS["mistral"]="lmsysorg/sglang:dev-cu13-mistral-medium-3.5|mistralai/Mistral-Medium-3.5|bfloat16|false|||"

# 5. DeepSeek (Blackwell Optimized)
MODEL_PARAMS["deepseek"]="lmsysorg/sglang:deepseek-v4-blackwell|deepseek-ai/DeepSeek-V4|bfloat16|false|||"

# --- API FUNCTIONS ---

get_profile_data() {
    local key=$1
    if [[ -z "${MODEL_PARAMS[$key]:-}" ]]; then
        return 1
    fi
    echo "${MODEL_PARAMS[$key]}"
}

get_all_profiles() {
    for key in "${!MODEL_PARAMS[@]}"; do
        echo "$key"
    done
}

get_mtp_capability() {
    local key=$1
    local data="${MODEL_PARAMS[$key]:-}"
    IFS='|' read -r _ _ _ _ mtp_cap _ _ <<< "$data"
    echo "$mtp_cap"
}

get_drafter_repo() {
    local key=$1
    local data="${MODEL_PARAMS[$key]:-}"
    IFS='|' read -r _ _ _ _ _ drafter _ <<< "$data"
    echo "$drafter"
}

get_spec_algo() {
    local key=$1
    local data="${MODEL_PARAMS[$key]:-}"
    IFS='|' read -r _ _ _ _ _ _ algo _ <<< "$data"
    echo "$algo"
}

get_special_args() {
    local key=$1
    local data="${MODEL_PARAMS[$key]:-}"
    IFS='|' read -r _ _ _ _ _ _ _ spec_args <<< "$data"
    echo "$spec_args"
}
