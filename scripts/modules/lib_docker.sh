#!/bin/bash
# =============================================================================
# lib_docker.sh v12.1 - Use python -m sglang.launch_server (fixes entrypoint error)
# =============================================================================

docker_launch_model() {
    local profile="$1"
    local mtp="$2"
    local mem_frac="${3:-0.82}"
    local tp="${4:-2}"
    local ctx_len="${5:-262144}"

    local env_vars
    env_vars=$(get_env_vars "$profile")
    local base_flags
    base_flags=$(get_base_flags "$profile")
    local model_name
    model_name=$(basename "$(get_profile_data "$profile" | cut -d'|' -f2)")

    echo "🚀 Launching $profile (TP=$tp, mem=$mem_frac, ctx=$ctx_len)"

    local full_cmd="docker run --gpus all --rm -it -v $MODELS_DIR:/models -p 30000:30000"

    if [ -n "$env_vars" ]; then
        full_cmd="$env_vars $full_cmd"
    fi

    full_cmd="$full_cmd lmsysorg/sglang:latest python -m sglang.launch_server --model-path /models/$model_name --tp $tp --mem-fraction-static $mem_frac --context-length $ctx_len --host 0.0.0.0 --port 30000 $base_flags"

    if [ "$mtp" == "true" ]; then
        full_cmd="$full_cmd --speculative-algorithm EAGLE"
    fi

    echo ""
    echo "Command: $full_cmd"
    echo ""
    eval "$full_cmd"
}
