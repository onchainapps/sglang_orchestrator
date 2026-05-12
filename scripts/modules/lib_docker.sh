#!/bin/bash
# =============================================================================
# lib_docker.sh v12.5 - With selectable port
# =============================================================================

docker_launch_model() {
    local profile="$1"
    local mtp="$2"
    local mem_frac="${3:-0.82}"
    local tp="${4:-2}"
    local ctx_len="${5:-262144}"
    local port="${6:-30001}"

    local env_vars
    env_vars=$(get_env_vars "$profile")
    local base_flags
    base_flags=$(get_base_flags "$profile")
    local hf_repo
    hf_repo=$(get_profile_data "$profile" | cut -d'|' -f2)

    echo "🚀 Launching $profile (TP=$tp, mem=$mem_frac, ctx=$ctx_len, port=$port, speculative=$mtp)"

    local full_cmd="docker run --gpus all --rm -it -v $MODELS_DIR:/models -p $port:$port"

    if [ -n "$env_vars" ]; then
        full_cmd="$env_vars $full_cmd"
    fi

    full_cmd="$full_cmd lmsysorg/sglang:latest sglang serve --model-path /models/$hf_repo --tp $tp --mem-fraction-static $mem_frac --context-length $ctx_len --trust-remote-code --host 0.0.0.0 --port $port"

    if [ "$mtp" == "true" ]; then
        full_cmd="$full_cmd $base_flags"
    else
        if [[ "$profile" == qwen* ]]; then
            full_cmd="$full_cmd --reasoning-parser qwen3 --tool-call-parser qwen3_coder"
        else
            full_cmd="$full_cmd --reasoning-parser gemma4 --tool-call-parser gemma4"
        fi
    fi

    echo ""
    echo "Command: $full_cmd"
    echo ""
    eval "$full_cmd"
}
