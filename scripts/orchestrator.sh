#!/bin/bash
# =============================================================================
# SGLang Orchestrator v12.8 - Return to menu after launch
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"
export MODELS_DIR="$PROJECT_ROOT/models"

MODULE_DIR="$SCRIPT_DIR/modules"
source "$MODULE_DIR/lib_params.sh"
source "$MODULE_DIR/lib_docker.sh"

print_header() {
    clear
    echo "============================================================"
    echo " SGLang Orchestrator v12.8 (Return to Menu)"
    echo "============================================================"
}

menu_docker() {
    while true; do
        print_header
        echo "🐳 [DOCKER] - Gemma 4 & Qwen3.6 (FP8 + BF16)"
        echo "1) Launch Profile"
        echo "2) Download Model from HF"
        echo "3) Show Status"
        echo "4) Back to Main Menu"
        read -p "Select: " opt

        case $opt in
            1)
                echo ""
                echo "Available Profiles:"
                mapfile -t keys < <(get_all_profiles)
                i=1
                for k in "${keys[@]}"; do
                    printf "%s) %s - %s\n" "$i" "$k" "$(get_profile_description "$k")"
                    ((i++))
                done

                read -p "Select Profile #: " p_idx
                sel="${keys[$((p_idx-1))]}"

                default_tp=$(get_default_tp "$sel")
                read -p "TP size [default $default_tp]: " user_tp
                tp=$(get_tp_for_launch "$sel" "$user_tp")

                read -p "Memory fraction [0.82]: " mem_frac
                mem_frac=${mem_frac:-0.82}

                read -p "Context length [262144]: " ctx_len
                ctx_len=${ctx_len:-262144}

                read -p "Port [30001]: " port
                port=${port:-30001}

                use_fp8="false"
                if [[ "$sel" == gemma* ]]; then
                    read -p "Use FP8 quantization for Gemma? (y/n): " fp8_in
                    [[ "$fp8_in" == "y" ]] && use_fp8="true"
                fi

                read -p "Enable Speculative? (y/n): " mtp_in
                mtp=$([[ "$mtp_in" == "y" ]] && echo "true" || echo "false")

                docker_launch_model "$sel" "$mtp" "$mem_frac" "$tp" "$ctx_len" "$port" "$use_fp8"

                echo ""
                echo "Server stopped or exited."
                read -p "Press Enter to return to menu..."
                ;;
            2)
                read -p "Enter HF Repo ID (e.g. Qwen/Qwen3.6-35B-A3B-FP8): " hf_repo
                if [ -n "$hf_repo" ]; then
                    bash "$SCRIPT_DIR/intelligence.sh" --download "$hf_repo"
                fi
                read -p "Press enter to return to menu..."
                ;;
            3) docker_show_status; read -p "Press enter to return to menu..." ;;
            4) return ;;
        esac
    done
}

while true; do
    print_header
    echo "1) Docker Launch"
    echo "2) Exit"
    read -p "Select: " main_opt
    case $main_opt in
        1) menu_docker ;;
        2) exit 0 ;;
    esac
done
