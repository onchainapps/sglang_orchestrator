#!/bin/bash
# =============================================================================
# lib_params.sh v11.3 - Clean env + flags separation
# =============================================================================

declare -A MODEL_PARAMS

# Format: IMAGE|HF_REPO|DEFAULT_TP|ENV_VARS|DOCKER_FLAGS
MODEL_PARAMS["gemma-4-26b-a4b"]="lmsysorg/sglang:cu13-gemma4|google/gemma-4-26B-A4B-it|2||--reasoning-parser gemma4 --tool-call-parser gemma4 --speculative-algorithm NEXTN --speculative-num-steps 5 --speculative-num-draft-tokens 6 --speculative-eagle-topk 1 --mem-fraction-static 0.85"

MODEL_PARAMS["gemma-4-31b"]="lmsysorg/sglang:cu13-gemma4|google/gemma-4-31B-it|2||--reasoning-parser gemma4 --tool-call-parser gemma4 --speculative-algorithm NEXTN --speculative-num-steps 5 --speculative-num-draft-tokens 6 --speculative-eagle-topk 1 --mem-fraction-static 0.85"

MODEL_PARAMS["qwen-27b-fp8"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-27B-FP8|1|SGLANG_ENABLE_SPEC_V2=1|--reasoning-parser qwen3 --tool-call-parser qwen3_coder --speculative-algorithm EAGLE --speculative-num-steps 3 --speculative-num-draft-tokens 4 --speculative-eagle-topk 1 --mamba-scheduler-strategy extra_buffer --mem-fraction-static 0.82"

MODEL_PARAMS["qwen-35b-a3b-fp8"]="lmsysorg/sglang:latest|Qwen/Qwen3.6-35B-A3B-FP8|2|SGLANG_ENABLE_SPEC_V2=1|--reasoning-parser qwen3 --tool-call-parser qwen3_coder --speculative-algorithm EAGLE --speculative-num-steps 3 --speculative-num-draft-tokens 4 --speculative-eagle-topk 1 --mamba-scheduler-strategy extra_buffer --mem-fraction-static 0.78"

get_profile_data() { echo "${MODEL_PARAMS[$1]:-}"; }
get_all_profiles() { for k in "${!MODEL_PARAMS[@]}"; do echo "$k"; done; }
get_default_tp() { IFS='|' read -r _ _ tp _ _ <<< "${MODEL_PARAMS[$1]}"; echo "$tp"; }
get_env_vars() { IFS='|' read -r _ _ _ env _ <<< "${MODEL_PARAMS[$1]}"; echo "$env"; }
get_docker_flags() { IFS='|' read -r _ _ _ _ flags <<< "${MODEL_PARAMS[$1]}"; echo "$flags"; }
get_profile_description() {
    case $1 in
        gemma-4-26b-a4b) echo "Gemma 4 26B-A4B MoE + MTP (NEXTN)" ;;
        gemma-4-31b) echo "Gemma 4 31B + MTP (NEXTN)" ;;
        qwen-27b-fp8) echo "Qwen3.6 27B FP8 + EAGLE + Spec V2" ;;
        qwen-35b-a3b-fp8) echo "Qwen3.6 35B-A3B MoE FP8 + EAGLE" ;;
    esac
}
get_tp_for_launch() { local d; d=$(get_default_tp "$1"); [[ -n "$2" && "$2" =~ ^[0-9]+$ ]] && echo "$2" || echo "$d"; }
