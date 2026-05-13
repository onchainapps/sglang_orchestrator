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
        echo "🐳 [DOCKER] - Gemma 4 & Qwen3.6 (BF16)"
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

                read -p "Max concurrent requests [default 2]: " user_reqs
                reqs=${user_reqs:-2}

                read -p "Page size [default 16]: " user_pg
                pg_size=${user_pg:-16}

                read -p "Memory fraction [0.82]: " mem_frac
                mem_frac=${mem_frac:-0.82}
                # Per-model defaults: MTP models need more VRAM for draft weights
                if [[ "$sel" == gemma-4-31b ]]; then
                    mem_frac=${mem_frac:-0.78}  # 31B needs more headroom for weights+KV cache
                elif [[ "$sel" == gemma* ]]; then
                    mem_frac=${mem_frac:-0.80}  # MTP draft model + KV cache
                fi
                # --- Qwen 3.6 Turbo ---
                # Push memory fraction higher (0.88) since MTP draft weights are efficient
                if [[ "$sel" == qwen-35b-a3b-bf16 ]]; then
                    mem_frac=${mem_frac:-0.88}
                elif [[ "$sel" == qwen*-*fp8 ]]; then
                    mem_frac=${mem_frac:-0.85}  # FP8 is more memory efficient
                fi

                read -p "Context length [262144]: " ctx_len
                ctx_len=${ctx_len:-262144}
                # 31B sliding window profiler is too conservative (~20K tokens)
                if [[ "$sel" == gemma-4-31b ]]; then
                    ctx_len=${ctx_len:-32768}
                fi

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

                docker_launch_model "$sel" "$mtp" "$mem_frac" "$tp" "$ctx_len" "$port" "$reqs" "$pg_size"

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
    echo "3) Proxy & Nginx Management"
    echo "4) Exit"
    read -p "Select: " main_opt
    case $main_opt in
        1) menu_docker ;;
        2) menu_venv ;;
        3) menu_proxy ;;
        4) exit 0 ;;
    esac
done
