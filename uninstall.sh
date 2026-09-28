#!/bin/bash
# uninstall.sh -- undo install.sh: restore Voxtype's previous whisper settings (if --set-voxtype
# was used), remove ~/.local/bin/whisper-cli-gcn and the installed builds.
#
#   ./uninstall.sh [--dry-run] [--keep-config]
set -uo pipefail
DRY=0 KEEP=0
for a in "$@"; do case "$a" in --dry-run) DRY=1 ;; --keep-config) KEEP=1 ;; *) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac; done
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}/voxtype-whisper-gcn"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype-whisper-gcn"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/voxtype-whisper-gcn"
VOX="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml"
do_() { local what=$1; shift; if (( DRY )); then echo "  would: $what"; else echo "  $what"; "$@"; fi; }

if [[ -f "$STATE/previous" && -f "$VOX" ]]; then
	mode=$(sed -n 's/^mode=//p' "$STATE/previous")
	path_line=$(grep -E '^whisper_cli_path' "$STATE/previous")
	do_ "restore Voxtype whisper.mode=${mode:-unchanged} and ${path_line}" python3 - "$VOX" "${mode:-}" "$path_line" <<'PY'
import re, sys
p, mode, line = sys.argv[1:]; s = open(p).read()
m = re.search(r'(?ms)^\[whisper\]\n(.*?)(?=^\[|\Z)', s); body = m.group(1)
if line.strip() == 'whisper_cli_path=':
    body = re.sub(r'(?m)^whisper_cli_path *=.*\n', '', body)
else:
    body = re.sub(r'(?m)^whisper_cli_path *=.*$', lambda _: line, body)
if mode:
    if re.fullmatch(r'[a-z]+', mode):
        body = re.sub(r'(?m)^mode *= *"[a-z]+"', f'mode = "{mode}"', body)
open(p, 'w').write(s[:m.start(1)] + body + s[m.end(1):])
PY
	do_ "restart voxtype.service" systemctl --user restart voxtype.service
fi
[[ "$(readlink "$HOME/.local/bin/whisper-cli-gcn")" == "$SHARE/current/whisper-cli-gcn" ]] &&
	do_ "remove ~/.local/bin/whisper-cli-gcn" rm "$HOME/.local/bin/whisper-cli-gcn"
[[ -d "$SHARE" ]] && do_ "remove $SHARE" rm -rf "$SHARE"
(( KEEP )) || { [[ -d "$CONF_DIR" ]] && do_ "remove $CONF_DIR" rm -rf "$CONF_DIR"; }
[[ -d "$STATE" ]] && do_ "remove $STATE" rm -rf "$STATE"
echo "Done."
