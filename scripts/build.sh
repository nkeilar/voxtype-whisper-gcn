#!/bin/bash
# build.sh -- fetch whisper.cpp at the pinned commit (UPSTREAM), apply patches/*.patch,
# and build whisper-cli + whisper-server with Vulkan into build/.
#
#   scripts/build.sh [--jobs N]      default: 2 jobs at nice 19 (safe while you work)
#
# Needs: git cmake gcc shaderc vulkan-headers spirv-headers vulkan-icd-loader
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
JOBS=2
[ "${1:-}" = "--jobs" ] && JOBS=${2:?}
SHA=$(tr -d '[:space:]' < "$ROOT/UPSTREAM")
SRC="$ROOT/build/whisper.cpp"
for t in git cmake glslc; do command -v $t >/dev/null || { echo "missing: $t" >&2; exit 1; }; done
if [ ! -d "$SRC/.git" ]; then
	git clone --quiet --filter=blob:none https://github.com/ggml-org/whisper.cpp.git "$SRC"
fi
git -C "$SRC" fetch --quiet origin "$SHA" 2>/dev/null || true
git -C "$SRC" checkout --quiet --force "$SHA"
git -C "$SRC" clean -fdq -e build-vk
for p in "$ROOT"/patches/[0-9]*.patch; do
	[ -e "$p" ] || continue
	git -C "$SRC" apply --check "$p" && git -C "$SRC" apply "$p" && echo "applied $(basename "$p")"
done
nice -n 19 cmake -S "$SRC" -B "$SRC/build-vk" -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release \
	-DWHISPER_SDL2=OFF -DWHISPER_BUILD_TESTS=OFF > "$ROOT/build/cmake.log"
nice -n 19 cmake --build "$SRC/build-vk" -j"$JOBS" --target whisper-cli whisper-server > "$ROOT/build/build.log"
OUT="$ROOT/build/dist/$SHA"; rm -rf "$OUT"; mkdir -p "$OUT"
cp -a "$SRC"/build-vk/bin/whisper-cli "$SRC"/build-vk/bin/whisper-server "$SRC"/build-vk/bin/lib*.so* "$OUT"/
echo "$SHA $(cd "$ROOT" && git rev-parse --short HEAD 2>/dev/null || echo nogit) $(date -u +%FT%TZ)" > "$OUT/BUILD_INFO"
echo "built: $OUT"
