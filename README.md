# voxtype-whisper-gcn

Faster local dictation for [Voxtype](https://voxtype.io) (the Omarchy dictation
tool) with [whisper.cpp](https://github.com/ggml-org/whisper.cpp) on Vulkan, and a small kernel
tuning patch that makes old AMD GCN GPUs (Radeon HD 7000 / R9 M300 era) usable for it.

On a 2015 MacBook Pro (AMD R9 M370X, RADV "VERDE", GCN 1.0), small.en, while also casting the screen:

| Recording | Voxtype CLI today | with this | faster |
|---|---|---|---|
| 10 s | 4.6 s | 1.8 s | 2.6× |
| 25 s | 6.6 s | 3.7 s | 1.75× |

Where it comes from, each step on top of the previous one:

1. **Greedy decoding** (`-bs 1`): one hypothesis instead of five. Saves ~0.7 s on short clips.
2. **Encoder window sized to the clip** (`-ac`): whisper normally encodes a full 30 s window even for a
   3 s clip. The adapter reads the WAV length and passes `min(1500, max(256, seconds*50 + 128))`.
   The biggest win (~1.9 s), on **any** GPU or CPU.
3. **GCN kernel tuning** (the patch): ggml-vulkan's occupancy tuning for GCN keys on 64 KB of shared
   memory; GCN 1.0 on RADV reports 32 KB and falls back to generic shapes. The patch uses one
   subgroup per flash-attention workgroup (4 rows per block) and a 256-thread float matmul tile on
   those GPUs only. Encoder 21-40% faster; identical text on every clip tested.

Adding `-t 8` or a newer whisper.cpp alone made no difference on this machine.

## Who this is for

- **Anyone using Voxtype's `cli` backend**: steps 1-2 need no special hardware.
- **Old AMD GCN GPUs on RADV** with 32 KB compute shared memory: step 3. Tested on **one** chip
  (VERDE, GCN 1.0). Other GCN parts reporting 32 KB (e.g. some Polaris) also get it, untested; the
  patch logs `ggml_vulkan: GCN 32 KB tuning on` when active, and `GGML_VK_GCN_TUNE=0` turns it off.

## Install

Needs Voxtype with a model downloaded (`voxtype setup --download --model small.en`), and
`git cmake gcc shaderc vulkan-headers spirv-headers vulkan-icd-loader python`.

```bash
git clone https://github.com/<owner>/voxtype-whisper-gcn && cd voxtype-whisper-gcn
./install.sh --dry-run          # see what it does
./install.sh --set-voxtype      # build (10-20 min, low priority), install, point Voxtype at it
```

No root needed. It installs to `~/.local/share/voxtype-whisper-gcn/<commit>/`, links
`~/.local/bin/whisper-cli-gcn`, writes `~/.config/voxtype-whisper-gcn/config`, runs one warm-up
transcription (the first run compiles GPU shaders), and with `--set-voxtype` sets Voxtype's
`[whisper] mode = "cli"` and `whisper_cli_path`, saving the old values.

**Laptops with two GPUs:** Vulkan may pick the wrong one. If the installer finds two GPUs including
an AMD one, it sets `ICD=/usr/share/vulkan/icd.d/radeon_icd.json` in the config. Change it there.

## Settings (`~/.config/voxtype-whisper-gcn/config`)

| Key | Default | Meaning |
|---|---|---|
| `FAST` | 1 | 0 = pass Voxtype's arguments through unchanged (beam search, 30 s window) |
| `GCN_TUNE` | 1 | 0 = untuned kernels (same as upstream) |
| `ICD` | (auto) | Vulkan driver JSON to force |
| `ARCHIVE_DIR` | (empty) | keep every recording + transcript there, with `log.jsonl` |
| `LOG_TIMING` | 0 | add `elapsed_ms`, `audio_s`, `profile`, `args` to `log.jsonl` |

**Trade-off:** greedy decoding can change wording on longer clips (a few words and punctuation on a
25 s clip in our tests; short clips were identical). `FAST=0` goes back to beam search.

## Undo

`./uninstall.sh` restores Voxtype's previous `mode` and `whisper_cli_path`, and removes the install.
Lighter switches: `FAST=0` or `GCN_TUNE=0` in the config (no restart needed).

## Benchmark it yourself

See [bench/README.md](bench/README.md): pick recordings, run the stacked comparison, profile the GPU.

## Licence

MIT ([LICENSE](LICENSE)). whisper.cpp and ggml are MIT; see [NOTICE](NOTICE).
