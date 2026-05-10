#!/bin/bash
# =============================================================================
# SGLang Dynamic Orchestrator v8.19 (Ultimate Portability)
# =============================================================================

# --- ABSOLUTE DYNAMIC PATHING ---
# Find the directory where THIS script resides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Orchestrator is in ~/llms/sglang-orchestrator/scripts/
# Therefore, the project root is two levels up from this script
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

# Define all core paths relative to the dynamic PROJECT_ROOT
# This ensures it works on /home/don, /home/ubuntu, or any other path.
MANAGER_DIR="$PROJECT_ROOT"
SGLANG_REPO="$PROJECT_ROOT/../sglang_repo"
SGLANG_VENV="$PROJECT_ROOT/../sglang_venv"
MODELS_DIR="$PROJECT_ROOT/../models"
LOGS_DIR="$PROJECT_ROOT/logs"
CONFIG_DIR="$PROJECT_ROOT/config"
MODULES_DIR="$PROJECT_ROOT/modules"

# --- UI HELPERS ---
print_header() {
    if [ ! -t 0 ]; then return; fi
    clear
    echo "============================================================"
    echo " SGLang Dynamic Orchestrator v8.19 (Universal) "
    echo "============================================================"
    echo " Workspace: $PROJECT_ROOT"
    echo " SGLang:    $SGLANG_REPO"
    echo " Venv:      $SGLANG_VENV"
    echo "------------------------------------------------------------"
}

apply_rust_patch() {
    local target_file="$SGLANG_REPO/rust/sglang-grpc/Cargo.toml"
    if [ -f "$target_file" ]; then
        if ! grep -q "cargo-features" "$target_file"; then
            echo "[🛠️] Patching Cargo.toml for edition2024 support..."
            sed -i '1i cargo-features = ["edition2024"]' "$target_file"
            echo "[✅] Patch applied."
        else
            echo "[✅] Cargo.toml already patched."
        fi
    else
        echo "[❌] ERROR: Could not find Cargo.toml at $target_file"
        return 1
    fi
}

install_rust() {
    if command -v rustc &> /dev/null; then
        echo "[✅] Rust is already installed ($(rustc --version))"
        return 0
    fi

    echo "[🚀] Rust not detected. Installing via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    
    export PATH="$HOME/.cargo/bin:$PATH"
    source "$HOME/.cargo/env"
    
    if command -v rustc &> /dev/null; then
        echo "[✅] Rust installation successful."
        return 0
    else
        echo "[❌] Rust installation failed."
        return 1
    fi
}

setup_environment() {
    print_header
    echo "--- 🛠️ SGLANG ENVIRONMENT SETUP ---"
    
    apply_rust_patch || return 1
    install_rust || return 1

    echo -e "\n--- 🔍 RUNNING DEPENDENCY AUDIT ---"
    for cmd in gcc g++ make cmake rustc cargo jq; do
        if command -v $cmd &> /dev/null; then
            echo "SUCCESS: $cmd is installed"
        else
            echo "ERROR: $cmd is MISSING. Please install it via apt."
            return 1
        fi
    done

    echo -e "\n--- 🐍 PYTHON VERSION DISCOVERY ---"
    local TARGET_PYTHON=""
    if command -v python3.12 &> /dev/null; then
        TARGET_PYTHON="python3.12"
    elif command -v python3.11 &> /dev/null; then
        TARGET_PYTHON="python3.11"
    elif command -v python3.10 &> /dev/null; then
        TARGET_PYTHON="python3.10"
    else
        echo "ERROR: No stable Python (3.10, 3.11, or 3.12) found!"
        return 1
    fi
    echo "SUCCESS: Found suitable Python: $TARGET_PYTHON"

    echo -e "\n--- 📦 VIRTUAL ENVIRONMENT MANAGEMENT ---"
    if [ ! -d "$SGLANG_VENV" ]; then
        echo "Creating new venv using $TARGET_PYTHON..."
        $TARGET_PYTHON -m venv "$SGLANG_VENV"
        [ $? -ne 0 ] && { echo "[❌] Failed to create venv."; return 1; }
        echo "SUCCESS: Venv created."
    else
        echo "SUCCESS: Venv already exists at $SGLANG_VENV"
    fi

    echo -e "\n--- 🚀 INSTALLING SGLANG (EDITABLE MODE) ---"
    source "$SGLANG_VENV/bin/activate"
    pip install --upgrade pip setuptools wheel
    
    echo "Building SGLang from $SGLANG_REPO/python..."
    cd "$SGLANG_REPO/python" || return 1
    pip install -e .

    if [ $? -eq 0 ]; then
        echo -e "\n[🎉] SUCCESS: SGLang is installed and ready!"
    else
        echo -e "\n[❌] ERROR: Installation failed."
        return 1
    fi
    deactivate
}

show_status() {
    print_header
    echo "--- 📊 SYSTEM STATUS ---"
    if [ -d "$SGLANG_VENV" ]; then
        echo "Venv: [ALIVE] ($SGLANG_VENV)"
        source "$SGLANG_VENV/bin/activate"
        echo "SGLang version: $($python3 -c 'import sglang; print(sglang.__version__)' 2>/dev/null || echo 'Not found')"
        deactivate
    else
        echo "Venv: [DEAD] Not created."
    fi
    [ -x "$(command -v rustc)" ] && echo "Rust: $(rustc --version)" || echo "Rust: NOT INSTALLED"
    [ -x "$(command -v cargo)" ] && echo "Cargo: $(cargo --version)" || echo "Cargo: NOT INSTALLED"
    echo "------------------------------------------------------------"
}

# --- MAIN LOOP ---
if [ ! -t 0 ]; then
    # HEADLESS MODE
    cmd_opt=$(cat -)
    case $cmd_opt in
        6) setup_environment ;;
        3) show_status ;;
        *) exit 1 ;;
    esac
else
    # INTERACTIVE MODE
    while true; do
        print_header
        echo "1) [LAUNCH] Select Model from Disk"
        echo "2) [DOWNLOAD] Search & Fetch (hf)"
        echo "3) [MAINT] Show Status"
        echo "4) [MAINT] Stop/Remove Processes"
        echo "5) [MAINT] Show Logs"
        echo "6) [🛠️ SETUP] SGLang Environment"
        echo "7) [🚨 RECOVERY] Emergency Recovery"
        echo "8) [EXIT] Exit"
        echo "------------------------------------------------------------"
        printf "Select an option: "
        read -r opt

        case $opt in
            3) show_status ; read -p "Press enter to continue..." ;;
            6) setup_environment ; read -p "Press enter to continue..." ;;
            8) exit 0 ;;
            *) echo "Invalid option." ; sleep 1 ;;
        esac
    done
fi
