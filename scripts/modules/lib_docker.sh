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

docker_launch_model() {
    local profile="$1"
    local mtp="$2"
    local mem_frac="${3:-0.85}"
    local tp="${4:-1}"
    local ctx_len="${5:-128000}"
    local port="${6:-30001}"
    local reqs="${7:-8}"

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
    if [[ "$profile" == gemma* ]] || [[ "$hf_repo" == google/* ]]; then
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
    # Auto-mount kernel tuning configs if they exist (search orchestrator kernel_configs/)
    local kernel_config_vol=""
    local kernel_config_base="$SCRIPT_DIR/../kernel_configs"
    if [ -d "$kernel_config_base" ]; then
        # Find the best matching config dir (try device-model, then device, then any)
        local device_name
        device_name=$(python3 -c "import torch; print(torch.cuda.get_device_name(0).replace(' ', '_').replace('-', '_'))" 2>/dev/null || echo "unknown_gpu")
        local config_match=""
        # Try exact device-model match first
        if ls "$kernel_config_base/${device_name}"-*.json 2>/dev/null | head -1 > /dev/null; then
            config_match=$(find "$kernel_config_base" -maxdepth 1 -type d -name "${device_name}-*" 2>/dev/null | head -1)
        fi
        # Fallback to any config dir
        if [ -z "$config_match" ]; then
            config_match=$(find "$kernel_config_base" -maxdepth 1 -type d 2>/dev/null | head -1)
        fi
        if [ -n "$config_match" ] && [ "$(find "$config_match" -name '*.json' 2>/dev/null | wc -l)" -gt 0 ]; then
            kernel_config_vol="-v $config_match:/sgl-workspace/sglang/python/sglang/srt/layers/quantization/configs"
        fi
    fi
    local full_cmd="docker run -d --name $container_name --gpus all --cap-add SYS_NICE --rm -v $MODELS_DIR:/models $kernel_config_vol -p $port:$port"

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
    if [[ "$profile" == "qwen-35b-a3b-bf16" || "$profile" == "qwen-27b-fp8" ]]; then
        chunk_size=16384
    fi

    full_cmd="$full_cmd $image sglang serve --model-path /models/$hf_repo --tp $tp --mem-fraction-static $mem_frac --context-length $ctx_len --max-running-requests $reqs --max-total-tokens $ctx_len --chunked-prefill-size $chunk_size --max-prefill-tokens 16384 --allow-auto-truncate --schedule-policy lpm --trust-remote-code --host 0.0.0.0 --port $port"

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
    echo "   Takes 10-20 minutes (benchmarks every config combination)."
    echo "   Results are saved to sglang_orchestrator/kernel_configs/ (git-tracked)."
    read -p "Start tuning? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Cancelled."
        read -p "Press Enter to return to menu..."
        return
    fi

    # Detect device and model for config subdirectory naming
    local device_name
    device_name=$(docker exec "$running" python3 -c "import torch; print(torch.cuda.get_device_name(0).replace(' ', '_').replace('-', '_'))" 2>/dev/null)
    local device_slug="${device_name:-unknown_gpu}"

    local model_repo
    model_repo=$(docker exec "$running" python3 -c "
from transformers import AutoConfig
config = AutoConfig.from_pretrained('/models', trust_remote_code=True)
# Try to detect model name from config
print(getattr(config, 'model_type', 'unknown'))
" 2>/dev/null)
    local model_slug="${model_repo:-unknown_model}"

    local config_dir="$SCRIPT_DIR/../kernel_configs/${device_slug}-${model_slug}"
    mkdir -p "$config_dir"

    # Step 1: Detect model architecture from container
    echo ""
    echo "📐 Step 1/3: Detecting model architecture..."
    local hidden_size
    hidden_size=$(docker exec "$running" python3 -c "
from transformers import AutoConfig
config = AutoConfig.from_pretrained('/models', trust_remote_code=True)
hs = getattr(config, 'hidden_size', 5120)
print(hs if hs else 5120)
" 2>/dev/null)
    if [ -z "$hidden_size" ] || [ "$hidden_size" = "0" ]; then
        echo "⚠️  Could not auto-detect hidden_size. Using Qwen3 default (5120)."
        hidden_size=5120
    fi

    local intermediate_size
    intermediate_size=$(docker exec "$running" python3 -c "
from transformers import AutoConfig
config = AutoConfig.from_pretrained('/models', trust_remote_code=True)
print(getattr(config, 'intermediate_size', 25600))
" 2>/dev/null)
    if [ -z "$intermediate_size" ] || [ "$intermediate_size" = "0" ]; then
        intermediate_size=25600
    fi

    local num_heads
    num_heads=$(docker exec "$running" python3 -c "
from transformers import AutoConfig
config = AutoConfig.from_pretrained('/models', trust_remote_code=True)
print(getattr(config, 'num_attention_heads', 64))
" 2>/dev/null)
    if [ -z "$num_heads" ] || [ "$num_heads" = "0" ]; then
        num_heads=64
    fi

    local num_kv_heads
    num_kv_heads=$(docker exec "$running" python3 -c "
from transformers import AutoConfig
config = AutoConfig.from_pretrained('/models', trust_remote_code=True)
print(getattr(config, 'num_key_value_heads', None))
" 2>/dev/null)
    if [ -z "$num_kv_heads" ] || [ "$num_kv_heads" = "None" ]; then
        # MHA: num_kv_heads = num_heads
        num_kv_heads=$num_heads
    fi

    local head_dim
    head_dim=$(docker exec "$running" python3 -c "
from transformers import AutoConfig
config = AutoConfig.from_pretrained('/models', trust_remote_code=True)
print(getattr(config, 'head_dim', 128))
" 2>/dev/null)
    if [ -z "$head_dim" ] || [ "$head_dim" = "0" ]; then
        head_dim=128
    fi

    echo "   hidden_size: $hidden_size"
    echo "   intermediate_size: $intermediate_size"
    echo "   num_heads: $num_heads"
    echo "   num_kv_heads: $num_kv_heads"
    echo "   head_dim: $head_dim"

    # Step 2: Compute weight shapes and tune each
    echo ""
    echo "🔧 Step 2/3: Running kernel autotuner..."

    # QKV projection: Q(num_heads*head_dim) + K(num_kv_heads*head_dim) + V(num_kv_heads*head_dim)
    local qkv_out=$((num_heads * head_dim + 2 * num_kv_heads * head_dim))
    local mlp_gate_up=$((2 * intermediate_size))
    local o_proj_in=$((num_heads * head_dim))

    # Weight shapes to tune: (N, K)
    local -a shapes=()
    shapes+=("$qkv_out,$hidden_size")       # QKV projection
    shapes+=("$mlp_gate_up,$hidden_size")   # MLP gate+up (SwiGLU)
    shapes+=("$hidden_size,$intermediate_size")  # MLP down projection
    shapes+=("$hidden_size,$o_proj_in")     # Output projection
    shapes+=("$hidden_size,$hidden_size")   # RMN, Gate, etc.

    for shape in "${shapes[@]}"; do
        local n="${shape%%,*}"
        local k="${shape##*,}"
        echo "   Tuning N=$n, K=$k..."
        docker exec "$running" python3 benchmark/kernels/quantization/tuning_block_wise_kernel.py \
            --N "$n" --K "$k" --input-type fp8 \
            --save-path python/sglang/srt/layers/quantization/configs 2>&1
        echo ""
    done

    # Step 3: Copy configs back to host
    echo ""
    echo "💾 Step 3/3: Saving tuned configs to host..."
    docker cp "$running:/sgl-workspace/sglang/python/sglang/srt/layers/quantization/configs/" \
        "$config_dir/" 2>/dev/null

    local config_count
    config_count=$(find "$config_dir" -name "*.json" 2>/dev/null | wc -l)
    echo "   Saved $config_count config files to $config_dir/"
    echo "   Device: $device_name"
    echo "   Model: $model_slug"

    echo ""
    echo "✅ Kernel tuning complete!"
    echo "   Configs saved to: $config_dir/"
    echo "   These are auto-mounted on next launch."
    echo "   Commit them to git to share across machines."
    read -p "Press Enter to return to menu..."
}
