# 0002. Local inference via MLX with a residency cache

Date: 2026-08-11

## Status

Accepted

## Context

bulletproof's local-model story was download-only: the catalog, downloader,
and on-disk Hugging Face snapshot layout existed, but LocalModelEngine was a
stub. Users on Macs without Apple Intelligence (or who prefer an open model)
had no working engine. The snapshot layout was chosen in advance to match
what MLX loads natively, so inference was the remaining piece.

Constraints that shaped the design: a 4-bit 4B model occupies ~2.5-3.5 GB of
unified memory when loaded and takes seconds to load; the Services and hotkey
paths budget 55 seconds end to end; proofreading is a stateless, bursty
workload (a few requests in quick succession, then nothing for hours).

## Decision

**Runtime: mlx-swift-lm (MLXLLM/MLXLMCommon/MLXHuggingFace).** Apple's ML
research runtime for Apple silicon - MIT licensed, Swift-native, loads our
snapshot directories as-is via `loadContainer(from:using:)` with the
`#huggingFaceTokenizerLoader()` macro (chat templates applied automatically).
The catalog is deliberately restricted to architectures this runtime can load
(qwen3, gemma3 today); better models that MLX cannot load yet (Gemma 4,
Qwen3.5) stay out of the catalog rather than becoming un-runnable downloads.

**Residency: keep the loaded model warm, evict on idle.** A generic
`ResidencyCache` actor holds at most one loaded ModelContainer: the first
request pays the load (visible via the menu bar activity pulse), subsequent
requests are fast, and the model is freed after 5 idle minutes, when the
engine choice changes, or when its files are deleted. Single-flight loading
means concurrent requests share one load; failed loads cache nothing so a
corrupt download surfaces an actionable error on every attempt until
re-downloaded. The generic core is unit-tested with fake loaders; MLX only
appears in the one production specialization.

**Generation: fresh ChatSession per request, no guided output.** Proofreading
is stateless (same reasoning as the Apple Intelligence engine's
session-per-request). MLX has no constrained decoding, so output shaping
relies on the shared ProofreadPrompt (instructions + few-shot examples +
<text> markers) and cleanResponse - the mechanism already validated against
adversarial inputs. Temperature 0 for deterministic corrections; maxTokens
proportional to input (2x + slack, clamped) so a runaway generation cannot
exhaust the 55-second budget; KV cache bounded at 4096.

## Consequences

- Downloaded models actually proofread; Macs without Apple Intelligence have
  a working engine for the first time.
- ~3 GB of unified memory is held while a local model is resident - the idle
  eviction and engine-switch eviction keep this bounded, but users on 8 GB
  machines will feel the pressure while it's loaded.
- First request after switching or idling pays a multi-second load; the
  activity indicator covers it and settings copy explains it.
- MLX compiles Metal kernels from source: builds require the Metal toolchain
  component (CI installs it per run) and -skipPackagePluginValidation; the
  release ships arm64-only in practice since MLX is Apple-silicon-only.
- Output quality is prompt-shaped, not grammar-constrained - the gated
  integration test suite (runs only where the model is installed) guards the
  adversarial cases; model-quality regressions surface there, not in CI.
