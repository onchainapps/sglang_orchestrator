# SGLang Orchestrator

**Version:** 13.5  \n**Last Updated:** 2026-05-15  \n**Purpose:** Manage SGLang inference engine deployments via Docker or VENV with production-ready tooling

## Overview

SGLang Orchestrator is a comprehensive management system for deploying and monitoring SGLang inference engines. It provides:

- 🚀 **Docker & VENV launch paths** with parallel, independent workflows
- 📊 **Real-time dashboard** with container status, logs, and GPU metrics
- 🔧 **Kernel tuning** with auto-detection and FP8 optimization
- 🌐 **Production API exposure** with Nginx, SSL, and UFW hardening
- 📋 **Pre-configured model profiles** for popular LLMs
- ⚡ **Power profiles** for conservative or aggressive GPU utilization

## Architecture

```
orchestrator.sh (TUI)
├── Docker Path → lib_docker.sh + lib_params.sh
│   ├── Containerized SGLang serve
│   ├── Pre-configured model profiles
│   ├── Dynamic model detection from ~/llms/models/
│   └── Speculative decoding support (EAGLE/MTP)
│
├── VENV Path → lib_venv.sh + lib_models.sh
│   ├── Direct Python venv launch
│   ├── Auto-detect model flags
│   └── Auto-download from HuggingFace
│
├── Dashboard → dashboard/ (Textual TUI)
│   ├── Real-time container status
│   ├── Live log streaming
│   ├── GPU metrics monitoring
│   ├── Nginx/proxy status
│   └── Kernel tuning controls
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
    ├── lib_params.sh    — Model profile registry
    ├── lib_models.sh    — Shared utilities (download, scan, detect)
    ├── lib_docker.sh    — Docker launch + status + kernel tuning
    ├── lib_venv.sh      — VENV launch (standalone)
    └── lib_api.sh       — API exposure wrapper (standalone)
```

**Design Principle:** Docker and VENV are parallel, independent paths. They share utilities (`lib_models.sh`) but never cross-pollinate business logic.

## Getting Started

### Prerequisites

- NVIDIA GPU (Blackwell architecture recommended)
- Docker installed and running
- Python 3.8+
- NVIDIA drivers installed
- SGLang virtual environment (for VENV path)

### Installation

```bash
cd ~/llms
git clone https://github.com/onchainapps/sglang_orchestrator.git
cd sglang_orchestrator
chmod +x *.sh scripts/*.sh scripts/modules/*.sh
```

### Launch

```bash
./scripts/orchestrator.sh
```

## Usage

### Main Menu

```
============================================================
 SGLang Orchestrator v13.5 (Docker + VENV)
============================================================
1) Docker Launch
2) VENV Launch
3) Proxy & Nginx Management
4) Dashboard (Textual TUI)
5) Exit
```

### Power Profiles

When launching, you'll be prompted to select a power profile:

#### Conservative (🛡️)
Safe defaults, stable, leaves headroom:
- `--mem-fraction-static`: 0.90
- `--max-running-requests`: 4
- `--schedule-conservativeness`: 1.3
- `--chunked-prefill-size`: 8192
- `--max-prefill-tokens`: 8192

#### Power (🔥)
Aggressive scheduling, pushes GPU limits:
- `--mem-fraction-static`: 0.95
- `--max-running-requests`: 12
- `--schedule-conservativeness`: 0.8
- `--chunked-prefill-size`: 32768
- `--max-prefill-tokens`: 16384

### Docker Path

1. Select "Docker Launch" from main menu
2. Choose power profile (Conservative/Power)
3. Select model profile
4. Configure:
   - TP size (tensor parallelism)
   - Memory fraction
   - Max concurrent requests
   - Context length
   - Port
   - API key (optional)
   - Admin API key (optional)
   - Enable speculative decoding (y/n)
5. Server starts in background with logging

### VENV Path

1. Select "VENV Launch" from main menu
2. Select a model from local scan (or auto-download)
3. Configure port, memory, TP
4. Server starts in background with logging

### Dashboard

**Launch from main menu:**
```
Select: 4) Dashboard (Textual TUI)
```

**Or launch directly:**
```bash
bash ~/llms/sglang_orchestrator/dashboard/launch.sh
```

**Dashboard Features:**
- **Containers Tab**: Live status table with CPU, VRAM, ports, uptime
- **Logs Tab**: Per-container log streaming with auto-scroll
- **Nginx Tab**: Proxy service status, uptime, active connections
- **Kernel Tuning Tab**: FP8 kernel autotuning progress monitoring

**Keyboard Shortcuts:**
| Key | Action |
|-----|--------|
| `Q` | Quit dashboard |
| `R` | Refresh data |
| `L` | Toggle logs tab |
| `D` | Container details |
| `N` | Nginx status |
| `K` | Kernel tuning |

**Auto-refresh:** Dashboard polls Docker and NVIDIA SMI every 5 seconds.

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

## Quantization: FP8 vs BF16

Understanding the trade-offs between FP8 and BF16 is crucial for optimizing your deployment on Blackwell GPUs.

| Feature | FP8 (Recommended) | BF16 (Reference) |
|---------|-------------------|------------------|
| **Performance** | ⚡ **Significantly faster.** Blackwell has dedicated FP8 tensor cores, doubling memory bandwidth efficiency. | 🐢 Slower. Uses standard tensor cores; less optimized for modern inference workloads. |
| **Accuracy** | ✅ **99%+ retention.** Post-Training Quantization (PTQ) preserves intelligence. Imperceptible drop in chat/coding. | 🏆 **100% Reference.** The baseline precision. Technically superior by <1%. |
| **VRAM Usage** | 💾 **~14-15 GB** (for 27B model). Leaves massive headroom for KV Cache and concurrent requests. | 💾 **~55 GB** (for 27B model). Eats ~40GB extra VRAM that could be used for context/throughput. |
| **Hardware Utilization** | 🔥 **Optimal.** Running FP8 on Blackwell is like driving a Ferrari at full throttle. | 🧊 **Underutilized.** Running BF16 on Blackwell is like putting a Ferrari in Economy mode. |

**Recommendation:** Stick to **FP8** unless you have a specific scientific/research requirement for BF16. The 1% theoretical accuracy gain is not worth the 50% performance and memory penalty.

## Model Profiles

| Profile | Model | TP | Quant | Speculative |
|---------|-------|----|-------|-------------|
| `qwen-27b-fp8` | Qwen3.6-27B-FP8 | 1 | FP8 | EAGLE + Spec V2 |
| `qwen-35b-a3b-fp8` | Qwen3.6-35B-A3B-FP8 | 1 | FP8 | EAGLE + Spec V2 |
| `qwen-27b-bf16` | Qwen3.6-27B | 1 | BF16 | None |
| `qwen-35b-a3b-bf16` | Qwen3.6-35B-A3B | 1 | BF16 | None |
| `gemma-4-26b-a4b` | Gemma 4 26B-A4B | 1 | BF16 | NEXTN (MTP) |
| `gemma-4-31b` | Gemma 4 31B | 1 | BF16 | NEXTN (MTP) |

## Configuration

### Global Configuration

Edit `scripts/config.sh` to change defaults:

```bash
export MODELS_DIR="$HOME/llms/models"      # Model weights location
export VENV_DIR="$HOME/llms/sglang_venv"   # Python venv location
export LOG_DIR="$HOME/llms/sglang_orchestrator/logs"  # Server logs
```

### Kernel Tuning

1. Launch a model first
2. From Docker menu, select "Kernel Tuning"
3. System auto-detects model architecture
4. Runs FP8 kernel autotuner
5. Saves configs to `kernel_configs/[device]-[model]/` (git-tracked)
6. Auto-mounts tuned configs on container launch

### API Keys

Set API keys during launch or via environment variables:
```bash
export API_KEY="your-api-key"
export ADMIN_API_KEY="your-admin-key"
```

## File Structure

```
sglang_orchestrator/
├── models/                          # Downloaded model weights
├── logs/                            # Server logs
├── sglang_venv/                     # Python virtual environment
├── kernel_configs/                  # Tuned FP8 kernel configs (git-tracked)
│   └── [device]-[model]/           # Auto-tuned Triton kernel configs
├── dashboard/                       # Textual TUI dashboard
│   ├── dashboard.py                 ← Main Textual app
│   ├── launch.sh                    ← Auto-install + launch
│   ├── requirements.txt             ← Python dependencies
│   └── .gitignore
├── scripts/
│   ├── orchestrator.sh              ← Main TUI entry point (v13.5)
│   ├── intelligence.sh              ← Standalone: scan/launch/download
│   ├── expose-api.sh                ← Standalone: Nginx/Certbot/UFW
│   ├── operations.sh                ← Standalone: process management
│   └── modules/
│       ├── lib_params.sh            ← Model profile registry
│       ├── lib_models.sh            ← Shared utilities (v1.0)
│       ├── lib_docker.sh            ← Docker launch/status/kernel tuning
│       ├── lib_venv.sh              ← VENV launch (standalone)
│       └── lib_api.sh               ← API exposure wrapper
├── references/
│   └── sglang-server-args.md        ← Server arguments reference
└── sglang_watchdog.sh               ← Watchdog script
```

## Troubleshooting

### Common Issues

**OOM during prefill:**
- Lower `--chunked-prefill-size` to 4096 or 2048

**OOM during decode:**
- Lower `--max-running-requests`

**General OOM:**
- Lower `--mem-fraction-static` (0.8 or 0.7)

**Slow prefill on long prompts:**
- Raise `--chunked-prefill-size` to 16384 or 32768

**Low throughput:**
- Raise `--schedule-conservativeness` to 0.3
- Increase `--mem-fraction-static`

**KV cache thrashing:**
- Increase `--max-total-tokens`
- Decrease `--schedule-conservativeness`

**Many short requests:**
- Use `--schedule-policy lpm` for prefix cache hits

### Diagnostic Commands

```bash
# Check container status
docker ps --filter "name=sglang-"

# View logs
docker logs -f sglang-*

# GPU metrics
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv

# Check running processes
./scripts/operations.sh --list
```

## Best Practices

1. **Start Conservative:** Begin with conservative power profile for stability
2. **Monitor GPU:** Use dashboard to track utilization and thermal limits
3. **Kernel Tune:** Run kernel tuning once per model/GPU combination
4. **Version Control:** Track kernel configs in git (auto-done)
5. **API Keys:** Always set API keys for production deployments
6. **SSL:** Use `--proxy-secure` or `--proxy-harden` for public APIs
7. **Watchdog:** Consider running `sglang_watchdog.sh` for reliability

## Changelog

### v13.5 (2026-05-15)
- Added power profiles (Conservative/Power) for launch
- Conservative: mem=0.90, reqs=4, conservativeness=1.3
- Power: mem=0.95, reqs=12, conservativeness=0.8
- Updated context length default to 262111 (full 256K context)

### v13.4 (2026-05-13)
- Added Textual TUI dashboard (`dashboard/`)
  - Real-time container status monitoring
  - Live log streaming with per-container filtering
  - GPU metrics (temp, power, utilization) footer
  - Nginx/proxy status monitoring
  - Keyboard shortcuts for quick navigation
- Added kernel tuning menu to Docker path
  - Auto-detects model architecture from running container
  - Runs SGLang FP8 kernel autotuner (`tuning_block_wise_kernel.py`)
  - Saves configs to `kernel_configs/[device]-[model]/` (git-tracked)
  - Auto-mounts tuned configs on container launch
- Fixed QKV detection for grouped-query attention (`num_key_value_heads`)
- Dynamic model detection from `~/llms/models/` in Docker menu
- Updated default parameters (mem=0.90, reqs=16) for Blackwell GPUs
- Added `--cap-add SYS_NICE` to fix NUMA affinity warnings

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
