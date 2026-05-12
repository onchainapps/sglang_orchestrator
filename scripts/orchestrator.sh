#!/bin/bash
# =============================================================================
# SGLang Modular Orchestrator v11.2 (FINAL CLEAN)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

export MODELS_DIR="$PROJECT_ROOT/models"

MODULE_DIR="$SCRIPT_DIR/modules"
source "$MODULE_DIR/lib_params.sh"
source "$MODULE_DIR/lib_docker.sh"
source "$MODULE_DIR/lib_venv.sh"
source "$MODULE_DIR/lib_api.sh"

print_header() {
    clear
    echo "============================================================"
    echo " SGLang Orchestrator v11.2 (FINAL)"
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

                # === ALWAYS ASK FOR TP ===
                default_tp=$(get_default_tp "$sel")
                read -p "TP size [default $default_tp]: " user_tp
                tp=$(get_tp_for_launch "$sel" "$user_tp")

                read -p "Enable MTP/Spec? (y/n): " mtp_in
                mtp=$([[ "$mtp_in" == "y" ]] && echo "true" || echo "false")

                read -p "Memory fraction [0.82]: " mem_frac
                mem_frac=${mem_frac:-0.82}

                docker_launch_model "$sel" "$mtp" "$mem_frac" "$tp"
                read -p "Press enter..."
                ;;
            2) docker_show_status; read -p "Press enter..." ;;
            3) return ;;
        esac
    done
}

# Main menu
while true; do
    print_header
    echo "1) Docker"
    echo "2) VENV"
    echo "3) Exit"
    read -p "Select: " main_opt
    case $main_opt in
        1) menu_docker ;;
        2) echo "VENV mode coming soon..." ;;
        3) exit 0 ;;
    esac
done
