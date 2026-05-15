#!/bin/bash
# =============================================================================
# SGLang Orchestrator - Global Configuration
# =============================================================================
# Source this file to get all shared paths and environment variables.
# Used by: orchestrator.sh, intelligence.sh, lib_venv.sh

# --- Directories ---
export MODELS_DIR="$HOME/llms/models"
export VENV_DIR="$HOME/llms/sglang_venv"
export LOG_DIR="$HOME/llms/sglang_orchestrator/logs"

# --- Python ---
export VENV_PYTHON="$VENV_DIR/bin/python"

# --- Power Profiles ---
# Conservative: Safe defaults, stable, leaves headroom
CONSERVATIVE_MEM_FRAC="0.90"
CONSERVATIVE_REQS="4"
CONSERVATIVE_CONSERVATIVENESS="1.3"
CONSERVATIVE_CHUNK_PREFILL="8192"
CONSERVATIVE_MAX_PREFILL="8192"

# Power: Aggressive scheduling, higher concurrency, pushes GPU limits
POWER_MEM_FRAC="0.95"
POWER_REQS="12"
POWER_CONSERVATIVENESS="0.8"
POWER_CHUNK_PREFILL="32768"
POWER_MAX_PREFILL="16384"
