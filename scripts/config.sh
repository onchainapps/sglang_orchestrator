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
