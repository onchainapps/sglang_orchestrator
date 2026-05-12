#!/bin/bash
# =============================================================================
# SGLang Orchestrator v12.5 - User-selectable Port
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
    echo " SGLang Orchestrator v12.5 (with selectable port)"
    echo "============================================================"
}

menu_docker() {
    while true; do
        print_header
        echo "🐳 [DOCKER] - Gemma 4 & Qwen3.6 FP8"
        echo "1) Launch Profile"
        echo "2) Show Status"
        echo "3) Back"
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

                # User-selectable parameters
                default_tp=$(get_default_tp "$sel")
                read -p "TP size [default $default_tp]: " user_tp
                tp=$(get_tp_for_launch "$sel" "$user_tp")

                read -p "Memory fraction [0.82]: " mem_frac
                mem_frac=${mem_frac:-0.82}

                read -p "Context length [262144]: " ctx_len
                ctx_len=${ctx_len:-262144}

                read -p "Port [30001]: " port
                port=${port:-30001}

                read -p "Enable Speculative? (y/n): " mtp_in
                mtp=$([[ "$mtp_in" == "y" ]] && echo "true" || echo "false")

                docker_launch_model "$sel" "$mtp" "$mem_frac" "$tp" "$ctx_len" "$port"
                read -p "Press enter..."
                ;;
            2) docker_show_status; read -p "Press enter..." ;;
            3) return ;;
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
