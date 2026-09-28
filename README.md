# voxtype-whisper-gcn

Fast, fully local dictation for [Voxtype](https://voxtype.io) (Omarchy's dictation tool) using
[whisper.cpp](https://github.com/ggml-org/whisper.cpp) on the GPU through Vulkan, with a small patch
that makes old AMD GCN GPUs (Radeon HD 7000 / R9 M200–M300 era) work well.

It does **not** modify Voxtype. Voxtype can hand each recording to an external `whisper-cli`
program (`[whisper] mode = "cli"`); this project provides that program, `whisper-cli-gcn`, and an
installer that points Voxtype at it. Remove it and Voxtype is exactly as before.

## Who it is for

- **Old AMD GPUs where Voxtype's built-in GPU engine gives empty or garbage text** (we hit this on a
  GCN 1.0 Radeon). Upstream whisper.cpp on Vulkan transcribes correctly there, and the patch here
  makes it faster.
- **Anyone already using Voxtype's `cli` mode**: the adapter's two decoding settings help on any
  GPU or CPU.

If Voxtype's built-in engine already works well on your machine, you probably don't need this. We
have not compared against the built-in engine on other GPUs.

## How much faster

2015 MacBook Pro, AMD R9 M370X (RADV "VERDE", GCN 1.0), model small.en, measured on real dictation
recordings. "Before" is whisper.cpp's `whisper-cli` with Voxtype's arguments and default settings.

| Recording | Before | After | |
|---|---|---|---|
| 10 s | 3.8–4.6 s | 1.4–1.8 s | ~2.6× |
| 25 s | 5.4–6.6 s | 3.0–3.7 s | ~1.8× |
| 26 recordings, 0.4–60 s, total | 131.7 s | 66.7 s | 2× |

Where it comes from:

1. **Greedy decoding** (`-bs 1`): one guess instead of five. Saves ~0.7 s on short clips.
2. **Encoder window sized to the recording** (`-ac`): whisper normally processes a full 30 s window
   even for a 3 s clip. The adapter reads the recording's length and passes
   `min(1500, max(256, seconds × 50 + 128))`. The biggest win, on any hardware.
3. **GCN kernel tuning** (`patches/0001-…`): ggml's tuning for AMD GCN only applies to GPUs with 64 KB
   of compute shared memory. GCN 1.0 on RADV reports 32 KB and gets generic kernel shapes. The patch
   gives those GPUs a better flash-attention workgroup and matrix-multiply tile: 21–40% faster
   encoding, with **word-for-word identical text** on every recording tested.

**Trade-off:** greedy decoding can change a few words or punctuation on longer recordings (median
word match with the old output was 100%, lowest 89% on a 25 s clip). Set `FAST=0` to keep the old
decoding.

**Tested on one GPU only** (RADV VERDE, GCN 1.0). Other GCN GPUs that report 32 KB of shared memory
(some Polaris cards, for example) also get the tuning, untested. The build prints
`ggml_vulkan: GCN 32 KB tuning on` when it is active.

## Install

On Omarchy, set up dictation first if you haven't (Omarchy menu → Install → AI → Dictation, or
`omarchy-voxtype-install`), and download the model you want (`voxtype setup model`; small.en is a good
balance). Then install the build tools and this project:

```bash
sudo pacman -S --needed git cmake gcc shaderc vulkan-headers spirv-headers vulkan-icd-loader vulkan-radeon python
git clone https://github.com/nkeilar/voxtype-whisper-gcn
cd voxtype-whisper-gcn
./install.sh --dry-run        # shows every step, changes nothing
./install.sh --set-voxtype    # builds (10–20 min, low priority), installs, switches Voxtype over
```

The installer never needs root. It:

1. builds whisper.cpp at the pinned commit in `UPSTREAM`, with the patch, into `build/`;
2. installs it to `~/.local/share/voxtype-whisper-gcn/<commit>/` and links `~/.local/bin/whisper-cli-gcn`;
3. writes `~/.config/voxtype-whisper-gcn/config`. On laptops with two GPUs where one is AMD, it sets
   `ICD=` so Vulkan uses the AMD GPU (otherwise it may pick the other one and fail);
4. runs one short test transcription, so the GPU shaders are compiled now and not on your first
   dictation;
5. with `--set-voxtype`: saves your current Voxtype settings, sets `[whisper] mode = "cli"` and
   `whisper_cli_path` in `~/.config/voxtype/config.toml`, and restarts `voxtype.service`.

## Use

Nothing changes: hold **F9** (or Super + Ctrl + X to toggle) and speak, as before.

Check it is being used:

```bash
voxtype transcribe some-recording.wav     # 16 kHz mono WAV; prints the text and the time taken
journalctl --user -u voxtype -n 20 | grep -E "whisper-cli backend|completed in"
```

The first line should mention `whisper-cli-gcn`, and "Transcription completed in …" shows the time.

## Settings

`~/.config/voxtype-whisper-gcn/config`, one `KEY=value` per line. Changes apply from the next
dictation, with no restart.

| Key | Default | Meaning |
|---|---|---|
| `FAST` | `1` | `0` = pass Voxtype's arguments through unchanged (five-guess decoding, 30 s window) |
| `GCN_TUNE` | `1` | `0` = don't use the GCN kernel tuning |
| `ICD` | set by installer | Vulkan driver file to use, e.g. `/usr/share/vulkan/icd.d/radeon_icd.json` |
| `ARCHIVE_DIR` | empty | if set, keep a copy of every recording and transcript there, with `log.jsonl` |
| `LOG_TIMING` | `0` | `1` = also record time taken and recording length in `log.jsonl` |

## Troubleshooting

- **Empty text, or an error about the model or the device:** Vulkan is probably using the wrong
  GPU. Set `ICD=` to your AMD driver file (`ls /usr/share/vulkan/icd.d/`).
- **The first dictation after install or a driver update is slow:** that is the one-off shader compile.
- **Different wording than before:** set `FAST=0`.
- **Anything else:** undo with `./uninstall.sh` and please open an issue with your GPU (`vulkaninfo --summary`).

## Undo

```bash
./uninstall.sh                # restores Voxtype's previous mode and whisper_cli_path, removes the install
./uninstall.sh --keep-config  # same, but keeps ~/.config/voxtype-whisper-gcn/
```

## Benchmark it yourself

[bench/README.md](bench/README.md) explains how to pick recordings, run the step-by-step comparison,
and profile the GPU. Our raw numbers are in `bench/results-2026-09-28/`.

## Licence

MIT, see [LICENSE](LICENSE). whisper.cpp and ggml are MIT; see [NOTICE](NOTICE). Voxtype is a separate
project and is not included.
