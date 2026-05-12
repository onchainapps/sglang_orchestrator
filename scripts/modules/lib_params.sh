#!/bin/bash
# =============================================================================
# SGLang Orchestrator - Parameter Library (Updated v11.0 - 2026-05-12)
# =============================================================================
# All Gemma 4 + Qwen3.6 FP8 models with verified SGLang flags
# TP is now choosable at launch time (user can override default)
# =============================================================================

set -uo pipefail

declare -A MODEL_PARAMS

# Format: DOCKER_IMAGE|HF_REPO|PRECISION|MTP_SUPPORTED|DEFAULT_TP|DRAFT_MODEL|ALGO|FULL_FLAGS
# FULL_FLAGS includes all verified --reasoning-parser, --tool-call-parser, speculative params, mamba, mem-fraction, etc.

MODEL_PARAMS["gemma-4-26b-a4b"]="lmsysorg/sglang:cu13-gemma4|google/gemma-4-26B-A4B-it|bfloat16|true|2|google/gemma-4-26B-A4B-it-assistant|NEXTN|--reasoning-parser gemma4 --tool-call-parser gemma4 --speculative-algorithm NEXTN --speculative-num-steps 5 --speculative-num-draft-tokens 6 --speculative-eagle-topk 1 --mem-fraction-static 0.85 --host 0.0.0.0"

MODEL_PARAMS["gemma-4-31b"]="lmsysorg/sglang:cu13-gemma4|google/gemma-4-31B-it|bfloat16|true|2|google/gemma-4-31B-it-assistant|NEXTN|--reasoning-parser gemma4 --tool-call-parser gemma4 --speculative-algorithm NEXTN --speculative-num-steps 5 --speculative-num-draft-tokens 6 --speculative-eagle-topk 1 --mem-fraction-static 0.85 --host 0.0.0.0"

MODEL_PARAMS["qwen-27b-fp8"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-27B-FP8|fp8|true|1||EAGLE|SGLANG_ENABLE_SPEC_V2=1 --reasoning-parser qwen3 --tool-call-parser qwen3_coder --speculative-algorithm EAGLE --speculative-num-steps 3 --speculative-num-draft-tokens 4 --speculative-eagle-topk 1 --mamba-scheduler-strategy extra_buffer --mem-fraction-static 0.82 --host 0.0.0.0"

MODEL_PARAMS["qwen-35b-a3b-fp8"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-35B-A3B-FP8|fp8|true|2||EAGLE|SGLANG_ENABLE_SPEC_V2=1 --reasoning-parser qwen3 --tool-call-parser qwen3_coder --speculative-algorithm EAGLE --speculative-num-steps 3 --speculative-num-draft-tokens 4 --speculative-eagle-topk 1 --mamba-scheduler-strategy extra_buffer --mem-fraction-static 0.78 --host 0.0.0.0"

# ============================================================
# HELPER FUNCTIONS
# ============================================================

get_profile_data() {
    local key=$1
    echo "${MODEL_PARAMS[$key]:-}"
}

get_all_profiles() {
    for key in "${!MODEL_PARAMS[@]}"; do
        echo "$key"
    done
}

get_default_tp() {
    local key=$1
    local data="${MODEL_PARAMS[$key]:-}"
    IFS='|' read -r _ _ _ _ default_tp _ _ _ <<< "$data"
    echo "${default_tp:-2}"
}

get_drafter_repo() {
    local key=$1
    local data="${MODEL_PARAMS[$key]:-}"
    IFS='|' read -r _ _ _ _ _ drafter _ _ <<< "$data"
    echo "$drafter"
}

get_spec_algo() {
    local key=$1
    local data="${MODEL_PARAMS[$key]:-}"
    IFS='|' read -r _ _ _ _ _ _ algo _ <<< "$data"
    echo "$algo"
}

get_full_flags() {
    local key=$1
    local data="${MODEL_PARAMS[$key]:-}"
    IFS='|' read -r _ _ _ _ _ _ _ flags <<< "$data"
    echo "$flags"
}

get_profile_description() {
    local key=$1
    case $key in
        gemma-4-26b-a4b)   echo "Gemma 4 26B-A4B MoE + MTP (NEXTN) • FP8 ready" ;;
        gemma-4-31b)       echo "Gemma 4 31B Dense + MTP (NEXTN)" ;;
        qwen-27b-fp8)      echo "Qwen3.6 27B FP8 + EAGLE + Spec V2 + extra_buffer" ;;
        qwen-35b-a3b-fp8)  echo "Qwen3.6 35B-A3B MoE FP8 + EAGLE + Spec V2" ;;
        *)                 echo "Unknown profile" ;;
    esac
}

# New: Allow user to choose TP at launch (used by orchestrator)
get_tp_for_launch() {
    local key=$1
    local chosen_tp=$2
    local default_tp
    default_tp=$(get_default_tp "$key")

    if [[ -n "$chosen_tp" && "$chosen_tp" =~ ^[0-9]+$ ]]; then
        echo "$chosen_tp"
    else
        echo "$default_tp"
    fi
}
