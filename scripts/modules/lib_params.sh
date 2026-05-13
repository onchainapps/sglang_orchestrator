#!/bin/bash
# =============================================================================
# lib_params.sh v12.7 - Full model support (FP8 + BF16)
# =============================================================================

declare -A MODEL_PARAMS

# Format: IMAGE|HF_REPO|DEFAULT_TP|ENV_VARS|BASE_FLAGS
# Qwen3.6 - FP8 versions
MODEL_PARAMS["qwen-27b-fp8"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-27B-FP8|1|SGLANG_ENABLE_SPEC_V2=1|--reasoning-parser qwen3 --tool-call-parser qwen3_coder --speculative-algorithm EAGLE --speculative-num-steps 3 --speculative-num-draft-tokens 4 --speculative-eagle-topk 1 --mamba-scheduler-strategy extra_buffer"
MODEL_PARAMS["qwen-35b-a3b-fp8"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-35B-A3B-FP8|2|SGLANG_ENABLE_SPEC_V2=1|--reasoning-parser qwen3 --tool-call-parser qwen3_coder --speculative-algorithm EAGLE --speculative-num-steps 3 --speculative-num-draft-tokens 4 --speculative-eagle-topk 1 --mamba-scheduler-strategy extra_buffer"

# Qwen3.6 - BF16 versions (separate downloads)
MODEL_PARAMS["qwen-27b-bf16"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-27B|1||--reasoning-parser qwen3 --tool-call-parser qwen3_coder"
MODEL_PARAMS["qwen-35b-a3b-bf16"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-35B-A3B|2||--reasoning-parser qwen3 --tool-call-parser qwen3_coder"

# Gemma 4
MODEL_PARAMS["gemma-4-26b-a4b"]="lmsysorg/sglang:cu13-gemma4|google/gemma-4-26B-A4B-it|2||--reasoning-parser gemma4 --tool-call-parser gemma4 --speculative-algorithm NEXTN --speculative-num-steps 5 --speculative-num-draft-tokens 6 --speculative-eagle-topk 1"
MODEL_PARAMS["gemma-4-31b"]="lmsysorg/sglang:cu13-gemma4|google/gemma-4-31B-it|1||--reasoning-parser gemma4 --tool-call-parser gemma4 --speculative-algorithm NEXTN --speculative-num-steps 3 --speculative-num-draft-tokens 4"

get_profile_data() { echo "${MODEL_PARAMS[$1]:-}"; }
get_all_profiles() { for k in "${!MODEL_PARAMS[@]}"; do echo "$k"; done; }
get_default_tp() { IFS='|' read -r _ _ tp _ _ <<< "${MODEL_PARAMS[$1]}"; echo "$tp"; }
get_env_vars() { IFS='|' read -r _ _ _ env _ <<< "${MODEL_PARAMS[$1]}"; echo "$env"; }
get_base_flags() { IFS='|' read -r _ _ _ _ flags <<< "${MODEL_PARAMS[$1]}"; echo "$flags"; }
get_profile_description() {
    case $1 in
        qwen-27b-fp8)      echo "Qwen3.6 27B FP8 + EAGLE + Spec V2" ;;
        qwen-35b-a3b-fp8)  echo "Qwen3.6 35B-A3B MoE FP8 + EAGLE" ;;
        qwen-27b-bf16)     echo "Qwen3.6 27B BF16 (Dense)" ;;
        qwen-35b-a3b-bf16) echo "Qwen3.6 35B-A3B BF16 (MoE)" ;;
        gemma-4-26b-a4b)   echo "Gemma 4 26B-A4B MoE + MTP (NEXTN)" ;;
        gemma-4-31b)       echo "Gemma 4 31B + MTP (NEXTN)" ;;
    esac
}
get_tp_for_launch() { local d; d=$(get_default_tp "$1"); [[ -n "$2" && "$2" =~ ^[0-9]+$ ]] && echo "$2" || echo "$d"; }
