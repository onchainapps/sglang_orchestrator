#!/bin/bash
# =============================================================================
# lib_docker.sh v12.14 - Blackwell optimized (reqs=8, ctx=128000, mem=0.85)
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

# =============================================================================
# DOCKER IMAGE UPDATE CHECK
# =============================================================================
check_docker_updates() {
    echo ""
    echo "🔍 Checking for Docker image updates..."
    echo "─────────────────────────────────────────────────────────────────────"

    # Get local images
    local local_images
    local_images=$(docker images lmsysorg/sglang --format "{{.Repository}}:{{.Tag}} - ID: {{.ID}} - Size: {{.Size}}" 2>/dev/null)
    if [ -z "$local_images" ]; then
        echo "  ⚠️  No local SGLang images found."
    else
        echo "📦 Local Images:"
        echo "$local_images" | while read -r line; do
            echo "  $line"
        done
    fi
    echo ""

    # Get Docker Hub latest
    echo "🌐 Docker Hub (lmsysorg/sglang:latest):"
    local hub_info
    hub_info=$(curl -s "https://hub.docker.com/v2/repositories/lmsysorg/sglang/tags/latest" 2>/dev/null)
    if [ -z "$hub_info" ]; then
        echo "  ❌ Failed to fetch Docker Hub info."
        return
    fi

    local hub_digest hub_size
    hub_digest=$(echo "$hub_info" | jq -r '.digest // "N/A"' 2>/dev/null)
    hub_size=$(echo "$hub_info" | jq -r '(.full_size / 1000000000 | floor) + "GB"' 2>/dev/null)
    echo "  Digest: ${hub_digest}"
    echo "  Size: ${hub_size}"
    echo ""

    # Get latest GitHub release
    echo "📋 GitHub Releases (sgl-project/sglang):"
    local releases
    releases=$(curl -s "https://api.github.com/repos/sgl-project/sglang/releases?per_page=3" 2>/dev/null)
    if [ -z "$releases" ]; then
        echo "  ❌ Failed to fetch GitHub releases."
    else
        echo "$releases" | jq -r '.[:3][] | "  \(.tag_name) - \(.published_at[0:10])"' 2>/dev/null
    fi
    echo ""

    # Compare local vs remote for latest tag
    local local_latest_id
    local_latest_id=$(docker images lmsysorg/sglang:latest --format "{{.ID}}" 2>/dev/null | head -1)
    if [ -n "$local_latest_id" ]; then
        echo "✅ Comparison:"
        echo "  Local latest ID: ${local_latest_id:0:12}"
        echo "  Remote digest:   ${hub_digest:0:35}"
        echo ""
        echo "💡 To pull latest updates:"
        echo "  docker pull lmsysorg/sglang:latest"
        echo ""
        echo "⚠️  Note: Pulling may update the base image. Test before restarting production containers."
    else
        echo "💡 No local 'latest' tag found. Pull with:"
        echo "  docker pull lmsysorg/sglang:latest"
    fi
    echo ""
}

docker_launch_model() {
    local profile="$1"
    local mtp="$2"
    local power_mode="${3:-conservative}"  # New: power or conservative
    local mem_frac="${4:-0.85}"
    local tp="${5:-1}"
    local ctx_len="${6:-128000}"
    local port="${7:-30001}"
    local reqs="${8:-8}"

    # Apply power profile defaults if not explicitly set
    if [[ "$power_mode" == "power" ]]; then
        mem_frac=${mem_frac:-$POWER_MEM_FRAC}
        reqs=${reqs:-$POWER_REQS}
        local conservativeness=$POWER_CONSERVATIVENESS
        local chunk_prefill=$POWER_CHUNK_PREFILL
        local max_prefill=$POWER_MAX_PREFILL
    else
        mem_frac=${mem_frac:-$CONSERVATIVE_MEM_FRAC}
        reqs=${reqs:-$CONSERVATIVE_REQS}
        local conservativeness=$CONSERVATIVE_CONSERVATIVENESS
        local chunk_prefill=$CONSERVATIVE_CHUNK_PREFILL
        local max_prefill=$CONSERVATIVE_MAX_PREFILL
    fi

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

    # For custom/detected models, use CUSTOM_MODEL_REPO if set
    if [ -z "$hf_repo" ] && [ -n "${CUSTOM_MODEL_REPO:-}" ]; then
        hf_repo="$CUSTOM_MODEL_REPO"
    fi

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

    local suffix=""
    if [[ "$mtp" == "true" ]]; then
        suffix="-mtp"
    fi
    local container_name="sglang-$(echo $profile | tr '[:upper:]' '[:lower:]' | tr -d '-')${suffix}"

    echo ""
    echo "🚀 Launching $profile in background (TP=$tp, port=$port)"

    # Added --cap-add SYS_NICE to fix NUMA affinity warnings
    # Auto-mount kernel tuning configs if they exist (search orchestrator kernel_configs/)
    local kernel_config_vol=""
    local kernel_config_base="$(dirname "$(dirname "$SCRIPT_DIR")")/kernel_configs"
    if [ -d "$kernel_config_base" ]; then
        # Check for flat JSON configs in kernel_configs/ (tuning script saves them flat)
        local json_count
        json_count=$(find "$kernel_config_base" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l)
        if [ "$json_count" -gt 0 ]; then
            kernel_config_vol="-v $kernel_config_base:/sgl-workspace/sglang/python/sglang/srt/layers/quantization/configs"
        fi
    fi
    local full_cmd="docker run -d --name $container_name --restart unless-stopped --gpus all --cap-add SYS_NICE -v $MODELS_DIR:/models $kernel_config_vol -p $port:$port"

    if [ -n "$env_vars" ]; then
        full_cmd="$env_vars $full_cmd"
    fi

    # RTX 6000 Blackwell (96GB) budget:
    # --mem-fraction-static: 0.90 default (aggressive, ~15GB headroom available)
    # Radix cache + CUDA graph enabled by default
    # max-running-requests: 16 for multi-user team scenarios (aggressive)
    # max-total-tokens: MUST equal ctx_len
    # --allow-auto-truncate: safety net if context overflows
    # NOTE: --enable-piecewise-cuda-graph is deprecated in current SGLang, removed 2026-05-13
    local chunk_size=8192
    if [[ "$power_mode" == "power" ]]; then
        chunk_size=$POWER_CHUNK_PREFILL
    elif [[ "$profile" == "qwen-35b-a3b-bf16" || "$profile" == "qwen-27b-fp8" ]]; then
        chunk_size=$CONSERVATIVE_CHUNK_PREFILL
    fi

    full_cmd="$full_cmd $image sglang serve --model-path /models/$hf_repo --tp $tp --mem-fraction-static $mem_frac --context-length $ctx_len --max-running-requests $reqs --max-queued-requests 8 --max-total-tokens $ctx_len --chunked-prefill-size $chunk_size --max-prefill-tokens $max_prefill --allow-auto-truncate --schedule-policy lpm --schedule-conservativeness $conservativeness --watchdog-timeout 120 --trust-remote-code --host 0.0.0.0 --port $port --enable-hierarchical-cache --hicache-ratio 2 --kv-cache-dtype fp8_e4m3"

    # SGLang API key authentication
    if [ -n "${API_KEY:-}" ]; then
        full_cmd="$full_cmd --api-key $API_KEY"
    fi
    if [ -n "${ADMIN_API_KEY:-}" ]; then
        full_cmd="$full_cmd --admin-api-key $ADMIN_API_KEY"
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

# =============================================================================
# KERNEL TUNING - Auto-tune FP8 Triton kernels for Blackwell (and other GPUs)
# =============================================================================
tune_kernels() {
    # Find running container
    local running
    running=$(docker ps --filter "name=sglang-" --format "{{.Names}}" 2>/dev/null | head -1)
    if [ -z "$running" ]; then
        echo ""
        echo "❌ No running SGLang container found. Launch one first."
        read -p "Press Enter to return to menu..."
        return
    fi

    echo ""
    echo "🔧 Kernel Tuning for container: $running"
    echo "   This will auto-tune Triton FP8 kernels for your GPU."
    echo "   Takes ~60-90 min per shape (benchmarks every config)."
    echo "   Results are saved to sglang_orchestrator/kernel_configs/ (git-tracked)."
    echo ""
    echo "⚠️  IMPORTANT: Tuning requires GPU memory. The SGLang server will be stopped"
    echo "   temporarily during tuning and restarted afterward."
    read -p "Continue? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Cancelled."
        read -p "Press Enter to return to menu..."
        return
    fi

    # Get container info before stopping
    local container_image
    container_image=$(docker inspect "$running" --format '{{.Config.Image}}' 2>/dev/null)
    local container_mounts
    container_mounts=$(docker inspect "$running" --format '{{json .Mounts}}' 2>/dev/null)
    local container_env
    container_env=$(docker inspect "$running" --format '{{json .Config.Env}}' 2>/dev/null)
    local container_cmd
    container_cmd=$(docker inspect "$running" --format '{{json .Config.Cmd}}' 2>/dev/null)

    # Stop the SGLang container to free GPU memory
    echo ""
    echo "🛑 Stopping SGLang container: $running"
    docker stop "$running" 2>&1
    sleep 3
    echo "✅ Container stopped."

    # Setup cleanup trap: ensure original container restarts even on error/interrupt
    local temp_container=""
    cleanup() {
        if [ -n "$temp_container" ]; then
            echo "🧹 Cleaning up temporary container..."
            docker stop "$temp_container" 2>/dev/null
            docker rm "$temp_container" 2>/dev/null
        fi
        if docker inspect "$running" --format '{{.State.Running}}' 2>/dev/null | grep -q "false"; then
            echo "⚠️  Original container was not running. Restarting..."
            docker start "$running" 2>&1
        fi
    }
    trap cleanup EXIT

    # Get the model path from the container's command
    local actual_model_path
    actual_model_path=$(echo "$container_cmd" | grep -oP '(?<=--model-path )[^ ]+' || true)
    actual_model_path="${actual_model_path:-/models}"

    # Detect device and model for config subdirectory naming
    local device_name
    device_name=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -1 | sed 's/ /_/g; s/-/_/g')
    local device_slug="${device_name:-unknown_gpu}"

    local config_dir="$(dirname "$(dirname "$SCRIPT_DIR")")/kernel_configs"
    mkdir -p "$config_dir"

    # Start a temporary container for detection and tuning (no model loaded = free GPU memory)
    echo ""
    echo "🔬 Starting temporary container for tuning..."
    temp_container="sglang-tune-$$"
    
    # Build docker run command for temp container
    local docker_run="docker run -d --name $temp_container --gpus all"
    docker_run+=" -v $MODELS_DIR:/models:ro"
    docker_run+=" -v $SCRIPT_DIR/../kernel_configs:/sgl-workspace/sglang/python/sglang/srt/layers/quantization/configs:rw"
    docker_run+=" -w /sgl-workspace/sglang"
    docker_run+=" $container_image"
    docker_run+=" sleep 3600"  # Keep running for 1 hour
    
    eval "$docker_run" 2>&1
    sleep 5
    
    # Verify temp container is running
    if ! docker ps --filter "name=$temp_container" --format "{{.Names}}" | grep -q "$temp_container"; then
        echo "❌ Failed to start temporary container."
        echo "   Starting original container..."
        docker start "$running" 2>&1
        read -p "Press Enter to return to menu..."
        return 1
    fi
    
    echo "✅ Temporary container started."

    # Step 1: Detect model architecture
    echo ""
    echo "📐 Step 1/3: Detecting model architecture..."
    echo "   Model path: $actual_model_path"
    
    local arch_output
    arch_output=$(docker exec "$temp_container" python3 -c "
from transformers import AutoConfig
import json
config = AutoConfig.from_pretrained('$actual_model_path', trust_remote_code=True)
tc = getattr(config, 'text_config', config)
mtp_layers = getattr(tc, 'mtp_num_hidden_layers', 0)
mtp_intermediate = getattr(tc, 'mtp_intermediate_size', None)
mtp_heads = getattr(tc, 'mtp_num_attention_heads', None)
mtp_kv_heads = getattr(tc, 'mtp_num_key_value_heads', None)
mtp_head_dim = getattr(tc, 'mtp_head_dim', None)
if mtp_heads is None:
    mtp_heads = getattr(tc, 'linear_num_key_heads', 0) + getattr(tc, 'linear_num_value_heads', 0)
    if mtp_heads == 0:
        mtp_heads = tc.num_attention_heads
if mtp_intermediate is None and mtp_heads > 0:
    mtp_intermediate = int(mtp_heads * tc.head_dim * 7 // 16)
if mtp_kv_heads is None:
    mtp_kv_heads = mtp_heads // 8
if mtp_head_dim is None:
    mtp_head_dim = tc.head_dim
print(json.dumps({
    'hidden_size': tc.hidden_size,
    'intermediate_size': tc.intermediate_size,
    'num_attention_heads': tc.num_attention_heads,
    'num_key_value_heads': getattr(tc, 'num_key_value_heads', None),
    'head_dim': tc.head_dim,
    'mtp_layers': mtp_layers,
    'mtp_intermediate_size': mtp_intermediate,
    'mtp_num_attention_heads': mtp_heads,
    'mtp_num_key_value_heads': mtp_kv_heads,
    'mtp_head_dim': mtp_head_dim,
}))
" 2>&1)
    
    local parse_err
    parse_err=$(echo "$arch_output" | grep -i "error\|exception\|traceback" || true)
    local hidden_size=5120 intermediate_size=17408 num_heads=24 num_kv_heads=4 head_dim=256
    local mtp_layers=1 mtp_intermediate_size=17408 mtp_heads=24 mtp_kv_heads=16 mtp_head_dim=256
    
    if [ -z "$parse_err" ]; then
        hidden_size=$(echo "$arch_output" | python3 -c "import sys,json; print(json.load(sys.stdin)['hidden_size'])" 2>/dev/null)
        intermediate_size=$(echo "$arch_output" | python3 -c "import sys,json; print(json.load(sys.stdin)['intermediate_size'])" 2>/dev/null)
        num_heads=$(echo "$arch_output" | python3 -c "import sys,json; print(json.load(sys.stdin)['num_attention_heads'])" 2>/dev/null)
        num_kv_heads=$(echo "$arch_output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['num_key_value_heads'] or '')" 2>/dev/null)
        head_dim=$(echo "$arch_output" | python3 -c "import sys,json; print(json.load(sys.stdin)['head_dim'])" 2>/dev/null)
        mtp_layers=$(echo "$arch_output" | python3 -c "import sys,json; print(json.load(sys.stdin)['mtp_layers'])" 2>/dev/null)
        mtp_intermediate_size=$(echo "$arch_output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['mtp_intermediate_size'] or '')" 2>/dev/null)
        mtp_heads=$(echo "$arch_output" | python3 -c "import sys,json; print(json.load(sys.stdin)['mtp_num_attention_heads'])" 2>/dev/null)
        mtp_kv_heads=$(echo "$arch_output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['mtp_num_key_value_heads'] or '')" 2>/dev/null)
        mtp_head_dim=$(echo "$arch_output" | python3 -c "import sys,json; print(json.load(sys.stdin)['mtp_head_dim'])" 2>/dev/null)
    else
        echo "⚠️  Could not auto-detect architecture. Using defaults."
    fi
    [ -z "$num_kv_heads" ] || [ "$num_kv_heads" = "" ] && num_kv_heads=$num_heads

    echo "   hidden_size: $hidden_size"
    echo "   intermediate_size: $intermediate_size"
    echo "   num_heads: $num_heads"
    echo "   num_kv_heads: $num_kv_heads"
    echo "   head_dim: $head_dim"
    [ "$mtp_layers" -gt 0 ] 2>/dev/null && {
        echo "   MTP layers: $mtp_layers"
        echo "   MTP intermediate_size: $mtp_intermediate_size"
        echo "   MTP num_heads: $mtp_heads"
        echo "   MTP num_kv_heads: $mtp_kv_heads"
        echo "   MTP head_dim: $mtp_head_dim"
    }

    # Step 2: Compute weight shapes and tune each
    echo ""
    echo "🔧 Step 2/3: Running kernel autotuner..."

    local qkv_out=$((num_heads * head_dim + 2 * num_kv_heads * head_dim))
    local mlp_gate_up=$((2 * intermediate_size))
    local o_proj_in=$((num_heads * head_dim))

    local -a shapes=()
    shapes+=("$qkv_out,$hidden_size")
    shapes+=("$mlp_gate_up,$hidden_size")
    shapes+=("$hidden_size,$intermediate_size")
    shapes+=("$hidden_size,$o_proj_in")
    shapes+=("$hidden_size,$hidden_size")

    # MTP shapes
    if [ "$mtp_layers" -gt 0 ] 2>/dev/null && [ -n "$mtp_intermediate_size" ] && [ "$mtp_intermediate_size" != "" ]; then
        local mtp_q_out=$((mtp_heads * mtp_head_dim))
        local mtp_kv_out=$((2 * mtp_kv_heads * mtp_head_dim))
        local mtp_mlp_gate_up=$((2 * mtp_intermediate_size))
        local mtp_o_proj_in=$((mtp_heads * mtp_head_dim))

        shapes+=("$mtp_q_out,$hidden_size")
        shapes+=("$mtp_kv_out,$hidden_size")
        shapes+=("$mtp_mlp_gate_up,$hidden_size")
        shapes+=("$hidden_size,$mtp_intermediate_size")
        shapes+=("$hidden_size,$mtp_o_proj_in")
        echo "   MTP Q: N=$mtp_q_out, K=$hidden_size"
        echo "   MTP KV: N=$mtp_kv_out, K=$hidden_size"
        echo "   MTP MLP: N=$mtp_mlp_gate_up, K=$hidden_size"
    fi

    # Remove duplicates
    local -a unique_shapes=()
    for shape in "${shapes[@]}"; do
        local found=0
        for unique in "${unique_shapes[@]+${unique_shapes[@]}}"; do
            [ "$shape" = "$unique" ] && { found=1; break; }
        done
        [ $found -eq 0 ] && unique_shapes+=("$shape")
    done

    # Detect MoE shapes
    echo ""
    echo "🔍 Step 1.5/3: Detecting MoE architecture..."
    local moe_output
    moe_output=$(docker exec "$temp_container" python3 -c "
from transformers import AutoConfig
config = AutoConfig.from_pretrained('$actual_model_path', trust_remote_code=True)
tc = getattr(config, 'text_config', config)
num_experts = getattr(tc, 'num_experts', 0)
num_experts_per_tok = getattr(tc, 'num_experts_per_tok', 0)
if num_experts_per_tok == 0:
    num_experts_per_tok = getattr(tc, 'top_k', 1)
expert_intermediate_size = getattr(tc, 'moe_intermediate_size', None)
if expert_intermediate_size is None:
    expert_intermediate_size = getattr(tc, 'intermediate_size', None)
router_dim = getattr(tc, 'moe_router_dim', None)
if router_dim is None:
    router_dim = getattr(tc, 'hidden_size', None)
print(f'{num_experts}|{num_experts_per_tok}|{expert_intermediate_size}|{router_dim}')
" 2>&1)
    
    local num_experts=0 num_experts_per_tok=1 expert_intermediate_size="" router_dim=""
    IFS='|' read -r num_experts num_experts_per_tok expert_intermediate_size router_dim <<< "$moe_output"
    
    if [ -n "$num_experts" ] && [ "$num_experts" -gt 1 ] 2>/dev/null; then
        echo "   MoE: $num_experts experts, $num_experts_per_tok per token"
        echo "   Expert intermediate: $expert_intermediate_size, Router dim: $router_dim"
        
        local gate_n="${num_experts}"
        local gate_k="${router_dim:-$hidden_size}"
        unique_shapes+=("${gate_n},${gate_k}")
        echo "   Adding MoE gate: N=$gate_n, K=$gate_k"
        
        if [ -n "$expert_intermediate_size" ] && [ "$expert_intermediate_size" != "None" ]; then
            unique_shapes+=("${expert_intermediate_size},${hidden_size}")
            echo "   Adding MoE expert up: N=$expert_intermediate_size, K=$hidden_size"
            unique_shapes+=("${hidden_size},${expert_intermediate_size}")
            echo "   Adding MoE expert down: N=$hidden_size, K=$expert_intermediate_size"
        fi
    else
        echo "   No MoE layers detected (dense model)"
    fi

    local shapes_tuned=0
    local root_kernel_dir="$(cd "$(dirname "$(dirname "$SCRIPT_DIR")")/kernel_configs" && pwd)"
    
    for shape in "${unique_shapes[@]}"; do
        local n="${shape%%,*}"
        local k="${shape##*,}"

        # Skip if config already exists
        if find "$root_kernel_dir" -maxdepth 1 -name "N=${n},K=${k},*.json" -type f 2>/dev/null | head -1 | grep -q .; then
            echo "   Skipping N=$n, K=$k (config exists)"
            continue
        fi

        shapes_tuned=$((shapes_tuned + 1))
        echo "   Tuning N=$n, K=$k..."
        docker exec "$temp_container" python3 benchmark/kernels/quantization/tuning_block_wise_kernel.py \
            --N "$n" --K "$k" --input-type fp8 \
            --save-path python/sglang/srt/layers/quantization/configs 2>&1 | tail -3
        echo ""
    done

    if [ "$shapes_tuned" -eq 0 ]; then
        echo ""
        echo "✅ All weight shapes already tuned — no new configs needed."
        # Clean up temp container
        docker stop "$temp_container" 2>/dev/null
        docker rm "$temp_container" 2>/dev/null
        # Restart original container
        echo "🔄 Restarting SGLang container: $running"
        docker start "$running" 2>&1
        echo "✅ Done."
        read -p "Press Enter to return to menu..."
        return 0
    fi

    # Step 3: Copy configs back to host
    echo ""
    echo "💾 Step 3/3: Saving tuned configs to host..."
    local tmp_cp=$(mktemp -d)
    docker cp "$temp_container:/sgl-workspace/sglang/python/sglang/srt/layers/quantization/configs/" \
        "$tmp_cp/" 2>&1
    if [ -d "$tmp_cp/configs" ]; then
        cp -f "$tmp_cp/configs"/*.json "$config_dir/" 2>/dev/null
    else
        cp -f "$tmp_cp"/*.json "$config_dir/" 2>/dev/null
    fi
    rm -rf "$tmp_cp"
    local config_count
    config_count=$(find "$config_dir" -name "*.json" 2>/dev/null | wc -l)
    echo "   Saved $config_count config files to $config_dir/"
    echo "   Device: $device_slug"

    # Clean up temp container
    echo ""
    echo "🧹 Cleaning up temporary container..."
    docker stop "$temp_container" 2>/dev/null
    docker rm "$temp_container" 2>/dev/null

    # Restart original container
    echo "🔄 Restarting SGLang container: $running"
    docker start "$running" 2>&1
    sleep 5
    echo "✅ Container restarted."

    echo ""
    echo "✅ Kernel tuning complete!"
    echo "   Configs saved to: $config_dir/"
    echo "   Press Enter to return to menu..."
    read -r
}
