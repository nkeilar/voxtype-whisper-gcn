#!/bin/bash
# clips.sh <folder-of-wavs> [seconds ...] -- pick one 16 kHz mono recording closest to each length.
# Prints "<seconds> <path>" lines; save them as clips.txt for stack.sh / tune.sh.
#   bench/clips.sh ~/.local/share/voxtype/library 1 3 6 10 15 25 45 > bench/clips.txt
set -euo pipefail
DIR=${1:?folder of .wav recordings}; shift
[ $# -gt 0 ] || set -- 3 6 10 15 25 45
python3 - "$DIR" "$@" <<'PY'
import glob, os, sys, wave
d, want = sys.argv[1], [float(x) for x in sys.argv[2:]]
clips = []
for f in glob.glob(os.path.join(d, '**', '*.wav'), recursive=True):
    try:
        w = wave.open(f)
        if w.getframerate() == 16000 and w.getnchannels() == 1: clips.append((w.getnframes() / 16000, f))
    except Exception: pass
if not clips: sys.exit("no 16 kHz mono .wav files in " + d)
for t in want:
    s, f = min(clips, key=lambda c: abs(c[0] - t)); print(f"{s:.1f} {f}")
PY
