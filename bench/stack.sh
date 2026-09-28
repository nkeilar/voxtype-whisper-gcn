#!/bin/bash
# stack.sh <clips.txt> <old-dir> <new-dir> -- measure each speed-up stacked on the previous one.
#   A old build, whisper-cli defaults (beam 5, 30 s window)   B + -bs 1   C + -t 8
#   D + -ac <clip>   E new build (GGML_VK_GCN_TUNE=0)   F + GCN tuning
# <dir> holds whisper-cli; its libggml*/libwhisper* next to it or in <dir>/lib (e.g. build/dist/<sha>).
# 1 warm-up + RUNS runs per step (default 3); prints median/min/max and text identity vs A and E.
# Env: MODEL (default ~/.local/share/voxtype/models/ggml-small.en.bin), ICD (Vulkan driver JSON),
#      RUNS, STEPS (default "A B C D E F"), OUT (default a temp dir).
set -uo pipefail
CLIPS=${1:?clips.txt}; OLD=${2:?old build dir}; NEW=${3:?new build dir}
MODEL=${MODEL:-$HOME/.local/share/voxtype/models/ggml-small.en.bin}
RUNS=${RUNS:-3}; STEPS=${STEPS:-A B C D E F}; OUT=${OUT:-$(mktemp -d)}
[ -n "${ICD:-}" ] && export VK_ICD_FILENAMES=$ICD
echo "# $(date -u +%FT%TZ) model=$(basename "$MODEL") runs=$RUNS casting=$(command -v raytube-cast >/dev/null && raytube-cast status | cut -f1 || echo unknown) out=$OUT"
TIMEFORMAT=%R
while read -r dur wav; do
	ac=$(awk -v s="$dur" 'BEGIN { a = int(s * 50) + 128; if (a < 256) a = 256; if (a > 1500) a = 1500; print a }')
	for st in $STEPS; do
		dir=$OLD e=GGML_VK_GCN_TUNE=0 a=()
		case $st in
			B) a=(-bs 1) ;; C) a=(-bs 1 -t 8) ;; D) a=(-bs 1 -ac "$ac") ;;
			E) dir=$NEW; a=(-bs 1 -ac "$ac") ;; F) dir=$NEW e=GGML_VK_GCN_TUNE=1; a=(-bs 1 -ac "$ac") ;;
		esac
		ts=()
		for r in $(seq 0 "$RUNS"); do
			t=$( { time env $e LD_LIBRARY_PATH="$dir:$dir/lib" nice -n 10 "$dir/whisper-cli" -m "$MODEL" -f "$wav" -l en -np "${a[@]}" \
				--output-txt --output-file "$OUT/$st-$dur" > "$OUT/$st-$dur.log" 2>&1; } 2>&1 )
			[ "$r" -gt 0 ] && ts+=("$t")
		done
		same=""
		[ "$st" != A ] && { cmp -s "$OUT/A-$dur.txt" "$OUT/$st-$dur.txt" && same="=A" || same="≠A"; }
		[ "$st" = F ] && { cmp -s "$OUT/E-$dur.txt" "$OUT/F-$dur.txt" && same+=" =E" || same+=" ≠E (TUNING CHANGED TEXT)"; }
		printf '%s\n' "${ts[@]}" | sort -n | awk -v d="$dur" -v s="$st" -v x="$same" \
			'{v[NR]=$1} END {printf "%6ss  %s  median %.2fs  min %.2f  max %.2f  %s\n", d, s, v[int((NR+1)/2)], v[1], v[NR], x}'
	done
done < "$CLIPS"
