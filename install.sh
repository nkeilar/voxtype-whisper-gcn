#!/bin/bash
# install.sh -- install the tuned whisper.cpp + whisper-cli-gcn adapter for the current user.
#
#   ./install.sh [--dry-run] [--no-build] [--set-voxtype]
#
#   --dry-run      show every action, change nothing
#   --no-build     use an existing build/dist/<sha> instead of building
#   --set-voxtype  point Voxtype at the adapter (whisper.mode = "cli", whisper_cli_path) and
#                  restart voxtype.service; the old values are saved for ./uninstall.sh
#
# Needs no root. Installs to ~/.local/share/voxtype-whisper-gcn/<sha>/ and links
# ~/.local/bin/whisper-cli-gcn. Your config lives in ~/.config/voxtype-whisper-gcn/config.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DRY=0 BUILD=1 SET_VOXTYPE=0
for a in "$@"; do
	case "$a" in
		--dry-run) DRY=1 ;; --no-build) BUILD=0 ;; --set-voxtype) SET_VOXTYPE=1 ;;
		*) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
	esac
done
SHA=$(tr -d '[:space:]' < "$ROOT/UPSTREAM")
DIST="$ROOT/build/dist/$SHA"
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}/voxtype-whisper-gcn"
DEST="$SHARE/$SHA"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype-whisper-gcn"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/voxtype-whisper-gcn"
VOX="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml"
say() { printf '\033[1m%s\033[0m\n' "$*"; }
do_() { local what=$1; shift; if (( DRY )); then echo "  would: $what"; else echo "  $what"; "$@"; fi; }

say "1. Build"
if (( BUILD )) && [[ ! -x "$DIST/whisper-cli" ]]; then
	do_ "build whisper.cpp $SHA with patches (10-20 min, low priority)" "$ROOT/scripts/build.sh"
elif [[ -x "$DIST/whisper-cli" ]]; then
	echo "  using $DIST"
else
	echo "  no build at $DIST; run scripts/build.sh or drop --no-build" >&2; exit 1
fi

say "2. Install to $DEST"
do_ "copy binaries and libraries" sh -c "mkdir -p '$DEST' && cp -a '$DIST'/. '$DEST'/ && install -m755 '$ROOT/whisper-cli-gcn' '$DEST/whisper-cli-gcn'"
do_ "link $SHARE/current -> $SHA" ln -sfn "$SHA" "$SHARE/current"
do_ "link ~/.local/bin/whisper-cli-gcn" sh -c "mkdir -p '$HOME/.local/bin' && ln -sfn '$SHARE/current/whisper-cli-gcn' '$HOME/.local/bin/whisper-cli-gcn'"

say "3. Settings ($CONF_DIR/config)"
if [[ -f "$CONF_DIR/config" ]]; then
	echo "  keeping your existing config"
else
	icd=""
	# Two GPUs and one of them AMD: force RADV, or Vulkan may run whisper on the other GPU.
	if [[ -f /usr/share/vulkan/icd.d/radeon_icd.json ]] && (( $(ls /usr/share/vulkan/icd.d/*.json 2>/dev/null | wc -l) > 1 )) &&
		grep -qx 0x1002 /sys/class/drm/card*/device/vendor 2>/dev/null; then
		icd=/usr/share/vulkan/icd.d/radeon_icd.json
		echo "  two GPUs found; whisper will use the AMD one (ICD=$icd)"
	fi
	do_ "write default config" sh -c "mkdir -p '$CONF_DIR' && printf '%s\n' \
		'# voxtype-whisper-gcn settings, KEY=value (explained at the top of whisper-cli-gcn)' \
		'FAST=1' 'GCN_TUNE=1' 'ICD=$icd' 'ARCHIVE_DIR=' 'LOG_TIMING=0' > '$CONF_DIR/config'"
fi

say "4. Warm-up (compiles the GPU shaders once, so the first dictation is not slow)"
# The model Voxtype is set to use (name like small.en, or an absolute path)
MODEL=$(voxtype config get whisper.model 2>/dev/null | tr -d '"[:space:]' || true)
[[ -n "$MODEL" && "$MODEL" != /* ]] && MODEL="$HOME/.local/share/voxtype/models/ggml-$MODEL.bin"
[[ -f "$MODEL" ]] || MODEL=$(ls "$HOME"/.local/share/voxtype/models/ggml-*.bin 2>/dev/null | head -1 || true)
if [[ -n "$MODEL" ]]; then
	WARM=$(mktemp --suffix=.wav)
	python3 -c "
import wave,random,sys
w=wave.open(sys.argv[1],'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
w.writeframes(b''.join(random.randint(-200,200).to_bytes(2,'little',signed=True) for _ in range(32000)))" "$WARM"
	do_ "transcribe 2 s of noise with $(basename "$MODEL")" sh -c "'$DEST/whisper-cli-gcn' -m '$MODEL' -f '$WARM' -l en -np > /dev/null 2>&1 || true"
	rm -f "$WARM"
else
	echo "  no Voxtype model found yet; skipped (download one with: voxtype setup --download --model small.en)"
fi

say "5. Voxtype"
if (( SET_VOXTYPE )); then
	[[ -f "$VOX" ]] || { echo "  no $VOX; run voxtype once first" >&2; exit 1; }
	do_ "save current whisper settings to $STATE/previous" sh -c "mkdir -p '$STATE' && cp -a '$VOX' '$STATE/config.toml.before' && \
		{ echo \"mode=\$(voxtype config get whisper.mode 2>/dev/null)\"; grep -E '^whisper_cli_path *=' '$VOX' || echo 'whisper_cli_path='; } > '$STATE/previous'"
	do_ "set whisper.mode = cli and whisper_cli_path = ~/.local/bin/whisper-cli-gcn" python3 - "$VOX" "$HOME/.local/bin/whisper-cli-gcn" <<'PY'
import re, sys
p, path = sys.argv[1:]; s = open(p).read()
line = f'whisper_cli_path = "{path}"'
m = re.search(r'(?ms)^\[whisper\]\n(.*?)(?=^\[|\Z)', s)
if not m: sys.exit("no [whisper] section in " + p)
body = m.group(1)
body = re.sub(r'(?m)^whisper_cli_path *=.*$', line, body) if re.search(r'(?m)^whisper_cli_path *=', body) else body.rstrip('\n') + '\n' + line + '\n\n'
body = re.sub(r'(?m)^mode *= *"[a-z]+"', 'mode = "cli"', body) if re.search(r'(?m)^mode *=', body) else body.rstrip('\n') + '\nmode = "cli"\n\n'
open(p, 'w').write(s[:m.start(1)] + body + s[m.end(1):])
PY
	do_ "restart voxtype.service" systemctl --user restart voxtype.service
else
	echo "  not changed. To use it, rerun with --set-voxtype, or set in $VOX under [whisper]:"
	echo "      mode = \"cli\""
	echo "      whisper_cli_path = \"$HOME/.local/bin/whisper-cli-gcn\""
fi
say "Done. Test: hold your dictation key and speak; ./uninstall.sh undoes this."
