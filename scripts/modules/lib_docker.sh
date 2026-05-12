#!/bin/bash
# =============================================================================
# lib_docker.sh - Docker Launch (CLEAN v11.2)
# =============================================================================
# Fixed: TP parsing bug
# Fixed: Duplicate flags
# Fixed: Clean command building
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

    local model_name
    model_name=$(basename "$hf_repo")

    echo "🚀 Launching $profile (TP=$tp, mem=$mem_frac)"

    # Build base command
    local cmd=(
        docker run --gpus all --rm -it
        -v "$MODELS_DIR:/models"
        -p 30000:30000
        "$image"
        --model-path "/models/$model_name"
        --tp "$tp"
        --mem-fraction-static "$mem_frac"
        --host 0.0.0.0
        --port 30000
    )

    # Add all verified flags from lib_params.sh (split properly)
    if [ -n "$flags" ]; then
        # Split flags string into array (handles spaces correctly)
        read -ra flag_array <<< "$flags"
        cmd+=("${flag_array[@]}")
    fi

    # Add speculative if MTP enabled
    if [ "$mtp" == "true" ] && [ -n "$algo" ]; then
        cmd+=(--speculative-algorithm "$algo")
    fi

    echo ""
    echo "Final command:"
    echo "${cmd[*]}"
    echo ""

    "${cmd[@]}"
}

docker_show_status() {
    docker ps --filter "ancestor=lmsysorg/sglang" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}
