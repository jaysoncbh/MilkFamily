#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-release}"
case "$mode" in
  release|user) configurations=(release) ;;
  debug|test) configurations=(debug) ;;
  all) configurations=(debug release) ;;
  *) echo 'Usage: scripts/build.sh [release|debug|all]' >&2; exit 2 ;;
esac
assets="${NAIJIA_ASSET_ROOT:-$repo_dir/Resources}"
assets="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$assets")"
if [[ ! -f "$assets/运行资源清单.json" ]]; then
  echo 'Set NAIJIA_ASSET_ROOT to an authorized runtime asset directory. See docs/BUILD.md.' >&2
  exit 2
fi
# Compile a clean source copy outside user/synced folders. Swift's debug runtime
# diagnostics can retain source paths even when DWARF prefix mapping is enabled.
build_root="$(mktemp -d /tmp/milk-family-build.XXXXXX)"
trap 'rm -rf "$build_root"' EXIT
python3 - "$repo_dir/macOS" "$build_root/macOS" <<'PY'
import shutil
import sys
shutil.copytree(sys.argv[1], sys.argv[2], ignore=shutil.ignore_patterns('.build', '.swiftpm', '__pycache__', '.DS_Store'))
PY
for configuration in "${configurations[@]}"; do
  swift build --package-path "$build_root/macOS" -c "$configuration" --product Naijia
  binary_dir="$(swift build --package-path "$build_root/macOS" -c "$configuration" --show-bin-path)"
  python3 "$repo_dir/scripts/package.py" --executable "$binary_dir/Naijia" \
    --assets "$assets" --configuration "$configuration"
done
