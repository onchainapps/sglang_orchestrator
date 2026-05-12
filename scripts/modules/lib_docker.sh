#!/bin/bash
# =============================================================================
# lib_docker.sh - Docker Launch Logic (FIXED v11.1)
# =============================================================================
# Fixed: spec_algo unbound variable
# Fixed: Only download drafter for Gemma models (not Qwen)
# Added: TP support
# =============================================================================

set -uo pipefail

docker_launch_model() {
    local profile="$1"
    local mtp="$2"
    local mem_frac="${3:-0.82}"
    local tp="${4:-2}"

    local data
    data=$(get_profile_data "$profile")
    IFS='|' read -r image hf_repo precision mtp_cap default_tp drafter algo flags <<< "$data"

    local spec_algo="${algo:-EAGLE}"
    local model_path="$hf_repo"

    echo "🚀 Launching $profile with TP=$tp"

    # Only handle drafter for Gemma models
    if [[ "$profile" == gemma* ]]; then
        local drafter_path
        drafter_path=$(get_drafter_repo "$profile")
        if [ -n "$drafter_path" ]; then
            if [ ! -d "$MODELS_DIR/$(basename "$drafter_path")" ]; then
                echo "⚠️ Drafter not found: $drafter_path"
                read -p "Download Drafter model now? (y/n): " dl_drafter
                if [[ "$dl_drafter" == "y" ]]; then
                    bash "$SCRIPT_DIR/intelligence.sh" --download "$drafter_path"
                fi
            fi
        fi
    fi

    # Build docker command with all verified flags + TP
    local docker_cmd=(
        docker run --gpus all --rm -it
        -v "$MODELS_DIR:/models"
        -p 30000:30000
        "$image"
        --model-path "/models/$(basename "$model_path")"
        --tp "$tp"
        $flags
        --mem-fraction-static "$mem_frac"
    )

    if [ "$mtp" == "true" ]; then
        docker_cmd+=(--speculative-algorithm "$spec_algo")
    fi

    echo "Running: ${docker_cmd[*]}"
    "${docker_cmd[@]}"
}

docker_show_status() {
    docker ps --filter "ancestor=lmsysorg/sglang" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}
