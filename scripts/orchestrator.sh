#!/bin/bash
# =============================================================================
# SGLang Modular Orchestrator v10.1 (Fixed Environment)
# =============================================================================

set -uo pipefail

# --- CONFIGURATION & PATHS ---
# Define core paths FIRST. Modules depend on these being set.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

# Environment variables for modules
export SGLANG_REPO="$PROJECT_ROOT/sglang_repo"
export SGLANG_VENV="$PROJECT_ROOT/sglang_venv"
export VENV_PYTHON="$SGLANG_VENV/bin/python"
export MODELS_DIR="$PROJECT_ROOT/models"
export LOG_DIR="$PROJECT_ROOT/logs"

# Load Modules
MODULE_DIR="$SCRIPT_DIR/modules"
source "$MODULE_DIR/lib_docker.sh"
source "$MODULE_DIR/lib_venv.sh"
source "$MODULE_DIR/lib_api.sh"

# --- UTILITIES ---
print_header() {
    clear
    echo "============================================================"
    echo " SGLang Modular Orchestrator v10.1"
    echo "============================================================"
    echo " Workspace: $PROJECT_ROOT"
    echo "------------------------------------------------------------"
}

bootstrap_workspace() {
    mkdir -p "$PROJECT_ROOT"/{sglang_repo,sglang_venv,models,logs,config,modules}
    echo "✅ Workspace initialized."
}

# --- SUB-MENUS ---

menu_docker() {
    while true; do
        print_header
        echo "🐳 [DOCKER MODE] - Specialized High-Perf Containers"
        echo "------------------------------------------------------------"
        echo "1) [🚀] Launch Profile"
        echo "2) [📊] Show Docker Status"
        echo "3) [🔙] Back to Main Menu"
        echo "------------------------------------------------------------"
        read -p "Select option: " opt

        case $opt in
            1)
                echo "Available Docker Profiles:"
                i=1
                mapfile -t keys < <(for k in "${!DOCKER_PROFILES[@]}"; do echo "$k"; done)
                for k in "${keys[@]}"; do echo "$i) $k"; ((i++)); done
                read -p "Select Profile #: " p_idx
                if [[ "$p_idx" =~ ^[0-9]+$ ]] && [ "$p_idx" -le "${#keys[@]}" ]; then
                    sel="${keys[$((p_idx-1))]}"
                    read -p "Enable MTP? (y/n): " mtp_in
                    [[ "$mtp_in" == "y" ]] && mtp="true" || mtp="false"
                    docker_launch_model "$sel" "$mtp"
                fi
                read -p "Press enter..."
                ;;
            2) docker_show_status; read -p "Press enter..." ;;
            3) return ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

menu_venv() {
    while true; do
        print_header
        echo "🐍 [VENV MODE] - Local Development Environment"
        echo "------------------------------------------------------------"
        echo "1) [🔍] Scan Local Models"
        echo "2) [🚀] Launch Model"
        echo "3) [🔙] Back to Main Menu"
        echo "------------------------------------------------------------"
        read -p "Select option: " opt

        case $opt in
            1) venv_scan_models; read -p "Press enter..." ;;
            2)
                venv_scan_models
                read -p "Enter Model Path (or ID from scan): " m_path
                if [ -n "$m_path" ]; then
                    venv_launch_model "$m_path"
                fi
                read -p "Press enter..."
                ;;
            3) return ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

menu_downloads() {
    while true; do
        print_header
        echo "📥 [DOWNLOADS] - Hugging Face Management"
        echo "------------------------------------------------------------"
        echo "1) [⏬] Download HF Model"
        echo "2) [🔙] Back to Main Menu"
        echo "------------------------------------------------------------"
        read -p "Select option: " opt

        case $opt in
            1)
                read -p "Enter HF Repo ID: " hf_repo
                if [ -n "$hf_repo" ]; then
                    bash "$SCRIPT_DIR/intelligence.sh" --download "$hf_repo"
                fi
                read -p "Press enter..."
                ;;
            2) return ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

menu_ops() {
    while true; do
        print_header
        echo "🛠️ [OPERATIONS] - Maintenance & Management"
        echo "------------------------------------------------------------"
        echo "1) [📊] Engine Status (All)"
        echo "2) [📜] View Logs"
        echo "3) [🛑] Stop/Kill Engine"
        echo "4) [🌐] Expose API"
        echo "5) [🔙] Back to Main Menu"
        echo "------------------------------------------------------------"
        read -p "Select option: " opt

        case $opt in
            1) bash "$SCRIPT_DIR/operations.sh" --list; read -p "Press enter..." ;;
            2) bash "$SCRIPT_DIR/operations.sh" --logs; read -p "Press enter..." ;;
            3) read -p "Enter PID to kill: " pid; bash "$SCRIPT_DIR/operations.sh" --kill "$pid"; read -p "Press enter..." ;;
            4) read -p "Port [30001]: " port; expose_api "${port:-30001}"; read -p "Press enter..." ;;
            5) return ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

# --- MAIN LOOP ---

while true; do
    print_header
    echo "=== [🚀] SGLang Modular Orchestrator v10.1 ==="
    echo "------------------------------------------------------------"
    echo "1) 🐳 [DOCKER] - Specialized High-Perf Containers"
    echo "2) 🐍 [VENV]   - Local Development Environment"
    echo "3) 📥 [DL]     - Hugging Face Downloads"
    echo "4) 🛠️ [OPS]    - Status, Logs, & API Management"
    echo "5) ❌ [EXIT]   - Quit"
    echo "------------------------------------------------------------"
    printf "Select mode: "
    read -r main_opt

    case $main_opt in
        1) menu_docker ;;
        2) menu_venv ;;
        3) menu_downloads ;;
        4) menu_ops ;;
        5) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done
