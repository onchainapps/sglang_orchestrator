# SGLang Orchestrator

**Version:** 13.0  
**Last Updated:** 2026-05-12  
**Purpose:** Manage SGLang inference engine deployments via Docker or VENV

## Architecture

```
orchestrator.sh (TUI)
├── Docker Path → lib_docker.sh + lib_params.sh
│   ├── Containerized SGLang serve
│   ├── Pre-configured model profiles
│   └── Speculative decoding support (EAGLE/NEXTN)
│
├── VENV Path → lib_venv.sh + lib_models.sh
│   ├── Direct Python venv launch
│   ├── Auto-detect model flags
│   └── Auto-download from HuggingFace
│
├── intelligence.sh (standalone CLI)
│   ├── --scan, --select-launch, --download
│   └── Reusable by other tools
│
├── operations.sh (standalone CLI)
│   ├── --list, --kill <pid>, --logs
│   └── Process management
│
├── expose-api.sh (standalone CLI)
│   ├── --proxy, --proxy-secure, --proxy-harden
│   └── Nginx/Certbot/UFW production exposure
│
└── modules/
    ├── lib_params.sh    — Model profile registry (6 profiles)
    ├── lib_models.sh    — Shared utilities (download, scan, detect)
    ├── lib_docker.sh    — Docker launch + status
    ├── lib_venv.sh      — VENV launch (standalone)
    ├── lib_api.sh       — API exposure wrapper (standalone)
    └── lib_docker.sh    — Docker utilities
```

**Design Principle:** Docker and VENV are parallel, independent paths. They share utilities (`lib_models.sh`) but never cross-pollinate business logic.

## Model Profiles

| Profile | Model | TP | Quant | Speculative |
|---------|-------|----|----|-------------|
| `qwen-27b-fp8` | Qwen3.6-27B-FP8 | 1 | FP8 | EAGLE + Spec V2 |
| `qwen-35b-a3b-fp8` | Qwen3.6-35B-A3B-FP8 | 2 | FP8 | EAGLE + Spec V2 |
| `qwen-27b-bf16` | Qwen3.6-27B | 1 | BF16 | None |
| `qwen-35b-a3b-bf16` | Qwen3.6-35B-A3B | 2 | BF16 | None |
| `gemma-4-26b-a4b` | Gemma 4 26B-A4B | 2 | BF16 | NEXTN (MTP) |
| `gemma-4-31b` | Gemma 4 31B | 2 | BF16 | NEXTN (MTP) |

## Usage

### Main TUI
```bash
cd ~/llms/sglang_orchestrator
chmod +x *.sh
./scripts/orchestrator.sh
```

### Docker Path
1. Select "Docker Launch" from main menu
2. Choose a profile
3. Configure TP, memory, context length, port
4. Enable FP8 (Gemma) and speculative decoding as needed

### VENV Path
1. Select "VENV Launch" from main menu
2. Select a model from local scan (or auto-download)
3. Configure port, memory, TP
4. Server starts in background with logging

### Standalone CLI Tools

**Model scan/launch (VENV):**
```bash
./scripts/intelligence.sh --scan              # List local models
./scripts/intelligence.sh --select-launch      # Interactive launch
./scripts/intelligence.sh --download <repo>    # Download from HuggingFace
```

**Process management:**
```bash
./scripts/operations.sh --list                 # Show running engines
./scripts/operations.sh --kill <pid>           # Stop an engine
./scripts/operations.sh --logs                 # Tail latest log
```

**Production API exposure:**
```bash
./scripts/expose-api.sh --proxy --api-port 30001           # Nginx only
./scripts/expose-api.sh --proxy-secure --api-port 30001 --domain example.com  # + SSL
./scripts/expose-api.sh --proxy-harden --api-port 30001 --domain example.com  # + SSL + UFW
```

## File Structure

```
sglang_orchestrator/
├── models/                          # Downloaded model weights
├── logs/                            # Server logs
├── sglang_venv/                     # Python virtual environment
├── scripts/
│   ├── orchestrator.sh              ← Main TUI entry point (v13.0)
│   ├── intelligence.sh              ← Standalone: scan/launch/download
│   ├── expose-api.sh                ← Standalone: Nginx/Certbot/UFW
│   ├── operations.sh                ← Standalone: process management
│   └── modules/
│       ├── lib_params.sh            ← Model profile registry
│       ├── lib_models.sh            ← Shared utilities (v1.0)
│       ├── lib_docker.sh            ← Docker launch/status
│       ├── lib_venv.sh              ← VENV launch (standalone)
│       ├── lib_api.sh               ← API exposure wrapper
│       └── lib_docker.sh            ← Docker utilities
└── CLEANUP_PLAN.md                  # Cleanup plan (executed)
```

## Changelog

### v13.0 (2026-05-12)
- Created `lib_models.sh` shared utility library (download, scan, detect)
- Deduplicated `get_python_env()`, `detect_model_flags()`, `scan_models_internal()`, `download_model()` between intelligence.sh and lib_venv.sh
- Added VENV menu to orchestrator.sh (Launch, Download, Status, Back)
- Added Docker status display to Docker menu
- Rewrote README with full architecture documentation
- All scripts pass `bash -n` syntax check

### v12.8 (previous)
- Return to menu after launch
- MTP fixes across multiple commits

### v10.3 (FIXED)
- Cleaned `lib_params.sh` — removed ~45 duplicate `get_special_args()` functions
- Added `venv_scan_models()` and `venv_launch_model()` wrappers to `lib_venv.sh`
- Fixed undefined `$profile_key` in `intelligence.sh`
- Fixed `lib_api.sh` calling `expose-api.sh` with wrong flags
