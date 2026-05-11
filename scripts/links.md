# SGLang Orchestrator - Model & Spec Update Links

This file serves as a quick-reference registry for checking if we need to update `lib_params.sh` with new models, new drafter/spec models, or updated SGLang flags.

## 🚀 Primary Models (Base)
- [Gemma 4 (Google)](https://huggingface.co/google/gemma-4-27b)
- [Qwen 3.6 (Alibaba)](https://huggingface.co/Qwen)
- [Nemotron (NVIDIA)](https://huggingface.co/nvidia)
- [Mistral (Mistral AI)](https://huggingface.co/mistralai)
- [DeepSeek (DeepSeek)](https://huggingface.co/deepseek-ai)

## 🧪 Speculative Decoding (SpecBundle/MTP)
*Check these specifically for drafter model updates.*

- **Gemma 4 MTP Drafter:** [google/gemma-4-26B-A4B-it-assistant](https://huggingface.co/google/gemma-4-26B-A4B-it-assistant)
- **Qwen 3.6 (Generic Drafter):** *TBD/Researching most efficient pair*
- **General SGLang Speculative Docs:** [SGLang Cookbook - SpecBundle](https://docs.sglang.io/cookbook/specbundle/specbundle_usage)

## 🛠️ SGLang Engine Updates
- [SGLang Official GitHub](https://github.com/sgl-project/sglang)
- [SGLang Docker Images (LMSYS)](https://hub.docker.com/r/lmsysorg/sglang)

## 🔄 Maintenance Workflow
1. Visit links above.
2. If a new model is released or a better drafter for Gemma/Qwen is found:
   - Update `scripts/modules/lib_params.sh`
   - Verify syntax with `bash -n scripts/modules/lib_params.sh`
   - Update `scripts/README.md` (if architecture changes)
3. Commit and push.
