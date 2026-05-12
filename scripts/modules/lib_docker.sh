#!/bin/bash
# =============================================================================
# lib_docker.sh v11.3 - Clean command builder (no duplicates)
# =============================================================================

set -uo pipefail

docker_launch_model() {
    local profile="$1"
    local mtp="$2"
    local mem_frac="${3:-0.82}"
    local tp="${4:-2}"

    local env_vars
    env_vars=$(get_env_vars "$profile")
    local docker_flags
    docker_flags=$(get_docker_flags "$profile")
    local model_name
    model_name=$(basename "$(get_profile_data "$profile" | cut -d'|' -f2)")

    echo "🚀 Launching $profile (TP=$tp)"

    local env_prefix=""
    [ -n "$env_vars" ] && env_prefix="$env_vars "

    local cmd=(
        docker run --gpus all --rm -it
        -v "$MODELS_DIR:/models"
        -p 30000:30000
        lmsysorg/sglang:latest
        --model-path "/models/$model_name"
        --tp "$tp"
        --mem-fraction-static "$mem_frac"
        --host 0.0.0.0
        --port 30000
    )

    if [ -n "$docker_flags" ]; then
        read -ra f <<< "$docker_flags"
        cmd+=("${f[@]}")
    fi

    if [ "$mtp" == "true" ]; then
        cmd+=(--speculative-algorithm "EAGLE")
    fi

    echo ""
    echo "Command: ${cmd[*]}"
    echo ""
    "${cmd[@]}"
}
