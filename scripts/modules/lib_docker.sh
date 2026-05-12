#!/bin/bash
# =============================================================================
# lib_docker.sh v12.11 - Final clean version with status function
# =============================================================================

docker_show_status() {
    echo ""
    echo "=== Running SGLang Containers ==="
    docker ps --filter "name=sglang-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
}

docker_launch_model() {
    local profile="$1"
    local mtp="$2"
    local mem_frac="${3:-0.82}"
    local tp="${4:-2}"
    local ctx_len="${5:-262144}"
    local port="${6:-30001}"
    local use_fp8="${7:-false}"

    local env_vars
    env_vars=$(get_env_vars "$profile")
    local base_flags
    base_flags=$(get_base_flags "$profile")
    local hf_repo
    hf_repo=$(get_profile_data "$profile" | cut -d'|' -f2)

    local local_path="$MODELS_DIR/$hf_repo"

    # === AUTO DETECTION ===
    if [ ! -d "$local_path" ]; then
        echo ""
        echo "❌ Model not found locally: $local_path"
        echo ""
        read -p "Would you like to download it now? (y/n): " dl
        if [[ "$dl" == "y" ]]; then
            bash "$SCRIPT_DIR/intelligence.sh" --download "$hf_repo"
            echo ""
            read -p "Press Enter after download finishes to continue..."
        else
            echo "Returning to menu..."
            return
        fi
    fi

    local container_name="sglang-$(echo $profile | tr '[:upper:]' '[:lower:]' | tr -d '-')"

    echo ""
    echo "🚀 Launching $profile in background (TP=$tp, port=$port)"
    echo "Container name: $container_name"

    local full_cmd="docker run -d --name $container_name --gpus all --rm -v $MODELS_DIR:/models -p $port:$port"

    if [ -n "$env_vars" ]; then
        full_cmd="$env_vars $full_cmd"
    fi

    full_cmd="$full_cmd lmsysorg/sglang:latest sglang serve --model-path /models/$hf_repo --tp $tp --mem-fraction-static $mem_frac --context-length $ctx_len --trust-remote-code --host 0.0.0.0 --port $port"

    if [ "$use_fp8" == "true" ]; then
        full_cmd="$full_cmd --quantization fp8"
    fi

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
    echo "Starting container..."
    eval "$full_cmd"

    echo ""
    echo "✅ Container started in background!"
    echo "   Name: $container_name"
    echo "   Port: $port"
    echo ""
    echo "To view logs:    docker logs -f $container_name"
    echo "To stop:         docker stop $container_name"
    echo ""
    read -p "Press Enter to return to menu..."
}
