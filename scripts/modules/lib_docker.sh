#!/bin/bash
# =============================================================================
# lib_docker.sh v11.4 - Working string-based version
# =============================================================================

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

    local full_cmd="docker run --gpus all --rm -it -v $MODELS_DIR:/models -p 30000:30000 lmsysorg/sglang:latest --model-path /models/$model_name --tp $tp --mem-fraction-static $mem_frac --host 0.0.0.0 --port 30000"

    if [ -n "$docker_flags" ]; then
        full_cmd="$full_cmd $docker_flags"
    fi

    if [ "$mtp" == "true" ]; then
        full_cmd="$full_cmd --speculative-algorithm EAGLE"
    fi

    if [ -n "$env_vars" ]; then
        full_cmd="$env_vars $full_cmd"
    fi

    echo ""
    echo "Command: $full_cmd"
    echo ""
    eval "$full_cmd"
}
