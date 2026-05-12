# SGLang Orchestrator - FIXED Version (v10.3)

**Date:** 2026-05-11  
**Status:** All critical bugs resolved

## What Was Broken & Fixed

### 1. `lib_params.sh` (Critical)
- **Problem:** ~45 duplicate identical `get_special_args()` functions + duplicate comment block.
- **Fix:** Completely cleaned. Only one clean definition remains.

### 2. `lib_venv.sh` (Critical)
- **Problem:** Missing `venv_scan_models()` and `venv_launch_model()` wrappers that `orchestrator.sh` expected.
- **Fix:** Added proper public API wrappers + removed duplicate/messy code.

### 3. `intelligence.sh` (Critical)
- **Problem:** Undefined variable `$profile_key` in `select_and_launch()` causing errors during auto-download.
- **Fix:** Removed the broken drafter logic block (it was incorrectly copied from Docker flow).

### 4. `lib_api.sh` (High)
- **Problem:** Called `expose-api.sh` with `--port` (unsupported flag).
- **Fix:** Changed to correct invocation: `--proxy --api-port "$port"`

### 5. `orchestrator.sh`
- Minor version bump + added "FIXED" header for clarity.

## How to Use the Fixed Version

1. Replace your `scripts/modules/` directory with the files in this folder.
2. Make sure `expose-api.sh` and `intelligence.sh` are in the parent `scripts/` directory.
3. Run:
   ```bash
   chmod +x *.sh
   ./orchestrator.sh
   ```

## Files Included (Complete Fixed Set)

- `orchestrator.sh`          ← Main entry point (v10.3)
- `lib_params.sh`            ← Clean parameter library
- `lib_venv.sh`              ← Fixed VENV module with wrappers
- `lib_docker.sh`            ← Unchanged (was already good)
- `lib_api.sh`               ← Fixed API exposure
- `intelligence.sh`          ← Fixed download/launch logic
- `operations.sh`            ← Unchanged
- `expose-api.sh`            ← Unchanged
- `links.md` & `README.md`   ← Reference docs

All scripts are now fully functional and consistent.

Enjoy your clean SGLang orchestrator! 🚀
