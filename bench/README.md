# Benchmarking

All runs are offline: they replay saved 16 kHz mono recordings through `whisper-cli`. Nothing is
recorded from the microphone. Run on a quiet machine, or note what else is using the GPU (the
scripts print whether a screen cast is running if `raytube-cast` exists), and compare builds under
the same conditions.

```bash
# 1. pick recordings near these lengths (Voxtype users: the library if you keep one)
bench/clips.sh ~/recordings 1 3 6 10 15 25 45 > bench/clips.txt
# 2. stacked comparison: old = your current whisper-cli dir, new = build/dist/<sha>
ICD=/usr/share/vulkan/icd.d/radeon_icd.json bench/stack.sh bench/clips.txt /path/to/old build/dist/$(cat UPSTREAM)
# 3. per-kernel GPU time for one clip (sweeps need patches/experimental-env-overrides.patch)
bench/tune.sh build/dist/$(cat UPSTREAM) clip.wav default
```

`stack.sh` steps: A old build defaults, B `-bs 1`, C `-t 8`, D `-ac`, E new build untuned
(`GGML_VK_GCN_TUNE=0`), F tuned. It prints median/min/max over `RUNS` (3) after a warm-up, and whether
the text matches A, and for F whether it matches E. **F must equal E**: tuning must never change text.

Deeper profiling:

- Per-op GPU time: `GGML_VK_PERF_LOGGER=1 whisper-cli ...`
- GPU ISA, registers, waves: `RADV_DEBUG=shaders,shaderstats MESA_SHADER_CACHE_DISABLE=1 whisper-cli ... 2> isa.txt`
- CPU: `perf record -g whisper-cli ...; perf report`

Our results (2026-09-28, MacBookPro11,5) are in `results-2026-09-28/`.
