#!/bin/bash
# =============================================================================
# SGLang Orchestrator v13.0 — Docker & VENV Launch (parallel paths)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$SCRIPT_DIR/modules"
source "$SCRIPT_DIR/config.sh"
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
# PROXY MENU
# =============================================================================
menu_proxy() {
    source "$MODULE_DIR/lib_api.sh"
    while true; do
        print_header
        echo "🌐 [PROXY] - API Exposure & Nginx Management"
        echo "1) Generate Nginx Config (HTTP proxy only)"
        echo "2) Full Production Harden (HTTP + SSL + UFW)"
        echo "3) Audit Nginx Config (validate + report)"
        echo "4) Monitor Scanner Hits (403 logs)"
        echo "5) Manage Nginx (test/reload/restart)"
        echo "6) Back to Main Menu"
        read -p "Select: " opt

        case $opt in
            1)
                read -p "API port [30001]: " port
                port=${port:-30001}
                read -p "Domain (leave blank for HTTP): " domain
                generate_nginx_config "$port" "$domain"
                echo ""
                read -p "Press Enter to return to menu..."
                ;;
            2)
                read -p "API port [30001]: " port
                port=${port:-30001}
                read -p "Domain (required for SSL): " domain
                if [ -n "$domain" ]; then
                    full_harden "$port" "$domain"
                else
                    echo ""
                    echo -e "${RED}❌ Domain is required for SSL+harden mode${NC}"
                fi
                echo ""
                read -p "Press Enter to return to menu..."
                ;;
            3)
                audit_nginx_config
                echo ""
                read -p "Press Enter to return to menu..."
                ;;
            4)
                monitor_scanner_hits
                echo ""
                read -p "Press Enter to return to menu..."
                ;;
            5)
                echo ""
                echo "1) Test config syntax"
                echo "2) Reload (graceful)"
                echo "3) Restart"
                read -p "Action [3]: " act
                act=${act:-3}
                case $act in
                    1) manage_nginx test ;;
                    2) manage_nginx reload ;;
                    3) manage_nginx restart ;;
                esac
                echo ""
                read -p "Press Enter to return to menu..."
                ;;
            6)
                return
                ;;
        esac
    done
}

# =============================================================================
# DOCKER MENU
# =============================================================================
menu_docker() {
    while true; do
        print_header
        echo "🐳 [DOCKER] - Predefined Profiles"
        echo "1) Launch Profile"
        echo "2) Download Model from HF"
        echo "3) Show Status"
        echo "4) Check for Docker Image Updates"
        echo "5) Kernel Tuning (auto-tune FP8 Triton kernels)"
        echo "6) Back to Main Menu"
        read -p "Select: " opt

        case $opt in
            1)
                # Power profile selection
                echo ""
                echo "⚡ Select Power Profile:"
                echo "  1) 🛡️  Conservative - Stable defaults, leaves headroom"
                echo "     (mem=0.90, reqs=4, conservativeness=1.3)"
                echo "  2) 🔥 Power - Aggressive scheduling, pushes GPU limits"
                echo "     (mem=0.95, reqs=12, conservativeness=0.8)"
                read -p "Select [1]: " power_opt
                power_mode="conservative"
                [[ "$power_opt" == "2" ]] && power_mode="power"
                echo ""
                echo "Selected: $power_mode mode"
                echo ""

                # Show predefined profiles only
                echo "📋 Predefined Profiles:"
                local -a all_options=()
                local i=1
                mapfile -t keys < <(get_all_profiles)
                for k in "${keys[@]}"; do
                    printf "%s) %s - %s\n" "$i" "$k" "$(get_profile_description "$k")"
                    all_options+=("$k")
                    ((i++))
                done

                echo ""
                read -p "Select #: " p_idx
                local sel="${all_options[$((p_idx-1))]}"

                default_tp=$(get_default_tp "$sel")
                read -p "TP size [default $default_tp]: " user_tp
                tp=$(get_tp_for_launch "$sel" "$user_tp")

                # Apply profile defaults
                if [[ "$power_mode" == "power" ]]; then
                    read -p "Memory fraction [${POWER_MEM_FRAC}]: " mem_frac
                    mem_frac=${mem_frac:-$POWER_MEM_FRAC}
                else
                    read -p "Memory fraction [${CONSERVATIVE_MEM_FRAC}]: " mem_frac
                    mem_frac=${mem_frac:-$CONSERVATIVE_MEM_FRAC}
                fi
                read -p "Max concurrent requests [$(if [[ "$power_mode" == "power" ]]; then echo "$POWER_REQS"; else echo "$CONSERVATIVE_REQS"; fi)]: " user_reqs
                if [[ "$power_mode" == "power" ]]; then
                    reqs=${user_reqs:-$POWER_REQS}
                else
                    reqs=${user_reqs:-$CONSERVATIVE_REQS}
                fi

                read -p "Context length [262111]: " ctx_len
                ctx_len=${ctx_len:-262111}

                read -p "Port [30001]: " port
                port=${port:-30001}

                # SGLang API key authentication
                read -p "API key (leave blank to skip): " DOCKER_API_KEY
                read -p "Admin API key (leave blank to skip): " DOCKER_ADMIN_API_KEY

                read -p "Enable Speculative? (y/n): " mtp_in
                mtp=$([[ "$mtp_in" == "y" ]] && echo "true" || echo "false")

                # Export API keys for lib_docker.sh to pick up
                [ -n "$DOCKER_API_KEY" ] && export API_KEY="$DOCKER_API_KEY"
                [ -n "$DOCKER_ADMIN_API_KEY" ] && export ADMIN_API_KEY="$DOCKER_ADMIN_API_KEY"

                echo ""
                echo "🚀 Launching in $power_mode mode..."
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "  Memory fraction: $mem_frac"
                echo "  Max requests: $reqs"
                echo "  Schedule conservativeness: $(if [[ "$power_mode" == "power" ]]; then echo "$POWER_CONSERVATIVENESS"; else echo "$CONSERVATIVE_CONSERVATIVENESS"; fi)"
                echo "  Chunked prefill: $(if [[ "$power_mode" == "power" ]]; then echo "$POWER_CHUNK_PREFILL"; else echo "$CONSERVATIVE_CHUNK_PREFILL"; fi)"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""

                docker_launch_model "$sel" "$mtp" "$power_mode" "$mem_frac" "$tp" "$ctx_len" "$port" "$reqs"

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
            4) check_docker_updates; read -p "Press enter to return to menu..." ;;
            5) tune_kernels ;;
            6) return ;;
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
    echo "3) Proxy & Nginx Management"
    echo "4) Dashboard (Textual TUI)"
    echo "5) Exit"
    read -p "Select: " main_opt
    case $main_opt in
        1) menu_docker ;;
        2) menu_venv ;;
        3) menu_proxy ;;
        4) bash "$SCRIPT_DIR/../dashboard/launch.sh" ;;
        5) exit 0 ;;
    esac
done
