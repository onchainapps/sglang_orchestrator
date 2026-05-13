#!/bin/bash
# =============================================================================
# SGLang Orchestrator v13.0 — Docker & VENV Launch (parallel paths)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$SCRIPT_DIR/modules"
export MODELS_DIR="$HOME/llms/models"
source "$MODULE_DIR/lib_params.sh"
source "$MODULE_DIR/lib_docker.sh"
source "$MODULE_DIR/lib_models.sh"

print_header() {
    clear
    echo "============================================================"
    echo " SGLang Orchestrator v13.4 (Docker + VENV)"
    echo "============================================================"
}

# =============================================================================
# DOCKER MENU
# =============================================================================
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

                read -p "Context length [1048576]: " ctx_len
                ctx_len=${ctx_len:-1048576}

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
                    download_model "$hf_repo"
                fi
                read -p "Press enter to return to menu..."
                ;;
            3) docker_show_status; read -p "Press enter to return to menu..." ;;
            4) return ;;
        esac
    done
}

# =============================================================================
# VENV MENU
# =============================================================================
menu_venv() {
    while true; do
        print_header
        echo "🐍 [VENV] - Direct Python Launch (sglang_venv)"
        echo "1) Launch Model"
        echo "2) Download Model from HF"
        echo "3) Show Status"
        echo "4) Back to Main Menu"
        read -p "Select: " opt

        case $opt in
            1)
                source "$MODULE_DIR/lib_venv.sh"
                venv_launch_model
                echo ""
                read -p "Press Enter to return to menu..."
                ;;
            2)
                read -p "Enter HF Repo ID: " hf_repo
                if [ -n "$hf_repo" ]; then
                    download_model "$hf_repo"
                fi
                read -p "Press enter to return to menu..."
                ;;
            3)
                echo ""
                echo "=== Running SGLang Engines (VENV) ==="
                if ! pgrep -f "sglang.launch_server" > /dev/null; then
                    echo "No running SGLang engines."
                else
                    printf "%-8s | %-60s | %-8s\n" "PID" "MODEL" "PORT"
                    echo "----------------------------------------------------------------"
                    ps aux | grep "sglang.launch_server" | grep -v grep | while read -r line; do
                        pid=$(echo "$line" | awk '{print $2}')
                        port=$(echo "$line" | grep -o '--port [0-9]*' | grep -o '[0-9]*' || echo "N/A")
                        model_path=$(echo "$line" | grep -o '--model-path [^ ]*' | cut -d' ' -f2- || echo "unknown")
                        model_name=$(basename "$model_path" 2>/dev/null || echo "$model_path")
                        printf "%-8s | %-60s | %-8s\n" "$pid" "${model_name:0:58}" "$port"
                    done
                fi
                read -p "Press enter to return to menu..."
                ;;
            4) return ;;
        esac
    done
}

# =============================================================================
# MAIN MENU
# =============================================================================
while true; do
    print_header
    echo "1) Docker Launch"
    echo "2) VENV Launch"
    echo "3) Exit"
    read -p "Select: " main_opt
    case $main_opt in
        1) menu_docker ;;
        2) menu_venv ;;
        3) exit 0 ;;
    esac
done
