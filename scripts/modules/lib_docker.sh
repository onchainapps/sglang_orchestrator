#!/bin/bash
# =============================================================================
# lib_docker.sh v12.13 - Default max-running-requests = 16
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/lib_params.sh"
source "$MODULE_DIR/lib_models.sh"

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
    local ctx_len="${5:-131072}"
    local port="${6:-30001}"
    local use_fp8="${7:-false}"

    local env_vars
    env_vars=$(get_env_vars "$profile")
    local base_flags
    base_flags=$(get_base_flags "$profile")
    local hf_repo
    hf_repo=$(get_profile_data "$profile" | cut -d'|' -f2)

    local local_path="$MODELS_DIR/$hf_repo"

    if [ ! -d "$local_path" ]; then
        echo ""
        echo "❌ Model not found locally: $local_path"
        read -p "Download it now? (y/n): " dl
        if [[ "$dl" == "y" ]]; then
            download_model "$hf_repo"
            read -p "Press Enter after download..."
        else
            return
        fi
    fi

    # Check for running containers
    local running_containers
    running_containers=$(docker ps --filter "name=sglang-" --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null)
    if [ -n "$running_containers" ]; then
        echo ""
        echo "⚠️  SGLang container(s) already running:"
        echo "------------------------------------------------------------"
        printf "%-35s | %-20s | %s\n" "NAME" "STATUS" "PORTS"
        echo "------------------------------------------------------------"
        echo "$running_containers" | while IFS=$'\t' read -r name status ports; do
            printf "%-35s | %-20s | %s\n" "$name" "$status" "$ports"
        done
        echo "------------------------------------------------------------"
        read -p "Stop running container(s) and proceed? (y/n): " stop_existing
        if [[ "$stop_existing" != "y" ]]; then
            echo "Launch cancelled."
            return 1
        fi
        echo ""
        echo "Stopping existing containers..."
        docker stop $(docker ps --filter "name=sglang-" -q) 2>/dev/null
        docker rm $(docker ps -a --filter "name=sglang-" -q) 2>/dev/null
        echo "Existing containers stopped."
    fi

    local image="lmsysorg/sglang:latest"
    if [[ "$profile" == gemma* ]]; then
        image="lmsysorg/sglang:cu13-gemma4"
    fi

    local suffix=""
    if [[ "$mtp" == "true" ]]; then
        suffix="-mtp"
    fi
    local container_name="sglang-$(echo $profile | tr '[:upper:]' '[:lower:]' | tr -d '-')${suffix}"

    echo ""
    echo "🚀 Launching $profile in background (TP=$tp, port=$port)"

    local full_cmd="docker run -d --name $container_name --gpus all --rm -v $MODELS_DIR:/models -p $port:$port"

    if [ -n "$env_vars" ]; then
        full_cmd="$env_vars $full_cmd"
    fi

    # Unified launch flags — must match VENV path
    full_cmd="$full_cmd $image sglang serve --model-path /models/$hf_repo --tp $tp --mem-fraction-static $mem_frac --context-length $ctx_len --max-running-requests 16 --max-total-tokens 131072 --chunked-prefill-size 8192 --allow-auto-truncate --trust-remote-code --host 0.0.0.0 --port $port --schedule-policy lru"

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
    echo "✅ Started: $container_name on port $port"
    echo "   Logs: docker logs -f $container_name"
    echo "   Stop: docker stop $container_name"
    echo ""
    read -p "Press Enter to return to menu..."
}
