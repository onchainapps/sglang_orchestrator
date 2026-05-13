#!/bin/bash
# =============================================================================
# lib_docker.sh v12.13 - Default max-running-requests = 2, max-total-tokens = ctx_len
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/lib_params.sh"
source "$MODULE_DIR/lib_models.sh"

docker_show_status() {
    echo ""
    echo "🔍 SGLang Engine Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local containers
    containers=$(docker ps --filter "name=sglang-" --no-trunc --format "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}|{{.RunningFor}}|{{.Command}}" 2>/dev/null)
    
    if [ -z "$containers" ]; then
        echo ""
        echo "  ⚠️  No running SGLang containers found."
        echo ""
    else
        # Header
        printf "  %-30s | %-8s | %-8s | %-8s | %-8s | %-10s | %-30s | %s\n" \
            "NAME" "STATUS" "VRAM" "CPU" "MEM" "UPTIME" "PORT" "PARAMS"
        echo "  ─────────────────────────────────────────────────────────────────────────────────"
        
        echo "$containers" | while IFS='|' read -r cid cname cimage cstatus cports crunning ccmd; do
            # Extract params from command
            local tp mem ctx port pprefill policy chunk piecewise mtp spec fp8
            tp=$(echo "$ccmd" | grep -oP '(?<=--tp )\d+' | head -1)
            mem=$(echo "$ccmd" | grep -oP '(?<=--mem-fraction-static )\d+\.\d+' | head -1)
            ctx=$(echo "$ccmd" | grep -oP '(?<=--context-length )\d+' | head -1)
            port=$(echo "$ccmd" | grep -oP '(?<=--port )\d+' | head -1)
            pprefill=$(echo "$ccmd" | grep -oP '(?<=--chunked-prefill-size )\d+' | head -1)
            policy=$(echo "$ccmd" | grep -oP '(?<=--max-running-requests )\d+' | head -1)
            chunk=$(echo "$ccmd" | grep -oP '(?<=--chunked-prefill-size )\d+' | head -1)
            mtp=$(echo "$ccmd" | grep -qP '(?<=--speculative-algorithm )NEXTN' && echo "MTP" || echo "-")
            spec=$(echo "$ccmd" | grep -qP '(?<=--speculative-algorithm )EAGLE' && echo "EAGLE" || echo "-")
            fp8=$(echo "$ccmd" | grep -qP '(?<=--quantization )fp8' && echo "FP8" || echo "-")
            piecewise=$(echo "$ccmd" | grep -qP '--enable-piecewise-cuda-graph' && echo "PW" || echo "-")
            
            # Get GPU VRAM usage from nvidia-smi inside container
            local vram_usage="N/A"
            if docker exec "$cname" nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | grep -q .; then
                vram_usage=$(docker exec "$cname" nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
            fi
            
            # Get container CPU/MEM stats
            local cpu_pct mem_mb
            cpu_pct=$(docker stats --no-stream --format "{{.CPUPerc}}" "$cname" 2>/dev/null | tr -d '% ')
            mem_mb=$(docker stats --no-stream --format "{{.MemUsage}}" "$cname" 2>/dev/null | cut -d'/' -f1 | tr -d ' ')
            
            # Format uptime
            local uptime_str="$crunning"
            [ ${#uptime_str} -gt 10 ] && uptime_str="${uptime_str:0:10}..."
            
            # Build param string
            local params=""
            params="TP=$tp mem=${mem:-0.82} ctx=${ctx:-131k}"
            [ "$policy" != "" ] && params="$params reqs=$policy"
            [ "$chunk" != "" ] && params="$params chunk=$chunk"
            [ "$piecewise" != "-" ] && params="$params $piecewise"
            [ "$mtp" != "-" ] && params="$params MTP"
            [ "$spec" != "-" ] && params="$params $spec"
            [ "$fp8" != "-" ] && params="$params $fp8"
            
            # Truncate name if needed
            [ ${#cname} -gt 30 ] && cname="${cname:0:27}..."
            
            printf "  %-30s | %-8s | %-8sMiB | %-8s%% | %-8s | %-10s | %s | %s\n" \
                "$cname" "$cstatus" "${vram_usage:-0}" "${cpu_pct:-0}" "${mem_mb:-0}" "$uptime_str" "$port" "$params"
        done
        
        echo ""
        
        # Try to get live metrics from the API (first running container)
        echo "📊 Live API Metrics:"
        echo "  ─────────────────────────────────────────────────────────────────────────────────"
        local first_port
        first_port=$(echo "$containers" | head -1 | tr '|' '\n' | grep '\-\>' | grep -oP '0\.0\.0\.0:\K\d+' | head -1)
        if [ -n "$first_port" ]; then
            local model_info
            model_info=$(curl -s --connect-timeout 2 "http://localhost:${first_port}/model_info" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$model_info" ] && echo "$model_info" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'model_path' in d else 1)" 2>/dev/null; then
                local model_path vram_total
                model_path=$(echo "$model_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('model_path','N/A'))" 2>/dev/null)
                vram_total=$(echo "$model_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mem_usage_max_bytes','0') // (1024**2))" 2>/dev/null)
                echo "  Model: $model_path"
                echo "  Peak VRAM: ${vram_total:-0} MiB"
            else
                echo "  ⚠️  API not responding on port $first_port"
            fi
        fi
        echo "  ─────────────────────────────────────────────────────────────────────────────────"
    fi
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
    local reqs="${8:-2}"
    local pg_size="${9:-16}"

    # --- Profile-specific safety overrides (covers both MTP & non-MTP paths) ---
    if [[ "$profile" == "gemma-4-31b" ]]; then
        mem_frac=${mem_frac:-0.78}
        ctx_len=${ctx_len:-32768}
        tp=${tp:-1}
    fi

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

    # Added --cap-add SYS_NICE to fix NUMA affinity warnings
    local full_cmd="docker run -d --name $container_name --gpus all --cap-add SYS_NICE --rm -v $MODELS_DIR:/models -p $port:$port"

    if [ -n "$env_vars" ]; then
        full_cmd="$env_vars $full_cmd"
    fi

    # RTX 6000 Ada (96GB) budget:
    # --mem-fraction-static: 0.85 for FP8/MoE (safe), 0.80 for BF16 dense
    # Radix cache + CUDA graph enabled by default (keep enabled)
    # max-running-requests: 2 for single-user coding sessions
    # max-total-tokens: MUST equal ctx_len — old bug set it to ctx_len/2
    # --allow-auto-truncate: safety net if context overflows
    # --- TURBO MODE FOR QWEN 35B ---
    local chunk_size=8192
    local piecewise_graph="--disable-piecewise-cuda-graph"
    if [[ "$profile" == "qwen-35b-a3b-bf16" ]]; then
        chunk_size=16384
        piecewise_graph="--enable-piecewise-cuda-graph"
    fi

    full_cmd="$full_cmd $image sglang serve --model-path /models/$hf_repo --tp $tp --mem-fraction-static $mem_frac --context-length $ctx_len --max-running-requests $reqs --max-total-tokens $ctx_len --chunked-prefill-size $chunk_size --max-prefill-tokens 16384 --allow-auto-truncate --schedule-policy lpm --trust-remote-code --host 0.0.0.0 --port $port $piecewise_graph --page-size $pg_size"

    # SGLang API key authentication
    if [ -n "${API_KEY:-}" ]; then
        full_cmd="$full_cmd --api-key $API_KEY"
    fi
    if [ -n "${ADMIN_API_KEY:-}" ]; then
        full_cmd="$full_cmd --admin-api-key $ADMIN_API_KEY"
    fi

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
