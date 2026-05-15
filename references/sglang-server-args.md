# SGLang Server Args — Official Deployment Configs

Source: docs.sglang.io (2026-05-12)

## Power Profiles

### Conservative (🛡️)
Safe defaults, stable, leaves headroom:
- `--mem-fraction-static`: 0.90
- `--max-running-requests`: 4
- `--schedule-conservativeness`: 1.3
- `--chunked-prefill-size`: 8192
- `--max-prefill-tokens`: 8192

### Power (🔥)
Aggressive scheduling, pushes GPU limits:
- `--mem-fraction-static`: 0.95
- `--max-running-requests`: 12
- `--schedule-conservativeness`: 0.8
- `--chunked-prefill-size`: 32768
- `--max-prefill-tokens`: 16384

## Official SGLang Defaults

| Parameter | Default | Description |
|:---|:---|:---|
| `--mem-fraction-static` | **0.9** | Fraction of GPU memory for (model weights + KV cache). Lower if OOM. |
| `--schedule-policy` | **fcfs** | First-come-first-served. Use **lpm** for shared-prefix workloads (coding). |
| `--chunked-prefill-size` | **None** (disabled) | Max tokens per chunk in chunked prefill. Set to **8192** for long prompts. |
| `--max-prefill-tokens` | **16384** | Max tokens in a single prefill batch. Reduced to **8192** for safety. |
| `--max-running-requests` | **auto** | Max concurrent requests. Set explicitly for concurrency control. |
| `--max-total-tokens` | **auto** | Max tokens in KV cache pool. Auto-calculated from mem-fraction. Set explicitly for dev/debug. |
| `--schedule-conservativeness` | **1.0** | Scheduler aggressiveness. Use **1.3** to prevent overcommit. |
| `--watchdog-timeout` | **300** | Seconds before self-crash on hang. Use **120** for faster recovery. |
| Radix Cache | **enabled** | Prefix caching for repeated sequences. |
| CUDA Graph | **enabled (small BS)** | Accelerates small-batch decode. Default BS < 160-256. |
| Overlap Schedule | **enabled** | Overlaps prefill with decode. |
| `--kv-cache-dtype` | **auto** | KV cache storage dtype. bf16 or fp8_e5m2/e4m3 supported. |

## Per-Model Configs (from SGLang Deployment Guides)

### Gemma 4 (H100/H200/MI300X)
```
model-path: google/gemma-4-{E2B,E4B,31B,26B-A4B}-it
```
| Variant | TP | mem-fraction | Notes |
|:---|:---|:---|:---|
| E2B (~2B) | 1 | 0.85 (H200) | 62GB GPU: ~22GB free |
| E4B (~4B) | 1 | 0.85 (H200) | 62GB GPU: ~20GB free |
| 31B (dense) | 2 (multi-GPU) | 0.85 | B200: TP=1, mem=0.9 |
| 26B-A4B (MoE) | 1 (H200), 2 (B200 w/ MTP) | 0.85 (H200), 0.80 (MI300X) | MTP needs TP=2 |

Flags: `--reasoning-parser gemma4 --tool-call-parser gemma4`

### Qwen3.6 (H100/H200/B200)
```
model-path: Qwen/Qwen3.6-{35B-A3B,27B}[-FP8]
```
| Variant | TP | mem-fraction | Notes |
|:---|:---|:---|:---|
| 35B-A3B (MoE, FP8) | 1 | 0.8 | All hardware |
| 27B (dense, FP8) | 1 | 0.8 | All hardware |

Flags: `--reasoning-parser qwen3 --tool-call-parser qwen3_coder`
Speculative: `SGLANG_ENABLE_SPEC_V2=1` + `--speculative-algorithm EAGLE --speculative-num-steps 3 --speculative-eagle-topk 1 --speculative-num-draft-tokens 4`
Mamba: `--mamba-scheduler-strategy extra_buffer` (V2 radix cache)

## Token Usage Interpretation (from Hyperparameter Tuning docs)

From SGLang logs, look for:
```
Decode batch. #running-req: 233, #token: 370959, token usage: 0.82, cuda graph: True, gen throughput (token/s): 4594.01, #queue-req: 317
```

- **token usage > 0.9** = good utilization
- **token usage < 0.9 + #queue-req > 0** = server too conservative → lower `--schedule-conservativeness` to 0.3
- **token usage very high + "KV cache pool is full. Retract requests"** = too aggressive → raise `--schedule-conservativeness` to 1.3
- **#queue-req 100-2000** = healthy (too high increases scheduling overhead)

## Memory Tuning Rules

```
Total memory = model weights + KV cache pool + CUDA graph buffers + activations
mem_fraction_static = (model weights + KV cache pool) / GPU memory capacity

Startup logs show: available_gpu_mem=13.50 GB
  • 5-8 GB → good
  • 10-20 GB → increase mem-fraction-static (more KV cache)
  • < 5 GB → risk of OOM, decrease mem-fraction-static

Rule of thumb: reserve 5-8 GB for activations.
```

## KV Cache Math

PagedAttention only allocates slots for loaded tokens.
```
KV_cache_per_token ≈ (num_kv_heads × head_dim × 2 bytes) / sequence_length
Total KV = KV_per_token × num_slots × max_slots_per_gpu
```

MoE models with few KV heads (gemma4: 60/64 with sliding window, qwen35B-A3B: 2/128) have dramatically smaller KV cache than dense models (qwen27B: 4/32).

## Common Fixes

| Problem | Fix |
|:---|:---|
| OOM during prefill | Lower `--chunked-prefill-size` to 4096 or 2048 |
| OOM during decode | Lower `--max-running-requests` |
| General OOM | Lower `--mem-fraction-static` (0.8 or 0.7) |
| Slow prefill on long prompts | Raise `--chunked-prefill-size` to 16384 or 32768 |
| Low throughput | Raise `--schedule-conservativeness` to 0.3, increase `--mem-fraction-static` |
| KV cache thrashing | Increase `--max-total-tokens`, decrease `--schedule-conservativeness` |
| Many short requests | Use `--schedule-policy lpm` for prefix cache hits |
