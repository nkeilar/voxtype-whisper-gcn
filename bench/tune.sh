#!/bin/bash
# tune.sh <dir> <clip.wav> <label> [VAR=value ...] -- run one clip twice with per-op GPU timing
# (GGML_VK_PERF_LOGGER=1); print flash-attention / matmul / total GPU ms, encoder ms, and whether the
# text matches the first run of this clip (the reference). The kernel-shape sweep tool; with the
# experimental patch, pass GGML_VK_FA_WG=.. GGML_VK_FA_BR=.. GGML_VK_MM_WT_M=.. to try shapes.
# Env: MODEL, ICD, AC (default 625), OUT (default /tmp/whisper-gcn-tune).
set -uo pipefail
DIR=${1:?build dir}; WAV=${2:?clip}; LABEL=${3:?label}; shift 3
MODEL=${MODEL:-$HOME/.local/share/voxtype/models/ggml-small.en.bin}; AC=${AC:-625}
OUT=${OUT:-/tmp/whisper-gcn-tune}; mkdir -p "$OUT"; REF="$OUT/ref-$(basename "$WAV")-$AC.txt"
[ -n "${ICD:-}" ] && export VK_ICD_FILENAMES=$ICD
for r in 1 2; do
	env GGML_VK_PERF_LOGGER=1 LD_LIBRARY_PATH="$DIR" "$@" nice -n 10 "$DIR/whisper-cli" -m "$MODEL" -f "$WAV" -l en \
		-bs 1 -ac "$AC" --output-txt --output-file "$OUT/$LABEL" > "$OUT/$LABEL.log" 2>&1 || { echo "$LABEL CRASH (exit $?)"; exit 1; }
done
python3 - "$OUT/$LABEL.log" "$OUT/$LABEL.txt" "$REF" "$LABEL" <<'PY'
import collections, os, re, sys
log, txt, ref, label = sys.argv[1:]
d = collections.Counter()
for l in open(log):
    m = re.match(r'^([A-Z_]+)(?: [^:]*)?: (\d+) x ([\d.]+) (us|ms)', l)
    if m: d[m[1]] += float(m[3]) * (1000 if m[4] == 'ms' else 1) * int(m[2])
enc = re.search(r'encode time = +([\d.]+)', open(log).read())
t = open(txt).read().strip()
if not os.path.exists(ref): open(ref, 'w').write(t)
same = 'same text' if t == open(ref).read().strip() else 'TEXT DIFFERS: ' + t[:80]
print(f"{label:14} FA {d['FLASH_ATTN_EXT']/1e3:6.0f} ms  MUL_MAT {d['MUL_MAT']/1e3:6.0f} ms  GPU {sum(d.values())/1e3:6.0f} ms  encode {float(enc[1]) if enc else 0:6.0f} ms  {same}")
PY
